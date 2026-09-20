import Foundation

extension BackendController {
    public struct Connection: Sendable {
        public let baseURL: URL
        private let token: String

        init(baseURL: URL, token: String) {
            self.baseURL = baseURL
            self.token = token
        }

        /// Authentication is header-only and only attached to this backend's URL.
        public func graphqlRequest(query: String) throws -> URLRequest {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/graphql"))
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["query": query])
            return request
        }

        static func isExtensionIconPath(_ path: String) -> Bool {
            guard path.hasPrefix("/proxy/icon/") else { return false }
            let id = path.dropFirst("/proxy/icon/".count)
            return !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) }
                && (Int64(id) ?? 0) > 0
        }

        public func coverRequest(path: String) throws -> URLRequest {
            guard let parts = URLComponents(string: path), parts.scheme == nil,
                parts.host == nil, parts.query == nil, parts.fragment == nil,
                parts.path.hasPrefix("/proxy/img/") || parts.path.hasPrefix("/proxy/cover/")
                    || Self.isExtensionIconPath(parts.path),
                !parts.path.contains("..")
            else { throw BackendError.invalidEndpoint }
            var request = URLRequest(url: baseURL.appendingPathComponent(parts.path))
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }

        public func contentRequest(path: String, byteRange: String? = nil) throws -> URLRequest {
            guard let relative = URLComponents(string: path), relative.scheme == nil,
                relative.host == nil, relative.fragment == nil,
                relative.path.hasPrefix("/content/"),
                !relative.path.split(separator: "/").contains(".."),
                var target = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            else { throw BackendError.invalidEndpoint }
            target.percentEncodedPath = relative.percentEncodedPath
            target.percentEncodedQuery = relative.percentEncodedQuery
            guard let url = target.url else { throw BackendError.invalidEndpoint }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let byteRange { request.setValue(byteRange, forHTTPHeaderField: "Range") }
            return request
        }

        public func chapterOpenRequest(mediaID: String, chapterID: String) throws -> URLRequest {
            guard let media = Int64(mediaID), let chapter = Int64(chapterID), media > 0, chapter > 0
            else {
                throw BackendError.invalidEndpoint
            }
            var request = URLRequest(url: baseURL.appendingPathComponent("api/mobile/chapter-open"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["mediaId": media, "chapterId": chapter])
            return request
        }

        func apiRequest(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
            guard let parts = URLComponents(string: path), parts.scheme == nil, parts.host == nil,
                parts.fragment == nil, parts.path.hasPrefix("/api/"),
                !parts.path.split(separator: "/").contains(".."),
                var target = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            else { throw BackendError.invalidEndpoint }
            target.percentEncodedPath = parts.percentEncodedPath
            target.percentEncodedQuery = parts.percentEncodedQuery
            guard let url = target.url else { throw BackendError.invalidEndpoint }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            request.timeoutInterval = 60
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            return request
        }

        public func statusRequest() -> URLRequest {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/mobile/status"))
            request.timeoutInterval = 5
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
    }

}
