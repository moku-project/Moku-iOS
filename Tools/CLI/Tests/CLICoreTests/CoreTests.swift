import XCTest

@testable import CLICore

final class CoreTests: XCTestCase {
  func temporary() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return root
  }
  func testArguments() throws {
    XCTAssertEqual(try Command(["backend", "jvm", "--platform", "device"]).task, "jvm")
    XCTAssertEqual(
      try Command(["--repo", "/tmp/app", "dev", "--simulator", "chosen"]).simulator, "chosen")
    XCTAssertTrue(try Command(["format", "--fix"]).fix)
    for args in [
      ["run", "--platform", "device"], ["dev", "--simulator"], ["backend", "typo"],
      ["test", "unit", "ui"], ["format", "--fix", "--fix"], ["--repo", "a", "dev", "--repo", "b"],
    ] {
      XCTAssertThrowsError(try Command(args), "\(args)")
    }
  }
  func testSimulatorSelection() throws {
    let json =
      #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-9-0":[{"udid":"old","name":"iPhone A","state":"Shutdown"}],"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"new","name":"iPhone B","state":"Shutdown"}]}}"#
    let devices = try Simulator.devices(json)
    XCTAssertEqual(try Simulator.select(devices, requested: nil).udid, "new")
    XCTAssertEqual(try Simulator.select(devices, requested: "old").udid, "old")
    XCTAssertThrowsError(try Simulator.select(devices, requested: "missing"))
    XCTAssertThrowsError(
      try Simulator.select(
        [
          Simulator(udid: "a", name: "iPhone", state: "Booted"),
          Simulator(udid: "b", name: "iPhone", state: "Booted"),
        ], requested: nil))
  }
  func testCacheInvalidationAndFailures() throws {
    let root = try temporary()
    let input = root.appendingPathComponent("input")
    let output = root.appendingPathComponent("output")
    try Data("one".utf8).write(to: input)
    var count = 0
    func build() throws {
      try Cache.cached(root, "fixture", inputs: ["input"], outputs: ["output"]) {
        count += 1
        try Data("built".utf8).write(to: output)
      }
    }
    try build()
    try build()
    try Data("changed".utf8).write(to: input)
    try build()
    try FileManager.default.removeItem(at: input)
    try build()
    try FileManager.default.removeItem(at: output)
    try build()
    XCTAssertEqual(count, 4)
    XCTAssertThrowsError(try Cache.cached(root, "failure", inputs: [], outputs: ["missing"]) {})
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent(".build/cli-state/swift/failure.json").path))
  }
  func testEditsDuringBuildInvalidateCache() throws {
    let root = try temporary()
    let input = root.appendingPathComponent("input")
    try Data("before".utf8).write(to: input)
    try Cache.cached(root, "fixture", inputs: ["input"], outputs: ["output"]) {
      try Data("edited during build".utf8).write(to: input)
      try Data().write(to: root.appendingPathComponent("output"))
    }
    var rebuilt = false
    try Cache.cached(root, "fixture", inputs: ["input"], outputs: ["output"]) { rebuilt = true }
    XCTAssertTrue(rebuilt)
  }
  func testRunnerAndCancellation() throws {
    let runner = Runner(root: try temporary())
    XCTAssertEqual(try runner.run(["printf", "hello"], capture: true), "hello")
    XCTAssertThrowsError(try runner.run(["false"]))
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { runner.cancel() }
    let start = Date()
    XCTAssertThrowsError(try runner.run(["sleep", "30"]))
    XCTAssertLessThan(Date().timeIntervalSince(start), 5)
  }
  func testRootValidation() throws {
    let root = try temporary()
    XCTAssertThrowsError(try Runner.findRoot(root.path))
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Services"), withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("project.yml"))
    try Data().write(to: root.appendingPathComponent("Services/go.mod"))
    XCTAssertEqual(try Runner.findRoot(root.path).path, root.path)
  }
}
