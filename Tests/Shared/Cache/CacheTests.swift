import Foundation
import Testing
#if canImport(UIKit)
import UIKit
#endif

@testable import Moku

struct CacheTests {
    @Test func memoryTrimPreservesDiskData() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ResourceCache(memoryLimit: 1024, directory: directory)
        _ = try await cache.value(for: "cover", lifetime: 60) { Data([1]) }
        await cache.trimMemory()
        let persisted = try await cache.value(for: "cover", lifetime: 60) { throw CacheTestError.failed }
        #expect(persisted == Data([1]))
    }

    @Test func memoryTrimReleasesEntriesAndPreservesRunningLoads() async throws {
        let cache = ResourceCache(memoryLimit: 1024)
        _ = try await cache.value(for: "cached", lifetime: 60) { Data([1]) }
        let gate = CacheGate()
        let request = Task { try await cache.value(for: "pending", lifetime: 60) { await gate.load() } }
        await gate.waitUntilStarted()
        await cache.trimMemory()
        let replacement = try await cache.value(for: "cached", lifetime: 60) { Data([2]) }
        #expect(replacement == Data([2]))
        let shared = Task { try await cache.value(for: "pending", lifetime: 60) { throw CacheTestError.failed } }
        await gate.release()
        #expect(try await request.value == Data([1]))
        #expect(try await shared.value == Data([1]))
    }

    @Test func expiredDiskResultsReloadAndClearRemovesPersistedResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ResourceCache(
            memoryLimit: 0, directory: directory, now: { Date(timeIntervalSince1970: 100) })
        _ = try await cache.value(for: "query", lifetime: 60) { Data([1]) }
        let restarted = ResourceCache(
            memoryLimit: 1024, directory: directory, now: { Date(timeIntervalSince1970: 161) })
        let refreshed = try await restarted.value(for: "query", lifetime: 60) { Data([2]) }
        #expect(refreshed == Data([2]))
        await restarted.clear()
        let cleared = ResourceCache(memoryLimit: 1024, directory: directory)
        let fresh = try await cleared.value(for: "query", lifetime: 60) { Data([3]) }
        #expect(fresh == Data([3]))
    }

    @Test func concurrentReadersShareOneLoadAndWarmReadsDoNoWork() async throws {
        let cache = ResourceCache(memoryLimit: 1024)
        let probe = CacheProbe()
        let values = try await concurrentMap(Array(0..<12), limit: 12) { _ in
            try await cache.value(for: "cover", lifetime: 60) { try await probe.load() }
        }
        #expect(values.allSatisfy { $0 == Data([1]) })
        _ = try await cache.value(for: "cover", lifetime: 60) { try await probe.load() }
        #expect(await probe.calls == 1)
    }

    @Test func expiredEntriesAndFailuresAreRetried() async throws {
        let cache = ResourceCache(memoryLimit: 1024)
        let probe = CacheProbe()
        _ = try await cache.value(for: "expired", lifetime: -1) { try await probe.load() }
        let fresh = try await cache.value(for: "expired", lifetime: 60) { try await probe.load() }
        #expect(fresh == Data([2]))
        do {
            _ = try await cache.value(for: "failure", lifetime: 60) { throw CacheTestError.failed }
            Issue.record("The failing loader should throw")
        } catch CacheTestError.failed {}
        let retry = try await cache.value(for: "failure", lifetime: 60) { Data([3]) }
        #expect(retry == Data([3]))
    }

    @Test func clearingDuringARequestDoesNotRestoreStaleData() async throws {
        let cache = ResourceCache(memoryLimit: 1024)
        let gate = CacheGate()
        let old = Task { try await cache.value(for: "title", lifetime: 60) { await gate.load() } }
        await gate.waitUntilStarted()
        await cache.clear()
        await gate.release()
        _ = try await old.value
        let fresh = try await cache.value(for: "title", lifetime: 60) { Data([2]) }
        #expect(fresh == Data([2]))
    }

    @Test func cancelledSearchStopsItsUnusedLoader() async throws {
        let cache = ResourceCache(memoryLimit: 1024, cancelWhenUnused: true)
        let probe = CancellationProbe()
        let request = Task {
            try await cache.value(for: "search", lifetime: 60) { try await probe.load() }
        }
        await probe.waitUntilStarted()
        request.cancel()
        do {
            _ = try await request.value
            Issue.record("Cancelled consumer should throw")
        } catch is CancellationError {}
        #expect(await probe.cancelled)
        let next = try await cache.value(for: "search", lifetime: 60) { Data([2]) }
        #expect(next == Data([2]))
    }

    @Test func memoryEvictsLeastRecentlyUsedData() async throws {
        let cache = ResourceCache(memoryLimit: 2)
        _ = try await cache.value(for: "a", lifetime: 60) { Data([1]) }
        _ = try await cache.value(for: "b", lifetime: 60) { Data([2]) }
        _ = try await cache.value(for: "a", lifetime: 60) { Data([9]) }
        _ = try await cache.value(for: "c", lifetime: 60) { Data([3]) }
        let b = try await cache.value(for: "b", lifetime: 60) { Data([4]) }
        #expect(b == Data([4]))
    }

    @Test func diskSurvivesNewInstancesAndStaysWithinBudget() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ResourceCache(memoryLimit: 0, directory: directory, diskLimit: 1500)
        _ = try await cache.value(for: "a", lifetime: 60) { Data(repeating: 1, count: 800) }
        let restarted = ResourceCache(memoryLimit: 0, directory: directory, diskLimit: 1500)
        let persisted = try await restarted.value(for: "a", lifetime: 60) {
            throw CacheTestError.failed
        }
        #expect(persisted == Data(repeating: 1, count: 800))
        _ = try await restarted.value(for: "b", lifetime: 60) { Data(repeating: 2, count: 800) }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) {
            try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        #expect(bytes <= 1500)
        #expect(files.count == 1)
        await restarted.clear()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func sourceFanoutIsBoundedAndKeepsSourceOrder() async throws {
        let probe = CacheProbe()
        let result = try await concurrentMap(Array(0..<9), limit: 3) { index in
            _ = try await probe.load()
            return index
        }
        #expect(result == Array(0..<9))
        #expect(await probe.peak == 3)
    }

    @Test func sourceFailureIsNotSilentlyDropped() async throws {
        do {
            _ = try await concurrentMap(Array(0..<6), limit: 3) { index in
                if index == 2 { throw CacheTestError.failed }
                return index
            }
            Issue.record("A failed source must fail the result")
        } catch CacheTestError.failed {}
    }

    #if canImport(UIKit)
    @MainActor @Test func oversizedArtworkIsDownsampled() async throws {
        let data = UIGraphicsImageRenderer(
            size: CGSize(width: 2000, height: 3000),
            format: {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                return format
            }()
        ).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 3000))
        }
        let image = try CoverImagePipeline.thumbnail(data)
        #expect(image.cgImage?.height == 600)
        #expect(image.cgImage?.width == 400)
    }
    #endif
}

private enum CacheTestError: Error { case failed }
private actor CacheProbe {
    var calls = 0
    var active = 0
    var peak = 0
    func load() async throws -> Data {
        calls += 1
        let call = calls
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(30))
        return Data([UInt8(call)])
    }
}
private actor CacheGate {
    private var loader: CheckedContinuation<Data, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func load() async -> Data {
        await withCheckedContinuation {
            loader = $0
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if loader != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() {
        loader?.resume(returning: Data([1]))
        loader = nil
    }
}

private actor CancellationProbe {
    var cancelled = false
    private var started = false
    private var waiting: CheckedContinuation<Void, Never>?
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func load() async throws -> Data {
        started = true
        waiting?.resume()
        waiting = nil
        do { try await Task.sleep(for: .seconds(2)) } catch {
            cancelled = true
            throw error
        }
        return Data([1])
    }
}
