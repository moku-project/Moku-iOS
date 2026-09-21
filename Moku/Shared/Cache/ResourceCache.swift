import CryptoKit
import Foundation

/// Disposable data only. User records remain in the backend database/profile stores.
/// Shares concurrent requests, bounds memory, and prevents cleared requests from
/// repopulating the cache when they finish later.
actor ResourceCache {
    struct Entry: Codable, Sendable {
        let data: Data
        let expires: Date
    }
    private struct Loaded: Sendable {
        let entry: Entry
        let downloaded: Bool
    }
    private struct Flight {
        let id: UUID
        let task: Task<Loaded, Error>
        var consumers: Set<UUID> = []
    }
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var bytes = 0
    private var flights: [String: Flight] = [:]
    private let cancelWhenUnused: Bool
    private let memoryLimit: Int
    private let disk: ResourceDisk?
    private let now: @Sendable () -> Date

    init(
        memoryLimit: Int, cancelWhenUnused: Bool = false, directory: URL? = nil,
        diskLimit: Int = 128 * 1024 * 1024,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cancelWhenUnused = cancelWhenUnused
        self.memoryLimit = memoryLimit
        self.disk = directory.map { ResourceDisk(directory: $0, limit: diskLimit) }
        self.now = now
    }

    func value(
        for key: String, lifetime: TimeInterval,
        load: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        try Task.checkCancellation()
        if let entry = entries[key], entry.expires > now() {
            touch(key)
            return entry.data
        }
        if let flight = flights[key] {
            let loaded = try await wait(flight, key: key)
            try Task.checkCancellation()
            return loaded.entry.data
        }
        let id = UUID()
        let disk = disk
        let now = now
        let task = Task<Loaded, Error> {
            if let entry = await disk?.read(key, now: now()) {
                return Loaded(entry: entry, downloaded: false)
            }
            let data = try await load()
            try Task.checkCancellation()
            return Loaded(
                entry: Entry(data: data, expires: now().addingTimeInterval(lifetime)),
                downloaded: true)
        }
        flights[key] = Flight(id: id, task: task)
        do {
            let loaded = try await wait(Flight(id: id, task: task), key: key)
            let entry = loaded.entry
            if flights[key]?.id == id {
                insert(entry, key: key)
                if loaded.downloaded { await disk?.write(entry, key: key) }
                if flights[key]?.id == id { flights[key] = nil }
            }
            try Task.checkCancellation()
            return entry.data
        } catch {
            if flights[key]?.id == id { flights[key] = nil }
            throw error
        }
    }

    private func wait(_ flight: Flight, key: String) async throws -> Loaded {
        let consumer = UUID()
        if flights[key]?.id == flight.id { flights[key]?.consumers.insert(consumer) }
        return try await withTaskCancellationHandler {
            try await flight.task.value
        } onCancel: {
            Task { await self.cancelConsumer(consumer, flightID: flight.id, key: key) }
        }
    }

    private func cancelConsumer(_ consumer: UUID, flightID: UUID, key: String) {
        guard cancelWhenUnused, var flight = flights[key], flight.id == flightID else { return }
        flight.consumers.remove(consumer)
        if flight.consumers.isEmpty {
            flight.task.cancel()
            flights[key] = nil
        } else {
            flights[key] = flight
        }
    }

    /// Invalidation leaves existing consumers running, but future reads start fresh.
    func clear() async {
        entries.removeAll()
        order.removeAll()
        bytes = 0
        flights.removeAll()
        await disk?.clear()
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
    private func insert(_ entry: Entry, key: String) {
        bytes -= entries.removeValue(forKey: key)?.data.count ?? 0
        order.removeAll { $0 == key }
        guard entry.data.count <= memoryLimit else { return }
        while bytes + entry.data.count > memoryLimit, let oldest = order.first {
            order.removeFirst()
            bytes -= entries.removeValue(forKey: oldest)?.data.count ?? 0
        }
        entries[key] = entry
        bytes += entry.data.count
        touch(key)
    }
}

private actor ResourceDisk {
    let directory: URL
    let limit: Int
    init(directory: URL, limit: Int) {
        self.directory = directory
        self.limit = limit
    }

    private func file(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }
    func read(_ key: String, now: Date) -> ResourceCache.Entry? {
        let url = file(key)
        guard let data = try? Data(contentsOf: url),
            let entry = try? PropertyListDecoder().decode(ResourceCache.Entry.self, from: data),
            entry.expires > now
        else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        return entry
    }
    func write(_ entry: ResourceCache.Entry, key: String) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(entry), data.count <= limit else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try data.write(to: file(key), options: .atomic)
            trim()
        } catch {
            // A disposable cache must never prevent playback or browsing.
        }
    }
    func clear() { try? FileManager.default.removeItem(at: directory) }

    private func trim() {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        let rows = files.compactMap { url -> (URL, Int, Date)? in
            guard
                let values = try? url.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey,
                ])
            else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = rows.reduce(0) { $0 + $1.1 }
        for (url, size, _) in rows where total > limit {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}
