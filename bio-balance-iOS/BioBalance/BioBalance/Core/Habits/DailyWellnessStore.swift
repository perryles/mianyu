import Foundation
import SwiftData

enum DailyWellnessActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case water
    case sunlight
    case breathing
    case move
    case bedtimeWindDown

    var id: String { rawValue }

    var definition: DailyWellnessActionDefinition {
        switch self {
        case .water:
            return DailyWellnessActionDefinition(
                kind: self,
                title: "补水一下",
                subtitle: "喝一杯水，先把恢复底盘稳住。",
                targetText: "250 ml 即完成",
                quickCompleteText: "记一杯水",
                symbol: "drop.fill",
                tintHex: "32ADE6",
                defaultAmount: 250
            )
        case .sunlight:
            return DailyWellnessActionDefinition(
                kind: self,
                title: "晒一会太阳",
                subtitle: "补一点自然光，让白天节律更清醒。",
                targetText: "5 分钟即完成",
                quickCompleteText: "记 5 分钟",
                symbol: "sun.max.fill",
                tintHex: "F4B46B",
                defaultAmount: 5
            )
        case .breathing:
            return DailyWellnessActionDefinition(
                kind: self,
                title: "呼吸放松",
                subtitle: "留 3 分钟给呼吸，把紧绷感降一档。",
                targetText: "3 分钟即完成",
                quickCompleteText: "完成呼吸",
                symbol: "wind",
                tintHex: "7AB7A8",
                defaultAmount: 3
            )
        case .move:
            return DailyWellnessActionDefinition(
                kind: self,
                title: "起身活动",
                subtitle: "离开座位走动一下，比硬扛更轻。",
                targetText: "起身一次即完成",
                quickCompleteText: "我起身了",
                symbol: "figure.walk",
                tintHex: "69B8F0",
                defaultAmount: 1
            )
        case .bedtimeWindDown:
            return DailyWellnessActionDefinition(
                kind: self,
                title: "早睡收尾",
                subtitle: "提前把夜间刺激降下来，给睡眠留窗口。",
                targetText: "开始收尾即完成",
                quickCompleteText: "开始收尾",
                symbol: "moon.stars.fill",
                tintHex: "5E7BFF",
                defaultAmount: 1
            )
        }
    }
}

struct DailyWellnessActionDefinition: Codable, Equatable, Sendable {
    let kind: DailyWellnessActionKind
    let title: String
    let subtitle: String
    let targetText: String
    let quickCompleteText: String
    let symbol: String
    let tintHex: String
    let defaultAmount: Int
}

enum DailyWellnessCompletionSource: String, Codable, Sendable {
    case healthData
    case quickComplete
    case microRecovery
}

struct DailyWellnessCompletedAction: Codable, Equatable, Sendable, Identifiable {
    let kind: DailyWellnessActionKind
    var source: DailyWellnessCompletionSource
    var completedAt: Date
    var value: Int

    var id: String { kind.rawValue }
}

struct DailyWellnessDayRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let date: Date
    var completedActions: [DailyWellnessCompletedAction]
    var microRecoveryCount: Int
    var updatedAt: Date

    var score: Int {
        min(100, completedActions.count * 20)
    }

    func isCompleted(_ kind: DailyWellnessActionKind) -> Bool {
        completedActions.contains { $0.kind == kind }
    }

    func completedAction(_ kind: DailyWellnessActionKind) -> DailyWellnessCompletedAction? {
        completedActions.first { $0.kind == kind }
    }
}

struct DailyWellnessReviewDay: Codable, Identifiable, Equatable, Sendable {
    let date: Date
    let score: Int
    let completedCount: Int

    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct DailyWellnessSummary: Codable, Equatable, Sendable {
    let todayRecord: DailyWellnessDayRecord
    let todayCompletedCount: Int
    let todayScore: Int
    let streak: Int
    let levelTitle: String
    let levelDetail: String
    let weeklyDays: [DailyWellnessReviewDay]
    let weeklyCompletionRate: Double
    let reviewText: String

    static func empty(for date: Date = Date()) -> DailyWellnessSummary {
        let record = DailyWellnessDayRecord.empty(for: date, calendar: .current)
        return DailyWellnessSummary(
            todayRecord: record,
            todayCompletedCount: 0,
            todayScore: 0,
            streak: 0,
            levelTitle: "起步",
            levelDetail: "先完成一个轻动作就很好。",
            weeklyDays: [],
            weeklyCompletionRate: 0,
            reviewText: "最近 7 天还没有形成轻养生记录。"
        )
    }
}

struct DailyWellnessReminderSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    init(isEnabled: Bool = false, hour: Int = 20, minute: Int = 30) {
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
    }

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct DailyWellnessEvaluationContext: Sendable {
    let waterMl: Int
    let sunlightMinutes: Int
    let mindfulnessMinutes: Int
    let standHours: Int
    let actionRecord: LocalActionDayRecord
    let now: Date
}

struct DailyWellnessActionProgress: Codable, Identifiable, Equatable, Sendable {
    let kind: DailyWellnessActionKind
    let isCompleted: Bool
    let source: DailyWellnessCompletionSource?
    let rawValue: Int
    let progressText: String
    let detailText: String

    var id: String { kind.rawValue }
}

struct DailyWellnessActionCardModel: Codable, Identifiable {
    let kind: DailyWellnessActionKind
    let title: String
    let subtitle: String
    let targetText: String
    let progressText: String
    let detailText: String
    let quickCompleteText: String
    let symbol: String
    let tintHex: String
    let isCompleted: Bool
    let sourceText: String

    var id: String { kind.rawValue }
}

enum DailyWellnessMicroRecoveryState: Codable, Equatable {
    case idle
    case completed(String)
}

struct DailyWellnessScoreBreakdown: Codable, Equatable, Sendable {
    let totalScore: Int
    let actionComponent: Double
    let pressureComponent: Double
    let hrvComponent: Double
    let completedCount: Int
    let pressureScore: Int?
    let todayHrv: Double?
    let recentAverageHrv: Double?
    let hrvRatio: Double?
    let levelTitle: String
    let levelDetail: String
    let pressureStatusText: String
    let hrvStatusText: String
    let explanation: String
}

enum DailyWellnessScoreEngine {
    static func evaluate(
        record: DailyWellnessDayRecord,
        pressureScore: Int?,
        todayHrv: Double?,
        recentAverageHrv: Double?
    ) -> DailyWellnessScoreBreakdown {
        let completedCount = record.completedActions.count
        let actionComponent = min(60.0, Double(completedCount) * 12.0)
        let pressure = pressureComponent(score: pressureScore)
        let hrv = hrvComponent(todayHrv: todayHrv, recentAverageHrv: recentAverageHrv)
        let total = max(0, min(100, Int((actionComponent + pressure.value + hrv.value).rounded())))
        let level = level(for: total)

        return DailyWellnessScoreBreakdown(
            totalScore: total,
            actionComponent: actionComponent,
            pressureComponent: pressure.value,
            hrvComponent: hrv.value,
            completedCount: completedCount,
            pressureScore: pressureScore.flatMap { $0 > 0 ? max(1, min(100, $0)) : nil },
            todayHrv: positive(todayHrv),
            recentAverageHrv: positive(recentAverageHrv),
            hrvRatio: hrv.ratio,
            levelTitle: level.title,
            levelDetail: level.detail,
            pressureStatusText: pressure.statusText,
            hrvStatusText: hrv.statusText,
            explanation: explanation(
                completedCount: completedCount,
                pressureScore: pressureScore,
                hrvRatio: hrv.ratio,
                totalScore: total
            )
        )
    }

    private static func pressureComponent(score: Int?) -> (value: Double, statusText: String) {
        guard let score, score > 0 else {
            return (13.0, "等待综合压力")
        }
        let clamped = Double(max(1, min(100, score)))
        let value = 25.0 * (1.0 - clamped / 100.0)
        let status: String
        switch clamped {
        case 70...:
            status = "压力偏高"
        case 50..<70:
            status = "压力有抬升"
        case 30..<50:
            status = "压力平稳"
        default:
            status = "压力较低"
        }
        return (max(0, min(25, value)), status)
    }

    private static func hrvComponent(todayHrv: Double?, recentAverageHrv: Double?) -> (value: Double, ratio: Double?, statusText: String) {
        guard let today = positive(todayHrv) else {
            return (8.0, nil, "等待 HRV 数据")
        }
        guard let baseline = positive(recentAverageHrv) else {
            return (8.0, nil, "等待 HRV 基线")
        }

        let ratio = today / baseline
        if ratio >= 1 {
            return (15.0, ratio, "HRV 高于基线")
        }
        if ratio >= 0.9 {
            let value = 11.0 + ((ratio - 0.9) / 0.1) * 4.0
            return (value, ratio, "HRV 接近基线")
        }
        if ratio >= 0.75 {
            let value = 6.0 + ((ratio - 0.75) / 0.15) * 4.0
            return (value, ratio, "HRV 低于基线")
        }

        let value = 3.0 + max(0, min(1, ratio / 0.75)) * 2.0
        return (value, ratio, "HRV 明显低于基线")
    }

    private static func level(for score: Int) -> (title: String, detail: String) {
        switch score {
        case 85...:
            return ("恢复轻盈", "动作、压力和 HRV 都支持今天维持轻盈节奏。")
        case 70..<85:
            return ("节律稳定", "今天整体稳定，可以继续完成低负担动作。")
        case 50..<70:
            return ("需要补恢复", "身体信号提示需要多留一点恢复窗口。")
        default:
            return ("优先降负荷", "今天先降刺激、补水和呼吸，比堆任务更重要。")
        }
    }

    private static func explanation(
        completedCount: Int,
        pressureScore: Int?,
        hrvRatio: Double?,
        totalScore: Int
    ) -> String {
        if let pressureScore, pressureScore >= 70 {
            return String(localized: "综合压力偏高，今天优先做呼吸、起身和补水，不建议继续堆任务。")
        }
        if let hrvRatio, hrvRatio < 0.9 {
            if completedCount >= 4 {
                return String(localized: "动作完成不错，但 HRV 低于近期基线，今天更适合轻恢复。")
            }
            return String(localized: "HRV 低于近期基线，先用最轻的恢复动作把身体拉回来。")
        }
        if completedCount >= 5 && totalScore >= 85 {
            return String(localized: "轻动作已经收满，压力和 HRV 也支持今天保持稳定节律。")
        }
        if completedCount == 0 {
            return String(localized: "先完成一个最轻动作，让今日养生分有一个温和起点。")
        }
        return String(localized: "继续补齐一个轻动作，同时观察压力和 HRV 是否保持稳定。")
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

struct DailyWellnessEvaluator {
    func evaluate(date: Date, context: DailyWellnessEvaluationContext) -> [DailyWellnessActionProgress] {
        DailyWellnessActionKind.allCases.map { kind in
            switch kind {
            case .water:
                let value = max(context.waterMl, context.actionRecord.waterMl)
                return DailyWellnessActionProgress(
                    kind: kind,
                    isCompleted: value >= 250,
                    source: value >= 250 ? .healthData : nil,
                    rawValue: value,
                    progressText: value > 0 ? "\(value) ml" : "0 ml",
                    detailText: value >= 250 ? "今天已经完成一次轻补水。" : "喝一杯水就能完成这一项。"
                )
            case .sunlight:
                let value = max(context.sunlightMinutes, context.actionRecord.sunlightMinutes)
                return DailyWellnessActionProgress(
                    kind: kind,
                    isCompleted: value >= 5,
                    source: value >= 5 ? .healthData : nil,
                    rawValue: value,
                    progressText: value > 0 ? "\(value) 分钟" : "0 分钟",
                    detailText: value >= 5 ? "今天已经补到一点自然光。" : "去窗边或户外 5 分钟就够。"
                )
            case .breathing:
                let value = max(context.mindfulnessMinutes, context.actionRecord.mindfulnessMinutes)
                return DailyWellnessActionProgress(
                    kind: kind,
                    isCompleted: value >= 3,
                    source: value >= 3 ? .healthData : nil,
                    rawValue: value,
                    progressText: value > 0 ? "\(value) 分钟" : "0 分钟",
                    detailText: value >= 3 ? "今天已经有一段呼吸放松。" : "做 3 分钟呼吸就能完成。"
                )
            case .move:
                let value = max(context.standHours, context.actionRecord.standHours)
                return DailyWellnessActionProgress(
                    kind: kind,
                    isCompleted: value > 0 || context.actionRecord.completedActions.contains(.stand),
                    source: (value > 0 || context.actionRecord.completedActions.contains(.stand)) ? .healthData : nil,
                    rawValue: value,
                    progressText: value > 0 ? "\(value) 小时" : "等待起身",
                    detailText: value > 0 ? "今天已经有起身活动记录。" : "站起来走一小圈就好。"
                )
            case .bedtimeWindDown:
                return DailyWellnessActionProgress(
                    kind: kind,
                    isCompleted: false,
                    source: nil,
                    rawValue: 0,
                    progressText: "今晚待完成",
                    detailText: "晚上点一下，表示开始收尾。"
                )
            }
        }
    }
}

final class DailyWellnessStore {
    static let shared = DailyWellnessStore()

    static let reminderIdentifier = "daily.wellness.reminder.daily"
    static let reminderPrefix = "daily.wellness.reminder"

    private let recordsKey = "dailyWellnessStore.records.v1"
    private let reminderKey = "dailyWellnessStore.reminder.v1"
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let calendar: Calendar
    private let reminderScheduler: UnifiedReminderScheduling
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let domain = "daily-wellness"
    private let kind = "day"

    private struct Payload: Codable {
        var records: [DailyWellnessDayRecord]
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        reminderScheduler: UnifiedReminderScheduling = UnifiedReminderWindowCoordinator.shared,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        self.calendar = calendar
        self.reminderScheduler = reminderScheduler
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
    }

    func allRecords() -> [DailyWellnessDayRecord] {
        loadPayload().records.sorted { $0.date > $1.date }
    }

    func record(on date: Date) -> DailyWellnessDayRecord {
        let day = calendar.startOfDay(for: date)
        return allRecords().first(where: { calendar.isDate($0.date, inSameDayAs: day) })
            ?? DailyWellnessDayRecord.empty(for: day, calendar: calendar)
    }

    @discardableResult
    func complete(
        kind: DailyWellnessActionKind,
        on date: Date = Date(),
        source: DailyWellnessCompletionSource,
        value: Int? = nil
    ) -> DailyWellnessDayRecord {
        updateRecord(on: date) { record in
            let completed = DailyWellnessCompletedAction(
                kind: kind,
                source: source,
                completedAt: Date(),
                value: value ?? kind.definition.defaultAmount
            )
            if let index = record.completedActions.firstIndex(where: { $0.kind == kind }) {
                record.completedActions[index] = completed
            } else {
                record.completedActions.append(completed)
            }
        }
    }

    @discardableResult
    func completeMicroRecovery(on date: Date = Date(), preferSunlight: Bool) -> DailyWellnessDayRecord {
        updateRecord(on: date) { record in
            record.microRecoveryCount += 1
            upsert(kind: .breathing, source: .microRecovery, value: 3, in: &record)
            upsert(kind: .move, source: .microRecovery, value: 1, in: &record)
            upsert(kind: preferSunlight ? .sunlight : .water, source: .microRecovery, value: preferSunlight ? 5 : 250, in: &record)
        }
    }

    @discardableResult
    func refreshFromHealthData(on date: Date, context: DailyWellnessEvaluationContext) -> DailyWellnessDayRecord {
        let progresses = DailyWellnessEvaluator().evaluate(date: date, context: context)
        return updateRecord(on: date) { record in
            for progress in progresses where progress.isCompleted {
                guard let source = progress.source else { continue }
                if record.completedAction(progress.kind)?.source == .quickComplete ||
                    record.completedAction(progress.kind)?.source == .microRecovery {
                    continue
                }
                if let existing = record.completedAction(progress.kind),
                   existing.source == source,
                   existing.value == progress.rawValue {
                    continue
                }
                upsert(kind: progress.kind, source: source, value: progress.rawValue, in: &record)
            }
        }
    }

    func summary(endingAt date: Date = Date(), days: Int = 7) -> DailyWellnessSummary {
        let endDay = calendar.startOfDay(for: date)
        let recordsByDay = Dictionary(
            loadPayload().records.map { (calendar.startOfDay(for: $0.date), $0) }
        ) { lhs, rhs in
            lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        }

        func resolvedRecord(on date: Date) -> DailyWellnessDayRecord {
            let day = calendar.startOfDay(for: date)
            return recordsByDay[day] ?? DailyWellnessDayRecord.empty(for: day, calendar: calendar)
        }

        let today = resolvedRecord(on: endDay)
        let reviewDays = (0..<max(days, 1)).compactMap { offset -> DailyWellnessReviewDay? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else { return nil }
            let record = resolvedRecord(on: day)
            return DailyWellnessReviewDay(
                date: day,
                score: record.score,
                completedCount: record.completedActions.count
            )
        }
        .sorted { $0.date < $1.date }

        let totalSlots = max(reviewDays.count * DailyWellnessActionKind.allCases.count, 1)
        let completedSlots = reviewDays.reduce(0) { $0 + $1.completedCount }
        let rate = Double(completedSlots) / Double(totalSlots)
        let streak = currentStreak(endingAt: endDay, recordsByDay: recordsByDay)
        let level = level(for: today.score)

        return DailyWellnessSummary(
            todayRecord: today,
            todayCompletedCount: today.completedActions.count,
            todayScore: today.score,
            streak: streak,
            levelTitle: level.title,
            levelDetail: level.detail,
            weeklyDays: reviewDays,
            weeklyCompletionRate: rate,
            reviewText: reviewText(rate: rate, streak: streak, todayScore: today.score)
        )
    }

    func loadReminderSettings() -> DailyWellnessReminderSettings {
        guard let data = defaults.data(forKey: reminderKey),
              let settings = try? decoder.decode(DailyWellnessReminderSettings.self, from: data) else {
            return DailyWellnessReminderSettings()
        }
        return settings
    }

    func saveReminderSettings(_ settings: DailyWellnessReminderSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: reminderKey)
        applyReminder(settings)
    }

    func applyReminder(_ settings: DailyWellnessReminderSettings) {
        if settings.isEnabled {
            reminderScheduler.scheduleDaily(
                identifier: Self.reminderIdentifier,
                hour: settings.hour,
                minute: settings.minute,
                title: "轻养生收尾",
                body: "今天还有一个轻养生动作没收尾，花 1 分钟补上就好。",
                source: .dailyGoal,
                priority: 200
            )
        } else {
            reminderScheduler.cancel(identifiers: [Self.reminderIdentifier])
        }
    }

    private func updateRecord(
        on date: Date,
        mutate: (inout DailyWellnessDayRecord) -> Void
    ) -> DailyWellnessDayRecord {
        let day = calendar.startOfDay(for: date)
        var payload = loadPayload()
        let index = payload.records.firstIndex { calendar.isDate($0.date, inSameDayAs: day) }
        var record = index.map { payload.records[$0] } ?? DailyWellnessDayRecord.empty(for: day, calendar: calendar)
        let previousRecord = record
        mutate(&record)
        record.completedActions = record.completedActions.sorted { $0.kind.rawValue < $1.kind.rawValue }
        guard record != previousRecord else { return previousRecord }
        record.updatedAt = Date()

        if let index {
            payload.records[index] = record
        } else {
            payload.records.append(record)
        }
        payload.records = payload.records.sorted { $0.date > $1.date }.prefix(180).map { $0 }
        savePayload(payload)
        return record
    }

    private func upsert(
        kind: DailyWellnessActionKind,
        source: DailyWellnessCompletionSource,
        value: Int,
        in record: inout DailyWellnessDayRecord
    ) {
        let completed = DailyWellnessCompletedAction(
            kind: kind,
            source: source,
            completedAt: Date(),
            value: value
        )
        if let index = record.completedActions.firstIndex(where: { $0.kind == kind }) {
            record.completedActions[index] = completed
        } else {
            record.completedActions.append(completed)
        }
    }

    private func currentStreak(
        endingAt date: Date,
        recordsByDay: [Date: DailyWellnessDayRecord]
    ) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: date)
        while true {
            guard let record = recordsByDay[calendar.startOfDay(for: cursor)],
                  record.completedActions.isEmpty == false else {
                break
            }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private func level(for score: Int) -> (title: String, detail: String) {
        switch score {
        case 100...:
            return ("满格", "今天五个轻动作都收住了。")
        case 70...99:
            return ("轻盈", "今天的养生节奏已经很完整。")
        case 40...69:
            return ("稳住", "已经完成一半，继续补一点就好。")
        default:
            return ("起步", "先完成一个轻动作就很好。")
        }
    }

    private func reviewText(rate: Double, streak: Int, todayScore: Int) -> String {
        if streak >= 7 {
            return String(localized: "最近 7 天都有轻养生记录，节奏已经很稳。")
        }
        if todayScore >= 100 {
            return String(localized: "今天已经满格，晚上只要轻轻收尾。")
        }
        switch rate {
        case 0.7...:
            return String(localized: "这一周整体完成度不错，继续保持低负担节奏。")
        case 0.35..<0.7:
            return String(localized: "这一周已经有基础，优先把最容易的一项固定下来。")
        default:
            return String(localized: "最近记录还少，从每天一个轻动作开始就够。")
        }
    }

    private func loadPayload() -> Payload {
        if let rows = records.records(domain: domain, kind: kind) {
            return Payload(records: rows.compactMap { try? decoder.decode(DailyWellnessDayRecord.self, from: $0.payload) })
        }
        return loadLegacyPayload()
    }

    private func loadLegacyPayload() -> Payload {
        guard let data = defaults.data(forKey: recordsKey),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(records: [])
        }
        return payload
    }

    private func savePayload(_ payload: Payload) {
        let seeds = payload.records.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: record.id,
                kind: kind,
                occurredAt: record.date,
                updatedAt: record.updatedAt,
                payload: data
            )
        }
        guard seeds.count == payload.records.count,
              records.replace(domain: domain, kind: kind, with: seeds) else { return }
        NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "dailyWellnessStore.records.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: recordsKey)
            return
        }
        let legacyData = defaults.data(forKey: recordsKey)
        let legacyRecords: [DailyWellnessDayRecord]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            legacyRecords = payload.records
        } else {
            legacyRecords = []
        }
        let seeds = legacyRecords.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: record.id,
                kind: kind,
                occurredAt: record.date,
                updatedAt: record.updatedAt,
                payload: data
            )
        }
        guard seeds.count == legacyRecords.count, records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: recordsKey)
    }
}

extension DailyWellnessDayRecord {
    static func empty(for date: Date, calendar: Calendar) -> DailyWellnessDayRecord {
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let id = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return DailyWellnessDayRecord(
            id: id,
            date: day,
            completedActions: [],
            microRecoveryCount: 0,
            updatedAt: day
        )
    }
}
