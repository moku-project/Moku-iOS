import Foundation

enum ReaderPagination {
    static func groups(count: Int, double: Bool, offset: Bool) -> [[Int]] {
        guard count > 0 else { return [] }
        guard double else { return (1...count).map { [$0] } }
        var result: [[Int]] = [[1]]
        if offset && count > 1 { result.append([2]) }
        var page = offset ? 3 : 2
        while page <= count {
            result.append(Array(page...min(page + 1, count)))
            page += 2
        }
        return result
    }
    static func adjacent(page: Int, groups: [[Int]], forward: Bool) -> Int? {
        guard let i = groups.firstIndex(where: { $0.contains(page) }),
            groups.indices.contains(i + (forward ? 1 : -1))
        else { return nil }
        return groups[i + (forward ? 1 : -1)].first
    }
}
