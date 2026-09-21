"""Exercise the actual embedded libraries; host ffmpeg only generates/inspects fixtures."""
import functools
import http.server
import json
import pathlib
import subprocess
import tempfile
import threading
import time

SERVICE = pathlib.Path(__file__).resolve().parents[1]

def run(*args):
    return subprocess.run(args, check=True, capture_output=True, timeout=60)

with tempfile.TemporaryDirectory(prefix="moku-video-") as directory:
    root = pathlib.Path(directory)
    def ff(*args):
        return run("ffmpeg", "-v", "error", "-y", *map(str,args))
    ff("-f","lavfi","-i","testsrc2=size=160x96:rate=10","-f","lavfi","-i","sine=frequency=440:sample_rate=48000","-t","2","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac","-movflags","+faststart",root/"input.mp4")
    ff("-i",root/"input.mp4","-c","copy","-f","hls","-hls_time","1","-hls_list_size","0",root/"index.m3u8")
    ff("-i",root/"input.mp4","-c","copy","-f","hls","-hls_segment_type","fmp4","-hls_list_size","0",root/"fragmented.m3u8")
    ff("-i",root/"input.mp4","-c","copy","-f","dash",root/"video.mpd")
    ff("-i",root/"input.mp4","-c:v","mpeg4","-c:a","pcm_s16le",root/"convert.avi")
    ff("-i",root/"input.mp4","-an","-c:v","copy","-f","hls","-hls_list_size","0",root/"separate-video.m3u8")
    ff("-i",root/"input.mp4","-vn","-c:a","copy","-f","hls","-hls_list_size","0",root/"separate-audio.m3u8")
    (root/"separate-master.m3u8").write_text('#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",DEFAULT=YES,AUTOSELECT=YES,URI="separate-audio.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=300000,AUDIO="audio"\nseparate-video.m3u8\n')
    (root/"missing.m3u8").write_text((root/"index.m3u8").read_text().replace("index0.ts", "missing.ts"))
    (root/"master.m3u8").write_text('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=300000\nindex.m3u8\n')
    (root/"key").write_bytes(bytes(range(16)))
    (root/"keyinfo").write_text("key\n"+str(root/"key")+"\n")
    ff("-i",root/"input.mp4","-c","copy","-f","hls","-hls_key_info_file",root/"keyinfo","-hls_list_size","0",root/"encrypted.m3u8")
    (root/"truncated.mp4").write_bytes((root/"input.mp4").read_bytes()[:len((root/"input.mp4").read_bytes()) // 2])
    (root/"live.m3u8").write_text((root/"index.m3u8").read_text().replace("#EXT-X-ENDLIST", ""))
    ff("-i",root/"input.mp4","-c","copy","-encryption_scheme","cenc-aes-ctr","-encryption_key","00112233445566778899aabbccddeeff","-encryption_kid","ffeeddccbbaa99887766554433221100",root/"drm.mp4")
    (root/"invalid.mp4").write_bytes(b"not a video")
    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self,*args): pass
        def do_GET(self):
            if self.headers.get("X-Source") != "required":
                self.send_error(403); return
            if self.path == "/slow.mp4":
                time.sleep(2)
                self.path = "/input.mp4"
            super().do_GET()
    server = http.server.ThreadingHTTPServer(("127.0.0.1",0),functools.partial(Handler,directory=directory))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}/"
    probe = str(SERVICE/".build/video-engine-probe")
    try:
        for name in ("input.mp4","index.m3u8","fragmented.m3u8","master.m3u8","separate-master.m3u8","encrypted.m3u8","video.mpd","convert.avi"):
            output=root/(name+".output.mp4")
            result = subprocess.run([probe,base+name,json.dumps({"X-Source":"required"}),str(output)],capture_output=True,timeout=60)
            assert result.returncode == 0, (name,result.stderr.decode())
            facts=json.loads(run("ffprobe","-v","error","-show_streams","-show_format","-of","json",str(output)).stdout)
            assert float(facts["format"]["duration"]) >= 1.8, (name,facts)
            assert {s["codec_name"] for s in facts["streams"]}=={"h264","aac"}, (name,facts)
            ff("-i",output,"-f","null","-")
            if name == "input.mp4":
                assert output.read_bytes() == (root / name).read_bytes(), "compatible MP4 was not copied directly"
            print("PASS",name,flush=True)
        for name,headers,timeout in (("missing.m3u8",{"X-Source":"required"},None),("drm.mp4",{"X-Source":"required"},None),("truncated.mp4",{"X-Source":"required"},None),("live.m3u8",{"X-Source":"required"},None),("invalid.mp4",{"X-Source":"required"},None),("input.mp4",{},None),("slow.mp4",{"X-Source":"required"},"0.1")):
            output=root/"failure.mp4"
            args=[probe,base+name,json.dumps(headers),str(output)]
            if timeout: args.append(timeout)
            result=subprocess.run(args,capture_output=True,timeout=10)
            assert result.returncode != 0 and not output.exists(), (name,result.stderr.decode())
            print("PASS rejection/cancellation",name,flush=True)
        output=root/"missing-directory"/"failure.mp4"
        result=subprocess.run([probe,base+"input.mp4",json.dumps({"X-Source":"required"}),str(output)],capture_output=True,timeout=10)
        assert result.returncode != 0 and not output.exists(), "native write failure was accepted"
        print("PASS output write failure",flush=True)
    finally:
        server.shutdown(); server.server_close()
