import Foundation

extension AcceptanceSuite {
  func run(budget: Double) throws {
    try check("http.authentication") {
      try require(
        try api.request("/api/mobile/status", authenticated: false).status == 401,
        "Unauthenticated API accepted")
    }
    for (name, index) in [("fixture", "index.pb"), ("novel", "novels.json")] {
      try check("catalog.\(name)_repository") {
        _ = try api.gql(
          "mutation($url:String!){addRepository(indexUrl:$url){id}}",
          ["url": website.origin + "/" + index])
      }
    }
    for kind in ["manga", "anime", "novel"] {
      try check("\(kind).install") { try install(kind) }
      try check("\(kind).search") { try search(kind) }
      try check("\(kind).details_and_chapters") { try details(kind) }
      try check("\(kind).download_and_offline_bytes") { try download(kind) }
    }
    try check("extensions.repository_sync_and_update") {
      let path = website.root.appendingPathComponent("index.pb")
      let data = NSMutableData(data: try Data(contentsOf: path))
      let before = Data("1.0".utf8)
      let after = Data("1.1".utf8)
      var start = 0
      while start < data.length {
        let range = data.range(
          of: before, options: [], in: NSRange(location: start, length: data.length - start))
        if range.location == NSNotFound { break }
        after.withUnsafeBytes {
          data.replaceBytes(in: range, withBytes: $0.baseAddress!, length: after.count)
        }
        start = range.location + after.count
      }
      try (data as Data).write(to: path)
      _ = try api.gql("mutation{syncRepository(repositoryId:\"1\"){id}}")
      let ext = try api.gql(
        "mutation{updateExtension(packageName:\"org.moku.acceptance.manga\"){installed version installedVersion needsUpdate}}"
      )["updateExtension"]
      try require(
        ext["installed"].b && ext["installedVersion"].s == "1.1" && !ext["needsUpdate"].b,
        "Extension update did not finalize")
      try search("manga")
    }
    try check("images.extension_icon_bytes_and_cache") {
      let rows = try api.gql("{installedExtensions{packageName iconUrl}}")["installedExtensions"].a
      guard let icon = rows.first(where: { $0["packageName"].s == extensionID("manga") }),
        !icon["iconUrl"].s.isEmpty
      else { throw CLIError("Extension icon missing") }
      try asset(icon["iconUrl"].s, fixture("icon.png"), "image/png")
      website.offline = true
      defer { website.offline = false }
      try asset(icon["iconUrl"].s, fixture("icon.png"), "image/png")
    }
    try check("extensions.apk_conversion_and_execution") {
      _ = try api.gql(
        "mutation{uninstallExtension(packageName:\"org.moku.acceptance.manga\"){installed}}")
      try require(
        try api.gql(
          "mutation($url:String!){installExternalExtension(url:$url){installed}}",
          ["url": website.origin + "/manga.apk"])["installExternalExtension"]["installed"].b,
        "Converted APK not installed")
      try search("manga")
      try details("manga")
    }
    try check("manga.search_pagination") { try search("manga", page: 2) }
    try check("manga.search_empty") { try search("manga", query: "missing") }
    try check("manga.warm_search_latency_and_identity") {
      var samples: [Double] = []
      for _ in 0..<5 {
        let start = Date()
        try search("manga")
        samples.append(Date().timeIntervalSince(start))
      }
      try require(samples.max()! <= budget, "Warm search exceeded \(budget)s: \(samples)")
      print("Search samples: \(samples)")
    }
    for kind in ["manga", "anime", "novel"] {
      try check("\(kind).cover_bytes_and_cache") {
        guard let item = media[kind] else { throw Blocked(description: "Search failed") }
        let path = "/proxy/cover/" + item["id"].s
        try asset(path, fixture("cover.png"), "image/png")
        website.offline = true
        defer { website.offline = false }
        try asset(path, fixture("cover.png"), "image/png")
      }
    }
    try check("images.concurrent_cache_latency") {
      guard let item = media["manga"] else { throw Blocked(description: "Search failed") }
      let expected = try fixture("cover.png")
      let path = "/proxy/cover/" + item["id"].s
      let queue = OperationQueue()
      queue.maxConcurrentOperationCount = 8
      let lock = NSLock()
      var errors: [Error] = []
      var samples: [Double] = []
      for _ in 0..<32 {
        queue.addOperation {
          let start = Date()
          do {
            try self.asset(path, expected, "image/png")
            lock.lock()
            samples.append(Date().timeIntervalSince(start))
            lock.unlock()
          } catch {
            lock.lock()
            errors.append(error)
            lock.unlock()
          }
        }
      }
      queue.waitUntilAllOperationsAreFinished()
      if let error = errors.first { throw error }
      try require(samples.count == 32, "Concurrent requests incomplete")
      print("32 image requests / 8 workers; max \(samples.max()!)s")
    }
    try check("images.cover_override_and_invalidation") {
      guard let item = media["manga"] else { throw Blocked(description: "Search failed") }
      let path = "/proxy/cover/" + item["id"].s
      let file = website.root.appendingPathComponent("override.png")
      let yellow = try fixturePNG(255, 255, 0)
      let cyan = try fixturePNG(0, 255, 255)
      try yellow.write(to: file)
      _ = try api.gql(
        "mutation($id:ID!,$url:String){setMediaCover(mediaId:$id,url:$url){hasCoverOverride}}",
        ["id": item["id"].s, "url": website.origin + "/override.png"])
      try asset(path, yellow, "image/png")
      try cyan.write(to: file)
      try asset(path, yellow, "image/png")
      _ = try api.gql("mutation{clearImageCache}")
      try asset(path, cyan, "image/png")
      _ = try api.gql(
        "mutation($id:ID!){setMediaCover(mediaId:$id,url:null){hasCoverOverride}}",
        ["id": item["id"].s])
      try asset(path, fixture("cover.png"), "image/png")
    }
    try check("manga.reader_page_bytes") { try pages() }
    try check("anime.mp4_seek_hls_segments_and_subtitle_guard") { try stream() }
    try check("novel.chapter_text") { try novel() }
    try check("manga.cbz_download_and_offline_bytes") {
      _ = try api.gql(
        "mutation{updateServerSetting(key:\"manga_download_format\",value:\"cbz\"){__typename}}")
      do { try download("manga") } catch {
        _ = try? api.gql(
          "mutation{updateServerSetting(key:\"manga_download_format\",value:\"loose\"){__typename}}"
        )
        throw error
      }
      _ = try api.gql(
        "mutation{updateServerSetting(key:\"manga_download_format\",value:\"loose\"){__typename}}")
    }
    try check("administration.folders_backups_trackers_storage_policies") { try administration() }
    for (name, query) in [
      (
        "discovery.popular",
        "query{popularManga(extensionId:\"org.moku.acceptance.manga\"){results{id title}}}"
      ),
      (
        "discovery.latest",
        "query{latestUpdates(extensionId:\"org.moku.acceptance.manga\"){results{id title}}}"
      ),
      (
        "discovery.filters",
        "query{filterOptions(extensionId:\"org.moku.acceptance.manga\"){__typename}}"
      ),
      ("library.browse", "{library{total items{id}}}"),
    ] { try check(name) { _ = try api.gql(query) } }
    try check("library.save_and_reading_progress") { try libraryProgress() }
    try check("source.preferences") {
      let rows = try api.gql(
        "{sourcePreferences(extensionId:\"org.moku.acceptance.manga\"){key currentValue}}")[
          "sourcePreferences"
        ].a
      try require(
        rows.count == 1 && rows[0]["key"].s == "fixture_option"
          && rows[0]["currentValue"].s == "default", "Preference default lost")
      let updated = try api.gql(
        "mutation{setSourcePreference(extensionId:\"org.moku.acceptance.manga\",key:\"fixture_option\",value:\"custom\"){key currentValue}}"
      )["setSourcePreference"].a
      try require(
        updated.count == 1 && updated[0]["key"].s == "fixture_option"
          && updated[0]["currentValue"].s == "custom", "Preference write lost")
    }
  }
  func migration() throws {
    let (item, _) = try chapter("manga")
    let old = item["id"].s
    _ = try api.gql(
      "mutation{installExtension(packageName:\"org.moku.acceptance.alternate\"){installed}}")
    let folder = try api.gql("mutation{createFolder(name:\"Migration\"){id}}")["createFolder"]["id"]
      .s
    _ = try api.gql(
      "mutation($m:ID!,$f:ID!){addMediaToFolder(mediaId:$m,folderId:$f)}", ["m": old, "f": folder])
    try require(
      try api.request(
        "/api/mobile/automation?mediaId=" + old, payload: JSON(["downloadAhead": 3]).data(),
        method: "PUT"
      ).status == 204, "Source policy save failed")
    try require(
      try api.gql("query($id:ID!){media(id:$id){downloadedCount}}", ["id": old])["media"][
        "downloadedCount"
      ].n == 1, "Downloaded count mismatch")
    let migrated = try api.gql(
      "mutation($id:ID!){migrateMedia(fromMediaId:$id,toExtensionId:\"org.moku.acceptance.alternate\",toExternalId:\"/manga/series\"){id inLibrary folders{id} readingProgress{progress} chapters{id}}}",
      ["id": old])["migrateMedia"]
    try require(
      migrated["id"].s != old && migrated["inLibrary"].b, "Migration did not adopt target")
    try require(migrated["folders"].a.contains { $0["id"].s == folder }, "Migration lost folders")
    try require(
      migrated["readingProgress"].a.contains { $0["progress"].n == 0.5 }, "Migration lost progress")
    let policy = try api.request("/api/mobile/automation?mediaId=" + migrated["id"].s)
    try require(
      policy.status == 200 && JSON(data: policy.body)["downloadAhead"].n == 3,
      "Migration lost policy")
    let rows = try api.gql(
      "{library(filter:{contentType:MANGA,query:\"Acceptance\"},sort:{by:TITLE,ascending:true}){items{id}}}"
    )["library"]["items"].a
    try require(
      rows.count == 1 && rows[0]["id"].s == migrated["id"].s, "Library migration/filter mismatch")
  }
}
