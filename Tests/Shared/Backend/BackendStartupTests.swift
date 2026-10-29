import Foundation
import Testing

@testable import Moku

@MainActor struct BackendStartupTests {
    @Test func cancelledRequestDoesNotStartServices() async {
        let backend = Backend()
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await backend.connection(manualStart: true)
                Issue.record("A cancelled request started the backend")
            } catch is CancellationError {
            } catch {
                Issue.record("Expected cancellation before startup: \(error)")
            }
        }
        await request.value
        #expect(await backend.currentServerURL() == nil)
    }

    @Test func catalogIsAvailableBeforeSourceRuntimeAndAfterFailedAttachment() async throws {
        let directory = URL.temporaryDirectory.appending(path: "MokuStartupTests/\(UUID())")
        let backend = BackendController()
        let connection = try await backend.start(dataDirectory: directory, deferSandbox: true)
        do {
            let iconRequest = try connection.coverRequest(path: "/proxy/icon/42")
            #expect(iconRequest.url?.path == "/proxy/icon/42")
            #expect(iconRequest.url?.host == connection.baseURL.host)
            #expect(iconRequest.value(forHTTPHeaderField: "Authorization") != nil)
            #expect(throws: BackendController.BackendError.self) {
                try connection.coverRequest(path: "/proxy/icon/42?redirect=elsewhere")
            }
            let status = try await backend.status()
            #expect(status.graphqlAvailable && !status.extensionsAvailable)
            let (data, response) = try await URLSession.shared.data(
                for: connection.graphqlRequest(
                    query: "{ repositories { id } installedExtensions { id } }"))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(String(decoding: data, as: UTF8.self).contains("\"repositories\":[]"))
            do {
                try await backend.attachSandbox(
                    .init(address: "example.com:1", token: String(repeating: "a", count: 32)))
                Issue.record("Accepted invalid source endpoint")
            } catch {}
            #expect(try await backend.status().graphqlAvailable)
            try await backend.stop()
            let restarted = try await backend.resume()
            #expect(restarted.baseURL.host == "127.0.0.1")
            #expect(try await !backend.status().extensionsAvailable)
            try await backend.stop()
            try FileManager.default.removeItem(at: directory)
        } catch {
            try? await backend.stop()
            throw error
        }
    }
}
