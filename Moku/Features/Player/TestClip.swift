#if DEBUG
    import AVFoundation
    import CoreGraphics

    /// A plain grid clip drawn on first use for the player preview and UI tests, so no video ships in the repo.
    enum TestClip {
        static func url() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appending(path: "moku-test-clip.mp4")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            let partial = url.deletingPathExtension().appendingPathExtension("partial.mp4")
            try? FileManager.default.removeItem(at: partial)
            try write(to: partial)
            try FileManager.default.moveItem(at: partial, to: url)
            return url
        }

        private static let width = 960, height = 540, fps: Int32 = 2, seconds = 24

        private static func write(to url: URL) throws {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            writer.startSession(atSourceTime: .zero)
            let frame = try gridFrame()
            for index in 0..<(seconds * Int(fps)) {
                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
                adaptor.append(
                    frame, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
            }
            input.markAsFinished()
            let done = DispatchSemaphore(value: 0)
            writer.finishWriting { done.signal() }
            done.wait()
            if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        }

        private static func gridFrame() throws -> CVPixelBuffer {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
            guard let context else { throw CocoaError(.fileWriteUnknown) }
            context.setFillColor(CGColor(red: 0.14, green: 0.2, blue: 0.22, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setStrokeColor(CGColor(red: 0.3, green: 0.4, blue: 0.42, alpha: 1))
            for x in stride(from: 0, through: width, by: 120) {
                context.stroke(CGRect(x: x, y: 0, width: 0, height: height))
            }
            for y in stride(from: 0, through: height, by: 90) {
                context.stroke(CGRect(x: 0, y: y, width: width, height: 0))
            }
            return buffer
        }
    }
#endif
