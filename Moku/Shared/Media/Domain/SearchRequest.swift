import Foundation

struct SearchRequest: Equatable, Sendable {
    let query: String
    let options: SearchOptions
    var page = 1
}
