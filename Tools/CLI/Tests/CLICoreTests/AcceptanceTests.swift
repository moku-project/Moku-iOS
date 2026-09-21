import XCTest

@testable import CLICore

final class AcceptanceTests: XCTestCase {
  func temporary() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try mkdir(root)
    addTeardownBlock { try? remove(root) }
    return root
  }
  func testGraphQLErrorsAndNullDataFail() throws {
    for response: [String: Any] in [
      ["errors": [["message": "missing"]], "data": ["value": true]], ["data": NSNull()], [:],
    ] {
      XCTAssertThrowsError(try BackendAPI.graphQLData(JSON(response).data()))
    }
  }
  func testExternalURLAndRedirectNeverReceiveCredential() throws {
    let target = try FixtureWebsite(temporary())
    defer { target.close() }
    let redirect = try FixtureWebsite(temporary())
    defer { redirect.close() }
    redirect.custom = { _, _ in HTTPReply(status: 302, headers: ["Location": target.origin + "/"]) }
    let api = try BackendAPI(JSON(["baseURL": redirect.origin, "token": "private"]))
    XCTAssertThrowsError(try api.request("https://example.com/page.png"))
    XCTAssertThrowsError(try api.request(target.origin + "/"))
    XCTAssertEqual(try api.request("/").status, 302)
    XCTAssertTrue(target.requests.isEmpty)
  }
  func testBlockedChecksFailJUnit() throws {
    let root = try temporary()
    let output = root.appendingPathComponent("results.json")
    let website = try FixtureWebsite(root)
    defer { website.close() }
    let suite = try AcceptanceSuite(
      api: BackendAPI(JSON(["baseURL": website.origin, "token": "test"])), website: website,
      output: output, directory: root, runner: Runner(root: root))
    try suite.check("reader") { throw Blocked(description: "Details failed") }
    XCTAssertEqual(try JSON(file: output)["blocked"].n, 1)
    let xml = try XMLDocument(
      contentsOf: output.deletingPathExtension().appendingPathExtension("xml"))
    XCTAssertEqual(xml.rootElement()?.attribute(forName: "failures")?.stringValue, "1")
    XCTAssertEqual(try xml.nodes(forXPath: "//testcase/failure").count, 1)
  }
  func testExactAssetBytesRequired() throws {
    XCTAssertThrowsError(
      try AcceptanceSuite.validateAsset(
        HTTPReply(status: 200, headers: ["content-type": "image/png"], body: Data("wrong".utf8)),
        expected: fixturePNG(255, 0, 0), type: "image/png", status: 200))
  }
  func testOriginHeadersRangesOfflineAndTraversal() throws {
    let root = try temporary()
    try Data(0...255).write(to: root.appendingPathComponent("video.mp4"))
    let website = try FixtureWebsite(root)
    defer { website.close() }
    let api = try BackendAPI(JSON(["baseURL": website.origin, "token": "test"]))
    XCTAssertEqual(try api.request("/video.mp4").status, 403)
    let headers = [
      "Referer": website.origin + "/", "Cookie": "acceptance_session=ready",
      "Range": "bytes=128-255",
    ]
    let response = try api.request("/video.mp4", headers: headers)
    XCTAssertEqual(response.status, 206)
    XCTAssertEqual(response.body, Data(128...255))
    XCTAssertEqual(response.headers["content-range"], "bytes 128-255/256")
    XCTAssertEqual(website.response("/../private", headers: [:]).status, 404)
    website.offline = true
    XCTAssertEqual(try api.request("/video.mp4", headers: headers).status, 503)
  }
  func testBinaryManifestLayoutAndArchiveConfinement() throws {
    let data = try androidManifest("org.moku.acceptance.manga", "org.moku.acceptance.Manga")
    XCTAssertEqual(Array(data.prefix(4)), [3, 0, 8, 0])
    let size = data[4..<8].enumerated().reduce(0) { $0 + (Int($1.element) << ($1.offset * 8)) }
    XCTAssertEqual(size, data.count)
    XCTAssertEqual(sha256(data), "39e97b25ee6b5be4cede58b5016fb2144a3de1eede2be77b044710238a499662")
    let root = try temporary()
    XCTAssertThrowsError(try confined(root.appendingPathComponent("../escape"), to: root))
  }
  func testOversizedHTTPResponseFails() throws {
    let root = try temporary()
    try Data(repeating: 0, count: 16 * 1024 * 1024 + 1).write(
      to: root.appendingPathComponent("large.bin"))
    let server = try FixtureWebsite(root)
    defer { server.close() }
    let api = try BackendAPI(JSON(["baseURL": server.origin, "token": "test"]))
    XCTAssertThrowsError(try api.request("/large.bin"))
  }
  func testPinnedDownloadsRejectCorruptCache() throws {
    let root = try temporary()
    try mkdir(root.appendingPathComponent("Services"))
    let archive = root.appendingPathComponent("cached.bin")
    try Data("tampered".utf8).write(to: archive)
    let native = NativeBuild(Runner(root: root))
    XCTAssertThrowsError(
      try native.download(
        "https://invalid.example/unused", to: archive, hash: sha256(Data("expected".utf8))))
    try native.download(
      "https://invalid.example/unused", to: archive, hash: sha256(Data("tampered".utf8)))
  }
  func testPackagedJVMDataFilesDereferenceSymlinks() throws {
    let root = try temporary()
    let original = root.appendingPathComponent("original")
    let link = root.appendingPathComponent("cacerts")
    let packaged = root.appendingPathComponent("app/lib/security/cacerts")
    try write("certificate data", original)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
    try CLICore.copy(link, packaged)
    try remove(original)
    XCTAssertEqual(try String(contentsOf: packaged, encoding: .utf8), "certificate data")
    XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: packaged.path))
    try remove(link)
    XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: link.path))
  }
  func testPreparedSimulatorAcceptance() throws {
    guard let id = ProcessInfo.processInfo.environment["MOKU_ACCEPTANCE_SIMULATOR"] else {
      throw XCTSkip(
        "Set MOKU_ACCEPTANCE_SIMULATOR to run the prepared embedded-runtime integration suite")
    }
    let root = try Runner.findRoot()
    try NativeBuild(Runner(root: root)).acceptance(id, live: false)
  }
}
