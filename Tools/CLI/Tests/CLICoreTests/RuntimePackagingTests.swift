import XCTest

@testable import CLICore

final class RuntimePackagingTests: XCTestCase {
  func testBundleCleanupKeepsCurrentRuntimeAndAssets() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for path in [
      "EmbeddedRuntime/Sandbox.jar", "Moku.debug.dylib", "__preview.dylib", "Sandbox.jar",
      "Assets.car",
    ] {
      try write("fixture", root.appendingPathComponent(path))
    }
    try RuntimePackaging.cleanBundle(root, debugDylib: false)
    for path in ["EmbeddedRuntime", "Moku.debug.dylib", "__preview.dylib"] {
      XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
    }
    for path in ["Sandbox.jar", "Assets.car"] {
      XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
    }
  }

  func testRuntimeSyncDereferencesLinksAndRemovesBuildFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let output = root.appendingPathComponent("output")
    try write("class", source.appendingPathComponent("modules/java.base/Object.class"))
    try write(
      "build metadata",
      source.appendingPathComponent("modules/java.base/_the.java.base_batch.filelist"))
    try write("certificate", root.appendingPathComponent("certificate"))
    try FileManager.default.createSymbolicLink(
      atPath: source.appendingPathComponent("cacerts").path, withDestinationPath: "../certificate")
    try write("stale", output.appendingPathComponent("_the.old"))
    try RuntimePackaging.syncRuntime(source, to: output, runner: Runner(root: root))
    XCTAssertEqual(
      try String(contentsOf: output.appendingPathComponent("cacerts"), encoding: .utf8),
      "certificate")
    XCTAssertNil(
      try? FileManager.default.destinationOfSymbolicLink(
        atPath: output.appendingPathComponent("cacerts").path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: output.appendingPathComponent("modules/java.base/Object.class").path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: output.appendingPathComponent("modules/java.base/_the.java.base_batch.filelist")
          .path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: output.appendingPathComponent("_the.old").path))
  }
}
