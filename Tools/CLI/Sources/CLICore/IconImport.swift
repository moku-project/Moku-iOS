import Foundation

extension NativeBuild {
  func importIcons() throws {
    let archive = path(".build/phosphor-svelte-3.1.0.tgz")
    let hash = "308250185e5ad1439f65d0929ae718e6f026b6fb8f176e2439743abbd7aee16d"
    try download(
      "https://registry.npmjs.org/phosphor-svelte/-/phosphor-svelte-3.1.0.tgz", to: archive,
      hash: hash)
    let root = path(".build/phosphor-import")
    try remove(root)
    try extract(archive, to: root)
    defer { try? remove(root) }
    let source = try Cache.files(runner.root, ["Moku"]).filter { $0.hasSuffix(".swift") }.map {
      try String(contentsOfFile: $0, encoding: .utf8)
    }.joined(separator: "\n")
    let expression = try NSRegularExpression(pattern: #""([A-Z][A-Za-z]*(?:\.fill)?)""#)
    let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
    let available = Set(
      try contents(root.appendingPathComponent("package/lib"), suffix: ".svelte").map {
        $0.deletingPathExtension().lastPathComponent
      })
    let used = Set(
      matches.compactMap {
        Range($0.range(at: 1), in: source).map {
          String(source[$0]).replacingOccurrences(of: ".fill", with: "")
        }
      }
    ).intersection(available).sorted()
    try require(!used.isEmpty, "No Phosphor icon references found")
    let assets = runner.path("Moku/Resources/Assets.xcassets/Phosphor")
    try JSON(["info": ["author": "xcode", "version": 1]]).save(
      assets.appendingPathComponent("Contents.json"))
    for name in used {
      let text = try String(
        contentsOf: root.appendingPathComponent("package/lib/\(name).svelte"), encoding: .utf8)
      let weights =
        ["MagnifyingGlass", "DownloadSimple"].contains(name)
        ? ["regular", "light", "fill", "bold"] : ["regular", "light", "fill"]
      for weight in weights {
        let regex = try NSRegularExpression(
          pattern: "(?:if|else if) weight === \"\(weight)\"\\}\\s*(.*?)\\s*\\{:",
          options: .dotMatchesLineSeparators)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text)
        else { throw CLIError("Missing icon weight \(name)/\(weight)") }
        let folder = assets.appendingPathComponent("\(name)-\(weight).imageset")
        try write(
          "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" width=\"256\" height=\"256\" fill=\"#000000\">\(text[range])</svg>\n",
          folder.appendingPathComponent("icon.svg"))
        try JSON([
          "images": [["filename": "icon.svg", "idiom": "universal"]],
          "info": ["author": "xcode", "version": 1],
          "properties": [
            "preserves-vector-representation": true, "template-rendering-intent": "template",
          ],
        ]).save(folder.appendingPathComponent("Contents.json"))
      }
    }
    try copy(
      root.appendingPathComponent("package/LICENSE"),
      runner.path("Moku/Resources/Phosphor-LICENSE.txt"))
    try JSON([
      "package": "phosphor-svelte", "version": "3.1.0", "sha256": hash, "icons": used,
      "weights": ["regular", "light", "fill"],
      "additionalWeights": ["MagnifyingGlass": ["bold"], "DownloadSimple": ["bold"]],
    ]).save(runner.path("Moku/Shared/Theme/phosphor-manifest.json"))
    print("Imported \(used.count) icon names; SHA256 \(hash)")
  }
}
