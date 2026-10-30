import XCTest
@testable import BioBalance

nonisolated final class AppDataCacheManagerTests: XCTestCase {
    @MainActor func testSnapshotCountsItemsAcrossLocalSharedAndWatchDefaults() throws {
        let suite = makeSuiteNames()
        let localDefaults = try XCTUnwrap(UserDefaults(suiteName: suite.local))
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite.shared))
        defer {
            localDefaults.removePersistentDomain(forName: suite.local)
            sharedDefaults.removePersistentDomain(forName: suite.shared)
        }

        localDefaults.set(Data(repeating: 1, count: 10), forKey: HealthDataManager.LocalCacheKeys.activity)
        localDefaults.set("stress-cache", forKey: StressStore.cacheKey)
        localDefaults.set(Data(repeating: 2, count: 6), forKey: WatchConnectivitySyncService.cachedPayloadKey)
        sharedDefaults.set(12_000, forKey: AppGroupManager.Keys.steps)
        sharedDefaults.set(Data(repeating: 3, count: 20), forKey: AppGroupSnapshotStore.widgetSnapshotV2Key)

        let manager = AppDataCacheManager(
            localDefaults: localDefaults,
            sharedDefaults: sharedDefaults,
            resetRuntimeStateOnClear: false
        )
        let snapshot = manager.snapshot()

        XCTAssertEqual(snapshot.category(.localPageSnapshots).itemCount, 2)
        XCTAssertEqual(snapshot.category(.sharedWidgetSnapshots).itemCount, 2)
        XCTAssertEqual(snapshot.category(.watchTransportSnapshots).itemCount, 1)
        XCTAssertEqual(snapshot.totalItemCount, 5)
        XCTAssertEqual(snapshot.totalBytes, 10 + 12 + 8 + 20 + 6)
    }

    @MainActor func testPartialClearRemovesOnlySelectedCategory() throws {
        let suite = makeSuiteNames()
        let localDefaults = try XCTUnwrap(UserDefaults(suiteName: suite.local))
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite.shared))
        defer {
            localDefaults.removePersistentDomain(forName: suite.local)
            sharedDefaults.removePersistentDomain(forName: suite.shared)
        }

        localDefaults.set(Data(repeating: 1, count: 10), forKey: HealthDataManager.LocalCacheKeys.activity)
        localDefaults.set(Data(repeating: 2, count: 6), forKey: WatchConnectivitySyncService.cachedPayloadKey)
        sharedDefaults.set(12_000, forKey: AppGroupManager.Keys.steps)

        let manager = AppDataCacheManager(
            localDefaults: localDefaults,
            sharedDefaults: sharedDefaults,
            resetRuntimeStateOnClear: false
        )
        let result = manager.clear(categories: [.localPageSnapshots])

        XCTAssertEqual(result.removedItemCount, 1)
        XCTAssertEqual(result.removedBytes, 10)
        XCTAssertNil(localDefaults.object(forKey: HealthDataManager.LocalCacheKeys.activity))
        XCTAssertNotNil(localDefaults.object(forKey: WatchConnectivitySyncService.cachedPayloadKey))
        XCTAssertNotNil(sharedDefaults.object(forKey: AppGroupManager.Keys.steps))
        XCTAssertEqual(result.remainingSnapshot.category(.localPageSnapshots).itemCount, 0)
        XCTAssertEqual(result.remainingSnapshot.category(.watchTransportSnapshots).itemCount, 1)
        XCTAssertEqual(result.remainingSnapshot.category(.sharedWidgetSnapshots).itemCount, 1)
    }

    @MainActor func testClearAllRemovesEveryKnownCacheKey() throws {
        let suite = makeSuiteNames()
        let localDefaults = try XCTUnwrap(UserDefaults(suiteName: suite.local))
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite.shared))
        defer {
            localDefaults.removePersistentDomain(forName: suite.local)
            sharedDefaults.removePersistentDomain(forName: suite.shared)
        }

        localDefaults.set(Data(repeating: 1, count: 10), forKey: HealthDataManager.LocalCacheKeys.activity)
        localDefaults.set("stress-cache", forKey: StressStore.cacheKey)
        localDefaults.set(Data(repeating: 2, count: 6), forKey: WatchConnectivitySyncService.cachedPayloadKey)
        sharedDefaults.set(12_000, forKey: AppGroupManager.Keys.steps)
        sharedDefaults.set(Data(repeating: 3, count: 20), forKey: AppGroupSnapshotStore.widgetSnapshotV2Key)

        let manager = AppDataCacheManager(
            localDefaults: localDefaults,
            sharedDefaults: sharedDefaults,
            resetRuntimeStateOnClear: false
        )
        let before = manager.snapshot()
        let result = manager.clear()

        XCTAssertEqual(result.removedItemCount, before.totalItemCount)
        XCTAssertEqual(result.removedBytes, before.totalBytes)
        XCTAssertEqual(result.removedItemCount, 5)
        XCTAssertNil(localDefaults.object(forKey: HealthDataManager.LocalCacheKeys.activity))
        XCTAssertNil(localDefaults.object(forKey: StressStore.cacheKey))
        XCTAssertNil(localDefaults.object(forKey: WatchConnectivitySyncService.cachedPayloadKey))
        XCTAssertNil(sharedDefaults.object(forKey: AppGroupManager.Keys.steps))
        XCTAssertNil(sharedDefaults.object(forKey: AppGroupSnapshotStore.widgetSnapshotV2Key))
        XCTAssertEqual(result.remainingSnapshot.totalItemCount, 0)
    }

    @MainActor func testClearWithoutSharedDefaultsKeepsSharedCategoryEmpty() throws {
        let suite = makeSuiteNames()
        let localDefaults = try XCTUnwrap(UserDefaults(suiteName: suite.local))
        defer { localDefaults.removePersistentDomain(forName: suite.local) }

        localDefaults.set(Data(repeating: 1, count: 4), forKey: HealthDataManager.LocalCacheKeys.activity)
        localDefaults.set(Data(repeating: 2, count: 3), forKey: WatchConnectivitySyncService.cachedPayloadKey)

        let manager = AppDataCacheManager(
            localDefaults: localDefaults,
            sharedDefaults: nil,
            resetRuntimeStateOnClear: false
        )
        let result = manager.clear()

        XCTAssertEqual(result.removedItemCount, 2)
        XCTAssertEqual(result.removedBytes, 7)
        XCTAssertEqual(result.remainingSnapshot.category(.sharedWidgetSnapshots).itemCount, 0)
    }

    @MainActor private func makeSuiteNames() -> (local: String, shared: String) {
        let id = UUID().uuidString
        return ("AppDataCacheManagerTests.local.\(id)", "AppDataCacheManagerTests.shared.\(id)")
    }

    @MainActor func testRepositoryCacheSupportsConcurrentWritesAndDomainInvalidation() async throws {
        let suiteName = "RepositoryCacheConcurrency.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = HealthKitRepositoryCache(defaults: defaults)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    let key = HealthKitRepositoryCacheKey(domain: "heart", name: "summary", parameters: String(index))
                    cache.store(index, for: key)
                }
            }
        }
        for index in 0..<8 {
            let key = HealthKitRepositoryCacheKey(domain: "heart", name: "summary", parameters: String(index))
            let value: Int? = cache.value(for: key)
            XCTAssertEqual(value, index)
        }
        cache.invalidate(domains: ["heart"])
        let key = HealthKitRepositoryCacheKey(domain: "heart", name: "summary", parameters: "0")
        let invalidated: Int? = cache.value(for: key)
        XCTAssertNil(invalidated)
        cache.store(42, for: key)
        let refreshed: Int? = cache.value(for: key)
        XCTAssertEqual(refreshed, 42)
    }
}
