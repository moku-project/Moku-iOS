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
  public func run(
    _ args: [String], capture: Bool = false, environment: [String: String] = [:], cwd: URL? = nil,
    timeout: TimeInterval? = nil
  ) throws -> String {
    String(
      decoding: try runData(
        args, capture: capture, environment: environment, cwd: cwd, timeout: timeout), as: UTF8.self
    )
  }

  public func runData(
    _ args: [String], capture: Bool = true, environment: [String: String] = [:], cwd: URL? = nil,
    timeout: TimeInterval? = nil
  ) throws -> Data {
    guard !cancelled else { throw CLIError("Interrupted") }
    guard !args.isEmpty else { throw CLIError("Missing executable") }
    var attributes: posix_spawnattr_t?
    var actions: posix_spawn_file_actions_t?
    posix_spawnattr_init(&attributes)
    posix_spawn_file_actions_init(&actions)
    defer {
      posix_spawnattr_destroy(&attributes)
      posix_spawn_file_actions_destroy(&actions)
    }
    posix_spawnattr_setflags(
      &attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
    posix_spawnattr_setpgroup(&attributes, 0)
    var signals = sigset_t()
    sigemptyset(&signals)
    sigaddset(&signals, SIGINT)
    sigaddset(&signals, SIGTERM)
    posix_spawnattr_setsigdefault(&attributes, &signals)
    sigemptyset(&signals)
    posix_spawnattr_setsigmask(&attributes, &signals)
    posix_spawn_file_actions_addchdir_np(&actions, (cwd ?? root).path)
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var fd: Int32 = -1
    if capture {
      fd = open(temporary.path, O_CREAT | O_EXCL | O_RDWR, 0o600)
      guard fd >= 0 else { throw CLIError("Cannot create command output file") }
      posix_spawn_file_actions_adddup2(&actions, fd, STDOUT_FILENO)
      posix_spawn_file_actions_addclose(&actions, fd)
    }
    defer {
      if fd >= 0 {
        close(fd)
        try? FileManager.default.removeItem(at: temporary)
      }
    }
    let env = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    // /usr/bin/env resolves the command using the child's PATH, without a shell.
    let command = ["/usr/bin/env"] + args
    let argv = command.map { strdup($0) } + [nil]
    let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
      argv.forEach { free($0) }
      envp.forEach { free($0) }
    }
    var pid: pid_t = 0
    let code = argv.withUnsafeBufferPointer { ap in
      envp.withUnsafeBufferPointer { ep in
        posix_spawn(&pid, "/usr/bin/env", &actions, &attributes, ap.baseAddress!, ep.baseAddress!)
      }
    }
    guard code == 0 else {
      throw CLIError("Could not start \(args[0]): \(String(cString: strerror(code)))")
    }
    var status: Int32 = 0
    let started = Date()
    while true {
      let result = waitpid(pid, &status, WNOHANG)
      if result == pid { break }
      if result < 0 && errno != EINTR { throw CLIError("waitpid failed") }
      if cancelled || timeout.map({ Date().timeIntervalSince(started) >= $0 }) == true {
        kill(-pid, SIGINT)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
          if waitpid(pid, &status, WNOHANG) == pid {
            kill(-pid, SIGKILL)
            throw CLIError(cancelled ? "Interrupted" : "Command timed out: \(args[0])")
          }
          Thread.sleep(forTimeInterval: 0.05)
        }
        kill(-pid, SIGKILL)
        waitpid(pid, &status, 0)
        throw CLIError(cancelled ? "Interrupted" : "Command timed out: \(args[0])")
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    guard status == 0 else { throw CLIError("\(args[0]) failed (status \(status))") }
    return capture ? try Data(contentsOf: temporary) : Data()
  }

  public static func findRoot(
    _ explicit: String? = nil,
    start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) throws -> URL {
    func valid(_ root: URL) -> Bool {
      FileManager.default.fileExists(atPath: root.appendingPathComponent("project.yml").path)
        && FileManager.default.fileExists(
          atPath: root.appendingPathComponent("Services/go.mod").path)
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
