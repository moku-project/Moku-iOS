import Foundation
import Testing

@testable import Moku

struct CoverURLTests {
    @Test func keepsProxyPathsAndEncodesRemoteCovers() throws {
        let path = "/proxy/img/aHR0cHM6Ly9leGFtcGxlLmNvbS9hLmpwZw=="
        #expect(BackendAPI.coverURL(path)?.relativeString == path)
        let remote = "https://uploads.mangadex.org/covers/title/cover.jpg?width=256"
        let proxy = try #require(BackendAPI.coverURL(remote))
        let encoded = String(proxy.relativeString.dropFirst("/proxy/img/".count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let decoded = try #require(Data(base64Encoded: encoded))
        #expect(String(decoding: decoded, as: UTF8.self) == remote)
        #expect(BackendAPI.coverURL(proxy.relativeString) == proxy)
    }

    @Test func acceptsExtensionIconProxyPathsAndDecodesIcons() throws {
        #expect(BackendAPI.coverURL("/proxy/icon/42")?.relativeString == "/proxy/icon/42")
        let json = Data(
            #"{"id":"42","repositoryId":"1","packageName":"source","displayName":"Source","version":"1","lang":"en","contentType":"MANGA","installed":true,"enabled":true,"isNsfw":false,"iconUrl":"/proxy/icon/42"}"#
                .utf8)
        let source = try JSONDecoder().decode(SourceExtension.self, from: json)
        #expect(source.iconURL?.relativeString == "/proxy/icon/42")
        for path in [
            "/proxy/icon/", "/proxy/icon/0", "/proxy/icon/-1", "/proxy/icon/42/other",
            "/proxy/icon/42?token=x", "/proxy/icon/../api/graphql",
        ] {
            #expect(BackendAPI.coverURL(path) == nil)
        }
    }

    @Test func rejectsUnsupportedPaths() {
        for value in [
            "file:///tmp/cover.jpg", "//example.com/cover.jpg", "/api/graphql",
            "/proxy/img/../../api/graphql", "https://user:secret@example.com/cover.jpg",
            "/proxy/cover/1?redirect=elsewhere",
        ] {
            #expect(BackendAPI.coverURL(value) == nil)
        }
        #expect(BackendAPI.coverURL(nil) == nil)
    }
}
