import AppKit
import Foundation

func fixturePNG(_ red: UInt8, _ green: UInt8, _ blue: UInt8) throws -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 3,
      hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 3, bitsPerPixel: 24
    ), let bytes = bitmap.bitmapData
  else { throw CLIError("Cannot create PNG fixture") }
  bytes[0] = red
  bytes[1] = green
  bytes[2] = blue
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CLIError("Cannot encode PNG fixture")
  }
  return png
}
func varint(_ value: Int) -> Data {
  var value = value
  var bytes = Data()
  while value > 127 {
    bytes.append(UInt8(value & 127) | 128)
    value >>= 7
  }
  bytes.append(UInt8(value))
  return bytes
}
func field(_ number: Int, _ value: Data) -> Data {
  varint(number * 8 + 2) + varint(value.count) + value
}
func field(_ number: Int, _ value: String) -> Data { field(number, Data(value.utf8)) }
func extensionID(_ kind: String) -> String {
  kind == "anime"
    ? "eu.kanade.tachiyomi.animeextension.en.acceptance" : "org.moku.acceptance." + kind
}
func androidManifest(_ package: String, _ source: String) throws -> Data {
  let strings = [
    "manifest", "package", package, "application", "meta-data", "name", "value",
    "tachiyomi.extension.class", source, "android", "http://schemas.android.com/apk/res/android",
    "versionName", "1.0",
  ]
  let index = Dictionary(uniqueKeysWithValues: strings.enumerated().map { ($1, UInt32($0)) })
  func u16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
  func words(_ values: [UInt32]) -> Data {
    values.reduce(Data()) { data, value in
      data + withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
  }
  func chunk(_ kind: UInt16, _ header: UInt16, _ body: Data) -> Data {
    u16(kind) + u16(header) + words([UInt32(8 + body.count)]) + body
  }
  var encoded = Data()
  var offsets: [UInt32] = []
  for string in strings {
    let bytes = Data(string.utf8)
    try require(
      bytes.count < 128 && string.utf16.count < 128, "Fixture manifest strings must be short")
    offsets.append(UInt32(encoded.count))
    encoded.append(UInt8(string.utf16.count))
    encoded.append(UInt8(bytes.count))
    encoded.append(bytes)
    encoded.append(0)
  }
  while encoded.count % 4 != 0 { encoded.append(0) }
  let pool = chunk(
    1, 28,
    words([UInt32(strings.count), 0, 256, UInt32(28 + strings.count * 4), 0]) + words(offsets)
      + encoded)
  let unset = UInt32.max
  func node(_ kind: UInt16, _ body: Data) -> Data { chunk(kind, 16, words([1, unset]) + body) }
  func tag(_ name: String, _ attrs: [(String?, String, String)] = [], end: Bool = false) -> Data {
    if end { return node(0x103, words([unset, index[name]!])) }
    var body =
      words([unset, index[name]!])
      + [UInt16(20), 20, UInt16(attrs.count), 0, 0, 0].reduce(Data()) { $0 + u16($1) }
    for (namespace, key, value) in attrs {
      body +=
        words([namespace.flatMap { index[$0] } ?? unset, index[key]!, index[value]!]) + u16(8)
        + Data([0, 3]) + words([index[value]!])
    }
    return node(0x102, body)
  }
  let uri = strings[10]
  let namespace = words([index["android"]!, index[uri]!])
  var xml = pool + node(0x100, namespace)
  xml += tag("manifest", [(nil, "package", package), (uri, "versionName", "1.0")])
  xml +=
    tag("application")
    + tag("meta-data", [(uri, "name", "tachiyomi.extension.class"), (uri, "value", source)])
  xml +=
    tag("meta-data", end: true) + tag("application", end: true) + tag("manifest", end: true)
    + node(0x101, namespace)
  return chunk(3, 8, xml)
}

final class AcceptanceFixtures {
  let runner: Runner
  let root: URL
  let origin: String
  var sandbox: URL { runner.path("vendor/Tsunagu/sandbox/build/libs/sandbox-0.1.0-all.jar") }
  var jdk: URL { runner.path("Services/.build/toolchains/jdk-21.0.12.1+1/Contents/Home/bin") }
  var classes: URL { root.appendingPathComponent("classes") }
  init(_ runner: Runner, _ website: FixtureWebsite) {
    self.runner = runner
    root = website.root
    origin = website.origin
  }
  func file(_ name: String) -> URL { root.appendingPathComponent(name) }
  func archive(_ name: String, entries: [String: Data]) throws {
    let staging = file("archive-" + UUID().uuidString)
    try mkdir(staging)
    defer { try? remove(staging) }
    for (name, data) in entries {
      let destination = staging.appendingPathComponent(name)
      try mkdir(destination.deletingLastPathComponent())
      try data.write(to: destination)
    }
    try runner.run(["zip", "-q", "-r", file(name).path, "."], cwd: staging, timeout: 60)
  }
  func build() throws {
    try mkdir(classes)
    let sources = try contents(runner.path("Services/tests/fixtures"), suffix: ".java").map {
      source -> String in
      let target = file(source.lastPathComponent)
      try write(
        try String(contentsOf: source, encoding: .utf8).replacingOccurrences(
          of: "FIXTURE_ORIGIN", with: origin), target)
      return target.path
    }
    try runner.run(
      [
        jdk.appendingPathComponent("javac").path, "--release", "11", "-cp", sandbox.path, "-d",
        classes.path,
      ] + sources, timeout: 60)
    var extensions = Data()
    for kind in ["manga", "anime", "alternate"] {
      let name = kind == "alternate" ? "MangaAlt" : kind.capitalized
      let package = extensionID(kind)
      let manifest =
        "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" package=\"\(package)\"><application><meta-data android:name=\"tachiyomi.extension.class\" android:value=\"org.moku.acceptance.\(name)\"/></application></manifest>"
      var entries = ["AndroidManifest.xml": Data(manifest.utf8)]
      for cls in kind == "alternate" ? ["Manga", "MangaAlt"] : [name] {
        let relative = "org/moku/acceptance/\(cls).class"
        entries[relative] = try Data(contentsOf: classes.appendingPathComponent(relative))
      }
      try archive(kind + ".jar", entries: entries)
      let link =
        field(501, origin + "/\(kind).jar")
        + (kind == "alternate" ? Data() : field(2, origin + "/icon.png"))
      let ext =
        field(1, "Acceptance " + (kind == "alternate" ? "Alternate" : name)) + field(2, package)
        + field(3, link) + field(6, "1.0") + field(8, field(3, "en"))
      extensions += field(1, ext)
    }
    let apkClasses = file("apk-classes")
    try mkdir(apkClasses)
    try runner.run(
      [
        jdk.appendingPathComponent("javac").path, "--release", "8", "-cp", sandbox.path, "-d",
        apkClasses.path, file("Manga.java").path,
      ], timeout: 60)
    try runner.run(
      [
        jdk.appendingPathComponent("java").path, "-cp", sandbox.path, "com.android.dx.command.Main",
        "--dex", "--output=" + file("classes.dex").path, apkClasses.path,
      ], timeout: 60)
    try archive(
      "manga.apk",
      entries: [
        "AndroidManifest.xml": androidManifest(extensionID("manga"), "org.moku.acceptance.Manga"),
        "classes.dex": Data(contentsOf: file("classes.dex")),
      ])
    try (field(1, "Acceptance") + field(101, extensions)).write(to: file("index.pb"))
    try write("<h1>Chapter 1</h1><p>Acceptance novel text.</p>", file("novel-text.html"))
    try write(
      try String(contentsOf: runner.path("Services/tests/fixtures/novel.js"), encoding: .utf8)
        .replacingOccurrences(of: "FIXTURE_ORIGIN", with: origin), file("novel.js"))
    try JSON([
      [
        "id": extensionID("novel"), "name": "Acceptance Novel", "site": origin, "lang": "en",
        "version": "1.0", "url": origin + "/novel.js",
      ]
    ]).save(file("novels.json"))
    for (name, rgb) in [
      ("icon.png", [25, 25, 25]), ("cover.png", [0, 0, 255]), ("page-1.png", [255, 0, 0]),
      ("page-2.png", [0, 255, 0]),
    ] { try fixturePNG(UInt8(rgb[0]), UInt8(rgb[1]), UInt8(rgb[2])).write(to: file(name)) }
    try runner.run(
      [
        "ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=160x90:r=10", "-t", "2",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", file("video.mp4").path,
      ], timeout: 30)
    for (format, name) in [("mpegts", "segment.ts"), ("dash", "video.mpd")] {
      try runner.run(
        [
          "ffmpeg", "-v", "error", "-i", file("video.mp4").path, "-c", "copy", "-f", format,
          file(name).path,
        ], timeout: 30)
    }
    try write(
      "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:2.0,\nsegment.ts\n#EXT-X-ENDLIST\n",
      file("master.m3u8"))
    try write("WEBVTT\n\n00:00.000 --> 00:01.500\nAcceptance subtitle.\n", file("subtitles.vtt"))
  }
}
