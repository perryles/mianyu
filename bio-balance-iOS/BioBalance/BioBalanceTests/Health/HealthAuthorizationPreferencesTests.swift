import XCTest
@testable import BioBalance

nonisolated final class HealthAuthorizationPreferencesTests: XCTestCase {
    @MainActor func testLegacyAuthorizationFlagsMigrateToUnifiedFlowMarker() {
        let suiteName = "HealthAuthorizationPreferencesTests.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "onboarding_permission_health")
        defaults.set(true, forKey: "social.sharing.health.authorizationRequested.v1")

        HealthAuthorizationPreferences.migrateIfNeeded(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: HealthAuthorizationPreferences.flowCompletedKey))
        XCTAssertNil(defaults.object(forKey: "onboarding_permission_health"))
        XCTAssertNil(defaults.object(forKey: "social.sharing.health.authorizationRequested.v1"))
    }

    @MainActor func testLegacyFlagsDoNotOverrideExplicitCurrentValue() {
        let suiteName = "HealthAuthorizationPreferencesTests.current.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: HealthAuthorizationPreferences.flowCompletedKey)
        defaults.set(true, forKey: "onboarding_permission_health")

        HealthAuthorizationPreferences.migrateIfNeeded(defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: HealthAuthorizationPreferences.flowCompletedKey))
        XCTAssertNil(defaults.object(forKey: "onboarding_permission_health"))
    }
}
