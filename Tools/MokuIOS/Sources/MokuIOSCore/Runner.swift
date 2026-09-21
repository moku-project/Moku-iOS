import Darwin
import Foundation

public final class Runner {
  public let root: URL
  private let lock = NSLock()
  private var interrupted = false
  public init(root: URL) { self.root = root }
  public var cancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return interrupted
  }
  public func cancel() {
    lock.lock()
    interrupted = true
    lock.unlock()
  }
  public func path(_ value: String) -> URL { root.appendingPathComponent(value) }

  @discardableResult
  public func run(_ args: [String], capture: Bool = false, environment: [String: String] = [:])
    throws -> String
  {
    guard !cancelled else { throw CLIError("Interrupted") }
    let process = Process()
    // Start a separate process group so cancellation also reaches shell grandchildren.
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", "setpgrp(0,0); exec @ARGV or die $!;", "--"] + args
    process.currentDirectoryURL = root
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var output: FileHandle?
    if capture {
      FileManager.default.createFile(atPath: temporary.path, contents: nil)
      output = try FileHandle(forWritingTo: temporary)
      process.standardOutput = output
    }
    defer {
      try? output?.close()
      try? FileManager.default.removeItem(at: temporary)
    }
    try process.run()
    while process.isRunning {
      if cancelled {
        kill(-process.processIdentifier, SIGINT)
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        kill(-process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        throw CLIError("Interrupted")
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CLIError("\(args.joined(separator: " ")) exited with \(process.terminationStatus)")
    }
    return capture ? String(decoding: try Data(contentsOf: temporary), as: UTF8.self) : ""
  }

  public static func findRoot(
    _ explicit: String? = nil,
    start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) throws -> URL {
    func valid(_ root: URL) -> Bool {
      FileManager.default.fileExists(atPath: root.appendingPathComponent("project.yml").path)
        && FileManager.default.fileExists(
          atPath: root.appendingPathComponent("services/go.mod").path)
    }
    if let explicit = explicit ?? ProcessInfo.processInfo.environment["MOKU_IOS_DIR"] {
      let root = URL(fileURLWithPath: explicit).standardizedFileURL
      guard valid(root) else { throw CLIError("Not a Moku-iOS checkout: \(explicit)") }
      return root
    }
    var root = start.standardizedFileURL
    while true {
      if valid(root) { return root }
      let parent = root.deletingLastPathComponent()
      if parent == root { break }
      root = parent
    }
    throw CLIError("Run ./moku-ios from the iOS checkout or pass --repo PATH.")
  }
}
