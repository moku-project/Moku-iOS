import Foundation

extension NativeBuild {
  func acceptance(_ simulator: String, live: Bool, budget: Double = 5) throws {
    let output = path(".build/last-acceptance.json")
    try remove(output)
    try remove(output.deletingPathExtension().appendingPathExtension("xml"))
    var suite: AcceptanceSuite?
    do {
      try require(budget > 0, "Search budget must be positive")
      _ = try? run(
        ["xcrun", "simctl", "terminate", simulator, "org.moku.backendprobe"], capture: true)
      try run([
        "xcrun", "simctl", "install", simulator,
        path(".build/native-simulator/MokuBackendProbe.app").path,
      ])
      let container = try run(
        ["xcrun", "simctl", "get_app_container", simulator, "org.moku.backendprobe", "data"],
        capture: true)
      let documents = URL(fileURLWithPath: container).appendingPathComponent("Documents")
      try mkdir(documents)
      let connection = documents.appendingPathComponent("acceptance-connection.json")
      let stop = documents.appendingPathComponent("acceptance-stop")
      let probe = documents.appendingPathComponent("probe.json")
      for file in [connection, stop, probe] { try remove(file) }
      defer {
        try? write("", stop)
        let deadline = Date().addingTimeInterval(8)
        while FileManager.default.fileExists(atPath: connection.path) && Date() < deadline {
          Thread.sleep(forTimeInterval: 0.2)
        }
        // Cleanup needs its own uncancelled runner after Ctrl-C.
        _ = try? Runner(root: runner.root).run(
          ["xcrun", "simctl", "terminate", simulator, "org.moku.backendprobe"], capture: true)
        try? remove(connection)
        try? remove(stop)
      }
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "moku-acceptance-" + UUID().uuidString)
      try mkdir(root)
      defer { try? remove(root) }
      let website = try FixtureWebsite(root)
      defer { website.close() }
      let fixtures = AcceptanceFixtures(runner, website)
      try fixtures.build()
      let start = Date()
      for file in [".build/acceptance-runtime.log", ".build/acceptance-runtime-error.log"] {
        try remove(path(file))
      }
      try run([
        "xcrun", "simctl", "launch", "--stdout=" + path(".build/acceptance-runtime.log").path,
        "--stderr=" + path(".build/acceptance-runtime-error.log").path, simulator,
        "org.moku.backendprobe", "--acceptance",
      ])
      try waitUntil(120, runner: runner) {
        if FileManager.default.fileExists(atPath: probe.path) {
          throw CLIError(
            "Probe startup failed; inspect Services/.build/acceptance-runtime-error.log")
        }
        return FileManager.default.fileExists(atPath: connection.path)
      }
      let info = try JSON(file: connection)
      let directory = try confined(
        documents.appendingPathComponent(info["dataDirectory"].s), to: documents)
      let checks = try AcceptanceSuite(
        api: BackendAPI(info), website: website, output: output, directory: directory,
        runner: runner)
      suite = checks
      checks.results.append([
        "name": "runtime.startup", "status": "PASS", "seconds": Date().timeIntervalSince(start),
      ])
      try checks.run(budget: budget)
      func jvm(_ name: String, args: [String] = [], timeout: Double = 180) throws {
        let report = root.appendingPathComponent(name + ".json")
        try run(
          [
            fixtures.jdk.appendingPathComponent("java").path, "-cp",
            fixtures.classes.path + ":" + fixtures.sandbox.path, "JvmContract", connection.path,
            report.path,
          ] + args, capture: true, timeout: timeout)
        let rows = try JSON(file: report).a
        try require(!rows.isEmpty, "JVM report has no checks")
        for row in rows {
          checks.results.append(row.object)
          print("\(row["status"].s) \(row["name"].s)")
        }
        try require(rows.allSatisfy { $0["status"].s == "PASS" }, "JVM contract failed")
      }
      try checks.check("jvm.contract_runner") { try jvm("jvm-results") }
      try checks.check("lifecycle.app_restart_offline_content_library_policies") {
        for kind in ["manga", "anime", "novel"] { try checks.download(kind, keep: true) }
        let oldToken = checks.api.token
        try write("", stop)
        try waitUntil(10, runner: runner) {
          !FileManager.default.fileExists(atPath: connection.path)
        }
        try run(["xcrun", "simctl", "terminate", simulator, "org.moku.backendprobe"])
        try remove(stop)
        website.offline = true
        defer { website.offline = false }
        let launched = try run(
          [
            "xcrun", "simctl", "launch", simulator, "org.moku.backendprobe", "--acceptance",
            "--resume-acceptance", info["dataDirectory"].s,
          ], capture: true)
        try waitUntil(120, runner: runner) {
          FileManager.default.fileExists(atPath: connection.path)
        }
        checks.api = try BackendAPI(JSON(file: connection))
        try require(checks.api.token != oldToken, "Restart reused bearer credential")
        for kind in ["manga", "anime", "novel"] {
          let (_, chapter) = try checks.chapter(kind)
          try require(
            try checks.api.gql(
              "query($id:ID!){chapter(id:$id){downloaded}}", ["id": chapter["id"].s])["chapter"][
                "downloaded"
              ].b, "Download flag lost after restart")
          try checks.offlineContent(kind)
        }
        let rows = try checks.api.gql("{library{items{id}}}")["library"]["items"].a
        try require(
          rows.contains { $0["id"].s == checks.media["manga"]?["id"].s }, "Library lost on relaunch"
        )
        let prefs = try checks.api.gql(
          "{sourcePreferences(extensionId:\"org.moku.acceptance.manga\"){key currentValue}}")[
            "sourcePreferences"
          ].a
        try require(
          prefs.count == 1 && prefs[0]["key"].s == "fixture_option"
            && prefs[0]["currentValue"].s == "custom", "Preferences lost on relaunch")
        let policy = try checks.api.request("/api/mobile/automation?mediaId=0")
        try require(
          policy.status == 200 && JSON(data: policy.body)["downloadAhead"].n == 2,
          "Policy lost on relaunch")
        try jvm("restored-cookie-results", args: ["cookies-restored"], timeout: 30)
        if let pid = launched.split(separator: ":").last,
          let number = Int(pid.trimmingCharacters(in: .whitespacesAndNewlines))
        {
          print(
            "Fresh process RSS KiB: \(try run(["ps", "-o", "rss=", "-p", String(number)], capture: true))"
          )
        }
      }
      try checks.check("library.source_migration_progress_folders_policies_filters") {
        try checks.migration()
      }
      if live {
        let package = "eu.kanade.tachiyomi.extension.all.mangadex"
        var found: JSON?
        try checks.check("live.mangadex.repository") {
          _ = try checks.api.gql(
            "mutation{addRepository(indexUrl:\"https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb\"){id}}"
          )
        }
        try checks.check("live.mangadex.install") {
          try require(
            try checks.api.gql(
              "mutation($p:String!){installExtension(packageName:$p){installed}}", ["p": package])[
                "installExtension"]["installed"].b, "Live extension not installed")
        }
        try checks.check("live.mangadex.search") {
          let rows = try checks.api.gql(
            "query($e:ID!){search(extensionId:$e,query:\"Rent a Girlfriend\",page:1){results{id externalId title thumbnailUrl}}}",
            ["e": package])["search"]["results"].a
          found = rows.first { $0["title"].s.lowercased() == "rent-a-girlfriend" }
          try require(found != nil, "Exact live title not found")
        }
        try checks.check("live.mangadex.cover_bytes") {
          guard let found else { throw Blocked(description: "Live search failed") }
          let response = try checks.api.request("/proxy/cover/" + found["id"].s)
          try require(
            response.status == 200 && (response.headers["content-type"] ?? "").hasPrefix("image/")
              && response.body.count > 100, "Live cover bytes not served")
          try require(
            [
              Data([255, 216, 255]), Data([137, 80, 78, 71]), Data("RIFF".utf8), Data("GIF8".utf8),
            ].contains { response.body.starts(with: $0) }, "Cover response is not an image")
        }
        try checks.check("live.mangadex.metadata_runner") {
          guard let found else { throw Blocked(description: "Live search failed") }
          try jvm("live-jvm-results", args: [package, found["externalId"].s], timeout: 100)
        }
      }
      checks.complete = true
      try checks.save()
      let failures = checks.results.filter { $0["status"] as? String != "PASS" }.count
      print(
        "\(checks.results.count - failures)/\(checks.results.count) passed. JSON: \(output.path)")
      try require(failures == 0, "Backend acceptance suite failed")
    } catch {
      var rows = suite?.results ?? []
      rows.append([
        "name": "runtime.runner", "status": "FAIL", "detail": String(describing: error),
        "seconds": 0,
      ])
      try AcceptanceSuite.save(rows, complete: false, to: output)
      throw error
    }
  }
  func nativeProbe(_ simulator: String, mode: String) throws {
    _ = try? run(
      ["xcrun", "simctl", "terminate", simulator, "org.moku.backendprobe"], capture: true)
    try run([
      "xcrun", "simctl", "install", simulator,
      path(".build/native-simulator/MokuBackendProbe.app").path,
    ])
    let container = try run(
      ["xcrun", "simctl", "get_app_container", simulator, "org.moku.backendprobe", "data"],
      capture: true)
    let file = URL(fileURLWithPath: container).appendingPathComponent("Documents/probe.json")
    try remove(file)
    try run(["xcrun", "simctl", "launch", simulator, "org.moku.backendprobe", "--" + mode])
    var report = JSON()
    try waitUntil(300, runner: runner) {
      guard let parsed = try? JSON(file: file) else { return false }
      report = parsed
      try require(report["backendError"].isNull, "Native backend probe failed")
      return mode != "jvm" || !report["jvm"].isNull
    }
    for key in ["repository", "extensions"] {
      try require(
        report[key]["errors"].isNull || report[key]["errors"].a.isEmpty, "GraphQL returned errors")
    }
    try require(
      report["extensions"]["data"]["extensions"]["items"].a.contains {
        $0["packageName"].s == "eu.kanade.tachiyomi.extension.all.mangadex"
      }, "MangaDex missing from live catalog")
    if mode == "search" {
      for key in ["installation", "search"] {
        try require(
          report[key]["errors"].isNull || report[key]["errors"].a.isEmpty,
          "Installation/search errors")
      }
      try require(
        report["installation"]["data"]["installExtension"]["installed"].b,
        "MangaDex was not installed")
      try require(
        report["search"]["data"]["search"]["results"].a.contains {
          $0["title"].s.lowercased() == "rent-a-girlfriend"
        }, "Requested title missing")
      let directory = try confined(
        file.deletingLastPathComponent().appendingPathComponent(report["dataDirectory"].s),
        to: file.deletingLastPathComponent())
      let packages = try contents(directory.appendingPathComponent("jar-cache")).filter {
        $0.lastPathComponent.hasPrefix("eu.kanade.tachiyomi.extension.all.mangadex-")
          && ["apk", "jar"].contains($0.pathExtension)
      }
      try require(packages.count == 1, "Expected one downloaded MangaDex package")
      let names = try run(["unzip", "-Z1", packages[0].path], capture: true).split(separator: "\n")
        .map(String.init)
      try require(
        packages[0].pathExtension == "jar"
          ? names.contains { $0.hasSuffix(".class") }
          : names.contains("AndroidManifest.xml") && names.contains("classes.dex"),
        "Package missing executable classes")
      var result = report.object
      result["download"] =
        [
          "file": packages[0].lastPathComponent, "bytes": try Data(contentsOf: packages[0]).count,
          "sha256": try sha256File(packages[0]),
        ] as [String: Any]
      try JSON(result).save(path(".build/last-search.json"))
    } else if mode == "jvm" {
      try require(
        report["jvm"].s.contains("dynamic JAR class loading and reflection: PASS")
          && report["jvm"].s.contains("app-owned NIO temp cache: PASS"), "JVM probe failed")
    }
    print("Native \(mode) probe: PASS")
  }
}
