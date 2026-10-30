/// CareAdherenceCalculator 提供更细粒度的完成率统计分析。
/// 作为 CareTaskEngine.adherenceSummary/weeklyAdherence 的补充，
/// 支持按模块、按任务和按日期的交叉分析。

import Foundation

nonisolated struct CareAdherenceBreakdown: Hashable, Sendable, Identifiable {
    var id: String { logicalTaskID ?? category.rawValue }
    let logicalTaskID: String?
    let category: CareTaskCategory
    let title: String
    let totalEvents: Int
    let completedEvents: Int
    let adherenceRate: Double
    let currentStreak: Int

    var formattedAdherence: String {
        totalEvents > 0
            ? String(format: "%.0f%%", adherenceRate * 100)
            : "--"
    }
}

@MainActor
enum CareAdherenceCalculator {

    /// 按任务维度拆解完成率
    static func breakdownByTask(days: Int = 14, category: CareTaskCategory? = nil, referenceDate: Date = Date()) -> [CareAdherenceBreakdown] {
        let engine = CareTaskEngine.shared
        let calendar = Calendar.current

        // 收集每个逻辑任务的完成统计
        var stats: [String: (task: CareTask, total: Int, completed: Int)] = [:]
        var streaks: [String: Int] = [:]

        for dayOffset in 0..<max(1, days) {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: referenceDate) else { continue }
            let dayEvents = engine.events(on: date, referenceDate: referenceDate)
            let filtered = category.map { target in dayEvents.filter { $0.category == target } } ?? dayEvents

            for event in filtered {
                let key = event.logicalTaskID
                if var existing = stats[key] {
                    existing.total += 1
                    if event.status == .completed { existing.completed += 1 }
                    stats[key] = existing
                } else {
                    stats[key] = (
                        task: CareTask(
                            id: event.taskID,
                            category: event.category,
                            title: event.title,
                            icon: event.icon,
                            schedule: CareSchedule(),
                            logicalTaskID: event.logicalTaskID
                        ),
                        total: 1,
                        completed: event.status == .completed ? 1 : 0
                    )
                }
            }
        }

        // 计算当前连续完成天数
        for key in stats.keys {
            streaks[key] = computeStreak(logicalTaskID: key, referenceDate: referenceDate)
        }

        return stats.map { key, data in
            let rate = data.total > 0 ? Double(data.completed) / Double(data.total) : 0
            return CareAdherenceBreakdown(
                logicalTaskID: key,
                category: data.task.category,
                title: data.task.title,
                totalEvents: data.total,
                completedEvents: data.completed,
                adherenceRate: rate,
                currentStreak: streaks[key] ?? 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.category == rhs.category {
                return lhs.adherenceRate > rhs.adherenceRate
            }
            return lhs.category.rawValue < rhs.category.rawValue
        }
    }

    /// 按模块维度汇总
    static func breakdownByCategory(days: Int = 14, referenceDate: Date = Date()) -> [CareAdherenceBreakdown] {
        CareTaskCategory.allCases.compactMap { category in
            let summary = CareTaskEngine.shared.adherenceSummary(days: days, category: category, referenceDate: referenceDate)
            guard summary.totalEvents > 0 else { return nil }
            return CareAdherenceBreakdown(
                logicalTaskID: nil,
                category: category,
                title: category.title,
                totalEvents: summary.totalEvents,
                completedEvents: summary.completedEvents,
                adherenceRate: summary.adherenceRate,
                currentStreak: 0
            )
        }
    }

    /// 计算某任务的连续完成天数
    static func computeStreak(logicalTaskID: String, referenceDate: Date = Date()) -> Int {
        let engine = CareTaskEngine.shared
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: referenceDate)
        var streak = 0

        while true {
            let dayEvents = engine.events(on: cursor, referenceDate: referenceDate)
                .filter { $0.logicalTaskID == logicalTaskID }
            guard !dayEvents.isEmpty else { break }

            let allCompleted = dayEvents.allSatisfy { $0.status == .completed }
            if allCompleted {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            } else {
                break
            }
        }
        return streak
    }
}
