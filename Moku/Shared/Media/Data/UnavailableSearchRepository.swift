/// Placeholder until the embedded backend is composed in; never returns demo results.
struct UnavailableSearchRepository: SearchRepository {
    func sources() async throws -> [SearchSource] { throw SearchFailure.notConnected }
    func search(_ request: SearchRequest) async throws -> [MediaEntry] {
        throw SearchFailure.notConnected
    }
}
