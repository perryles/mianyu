/// ProfileHeatmapViewModel 作为个人资料页热力图的数据支撑。
/// 负责定义每日健康分数、数据来源和健康指标计数的数据模型（ProfileHeatmapDay）。

import Foundation
import SwiftUI

// MARK: - 数据类型

struct ProfileHeatmapDay: Identifiable {
    let date: Date
    let score: Int?
    let source: ProfileHeatmapSource
    let healthMetricCount: Int
    let behaviorSignalCount: Int

    var id: TimeInterval { date.timeIntervalSince1970 }
    var hasActivity: Bool { score != nil || behaviorSignalCount > 0 }

    static func empty(for date: Date) -> ProfileHeatmapDay {
        ProfileHeatmapDay(
            date: Calendar.current.startOfDay(for: date),
            score: nil,
            source: .none,
            healthMetricCount: 0,
            behaviorSignalCount: 0
        )
    }
}

enum ProfileHeatmapSource: Equatable {
    case health
    case healthAndRecords
    case records
    case none

    var title: String {
        switch self {
        case .health: return "健康综合评分"
        case .healthAndRecords: return "健康综合评分"
        case .records: return "行为记录"
        case .none: return "暂无数据"
        }
    }

    func detailText(healthMetricCount: Int, behaviorSignalCount: Int) -> String {
        switch self {
        case .health:
            return String(localized: "报告同源健康指标 \(healthMetricCount) 项")
        case .healthAndRecords:
            return String(localized: "报告同源健康指标 \(healthMetricCount) 项 · 另有行为记录信号 \(behaviorSignalCount) 类")
        case .records:
            return String(localized: "无健康综合分 · 当天行为记录信号 \(behaviorSignalCount) 类")
        case .none:
            return String(localized: "当天暂无可用健康样本或行为记录")
        }
    }
}

// MARK: - 视图模型

@Observable
final class ProfileHeatmapViewModel {

    // MARK: 状态

    var refreshToken = UUID()
    var selectedDayID: TimeInterval?
    var monthOffset = 0
    private(set) var lastHealthScoreLoadAt: Date?

    // MARK: 月份派生属性

    var selectedMonth: Date {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start
            ?? calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .month, value: monthOffset, to: currentMonth)
            ?? currentMonth
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("yyyyMM")
        return formatter.string(from: selectedMonth)
    }

    // MARK: 操作

    func shiftMonth(by offset: Int) {
        let nextOffset = min(0, max(-3, monthOffset + offset))
        guard nextOffset != monthOffset else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            monthOffset = nextOffset
            selectedDayID = nil
        }
    }

    func refresh() {
        refreshToken = UUID()
    }

    func shouldLoadHealthScores(hasScores: Bool, force: Bool) -> Bool {
        let now = Date()
        let refreshInterval: TimeInterval = hasScores ? 5 * 60 : 60
        if !force,
           let lastLoad = lastHealthScoreLoadAt,
           now.timeIntervalSince(lastLoad) < refreshInterval {
            return false
        }
        return true
    }

    func markHealthScoreLoaded() {
        lastHealthScoreLoadAt = Date()
    }

    // MARK: - 计算逻辑

    func computeDisplayDays(count: Int, reportDays: [ReportDaySummary]) -> [ProfileHeatmapDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let wellnessByDay = Dictionary(
            DailyWellnessStore.shared.allRecords().map { (dayKey(for: $0.date), $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let actionByDay = Dictionary(
            ActionRecordStore.shared.allRecords().map { (dayKey(for: $0.date), $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let moodCountsByDay = countByDay(MoodStore.shared.allEntries().map(\.loggedAt))
        let medicationCountsByDay = countByDay(MedicationStore.shared.allEntries().map(\.takenAt))
        let caffeineCountsByDay = countByDay(CaffeineDoseEventStore.shared.allEvents().map(\.consumedAt))
        let drinkCountsByDay = countByDay(DrinkExperienceStore.shared.allStamps().map(\.capturedAt))
        let mealCountsByDay = countByDay(DrinkExperienceStore.shared.allMealRecords().map(\.capturedAt))
        let recoveryCountsByDay = recoveryChallengeCountByDay()
        let reportByDay = Dictionary(
            reportDays.map { (dayKey(for: $0.date), $0) },
            uniquingKeysWith: { current, _ in current }
        )

        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - (count - 1), to: today) else {
                return nil
            }

            let key = dayKey(for: date)
            let wellness = wellnessByDay[key]
            let action = actionByDay[key]
            let behaviorSignalCount = heatmapSignalCount(
                wellness: wellness,
                action: action,
                moodCount: moodCountsByDay[key, default: 0],
                medicationCount: medicationCountsByDay[key, default: 0],
                caffeineCount: caffeineCountsByDay[key, default: 0],
                drinkCount: drinkCountsByDay[key, default: 0],
                mealCount: mealCountsByDay[key, default: 0],
                recoveryCount: recoveryCountsByDay[key, default: 0]
            )
            let report = reportByDay[key]
            let healthMetricCount = self.healthMetricCount(report)
            let score: Int?
            let source: ProfileHeatmapSource

            if let reportScore = report?.score {
                score = reportScore
                source = behaviorSignalCount > 0 ? .healthAndRecords : .health
            } else if behaviorSignalCount > 0 {
                score = nil
                source = .records
            } else {
                score = nil
                source = .none
            }

            return ProfileHeatmapDay(
                date: date,
                score: score,
                source: source,
                healthMetricCount: healthMetricCount,
                behaviorSignalCount: behaviorSignalCount
            )
        }
    }

    func monthDays(from days: [ProfileHeatmapDay]) -> [ProfileHeatmapDay] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: selectedMonth) else {
            return []
        }
        let daysByKey = Dictionary(
            days.map { (dayKey(for: $0.date), $0) },
            uniquingKeysWith: { current, _ in current }
        )
        var result: [ProfileHeatmapDay] = []
        var date = interval.start
        while date < interval.end {
            result.append(
                daysByKey[dayKey(for: date)]
                    ?? ProfileHeatmapDay.empty(for: date)
            )
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? interval.end
        }
        return result
    }

    func activeDays(in days: [ProfileHeatmapDay]) -> Int {
        days.filter(\.hasActivity).count
    }

    func averageScore(in days: [ProfileHeatmapDay]) -> Int? {
        let scores = days.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    func healthDays(in days: [ProfileHeatmapDay]) -> Int {
        days.filter { $0.score != nil }.count
    }

    func bestStreak(in days: [ProfileHeatmapDay]) -> Int {
        var best = 0
        var current = 0
        for day in days {
            if day.hasActivity {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    // MARK: - 私有辅助方法

    func dayKey(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private func heatmapSignalCount(
        wellness: DailyWellnessDayRecord?,
        action: LocalActionDayRecord?,
        moodCount: Int,
        medicationCount: Int,
        caffeineCount: Int,
        drinkCount: Int,
        mealCount: Int,
        recoveryCount: Int
    ) -> Int {
        var count = 0

        if let wellness {
            count += wellness.completedActions.count
            if wellness.microRecoveryCount > 0 {
                count += 1
            }
        }

        count += actionSignalCount(action)
        count += fitnessSignalCount(action?.fitnessCheckinMode)

        if moodCount > 0 { count += 1 }
        if medicationCount > 0 { count += 1 }
        if caffeineCount > 0 { count += 1 }
        if drinkCount > 0 { count += 1 }
        if mealCount > 0 { count += 1 }
        if recoveryCount > 0 { count += 1 }

        return count
    }

    private func actionSignalCount(_ record: LocalActionDayRecord?) -> Int {
        guard let record else { return 0 }
        var count = 0
        if record.waterMl > 0 { count += 1 }
        if record.caffeineMg > 0 { count += 1 }
        if record.sunlightMinutes > 0 { count += 1 }
        if record.mindfulnessMinutes > 0 { count += 1 }
        if record.standHours > 0 { count += 1 }
        count += record.completedActions.count
        if record.manualWorkoutMinutes > 0 { count += 1 }
        if record.manualWorkoutEffort != nil { count += 1 }
        if record.hasTrainingNote { count += 1 }
        if record.isShared { count += 1 }
        return count
    }

    private func fitnessSignalCount(_ mode: FitnessCheckinMode?) -> Int {
        mode == nil ? 0 : 1
    }

    private func healthMetricCount(_ summary: ReportDaySummary?) -> Int {
        guard let summary else { return 0 }
        var count = 0
        if let sleepHours = summary.sleepHours, sleepHours > 0 { count += 1 }
        if let stress = summary.stress, stress > 0 { count += 1 }
        if let hrv = summary.hrv, hrv > 0 { count += 1 }
        if let steps = summary.steps, steps > 0 { count += 1 }
        return count
    }

    private func countByDay(_ dates: [Date]) -> [String: Int] {
        Dictionary(grouping: dates, by: dayKey(for:))
            .mapValues(\.count)
    }

    private func recoveryChallengeCountByDay() -> [String: Int] {
        let dates = RecoveryChallengeStore.shared.allRecords()
            .flatMap { record in
                record.dayProgresses
                    .filter { $0.status == .completed || $0.status == .failed }
                    .map(\.date)
            }
        return countByDay(dates)
    }
}
