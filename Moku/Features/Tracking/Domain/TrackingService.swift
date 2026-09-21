import Foundation

struct TrackingService: Decodable, Sendable, Identifiable {
    let key: String
    let name: String
    let configured: Bool
    let isLoggedIn: Bool
    let authUrl: String?
    let iconUrl: String?
    let username: String?
    var id: String { key }
    var comingSoon: Bool { key == "mal" || key == "myanimelist" }
    var status: String {
        comingSoon
            ? "Coming soon"
            : isLoggedIn ? "Connected" : configured ? "Not connected" : "Not configured"
    }
}
