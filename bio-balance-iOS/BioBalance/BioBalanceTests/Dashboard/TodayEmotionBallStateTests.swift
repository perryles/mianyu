import XCTest
@testable import BioBalance

nonisolated final class TodayMianyuMascotStateTests: XCTestCase {
    @MainActor func testWebEngineMountIsDeferredUntilAfterTheInitialDashboardFrame() {
        XCTAssertFalse(TodayMianyuMascotLoadPolicy.shouldMountWebView(hasFinishedInitialDelay: false))
        XCTAssertTrue(TodayMianyuMascotLoadPolicy.shouldMountWebView(hasFinishedInitialDelay: true))
        XCTAssertGreaterThan(TodayMianyuMascotLoadPolicy.initialDelayNanoseconds, 0)
    }

    @MainActor func testHeavyHealthLoadsAreStaggeredAfterMascotMount() {
        XCTAssertGreaterThan(
            TodayDashboardInitialLoadPolicy.heavyDataDelayNanoseconds,
            TodayMianyuMascotLoadPolicy.initialDelayNanoseconds
        )
    }

    @MainActor func testMissingDataUsesLegacyBootingEmotion() {
        XCTAssertEqual(TodayMianyuMascotState.emotion(hasData: false, band: .waiting), .booting)
    }

    @MainActor func testHealthBandsReuseThePreviousEmotionSemantics() {
        XCTAssertEqual(TodayMianyuMascotState.emotion(hasData: true, band: .relaxed), .happy)
        XCTAssertEqual(TodayMianyuMascotState.emotion(hasData: true, band: .steady), .idle)
        XCTAssertEqual(TodayMianyuMascotState.emotion(hasData: true, band: .mild), .focused)
        XCTAssertEqual(TodayMianyuMascotState.emotion(hasData: true, band: .caution), .tired)
        XCTAssertEqual(TodayMianyuMascotState.emotion(hasData: true, band: .high), .sleeping)
    }

    @MainActor func testFirstUpdateReloadsTheWebEngine() {
        XCTAssertEqual(
            TodayMianyuMascotUpdateAction.resolve(
                loadedEmotion: nil,
                loadedReduceMotion: nil,
                requestedEmotion: .idle,
                requestedReduceMotion: false
            ),
            .reload
        )
    }

    @MainActor func testMotionPreferenceChangeReloadsTheWebEngine() {
        XCTAssertEqual(
            TodayMianyuMascotUpdateAction.resolve(
                loadedEmotion: .idle,
                loadedReduceMotion: false,
                requestedEmotion: .idle,
                requestedReduceMotion: true
            ),
            .reload
        )
    }

    @MainActor func testEmotionChangeUsesTheJavaScriptBridge() {
        XCTAssertEqual(
            TodayMianyuMascotUpdateAction.resolve(
                loadedEmotion: .idle,
                loadedReduceMotion: false,
                requestedEmotion: .tired,
                requestedReduceMotion: false
            ),
            .setEmotion(.tired)
        )
    }

    @MainActor func testUnchangedEmotionDoesNothing() {
        XCTAssertEqual(
            TodayMianyuMascotUpdateAction.resolve(
                loadedEmotion: .sleeping,
                loadedReduceMotion: true,
                requestedEmotion: .sleeping,
                requestedReduceMotion: true
            ),
            .none
        )
    }
}
