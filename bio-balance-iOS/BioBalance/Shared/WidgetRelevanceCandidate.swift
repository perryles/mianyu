import Foundation

enum WidgetRelevanceKind: String, Codable, Sendable, Hashable {
    case morningRecovery
    case recoveryAction
    case activityProgress
    case sleepPreparation
    case hydration
}

struct WidgetRelevanceCandidate: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let kind: WidgetRelevanceKind
    let startDate: Date
    let endDate: Date
    let priority: Int
    let title: String
    let detail: String
    let symbolName: String
    let deepLink: URL
}

enum WidgetRelevanceResolver {
    static func candidates(
        from snapshot: AppGroupHealthSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WidgetRelevanceCandidate] {
        var values: [WidgetRelevanceCandidate] = []
        let hour = calendar.component(.hour, from: now)

        if !snapshot.sleep.freshness.isStale(at: now),
           (6..<11).contains(hour),
           let score = snapshot.sleep.score {
            values.append(candidate(
                id: "morning-recovery",
                kind: .morningRecovery,
                now: now,
                duration: 2 * 60 * 60,
                priority: 80,
                title: "昨夜恢复",
                detail: "睡眠评分 \(score)",
                symbol: "bed.double.fill",
                path: "widget/sleep"
            ))
        }

        if !snapshot.activity.freshness.isStale(at: now),
           snapshot.activity.sedentaryIsCounting == true,
           let minutes = snapshot.activity.sedentaryElapsedMinutes,
           minutes >= 60 {
            values.append(candidate(
                id: "sedentary-recovery",
                kind: .recoveryAction,
                now: now,
                duration: 90 * 60,
                priority: 100,
                title: "起来活动一下",
                detail: "已久坐 \(minutes) 分钟",
                symbol: "figure.walk",
                path: "widget/activity"
            ))
        } else if !snapshot.vitals.freshness.isStale(at: now),
                  let stress = snapshot.vitals.stress,
                  stress >= 60 {
            values.append(candidate(
                id: "stress-recovery",
                kind: .recoveryAction,
                now: now,
                duration: 60 * 60,
                priority: 95,
                title: "安排一次恢复",
                detail: "当前压力偏高",
                symbol: "wind",
                path: "widget/stress"
            ))
        }

        let activityProgress = snapshot.activity.freshness.isStale(at: now)
            ? nil
            : completionRate(value: snapshot.activity.steps, goal: snapshot.activity.stepsGoal)
        if let activityProgress, (0.8..<1).contains(activityProgress) {
            values.append(candidate(
                id: "activity-progress",
                kind: .activityProgress,
                now: now,
                duration: 2 * 60 * 60,
                priority: 70,
                title: "今日目标快完成了",
                detail: "已完成 \(Int(activityProgress * 100))%",
                symbol: "figure.run.circle.fill",
                path: "widget/activity"
            ))
        }

        if !snapshot.sleep.freshness.isStale(at: now),
           (20...23).contains(hour),
           snapshot.sleep.lateNightRecoveryPrompt != nil || snapshot.sleep.environmentPrompt != nil {
            values.append(candidate(
                id: "sleep-preparation",
                kind: .sleepPreparation,
                now: now,
                duration: 3 * 60 * 60,
                priority: 75,
                title: "准备今晚睡眠",
                detail: snapshot.sleep.lateNightRecoveryPrompt ?? snapshot.sleep.environmentPrompt ?? "查看睡眠建议",
                symbol: "moon.stars.fill",
                path: "widget/sleep"
            ))
        }

        if !snapshot.hydration.freshness.isStale(at: now),
           (10..<20).contains(hour),
           let rate = snapshot.hydration.waterCompletionRate,
           rate.isFinite,
           rate >= 0,
           rate < 0.6 {
            values.append(candidate(
                id: "hydration",
                kind: .hydration,
                now: now,
                duration: 2 * 60 * 60,
                priority: 65,
                title: "补充一些水分",
                detail: "今日补水完成 \(Int(rate * 100))%",
                symbol: "drop.fill",
                path: "widget/overall"
            ))
        }

        return values.sorted {
            if $0.priority == $1.priority { return $0.startDate < $1.startDate }
            return $0.priority > $1.priority
        }
    }

    private static func completionRate(value: Int?, goal: Int?) -> Double? {
        guard let value, let goal, goal > 0 else { return nil }
        return min(max(Double(value) / Double(goal), 0), 1)
    }

    private static func candidate(
        id: String,
        kind: WidgetRelevanceKind,
        now: Date,
        duration: TimeInterval,
        priority: Int,
        title: String,
        detail: String,
        symbol: String,
        path: String
    ) -> WidgetRelevanceCandidate {
        WidgetRelevanceCandidate(
            id: id,
            kind: kind,
            startDate: now,
            endDate: now.addingTimeInterval(duration),
            priority: priority,
            title: title,
            detail: detail,
            symbolName: symbol,
            deepLink: URL(string: "biobalance://\(path)")!
        )
    }
}
