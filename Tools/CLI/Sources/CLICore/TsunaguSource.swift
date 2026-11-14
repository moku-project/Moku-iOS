import Foundation

/// Tsunagu is built from a checkout next to this repository, as Moku-Android
/// does (`git clone https://github.com/moku-project/Tsunagu ../Tsunagu`).
/// Paths are relative to the Moku-iOS root. Services/go.mod's `replace`
/// line points at the same place.
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
