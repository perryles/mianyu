/// SleepEnvironmentManagementSupport 作为睡眠环境管理的支撑类型。
/// 负责定义语气枚举（构建中/稳定/观察/提升）及其标签和颜色。

import Foundation
import SwiftData

enum SleepEnvironmentManagementTone: String, Codable, Sendable {
    case building
    case steady
    case watch
    case elevated

    var label: String {
        switch self {
        case .building: return "样本积累中"
        case .steady: return "环境稳定"
        case .watch: return "需要观察"
        case .elevated: return "重点优化"
        }
    }
}

struct SleepBedroomChecklistItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String

    static let defaults: [SleepBedroomChecklistItem] = [
        SleepBedroomChecklistItem(
            id: "quiet_room",
            title: "安静环境",
            detail: "关掉持续底噪，必要时准备耳塞或白噪声。",
            symbol: "speaker.slash.fill"
        ),
        SleepBedroomChecklistItem(
            id: "low_light",
            title: "低光收尾",
            detail: "睡前把主灯和高亮屏幕降下来。",
            symbol: "lightbulb.min.fill"
        ),
        SleepBedroomChecklistItem(
            id: "temperature_bedding",
            title: "温度被褥",
            detail: "让卧室和被褥保持舒适，不闷热也不发冷。",
            symbol: "thermometer.medium"
        ),
        SleepBedroomChecklistItem(
            id: "device_finish",
            title: "设备收尾",
            detail: "充电、闹钟、明早物品提前处理好。",
            symbol: "iphone.gen3"
        ),
        SleepBedroomChecklistItem(
            id: "monitoring_ready",
            title: "监测准备",
            detail: "确认手表佩戴稳定，必要时开启鼾声分析。",
            symbol: "applewatch.watchface"
        )
    ]
}

struct SleepEnvironmentManagementRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date
    var completedItemIDs: Set<String>
    var updatedAt: Date
}

struct SleepEnvironmentManagementSummary: Equatable, Sendable {
    let score: Int
    let tone: SleepEnvironmentManagementTone
    let headline: String
    let detail: String
    let checklistItems: [SleepBedroomChecklistItem]
    let completedItemIDs: Set<String>
    let completedCount: Int
    let trendLabel: String
    let focusItemTitle: String
    let suggestionText: String
    let coverageFlags: [String]
}

final class SleepEnvironmentManagementStore {
    static let shared = SleepEnvironmentManagementStore()

    private let key = "sleepEnvironmentManagementStore.v1"
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let calendar: Calendar
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let domain = "sleep-environment-management"
    private let kind = "day"

    private struct Payload: Codable {
        var records: [SleepEnvironmentManagementRecord]
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        self.calendar = calendar
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
    }

    func record(for date: Date = Date()) -> SleepEnvironmentManagementRecord? {
        let key = dayKey(for: date)
        return loadPayload().records.first(where: { $0.dayKey == key })
    }

    func recentRecords(days: Int = 14, from date: Date = Date()) -> [SleepEnvironmentManagementRecord] {
        let start = calendar.startOfDay(for: date)
        guard let lower = calendar.date(byAdding: .day, value: -max(days - 1, 0), to: start) else {
            return []
        }
        return loadPayload().records
            .filter { $0.date >= lower && $0.date <= start }
            .sorted { $0.date < $1.date }
    }

    @discardableResult
    func setChecklistItem(_ itemID: String, completed: Bool, on date: Date = Date()) -> SleepEnvironmentManagementRecord {
        var payload = loadPayload()
        let key = dayKey(for: date)
        let normalized = calendar.startOfDay(for: date)
        var record = payload.records.first(where: { $0.dayKey == key }) ?? SleepEnvironmentManagementRecord(
            dayKey: key,
            date: normalized,
            completedItemIDs: [],
            updatedAt: Date()
        )
        if completed {
            record.completedItemIDs.insert(itemID)
        } else {
            record.completedItemIDs.remove(itemID)
        }
        record.updatedAt = Date()
        replace(record, in: &payload)
        savePayload(payload)
        return record
    }

    func resetToday(on date: Date = Date()) {
        var payload = loadPayload()
        let key = dayKey(for: date)
        payload.records.removeAll { $0.dayKey == key }
        savePayload(payload)
    }

    private func replace(_ record: SleepEnvironmentManagementRecord, in payload: inout Payload) {
        if let index = payload.records.firstIndex(where: { $0.dayKey == record.dayKey }) {
            payload.records[index] = record
        } else {
            payload.records.append(record)
        }
        payload.records = payload.records
            .sorted { $0.date > $1.date }
            .prefix(60)
            .map { $0 }
    }

    private func loadPayload() -> Payload {
        if let rows = records.records(domain: domain, kind: kind) {
            return Payload(records: rows.compactMap { try? decoder.decode(SleepEnvironmentManagementRecord.self, from: $0.payload) })
        }
        return loadLegacyPayload()
    }

    private func loadLegacyPayload() -> Payload {
        guard let data = defaults.data(forKey: key),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(records: [])
        }
        return payload
    }

    private func savePayload(_ payload: Payload) {
        let seeds = payload.records.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(domain: domain, recordID: record.dayKey, kind: kind, occurredAt: record.date, updatedAt: record.updatedAt, payload: data)
        }
        guard seeds.count == payload.records.count else { return }
        _ = records.replace(domain: domain, kind: kind, with: seeds)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "sleepEnvironmentManagementStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let legacyRecords: [SleepEnvironmentManagementRecord]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            legacyRecords = payload.records
        } else { legacyRecords = [] }
        let seeds = legacyRecords.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(domain: domain, recordID: record.dayKey, kind: kind, occurredAt: record.date, updatedAt: record.updatedAt, payload: data)
        }
        guard seeds.count == legacyRecords.count, records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

struct SleepEnvironmentManagementEngine {
    struct Input {
        let environmentInsight: SleepEnvironmentSnoreInsight?
        let todayRecord: SleepEnvironmentManagementRecord?
        let recentRecords: [SleepEnvironmentManagementRecord]
        let sleepData: SleepData?
        let sleepSummary: SleepSessionSummary?
    }

    func build(input: Input) -> SleepEnvironmentManagementSummary {
        let items = SleepBedroomChecklistItem.defaults
        let completed = input.todayRecord?.completedItemIDs ?? []
        let checklistRatio = Double(completed.count) / Double(max(items.count, 1))
        let insight = input.environmentInsight
        let hasSleep = (input.sleepData?.duration_minutes ?? 0) > 0 || input.sleepSummary != nil
        var score = Int((54 + checklistRatio * 26).rounded())
        var coverageFlags: [String] = []

        if !hasSleep {
            coverageFlags.append("缺少睡眠样本")
            score -= 6
        }
        if insight == nil {
            coverageFlags.append("缺少环境音量样本")
            score -= 4
        }

        if let insight {
            switch insight.tone {
            case .elevated:
                score -= 22
            case .caution:
                score -= 10
            case .moderate:
                score -= 4
            case .calm:
                score += 10
            }
            coverageFlags.append(contentsOf: insight.coverageFlags)
        }

        if let summary = input.sleepSummary?.snoreSummary {
            switch summary.intensity {
            case .high:
                score -= 12
            case .medium:
                score -= 7
            case .low:
                score -= 3
            case .none:
                score += 4
            }
        }

        score = min(96, max(30, score))
        let tone = tone(for: score, coverageFlags: coverageFlags)
        let focusItem = focusItem(from: items, completed: completed, insight: insight)
        let completedDays = input.recentRecords.filter { !$0.completedItemIDs.isEmpty }.count
        let trendLabel = trendLabel(completedDays: completedDays, totalDays: min(max(input.recentRecords.count, 0), 7))

        return SleepEnvironmentManagementSummary(
            score: score,
            tone: tone,
            headline: headline(for: tone, insight: insight),
            detail: detail(for: tone, insight: insight, coverageFlags: coverageFlags),
            checklistItems: items,
            completedItemIDs: completed,
            completedCount: completed.count,
            trendLabel: trendLabel,
            focusItemTitle: focusItem.title,
            suggestionText: suggestion(for: focusItem, insight: insight, tone: tone),
            coverageFlags: Array(Set(coverageFlags)).sorted()
        )
    }

    private func tone(for score: Int, coverageFlags: [String]) -> SleepEnvironmentManagementTone {
        if !coverageFlags.isEmpty && score < 64 {
            return .building
        }
        if score >= 80 {
            return .steady
        }
        if score >= 62 {
            return .watch
        }
        return .elevated
    }

    private func focusItem(
        from items: [SleepBedroomChecklistItem],
        completed: Set<String>,
        insight: SleepEnvironmentSnoreInsight?
    ) -> SleepBedroomChecklistItem {
        if insight?.tone == .elevated,
           let quiet = items.first(where: { $0.id == "quiet_room" }),
           !completed.contains(quiet.id) {
            return quiet
        }
        return items.first(where: { !completed.contains($0.id) }) ?? items[0]
    }

    private func trendLabel(completedDays: Int, totalDays: Int) -> String {
        guard totalDays >= 3 else { return "样本积累中" }
        if completedDays >= 5 { return "近 7 天环境准备稳定" }
        if completedDays >= 2 { return "近 7 天已有 \(completedDays) 天完成准备" }
        return String(localized: "近 7 天准备记录偏少")
    }

    private func headline(for tone: SleepEnvironmentManagementTone, insight: SleepEnvironmentSnoreInsight?) -> String {
        if let insight, tone != .steady {
            return insight.headline
        }
        switch tone {
        case .building:
            return String(localized: "卧室环境样本正在积累")
        case .steady:
            return String(localized: "今晚卧室环境准备得比较稳")
        case .watch:
            return String(localized: "今晚先守住一个关键环境动作")
        case .elevated:
            return "今晚优先把睡眠环境降负荷"
        }
    }

    private func detail(
        for tone: SleepEnvironmentManagementTone,
        insight: SleepEnvironmentSnoreInsight?,
        coverageFlags: [String]
    ) -> String {
        if let insight {
            return insight.summary
        }
        if !coverageFlags.isEmpty {
            return String(localized: "先用卧室检查清单建立稳定准备，完成几晚后会把环境音量、鼾声和夜醒一起读。")
        }
        return tone == .steady ? "继续保持当前睡前环境，不需要额外增加压力。" : "先从安静、低光和设备收尾里选一项完成。"
    }

    private func suggestion(
        for focusItem: SleepBedroomChecklistItem,
        insight: SleepEnvironmentSnoreInsight?,
        tone: SleepEnvironmentManagementTone
    ) -> String {
        if let first = insight?.suggestions.first {
            return first
        }
        if tone == .steady {
            return String(localized: "今晚照旧完成准备即可，把注意力留给放松而不是反复检查。")
        }
        return String(localized: "今晚先完成「\(focusItem.title)」，少做一点也算给身体一个稳定信号。")
    }
}
