import Foundation

struct SearchRequest: Equatable, Sendable {
    let query: String
    let options: SearchOptions
}
