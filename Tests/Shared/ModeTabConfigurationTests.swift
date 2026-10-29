import Testing
@testable import Moku

struct ModeTabConfigurationTests {
    @Test func defaultsAndInvalidStorageKeepAllModes() {
        #expect(ModeTabConfiguration().visible == ContentMode.allCases)
        #expect(ModeTabConfiguration(storage: "invalid").visible == ContentMode.allCases)
    }
    @Test func hiddenModesKeepTheirOrderAndAllCannotBeHidden() {
        var modes = ModeTabConfiguration()
        modes.move(.anime, to: .manga)
        modes.toggle(.manga)
        modes.toggle(.all)
        let saved = ModeTabConfiguration(storage: modes.storage)
        #expect(saved.visible == [.all, .anime, .novels])
        modes.toggle(.manga)
        #expect(modes.visible == [.all, .anime, .manga, .novels])
        #expect(saved == ModeTabConfiguration(storage: saved.storage))
    }
    @Test func normalizationRepairsDuplicatesUnknownModesAndHiddenAll() {
        let modes = ModeTabConfiguration(storage: #"{"order":["anime","anime","unknown"],"hidden":["all","manga"]}"#)
        #expect(modes.order == [.all, .anime, .manga, .novels])
        #expect(modes.visible == [.all, .anime, .novels])
    }
    @Test func movingInEitherDirectionPreservesEveryMode() {
        var modes = ModeTabConfiguration()
        modes.move(.manga, to: .anime)
        #expect(modes.order == [.all, .novels, .anime, .manga])
        modes.move(.manga, to: .novels)
        #expect(modes.order == ContentMode.allCases)
        modes.move(.all, to: .anime)
        modes.move(.anime, to: .all)
        #expect(modes.order == ContentMode.allCases)
    }
}
