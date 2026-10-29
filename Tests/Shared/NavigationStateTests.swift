import Foundation
import Observation
import Testing
@testable import Moku

@MainActor struct NavigationStateTests {
    @Test func scrollTravelOnlyNotifiesWhenCompactStateChanges() {
        let state = NavigationState()
        let notifications = Notifications()
        func observe() {
            withObservationTracking { _ = state.isCompact } onChange: { notifications.increment() }
        }
        observe()
        for offset in 10..<33 { state.update(from: CGFloat(offset), to: CGFloat(offset + 1)) }
        #expect(notifications.count == 0)
        state.update(from: 33, to: 34)
        #expect(state.isCompact)
        #expect(notifications.count == 1)
        observe()
        state.update(from: 34, to: 70)
        #expect(notifications.count == 1)
        state.update(from: 70, to: 58)
        #expect(!state.isCompact)
        #expect(notifications.count == 2)
        observe()
        state.update(from: 58, to: 0)
        #expect(notifications.count == 2)
    }
}

private final class Notifications: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
