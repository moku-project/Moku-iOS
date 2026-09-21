import Foundation

struct LocalProfile: Codable, Identifiable, Equatable, Sendable {
    static let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var id: UUID
    var name: String
    var createdAt = Date()
}

struct ProfileManifest: Codable, Sendable {
    var profiles: [LocalProfile]
    var activeID: UUID
}

/// All JSON disk access is serialized away from the UI executor.
