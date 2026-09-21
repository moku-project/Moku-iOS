import CryptoKit
import Foundation

func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() { throw CLIError(message) }
}
func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
func sha256File(_ url: URL) throws -> String {
  let file = try FileHandle(forReadingFrom: url)
  defer { try? file.close() }
  var hash = SHA256()
  while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
  return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
func mkdir(_ url: URL) throws {
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}
func write(_ text: String, _ url: URL) throws {
  try mkdir(url.deletingLastPathComponent())
  try Data(text.utf8).write(to: url, options: .atomic)
}
func remove(_ url: URL) throws {
  if FileManager.default.fileExists(atPath: url.path)
    || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
  {
    try FileManager.default.removeItem(at: url)
  }
}
func copy(_ from: URL, _ to: URL) throws {
  try mkdir(to.deletingLastPathComponent())
  try remove(to)
  try FileManager.default.copyItem(at: from.resolvingSymlinksInPath(), to: to)
}
func contents(_ url: URL, suffix: String? = nil) throws -> [URL] {
  try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).filter {
    suffix == nil || $0.lastPathComponent.hasSuffix(suffix!)
  }.sorted { $0.path < $1.path }
}
func recursiveFiles(_ root: URL) -> [URL] {
  guard
    let entries = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isRegularFileKey])
  else { return [] }
  return entries.compactMap { $0 as? URL }.filter {
    (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
  }
}
func confined(_ path: URL, to root: URL) throws -> URL {
  let path = path.resolvingSymlinksInPath().standardizedFileURL
  let root = root.resolvingSymlinksInPath().standardizedFileURL
  try require(path.path.hasPrefix(root.path + "/"), "Path escapes expected directory")
  return path
}
struct JSON {
  let raw: Any
  init(_ raw: Any = NSNull()) { self.raw = raw }
  init(data: Data) throws { raw = try JSONSerialization.jsonObject(with: data) }
  init(file: URL) throws { try self.init(data: Data(contentsOf: file)) }
  subscript(_ key: String) -> JSON { JSON((raw as? [String: Any])?[key] ?? NSNull()) }
  subscript(_ index: Int) -> JSON {
    let items = raw as? [Any] ?? []
    return JSON(items.indices.contains(index) ? items[index] : NSNull())
  }
  var s: String { raw as? String ?? "" }
  var b: Bool { raw as? Bool ?? false }
  var n: Double { (raw as? NSNumber)?.doubleValue ?? 0 }
  var a: [JSON] { (raw as? [Any] ?? []).map(JSON.init) }
  var object: [String: Any] { raw as? [String: Any] ?? [:] }
  var isNull: Bool { raw is NSNull }
  func data() throws -> Data {
    try JSONSerialization.data(
      withJSONObject: raw, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
  }
  func save(_ url: URL) throws {
    try mkdir(url.deletingLastPathComponent())
    try data().write(to: url, options: .atomic)
  }
}
func waitUntil(_ seconds: TimeInterval, runner: Runner, _ condition: () throws -> Bool) throws {
  let end = Date().addingTimeInterval(seconds)
  while try !condition() {
    try require(!runner.cancelled, "Interrupted")
    try require(Date() < end, "Timed out after \(seconds)s")
    Thread.sleep(forTimeInterval: 0.2)
  }
}
