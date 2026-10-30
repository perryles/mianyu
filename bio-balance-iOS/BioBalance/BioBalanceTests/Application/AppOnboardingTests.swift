import XCTest
@testable import BioBalance

nonisolated final class AppOnboardingTests: XCTestCase {
    @MainActor func testStepsAdvanceInOrderAndStopAtReady() {
        let store = AppOnboardingStore()

        for expected in AppOnboardingStep.allCases.dropFirst() {
            store.next()
            XCTAssertEqual(store.currentStep, expected)
        }
        store.next()
        XCTAssertEqual(store.currentStep, .ready)
    }

    @MainActor func testPreviousMovesBackOneStepAndStopsAtWelcome() {
        let store = AppOnboardingStore(currentStep: .healthPermission)

        store.previous()
        XCTAssertEqual(store.currentStep, .focus)
        store.previous()
        store.previous()
        XCTAssertEqual(store.currentStep, .welcome)
    }

    @MainActor func testFocusDefaultsToSleepAndPersistsSelection() {
        let suiteName = "AppOnboardingTests.focus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppOnboardingStore(defaults: defaults)

        XCTAssertEqual(store.selectedFocus, .sleep)
        XCTAssertEqual(defaults.string(forKey: AppOnboardingPreferences.focusKey), "sleep")

        store.selectFocus(.stress)

        XCTAssertEqual(store.selectedFocus, .stress)
        XCTAssertEqual(defaults.string(forKey: AppOnboardingPreferences.focusKey), "stress")
        XCTAssertNotNil(defaults.object(forKey: OnboardingPreferenceCloudStore.LocalKey.updatedAt))
    }

    @MainActor func testHealthAuthorizationRefreshesPhaseWithoutCompletingOnboarding() async {
        let suiteName = "AppOnboardingTests.health.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppOnboardingStore(currentStep: .healthPermission, defaults: defaults)
        var requested = false

        let phase = await store.requestHealthAuthorization {
            requested = true
            return .authorizedNoData
        }

        XCTAssertTrue(requested)
        XCTAssertEqual(phase, .authorizedNoData)
        XCTAssertEqual(store.healthAuthorizationPhase, .authorizedNoData)
        XCTAssertFalse(store.isRequestingAuthorization)
        XCTAssertFalse(defaults.bool(forKey: AppOnboardingPreferences.completedKey))
    }

    @MainActor func testOnlyExplicitCompletionWritesCompletedFlag() {
        let suiteName = "AppOnboardingTests.complete.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppOnboardingStore(currentStep: .ready, defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: AppOnboardingPreferences.completedKey))
        store.markCompleted()
        XCTAssertTrue(defaults.bool(forKey: AppOnboardingPreferences.completedKey))
    }

    @MainActor func testLegacyCompletionMigratesToAppSpecificKey() {
        let suiteName = "AppOnboardingTests.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "hasCompletedFirstLaunchOnboarding")

        AppOnboardingPreferences.migrateIfNeeded(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: AppOnboardingPreferences.completedKey))
    }

    @MainActor func testExplicitIncompleteStateIsNotOverridden() {
        let suiteName = "AppOnboardingTests.explicit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: AppOnboardingPreferences.completedKey)
        defaults.set(true, forKey: "isGuest")

        AppOnboardingPreferences.migrateIfNeeded(defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: AppOnboardingPreferences.completedKey))
    }
}
