import Foundation

public enum Cache {
  public static func files(_ root: URL, _ inputs: [String]) throws -> [String] {
    let fm = FileManager.default
    var result = Set<String>()
    func collect(_ url: URL) throws {
      guard fm.fileExists(atPath: url.path) else { return }
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      if values.isDirectory == true {
        if values.isSymbolicLink == true { return }
        for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
          if child.lastPathComponent.hasPrefix(".")
            || ["build", "target", "node_modules", "__pycache__"].contains(child.lastPathComponent)
          {
            continue
          }
          try collect(child)
        }
      } else {
        result.insert(url.path)
      }
    }
    for input in inputs { try collect(root.appendingPathComponent(input)) }
    return result.sorted()
  }
  public static func snapshot(_ root: URL, _ inputs: [String]) throws -> [String: String] {
    var result: [String: String] = [:]
    for path in try files(root, inputs) {
      let attributes = try FileManager.default.attributesOfItem(atPath: path)
      result[path] =
        "\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0):\(attributes[.size] ?? 0)"
    }
    return result
  }
  public static func cached(
    _ root: URL, _ label: String, inputs: [String], outputs: [String], force: Bool = false,
    action: () throws -> Void
  ) throws {
    let fm = FileManager.default
    let state = root.appendingPathComponent(".build/cli-state/swift/\(label).json")
    let current = try snapshot(root, inputs)
    let previous = (try? Data(contentsOf: state)).flatMap {
      try? JSONDecoder().decode([String: String].self, from: $0)
    }
    let paths = outputs.map { root.appendingPathComponent($0) }
    let complete = paths.allSatisfy { fm.fileExists(atPath: $0.path) }
    let oldest =
      paths.compactMap {
        try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      }.min() ?? .distantPast
    let newer = try files(root, inputs).contains { path in
      let modified =
        try URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate ?? .distantFuture
      return modified > oldest
    }
    if force || !complete || (previous.map { $0 != current } ?? newer) {
      print("Building \(label)…")
      try action()
      guard paths.allSatisfy({ fm.fileExists(atPath: $0.path) }) else {
        throw CLIError("\(label) finished without its expected outputs")
      }
    } else {
      print("Using cached \(label).")
    }
    try fm.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(current).write(to: state, options: .atomic)
  }
}
