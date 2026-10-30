/// SelfObservationSupport 作为自我观察模块的支撑类型。
/// 负责定义症状枚举（头痛/喉咙/胸部/胃部/疲劳等）及其展示属性。

import Foundation
import SwiftData
import SwiftUI
import Charts

nonisolated enum SelfObservationSymptom: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case headache
    case throat
    case chest
    case stomach
    case fatigue
    case dizziness
    case muscle
    case skin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .headache: return "头痛"
        case .throat: return "咽喉"
        case .chest: return "胸闷"
        case .stomach: return "肠胃"
        case .fatigue: return "乏力"
        case .dizziness: return "头晕"
        case .muscle: return "肌肉"
        case .skin: return "皮肤"
        }
    }

    var systemImage: String {
        switch self {
        case .headache: return "brain.head.profile"
        case .throat: return "lungs.fill"
        case .chest: return "heart.text.square.fill"
        case .stomach: return "allergens.fill"
        case .fatigue: return "battery.25"
        case .dizziness: return "circle.dashed"
        case .muscle: return "figure.flexibility"
        case .skin: return "hand.raised.fill"
        }
    }
}

nonisolated enum SelfObservationAnswerField: String, Codable, CaseIterable, Hashable, Sendable {
    case selfRating
    case energy
    case stressLoad
    case sleepQuality
    case symptomSeverity
}

nonisolated enum SelfObservationRecordSource: String, Codable, Hashable, Sendable {
    case healthProfile
    case symptomObservation
}

nonisolated enum SelfObservationRecordScope: Hashable, Sendable {
    case all
    case healthProfileAssessments
    case symptomObservations

    func includes(_ record: SelfObservationRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .healthProfileAssessments:
            return record.isHealthProfileAssessment
        case .symptomObservations:
            return record.isSymptomObservation
        }
    }
}

nonisolated struct SelfObservationRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var recordedAt: Date
    var symptomIDs: [SelfObservationSymptom.RawValue]
    var symptomSeverity: Int
    var selfRating: Int
    var energy: Int
    var stressLoad: Int
    var sleepQuality: Int
    var note: String
    var answeredFieldIDs: [SelfObservationAnswerField.RawValue]? = nil
    var source: SelfObservationRecordSource? = nil

    var symptomCount: Int { symptomIDs.count }

    var isSymptomObservation: Bool {
        source == .symptomObservation || !symptomIDs.isEmpty
    }

    var isHealthProfileAssessment: Bool {
        guard symptomIDs.isEmpty, source != .symptomObservation else { return false }
        return source == .healthProfile || answeredFieldIDs != nil
    }

    var selectedSymptoms: [SelfObservationSymptom] {
        symptomIDs.compactMap(SelfObservationSymptom.init(rawValue:))
    }

    func answer(for field: SelfObservationAnswerField) -> Int? {
        if let answeredFieldIDs,
           !answeredFieldIDs.contains(field.rawValue) {
            return nil
        }

        let value: Int
        let validRange: ClosedRange<Int>
        switch field {
        case .selfRating:
            value = selfRating
            validRange = 1...5
        case .energy:
            value = energy
            validRange = 1...5
        case .stressLoad:
            value = stressLoad
            validRange = 1...5
        case .sleepQuality:
            value = sleepQuality
            validRange = 1...5
        case .symptomSeverity:
            value = symptomSeverity
            validRange = 0...5
        }
        return validRange.contains(value) ? value : nil
    }

    var burdenScore: Double {
        let componentScores = [
            answer(for: .selfRating).map { Double($0) * 20.0 },
            answer(for: .energy).map { Double($0) * 20.0 },
            answer(for: .sleepQuality).map { Double($0) * 20.0 },
            answer(for: .stressLoad).map { Double(6 - $0) * 20.0 }
        ].compactMap { $0 }
        let baseScore = componentScores.isEmpty
            ? 0
            : componentScores.reduce(0, +) / Double(componentScores.count)
        let severity = answer(for: .symptomSeverity) ?? (symptomIDs.isEmpty ? 0 : symptomSeverity)
        let symptomPenalty = Double(severity) * 8.0 + Double(symptomCount) * 3.0
        return min(100, max(0, baseScore - symptomPenalty))
    }

    var symptomTitleText: String {
        let titles = selectedSymptoms.map(\.title)
        return titles.isEmpty ? "无明显症状" : titles.prefix(3).joined(separator: "、")
    }
}

struct SelfObservationDailySummary: Identifiable, Hashable {
    let date: Date
    let recordCount: Int
    let symptomCount: Double
    let symptomSeverity: Double
    let selfRating: Double
    let energy: Double
    let stressLoad: Double
    let sleepQuality: Double
    let burdenScore: Double

    var id: Int64 { Int64(date.timeIntervalSince1970) }

    var hasData: Bool { recordCount > 0 }
}

enum SelfObservationCatalog {
    static let accent = Color(hex: "4C7DFF")
    static let symptomTint = Color(hex: "F46B5A")
    static let assessmentTint = Color(hex: "34C759")

    static func ratingText(_ value: Int) -> String {
        switch value {
        case 1: return "很差"
        case 2: return "偏差"
        case 3: return "一般"
        case 4: return "还好"
        default: return "很好"
        }
    }

    static func severityText(_ value: Int) -> String {
        switch value {
        case 0: return "无"
        case 1: return "轻微"
        case 2: return "可感知"
        case 3: return "影响状态"
        case 4: return "明显影响"
        default: return "需要重视"
        }
    }

    static func burdenTitle(score: Double?) -> String {
        guard let score else { return "等待自评" }
        switch score {
        case 82...: return "负担很低"
        case 66..<82: return "负担可控"
        case 45..<66: return "有些吃力"
        default: return "优先休整"
        }
    }

    static func symptomTrendInsight(from summaries: [SelfObservationDailySummary]) -> String {
        let valid = summaries.filter(\.hasData)
        guard !valid.isEmpty else {
            return String(localized: "记录症状后，这里会帮助你回看出现频率和强度变化。")
        }
        let avgSeverity = valid.map(\.symptomSeverity).reduce(0, +) / Double(valid.count)
        let highSymptomDays = valid.filter { $0.symptomSeverity >= 3 || $0.symptomCount >= 2 }.count

        if highSymptomDays >= max(2, valid.count / 3) {
            return String(localized: "最近有 \(highSymptomDays) 天出现较明显症状，建议把睡眠、压力和活动负荷一起回看。")
        }
        if avgSeverity < 1.5 {
            return String(localized: "最近记录的症状整体较轻，继续按需观察即可。")
        }
        return "最近症状平均强度约 \(String(format: "%.1f", avgSeverity))/5，可结合发生前 24 小时线索一起回看。"
    }
}

enum SelfObservationSafetyLevel: Int, Comparable, Sendable {
    case none
    case watch
    case urgent

    static func < (lhs: SelfObservationSafetyLevel, rhs: SelfObservationSafetyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct SelfObservationSafetyAssessment: Equatable, Sendable {
    let level: SelfObservationSafetyLevel
    let title: String
    let detail: String
    let actionText: String

    var requiresAcknowledgement: Bool { level == .urgent }
}

enum SelfObservationSafetyEvaluator {
    static func evaluate(
        symptoms: Set<SelfObservationSymptom>,
        severity: Int
    ) -> SelfObservationSafetyAssessment {
        let normalizedSeverity = min(5, max(0, severity))

        if normalizedSeverity >= 5 ||
            (symptoms.contains(.chest) && normalizedSeverity >= 3) ||
            (symptoms.contains(.dizziness) && normalizedSeverity >= 4) {
            return SelfObservationSafetyAssessment(
                level: .urgent,
                title: "请先确认是否需要及时就医",
                detail: "明显胸部不适、严重头晕或达到“需要重视”的症状不适合只靠 App 观察。若伴随胸痛、呼吸困难、意识异常、单侧无力或症状突然加重，请立即寻求急救或专业医疗帮助。",
                actionText: "可以保存记录，但不要因此延误就医。"
            )
        }

        if symptoms.contains(.chest) || normalizedSeverity >= 4 || symptoms.count >= 3 {
            return SelfObservationSafetyAssessment(
                level: .watch,
                title: "建议持续留意变化",
                detail: "当前记录包含胸部不适、较明显强度或多项症状。若持续不缓解、反复出现或影响日常活动，建议尽快咨询医疗专业人员。",
                actionText: "记录只能帮助整理线索，不能替代诊断。"
            )
        }

        return SelfObservationSafetyAssessment(
            level: .none,
            title: "",
            detail: "",
            actionText: ""
        )
    }
}

enum SelfObservationAssociationKind: String, CaseIterable, Hashable, Sendable, Identifiable {
    case sleep
    case stress
    case caffeine
    case medication
    case meal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return "睡眠"
        case .stress: return "压力"
        case .caffeine: return "咖啡因"
        case .medication: return "用药与补剂"
        case .meal: return "餐食"
        }
    }

    var systemImage: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .stress: return "brain.head.profile"
        case .caffeine: return "cup.and.saucer.fill"
        case .medication: return "pills.fill"
        case .meal: return "fork.knife"
        }
    }
}

struct SelfObservationAssociationItem: Identifiable, Equatable, Sendable {
    var id: SelfObservationAssociationKind { kind }
    let kind: SelfObservationAssociationKind
    let valueText: String
    let detail: String
}

struct SelfObservationAssociationSnapshot: Equatable, Sendable {
    let recordID: String
    let windowStart: Date
    let windowEnd: Date
    let headline: String
    let detail: String
    let items: [SelfObservationAssociationItem]

    var hasEvidence: Bool { !items.isEmpty }
}

struct SelfObservationAssociationInput: Sendable {
    let record: SelfObservationRecord
    let sleepMinutes: Int?
    let pressureAssessment: StressPresentationAssessment?
    let caffeineEvents: [CaffeineDoseEvent]
    let medicationEntries: [MedicationEntry]
    let mealRecords: [MealRecognitionRecord]
}

enum SelfObservationAssociationAnalyzer {
    static func analyze(_ input: SelfObservationAssociationInput) -> SelfObservationAssociationSnapshot {
        let end = input.record.recordedAt
        let start = end.addingTimeInterval(-24 * 60 * 60)
        let interval = DateInterval(start: start, end: end)
        var items: [SelfObservationAssociationItem] = []

        if let sleepMinutes = input.sleepMinutes, sleepMinutes > 0 {
            let hours = Double(sleepMinutes) / 60.0
            let detail: String
            if sleepMinutes < 360 {
                detail = "最近一晚睡眠偏短，是值得和本次不适一起回看的恢复线索。"
            } else if sleepMinutes < 420 {
                detail = "最近一晚睡眠略少，可以继续观察症状是否在补足睡眠后缓解。"
            } else {
                detail = "最近一晚睡眠时长相对充足，暂未看到明显的短睡眠线索。"
            }
            items.append(
                SelfObservationAssociationItem(
                    kind: .sleep,
                    valueText: String(format: String(localized: "%.1f 小时"), hours),
                    detail: detail
                )
            )
        }

        if let assessment = input.pressureAssessment,
           let score = assessment.score,
           let updatedAtSeconds = assessment.updatedAtSeconds {
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedAtSeconds))
            if interval.contains(updatedAt) {
                items.append(
                    SelfObservationAssociationItem(
                        kind: .stress,
                        valueText: "\(score) · \(assessment.title)",
                        detail: score >= 70
                            ? "症状前 24 小时内记录到较高压力，属于可继续观察的时间线索。"
                            : "症状前 24 小时内有压力样本，但当前数值没有进入明显高压区间。"
                    )
                )
            }
        }

        let caffeineEvents = input.caffeineEvents.filter { interval.contains($0.consumedAt) }
        if !caffeineEvents.isEmpty {
            let total = caffeineEvents.reduce(0) { $0 + max(0, $1.amountMg) }
            let latest = caffeineEvents.max(by: { $0.consumedAt < $1.consumedAt })
            let timing = latest.map { relativeTimeText(from: $0.consumedAt, to: end) } ?? "24 小时内"
            items.append(
                SelfObservationAssociationItem(
                    kind: .caffeine,
                    valueText: "\(total) mg",
                    detail: "共 \(caffeineEvents.count) 次，最近一次在\(timing)。这只表示时间接近，不代表咖啡因就是症状原因。"
                )
            )
        }

        let medicationEntries = input.medicationEntries.filter { interval.contains($0.takenAt) }
        if !medicationEntries.isEmpty {
            let names = Array(Set(medicationEntries.map(\.name).filter { !$0.isEmpty })).sorted()
            let nameText = names.prefix(3).joined(separator: "、")
            items.append(
                SelfObservationAssociationItem(
                    kind: .medication,
                    valueText: "\(medicationEntries.count) 次",
                    detail: "症状前记录了\(nameText.isEmpty ? "用药或补剂" : nameText)。请按医嘱使用，不要仅凭时间重合自行停药或调整剂量。"
                )
            )
        }

        let mealRecords = input.mealRecords.filter { interval.contains($0.capturedAt) }
        if !mealRecords.isEmpty {
            let foods = mealRecords
                .flatMap(\.recognizedFoods)
                .map(\.name)
                .filter { !$0.isEmpty }
            let foodText = Array(Set(foods)).sorted().prefix(4).joined(separator: "、")
            items.append(
                SelfObservationAssociationItem(
                    kind: .meal,
                    valueText: "\(mealRecords.count) 餐",
                    detail: foodText.isEmpty
                        ? "症状前 24 小时内有餐食记录，可继续观察是否在相似进食场景后重复出现。"
                        : "记录包含\(foodText)。只有重复出现相似模式时，才更值得继续观察。"
                )
            )
        }

        let evidenceCount = items.count
        let headline = evidenceCount == 0
            ? "前 24 小时暂无线索可对照"
            : "找到 \(evidenceCount) 类可回看的时间线索"
        let detail = evidenceCount == 0
            ? "继续记录睡眠、压力、咖啡因、用药和餐食后，系统会在这里整理症状发生前的共同背景。"
            : "这些内容只表示在症状发生前 24 小时内共同出现，不代表因果关系。重复记录后再观察模式会更可靠。"

        return SelfObservationAssociationSnapshot(
            recordID: input.record.id,
            windowStart: start,
            windowEnd: end,
            headline: headline,
            detail: detail,
            items: items
        )
    }

    private static func relativeTimeText(from date: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(date) / 60.0))
        if minutes < 60 {
            return String(localized: "约 \(max(1, minutes)) 分钟前")
        }
        return String(localized: "约 \(minutes / 60) 小时前")
    }
}

struct SelfObservationAssociationLoader {
    @MainActor
    func load(for record: SelfObservationRecord) async -> SelfObservationAssociationSnapshot {
        let end = record.recordedAt
        let interval = DateInterval(start: end.addingTimeInterval(-24 * 60 * 60), end: end)
        let sleepMinutes = try? await HealthKitManager.shared.fetchSleepDurationInMinutes(on: end)
        let pressureAssessment = try? StressStore().load().map {
            StressPresentation.assessment(from: $0.current)
        }

        return SelfObservationAssociationAnalyzer.analyze(
            SelfObservationAssociationInput(
                record: record,
                sleepMinutes: sleepMinutes,
                pressureAssessment: pressureAssessment,
                caffeineEvents: CaffeineDoseEventStore.shared.events(in: interval),
                medicationEntries: MedicationStore.shared.allEntries(),
                mealRecords: DrinkExperienceStore.shared.allMealRecords()
            )
        )
    }
}

final class SelfObservationStore {
    static let shared = SelfObservationStore()

    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let calendar = Calendar.current
    private let key = "selfObservationStore.v1"
    private let domain = "self-observation"
    private let kind = "record"

    private struct Payload: Codable {
        var records: [SelfObservationRecord]
    }

    init(
        defaults: UserDefaults = .standard,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
    }

    func save(
        _ record: SelfObservationRecord,
        replacingProfileAssessmentOnSameDay: Bool = false
    ) {
        var payload = load()
        if replacingProfileAssessmentOnSameDay {
            payload.records.removeAll {
                $0.id != record.id &&
                    $0.symptomIDs.isEmpty &&
                    calendar.isDate($0.recordedAt, inSameDayAs: record.recordedAt)
            }
        }
        if let index = payload.records.firstIndex(where: { $0.id == record.id }) {
            payload.records[index] = record
        } else {
            payload.records.append(record)
        }
        payload.records.sort { $0.recordedAt > $1.recordedAt }
        payload.records = Array(payload.records.prefix(365))
        persist(payload)
    }

    func allRecords() -> [SelfObservationRecord] {
        load().records.sorted { $0.recordedAt > $1.recordedAt }
    }

    func records(on date: Date) -> [SelfObservationRecord] {
        allRecords().filter { calendar.isDate($0.recordedAt, inSameDayAs: date) }
    }

    func latestRecord() -> SelfObservationRecord? {
        allRecords().first
    }

    func dailySummaries(
        days: Int,
        endingAt endDate: Date = Date(),
        scope: SelfObservationRecordScope = .all
    ) -> [SelfObservationDailySummary] {
        let end = calendar.startOfDay(for: endDate)
        let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: end) ?? end
        let scopedRecords = allRecords().filter(scope.includes)
        let grouped = Dictionary(grouping: scopedRecords) { calendar.startOfDay(for: $0.recordedAt) }

        return (0..<max(days, 1)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let day = calendar.startOfDay(for: date)
            let records = grouped[day] ?? []
            return makeSummary(date: day, records: records)
        }
    }

    private func makeSummary(date: Date, records: [SelfObservationRecord]) -> SelfObservationDailySummary {
        guard !records.isEmpty else {
            return SelfObservationDailySummary(
                date: date,
                recordCount: 0,
                symptomCount: 0,
                symptomSeverity: 0,
                selfRating: 0,
                energy: 0,
                stressLoad: 0,
                sleepQuality: 0,
                burdenScore: 0
            )
        }

        func average(_ values: [Double]) -> Double {
            values.reduce(0, +) / Double(Swift.max(values.count, 1))
        }

        return SelfObservationDailySummary(
            date: date,
            recordCount: records.count,
            symptomCount: average(records.map { Double($0.symptomCount) }),
            symptomSeverity: average(records.map { Double($0.symptomSeverity) }),
            selfRating: average(records.compactMap { $0.answer(for: .selfRating).map(Double.init) }),
            energy: average(records.compactMap { $0.answer(for: .energy).map(Double.init) }),
            stressLoad: average(records.compactMap { $0.answer(for: .stressLoad).map(Double.init) }),
            sleepQuality: average(records.compactMap { $0.answer(for: .sleepQuality).map(Double.init) }),
            burdenScore: average(records.map(\.burdenScore))
        )
    }

    private func load() -> Payload {
        if let rows = records.records(domain: domain, kind: kind) {
            return Payload(records: rows.compactMap { try? decoder.decode(SelfObservationRecord.self, from: $0.payload) })
        }
        return loadLegacy()
    }

    private func loadLegacy() -> Payload {
        guard let data = defaults.data(forKey: key),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(records: [])
        }
        return payload
    }

    private func persist(_ payload: Payload) {
        let seeds = payload.records.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(domain: domain, recordID: record.id, kind: kind, occurredAt: record.recordedAt, updatedAt: record.recordedAt, payload: data)
        }
        guard seeds.count == payload.records.count else { return }
        _ = records.replace(domain: domain, kind: kind, with: seeds)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "selfObservationStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let legacyRecords: [SelfObservationRecord]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            legacyRecords = payload.records
        } else { legacyRecords = [] }
        let seeds = legacyRecords.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(domain: domain, recordID: record.id, kind: kind, occurredAt: record.recordedAt, updatedAt: record.recordedAt, payload: data)
        }
        guard seeds.count == legacyRecords.count, records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }
}

@MainActor
@Observable
final class SelfObservationViewModel {
    var records: [SelfObservationRecord] = []
    var summaries: [SelfObservationDailySummary] = []

    private let store: SelfObservationStore
    private var summaryScope: SelfObservationRecordScope

    init(
        store: SelfObservationStore? = nil,
        summaryScope: SelfObservationRecordScope = .all
    ) {
        self.store = store ?? SelfObservationStore.shared
        self.summaryScope = summaryScope
        reload(days: 14, scope: summaryScope)
    }

    func reload(
        days: Int = 14,
        endingAt endDate: Date = Date(),
        scope: SelfObservationRecordScope? = nil
    ) {
        if let scope {
            summaryScope = scope
        }
        records = store.allRecords()
        summaries = store.dailySummaries(days: days, endingAt: endDate, scope: summaryScope)
    }

    @discardableResult
    func save(
        recordedAt: Date = Date(),
        symptoms: Set<SelfObservationSymptom>,
        symptomSeverity: Int,
        selfRating: Int,
        energy: Int,
        stressLoad: Int,
        sleepQuality: Int,
        note: String,
        answeredFields: Set<SelfObservationAnswerField>? = nil,
        replacingProfileAssessmentOnSameDay: Bool = false
    ) -> SelfObservationRecord {
        let existingProfileRecord = replacingProfileAssessmentOnSameDay
            ? store.records(on: recordedAt).first(where: { $0.symptomIDs.isEmpty })
            : nil

        func storedValue(_ field: SelfObservationAnswerField, value: Int) -> Int {
            guard let answeredFields else { return value }
            return answeredFields.contains(field) ? value : 0
        }

        let record = SelfObservationRecord(
            id: existingProfileRecord?.id ?? UUID().uuidString,
            recordedAt: recordedAt,
            symptomIDs: symptoms.map(\.rawValue).sorted(),
            symptomSeverity: storedValue(.symptomSeverity, value: symptomSeverity),
            selfRating: storedValue(.selfRating, value: selfRating),
            energy: storedValue(.energy, value: energy),
            stressLoad: storedValue(.stressLoad, value: stressLoad),
            sleepQuality: storedValue(.sleepQuality, value: sleepQuality),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            answeredFieldIDs: answeredFields?.map(\.rawValue).sorted(),
            source: symptoms.isEmpty ? .healthProfile : .symptomObservation
        )
        store.save(
            record,
            replacingProfileAssessmentOnSameDay: replacingProfileAssessmentOnSameDay
        )
        reload()
        return record
    }
}

struct SelfObservationSymptomTrendCard: View {
    let days: Int
    let summaries: [SelfObservationDailySummary]

    private var validSummaries: [SelfObservationDailySummary] {
        summaries.filter(\.hasData)
    }

    private var insightText: String {
        SelfObservationCatalog.symptomTrendInsight(from: summaries)
    }

    private var averageSeverityText: String {
        let values = validSummaries.map(\.symptomSeverity)
        guard !values.isEmpty else { return "--" }
        return String(format: "%.1f", values.reduce(0, +) / Double(values.count))
    }

    private var symptomDaysText: String {
        let count = validSummaries.filter { $0.symptomSeverity > 0 || $0.symptomCount > 0 }.count
        return String(localized: "\(count)天")
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("症状趋势")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(insightText)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(validSummaries.isEmpty ? "按需记录" : "最近 \(days) 天")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(SelfObservationCatalog.symptomTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SelfObservationCatalog.symptomTint.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 10) {
                reportPill(title: "平均强度", value: averageSeverityText, tint: SelfObservationCatalog.symptomTint)
                reportPill(title: "记录", value: "\(validSummaries.reduce(0) { $0 + $1.recordCount })次", tint: SelfObservationCatalog.accent)
                reportPill(title: "症状日", value: symptomDaysText, tint: SelfObservationCatalog.symptomTint)
            }

            if validSummaries.isEmpty {
                ReportsInlineEmptyState(text: "暂无症状记录")
            } else {
                Chart(summaries) { item in
                    if item.hasData {
                        BarMark(
                            x: .value("日期", item.date, unit: .day),
                            y: .value("症状强度", item.symptomSeverity)
                        )
                        .foregroundStyle(SelfObservationCatalog.symptomTint.opacity(0.28))
                        .cornerRadius(5)

                        LineMark(
                            x: .value("日期", item.date, unit: .day),
                            y: .value("症状强度", item.symptomSeverity)
                        )
                        .foregroundStyle(SelfObservationCatalog.symptomTint)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("日期", item.date, unit: .day),
                            y: .value("症状强度", item.symptomSeverity)
                        )
                        .foregroundStyle(SelfObservationCatalog.symptomTint)
                    }
                }
                .chartYScale(domain: 0...5)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, days / 5))) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 1, 2, 3, 4, 5]) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(ReportsChartStyle.plotBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .frame(height: 178)
            }
        }
    }

    private func reportPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
