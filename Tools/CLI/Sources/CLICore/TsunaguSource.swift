import Foundation

/// Tsunagu is built from a sibling checkout (../Tsunagu), the path Services/go.mod's `replace` also uses.
enum TsunaguSource {
  static let root = "../Tsunagu"
  static let backend = root + "/backend"
  static let sandbox = root + "/sandbox"
  static let proto = root + "/proto"
  static let sandboxJar = sandbox + "/build/libs/sandbox-0.6.0-all.jar"
  /// Inputs that change the sandbox jar.
  static let sandboxInputs = [
    sandbox + "/src", sandbox + "/build.gradle.kts", sandbox + "/settings.gradle.kts", proto,
  ]
}
