import Foundation

/// 每周健康回顾的数据可信度。可信度只描述样本覆盖，不代表健康好坏。
enum WeeklyHealthReviewReliability: String, Hashable {
    case noData
    case limited
    case readable

    var title: String {
        switch self {
        case .noData:
            return String(localized: "等待数据")
        case .limited:
            return String(localized: "样本积累中")
        case .readable:
            return String(localized: "可以回顾")
        }
    }
}

/// 与前一周的确定性评分比较。只有两周都达到最小样本数时才产生方向。
enum WeeklyHealthReviewDirection: String, Hashable {
    case improving
    case stable
    case declining
    case unavailable

    var title: String {
        switch self {
        case .improving:
            return String(localized: "较前一周回升")
        case .stable:
            return String(localized: "与前一周持平")
        case .declining:
            return String(localized: "较前一周走弱")
        case .unavailable:
            return String(localized: "等待可比样本")
        }
    }
}

/// 周报首屏消费的稳定展示模型，不包含 HealthKit 原始样本或生成式 AI 内容。
struct WeeklyHealthReview {
    let scope: String
    let expectedDays: Int
    let observedDays: Int
    let scoredDays: Int
    let averageScore: Int?
    let previousAverageScore: Int?
    let scoreDelta: Int?
    let reliability: WeeklyHealthReviewReliability
    let direction: WeeklyHealthReviewDirection
    let supportKind: ReportMetricKind?
    let attentionKind: ReportMetricKind?
    let metricCoverage: [ReportMetricCoverageItem]
    let headline: String
    let summary: String
    let comparisonText: String
    let coverageText: String
    let nextAction: String

    var overallCoveragePercent: Int {
        guard expectedDays > 0, !metricCoverage.isEmpty else { return 0 }
        let available = metricCoverage.reduce(0) { $0 + $1.availableCount }
        let possible = expectedDays * metricCoverage.count
        guard possible > 0 else { return 0 }
        return min(100, max(0, Int((Double(available) / Double(possible) * 100).rounded())))
    }
}

/// 确定性每周健康回顾引擎。
///
/// - 不使用生成式 AI；
/// - 不把缺失指标按 0 参与评分或比较；
/// - 只有当前周与前一周各至少 3 个评分日时才输出周环比；
/// - 支撑项和关注项只采用明确的 positive/caution contribution。
enum WeeklyHealthReviewEngine {
    static let minimumComparableScoreDays = 3
    private static let stableDeltaRange = -3...3

    static func make(
        current: [ReportDaySummary],
        previous: [ReportDaySummary],
        expectedDays: Int,
        scope: String
    ) -> WeeklyHealthReview {
        let normalizedExpectedDays = min(7, max(1, expectedDays))
        let currentDays = current.filter(\.hasData)
        let currentScores = currentDays.compactMap(\.score)
        let previousScores = previous.filter(\.hasData).compactMap(\.score)
        let averageScore = average(currentScores)
        let previousAverageScore = average(previousScores)
        let coverage = ReportMetricFormatter.coverageItems(
            from: currentDays,
            expectedCount: normalizedExpectedDays
        )
        let coveragePercent = overallCoveragePercent(
            items: coverage,
            expectedDays: normalizedExpectedDays
        )
        let reliability = reliability(
            observedDays: currentDays.count,
            scoredDays: currentScores.count,
            expectedDays: normalizedExpectedDays,
            coveragePercent: coveragePercent
        )
        let comparison = comparison(
            currentScores: currentScores,
            previousScores: previousScores,
            currentAverage: averageScore,
            previousAverage: previousAverageScore
        )
        let supportKind = mostFrequentKind(
            currentDays.compactMap { summary in
                guard let item = summary.scoreBreakdown?.leadingPositive,
                      item.tone == .positive else { return nil }
                return item.kind
            }
        )
        let attentionKind = mostFrequentKind(
            currentDays.compactMap { summary in
                guard let item = summary.scoreBreakdown?.leadingNegative,
                      item.tone == .caution else { return nil }
                return item.kind
            }
        )
        let coverageText = coverageText(
            observedDays: currentDays.count,
            expectedDays: normalizedExpectedDays,
            coverage: coverage
        )
        let comparisonText = comparisonText(
            direction: comparison.direction,
            delta: comparison.delta,
            currentScoreDays: currentScores.count,
            previousScoreDays: previousScores.count
        )
        let headline = headline(
            scope: scope,
            reliability: reliability,
            direction: comparison.direction,
            averageScore: averageScore
        )
        let summary = summary(
            coverageText: coverageText,
            comparisonText: comparisonText,
            direction: comparison.direction,
            supportKind: supportKind,
            attentionKind: attentionKind
        )

        return WeeklyHealthReview(
            scope: scope,
            expectedDays: normalizedExpectedDays,
            observedDays: currentDays.count,
            scoredDays: currentScores.count,
            averageScore: averageScore,
            previousAverageScore: previousAverageScore,
            scoreDelta: comparison.delta,
            reliability: reliability,
            direction: comparison.direction,
            supportKind: supportKind,
            attentionKind: attentionKind,
            metricCoverage: coverage,
            headline: headline,
            summary: summary,
            comparisonText: comparisonText,
            coverageText: coverageText,
            nextAction: nextAction(reliability: reliability, attentionKind: attentionKind)
        )
    }

    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private static func reliability(
        observedDays: Int,
        scoredDays: Int,
        expectedDays: Int,
        coveragePercent: Int
    ) -> WeeklyHealthReviewReliability {
        guard observedDays > 0 else { return .noData }
        let minimumReadableDays = minimumComparableScoreDays
        guard observedDays >= minimumReadableDays,
              scoredDays >= minimumReadableDays,
              coveragePercent >= 50 else {
            return .limited
        }
        return .readable
    }

    private static func comparison(
        currentScores: [Int],
        previousScores: [Int],
        currentAverage: Int?,
        previousAverage: Int?
    ) -> (direction: WeeklyHealthReviewDirection, delta: Int?) {
        guard currentScores.count >= minimumComparableScoreDays,
              previousScores.count >= minimumComparableScoreDays,
              let currentAverage,
              let previousAverage else {
            return (.unavailable, nil)
        }

        let delta = currentAverage - previousAverage
        if stableDeltaRange.contains(delta) {
            return (.stable, delta)
        }
        return (delta > 0 ? .improving : .declining, delta)
    }

    private static func overallCoveragePercent(
        items: [ReportMetricCoverageItem],
        expectedDays: Int
    ) -> Int {
        guard expectedDays > 0, !items.isEmpty else { return 0 }
        let available = items.reduce(0) { $0 + $1.availableCount }
        let possible = expectedDays * items.count
        return min(100, max(0, Int((Double(available) / Double(possible) * 100).rounded())))
    }

    private static func mostFrequentKind(_ kinds: [ReportMetricKind]) -> ReportMetricKind? {
        let counts = Dictionary(grouping: kinds, by: { $0 }).mapValues(\.count)
        return counts.keys.sorted { lhs, rhs in
            let leftCount = counts[lhs, default: 0]
            let rightCount = counts[rhs, default: 0]
            if leftCount == rightCount { return lhs.rawValue < rhs.rawValue }
            return leftCount > rightCount
        }.first
    }

    private static func coverageText(
        observedDays: Int,
        expectedDays: Int,
        coverage: [ReportMetricCoverageItem]
    ) -> String {
        guard observedDays > 0 else {
            return String(localized: "当前周期还没有可用健康数据。")
        }
        let missing = coverage
            .filter { $0.availableCount < expectedDays }
            .sorted { lhs, rhs in
                if lhs.availableCount == rhs.availableCount {
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }
                return lhs.availableCount < rhs.availableCount
            }
            .map { $0.kind.title }
        if missing.isEmpty {
            return String(localized: "\(observedDays)/\(expectedDays) 天有数据，四项核心指标均有覆盖。")
        }
        let missingText = missing.joined(separator: "、")
        return String(localized: "\(observedDays)/\(expectedDays) 天有数据，\(missingText)仍有缺口。")
    }

    private static func comparisonText(
        direction: WeeklyHealthReviewDirection,
        delta: Int?,
        currentScoreDays: Int,
        previousScoreDays: Int
    ) -> String {
        guard let delta, direction != .unavailable else {
            return String(localized: "当前 \(currentScoreDays) 天、前一周 \(previousScoreDays) 天有有效评分；两边至少各 3 天后再比较。")
        }
        if direction == .stable {
            return String(localized: "平均评分与前一周基本持平（变化 \(delta) 分）。")
        }
        if delta > 0 {
            return String(localized: "平均评分较前一周高 \(delta) 分。")
        }
        let absoluteDelta = abs(delta)
        return String(localized: "平均评分较前一周低 \(absoluteDelta) 分。")
    }

    private static func headline(
        scope: String,
        reliability: WeeklyHealthReviewReliability,
        direction: WeeklyHealthReviewDirection,
        averageScore: Int?
    ) -> String {
        switch reliability {
        case .noData:
            return String(localized: "\(scope)还没有足够数据形成回顾。")
        case .limited:
            return String(localized: "\(scope)样本仍在积累，先看已有事实。")
        case .readable:
            switch direction {
            case .improving:
                return String(localized: "\(scope)整体较前一周回升。")
            case .declining:
                return String(localized: "\(scope)整体较前一周走弱。")
            case .stable:
                return String(localized: "\(scope)整体与前一周接近。")
            case .unavailable:
                guard let averageScore else {
                    return String(localized: "\(scope)已经可以开始回顾。")
                }
                switch averageScore {
                case 85...:
                    return String(localized: "\(scope)整体维持得较稳。")
                case 70..<85:
                    return String(localized: "\(scope)整体状态平稳。")
                case 50..<70:
                    return String(localized: "\(scope)出现了一些波动。")
                default:
                    return String(localized: "\(scope)更需要优先恢复。")
                }
            }
        }
    }

    private static func summary(
        coverageText: String,
        comparisonText: String,
        direction: WeeklyHealthReviewDirection,
        supportKind: ReportMetricKind?,
        attentionKind: ReportMetricKind?
    ) -> String {
        var parts = [coverageText]
        if direction != .unavailable {
            parts.append(comparisonText)
        }
        if let supportKind {
            parts.append(String(localized: "\(supportKind.title)是出现更频繁的支撑项。"))
        }
        if let attentionKind {
            parts.append(String(localized: "\(attentionKind.title)是更值得优先回看的波动项。"))
        }
        return parts.joined(separator: " ")
    }

    private static func nextAction(
        reliability: WeeklyHealthReviewReliability,
        attentionKind: ReportMetricKind?
    ) -> String {
        switch reliability {
        case .noData:
            return String(localized: "先保持设备佩戴并完成一次健康数据同步，再回来查看这一周。")
        case .limited:
            return String(localized: "先补齐更多天的睡眠、HRV、压力和活动样本，不急着根据少量数据下结论。")
        case .readable:
            switch attentionKind {
            case .sleep:
                return String(localized: "下一周先固定一个更容易坚持的入睡准备时间。")
            case .stress:
                return String(localized: "下一周优先安排一次低负担的散步或呼吸放松。")
            case .hrv:
                return String(localized: "下一周先守住恢复节律，避免连续几天叠加强度。")
            case .activity:
                return String(localized: "下一周先安排一个容易完成的轻活动时段。")
            case nil:
                return String(localized: "下一周继续保持当前节律，并留意数据是否持续稳定。")
            }
        }
    }
}
