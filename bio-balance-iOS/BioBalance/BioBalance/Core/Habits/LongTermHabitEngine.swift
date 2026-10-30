import Foundation

enum LongTermHabitTrend: String, Codable, Equatable, Sendable {
    case collecting
    case improving
    case steady
    case needsAttention

    var title: String {
        switch self {
        case .collecting:
            return String(localized: "样本积累中")
        case .improving:
            return String(localized: "正在变稳")
        case .steady:
            return "节奏稳定"
        case .needsAttention:
            return String(localized: "需要轻扶一下")
        }
    }

    var tintHex: String {
        switch self {
        case .collecting:
            return "94A3C3"
        case .improving:
            return "58CC6A"
        case .steady:
            return "2AA7A1"
        case .needsAttention:
            return "F4A259"
        }
    }
}

enum LongTermHabitSignalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case water
    case sunlight
    case breathing
    case move
    case bedtimeWindDown
    case movementRhythm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water:
            return "补水"
        case .sunlight:
            return "日照"
        case .breathing:
            return "呼吸"
        case .move:
            return String(localized: "起身")
        case .bedtimeWindDown:
            return "睡前收尾"
        case .movementRhythm:
            return "训练/恢复"
        }
    }

    var symbol: String {
        switch self {
        case .water:
            return "drop.fill"
        case .sunlight:
            return "sun.max.fill"
        case .breathing:
            return "wind"
        case .move:
            return "figure.walk"
        case .bedtimeWindDown:
            return "moon.stars.fill"
        case .movementRhythm:
            return "figure.mind.and.body"
        }
    }

    var tintHex: String {
        switch self {
        case .water:
            return "32ADE6"
        case .sunlight:
            return "F4B46B"
        case .breathing:
            return "7AB7A8"
        case .move:
            return "69B8F0"
        case .bedtimeWindDown:
            return "5E7BFF"
        case .movementRhythm:
            return "58CC6A"
        }
    }
}

struct LongTermHabitSignal: Codable, Equatable, Identifiable, Sendable {
    let kind: LongTermHabitSignalKind
    let completedDays: Int
    let observedDays: Int
    let completionRate: Double
    let detailText: String

    var id: String { kind.rawValue }
    var title: String { kind.title }
    var symbol: String { kind.symbol }
    var tintHex: String { kind.tintHex }
}

struct LongTermHabitDaySnapshot: Codable, Equatable, Identifiable, Sendable {
    let date: Date
    let completedSignals: Int
    let hasAnyRecord: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct LongTermHabitSummary: Codable, Equatable, Sendable {
    let phaseTitle: String
    let phaseDetail: String
    let score: Int
    let currentStreak: Int
    let longestStreak: Int
    let completionRate30Days: Double
    let completionRate90Days: Double
    let trend: LongTermHabitTrend
    let strongestHabit: LongTermHabitSignal?
    let focusHabit: LongTermHabitSignal?
    let suggestionText: String
    let signals: [LongTermHabitSignal]
    let timeline30Days: [LongTermHabitDaySnapshot]
    let recordedDays90: Int
    let completedChallengeCount: Int

    static func empty(for date: Date = Date(), calendar: Calendar = .current) -> LongTermHabitSummary {
        LongTermHabitEngine(calendar: calendar).evaluate(
            endingAt: date,
            dailyRecords: [],
            actionRecords: [],
            challengeRecords: []
        )
    }
}

struct LongTermHabitEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func evaluate(
        endingAt date: Date = Date(),
        dailyRecords: [DailyWellnessDayRecord],
        actionRecords: [LocalActionDayRecord],
        challengeRecords: [RecoveryChallengeRecord] = []
    ) -> LongTermHabitSummary {
        let endDay = calendar.startOfDay(for: date)
        let days90 = days(endingAt: endDay, count: 90)
        let days30 = Array(days90.suffix(30))
        let dailyByDay = dictionaryByDay(dailyRecords)
        let actionByDay = dictionaryByDay(actionRecords)
        let snapshots90 = days90.map { snapshot(for: $0, dailyByDay: dailyByDay, actionByDay: actionByDay) }
        let snapshots30 = Array(snapshots90.suffix(30))
        let recordedDays90 = snapshots90.filter(\.hasAnyRecord).count
        let recordedDays30 = snapshots30.filter(\.hasAnyRecord).count
        let completionRate30 = rate(recordedDays30, of: days30.count)
        let completionRate90 = rate(recordedDays90, of: days90.count)
        let currentStreak = currentStreak(in: snapshots90)
        let longestStreak = longestStreak(in: snapshots90)
        let completedChallengeCount = challengeRecords.filter { $0.status == .completed }.count
        let signals = LongTermHabitSignalKind.allCases.map {
            signal(for: $0, days: days90, dailyByDay: dailyByDay, actionByDay: actionByDay)
        }
        let strongest = signals
            .filter { $0.completedDays > 0 }
            .max { left, right in
                if left.completionRate == right.completionRate {
                    return left.completedDays < right.completedDays
                }
                return left.completionRate < right.completionRate
            }
        let focus = signals
            .filter { $0.completedDays < max($0.observedDays, 1) }
            .min { left, right in
                if left.completionRate == right.completionRate {
                    return left.completedDays > right.completedDays
                }
                return left.completionRate < right.completionRate
            }
        let trend = trend(for: snapshots90)
        let phase = phase(
            completionRate30: completionRate30,
            currentStreak: currentStreak,
            recordedDays90: recordedDays90,
            trend: trend
        )
        let score = score(
            completionRate30: completionRate30,
            currentStreak: currentStreak,
            completedChallengeCount: completedChallengeCount
        )

        return LongTermHabitSummary(
            phaseTitle: phase.title,
            phaseDetail: phase.detail,
            score: score,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            completionRate30Days: completionRate30,
            completionRate90Days: completionRate90,
            trend: trend,
            strongestHabit: strongest,
            focusHabit: focus,
            suggestionText: suggestion(phaseTitle: phase.title, trend: trend, strongest: strongest, focus: focus),
            signals: signals,
            timeline30Days: snapshots30,
            recordedDays90: recordedDays90,
            completedChallengeCount: completedChallengeCount
        )
    }

    private func days(endingAt date: Date, count: Int) -> [Date] {
        (0..<max(count, 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: -(count - 1 - offset), to: date)
        }
    }

    private func dictionaryByDay(_ records: [DailyWellnessDayRecord]) -> [String: DailyWellnessDayRecord] {
        records.reduce(into: [:]) { result, record in
            let key = dayKey(for: record.date)
            if let existing = result[key], existing.updatedAt >= record.updatedAt {
                return
            }
            result[key] = record
        }
    }

    private func dictionaryByDay(_ records: [LocalActionDayRecord]) -> [String: LocalActionDayRecord] {
        records.reduce(into: [:]) { result, record in
            let key = dayKey(for: record.date)
            if let existing = result[key], existing.updatedAt >= record.updatedAt {
                return
            }
            result[key] = record
        }
    }

    private func snapshot(
        for date: Date,
        dailyByDay: [String: DailyWellnessDayRecord],
        actionByDay: [String: LocalActionDayRecord]
    ) -> LongTermHabitDaySnapshot {
        let completedSignals = LongTermHabitSignalKind.allCases.reduce(0) { partial, kind in
            partial + (isCompleted(kind, on: date, dailyByDay: dailyByDay, actionByDay: actionByDay) ? 1 : 0)
        }
        return LongTermHabitDaySnapshot(
            date: date,
            completedSignals: completedSignals,
            hasAnyRecord: completedSignals > 0
        )
    }

    private func signal(
        for kind: LongTermHabitSignalKind,
        days: [Date],
        dailyByDay: [String: DailyWellnessDayRecord],
        actionByDay: [String: LocalActionDayRecord]
    ) -> LongTermHabitSignal {
        let completed = days.filter {
            isCompleted(kind, on: $0, dailyByDay: dailyByDay, actionByDay: actionByDay)
        }.count
        let observed = max(days.count, 1)
        let completionRate = rate(completed, of: observed)
        return LongTermHabitSignal(
            kind: kind,
            completedDays: completed,
            observedDays: observed,
            completionRate: completionRate,
            detailText: signalDetail(kind: kind, completedDays: completed, observedDays: observed)
        )
    }

    private func isCompleted(
        _ kind: LongTermHabitSignalKind,
        on date: Date,
        dailyByDay: [String: DailyWellnessDayRecord],
        actionByDay: [String: LocalActionDayRecord]
    ) -> Bool {
        let key = dayKey(for: date)
        let daily = dailyByDay[key]
        let action = actionByDay[key]

        switch kind {
        case .water:
            return daily?.isCompleted(.water) == true
                || action?.completedActions.contains(.water) == true
                || (action?.waterMl ?? 0) > 0
        case .sunlight:
            return daily?.isCompleted(.sunlight) == true
                || action?.completedActions.contains(.sunlight) == true
                || (action?.sunlightMinutes ?? 0) >= 5
        case .breathing:
            return daily?.isCompleted(.breathing) == true
                || action?.completedActions.contains(.mindfulness) == true
                || (action?.mindfulnessMinutes ?? 0) >= 3
        case .move:
            return daily?.isCompleted(.move) == true
                || action?.completedActions.contains(.stand) == true
                || (action?.standHours ?? 0) > 0
        case .bedtimeWindDown:
            return daily?.isCompleted(.bedtimeWindDown) == true
        case .movementRhythm:
            return action?.fitnessCheckinMode != nil
                || (action?.manualWorkoutMinutes ?? 0) > 0
        }
    }

    private func currentStreak(in snapshots: [LongTermHabitDaySnapshot]) -> Int {
        var streak = 0
        for snapshot in snapshots.reversed() {
            guard snapshot.hasAnyRecord else { break }
            streak += 1
        }
        return streak
    }

    private func longestStreak(in snapshots: [LongTermHabitDaySnapshot]) -> Int {
        snapshots.reduce((current: 0, longest: 0)) { state, snapshot in
            let current = snapshot.hasAnyRecord ? state.current + 1 : 0
            return (current, max(state.longest, current))
        }.longest
    }

    private func trend(for snapshots90: [LongTermHabitDaySnapshot]) -> LongTermHabitTrend {
        let recent14 = Array(snapshots90.suffix(14))
        let recorded = recent14.filter(\.hasAnyRecord).count
        guard recorded >= 7 else { return .collecting }

        let previous7 = Array(recent14.prefix(7))
        let latest7 = Array(recent14.suffix(7))
        let previousRate = rate(previous7.filter(\.hasAnyRecord).count, of: 7)
        let latestRate = rate(latest7.filter(\.hasAnyRecord).count, of: 7)
        let delta = latestRate - previousRate

        if delta >= 0.15 { return .improving }
        if delta <= -0.15 { return .needsAttention }
        return .steady
    }

    private func phase(
        completionRate30: Double,
        currentStreak: Int,
        recordedDays90: Int,
        trend: LongTermHabitTrend
    ) -> (title: String, detail: String) {
        if recordedDays90 == 0 {
            return ("样本积累中", "先从每天一个轻动作开始，长期轨迹会自己长出来。")
        }
        if recordedDays90 < 7 {
            return ("起步期", "记录还少，先不用追求完整，保持看得见的连续性就好。")
        }
        if completionRate30 < 0.2 {
            return ("起步期", "最近 30 天还在找节奏，先固定一个最容易完成的动作。")
        }
        if completionRate30 < 0.5 {
            return ("建立期", "长期节奏已经冒头了，接下来把它变成更稳定的默认动作。")
        }
        if completionRate30 < 0.8 {
            return ("稳定期", "最近一个月已经有不错的连续性，可以开始巩固薄弱项。")
        }
        if currentStreak >= 14 {
            return ("巩固期", "连续性和完成率都很稳，这已经接近真正的生活习惯。")
        }
        if trend == .needsAttention {
            return ("成长期", "完成率不错，但最近一周略有松动，轻轻拉回来就好。")
        }
        return ("成长期", "最近 30 天完成率很高，继续把连续天数养起来。")
    }

    private func score(
        completionRate30: Double,
        currentStreak: Int,
        completedChallengeCount: Int
    ) -> Int {
        let completionScore = completionRate30 * 70
        let streakScore = min(Double(currentStreak), 14) / 14 * 20
        let challengeScore = min(Double(completedChallengeCount), 2) / 2 * 10
        return min(100, max(0, Int((completionScore + streakScore + challengeScore).rounded())))
    }

    private func suggestion(
        phaseTitle: String,
        trend: LongTermHabitTrend,
        strongest: LongTermHabitSignal?,
        focus: LongTermHabitSignal?
    ) -> String {
        if trend == .collecting {
            return String(localized: "先连续记录 7 天，系统会更清楚你最容易坚持哪一类动作。")
        }
        if let focus, focus.completedDays == 0 {
            return String(localized: "这周可以只补一个「\(focus.title)」，不用一次把所有习惯都拉满。")
        }
        if trend == .needsAttention {
            return String(localized: "最近节奏有点松，优先保住最容易完成的一项，把连续性接回来。")
        }
        if let strongest, phaseTitle == "巩固期" {
            return String(localized: "「\(strongest.title)」已经很稳，可以把它当成其他习惯的启动锚点。")
        }
        if let focus {
            return String(localized: "下一步把「\(focus.title)」从偶尔完成，慢慢变成每周固定出现。")
        }
        return String(localized: "继续保持现在的低负担节奏，长期变化会在 30 天窗口里更明显。")
    }

    private func signalDetail(kind: LongTermHabitSignalKind, completedDays: Int, observedDays: Int) -> String {
        let percent = Int((rate(completedDays, of: observedDays) * 100).rounded())
        switch kind {
        case .movementRhythm:
            return String(localized: "90 天内 \(completedDays) 天有训练或恢复节律记录，完成率 \(localizedPercent(percent))")
        default:
            return String(localized: "90 天内完成 \(completedDays) 天，完成率 \(localizedPercent(percent))")
        }
    }

    private func rate(_ count: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, Double(count) / Double(total)))
    }

    private func dayKey(for date: Date) -> String {
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
