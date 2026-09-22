import Foundation

/// Operates only on generated app-bundle resources, never application data.
enum RuntimePackaging {
  static func cleanBundle(_ output: URL, debugDylib: Bool) throws {
    try remove(output.appendingPathComponent("EmbeddedRuntime"))
    if !debugDylib {
      try remove(output.appendingPathComponent("Moku.debug.dylib"))
      try remove(output.appendingPathComponent("__preview.dylib"))
    }
  }

  static func syncRuntime(_ source: URL, to output: URL, runner: Runner) throws {
    try mkdir(output)
    // Dereference certificates/configuration links before entering the signed app bundle.
    // OpenJDK's _the.* files are make bookkeeping, not runtime resources.
    try runner.run([
      "rsync", "-a", "--copy-links", "--delete", "--delete-excluded", "--exclude=_the.*",
      source.path + "/", output.path + "/",
    ])
  }
}
