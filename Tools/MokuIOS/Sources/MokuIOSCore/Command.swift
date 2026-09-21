import Foundation

public struct CLIError: Error, CustomStringConvertible {
  public let description: String
  public init(_ message: String) { description = message }
}

public struct Command {
  public var name = "help"
  public var task: String?
  public var platform = "simulator"
  public var simulator: String?
  public var repo: String?
  public var fix = false

  public init(_ arguments: [String]) throws {
    var args = arguments.makeIterator()
    var named = false
    var platformSeen = false
    while let arg = args.next() {
      switch arg {
      case "--help", "-h":
        name = "help"
        return
      case "--repo", "--platform", "--simulator":
        guard let value = args.next(), !value.hasPrefix("-") else {
          throw CLIError("\(arg) needs a value")
        }
        if arg == "--repo", repo == nil {
          repo = value
        } else if arg == "--platform", !platformSeen, ["build", "backend"].contains(name),
          ["simulator", "device"].contains(value)
        {
          platform = value
          platformSeen = true
        } else if arg == "--simulator", simulator == nil, ["dev", "run", "test"].contains(name) {
          simulator = value
        } else {
          throw CLIError("Invalid or repeated \(arg)")
        }
      case "--fix":
        guard name == "format", !fix else { throw CLIError("--fix is only valid once with format") }
        fix = true
      default:
        if !named {
          guard
            [
              "dev", "run", "build", "backend", "test", "simulators", "generate", "format",
              "doctor", "embed-backend", "help",
            ].contains(arg)
          else { throw CLIError("Unknown command '\(arg)'. Run ./moku-ios help.") }
          name = arg
          named = true
        } else {
          let choices =
            name == "backend"
            ? ["all", "go", "jvm", "sandbox", "native"]
            : name == "test"
              ? [
                "unit", "ui", "live-ui", "backend", "acceptance", "acceptance-live", "search",
                "jvm", "cli", "all",
              ] : []
          guard task == nil, choices.contains(arg) else {
            throw CLIError("Unexpected argument '\(arg)' for \(name)")
          }
          task = arg
        }
      }
    }
  }

  public static let help = """
    Moku iOS development tool

    Usage: ./moku-ios [--repo PATH] <command>

      dev [--simulator UDID]        Build, launch, and watch saved changes
      run [--simulator UDID]        Build and launch once
      build [--platform simulator|device]
      backend [all|go|jvm|sandbox|native] [--platform simulator|device]
      test [unit|ui|live-ui|backend|acceptance|acceptance-live|search|jvm|cli|all]
           [--simulator UDID]
      simulators                   List available simulators
      generate                     Regenerate the Xcode project
      format [--fix]               Check or format app Swift sources
      doctor                       Check local tools and backend artifacts
      help

    The Swift tool lives in Tools/MokuIOS. No separate install or configure step.
    backend forces a rebuild; test defaults to unit. Live tests need network access.
    """
}
