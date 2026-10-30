import Foundation

/// Dashboard 刷新策略。把去重和缓存有效期从视图模型中抽离，便于独立测试。
struct DashboardRefreshPolicy: Sendable {
    let minimumInterval: Duration

    init(minimumInterval: Duration = .seconds(30)) {
        self.minimumInterval = minimumInterval
    }

    func shouldRefresh(
        requestedDate: Date,
        lastLoadedDate: Date?,
        lastLoadedAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        calendar: Calendar,
        force: Bool
    ) -> Bool {
        guard !force else { return true }
        guard let lastLoadedDate, let lastLoadedAt else { return true }
        guard calendar.isDate(requestedDate, inSameDayAs: lastLoadedDate) else { return true }
        return lastLoadedAt.duration(to: now) >= minimumInterval
    }
}
