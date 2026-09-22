import Foundation

public final class Workflow {
  let runner: Runner
  let fm = FileManager.default
  public init(runner: Runner) { self.runner = runner }
  var native: NativeBuild { NativeBuild(runner) }
  func backend(_ platform: String, _ task: String, force: Bool) throws {
    try native.prepare()
    if ["all", "go", "native"].contains(task) {
      try Cache.cached(
        runner.root, "go",
        inputs: [
          "Services/binding.go", "Services/go.mod", "Services/go.sum",
          "Tools/CLI/Sources/CLICore/NativeBuild.swift", "Tools/CLI/Sources/CLICore/Support.swift",
          "vendor/Tsunagu/backend",
        ],
        outputs: [
          "Services/.build/Tsunagu.xcframework/ios-arm64/Tsunagu.framework/Tsunagu",
          "Services/.build/Tsunagu.xcframework/ios-arm64-simulator/Tsunagu.framework/Tsunagu",
        ], force: force && ["all", "go"].contains(task)
      ) { try native.go() }
    }
    if ["all", "jvm", "native"].contains(task) {
      try Cache.cached(
        runner.root, "jvm-\(platform)",
        inputs: [
          "Services/patches/0002-openjdk-ios.patch",
          "Services/patches/0003-openjdk-ios-debug-dylib.patch",
          "Tools/CLI/Sources/CLICore/NativeBuild.swift",
          "Tools/CLI/Sources/CLICore/Support.swift",
        ],
        outputs: [
          "Services/.build/openjdk-local/\(platform)/libopenjdk.a",
          "Services/.build/openjdk-local/\(platform)/lib/modules/java.base/java/lang/Object.class",
        ], force: force && ["all", "jvm"].contains(task)
      ) { try native.jvm(platform) }
    }
    if ["all", "sandbox", "native"].contains(task) {
      try Cache.cached(
        runner.root, "sandbox",
        inputs: [
          "vendor/Tsunagu/sandbox/src", "vendor/Tsunagu/sandbox/build.gradle.kts",
          "vendor/Tsunagu/sandbox/settings.gradle.kts", "vendor/Tsunagu/proto",
          "Tools/CLI/Sources/CLICore/NativeBuild.swift", "Tools/CLI/Sources/CLICore/Support.swift",
        ], outputs: ["vendor/Tsunagu/sandbox/build/libs/sandbox-0.1.0-all.jar"],
        force: force && ["all", "sandbox"].contains(task)
      ) { try native.sandbox() }
    }
    if ["all", "native"].contains(task) {
      let slice = platform == "device" ? "ios-arm64" : "ios-arm64-simulator"
      try Cache.cached(
        runner.root, "native-\(platform)",
        inputs: [
          "Services/native", "Services/java", "Services/tests",
          "Tools/CLI/Sources/CLICore/NativeBuild.swift", "Tools/CLI/Sources/CLICore/Support.swift",
          "Services/.build/Tsunagu.xcframework/\(slice)/Tsunagu.framework",
          "Services/.build/openjdk-local/\(platform)",
          "vendor/Tsunagu/sandbox/build/libs/sandbox-0.1.0-all.jar",
        ],
        outputs: [
          "Services/.build/native-\(platform)/libtsunagu.a",
          "Services/.build/native-\(platform)/libtsmedia.a",
          "Services/.build/native-\(platform)/MokuBackendProbe.app/MokuBackendProbe",
        ], force: force
      ) { try native.native(platform) }
    }
  }
  func project() throws {
    let membership = runner.path(".build/cli-state/swift/project-files.json")
    let data = try JSONEncoder().encode(
      Cache.files(
        runner.root, ["Moku", "Tests", "UITests", "Services/swift", "Tools/CLI/Sources", "Tools/CLI/Tests"]))
    if (try? Data(contentsOf: membership)) != data {
      try fm.createDirectory(
        at: membership.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: membership, options: .atomic)
    }
    try Cache.cached(
      runner.root, "project", inputs: ["project.yml", ".build/cli-state/swift/project-files.json"],
      outputs: ["Moku.xcodeproj/project.pbxproj"]
    ) { try runner.run(["xcodegen", "generate"]) }
  }
  func simulator(_ requested: String?) throws -> Simulator {
    let json = try runner.run(
      ["xcrun", "simctl", "list", "devices", "available", "-j"], capture: true)
    let selected = try Simulator.select(Simulator.devices(json), requested: requested)
    if selected.state != "Booted" { try runner.run(["xcrun", "simctl", "boot", selected.udid]) }
    try runner.run(["xcrun", "simctl", "bootstatus", selected.udid, "-b"])
    try runner.run(["open", "-a", "Simulator"])
    return selected
  }
  func xcode(
    _ platform: String, simulator: Simulator? = nil, action: String, extra: [String] = [],
    environment: [String: String] = [:]
  ) throws {
    let destination =
      simulator.map { "id=\($0.udid)" }
      ?? (platform == "device" ? "generic/platform=iOS" : "generic/platform=iOS Simulator")
    var args = [
      "xcodebuild", "-quiet", "-project", "Moku.xcodeproj", "-scheme", "Moku", "-configuration",
      "Debug", "-destination", destination, "-derivedDataPath", ".build/frontend",
    ]
    if platform == "simulator" { args.append("CODE_SIGNING_ALLOWED=NO") }
    var env = environment
    // Use the running binary in nested phases, avoiding a recursive SwiftPM build.
    env["MOKU_IOS_TOOL"] = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    try runner.run(args + extra + [action], environment: env)
  }
  func launch(_ device: Simulator) throws {
    try runner.run([
      "xcrun", "simctl", "install", device.udid,
      ".build/frontend/Build/Products/Debug-iphonesimulator/Moku.app",
    ])
    try runner.run([
      "xcrun", "simctl", "launch", "--terminate-running-process", device.udid, "com.moku.app",
    ])
  }
  func develop(_ command: Command) throws {
    let device = try simulator(command.simulator)
    print("Using \(device.name).")
    let watched = [
      "Moku", "Configuration", "project.yml", "Tests", "UITests", "Services/binding.go",
      "Services/go.mod", "Services/go.sum", "Services/swift", "Services/native", "Services/java",
      "Services/tests", "Services/patches", "Tools/CLI/Sources", "vendor/Tsunagu/backend",
      "vendor/Tsunagu/sandbox/src", "vendor/Tsunagu/sandbox/build.gradle.kts",
      "vendor/Tsunagu/sandbox/settings.gradle.kts", "vendor/Tsunagu/proto",
    ]
    var previous: [String: String]?
    while !runner.cancelled {
      let current = try Cache.snapshot(runner.root, watched)
      if previous != current {
        Thread.sleep(forTimeInterval: 0.4)
        previous = try Cache.snapshot(runner.root, watched)
        let start = Date()
        do {
          try backend("simulator", "all", force: false)
          try project()
          try xcode("simulator", simulator: device, action: "build")
          try launch(device)
          print(String(format: "Ready in %.1fs.", Date().timeIntervalSince(start)))
        } catch {
          if runner.cancelled || command.name == "run" { throw error }
          print("\(error). Save a change to retry.")
        }
        if command.name == "dev" { print("Watching for saves. Ctrl-C stops watching.") }
      }
      if command.name == "run" { return }
      Thread.sleep(forTimeInterval: 1)
    }
  }
  func embed() throws {
    let env = ProcessInfo.processInfo.environment
    guard let sdk = env["PLATFORM_NAME"], ["iphoneos", "iphonesimulator"].contains(sdk),
      let target = env["TARGET_BUILD_DIR"], !target.isEmpty,
      let resources = env["UNLOCALIZED_RESOURCES_FOLDER_PATH"], !resources.isEmpty
    else {
      throw CLIError(
        "embed-backend is an internal Xcode build phase; resource destination and iOS platform are required"
      )
    }
    let platform = sdk == "iphoneos" ? "device" : "simulator"
    let runtime = runner.path("Services/.build/openjdk-local/\(platform)/lib")
    let sandbox = runner.path("vendor/Tsunagu/sandbox/build/libs/sandbox-0.1.0-all.jar")
    for path in [
      runtime, sandbox, runner.path("Services/.build/native-\(platform)/libtsunagu.a"),
      runner.path("Services/.build/native-\(platform)/libtsmedia.a"),
    ] {
      guard fm.fileExists(atPath: path.path) else {
        throw CLIError("Missing \(path.path). Run ./moku-ios backend --platform \(platform)")
      }
    }
    let output = URL(fileURLWithPath: target).appendingPathComponent(resources)
    try RuntimePackaging.cleanBundle(output, debugDylib: env["ENABLE_DEBUG_DYLIB"] == "YES")
    let notices = output.appendingPathComponent("ThirdPartyNotices/FFmpeg")
    try fm.createDirectory(
      at: output.appendingPathComponent("lib"), withIntermediateDirectories: true)
    try fm.createDirectory(at: notices, withIntermediateDirectories: true)
    for name in ["COPYING.LGPLv2.1", "LICENSE.md"] {
      try runner.run([
        "rsync", "-a", runner.path("Services/.build/ffmpeg/\(platform)/\(name)").path,
        notices.appendingPathComponent(name).path,
      ])
    }
    try runner.run([
      "rsync", "-a", runner.path("Services/THIRD_PARTY_MEDIA.md").path,
      notices.appendingPathComponent("BUILD-AND-SOURCE.md").path,
    ])
    try RuntimePackaging.syncRuntime(runtime, to: output.appendingPathComponent("lib"), runner: runner)
    try runner.run(["rsync", "-a", sandbox.path, output.appendingPathComponent("Sandbox.jar").path])
    if let derived = env["DERIVED_FILE_DIR"] {
      try write("Runtime packaging complete\n", URL(fileURLWithPath: derived).appendingPathComponent("moku-runtime-embedded"))
    }
  }
  func test(_ task: String, _ requested: String?) throws {
    switch task {
    case "all":
      for item in ["cli", "backend", "unit", "ui", "search", "acceptance"] {
        try test(item, requested)
      }
    case "cli":
      try runner.run([
        "swift", "test", "--package-path", "Tools/CLI", "--scratch-path", ".build/cli",
      ])
    case "backend": try native.verify()
    case "video": try native.videoEngine()
    case "bridge": try native.bridge()
    default:
      try backend("simulator", "all", force: false)
      let device = try simulator(requested)
      if ["acceptance", "acceptance-live"].contains(task) {
        try native.acceptance(device.udid, live: task == "acceptance-live")
      } else if ["jvm", "search"].contains(task) {
        try native.nativeProbe(device.udid, mode: task)
      } else {
        try project()
        let target =
          task == "live-ui" ? "UITests/LiveSearchTests" : task == "ui" ? "UITests" : "Tests"
        try xcode(
          "simulator", simulator: device, action: "test", extra: ["-only-testing:\(target)"],
          environment: task == "live-ui" ? ["TEST_RUNNER_MOKU_LIVE_SEARCH": "1"] : [:])
      }
    }
  }
  func doctor() throws {
    print("Checkout: \(runner.root.path)")
    var missing = false
    for tool in [
      "swift", "xcodebuild", "xcrun", "xcodegen", "go", "javac", "make", "autoconf",
      "rsync", "curl", "tar", "zip", "unzip",
    ] {
      do {
        let path = try runner.run(["which", tool], capture: true)
        print("OK \(tool): \(path.trimmingCharacters(in: .whitespacesAndNewlines))")
      } catch {
        if runner.cancelled { throw error }
        print("MISSING \(tool)")
        missing = true
      }
    }
    let boot =
      ProcessInfo.processInfo.environment["MOKU_BOOT_JDK"] ?? "/opt/homebrew/opt/openjdk@25"
    let exists = fm.fileExists(atPath: boot + "/bin/java")
    missing = missing || !exists
    print("OpenJDK boot compiler: \(boot)\(exists ? "" : " (missing)")")
    for platform in ["simulator", "device"] {
      let ready = fm.fileExists(
        atPath: runner.path("Services/.build/native-\(platform)/libtsunagu.a").path)
      print("\(platform) archive: \(ready ? "ready" : "not built")")
    }
    if missing { throw CLIError("Install missing tools before building") }
  }
  public func execute(_ command: Command) throws {
    switch command.name {
    case "dev", "run": try develop(command)
    case "build":
      try backend(command.platform, "all", force: false)
      try project()
      try xcode(command.platform, action: "build")
    case "backend":
      switch command.task ?? "all" {
      case "prepare": try native.prepare()
      case "inputs": try native.fetchInputs()
      case "snapshot": try native.fetchSnapshot()
      case "package-jvm": try native.packageJVM(command.platform)
      case "ffmpeg": try native.ffmpeg(command.platform)
      default: try backend(command.platform, command.task ?? "all", force: true)
      }
    case "import-icons": try native.importIcons()
    case "video-device": try native.videoDevice(command.task!)
    case "generate": try runner.run(["xcodegen", "generate"])
    case "embed-backend": try embed()
    case "simulators": try runner.run(["xcrun", "simctl", "list", "devices", "available"])
    case "test": try test(command.task ?? "unit", command.simulator)
    case "format":
      var args = [
        "xcrun", "swift-format", command.fix ? "format" : "lint",
        command.fix ? "--in-place" : "--strict", "--recursive", "--configuration",
        "Configuration/swift-format.json", "Moku", "Tests",
      ]
      if fm.fileExists(atPath: runner.path("UITests").path) { args.append("UITests") }
      try runner.run(args)
    case "doctor": try doctor()
    default: print(Command.help)
    }
  }
}
