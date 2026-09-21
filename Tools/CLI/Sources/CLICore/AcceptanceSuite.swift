import Foundation

struct Blocked: Error, CustomStringConvertible { let description: String }
final class AcceptanceSuite {
  var api: BackendAPI
  let website: FixtureWebsite
  let output: URL
  let directory: URL
  let runner: Runner
  var results: [[String: Any]] = []
  var media: [String: JSON] = [:]
  var complete = false
  init(api: BackendAPI, website: FixtureWebsite, output: URL, directory: URL, runner: Runner) {
    self.api = api
    self.website = website
    self.output = output
    self.directory = directory
    self.runner = runner
  }
  func check(_ name: String, _ action: () throws -> Void) throws {
    let start = Date()
    var row: [String: Any] = ["name": name]
    do {
      try action()
      row["status"] = "PASS"
    } catch {
      row["status"] = error is Blocked ? "BLOCKED" : "FAIL"
      row["detail"] = String(describing: error)
    }
    row["seconds"] = Date().timeIntervalSince(start)
    results.append(row)
    print("\(row["status"]!) \(name) \(row["detail"] ?? "")")
    try save()
    try require(!runner.cancelled, "Interrupted")
  }
  func save() throws { try Self.save(results, complete: complete, to: output) }
  static func save(_ results: [[String: Any]], complete: Bool, to output: URL) throws {
    let failed = results.filter { $0["status"] as? String == "FAIL" }.count
    let blocked = results.filter { $0["status"] as? String == "BLOCKED" }.count
    try JSON([
      "runtime": "iOS Simulator / embedded OpenJDK Zero + Go", "complete": complete,
      "results": results, "passed": results.count - failed - blocked, "failed": failed,
      "blocked": blocked,
    ]).save(output)
    let root = XMLElement(name: "testsuite")
    func attribute(_ node: XMLElement, _ name: String, _ value: String) {
      node.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }
    attribute(root, "name", "embedded-backend-parity")
    attribute(root, "tests", String(results.count))
    attribute(root, "failures", String(failed + blocked))
    for row in results {
      let node = XMLElement(name: "testcase")
      attribute(node, "name", row["name"] as? String ?? "unknown")
      attribute(node, "time", String(describing: row["seconds"] ?? 0))
      if row["status"] as? String != "PASS" {
        let failure = XMLElement(name: "failure", stringValue: row["detail"] as? String ?? "")
        attribute(failure, "type", row["status"] as? String ?? "FAIL")
        node.addChild(failure)
      }
      root.addChild(node)
    }
    try XMLDocument(rootElement: root).xmlData.write(
      to: output.deletingPathExtension().appendingPathExtension("xml"), options: .atomic)
  }
  func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: website.root.appendingPathComponent(name))
  }
  func asset(
    _ path: String, _ expected: Data, _ type: String, headers: [String: String] = [:],
    status: Int = 200
  ) throws {
    let response = try api.request(path, headers: headers)
    try Self.validateAsset(response, expected: expected, type: type, status: status)
  }
  static func validateAsset(_ response: HTTPReply, expected: Data, type: String, status: Int) throws
  {
    try require(response.status == status, "Asset HTTP \(response.status)")
    try require((response.headers["content-type"] ?? "").hasPrefix(type), "Incorrect content type")
    try require(response.body == expected, "Downloaded bytes differ from fixture")
  }
  func install(_ kind: String) throws {
    let result = try api.gql(
      "mutation($pkg:String!){installExtension(packageName:$pkg){installed contentType}}",
      ["pkg": extensionID(kind)])["installExtension"]
    try require(
      result["installed"].b && result["contentType"].s == kind.uppercased(),
      "Extension install/type mismatch")
  }
  func search(_ kind: String, page: Int = 1, query: String = "acceptance") throws {
    let result = try api.gql(
      "query($ext:ID!,$page:Int!,$q:String!){search(extensionId:$ext,query:$q,page:$page){results{id externalId title thumbnailUrl genres metadata{coverUrl}} hasNextPage}}",
      ["ext": extensionID(kind), "page": page, "q": query])["search"]
    if page == 1 && query != "missing" {
      try require(result["results"].a.count == 1, "Expected one fixture search result")
      let found = result["results"][0]
      try require(
        found["title"].s == "Acceptance " + kind.capitalized
          && found["externalId"].s == "/\(kind)/series", "Source title/ID mismatch")
      if let previous = media[kind] {
        try require(previous["id"].s == found["id"].s, "Repeated search created duplicate media")
      }
      media[kind] = JSON((media[kind]?.object ?? [:]).merging(found.object) { _, new in new })
    } else {
      try require(
        result["results"].raw is [Any] && result["results"].a.isEmpty
          && !result["hasNextPage"].isNull && !result["hasNextPage"].b,
        "Pagination/empty search mismatch")
    }
  }
  func details(_ kind: String) throws {
    let found = try api.gql(
      "query($ext:ID!,$external:String!){resolveMedia(extensionId:$ext,externalId:$external,syncChapters:true){id title description author genres chapters{id externalId number}}}",
      ["ext": extensionID(kind), "external": "/\(kind)/series"])["resolveMedia"]
    try require(
      found["description"].s == "A deterministic source description.", "Description missing")
    try require(
      found["author"].s == "Fixture Author" && found["genres"].a.contains { $0.s == "Adventure" },
      "Metadata missing")
    try require(
      found["chapters"].a.count == 1 && found["chapters"][0]["number"].n == 1,
      "Chapter/episode mapping failed")
    if let previous = media[kind] {
      try require(previous["id"].s == found["id"].s, "Details did not reuse search record")
    }
    media[kind] = found
  }
  func chapter(_ kind: String) throws -> (JSON, JSON) {
    guard let item = media[kind], !item["chapters"].a.isEmpty else {
      throw Blocked(description: "\(kind).details_and_chapters must pass before content tests")
    }
    return (item, item["chapters"][0])
  }
  func pages() throws {
    let (_, chapter) = try chapter("manga")
    let pages = try api.gql("query($id:ID!){chapter(id:$id){pages}}", ["id": chapter["id"].s])[
      "chapter"]["pages"].a
    try require(pages.count == 2, "Expected two reader page URLs")
    for (index, page) in pages.enumerated() {
      try asset(page.s, fixture("page-\(index + 1).png"), "image/png")
    }
  }
  func stream() throws {
    let (_, chapter) = try chapter("anime")
    let stream = try api.gql(
      "query($id:ID!){chapter(id:$id){videoStream{url sources{label url} subtitles{lang url}}}}",
      ["id": chapter["id"].s])["chapter"]["videoStream"]
    try require(stream["sources"].a.count == 3, "MP4/HLS/DASH sources missing")
    let sources = Dictionary(
      uniqueKeysWithValues: stream["sources"].a.map { ($0["label"].s, $0["url"].s) })
    guard let mp4 = sources["360p MP4"], let hls = sources["360p HLS"],
      let dash = sources["360p DASH"]
    else { throw CLIError("Missing stream variants") }
    let video = try fixture("video.mp4")
    try asset(mp4, video, "video/")
    try asset(
      mp4, video.subdata(in: 128..<256), "video/", headers: ["Range": "bytes=128-255"], status: 206)
    let playlist = try api.request(hls)
    try require(
      playlist.status == 200 && playlist.body.starts(with: Data("#EXTM3U".utf8)),
      "HLS playlist not delivered")
    let segments = String(decoding: playlist.body, as: UTF8.self).split(separator: "\n").filter {
      !$0.hasPrefix("#")
    }
    try require(segments.count == 1, "Unexpected fixture HLS playlist")
    guard let base = URL(string: hls, relativeTo: api.base),
      let segment = URL(string: String(segments[0]), relativeTo: base)
    else { throw CLIError("Invalid playlist URL") }
    try asset(segment.absoluteString, fixture("segment.ts"), "video/")
    let manifest = try api.request(dash)
    try require(manifest.status == 200, "DASH manifest not delivered")
    let doc = try XMLDocument(data: manifest.body)
    guard let baseText = try doc.nodes(forXPath: "//*[local-name()='BaseURL']").first?.stringValue,
      let dashURL = URL(string: dash, relativeTo: api.base),
      let proxy = URL(string: baseText, relativeTo: dashURL)
    else { throw CLIError("DASH proxy base missing") }
    for file in try contents(website.root, suffix: ".m4s") {
      let response = try api.request(
        proxy.appendingPathComponent(file.lastPathComponent).absoluteString)
      try require(
        response.status == 200 && response.body == Data(contentsOf: file),
        "DASH init/media bytes differ")
    }
    try require(!stream["subtitles"].a.isEmpty, "Subtitle URL missing")
    try require(
      try api.request(stream["subtitles"][0]["url"].s).status == 400,
      "Private subtitle target was not rejected")
  }
  func novel() throws {
    let (media, chapter) = try chapter("novel")
    let response = try api.request("/content/\(media["id"].s)/\(chapter["id"].s)/text")
    try require(
      response.status == 200 && response.body.range(of: Data("Acceptance novel text.".utf8)) != nil,
      "Novel body not delivered")
  }
  func libraryProgress() throws {
    let (item, chapter) = try chapter("manga")
    let id = item["id"].s
    try require(
      try api.gql(
        "mutation($id:ID!){setInLibrary(mediaId:$id,inLibrary:true){id inLibrary}}", ["id": id])[
          "setInLibrary"]["inLibrary"].b, "Save was not persisted")
    try require(
      try api.gql("{library{items{id}}}")["library"]["items"].a.contains { $0["id"].s == id },
      "Saved title absent from library")
    _ = try api.gql(
      "mutation($m:ID!,$c:ID!){updateReadingProgress(mediaId:$m,chapterId:$c,progress:0.5,completed:false){progress}}",
      ["m": id, "c": chapter["id"].s])
    let progress = try api.gql(
      "query($m:ID!){readingProgress(mediaId:$m){chapterId progress completed}}", ["m": id])[
        "readingProgress"
      ].a
    try require(
      progress.contains {
        $0["chapterId"].s == chapter["id"].s && $0["progress"].n == 0.5 && !$0["completed"].b
      }, "Reading progress not persisted")
  }
  func videoFrames(_ file: URL) throws -> String {
    let bytes = try runner.runData(
      [
        "ffmpeg", "-v", "error", "-i", file.path, "-map", "0:v:0", "-f", "rawvideo", "-pix_fmt",
        "rgb24", "-",
      ], timeout: 30)
    try require(bytes.count == 160 * 90 * 3 * 20, "Expected twenty complete fixture video frames")
    return sha256(bytes)
  }
  func offlineContent(_ kind: String) throws {
    let (item, chapter) = try chapter(kind)
    let prefix = "/content/\(item["id"].s)/\(chapter["id"].s)"
    if kind == "manga" {
      for index in 1...2 {
        try asset(prefix + "/pages/\(index)", fixture("page-\(index).png"), "image/png")
      }
    } else if kind == "anime" {
      let videos = recursiveFiles(directory.appendingPathComponent("media")).filter {
        $0.pathExtension == "mp4"
      }
      try require(videos.count == 1, "Expected one persisted episode")
      try asset(prefix + "/video", Data(contentsOf: videos[0]), "video/")
    } else {
      try novel()
    }
  }
  func download(_ kind: String, keep: Bool = false) throws {
    _ = try api.gql(
      "{downloadQueue{id status} downloaderStatus{isRunning queuedCount failedCount}}")
    let (item, chapter) = try chapter(kind)
    let variables: [String: Any] = ["m": item["id"].s, "c": [chapter["id"].s]]
    let rows = try api.gql(
      "mutation($m:ID!,$c:[ID!]!){enqueueDownload(mediaId:$m,chapterIds:$c){chapterId status}}",
      variables)["enqueueDownload"].a
    try require(
      rows.count == 1 && rows[0]["chapterId"].s == chapter["id"].s, "Wrong chapter enqueued")
    _ = try api.gql("mutation{startDownloader}")
    try waitUntil(45, runner: runner) {
      let row = try api.gql(
        "query($m:ID!,$c:ID!){downloadStatus(mediaId:$m,chapterId:$c){status progress error}}",
        ["m": item["id"].s, "c": chapter["id"].s])["downloadStatus"]
      try require(!row.isNull && row["status"].s != "FAILED", "Download failed")
      if row["status"].s == "DONE" {
        try require(row["progress"].n == 1, "DONE download is not at 100%")
        return true
      }
      return false
    }
    let files = recursiveFiles(directory.appendingPathComponent("media"))
    var persisted: [Data] = []
    for file in files {
      if ["cbz", "zip"].contains(file.pathExtension.lowercased()) {
        let names = try runner.run(["unzip", "-Z1", file.path], capture: true).split(
          separator: "\n")
        for name in names where !name.hasSuffix("/") {
          persisted.append(
            try runner.runData(["unzip", "-p", file.path, String(name)], timeout: 30))
        }
      } else {
        persisted.append(try Data(contentsOf: file))
      }
    }
    if kind == "manga" {
      for i in 1...2 {
        try require(
          try persisted.contains(fixture("page-\(i).png")), "Download did not persist both pages")
      }
    } else if kind == "anime" {
      let videos = files.filter { $0.pathExtension == "mp4" }
      try require(videos.count == 1, "Expected one persisted episode")
      try require(
        try videoFrames(videos[0]) == videoFrames(website.root.appendingPathComponent("video.mp4")),
        "Downloaded video differs")
    } else {
      try require(
        persisted.contains { $0.range(of: Data("Acceptance novel text.".utf8)) != nil },
        "Novel text was not persisted")
    }
    website.offline = true
    do {
      try offlineContent(kind)
      website.offline = false
    } catch {
      website.offline = false
      throw error
    }
    if !keep {
      _ = try api.gql(
        "mutation($m:ID!,$c:[ID!]!){deleteDownload(mediaId:$m,chapterIds:$c)}", variables)
      try require(
        try !api.gql("query($id:ID!){chapter(id:$id){downloaded}}", ["id": chapter["id"].s])[
          "chapter"]["downloaded"].b, "Deletion left chapter downloaded")
    }
  }
  func administration() throws {
    let (item, chapter) = try chapter("manga")
    let folder = try api.gql("mutation{createFolder(name:\"Acceptance Folder\"){id name}}")[
      "createFolder"]["id"].s
    _ = try api.gql(
      "mutation($m:ID!,$f:ID!){addMediaToFolder(mediaId:$m,folderId:$f)}",
      ["m": item["id"].s, "f": folder])
    try require(
      try api.gql("query($f:ID!){mediaInFolder(folderId:$f){id}}", ["f": folder])["mediaInFolder"].a
        .contains { $0["id"].s == item["id"].s }, "Folder membership missing")
    _ = try api.gql(
      "mutation($f:ID!){renameFolder(folderId:$f,name:\"Renamed\"){name} deleteFolder(folderId:$f)}",
      ["f": folder])
    let backup = try api.gql("mutation{createDatabaseBackup{name}}")["createDatabaseBackup"]["name"]
      .s
    let file = try confined(
      directory.appendingPathComponent("backups/" + backup),
      to: directory.appendingPathComponent("backups"))
    try require(FileManager.default.fileExists(atPath: file.path), "Snapshot file missing")
    _ = try api.gql("mutation($name:String!){deleteDatabaseBackup(name:$name)}", ["name": backup])
    try require(!FileManager.default.fileExists(atPath: file.path), "Backup deletion failed")
    let exported = try api.gql("mutation{exportMihonBackup{name}}")["exportMihonBackup"]["name"].s
    _ = try api.gql(
      "mutation($name:String!){importMihonBackup(name:$name){__typename}}", ["name": exported])
    _ = try api.gql(
      "{storageInfo{__typename} trackers{key isLoggedIn} contentFilterRules{__typename} serverSettings{key}}"
    )
    try require(
      try api.request(
        "/api/mobile/automation?mediaId=0",
        payload: JSON(["downloadAhead": 2, "deleteOnRead": false]).data(), method: "PUT"
      ).status == 204, "Policy save failed")
    let policy = try api.request("/api/mobile/automation?mediaId=0")
    try require(
      policy.status == 200 && JSON(data: policy.body)["downloadAhead"].n == 2,
      "Policy was not persisted")
    guard let mediaID = Int(item["id"].s), let chapterID = Int(chapter["id"].s) else {
      throw CLIError("Invalid numeric IDs")
    }
    try require(
      try api.request(
        "/api/mobile/chapter-open",
        payload: JSON(["mediaId": mediaID, "chapterId": chapterID]).data()
      ).status == 204, "Chapter-open failed")
  }
}
