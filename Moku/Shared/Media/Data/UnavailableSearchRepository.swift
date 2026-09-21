/// Replaced at app composition when the embedded backend is integrated.
/// Never supplies demonstration results to a normal app session.
struct UnavailableSearchRepository: SearchRepository {
    func sources() async throws -> [SearchSource] { throw SearchFailure.notConnected }
    func search(_ request: SearchRequest) async throws -> [MediaEntry] {
        throw SearchFailure.notConnected
    }
}
