import Darwin
import Foundation

struct HTTPReply {
  var status: Int
  var headers: [String: String] = [:]
  var body = Data()
}
final class HTTPCollector: NSObject, URLSessionDataDelegate {
  let done = DispatchSemaphore(value: 0)
  var result: Result<HTTPReply, Error>?
  private var bytes = Data()
  private var response: HTTPURLResponse?
  private var failure: Error?
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    self.response = response as? HTTPURLResponse
    if response.expectedContentLength > 16 * 1024 * 1024 {
      failure = CLIError("Response exceeded fixture size limit")
      completionHandler(.cancel)
    } else {
      completionHandler(.allow)
    }
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard bytes.count + data.count <= 16 * 1024 * 1024 else {
      failure = CLIError("Response exceeded fixture size limit")
      dataTask.cancel()
      return
    }
    bytes.append(data)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    defer { done.signal() }
    if let error = failure ?? error {
      result = .failure(error)
      return
    }
    guard let response else {
      result = .failure(CLIError("Missing HTTP response"))
      return
    }
    var fields: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
      fields[String(describing: key).lowercased()] = String(describing: value)
    }
    result = .success(HTTPReply(status: response.statusCode, headers: fields, body: bytes))
  }
}
final class BackendAPI {
  let base: URL
  let token: String
  init(_ connection: JSON) throws {
    guard let url = URL(string: connection["baseURL"].s), url.host == "127.0.0.1",
      url.scheme == "http"
    else { throw CLIError("Expected loopback backend URL") }
    base = url
    token = connection["token"].s
    try require(!token.isEmpty, "Missing backend credential")
  }
  func request(
    _ path: String, payload: Data? = nil, headers: [String: String] = [:],
    authenticated: Bool = true, method: String? = nil
  ) throws -> HTTPReply {
    guard let url = URL(string: path, relativeTo: base)?.absoluteURL, url.host == base.host,
      url.port == base.port, url.scheme == base.scheme, url.user == nil, url.password == nil
    else { throw CLIError("backend returned a non-local delivery URL") }
    var request = URLRequest(url: url, timeoutInterval: 45)
    request.httpMethod = method ?? (payload == nil ? "GET" : "POST")
    request.httpBody = payload
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    if authenticated { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    if payload != nil && request.value(forHTTPHeaderField: "Content-Type") == nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.connectionProxyDictionary = [:]
    configuration.httpCookieStorage = nil
    let collector = HTTPCollector()
    let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    session.dataTask(with: request).resume()
    guard collector.done.wait(timeout: .now() + 50) == .success, let result = collector.result
    else { throw CLIError("HTTP request timed out") }
    return try result.get()
  }
  func gql(_ query: String, _ variables: [String: Any] = [:]) throws -> JSON {
    let response = try request(
      "/api/graphql", payload: JSON(["query": query, "variables": variables]).data())
    try require(response.status == 200, "GraphQL HTTP \(response.status)")
    return try Self.graphQLData(response.body)
  }
  static func graphQLData(_ data: Data) throws -> JSON {
    let result = try JSON(data: data)
    try require(
      result["errors"].isNull || result["errors"].a.isEmpty && result["errors"].raw is [Any],
      "GraphQL returned errors")
    try require(result["data"].raw is [String: Any], "GraphQL returned no data")
    return result["data"]
  }
}

final class FixtureWebsite {
  let root: URL
  let origin: String
  private let socketFD: Int32
  private let lock = NSLock()
  private var stopped = false
  private var isOffline = false
  private var recorded: [String] = []
  var mediaMode = false
  var custom: ((String, [String: String]) -> HTTPReply)?
  var offline: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return isOffline
    }
    set {
      lock.lock()
      isOffline = newValue
      lock.unlock()
    }
  }
  var requests: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
  init(_ root: URL) throws {
    self.root = root
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    socketFD = fd
    guard socketFD >= 0 else { throw CLIError("Cannot create fixture socket") }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0, listen(socketFD, 64) == 0 else {
      Darwin.close(socketFD)
      throw CLIError("Cannot bind fixture server")
    }
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
    }
    guard named == 0 else {
      Darwin.close(socketFD)
      throw CLIError("Cannot inspect fixture port")
    }
    origin = "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))"
    DispatchQueue.global().async { [self] in
      while true {
        lock.lock()
        let closed = stopped
        lock.unlock()
        if closed { return }
        let client = accept(socketFD, nil, nil)
        if client < 0 { return }
        DispatchQueue.global().async { [self] in handle(client) }
      }
    }
  }
  func close() {
    lock.lock()
    if stopped {
      lock.unlock()
      return
    }
    stopped = true
    lock.unlock()
    shutdown(socketFD, SHUT_RDWR)
    Darwin.close(socketFD)
  }
  func response(_ rawPath: String, headers: [String: String]) -> HTTPReply {
    let path = String(rawPath.split(separator: "?", maxSplits: 1).first ?? "")
    lock.lock()
    recorded.append(path)
    lock.unlock()
    if let custom { return custom(path, headers) }
    if offline { return HTTPReply(status: 503) }
    if mediaMode && headers["x-source"] != "required" { return HTTPReply(status: 403) }
    let protected =
      path.hasSuffix(".mpd") || path.hasSuffix(".m4s") || path.hasPrefix("/page-")
      || [
        "/cover.png", "/video.mp4", "/master.m3u8", "/segment.ts", "/subtitles.vtt",
        "/novel-text.html",
      ].contains(path)
    if !mediaMode && protected
      && (headers["referer"] != origin + "/"
        || !(headers["cookie"] ?? "").contains("acceptance_session=ready"))
    {
      return HTTPReply(status: 403)
    }
    var filePath = path
    if mediaMode && path == "/slow.mp4" {
      Thread.sleep(forTimeInterval: 2)
      filePath = "/input.mp4"
    }
    let file = root.appendingPathComponent(
      String(filePath.dropFirst()).removingPercentEncoding ?? String(filePath.dropFirst()))
    let virtual = [
      "/manga/search", "/manga/series", "/manga/chapter-1", "/anime/search", "/anime/series",
      "/anime/episode-1",
    ]
    let bytes: Data
    if let safe = try? confined(file, to: root), let data = try? Data(contentsOf: safe) {
      bytes = data
    } else if virtual.contains(path) {
      bytes = Data("{\"fixture\":true}".utf8)
    } else {
      return HTTPReply(status: 404)
    }
    let types = [
      "png": "image/png", "mp4": "video/mp4", "m3u8": "application/vnd.apple.mpegurl",
      "ts": "video/mp2t", "vtt": "text/vtt",
    ]
    var reply = HTTPReply(
      status: 200,
      headers: [
        "Content-Type": types[file.pathExtension] ?? "application/octet-stream",
        "Accept-Ranges": "bytes",
      ], body: bytes)
    if ["/manga/search", "/anime/search"].contains(path) {
      reply.headers["Set-Cookie"] = "acceptance_session=ready; Path=/; Max-Age=600; HttpOnly"
    }
    if let range = headers["range"] {
      guard let match = range.range(of: #"^bytes=\d+-\d*$"#, options: .regularExpression) else {
        return HTTPReply(status: 416)
      }
      let parts = range[match].dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
      guard let start = Int(parts[0]) else { return HTTPReply(status: 416) }
      let end = min(Int(parts[1]) ?? (bytes.count - 1), bytes.count - 1)
      guard start <= end else { return HTTPReply(status: 416) }
      reply.status = 206
      reply.body = bytes.subdata(in: start..<(end + 1))
      reply.headers["Content-Range"] = "bytes \(start)-\(end)/\(bytes.count)"
    }
    return reply
  }
  private func handle(_ fd: Int32) {
    defer { Darwin.close(fd) }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var bytes = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while bytes.range(of: Data("\r\n\r\n".utf8)) == nil && bytes.count < 65536 {
      let count = recv(fd, &buffer, buffer.count, 0)
      if count <= 0 { return }
      bytes.append(contentsOf: buffer.prefix(count))
    }
    let lines = String(decoding: bytes, as: UTF8.self).components(separatedBy: "\r\n")
    let parts = (lines.first ?? "").split(separator: " ")
    guard parts.count >= 2 else { return }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      if let split = line.firstIndex(of: ":") {
        headers[String(line[..<split]).lowercased()] = String(line[line.index(after: split)...])
          .trimmingCharacters(in: .whitespaces)
      }
    }
    var reply = response(String(parts[1]), headers: headers)
    reply.headers["Content-Length"] = String(reply.body.count)
    reply.headers["Connection"] = "close"
    let head =
      "HTTP/1.1 \(reply.status) Response\r\n"
      + reply.headers.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
    let output = Data(head.utf8) + reply.body
    output.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset < output.count {
        let count = send(fd, base.advanced(by: offset), output.count - offset, 0)
        if count <= 0 { return }
        offset += count
      }
    }
  }
}
