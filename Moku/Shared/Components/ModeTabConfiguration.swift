import Foundation

struct ModeTabConfiguration: Equatable {
    private struct Saved: Codable {
        var order: [String]
        var hidden: [String]
    }
    private(set) var order: [ContentMode]
    private(set) var hidden: Set<ContentMode>

    init(storage: String = "") {
        let saved = try? JSONDecoder().decode(Saved.self, from: Data(storage.utf8))
        var seen = Set<ContentMode>()
        order = ((saved?.order.compactMap(ContentMode.init(rawValue:)) ?? []) + ContentMode.allCases)
            .filter { seen.insert($0).inserted }
        order.removeAll { $0 == .all }
        order.insert(.all, at: 0)
        hidden = Set(saved?.hidden.compactMap(ContentMode.init(rawValue:)) ?? [])
        hidden.remove(.all)
    }

    var visible: [ContentMode] { order.filter { !hidden.contains($0) } }
    var storage: String {
        let saved = Saved(order: order.map(\.rawValue), hidden: order.filter { hidden.contains($0) }.map(\.rawValue))
        return String(decoding: try! JSONEncoder().encode(saved), as: UTF8.self)
    }

    mutating func toggle(_ mode: ContentMode) {
        guard mode != .all else { return }
        if hidden.contains(mode) { hidden.remove(mode) } else { hidden.insert(mode) }
    }

    mutating func move(_ mode: ContentMode, to target: ContentMode) {
        guard mode != .all, target != .all, let source = order.firstIndex(of: mode), let destination = order.firstIndex(of: target), source != destination else { return }
        order.remove(at: source)
        order.insert(mode, at: destination)
    }
}
