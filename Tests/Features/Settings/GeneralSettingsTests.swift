import Foundation
import Testing

@testable import Moku

@MainActor struct GeneralSettingsTests {
    @Test func activityRestartsIdleDeadlineAndDismissesSplash() {
        let state = IdleScreenState()
        let start = ContinuousClock.now
        state.recordActivity(at: start)
        state.check(timeout: .seconds(60), at: start.advanced(by: .seconds(59)))
        #expect(!state.isVisible)
        state.check(timeout: .seconds(60), at: start.advanced(by: .seconds(60)))
        #expect(state.isVisible)
        state.recordActivity(at: start.advanced(by: .seconds(61)))
        #expect(!state.isVisible)
        state.check(timeout: .seconds(60), at: start.advanced(by: .seconds(120)))
        #expect(!state.isVisible)
    }
    @Test func backgroundMediaAndNeverTimeoutCannotShowIdleScreen() {
        let state = IdleScreenState()
        let start = ContinuousClock.now
        state.recordActivity(at: start)
        let later = start.advanced(by: .seconds(600))
        state.isActive = false
        state.check(timeout: .seconds(60), at: later)
        #expect(!state.isVisible)
        state.isActive = true
        state.setPresentationBlocked(true)
        state.check(timeout: .seconds(60), at: later)
        #expect(!state.isVisible)
        state.setPresentationBlocked(false)
        state.setMediaActive(true)
        state.check(timeout: .seconds(60), at: later)
        #expect(!state.isVisible)
        state.setMediaActive(false)
        state.check(timeout: .zero, at: later)
        #expect(!state.isVisible)
    }
    @Test func desktopLanguageAliasesAndArbitraryCodesArePreserved() {
        for value in ["", "ALL", "*", "any", "multi", "mul"] {
            #expect(GeneralPreferences.canonicalLanguage(value) == "all")
        }
        #expect(GeneralPreferences.canonicalLanguage(" PT_BR ") == "pt-br")
        #expect(GeneralPreferences.canonicalLanguage("zh-Hant") == "zh-hant")
        #expect(GeneralPreferences.canonicalLanguage("uncommon") == "uncommon")
        #expect(GeneralPreferences.clampedScale(.nan) == 100)
        #expect(GeneralPreferences.clampedScale(-5) == 50)
        #expect(GeneralPreferences.clampedScale(400) == 200)
    }
}
