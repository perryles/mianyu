import XCTest
@testable import BioBalance

nonisolated final class HealthProfileSummaryStoreCacheTests: XCTestCase {
    @MainActor func testFreshSummaryHitsCacheWithoutReloading() async {
        let dataSource = CountingHealthProfileDataSource()
        let store = makeStore(dataSource: dataSource, ttl: 600)

        let first = await store.summary()
        let second = await store.summary()

        XCTAssertEqual(first, second)
        XCTAssertEqual(dataSource.loadCount, 1)
    }

    @MainActor func testExpiredSummaryReloadsAfterTTL() async throws {
        let dataSource = CountingHealthProfileDataSource()
        let store = makeStore(dataSource: dataSource, ttl: 0.05)

        _ = await store.summary()
        try await Task.sleep(nanoseconds: 80_000_000)
        _ = await store.summary()

        XCTAssertEqual(dataSource.loadCount, 2)
    }

    @MainActor func testForceRefreshBypassesFreshCache() async {
        let dataSource = CountingHealthProfileDataSource()
        let store = makeStore(dataSource: dataSource, ttl: 600)

        _ = await store.summary()
        _ = await store.summary(forceRefresh: true)

        XCTAssertEqual(dataSource.loadCount, 2)
    }

    @MainActor func testInvalidateClearsCachedSummary() async {
        let dataSource = CountingHealthProfileDataSource()
        let store = makeStore(dataSource: dataSource, ttl: 600)

        _ = await store.summary()
        store.invalidate()
        _ = await store.summary()

        XCTAssertEqual(dataSource.loadCount, 2)
    }

    @MainActor func testConcurrentRequestsShareInFlightLoad() async {
        let dataSource = SlowCountingHealthProfileDataSource(delay: .milliseconds(60))
        let store = makeStore(dataSource: dataSource, ttl: 600)

        async let first = store.summary()
        async let second = store.summary()
        _ = await (first, second)

        XCTAssertEqual(dataSource.loadCount, 1)
    }

    @MainActor private func makeStore(
        dataSource: HealthProfileDataSource,
        ttl: TimeInterval
    ) -> HealthProfileSummaryStore {
        HealthProfileSummaryStore(
            engine: HealthProfileEngine(dataSource: dataSource, calendar: calendar()),
            cacheTTL: ttl
        )
    }

    @MainActor private func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
}

private final class CountingHealthProfileDataSource: HealthProfileDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var storedLoadCount = 0

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedLoadCount
    }

    func loadProfileData(days: Int, endDate: Date, calendar: Calendar) async -> HealthProfileData {
        lock.withLock { storedLoadCount += 1 }
        return HealthProfileData()
    }
}

private final class SlowCountingHealthProfileDataSource: HealthProfileDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var storedLoadCount = 0
    private let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedLoadCount
    }

    func loadProfileData(days: Int, endDate: Date, calendar: Calendar) async -> HealthProfileData {
        lock.withLock { storedLoadCount += 1 }
        try? await Task.sleep(for: delay)
        return HealthProfileData()
    }
}
