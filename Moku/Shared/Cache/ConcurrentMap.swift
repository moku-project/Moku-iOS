import Foundation

/// Bounded fan-out without changing source order or silently dropping failures.
func concurrentMap<Input: Sendable, Output: Sendable>(
    _ inputs: [Input], limit: Int,
    onUpdate: (@Sendable ([Output]) async -> Void)? = nil,
    transform: @escaping @Sendable (Input) async throws -> Output
) async throws -> [Output] {
    try await withThrowingTaskGroup(of: (Int, Output).self) { group in
        var next = 0
        var values: [Int: Output] = [:]
        func enqueue(_ index: Int) {
            group.addTask {
                try Task.checkCancellation()
                return (index, try await transform(inputs[index]))
            }
        }
        while next < min(max(1, limit), inputs.count) {
            enqueue(next)
            next += 1
        }
        while let (index, value) = try await group.next() {
            values[index] = value
            try Task.checkCancellation()
            if next < inputs.count {
                enqueue(next)
                next += 1
            }
            await onUpdate?(inputs.indices.compactMap { values[$0] })
        }
        return inputs.indices.map { values[$0]! }
    }
}
