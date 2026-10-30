import XCTest
@testable import BioBalance

nonisolated final class AppGroupSnapshotSyncTests: XCTestCase {
    @MainActor func testSaveAndLoadRoundTripAcrossDefaults() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let generatedAt = Date(timeIntervalSince1970: 1_000)
        let snapshot = AppGroupHealthSnapshot.empty(generatedAt: generatedAt)

        AppGroupSnapshotStore.save(snapshot, defaults: defaults)

        XCTAssertEqual(AppGroupSnapshotStore.load(defaults: defaults), snapshot)
        XCTAssertEqual(
            defaults.double(forKey: AppGroupSnapshotStore.lastSnapshotWriteKey),
            generatedAt.timeIntervalSince1970
        )
    }

    @MainActor func testSaveRejectsOlderGeneratedAtSnapshot() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let newer = AppGroupHealthSnapshot.empty(generatedAt: Date(timeIntervalSince1970: 2_000))
        let older = AppGroupHealthSnapshot.empty(generatedAt: Date(timeIntervalSince1970: 1_000))

        AppGroupSnapshotStore.save(newer, defaults: defaults)
        AppGroupSnapshotStore.save(older, defaults: defaults)

        XCTAssertEqual(AppGroupSnapshotStore.load(defaults: defaults), newer)
        XCTAssertEqual(
            defaults.double(forKey: AppGroupSnapshotStore.lastSnapshotWriteKey),
            2_000
        )
    }

    @MainActor func testNewerEmptyRefreshPreservesPreviouslySyncedMetricDomains() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let syncedAt = Date(timeIntervalSince1970: 2_000)
        let refreshAt = Date(timeIntervalSince1970: 2_100)
        let synced = AppGroupHealthSnapshot(
            schemaVersion: AppGroupHealthSnapshot.currentSchemaVersion,
            generatedAt: syncedAt,
            vitals: .init(
                heartRate: 68,
                hrv: 52,
                stress: 24,
                stressState: "relaxed",
                stressExplanationCode: nil,
                stressConfidence: nil,
                stressTrend: "稳定",
                stressHistory: [],
                freshness: .init(updatedAt: syncedAt, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter)
            ),
            hydration: AppGroupHealthSnapshot.empty(generatedAt: syncedAt).hydration,
            activity: AppGroupHealthSnapshot.empty(generatedAt: syncedAt).activity,
            sleep: AppGroupHealthSnapshot.empty(generatedAt: syncedAt).sleep,
            summary: AppGroupHealthSnapshot.empty(generatedAt: syncedAt).summary
        )

        AppGroupSnapshotStore.save(synced, defaults: defaults)
        AppGroupSnapshotStore.save(.empty(generatedAt: refreshAt), defaults: defaults)

        let loaded = try XCTUnwrap(AppGroupSnapshotStore.load(defaults: defaults))
        XCTAssertEqual(loaded.generatedAt, refreshAt)
        XCTAssertEqual(loaded.vitals.heartRate, 68)
        XCTAssertEqual(loaded.vitals.hrv, 52)
        XCTAssertEqual(loaded.vitals.freshness.updatedAt, syncedAt)
    }

    @MainActor func testNewerEmptyRefreshDropsExpiredMetricDomain() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let syncedAt = Date(timeIntervalSince1970: 2_000)
        let refreshAt = syncedAt.addingTimeInterval(AppGroupSchema.Freshness.vitalsStaleAfter + 1)
        let synced = snapshotWithVitals(syncedAt: syncedAt)

        AppGroupSnapshotStore.save(synced, defaults: defaults)
        AppGroupSnapshotStore.save(.empty(generatedAt: refreshAt), defaults: defaults)

        let loaded = try XCTUnwrap(AppGroupSnapshotStore.load(defaults: defaults))
        XCTAssertNil(loaded.vitals.heartRate)
        XCTAssertNil(loaded.vitals.freshness.updatedAt)
    }

    @MainActor func testNewerEmptyRefreshDoesNotCarryDailyActivityAcrossMidnight() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 2_000_000_000))
        let syncedAt = try XCTUnwrap(calendar.date(byAdding: .minute, value: 23 * 60 + 30, to: dayStart))
        let refreshAt = try XCTUnwrap(calendar.date(byAdding: .hour, value: 1, to: syncedAt))
        let empty = AppGroupHealthSnapshot.empty(generatedAt: syncedAt)
        let synced = AppGroupHealthSnapshot(
            schemaVersion: AppGroupHealthSnapshot.currentSchemaVersion,
            generatedAt: syncedAt,
            vitals: empty.vitals,
            hydration: empty.hydration,
            activity: .init(
                steps: 8_000,
                stepsGoal: 8_000,
                activeEnergy: 500,
                activeEnergyGoal: 500,
                exerciseMinutes: 30,
                exerciseMinutesGoal: 30,
                standHours: 12,
                standHoursGoal: 12,
                walkingSpeedMps: nil,
                walkingPaceSecondsPerKm: nil,
                sedentaryElapsedMinutes: nil,
                sedentaryIsCounting: nil,
                freshness: .init(updatedAt: syncedAt, staleAfter: AppGroupSchema.Freshness.activityStaleAfter)
            ),
            sleep: empty.sleep,
            summary: empty.summary
        )

        AppGroupSnapshotStore.save(synced, defaults: defaults)
        AppGroupSnapshotStore.save(.empty(generatedAt: refreshAt), defaults: defaults)

        let loaded = try XCTUnwrap(AppGroupSnapshotStore.load(defaults: defaults))
        XCTAssertNil(loaded.activity.steps)
        XCTAssertNil(loaded.activity.freshness.updatedAt)
    }

    @MainActor func testLoadMigratesLegacySnapshotToV2Key() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshot = AppGroupHealthSnapshot.empty(generatedAt: Date(timeIntervalSince1970: 3_000))
        let data = try JSONEncoder().encode(snapshot)
        defaults.set(data, forKey: AppGroupSnapshotStore.legacyWidgetSnapshotV2Key)

        XCTAssertEqual(AppGroupSnapshotStore.load(defaults: defaults), snapshot)
        XCTAssertEqual(defaults.data(forKey: AppGroupSnapshotStore.widgetSnapshotV2Key), data)
        XCTAssertNil(defaults.data(forKey: AppGroupSnapshotStore.legacyWidgetSnapshotV2Key))
    }

    @MainActor func testClearRemovesAllSnapshotKeys() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppGroupSnapshotStore.save(
            AppGroupHealthSnapshot.empty(generatedAt: Date(timeIntervalSince1970: 4_000)),
            defaults: defaults
        )

        AppGroupSnapshotStore.clear(defaults: defaults)

        XCTAssertNil(AppGroupSnapshotStore.load(defaults: defaults))
        XCTAssertNil(defaults.object(forKey: AppGroupSnapshotStore.widgetSnapshotV2Key))
        XCTAssertNil(defaults.object(forKey: AppGroupSnapshotStore.legacyWidgetSnapshotV2Key))
        XCTAssertNil(defaults.object(forKey: AppGroupSnapshotStore.lastSnapshotWriteKey))
    }

    @MainActor func testMetricFreshnessExpiresAfterTTL() {
        let freshness = AppGroupHealthSnapshot.MetricFreshness(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            staleAfter: 60
        )

        XCTAssertFalse(freshness.isStale(at: Date(timeIntervalSince1970: 1_059)))
        XCTAssertTrue(freshness.isStale(at: Date(timeIntervalSince1970: 1_061)))
        XCTAssertEqual(
            freshness.nextRefreshDate(from: Date())?.timeIntervalSince1970,
            1_060
        )
    }

    @MainActor func testMetricFreshnessWithoutUpdateIsImmediatelyStale() {
        let freshness = AppGroupHealthSnapshot.MetricFreshness(updatedAt: nil, staleAfter: 60)

        XCTAssertTrue(freshness.isStale(at: Date(timeIntervalSince1970: 1_000)))
        XCTAssertNil(freshness.nextRefreshDate(from: Date(timeIntervalSince1970: 1_000)))
    }

    @MainActor func testMetricFreshnessCombinedUsesEarliestStaleBoundary() {
        let combined = AppGroupHealthSnapshot.MetricFreshness.combined([
            .init(updatedAt: Date(timeIntervalSince1970: 1_000), staleAfter: 60),
            .init(updatedAt: Date(timeIntervalSince1970: 1_010), staleAfter: 10)
        ])

        XCTAssertEqual(combined.updatedAt?.timeIntervalSince1970, 1_000)
        XCTAssertEqual(combined.staleAfter, 20)
        XCTAssertFalse(combined.isStale(at: Date(timeIntervalSince1970: 1_019)))
        XCTAssertTrue(combined.isStale(at: Date(timeIntervalSince1970: 1_021)))
    }

    @MainActor private let suiteName = "AppGroupSnapshotSyncTests.\(UUID().uuidString)"

    @MainActor private func snapshotWithVitals(syncedAt: Date) -> AppGroupHealthSnapshot {
        let empty = AppGroupHealthSnapshot.empty(generatedAt: syncedAt)
        return AppGroupHealthSnapshot(
            schemaVersion: AppGroupHealthSnapshot.currentSchemaVersion,
            generatedAt: syncedAt,
            vitals: .init(
                heartRate: 68,
                hrv: 52,
                stress: 24,
                stressState: "relaxed",
                stressExplanationCode: nil,
                stressConfidence: nil,
                stressTrend: "稳定",
                stressHistory: [],
                freshness: .init(updatedAt: syncedAt, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter)
            ),
            hydration: empty.hydration,
            activity: empty.activity,
            sleep: empty.sleep,
            summary: empty.summary
        )
    }

    @MainActor private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }
}
