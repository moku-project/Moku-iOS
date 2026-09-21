import Foundation

protocol RecentRepository: Sendable {
    func chapters(for entry: MediaEntry, refresh: Bool) async throws -> [RecentUpdate]
    func entry(id: String) async throws -> MediaEntry
    func download(_ update: RecentUpdate, delete: Bool) async throws
}
