import Foundation

struct RecoveryActionLoopReview: Equatable, Sendable {
    let days: Int
    let plannedCount: Int
    let processedCount: Int
    let completedCount: Int
    let snoozedCount: Int
    let skippedCount: Int
    let notApplicableCount: Int
    let feedbackCount: Int
    let betterCount: Int
    let similarCount: Int
    let harderCount: Int
    let headline: String
    let detail: String

    var completionRate: Double? {
        guard plannedCount > 0 else { return nil }
        return Double(completedCount) / Double(plannedCount)
    }

    var feedbackCoverage: Double? {
        guard completedCount > 0 else { return nil }
        return Double(feedbackCount) / Double(completedCount)
    }
}

enum RecoveryActionLoopEngine {
    static func make(
        records: [DailyRecoveryActionStateRecord],
        days: Int = 7,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> RecoveryActionLoopReview {
        let normalizedDays = max(1, days)
        let end = referenceDate
        let startDay = calendar.date(
            byAdding: .day,
            value: -(normalizedDays - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? calendar.startOfDay(for: referenceDate)
        let scoped = records.filter { record in
            let date = record.plannedFor ?? record.updatedAt
            return date >= startDay && date <= end
        }
        let completed = scoped.filter { $0.state == .completed }
        let feedback = completed.compactMap(\.feedback)
        let plannedCount = scoped.count
        let completedCount = completed.count
        let feedbackCount = feedback.count

        let headline: String
        let detail: String
        if plannedCount == 0 {
            headline = String(localized: "最近还没有恢复行动记录")
            detail = String(localized: "形成每日恢复计划并处理行动后，这里会汇总完成事实和可选体感。")
        } else if completedCount == 0 {
            headline = String(localized: "先完成一个低负担行动")
            detail = String(localized: "最近 \(normalizedDays) 天计划了 \(plannedCount) 项行动，目前还没有完成记录。稍后、跳过和不适用都不会降低健康评分。")
        } else {
            let percent = Int((Double(completedCount) / Double(plannedCount) * 100).rounded())
            headline = String(localized: "最近 \(normalizedDays) 天完成了 \(completedCount) 项恢复行动")
            if feedbackCount == 0 {
                detail = String(localized: "完成率约 \(percent)%。下次完成后可选记录体感，帮助回看哪些行动更容易坚持。")
            } else {
                detail = String(localized: "完成率约 \(percent)%，其中 \(feedbackCount) 项补充了主观体感。体感只用于个人回看，不代表行动产生了因果效果。")
            }
        }

        return RecoveryActionLoopReview(
            days: normalizedDays,
            plannedCount: plannedCount,
            processedCount: scoped.filter { $0.state != .pending }.count,
            completedCount: completedCount,
            snoozedCount: scoped.filter { $0.state == .snoozed }.count,
            skippedCount: scoped.filter { $0.state == .skipped }.count,
            notApplicableCount: scoped.filter { $0.state == .notApplicable }.count,
            feedbackCount: feedbackCount,
            betterCount: feedback.filter { $0 == .better }.count,
            similarCount: feedback.filter { $0 == .similar }.count,
            harderCount: feedback.filter { $0 == .harder }.count,
            headline: headline,
            detail: detail
        )
    }
}

