#import "TSVideoEngine.h"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/opt.h>
#include <libavutil/time.h>
#include <libavutil/pixdesc.h>

// No global job state: contexts belong to a single invocation. Conversion is
// serialized by the engine semaphore, and waiting jobs remain cancellable.
static int interrupted(void *opaque) {
    return [(__bridge id<BackendVideoObserver>)opaque cancelled] ? 1 : 0;
}
// Compatible MP4 is copied byte-for-byte, then demuxed locally before success.
// This avoids a muxing pass without trusting HTTP success or content length alone.
static int copyCompatibleMP4(NSString *url, NSString *headers, NSString *path, id<BackendVideoObserver> observer) {
    AVIOContext *source = NULL, *destination = NULL;
    AVFormatContext *validation = NULL;
    AVPacket *packet = NULL;
    AVDictionary *options = NULL;
    AVIOInterruptCB interrupt = {interrupted, (__bridge void *)observer};
    int result = 0;
    int64_t bytes = 0, expected = -1, started = av_gettime_relative(), reported = started, end = 0, packets = 0;
    uint8_t buffer[65536];
    av_dict_set(&options, "headers", headers.UTF8String, 0);
    av_dict_set(&options, "tls_verify", "1", 0);
    av_dict_set(&options, "rw_timeout", "30000000", 0);
    av_dict_set(&options, "protocol_whitelist", "http,https,tcp,tls", 0);
    if ((result = avio_open2(&source, url.UTF8String, AVIO_FLAG_READ, &interrupt, &options)) < 0) goto done;
    expected = avio_size(source);
    if ((result = avio_open2(&destination, path.UTF8String, AVIO_FLAG_WRITE, &interrupt, NULL)) < 0) goto done;
    while ((result = avio_read(source, buffer, sizeof(buffer))) > 0) {
        if ([observer cancelled]) { result = AVERROR_EXIT; goto done; }
        avio_write(destination, buffer, result);
        if (destination->error < 0) { result = destination->error; goto done; }
        bytes += result;
        int64_t now = av_gettime_relative();
        if (now - reported >= 500000) {
            [observer progress:expected > 0 ? MIN(.99, (double)bytes / expected) : 0 bytes:bytes bytesPerSecond:bytes * 1000000.0 / MAX(1, now - started)];
            reported = now;
        }
    }
    if (result != AVERROR_EOF || (expected >= 0 && bytes != expected)) { if (result == AVERROR_EOF) result = AVERROR_INVALIDDATA; goto done; }
    if ((result = avio_closep(&destination)) < 0) goto done;
    validation = avformat_alloc_context();
    if (!validation) { result = AVERROR(ENOMEM); goto done; }
    validation->interrupt_callback = interrupt;
    if ((result = avformat_open_input(&validation, path.UTF8String, NULL, NULL)) < 0) goto done;
    if ((result = avformat_find_stream_info(validation, NULL)) < 0) goto done;
    packet = av_packet_alloc();
    if (!packet) { result = AVERROR(ENOMEM); goto done; }
    while ((result = av_read_frame(validation, packet)) >= 0) {
        if ([observer cancelled]) { result = AVERROR_EXIT; goto done; }
        if (av_packet_get_side_data(packet, AV_PKT_DATA_ENCRYPTION_INFO, NULL)) { result = AVERROR(ENOTSUP); goto done; }
        if (packet->flags & AV_PKT_FLAG_CORRUPT) { result = AVERROR_INVALIDDATA; goto done; }
        AVStream *stream = validation->streams[packet->stream_index];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) packets++;
        if (packet->pts != AV_NOPTS_VALUE) end = MAX(end, av_rescale_q(packet->pts + MAX(0,packet->duration), stream->time_base, AV_TIME_BASE_Q) - (validation->start_time == AV_NOPTS_VALUE ? 0 : validation->start_time));
        av_packet_unref(packet);
    }
    if (result == AVERROR_EOF) result = packets && (validation->duration <= 0 || end + 500000 >= validation->duration) ? 0 : AVERROR_INVALIDDATA;
done:
    av_dict_free(&options);
    avio_closep(&source);
    if (destination) { int closed = avio_closep(&destination); if (result >= 0 && closed < 0) result = closed; }
    av_packet_free(&packet);
    avformat_close_input(&validation);
    return result;
}

typedef struct {
    AVStream *input, *output;
    AVCodecContext *decoder, *encoder;
    AVFilterGraph *graph;
    AVFilterContext *source, *sink;
    int64_t packets;
} TSTrack;
static void freeTrack(TSTrack *track) {
    avfilter_graph_free(&track->graph);
    avcodec_free_context(&track->decoder);
    avcodec_free_context(&track->encoder);
}
static int writeEncoded(TSTrack *track, AVFormatContext *output, AVFrame *frame) {
    int result = avcodec_send_frame(track->encoder, frame);
    if (result < 0) return result;
    AVPacket *packet = av_packet_alloc();
    if (!packet) return AVERROR(ENOMEM);
    while ((result = avcodec_receive_packet(track->encoder, packet)) >= 0) {
        av_packet_rescale_ts(packet, track->encoder->time_base, track->output->time_base);
        packet->stream_index = track->output->index;
        result = av_interleaved_write_frame(output, packet);
        av_packet_unref(packet);
        if (result < 0) break;
        track->packets++;
    }
    av_packet_free(&packet);
    return result == AVERROR(EAGAIN) || result == AVERROR_EOF ? 0 : result;
}
static int filterFrame(TSTrack *track, AVFormatContext *output, AVFrame *frame) {
    int result = av_buffersrc_add_frame_flags(track->source, frame, AV_BUFFERSRC_FLAG_KEEP_REF);
    if (result < 0) return result;
    AVFrame *filtered = av_frame_alloc();
    if (!filtered) return AVERROR(ENOMEM);
    while ((result = av_buffersink_get_frame(track->sink, filtered)) >= 0) {
        filtered->pts = av_rescale_q(filtered->pts, av_buffersink_get_time_base(track->sink), track->encoder->time_base);
        filtered->pict_type = AV_PICTURE_TYPE_NONE;
        result = writeEncoded(track, output, filtered);
        av_frame_unref(filtered);
        if (result < 0) break;
    }
    av_frame_free(&filtered);
    return result == AVERROR(EAGAIN) || result == AVERROR_EOF ? 0 : result;
}
static int decodePacket(TSTrack *track, AVFormatContext *output, AVPacket *packet) {
    int result = avcodec_send_packet(track->decoder, packet);
    if (result < 0) return result;
    AVFrame *frame = av_frame_alloc();
    if (!frame) return AVERROR(ENOMEM);
    while ((result = avcodec_receive_frame(track->decoder, frame)) >= 0) {
        frame->pts = frame->best_effort_timestamp;
        result = filterFrame(track, output, frame);
        av_frame_unref(frame);
        if (result < 0) break;
    }
    av_frame_free(&frame);
    return result == AVERROR(EAGAIN) || result == AVERROR_EOF ? 0 : result;
}
static int configureTrack(TSTrack *track, AVFormatContext *input, AVFormatContext *output) {
    AVCodecParameters *parameters = track->input->codecpar;
    track->output = avformat_new_stream(output, NULL);
    if (!track->output) return AVERROR(ENOMEM);
    BOOL video = parameters->codec_type == AVMEDIA_TYPE_VIDEO;
    BOOL copy = video ? (parameters->codec_id == AV_CODEC_ID_H264 || parameters->codec_id == AV_CODEC_ID_HEVC)
                      : parameters->codec_id == AV_CODEC_ID_AAC;
    if (copy) {
        int result = avcodec_parameters_copy(track->output->codecpar, parameters);
        track->output->codecpar->codec_tag = 0;
        track->output->time_base = track->input->time_base;
        return result;
    }
    const AVCodec *decoder = avcodec_find_decoder(parameters->codec_id);
    const AVCodec *encoder = avcodec_find_encoder_by_name(video ? "h264_videotoolbox" : "aac");
    if (!decoder || !encoder) return AVERROR_ENCODER_NOT_FOUND;
    track->decoder = avcodec_alloc_context3(decoder);
    track->encoder = avcodec_alloc_context3(encoder);
    if (!track->decoder || !track->encoder) return AVERROR(ENOMEM);
    int result = avcodec_parameters_to_context(track->decoder, parameters);
    if (result < 0) return result;
    track->decoder->pkt_timebase = track->input->time_base;
    if ((result = avcodec_open2(track->decoder, decoder, NULL)) < 0) return result;
    AVCodecContext *enc = track->encoder, *dec = track->decoder;
    if (video) {
        enc->width = dec->width; enc->height = dec->height;
        enc->sample_aspect_ratio = dec->sample_aspect_ratio;
        enc->pix_fmt = AV_PIX_FMT_YUV420P;
        enc->framerate = av_guess_frame_rate(input, track->input, NULL);
        if (enc->framerate.num == 0) enc->framerate = (AVRational){30, 1};
        enc->time_base = av_inv_q(enc->framerate);
        enc->bit_rate = MAX(2000000, dec->bit_rate);
        enc->max_b_frames = 0;
    } else {
        enc->sample_rate = 48000;
        enc->sample_fmt = AV_SAMPLE_FMT_FLTP;
        av_channel_layout_default(&enc->ch_layout, 2);
        enc->time_base = (AVRational){1, enc->sample_rate};
        enc->bit_rate = 160000;
    }
    if (output->oformat->flags & AVFMT_GLOBALHEADER) enc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    if ((result = avcodec_open2(enc, encoder, NULL)) < 0) return result;
    if ((result = avcodec_parameters_from_context(track->output->codecpar, enc)) < 0) return result;
    track->output->time_base = enc->time_base;
    track->graph = avfilter_graph_alloc();
    if (!track->graph) return AVERROR(ENOMEM);
    char args[1024];
    if (video) {
        AVRational sar = dec->sample_aspect_ratio;
        if (!sar.num) sar = (AVRational){1,1};
        snprintf(args, sizeof(args), "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d", dec->width, dec->height, dec->pix_fmt, track->input->time_base.num, track->input->time_base.den, sar.num, sar.den);
    } else {
        char layout[128]; av_channel_layout_describe(&dec->ch_layout, layout, sizeof(layout));
        snprintf(args, sizeof(args), "time_base=%d/%d:sample_rate=%d:sample_fmt=%s:channel_layout=%s", track->input->time_base.num, track->input->time_base.den, dec->sample_rate, av_get_sample_fmt_name(dec->sample_fmt), layout);
    }
    result = avfilter_graph_create_filter(&track->source, avfilter_get_by_name(video ? "buffer" : "abuffer"), "in", args, NULL, track->graph);
    if (result < 0) return result;
    result = avfilter_graph_create_filter(&track->sink, avfilter_get_by_name(video ? "buffersink" : "abuffersink"), "out", NULL, NULL, track->graph);
    if (result < 0) return result;
    AVFilterInOut *outputs = avfilter_inout_alloc(), *inputs = avfilter_inout_alloc();
    if (!outputs || !inputs) { avfilter_inout_free(&outputs); avfilter_inout_free(&inputs); return AVERROR(ENOMEM); }
    outputs->name = av_strdup("in"); outputs->filter_ctx = track->source; outputs->pad_idx = 0;
    inputs->name = av_strdup("out"); inputs->filter_ctx = track->sink; inputs->pad_idx = 0;
    result = avfilter_graph_parse_ptr(track->graph, video ? "format=pix_fmts=yuv420p" : "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo", &inputs, &outputs, NULL);
    avfilter_inout_free(&inputs); avfilter_inout_free(&outputs);
    if (result < 0) return result;
    if ((result = avfilter_graph_config(track->graph, NULL)) < 0) return result;
    if (!video) av_buffersink_set_frame_size(track->sink, enc->frame_size);
    return 0;
}

@implementation TSVideoEngine {
    dispatch_semaphore_t _slot;
}
- (instancetype)init { if ((self = [super init])) _slot = dispatch_semaphore_create(1); return self; }
- (BOOL)process:(NSString *)url headersJSON:(NSString *)headersJSON outputPath:(NSString *)outputPath observer:(id<BackendVideoObserver>)observer error:(NSError **)error {
    while (dispatch_semaphore_wait(_slot, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC))) {
        if ([observer cancelled]) { if (error) *error = [NSError errorWithDomain:@"TsunaguVideo" code:AVERROR_EXIT userInfo:nil]; return NO; }
    }
    int result = 0;
    NSString *failureReason = nil, *requestHeaders = nil;
    AVFormatContext *input = avformat_alloc_context(), *output = NULL;
    AVPacket *packet = NULL;
    AVDictionary *options = NULL;
    TSTrack tracks[2] = {0};
    if (!input) { result = AVERROR(ENOMEM); goto finish; }
    input->interrupt_callback = (AVIOInterruptCB){interrupted, (__bridge void *)observer};
    {
        NSData *data = [headersJSON dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *headers = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![headers isKindOfClass:NSDictionary.class]) { result = AVERROR(EINVAL); goto finish; }
        NSMutableString *text = [NSMutableString stringWithString:@"Accept-Encoding: identity\r\n"];
        for (NSString *key in headers) {
            NSString *value = headers[key];
            if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class] ||
                [key rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound ||
                [value rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) { result = AVERROR(EINVAL); goto finish; }
            if ([key caseInsensitiveCompare:@"accept-encoding"] != NSOrderedSame) [text appendFormat:@"%@: %@\r\n", key, value];
        }
        requestHeaders = [text copy];
        av_dict_set(&options, "headers", text.UTF8String, 0);
        av_dict_set(&options, "rw_timeout", "30000000", 0);
        av_dict_set(&options, "protocol_whitelist", "http,https,tcp,tls,crypto,data", 0);
        av_dict_set(&options, "allowed_extensions", "ALL", 0);
        av_dict_set(&options, "allowed_segment_extensions", "ALL", 0);
        av_dict_set(&options, "tls_verify", "1", 0);
    }
    if ((result = avformat_open_input(&input, url.UTF8String, NULL, &options)) < 0) goto finish;
    av_dict_free(&options);
    // HLS/DASH advertise a finite duration in their manifest. Reject live
    // manifests before stream probing, which could otherwise wait indefinitely.
    if (input->duration == AV_NOPTS_VALUE && (strstr(input->iformat->name, "hls") || strstr(input->iformat->name, "dash"))) { failureReason = @"Unbounded live streams cannot be downloaded; a finite HLS or DASH manifest is required."; result = AVERROR(ENOTSUP); goto finish; }
    if ((result = avformat_find_stream_info(input, NULL)) < 0) goto finish;
    if (strstr(input->iformat->name, "mov")) {
        BOOL compatible = YES, video = NO;
        for (unsigned i = 0; i < input->nb_streams; i++) {
            AVCodecParameters *codec = input->streams[i]->codecpar;
            if (av_packet_side_data_get(codec->coded_side_data, codec->nb_coded_side_data, AV_PKT_DATA_ENCRYPTION_INIT_INFO)) { compatible = NO; break; }
            if (codec->codec_type == AVMEDIA_TYPE_VIDEO) {
                video = YES;
                compatible = compatible && (codec->codec_id == AV_CODEC_ID_H264 || codec->codec_id == AV_CODEC_ID_HEVC);
            } else if (codec->codec_type == AVMEDIA_TYPE_AUDIO) compatible = compatible && codec->codec_id == AV_CODEC_ID_AAC;
            else compatible = NO;
        }
        if (compatible && video) {
            avformat_close_input(&input);
            result = copyCompatibleMP4(url, requestHeaders, outputPath, observer);
            if (result == AVERROR(ENOTSUP)) failureReason = @"DRM/CENC encrypted tracks are unsupported.";
            goto finish;
        }
    }
    if ((result = avformat_alloc_output_context2(&output, NULL, "mp4", outputPath.UTF8String)) < 0) goto finish;
    output->interrupt_callback = input->interrupt_callback;
    for (unsigned i = 0; i < input->nb_streams; i++) {
        AVStream *stream = input->streams[i];
        if (av_packet_side_data_get(stream->codecpar->coded_side_data, stream->codecpar->nb_coded_side_data, AV_PKT_DATA_ENCRYPTION_INIT_INFO)) {
            failureReason = @"DRM/CENC encrypted tracks are unsupported. Only ordinary AES-128 HLS encryption is supported.";
            result = AVERROR(ENOTSUP); goto finish;
        }
        int slot = stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO ? 0 : stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO ? 1 : -1;
        if (slot < 0 || tracks[slot].input) continue;
        tracks[slot].input = stream;
        if ((result = configureTrack(&tracks[slot], input, output)) < 0) goto finish;
    }
    if (!tracks[0].input) { result = AVERROR_STREAM_NOT_FOUND; goto finish; }
    if ((result = avio_open2(&output->pb, outputPath.UTF8String, AVIO_FLAG_WRITE, &output->interrupt_callback, NULL)) < 0) goto finish;
    av_dict_set(&options, "movflags", "+faststart", 0);
    if ((result = avformat_write_header(output, &options)) < 0) goto finish;
    packet = av_packet_alloc();
    if (!packet) { result = AVERROR(ENOMEM); goto finish; }
    int64_t started = av_gettime_relative(), reported = started, position = 0;
    while ((result = av_read_frame(input, packet)) >= 0) {
        if ([observer cancelled]) { result = AVERROR_EXIT; break; }
        if (av_packet_get_side_data(packet, AV_PKT_DATA_ENCRYPTION_INFO, NULL)) {
            failureReason = @"DRM/CENC encrypted tracks are unsupported. Only ordinary AES-128 HLS encryption is supported.";
            result = AVERROR(ENOTSUP); break;
        }
        if (packet->flags & AV_PKT_FLAG_CORRUPT) { result = AVERROR_INVALIDDATA; break; }
        for (int i = 0; i < 2; i++) {
            TSTrack *track = &tracks[i];
            if (!track->input || packet->stream_index != track->input->index) continue;
            if (packet->pts != AV_NOPTS_VALUE) position = MAX(position, av_rescale_q(packet->pts + MAX(0, packet->duration), track->input->time_base, AV_TIME_BASE_Q) - (input->start_time == AV_NOPTS_VALUE ? 0 : input->start_time));
            if (track->encoder) result = decodePacket(track, output, packet);
            else {
                av_packet_rescale_ts(packet, track->input->time_base, track->output->time_base);
                packet->stream_index = track->output->index;
                packet->pos = -1;
                result = av_interleaved_write_frame(output, packet);
                if (result >= 0) track->packets++;
            }
            break;
        }
        av_packet_unref(packet);
        if (result < 0) break;
        int64_t now = av_gettime_relative();
        if (now - reported >= 500000) {
            int64_t bytes = MAX(0, avio_tell(output->pb));
            [observer progress:input->duration > 0 ? MIN(.99, (double)position / input->duration) : 0 bytes:bytes bytesPerSecond:bytes * 1000000.0 / MAX(1, now - started)];
            reported = now;
        }
    }
    if (result != AVERROR_EOF) goto finish;
    // Some demuxers report EOF for a truncated transport. Do not finalize a
    // known-duration asset when its final media timestamps were never reached.
    if (input->duration > 0 && position + 500000 < input->duration) { result = AVERROR_INVALIDDATA; goto finish; }
    result = 0;
    for (int i = 0; i < 2; i++) {
        TSTrack *track = &tracks[i];
        if (!track->encoder) continue;
        if ((result = decodePacket(track, output, NULL)) < 0 || (result = filterFrame(track, output, NULL)) < 0 || (result = writeEncoded(track, output, NULL)) < 0) goto finish;
    }
    if (!tracks[0].packets) { result = AVERROR_INVALIDDATA; goto finish; }
    result = av_write_trailer(output);
finish:
    av_dict_free(&options);
    av_packet_free(&packet);
    for (int i = 0; i < 2; i++) freeTrack(&tracks[i]);
    if (output) { int closeResult = avio_closep(&output->pb); if (result >= 0 && closeResult < 0) result = closeResult; avformat_free_context(output); }
    avformat_close_input(&input);
    dispatch_semaphore_signal(_slot);
    if (result < 0) {
        [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
        char message[AV_ERROR_MAX_STRING_SIZE]; av_strerror(result, message, sizeof(message));
        if (error) *error = [NSError errorWithDomain:@"TsunaguVideo" code:result userInfo:@{NSLocalizedDescriptionKey:failureReason ?: [NSString stringWithUTF8String:message]}];
        return NO;
    }
    return YES;
}
@end
