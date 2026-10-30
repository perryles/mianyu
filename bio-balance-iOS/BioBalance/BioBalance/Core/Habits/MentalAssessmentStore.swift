import Foundation
import SwiftData

enum MentalAssessmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case gad7
    case phq9

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gad7:
            return "GAD-7 焦虑问卷"
        case .phq9:
            return String(localized: "PHQ-9 抑郁问卷")
        }
    }

    var shortTitle: String {
        switch self {
        case .gad7:
            return "焦虑问卷"
        case .phq9:
            return String(localized: "抑郁问卷")
        }
    }
}

enum MentalAssessmentOption: Int, Codable, CaseIterable, Identifiable, Sendable {
    case notAtAll = 0
    case severalDays = 1
    case moreThanHalfTheDays = 2
    case nearlyEveryDay = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .notAtAll:
            return String(localized: "完全没有")
        case .severalDays:
            return String(localized: "好几天")
        case .moreThanHalfTheDays:
            return String(localized: "一半以上天数")
        case .nearlyEveryDay:
            return String(localized: "几乎每天")
        }
    }
}

struct MentalAssessmentQuestion: Identifiable, Hashable, Sendable {
    let index: Int
    let prompt: String

    var id: Int { index }
}

struct MentalAssessmentResult: Codable, Identifiable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        case local
        case healthKit
    }

    let kind: MentalAssessmentKind
    let recordedAt: Date
    let answers: [Int]
    let score: Int
    let source: Source
    let syncedToHealthKitAt: Date?

    var id: String { "\(kind.rawValue)-\(Int(recordedAt.timeIntervalSince1970))" }
}

enum MentalAssessmentCatalog {
    static let gad7Questions: [MentalAssessmentQuestion] = [
        MentalAssessmentQuestion(index: 1, prompt: "感到紧张、焦虑或心烦"),
        MentalAssessmentQuestion(index: 2, prompt: "无法停止或控制担忧"),
        MentalAssessmentQuestion(index: 3, prompt: "对各种事情担心过多"),
        MentalAssessmentQuestion(index: 4, prompt: "很难放松下来"),
        MentalAssessmentQuestion(index: 5, prompt: "由于坐立不安而难以静坐"),
        MentalAssessmentQuestion(index: 6, prompt: "变得容易烦恼或急躁"),
        MentalAssessmentQuestion(index: 7, prompt: "感到好像有什么可怕的事要发生")
    ]

    static let phq9Questions: [MentalAssessmentQuestion] = [
        MentalAssessmentQuestion(index: 1, prompt: "做事时提不起劲或没有兴趣"),
        MentalAssessmentQuestion(index: 2, prompt: "感到心情低落、沮丧或绝望"),
        MentalAssessmentQuestion(index: 3, prompt: "入睡困难、睡不安稳，或睡得太多"),
        MentalAssessmentQuestion(index: 4, prompt: "感到疲倦或没有活力"),
        MentalAssessmentQuestion(index: 5, prompt: "食欲不振或吃太多"),
        MentalAssessmentQuestion(index: 6, prompt: "觉得自己很糟，或觉得自己很失败，让自己或家人失望"),
        MentalAssessmentQuestion(index: 7, prompt: "对事物专注有困难，例如看报纸或看电视时"),
        MentalAssessmentQuestion(index: 8, prompt: "动作或说话速度缓慢到别人已经察觉，或正好相反，烦躁或坐立不安、动来动去比平常更多"),
        MentalAssessmentQuestion(index: 9, prompt: "有不如死掉或用某种方式伤害自己的念头")
    ]

    static func questions(for kind: MentalAssessmentKind) -> [MentalAssessmentQuestion] {
        switch kind {
        case .gad7:
            return gad7Questions
        case .phq9:
            return phq9Questions
        }
    }

    static func score(for answers: [MentalAssessmentOption]) -> Int {
        answers.reduce(0) { $0 + $1.rawValue }
    }

    static func levelText(for kind: MentalAssessmentKind, score: Int) -> String {
        switch kind {
        case .gad7:
            switch score {
            case ..<5:
                return String(localized: "无或极轻")
            case ..<10:
                return String(localized: "轻度")
            case ..<15:
                return String(localized: "中度")
            default:
                return String(localized: "重度")
            }
        case .phq9:
            switch score {
            case ..<5:
                return String(localized: "无或极轻")
            case ..<10:
                return String(localized: "轻度")
            case ..<15:
                return String(localized: "中度")
            case ..<20:
                return String(localized: "中重度")
            default:
                return String(localized: "重度")
            }
        }
    }

    static func accentHex(for kind: MentalAssessmentKind) -> String {
        switch kind {
        case .gad7:
            return "F08B57"
        case .phq9:
            return "7D6BEB"
        }
    }

    static func summary(for result: MentalAssessmentResult) -> String {
        let level = levelText(for: result.kind, score: result.score)
        switch result.kind {
        case .gad7:
            return String(localized: "最近一次 GAD-7 结果为 \(level)，总分 \(result.score) 分。")
        case .phq9:
            return String(localized: "最近一次 PHQ-9 结果为 \(level)，总分 \(result.score) 分。")
        }
    }

    static func detail(for result: MentalAssessmentResult) -> String {
        switch result.kind {
        case .gad7:
            if result.score >= 15 {
                return String(localized: "近两周焦虑困扰已经比较明显，建议把作息、咖啡因和高压时段一起回看，必要时尽快寻求专业支持。")
            }
            if result.score >= 10 {
                return String(localized: "近两周焦虑波动不算轻，可以继续连续观察，并给自己留出更稳定的恢复窗口。")
            }
            return String(localized: "当前更适合继续观察近两周是否有阶段性抬升，不需要只盯着一次结果。")
        case .phq9:
            if result.score >= 20 {
                return String(localized: "近两周低落和功能受影响已经比较明显，建议尽快联系专业支持，并认真看待休息和陪伴需求。")
            }
            if result.score >= 15 {
                return String(localized: "近两周低落和疲惫感已经偏重，适合尽快补充支持，而不是只靠自己硬扛。")
            }
            if result.score >= 10 {
                return String(localized: "最近低落、疲惫或兴趣下降已有一定累积，适合把睡眠、活动和社交支持一起放进回顾里。")
            }
            return String(localized: "当前更适合继续观察最近两周的节律变化，看它是不是短期波动。")
        }
    }

    static func actionText(for result: MentalAssessmentResult) -> String {
        switch result.kind {
        case .gad7:
            return result.score >= 10 ? "建议动作：减少刺激源，优先稳住作息和恢复节奏" : "建议动作：继续按周复测，观察是否持续抬升"
        case .phq9:
            return result.score >= 10 ? "建议动作：优先补睡眠、活动和支持，不要只靠意志力顶住" : "建议动作：继续按周复测，观察低落是否连续出现"
        }
    }

    // MARK: - 引用依据

    /// GAD-7 量表原始文献引用。
    static let gad7Citation = (
        title: "A brief measure for assessing generalized anxiety disorder: the GAD-7",
        authors: "Spitzer RL, Kroenke K, Williams JBW, Löwe B",
        journal: "Archives of Internal Medicine, 2006;166(10):1092–1097",
        url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/16717171/")!
    )

    /// PHQ-9 量表原始文献引用。
    static let phq9Citation = (
        title: "The PHQ-9: validity of a brief depression severity measure",
        authors: "Kroenke K, Spitzer RL, Williams JBW",
        journal: "Journal of General Internal Medicine, 2001;16(9):606–613",
        url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/11556941/")!
    )

    /// Pfizer 官方 PHQ 屏查量表页面（含中英文版下载）。
    static let phqScreenersURL = URL(string: "https://www.phqscreeners.com/")!

    static func citation(for kind: MentalAssessmentKind) -> (title: String, authors: String, journal: String, url: URL) {
        switch kind {
        case .gad7:
            return gad7Citation
        case .phq9:
            return phq9Citation
        }
    }
}

struct MentalAssessmentStore {
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let key = "mentalAssessmentStore.v1"
    private let domain = "mental-assessment"
    private let kind = "result"

    private struct Payload: Codable {
        var results: [MentalAssessmentResult]
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

    func save(_ result: MentalAssessmentResult) {
        guard let payload = try? encoder.encode(result) else { return }
        _ = records.upsert(
            LocalDataRecordSeed(
                domain: domain,
                recordID: result.id,
                kind: kind,
                occurredAt: result.recordedAt,
                updatedAt: result.syncedToHealthKitAt ?? result.recordedAt,
                payload: payload
            ),
            keepingNewest: 120
        )
    }

    func latestResult(for kind: MentalAssessmentKind) -> MentalAssessmentResult? {
        allResults().first { $0.kind == kind }
    }

    func results(for kind: MentalAssessmentKind) -> [MentalAssessmentResult] {
        allResults()
            .filter { $0.kind == kind }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    func allResults() -> [MentalAssessmentResult] {
        guard let rows = records.records(domain: domain, kind: kind) else {
            return loadLegacy().results.sorted { $0.recordedAt > $1.recordedAt }
        }
        return rows.compactMap { try? decoder.decode(MentalAssessmentResult.self, from: $0.payload) }
    }

    private func loadLegacy() -> Payload {
        guard let data = defaults.data(forKey: key),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(results: [])
        }
        return payload
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "mentalAssessmentStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let legacyResults: [MentalAssessmentResult]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            legacyResults = payload.results
        } else {
            legacyResults = []
        }
        let seeds = legacyResults.compactMap { result -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(result) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: result.id,
                kind: kind,
                occurredAt: result.recordedAt,
                updatedAt: result.syncedToHealthKitAt ?? result.recordedAt,
                payload: data
            )
        }
        guard seeds.count == legacyResults.count,
              records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }
}
