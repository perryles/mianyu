/// HolographicBadgeStore：全息徽章的解锁状态中枢。
///
/// 进度从既有行为 Store（心情/打卡/健康报告等）实时聚合；解锁时间与庆祝确认
/// 持久化到 SwiftData（domain "badge"，kind "snapshot"），模式与 MoodStore 一致。

import Foundation
import SwiftData

final class HolographicBadgeStore {
    static let shared = HolographicBadgeStore()

    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let calendar = Calendar.current
    private let domain = "badge"
    private let kind = "snapshot"

    init(container: ModelContainer = MianyuModelContainer.shared) {
        records = SwiftDataRecordStore(container: container)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - 目录

    /// 徽章目录：月度挑战系列 + 累计系列。
    static let catalog: [HolographicBadgeDefinition] = [
        HolographicBadgeDefinition(
            id: "monthly.mood",
            titleKey: "月度心境挑战",
            seriesKey: "月度挑战",
            theme: .azureGold,
            symbol: "face.smiling",
            requirementKey: "本月记录 %lld 天心情",
            requiredDays: 10,
            isMonthly: true
        ),
        HolographicBadgeDefinition(
            id: "monthly.checkin",
            titleKey: "月度活力挑战",
            seriesKey: "月度挑战",
            theme: .warmGold,
            symbol: "flame.fill",
            requirementKey: "本月完成 %lld 天行为打卡",
            requiredDays: 12,
            isMonthly: true
        ),
        HolographicBadgeDefinition(
            id: "monthly.sleep",
            titleKey: "月度安睡挑战",
            seriesKey: "月度挑战",
            theme: .jade,
            symbol: "moon.stars.fill",
            requirementKey: "本月生成 %lld 天健康报告",
            requiredDays: 15,
            isMonthly: true
        ),
        HolographicBadgeDefinition(
            id: "streak.mood",
            titleKey: "心境收藏家",
            seriesKey: "累计记录",
            theme: .bronze,
            symbol: "heart.circle.fill",
            requirementKey: "累计记录 %lld 天心情",
            requiredDays: 30,
            isMonthly: false
        ),
        HolographicBadgeDefinition(
            id: "streak.checkin",
            titleKey: "活力常驻者",
            seriesKey: "累计记录",
            theme: .warmGold,
            symbol: "bolt.heart.fill",
            requirementKey: "累计完成 %lld 天行为打卡",
            requiredDays: 50,
            isMonthly: false
        ),
        HolographicBadgeDefinition(
            id: "streak.sleep",
            titleKey: "安睡守望者",
            seriesKey: "累计记录",
            theme: .iridescent,
            symbol: "bed.double.fill",
            requirementKey: "累计生成 %lld 天健康报告",
            requiredDays: 60,
            isMonthly: false
        )
    ]

    static func definition(id: String) -> HolographicBadgeDefinition? {
        catalog.first(where: { $0.id == id })
    }

    // MARK: - 状态派生

    /// 聚合全部徽章状态（按目录顺序），并在聚合时写入新解锁的快照。
    /// 新解锁（进度达标但还没有快照）会以当前时间落库，随后触发通知。
    func allStatuses() -> [HolographicBadgeStatus] {
        let snapshots = loadSnapshots()
        let snapshotByID = Dictionary(snapshots.map { ($0.badgeID, $0) }, uniquingKeysWith: { current, _ in current })
        let progressByBadge = Self.progressByBadgeID(calendar: calendar)

        var updated = snapshots
        var hasNewUnlock = false

        let statuses = Self.catalog.map { definition in
            let progress = progressByBadge[definition.id] ?? 0
            let existing = snapshotByID[definition.id]
            let unlockedAt: Date?
            if let existing {
                unlockedAt = existing.unlockedAt
            } else if progress >= definition.requiredDays {
                // 历史已达标但还没有快照：以当前时刻解锁并落库。
                unlockedAt = Date()
                updated.append(
                    HolographicBadgeSnapshot(badgeID: definition.id, unlockedAt: unlockedAt!)
                )
                hasNewUnlock = true
            } else {
                unlockedAt = nil
            }
            // 弹窗确认前一直视为待庆祝（即使跨启动）。
            let isPending = unlockedAt != nil && (existing?.celebratedAt == nil)
            return HolographicBadgeStatus(
                definition: definition,
                progressDays: progress,
                unlockedAt: unlockedAt,
                isPendingCelebration: isPending
            )
        }

        if hasNewUnlock {
            persist(updated)
            NotificationCenter.default.post(name: .holographicBadgesDidChange, object: self)
        }
        return statuses
    }

    func status(for badgeID: String) -> HolographicBadgeStatus? {
        allStatuses().first(where: { $0.id == badgeID })
    }

    /// 未确认庆祝的解锁（弹窗用，按解锁时间倒序）。
    func pendingCelebrations() -> [HolographicBadgeStatus] {
        allStatuses()
            .filter(\.isPendingCelebration)
            .sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }
    }

    func unlockedCount() -> Int {
        loadSnapshots().count
    }

    /// 解锁进度击败的虚拟用户百分比（展示型，不做真实排行）。
    func percentileText(unlocked: Int) -> String? {
        guard unlocked > 0 else { return nil }
        let percent = min(99, 60 + unlocked * 4)
        return String(localized: "超过 \(percent)% 用户")
    }

    // MARK: - 庆祝确认

    /// 用户在弹窗点「收入囊中」后调用。
    func markCelebrated(badgeID: String) {
        var snapshots = loadSnapshots()
        guard let index = snapshots.firstIndex(where: { $0.badgeID == badgeID }) else { return }
        guard snapshots[index].celebratedAt == nil else { return }
        snapshots[index].celebratedAt = Date()
        persist(snapshots)
        NotificationCenter.default.post(name: .holographicBadgesDidChange, object: self)
    }

    // MARK: - 进度聚合（供解锁判定与详情页复用）

    /// 各徽章在当前窗口（本月 / 全部累计）内的达成天数。
    static func progressByBadgeID(calendar: Calendar) -> [String: Int] {
        var result: [String: Int] = [:]

        let moodDates = MoodStore.shared.allEntries().map(\.loggedAt)
        let drinkDates = DrinkExperienceStore.shared.allStamps().map(\.capturedAt)
        let mealDates = DrinkExperienceStore.shared.allMealRecords().map(\.capturedAt)
        let recoveryDates = RecoveryChallengeStore.shared.allRecords()
            .flatMap { record in
                record.dayProgresses
                    .filter { $0.status == .completed || $0.status == .failed }
                    .map(\.date)
            }
        let wellnessDates = DailyWellnessStore.shared.allRecords().map(\.date)
        let actionDates = ActionRecordStore.shared.allRecords().map(\.date)

        let checkinDates = (drinkDates + mealDates + recoveryDates + wellnessDates + actionDates)

        result["monthly.mood"] = distinctDayCount(dates: moodDates, in: currentMonth(calendar: calendar), calendar: calendar)
        result["monthly.checkin"] = distinctDayCount(dates: checkinDates, in: currentMonth(calendar: calendar), calendar: calendar)
        result["monthly.sleep"] = distinctDayCount(dates: wellnessDates, in: currentMonth(calendar: calendar), calendar: calendar)
        result["streak.mood"] = distinctDayCount(dates: moodDates, in: nil, calendar: calendar)
        result["streak.checkin"] = distinctDayCount(dates: checkinDates, in: nil, calendar: calendar)
        result["streak.sleep"] = distinctDayCount(dates: wellnessDates, in: nil, calendar: calendar)

        return result
    }

    private static func currentMonth(calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .month, for: Date())
    }

    private static func distinctDayCount(dates: [Date], in interval: DateInterval?, calendar: Calendar) -> Int {
        var dayKeys = Set<String>()
        for date in dates {
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            dayKeys.insert(String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0))
        }
        guard let interval else { return dayKeys.count }
        let startComps = calendar.dateComponents([.year, .month, .day], from: interval.start)
        let startKey = String(format: "%04d-%02d-%02d", startComps.year ?? 0, startComps.month ?? 0, startComps.day ?? 0)
        let endComps = calendar.dateComponents([.year, .month, .day], from: interval.end.addingTimeInterval(-1))
        let endKey = String(format: "%04d-%02d-%02d", endComps.year ?? 0, endComps.month ?? 0, endComps.day ?? 0)
        return dayKeys.filter { $0 >= startKey && $0 <= endKey }.count
    }

    // MARK: - 快照持久化

    private func loadSnapshots() -> [HolographicBadgeSnapshot] {
        guard let rows = records.records(domain: domain, kind: kind) else { return [] }
        return rows.compactMap { try? decoder.decode(HolographicBadgeSnapshot.self, from: $0.payload) }
    }

    private func persist(_ snapshots: [HolographicBadgeSnapshot]) {
        let seeds = snapshots.map { snapshot -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(snapshot) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: snapshot.badgeID,
                kind: kind,
                occurredAt: snapshot.unlockedAt,
                updatedAt: snapshot.celebratedAt ?? snapshot.unlockedAt,
                payload: data
            )
        }
        for seed in seeds.compactMap({ $0 }) {
            _ = records.upsert(seed)
        }
    }
}

// MARK: - 通知

extension Notification.Name {
    static let holographicBadgesDidChange = Notification.Name("holographicBadgesDidChange")
}
