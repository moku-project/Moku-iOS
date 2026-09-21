import Foundation

extension NativeBuild {
  func verify() throws {
    try prepare()
    try runner.run(["swift", "test", "--package-path", "Tools/CLI", "--scratch-path", ".build/cli"])
    try run([
      "go", "test", "-race", "tsunagu/backend/mobile", "tsunagu/backend/internal/sandbox", "./...",
    ])
    try run(["go", "vet", "./...", "tsunagu/backend/mobile", "tsunagu/backend/internal/sandbox"])
    try go()
    try videoEngine()
    try bridge()
  }

  func bridge() throws {
    let libs = try contents(path(".build/ffmpeg/macos/lib"), suffix: ".a").map(\.path)
    try run([
      "xcrun", "clang", "-target", "arm64-apple-macos14.0", "-fobjc-arc", "-fmodules",
      "-I.build/ffmpeg/macos/include", "-F.build/Tsunagu.xcframework/macos-arm64", "-c",
      "native/TSVideoEngine.m", "-o", ".build/TSVideoEngine-macos.o",
    ])
    let swift = try contents(path("swift"), suffix: ".swift").map(\.path)
    try run(
      [
        "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
        "-F.build/Tsunagu.xcframework/macos-arm64", "-framework", "Tsunagu", "-lresolv",
        "-import-objc-header", "native/TSVideoEngine.h",
      ] + swift + ["tests/Smoke.swift", ".build/TSVideoEngine-macos.o"] + libs + [
        "-framework", "WebKit",
      ] + frameworks + ["-lz", "-lxml2", "-o", ".build/backend-smoke"])
    try run([path(".build/backend-smoke").path], timeout: 180)
    for value in ["device", "simulator"] {
      let p = try platform(value)
      try run(
        [
          "xcrun", "--sdk", p.sdk, "swiftc", "-swift-version", "6", "-typecheck", "-target",
          p.target, "-sdk", try sdk(p.sdk), "-F.build/Tsunagu.xcframework/\(p.slice)",
          "-import-objc-header", "native/TSVideoEngine.h",
        ] + swift)
    }
  }
  func videoEngine() throws {
    try ffmpeg("macos")
    let libs = try contents(path(".build/ffmpeg/macos/lib"), suffix: ".a").map(\.path)
    try run(
      [
        "xcrun", "clang", "-target", "arm64-apple-macos14.0", "-fobjc-arc", "-fmodules",
        "-I.build/ffmpeg/macos/include", "-Inative", "-F.build/Tsunagu.xcframework/macos-arm64",
        "native/TSVideoEngine.m", "tests/VideoEngineProbe.m",
      ] + libs + frameworks + ["-lz", "-lxml2", "-o", ".build/video-engine-probe"])
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "moku-video-" + UUID().uuidString)
    try mkdir(root)
    defer { try? remove(root) }
    func file(_ name: String) -> URL { root.appendingPathComponent(name) }
    func ff(_ args: [String]) throws {
      try run(["ffmpeg", "-v", "error", "-y"] + args, timeout: 60)
    }
    try ff([
      "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=10", "-f", "lavfi", "-i",
      "sine=frequency=440:sample_rate=48000", "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p",
      "-c:a", "aac", "-movflags", "+faststart", file("input.mp4").path,
    ])
    let input = ["-i", file("input.mp4").path]
    for (name, args) in [
      ("index.m3u8", ["-c", "copy", "-f", "hls", "-hls_time", "1", "-hls_list_size", "0"]),
      (
        "fragmented.m3u8",
        ["-c", "copy", "-f", "hls", "-hls_segment_type", "fmp4", "-hls_list_size", "0"]
      ),
      ("video.mpd", ["-c", "copy", "-f", "dash"]),
      ("convert.avi", ["-c:v", "mpeg4", "-c:a", "pcm_s16le"]),
      ("separate-video.m3u8", ["-an", "-c:v", "copy", "-f", "hls", "-hls_list_size", "0"]),
      ("separate-audio.m3u8", ["-vn", "-c:a", "copy", "-f", "hls", "-hls_list_size", "0"]),
    ] { try ff(input + args + [file(name).path]) }
    try write(
      "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"English\",DEFAULT=YES,AUTOSELECT=YES,URI=\"separate-audio.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH=300000,AUDIO=\"audio\"\nseparate-video.m3u8\n",
      file("separate-master.m3u8"))
    let playlist = try String(contentsOf: file("index.m3u8"), encoding: .utf8)
    try write(
      playlist.replacingOccurrences(of: "index0.ts", with: "missing.ts"), file("missing.m3u8"))
    try write("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=300000\nindex.m3u8\n", file("master.m3u8"))
    try Data(0..<16).write(to: file("key"))
    try write("key\n\(file("key").path)\n", file("keyinfo"))
    try ff(
      input + [
        "-c", "copy", "-f", "hls", "-hls_key_info_file", file("keyinfo").path, "-hls_list_size",
        "0", file("encrypted.m3u8").path,
      ])
    let original = try Data(contentsOf: file("input.mp4"))
    try original.prefix(original.count / 2).write(to: file("truncated.mp4"))
    try write(playlist.replacingOccurrences(of: "#EXT-X-ENDLIST", with: ""), file("live.m3u8"))
    try ff(
      input + [
        "-c", "copy", "-encryption_scheme", "cenc-aes-ctr", "-encryption_key",
        "00112233445566778899aabbccddeeff", "-encryption_kid", "ffeeddccbbaa99887766554433221100",
        file("drm.mp4").path,
      ])
    try write("not a video", file("invalid.mp4"))
    let server = try FixtureWebsite(root)
    server.mediaMode = true
    defer { server.close() }
    let probe = path(".build/video-engine-probe").path
    let headers = "{\"X-Source\":\"required\"}"
    for name in [
      "input.mp4", "index.m3u8", "fragmented.m3u8", "master.m3u8", "separate-master.m3u8",
      "encrypted.m3u8", "video.mpd", "convert.avi",
    ] {
      let output = file(name + ".output.mp4")
      try run([probe, server.origin + "/" + name, headers, output.path], timeout: 60)
      let facts = try JSON(
        data: runner.runData(
          ["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", output.path],
          timeout: 60))
      try require((Double(facts["format"]["duration"].s) ?? 0) >= 1.8, "\(name): duration mismatch")
      try require(
        Set(facts["streams"].a.map { $0["codec_name"].s }) == ["h264", "aac"],
        "\(name): codec mismatch")
      try ff(["-i", output.path, "-f", "null", "-"])
      if name == "input.mp4" {
        try require(
          try Data(contentsOf: output) == original, "Compatible MP4 was not copied directly")
      }
      print("PASS \(name)")
    }
    for (name, header, timeout) in [
      ("missing.m3u8", headers, ""), ("drm.mp4", headers, ""), ("truncated.mp4", headers, ""),
      ("live.m3u8", headers, ""), ("invalid.mp4", headers, ""), ("input.mp4", "{}", ""),
      ("slow.mp4", headers, "0.1"),
    ] {
      let output = file("failure.mp4")
      let args =
        [probe, server.origin + "/" + name, header, output.path]
        + (timeout.isEmpty ? [] : [timeout])
      var rejected = false
      do { try run(args, timeout: 10) } catch {
        try require(!runner.cancelled, "Interrupted")
        rejected = true
      }
      try require(
        rejected && !FileManager.default.fileExists(atPath: output.path),
        "\(name) was not rejected cleanly")
      print("PASS rejection/cancellation \(name)")
    }
    let output = file("missing-directory/failure.mp4")
    var rejected = false
    do { try run([probe, server.origin + "/input.mp4", headers, output.path], timeout: 10) } catch {
      rejected = true
    }
    try require(
      rejected && !FileManager.default.fileExists(atPath: output.path),
      "Native write failure was accepted")
    print("PASS output write failure")
  }
  func videoDevice(_ device: String) throws {
    try ffmpeg("device")
    let output = path(".build/device-media")
    try mkdir(output)
    try run(
      [
        "ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=10", "-f",
        "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "2", "-c:v", "libx264",
        "-pix_fmt", "yuv420p", "-c:a", "aac", output.appendingPathComponent("input.mp4").path,
      ], timeout: 60)
    try run(
      [
        "ffmpeg", "-v", "error", "-y", "-i", output.appendingPathComponent("input.mp4").path,
        "-c:v", "mpeg4", "-c:a", "pcm_s16le", output.appendingPathComponent("convert.avi").path,
      ], timeout: 60)
    let libs = try contents(path(".build/ffmpeg/device/lib"), suffix: ".a").map(\.path).joined(
      separator: " ")
    let settings: [String: Any] = [
      "PRODUCT_BUNDLE_IDENTIFIER": "com.moku.media-validation",
      "DEVELOPMENT_TEAM": env["MOKU_DEVELOPMENT_TEAM"] ?? "7D6BVN4W87",
      "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "YES",
      "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
      "HEADER_SEARCH_PATHS": "\(service.path)/native \(service.path)/.build/ffmpeg/device/include",
      "FRAMEWORK_SEARCH_PATHS": path(".build/Tsunagu.xcframework/ios-arm64").path,
      "CLANG_ENABLE_OBJC_ARC": "YES",
      "OTHER_LDFLAGS": libs
        + " -framework UIKit -framework Foundation -framework Security -framework CoreMedia -framework CoreVideo -framework VideoToolbox -framework AudioToolbox -lz -lxml2",
    ]
    let sources: [Any] = [
      path("tests/NativeMediaDeviceProbe.m").path, path("native/TSVideoEngine.m").path,
      ["path": output.appendingPathComponent("input.mp4").path, "buildPhase": "resources"],
      ["path": output.appendingPathComponent("convert.avi").path, "buildPhase": "resources"],
    ]
    try JSON([
      "name": "MediaValidation", "options": ["deploymentTarget": ["iOS": "18.2"]],
      "targets": [
        "MediaValidation": [
          "type": "application", "platform": "iOS", "sources": sources,
          "settings": ["base": settings],
        ]
      ],
    ]).save(output.appendingPathComponent("project.json"))
    try run([
      "xcodegen", "generate", "--spec", output.appendingPathComponent("project.json").path,
      "--project", output.path,
    ])
    try run([
      "xcodebuild", "-project", output.appendingPathComponent("MediaValidation.xcodeproj").path,
      "-scheme", "MediaValidation", "-configuration", "Debug", "-destination",
      "generic/platform=iOS", "-derivedDataPath", output.appendingPathComponent("DerivedData").path,
      "-allowProvisioningUpdates", "build",
    ])
    try run([
      "xcrun", "devicectl", "device", "install", "app", "--device", device,
      output.appendingPathComponent("DerivedData/Build/Products/Debug-iphoneos/MediaValidation.app")
        .path,
    ])
    defer {
      _ = try? run([
        "xcrun", "devicectl", "device", "uninstall", "app", "--device", device,
        "com.moku.media-validation",
      ])
    }
    let log = try run(
      [
        "xcrun", "devicectl", "device", "process", "launch", "--device", device, "--console",
        "--timeout", "60", "com.moku.media-validation",
      ], capture: true, timeout: 70)
    try write(log, path(".build/device-media-result.log"))
    guard
      let line = log.components(separatedBy: .newlines).first(where: {
        $0.hasPrefix("MEDIA_DEVICE_RESULT ")
      })
    else { throw CLIError("Missing device media report") }
    let rows = try JSON(data: Data(line.dropFirst("MEDIA_DEVICE_RESULT ".count).utf8)).a
    try require(
      rows.count == 2 && rows.allSatisfy { $0["passed"].b }, "Device media validation failed")
    print("Physical-device embedded MP4 remux + VideoToolbox/AAC conversion: PASS")
  }
}
