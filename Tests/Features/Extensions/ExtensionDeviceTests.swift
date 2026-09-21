import Foundation
import XCTest

@testable import Moku

/// Opt-in regression against the device's saved repositories and actual backend.
final class ExtensionDeviceTests: XCTestCase {
    @MainActor func testSavedRepositoriesAndCatalogLoad() async throws {
        guard ProcessInfo.processInfo.environment["MOKU_LIVE_EXTENSION_CHECK"] == "1" else {
            throw XCTSkip("Requires a device with saved extension repositories.")
        }
        let repository = LiveExtensionRepository()
        let model = ExtensionsViewModel(repository: repository)
        // Match the screen's concurrent requests, including overlapping initial loads.
        async let first: Void = model.load()
        async let second: Void = model.load()
        _ = await (first, second)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.repositories.isEmpty)
        XCTAssertGreaterThan(model.total, 0)
        do {
            let repositories = try await repository.repositories()
            XCTAssertFalse(repositories.isEmpty)
            print("Saved repositories decoded: \(repositories.count)")
        } catch { XCTFail("Repositories: \(String(reflecting: error))") }
        do {
            let installed = try await repository.installed()
            XCTAssertFalse(installed.isEmpty)
            print("Installed sources decoded: \(installed.count)")
        } catch { XCTFail("Installed sources: \(String(reflecting: error))") }
        do {
            let page = try await repository.catalog(
                query: "", repository: nil,
                language: nil, media: .all, offset: 0)
            XCTAssertGreaterThan(page.total, 0)
            XCTAssertFalse(page.items.isEmpty)
            print(
                "Catalog decoded: \(page.items.count)/\(page.total), languages: \(page.languages.count)"
            )
        } catch { XCTFail("Catalog: \(String(reflecting: error))") }
    }
}
