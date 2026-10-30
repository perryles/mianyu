import Foundation
import XCTest
@testable import BioBalance

nonisolated final class LegacyAppGroupDataMigrationTests: XCTestCase {
    @MainActor private func makeSuite(_ label: String) throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "LegacyAppGroupDataMigrationTests.\(label).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @MainActor func testBusinessKeysMoveFromAppGroupToStandardDefaults() throws {
        let appGroup = try makeSuite("appGroup")
        let standard = try makeSuite("standard")
        defer {
            appGroup.defaults.removePersistentDomain(forName: appGroup.suiteName)
            standard.defaults.removePersistentDomain(forName: standard.suiteName)
        }

        let key = "moodStore.v1"
        let legacyPayload = Data("legacy-payload".utf8)
        appGroup.defaults.set(legacyPayload, forKey: key)

        LegacyAppGroupDataMigration.migrateBusinessDataToStandardDefaults(
            appGroupDefaults: appGroup.defaults,
            standardDefaults: standard.defaults
        )

        XCTAssertEqual(standard.defaults.data(forKey: key), legacyPayload)
        XCTAssertNil(appGroup.defaults.object(forKey: key))
    }

    @MainActor func testBusinessKeyDoesNotOverwriteExistingStandardValue() throws {
        let appGroup = try makeSuite("appGroup")
        let standard = try makeSuite("standard")
        defer {
            appGroup.defaults.removePersistentDomain(forName: appGroup.suiteName)
            standard.defaults.removePersistentDomain(forName: standard.suiteName)
        }

        let key = "periodStore.v1"
        let legacyPayload = Data("legacy".utf8)
        let currentPayload = Data("current".utf8)
        appGroup.defaults.set(legacyPayload, forKey: key)
        standard.defaults.set(currentPayload, forKey: key)

        LegacyAppGroupDataMigration.migrateBusinessDataToStandardDefaults(
            appGroupDefaults: appGroup.defaults,
            standardDefaults: standard.defaults
        )

        XCTAssertEqual(standard.defaults.data(forKey: key), currentPayload)
        XCTAssertNil(appGroup.defaults.object(forKey: key))
    }

    @MainActor func testPrefixedMetricKeysMigrate() throws {
        let appGroup = try makeSuite("appGroup")
        let standard = try makeSuite("standard")
        defer {
            appGroup.defaults.removePersistentDomain(forName: appGroup.suiteName)
            standard.defaults.removePersistentDomain(forName: standard.suiteName)
        }

        let key = "metric.reminder.settings.water"
        appGroup.defaults.set(42, forKey: key)

        LegacyAppGroupDataMigration.migrateBusinessDataToStandardDefaults(
            appGroupDefaults: appGroup.defaults,
            standardDefaults: standard.defaults
        )

        XCTAssertEqual(standard.defaults.integer(forKey: key), 42)
        XCTAssertNil(appGroup.defaults.object(forKey: key))
    }

    @MainActor func testScalarPreferencesMigrateOnceAndRemoveOldKeys() throws {
        let fixture = try makeSuite("scalar")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.defaults.set(8.5, forKey: "sleepGoalHours")
        LegacyAppGroupDataMigration.migrateLegacyStandardPreferences(defaults: fixture.defaults)

        XCTAssertEqual(fixture.defaults.double(forKey: "daily_sleep_goal_hours"), 8.5)
        XCTAssertNil(fixture.defaults.object(forKey: "sleepGoalHours"))

        // 再次运行不改写已有新值。
        fixture.defaults.set(7.0, forKey: "daily_sleep_goal_hours")
        LegacyAppGroupDataMigration.migrateLegacyStandardPreferences(defaults: fixture.defaults)
        XCTAssertEqual(fixture.defaults.double(forKey: "daily_sleep_goal_hours"), 7.0)
    }

    @MainActor func testScalarNewKeyWinsWhenAlreadyPresent() throws {
        let fixture = try makeSuite("scalar-wins")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.defaults.set(9.0, forKey: "daily_sleep_goal_hours")
        fixture.defaults.set(6.0, forKey: "sleepGoalHours")

        LegacyAppGroupDataMigration.migrateLegacyStandardPreferences(defaults: fixture.defaults)

        XCTAssertEqual(fixture.defaults.double(forKey: "daily_sleep_goal_hours"), 9.0)
        XCTAssertNil(fixture.defaults.object(forKey: "sleepGoalHours"))
    }
}
