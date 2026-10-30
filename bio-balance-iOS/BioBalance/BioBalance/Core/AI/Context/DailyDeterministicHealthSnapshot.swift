import Foundation

/// 集中声明会影响快照可比性的确定性引擎版本。
nonisolated enum HealthEngineVersion {
    static let baseline = "baseline-1.0.0"
    static let sleepScoring = SleepRhythmScoringEngine.algorithmVersion
    static let stress = "stress-2.1.0"
    static let recovery = "recovery-2.0.0"
}

/// 标记快照指标是实测值、派生估算值，还是不足以支持数值结论。
enum HealthMetricDataQuality: String, Codable, Sendable {
    case measured
    case estimated
    case insufficient

    var title: String {
        switch self {
        case .measured:
            return String(localized: "已测量")
        case .estimated:
            return String(localized: "估算")
        case .insufficient:
            return String(localized: "样本不足")
        }
    }
}

/// 表示快照相对查询时间是否仍在允许的使用窗口内。
enum HealthSnapshotFreshness: String, Codable, Sendable {
    case fresh
    case stale

    var title: String {
        switch self {
        case .fresh:
            return String(localized: "数据较新")
        case .stale:
            return String(localized: "等待更新")
        }
    }
}

/// 确定性快照中的稳定指标标识，作为持久化和同步契约使用。
enum DeterministicHealthMetricID: String, Codable, Sendable {
    case hrvToday = "hrv.today"
    case hrvNightly = "hrv.nightly"
    case hrvBaseline = "hrv.baseline"
    case restingHeartRate = "heart.resting"
    case sleepDuration = "sleep.duration"
    case sleepScore = "sleep.score"
    case stressScore = "stress.score"
    case recoveryScore = "recovery.score"
}

/// 区分 Apple Health 原始测量与本地规则派生结果。
enum DeterministicHealthMetricSource: String, Codable, Sendable {
    case healthKit
    case localRule

    var title: String {
        switch self {
        case .healthKit:
            return "Apple Health"
        case .localRule:
            return String(localized: "本地确定性计算")
        }
    }
}

/// 单个确定性指标及其单位、来源、质量和观测时间。
struct DeterministicHealthMetric: Codable, Equatable, Sendable {
    let id: DeterministicHealthMetricID
    let value: Double?
    let unit: HealthMetricUnit?
    let source: DeterministicHealthMetricSource
    let quality: HealthMetricDataQuality
    let observedAt: Date

    var canSupportNumericClaim: Bool {
        value != nil && quality != .insufficient && typedValue != nil
    }

    var typedValue: HealthMetricTypedValue? {
        guard let value, value.isFinite, let unit else { return nil }
        switch (id, unit) {
        case (.hrvToday, .milliseconds), (.hrvNightly, .milliseconds), (.hrvBaseline, .milliseconds):
            return HRVSDNNMilliseconds(value).map(HealthMetricTypedValue.hrvSDNN)
        case (.restingHeartRate, .beatsPerMinute):
            return HeartRateBPM(value).map(HealthMetricTypedValue.beatsPerMinute)
        case (.sleepDuration, .minutes):
            return SleepDurationMinutes(value).map(HealthMetricTypedValue.minutes)
        case (.sleepScore, .score), (.stressScore, .score), (.recoveryScore, .score):
            return (0...100).contains(value) ? .score(value) : nil
        default:
            return nil
        }
    }
}

/// 记录生成快照时各确定性引擎的版本，用于阻止跨版本直接比较。
struct HealthEngineVersionSnapshot: Codable, Equatable, Sendable {
    let baseline: String
    let sleepScoring: String
    let stress: String
    let recovery: String

    static let current = HealthEngineVersionSnapshot(
        baseline: HealthEngineVersion.baseline,
        sleepScoring: HealthEngineVersion.sleepScoring,
        stress: HealthEngineVersion.stress,
        recovery: HealthEngineVersion.recovery
    )
}

/// 按日保存的确定性健康指标集合，不包含模型生成内容。
struct DailyDeterministicHealthSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let date: Date
    let generatedAt: Date
    let engineVersions: HealthEngineVersionSnapshot
    let metrics: [DeterministicHealthMetric]

    func metric(_ id: DeterministicHealthMetricID) -> DeterministicHealthMetric? {
        metrics.first { $0.id == id }
    }

    var missingMetricIDs: [DeterministicHealthMetricID] {
        metrics.filter { !$0.canSupportNumericClaim }.map(\.id)
    }

    func freshness(
        at date: Date = Date(),
        maximumAge: TimeInterval = 6 * 60 * 60
    ) -> HealthSnapshotFreshness {
        let age = date.timeIntervalSince(generatedAt)
        guard age >= 0 else { return .stale }
        return age <= max(0, maximumAge) ? .fresh : .stale
    }

    func isComparable(to other: DailyDeterministicHealthSnapshot) -> Bool {
        schemaVersion == other.schemaVersion && engineVersions == other.engineVersions
    }

    static func make(
        context: HealthAIContext,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyDeterministicHealthSnapshot {
        let metrics = [
            makeMetric(id: .hrvToday, value: context.todayVitals.typedTodayAverageHrv, source: .healthKit, measured: context.todayVitals.typedTodayAverageHrv != nil, at: generatedAt),
            makeMetric(id: .hrvNightly, value: context.recoveryVitals.typedNightlyHrv, source: .healthKit, measured: context.recoveryVitals.typedNightlyHrv != nil, at: generatedAt),
            makeMetric(id: .hrvBaseline, value: context.todayVitals.typedRecentAverageHrv, source: .localRule, measured: false, at: generatedAt),
            makeMetric(id: .restingHeartRate, value: context.todayVitals.typedRestingHeartRate, source: .healthKit, measured: context.todayVitals.typedRestingHeartRate != nil, at: generatedAt),
            makeMetric(id: .sleepDuration, value: context.sleep.typedDuration, source: .healthKit, measured: context.sleep.typedDuration != nil, at: generatedAt),
            makeMetric(id: .sleepScore, value: context.sleep.score.map(Double.init), unit: .score, source: .localRule, measured: false, at: generatedAt),
            makeMetric(id: .stressScore, value: context.stress.score.map(Double.init), unit: .score, source: .localRule, measured: false, at: generatedAt),
            makeMetric(
                id: .recoveryScore,
                value: context.recoveryScriptPlan.flatMap { $0.confidence > 0 ? Double($0.readinessScore) : nil },
                unit: .score,
                source: .localRule,
                measured: false,
                at: generatedAt
            )
        ]

        return DailyDeterministicHealthSnapshot(
            schemaVersion: currentSchemaVersion,
            date: calendar.startOfDay(for: generatedAt),
            generatedAt: generatedAt,
            engineVersions: .current,
            metrics: metrics
        )
    }

    private static func makeMetric(
        id: DeterministicHealthMetricID,
        value: Double?,
        unit: HealthMetricUnit,
        source: DeterministicHealthMetricSource,
        measured: Bool,
        at date: Date
    ) -> DeterministicHealthMetric {
        DeterministicHealthMetric(
            id: id,
            value: value,
            unit: unit,
            source: source,
            quality: value == nil ? .insufficient : (measured ? .measured : .estimated),
            observedAt: date
        )
    }

    private static func makeMetric<T: HealthMeasurementValue>(
        id: DeterministicHealthMetricID,
        value: T?,
        source: DeterministicHealthMetricSource,
        measured: Bool,
        at date: Date
    ) -> DeterministicHealthMetric {
        makeMetric(id: id, value: value?.rawValue, unit: T.unit, source: source, measured: measured, at: date)
    }
}
