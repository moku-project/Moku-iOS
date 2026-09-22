import Foundation

final class NativeBuild {
  let runner: Runner
  let service: URL
  var env: [String: String] { ProcessInfo.processInfo.environment }
  init(_ runner: Runner) {
    self.runner = runner
    service = runner.path("Services")
  }
  func path(_ name: String) -> URL { service.appendingPathComponent(name) }
  @discardableResult
  func run(
    _ args: [String], cwd: URL? = nil, environment: [String: String] = [:], capture: Bool = false,
    timeout: TimeInterval? = nil
  ) throws -> String {
    try runner.run(
      args, capture: capture, environment: environment, cwd: cwd ?? service, timeout: timeout
    ).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  func sdk(_ name: String) throws -> String {
    try run(["xcrun", "--sdk", name, "--show-sdk-path"], capture: true)
  }
  func platform(_ value: String) throws -> (sdk: String, target: String, slice: String) {
    switch value {
    case "simulator":
      return ("iphonesimulator", "arm64-apple-ios18.2-simulator", "ios-arm64-simulator")
    case "device": return ("iphoneos", "arm64-apple-ios18.2", "ios-arm64")
    case "macos": return ("macosx", "arm64-apple-macos14.0", "macos-arm64")
    default: throw CLIError("Unsupported platform \(value)")
    }
  }
  func apply(_ patch: URL, in directory: URL) throws {
    do {
      try run(["git", "apply", "--reverse", "--check", patch.path], cwd: directory, capture: true)
      return
    } catch { try require(!runner.cancelled, "Interrupted") }
    try run(["git", "apply", "--check", patch.path], cwd: directory)
    try run(["git", "apply", patch.path], cwd: directory)
  }
  func prepare() throws {
    if !FileManager.default.fileExists(atPath: runner.path("vendor/Tsunagu/backend/go.mod").path) {
      try runner.run([
        "git", "submodule", "update", "--init", "--recursive", "--", "vendor/Tsunagu",
      ])
    }
    try apply(path("patches/0001-embedded-core.patch"), in: runner.path("vendor/Tsunagu"))
  }
  func download(_ url: String, to destination: URL, hash: String) throws {
    try mkdir(destination.deletingLastPathComponent())
    if !FileManager.default.fileExists(atPath: destination.path) {
      let partial = destination.appendingPathExtension("part")
      defer { try? remove(partial) }
      // curl is a system executable, invoked directly without shell code.
      try run([
        "curl", "--fail", "--location", "--retry", "3", "--max-time", "600", url, "--output",
        partial.path,
      ])
      try require(
        try sha256File(partial) == hash, "Checksum mismatch: \(destination.lastPathComponent)")
      try FileManager.default.moveItem(at: partial, to: destination)
    }
    try require(
      try sha256File(destination) == hash, "Checksum mismatch: \(destination.lastPathComponent)")
  }
  func extract(_ archive: URL, to destination: URL) throws {
    try mkdir(destination)
    let names = try run(["tar", "-tf", archive.path], capture: true).split(separator: "\n")
    for name in names {
      try require(
        !name.hasPrefix("/") && !name.split(separator: "/").contains(".."), "Unsafe archive path")
    }
    // macOS libarchive rejects traversal through archive-created symlinks.
    try run(["tar", "-xf", archive.path, "-C", destination.path])
  }
  func fetchInputs() throws {
    let cache = path(".build/toolchains")
    let assets = [
      (
        "jdk21.tar.gz",
        "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_aarch64_mac_hotspot_21.0.12.1_1.tar.gz",
        "3623232f33a9c3baadf304480b2535f9a3cba8a58d42ecbb438ba267315d9998", cache
      ),
      (
        "gradle-8.14.4-bin.zip", "https://services.gradle.org/distributions/gradle-8.14.4-bin.zip",
        "f1771298a70f6db5a29daf62378c4e18a17fc33c9ba6b14362e0cdf40610380d", cache
      ),
      (
        "libffi-ios-sim.zip",
        "https://github.com/openjdk-mobile/ios-tools/releases/download/libffi-build/libffi-ios-sim.zip",
        "701b522e3eff0263f18d4a9e487f0a7ac30050fb2af20e86b6849daa14f5781f",
        path(".build/libffi-sim")
      ),
      (
        "libffi-ios.zip",
        "https://github.com/openjdk-mobile/ios-tools/releases/download/libffi-build/libffi-ios.zip",
        "4f39fd1d53fbd69d1bdbd915413077d130daa3f6792d1b3a03a690a9cbd4dea3",
        path(".build/libffi-device")
      ),
    ]
    for (name, url, hash, destination) in assets {
      let archive = cache.appendingPathComponent(name)
      try download(url, to: archive, hash: hash)
      let marker = cache.appendingPathComponent(name + ".extracted")
      if !FileManager.default.fileExists(atPath: marker.path) {
        try extract(archive, to: destination)
        if name.hasPrefix("gradle") {
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: cache.appendingPathComponent("gradle-8.14.4/bin/gradle").path)
        }
        try write("", marker)
      }
      print("Verified \(name)")
    }
  }
  func fetchSnapshot() throws {
    for (name, hash) in [
      "OpenJDK.xcframework": "ae8e22142e45e5c1e9e8e3541829f3cc00584658eb21eeeb0d3612e3fbaf7c9f",
      "java.base-device": "af099f41010c4ceffd21231ae7d40b7c292190ab44c19616077545ae609f8c8d",
      "java.base-simulator": "5b0e75dbd88dd4f35f3108b263969d311ed697c1397a3fd0a247505acf91e49a",
    ] {
      let archive = path(".build/openjdk/\(name).zip")
      try download(
        "https://github.com/openjdk-mobile/ios-tools/releases/download/snapshot/\(name).zip",
        to: archive, hash: hash)
      try extract(archive, to: path(".build/openjdk/\(name)"))
    }
  }
  func go() throws {
    try prepare()
    try mkdir(path(".build/tools"))
    try run(
      ["go", "install", "golang.org/x/mobile/cmd/gobind"],
      environment: ["GOBIN": path(".build/tools").path])
    try run(
      [
        "go", "tool", "gomobile", "bind", "-target=ios/arm64,iossimulator/arm64,macos/arm64",
        "-iosversion=18.0", "-o", ".build/Tsunagu.xcframework", ".",
      ], environment: ["PATH": path(".build/tools").path + ":" + (env["PATH"] ?? "/usr/bin:/bin")])
  }
  func sandbox() throws {
    try prepare()
    try fetchInputs()
    try run(
      [
        path(".build/toolchains/gradle-8.14.4/bin/gradle").path, "-p",
        runner.path("vendor/Tsunagu/sandbox").path, "--no-daemon", "shadowJar",
      ], environment: ["JAVA_HOME": path(".build/toolchains/jdk-21.0.12.1+1/Contents/Home").path])
  }
  func jvm(_ value: String) throws {
    let p = try platform(value)
    try require(value != "macos", "JVM build supports device or simulator")
    let source = path(".build/openjdk-source")
    let pin = "dfd62e275c0970f75595f8bfe91eff34923fa896"
    if !FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path) {
      try run(["git", "init", source.path])
      try run(
        ["git", "remote", "add", "origin", "https://github.com/openjdk/mobile.git"], cwd: source)
      try run(["git", "fetch", "--depth", "1", "origin", pin], cwd: source)
      try run(["git", "checkout", "--detach", "FETCH_HEAD"], cwd: source)
    }
    try require(
      try run(["git", "rev-parse", "HEAD"], cwd: source, capture: true) == pin,
      "OpenJDK revision differs from pin")
    try fetchInputs()
    try apply(path("patches/0002-openjdk-ios.patch"), in: source)
    try apply(path("patches/0003-openjdk-ios-debug-dylib.patch"), in: source)
    let conf = value == "device" ? "moku-ios" : "moku-iossim"
    let ffi = path(value == "device" ? ".build/libffi-device" : ".build/libffi-sim")
    let flags =
      value == "device"
      ? "-target arm64-apple-ios -miphoneos-version-min=18.2"
      : "-target arm64-apple-ios-simulator -mios-simulator-version-min=18.2"
    try run(
      [
        "bash", "configure", "--with-conf-name=\(conf)", "--disable-warnings-as-errors",
        "--openjdk-target=aarch64-macos-ios",
        "--with-boot-jdk=\(env["MOKU_BOOT_JDK"] ?? "/opt/homebrew/opt/openjdk@25")",
        "--with-sysroot=\(try sdk(p.sdk))", "--with-libffi-include=\(ffi.path)/include/ffi",
        "--with-libffi-lib=\(ffi.path)", "--with-extra-cflags=\(flags)",
        "--with-extra-cxxflags=\(flags)", "--with-cups-include=\(try sdk("macosx"))/usr/include",
      ], cwd: source)
    try run(
      [
        "make", "JOBS=\(env["MOKU_BUILD_JOBS"] ?? "8")", "CONF=\(conf)", "static-libs-image",
        "java", "java.base-gendata",
      ], cwd: source)
    try packageJVM(value)
  }
  func packageJVM(_ value: String) throws {
    _ = try platform(value)
    let conf = value == "device" ? "moku-ios" : "moku-iossim"
    let ffi = value == "device" ? "libffi-device" : "libffi-sim"
    let source = path(".build/openjdk-source/build/\(conf)")
    let output = path(".build/openjdk-local/\(value)")
    try remove(output)
    try mkdir(output.appendingPathComponent("Headers"))
    try mkdir(output.appendingPathComponent("lib/modules"))
    for dir in ["jdk/include", "jdk/include/ios"] {
      for file in try contents(source.appendingPathComponent(dir), suffix: ".h") {
        try copy(file, output.appendingPathComponent("Headers/\(file.lastPathComponent)"))
      }
    }
    let libs = [
      "zero/libjvm.a", "libjava.a", "libverify.a", "libjimage.a", "libnet.a", "libnio.a",
      "libzip.a",
    ].map { source.appendingPathComponent("images/static-libs/lib/\($0)").path }
    try run(
      ["xcrun", "libtool", "-static", "-o", output.appendingPathComponent("libopenjdk.a").path]
        + libs + [path(".build/\(ffi)/libffi.a").path])
    for module in [
      "java.base", "java.logging", "java.management", "java.naming", "java.security.jgss",
      "java.security.sasl", "java.xml", "jdk.crypto.ec", "jdk.unsupported", "jdk.zipfs",
    ] {
      try copy(
        source.appendingPathComponent("jdk/modules/\(module)"),
        output.appendingPathComponent("lib/modules/\(module)"))
    }
    for (from, to) in [
      ("jdk/lib/security/cacerts", "lib/security/cacerts"), ("jdk/conf", "lib/conf"),
      ("jdk/lib/tzdb.dat", "lib/lib/tzdb.dat"),
    ] { try copy(source.appendingPathComponent(from), output.appendingPathComponent(to)) }
  }
  func ffmpeg(_ value: String) throws {
    let p = try platform(value)
    let hash = "8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
    let archive = path(".build/ffmpeg-9.0.2.tar.xz")
    let source = path(".build/ffmpeg-9.0.2")
    let prefix = path(".build/ffmpeg/\(value)")
    try download("https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz", to: archive, hash: hash)
    if !FileManager.default.fileExists(atPath: source.path) {
      try extract(archive, to: path(".build"))
    }
    let marker = prefix.appendingPathComponent("complete-\(hash)-dash1")
    if FileManager.default.fileExists(atPath: marker.path) { return }
    let build = prefix.appendingPathComponent("build")
    try mkdir(build)
    let sdkPath = try sdk(p.sdk)
    try write(
      "Name: libXML\nDescription: Apple SDK libxml2\nVersion: 2.9.4\nLibs: -L\(sdkPath)/usr/lib -lxml2\nCflags: -I\(sdkPath)/usr/include/libxml2\n",
      prefix.appendingPathComponent("pkgconfig/libxml-2.0.pc"))
    let environment = [
      "PKG_CONFIG_LIBDIR": prefix.appendingPathComponent("pkgconfig").path, "PKG_CONFIG_PATH": "",
    ]
    try run(
      [
        source.appendingPathComponent("configure").path, "--prefix=\(prefix.path)",
        "--target-os=darwin", "--arch=aarch64", "--enable-cross-compile",
        "--cc=\(try run(["xcrun", "--sdk", p.sdk, "-f", "clang"], capture: true))",
        "--sysroot=\(sdkPath)", "--extra-cflags=-target \(p.target)",
        "--extra-ldflags=-target \(p.target)", "--disable-programs", "--disable-doc",
        "--disable-debug", "--disable-autodetect", "--disable-gpl", "--disable-nonfree",
        "--disable-shared", "--enable-static", "--disable-avdevice", "--disable-encoders",
        "--enable-encoder=h264_videotoolbox,aac", "--enable-videotoolbox",
        "--enable-securetransport", "--enable-zlib", "--enable-libxml2", "--enable-network",
        "--disable-protocols", "--enable-protocol=file,http,https,tcp,tls,crypto,data",
      ], cwd: build, environment: environment)
    try run(["make", "-j\(env["MOKU_BUILD_JOBS"] ?? "8")"], cwd: build, environment: environment)
    try run(["make", "install"], cwd: build, environment: environment)
    for name in ["COPYING.LGPLv2.1", "LICENSE.md"] {
      try copy(source.appendingPathComponent(name), prefix.appendingPathComponent(name))
    }
    try write("", marker)
  }
  var frameworks: [String] {
    [
      "Foundation", "Security", "CoreFoundation", "CFNetwork", "VideoToolbox", "CoreMedia",
      "CoreVideo", "AudioToolbox",
    ].flatMap { ["-framework", $0] }
  }
  func native(_ value: String) throws {
    let p = try platform(value)
    try require(value != "macos", "Probe supports iOS device or simulator")
    let local = env["MOKU_LOCAL_JDK"] != "0"
    if !local { try fetchSnapshot() }
    let jdk =
      local
      ? path(".build/openjdk-local/\(value)")
      : path(
        ".build/openjdk/OpenJDK.xcframework/OpenJDK.xcframework/\(value == "device" ? "ios-arm64" : "ios-arm64_x86_64-simulator")"
      )
    let archive = local ? "libopenjdk.a" : value == "device" ? "libdevice.a" : "libsim.a"
    try ffmpeg(value)
    let ff = path(".build/ffmpeg/\(value)")
    let output = path(".build/native-\(value)")
    let app = output.appendingPathComponent("MokuBackendProbe.app")
    try remove(app)
    try mkdir(app.appendingPathComponent("lib/modules"))
    for name in ["COPYING.LGPLv2.1", "LICENSE.md"] {
      try copy(
        ff.appendingPathComponent(name),
        app.appendingPathComponent("ThirdPartyNotices/FFmpeg/\(name)"))
    }
    try copy(
      path("THIRD_PARTY_MEDIA.md"),
      app.appendingPathComponent("ThirdPartyNotices/FFmpeg/BUILD-AND-SOURCE.md"))
    for (dir, source, name) in [
      ("probe", "java/RuntimeProbe.java", "RuntimeProbe"),
      ("fixture", "tests/java/Extension.java", "Fixture"),
    ] {
      try mkdir(path(".build/java/\(dir)"))
      try run(["javac", "--release", "11", "-d", ".build/java/\(dir)", source])
      try run(["jar", "cf", ".build/java/\(name).jar", "-C", ".build/java/\(dir)", "."])
      try copy(path(".build/java/\(name).jar"), app.appendingPathComponent("\(name).jar"))
    }
    try copy(
      runner.path("vendor/Tsunagu/sandbox/build/libs/sandbox-0.1.0-all.jar"),
      app.appendingPathComponent("Sandbox.jar"))
    if local {
      try copy(jdk.appendingPathComponent("lib"), app.appendingPathComponent("lib"))
    } else {
      try copy(
        path(".build/openjdk/java.base-\(value)/java.base"),
        app.appendingPathComponent("lib/modules/java.base"))
    }
    let compile = [
      "xcrun", "clang", "-target", p.target, "-isysroot", try sdk(p.sdk), "-fobjc-arc", "-fmodules",
    ]
    let frame = path(".build/Tsunagu.xcframework/\(p.slice)").path
    try run(
      compile + [
        "-I\(jdk.path)/Headers", "-c", "native/TSJavaRuntime.m", "-o",
        output.appendingPathComponent("TSJavaRuntime.o").path,
      ])
    try run(
      compile + [
        "-I\(ff.path)/include", "-F\(frame)", "-c", "native/TSVideoEngine.m", "-o",
        output.appendingPathComponent("TSVideoEngine.o").path,
      ])
    try run(
      ["xcrun", "libtool", "-static", "-o", output.appendingPathComponent("libtsmedia.a").path]
        + contents(ff.appendingPathComponent("lib"), suffix: ".a").map(\.path))
    try run([
      "xcrun", "libtool", "-static", "-o", output.appendingPathComponent("libtsunagu.a").path,
      output.appendingPathComponent("TSJavaRuntime.o").path,
      output.appendingPathComponent("TSVideoEngine.o").path, frame + "/Tsunagu.framework/Tsunagu",
      jdk.appendingPathComponent(archive).path,
    ])
    try run(
      compile + [
        "-Inative", "-F\(frame)", "tests/NativeProbe.m", "-Wl,-export_dynamic",
        "-Wl,-force_load,\(output.path)/libtsunagu.a",
        output.appendingPathComponent("libtsmedia.a").path, "-framework", "UIKit",
      ] + frameworks + [
        "-lresolv", "-lz", "-lxml2", "-lc++", "-o",
        app.appendingPathComponent("MokuBackendProbe").path,
      ])
    let plist: [String: Any] = [
      "CFBundleIdentifier": "org.moku.backendprobe", "CFBundleExecutable": "MokuBackendProbe",
      "CFBundleName": "MokuBackendProbe", "CFBundleVersion": "1",
      "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL",
      "MinimumOSVersion": "18.2", "UIDeviceFamily": [1],
      "NSAppTransportSecurity": ["NSAllowsLocalNetworking": true],
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
      to: app.appendingPathComponent("Info.plist"))
    try run(["codesign", "--force", "--sign", "-", app.path])
  }
}
