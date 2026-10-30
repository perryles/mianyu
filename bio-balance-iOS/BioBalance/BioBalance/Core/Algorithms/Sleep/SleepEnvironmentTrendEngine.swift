import Foundation

// MARK: - 环境与睡眠关联等级

enum EnvironmentSleepCorrelation: String, Codable, Sendable {
    case strong       // 完成环境准备的夜晚睡眠明显更好
    case moderate     // 有一定关联
    case weak         // 关联不明显
    case insufficient // 数据不足

    var label: String {
        switch self {
        case .strong: return "关联明显"
        case .moderate: return "有一定关联"
        case .weak: return "关联较弱"
        case .insufficient: return "数据积累中"
        }
    }

    var symbol: String {
        switch self {
        case .strong: return "checkmark.seal.fill"
        case .moderate: return "checkmark.circle.fill"
        case .weak: return "circle.dashed"
        case .insufficient: return "chart.bar.xaxis"
        }
    }
}

// MARK: - 单项环境因子影响

struct EnvironmentFactorImpact: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let avgScoreWhenCompleted: Int
    let avgScoreWhenSkipped: Int
    let scoreDifference: Int
    let completionRate: Double  // 0-1, 完成比例
    let nightsCompleted: Int
    let nightsSkipped: Int

    var hasImpact: Bool {
        abs(scoreDifference) >= 3 && nightsCompleted >= 2 && nightsSkipped >= 2
    }

    var impactLabel: String {
        guard hasImpact else { return "样本不足" }
        if scoreDifference >= 8 { return "影响明显" }
        if scoreDifference >= 3 { return "有正面影响" }
        if scoreDifference <= -3 { return "影响反向" }
        return String(localized: "影响不明显")
    }
}

// MARK: - 环境趋势摘要

struct SleepEnvironmentTrendSummary: Equatable, Sendable {
    let correlation: EnvironmentSleepCorrelation
    let headline: String
    let insight: String
    let preparedAvgScore: Int?
    let unpreparedAvgScore: Int?
    let scoreDifference: Int?
    let totalNights: Int
    let preparedNights: Int
    let unpreparedNights: Int
    let factorImpacts: [EnvironmentFactorImpact]
    let recentCompletionRate: Double
    let suggestion: String
    let watchPrompt: String?
}

// MARK: - 环境趋势分析引擎

struct SleepEnvironmentTrendEngine {
    struct Input {
        let environmentRecords: [SleepEnvironmentManagementRecord]
        let sleepNightSummaries: [SleepTrendNightSummary]
        let checklistItems: [SleepBedroomChecklistItem]
        let calendar: Calendar

        static func make(
            environmentRecords: [SleepEnvironmentManagementRecord],
            sleepNightSummaries: [SleepTrendNightSummary],
            checklistItems: [SleepBedroomChecklistItem] = SleepBedroomChecklistItem.defaults,
            calendar: Calendar = .current
        ) -> Input {
            Input(
                environmentRecords: environmentRecords,
                sleepNightSummaries: sleepNightSummaries,
                checklistItems: checklistItems,
                calendar: calendar
            )
        }
    }

    // MARK: - 分析入口

    func analyze(input: Input) -> SleepEnvironmentTrendSummary {
        let paired = pairNights(input: input)
        let totalNights = paired.count
        let threshold = max(1, Int(ceil(Double(input.checklistItems.count) * 0.5))) // 完成至少半数算"有准备"，5 项即 3 项

        let prepared = paired.filter { $0.record.completedItemIDs.count >= threshold }
        let unprepared = paired.filter { $0.record.completedItemIDs.count < threshold }

        let preparedScores = prepared.compactMap { $0.sleepScore }
        let unpreparedScores = unprepared.compactMap { $0.sleepScore }
        let preparedScoredCount = preparedScores.count
        let unpreparedScoredCount = unpreparedScores.count
        let scoredNights = preparedScoredCount + unpreparedScoredCount

        let preparedAvg = average(preparedScores)
        let unpreparedAvg = average(unpreparedScores)
        let diff = (preparedAvg != nil && unpreparedAvg != nil) ? preparedAvg! - unpreparedAvg! : nil

        let correlation = correlationLevel(
            diff: diff,
            preparedScoredCount: preparedScoredCount,
            unpreparedScoredCount: unpreparedScoredCount,
            scoredNights: scoredNights
        )

        let factorImpacts = analyzeFactors(input: input, paired: paired)

        let recentRate = recentCompletionRate(
            records: input.environmentRecords,
            itemCount: input.checklistItems.count,
            calendar: input.calendar
        )

        let headline = headlineText(correlation: correlation, diff: diff, totalNights: totalNights)
        let insight = insightText(
            correlation: correlation,
            preparedAvg: preparedAvg,
            unpreparedAvg: unpreparedAvg,
            diff: diff,
            preparedCount: preparedScoredCount,
            unpreparedCount: unpreparedScoredCount
        )
        let suggestion = suggestionText(correlation: correlation, factorImpacts: factorImpacts)
        let watchPrompt = watchPromptText(correlation: correlation, recentRate: recentRate)

        return SleepEnvironmentTrendSummary(
            correlation: correlation,
            headline: headline,
            insight: insight,
            preparedAvgScore: preparedAvg,
            unpreparedAvgScore: unpreparedAvg,
            scoreDifference: diff,
            totalNights: scoredNights,
            preparedNights: preparedScoredCount,
            unpreparedNights: unpreparedScoredCount,
            factorImpacts: factorImpacts,
            recentCompletionRate: recentRate,
            suggestion: suggestion,
            watchPrompt: watchPrompt
        )
    }

    // MARK: - 数据配对

    private struct PairedNight {
        let record: SleepEnvironmentManagementRecord
        let sleepScore: Int?
    }

    private func pairNights(input: Input) -> [PairedNight] {
        let sleepByDayKey: [String: (score: Int, date: Date)] = Dictionary(
            input.sleepNightSummaries.map {
                let key = dayKey(for: $0.day, calendar: input.calendar)
                return (key, (score: $0.sleepScoreEstimate, date: input.calendar.startOfDay(for: $0.day)))
            },
            uniquingKeysWith: { _, last in last }
        )
        var usedSleepKeys = Set<String>()
        var paired: [PairedNight] = []

        for record in input.environmentRecords.sorted(by: { $0.date < $1.date }) {
            let sleepKey = sleepMatchKeys(for: record, calendar: input.calendar)
                .first { sleepByDayKey[$0] != nil && !usedSleepKeys.contains($0) }
            if let sleepKey {
                usedSleepKeys.insert(sleepKey)
            }
            let score = sleepKey.flatMap { sleepByDayKey[$0]?.score }
            if score != nil || !record.completedItemIDs.isEmpty {
                paired.append(PairedNight(record: record, sleepScore: score))
            }
        }

        for (key, sleep) in sleepByDayKey where !usedSleepKeys.contains(key) {
            let record = SleepEnvironmentManagementRecord(
                dayKey: key,
                date: sleep.date,
                completedItemIDs: [],
                updatedAt: sleep.date
            )
            paired.append(PairedNight(record: record, sleepScore: sleep.score))
        }

        return paired.sorted { $0.record.date < $1.record.date }
    }

    // MARK: - 关联等级判定

    private func correlationLevel(
        diff: Int?,
        preparedScoredCount: Int,
        unpreparedScoredCount: Int,
        scoredNights: Int
    ) -> EnvironmentSleepCorrelation {
        // 数据不足：少于 5 个有睡眠评分的夜晚
        if scoredNights < 5 || diff == nil {
            return .insufficient
        }
        // 两组各至少 2 个样本
        if preparedScoredCount < 2 || unpreparedScoredCount < 2 {
            return .insufficient
        }

        guard let diff else { return .insufficient }

        if diff >= 8 {
            return .strong
        }
        if diff >= 3 {
            return .moderate
        }
        return .weak
    }

    // MARK: - 逐项影响分析

    private func analyzeFactors(input: Input, paired: [PairedNight]) -> [EnvironmentFactorImpact] {
        let scored = paired.filter { $0.sleepScore != nil }
        return input.checklistItems.map { item in
            let completed = scored.filter { $0.record.completedItemIDs.contains(item.id) }
            let skipped = scored.filter { !$0.record.completedItemIDs.contains(item.id) }

            let completedScores = completed.compactMap { $0.sleepScore }
            let skippedScores = skipped.compactMap { $0.sleepScore }

            let completedAvg = average(completedScores) ?? 0
            let skippedAvg = average(skippedScores) ?? 0
            let totalNights = completed.count + skipped.count
            let rate = totalNights > 0 ? Double(completed.count) / Double(totalNights) : 0

            return EnvironmentFactorImpact(
                id: item.id,
                title: item.title,
                symbol: item.symbol,
                avgScoreWhenCompleted: completedAvg,
                avgScoreWhenSkipped: skippedAvg,
                scoreDifference: completedAvg - skippedAvg,
                completionRate: rate,
                nightsCompleted: completed.count,
                nightsSkipped: skipped.count
            )
        }
    }

    // MARK: - 近期完成率

    private func recentCompletionRate(records: [SleepEnvironmentManagementRecord], itemCount: Int, calendar: Calendar) -> Double {
        guard let anchorDate = records.map(\.date).max() else { return 0 }
        let anchorStart = calendar.startOfDay(for: anchorDate)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: anchorStart) ?? anchorStart
        let recent = records.filter { $0.date >= sevenDaysAgo && $0.date <= anchorStart }
        guard !recent.isEmpty else { return 0 }
        let totalItems = recent.count * max(itemCount, 1)
        let completedItems = recent.reduce(0) { $0 + $1.completedItemIDs.count }
        return totalItems > 0 ? Double(completedItems) / Double(totalItems) : 0
    }

    // MARK: - 文案

    private func headlineText(correlation: EnvironmentSleepCorrelation, diff: Int?, totalNights: Int) -> String {
        switch correlation {
        case .strong:
            let d = diff ?? 0
            return String(format: String(localized: "环境准备对睡眠影响明显（评分高 %d 分）"), d)
        case .moderate:
            return "环境准备和睡眠质量有正向关联"
        case .weak:
            return "环境准备和睡眠关联不明显"
        case .insufficient:
            return String(localized: "环境趋势样本积累中（已记录 \(totalNights) 晚）")
        }
    }

    private func insightText(
        correlation: EnvironmentSleepCorrelation,
        preparedAvg: Int?,
        unpreparedAvg: Int?,
        diff: Int?,
        preparedCount: Int,
        unpreparedCount: Int
    ) -> String {
        switch correlation {
        case .strong, .moderate:
            let p = preparedAvg ?? 0
            let u = unpreparedAvg ?? 0
            return String(
                format: "完成环境准备的 %@平均睡眠评分 %@，未准备的%@平均 %@。",
                "\(preparedCount) 晚",
                "\(p) 分",
                "(\(unpreparedCount) 晚)",
                "\(u) 分"
            )
        case .weak:
            return String(localized: "目前环境准备和睡眠评分之间的关联不明显，可能需要更多样本或受其他因素影响更大。")
        case .insufficient:
            return String(localized: "继续记录每晚的卧室环境准备，积累 5 晚以上后会自动分析环境与睡眠质量的关联。")
        }
    }

    private func suggestionText(
        correlation: EnvironmentSleepCorrelation,
        factorImpacts: [EnvironmentFactorImpact]
    ) -> String {
        switch correlation {
        case .strong, .moderate:
            // 找出影响最大的项
            if let top = factorImpacts.filter({ $0.hasImpact }).sorted(by: { $0.scoreDifference > $1.scoreDifference }).first {
                return String(localized: "优先完成「\(top.title)」——完成时睡眠评分平均高 \(top.scoreDifference) 分。")
            }
            return String(localized: "继续保持每晚的环境准备，稳定后睡眠评分会更有优势。")
        case .weak:
            return String(localized: "环境准备关联不明显，可以先关注睡眠节律和咖啡因摄入的影响。")
        case .insufficient:
            return String(localized: "再记录几晚环境准备，系统会自动分析哪些环境因素对你影响最大。")
        }
    }

    private func watchPromptText(correlation: EnvironmentSleepCorrelation, recentRate: Double) -> String? {
        switch correlation {
        case .strong:
            return recentRate < 0.6 ? "环境准备影响明显，今晚别跳过。" : nil
        case .moderate:
            return recentRate < 0.4 ? "今晚试试完成环境清单。" : nil
        default:
            return nil
        }
    }

    // MARK: - 工具方法

    private func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int(values.reduce(0, +) / values.count)
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func sleepMatchKeys(for record: SleepEnvironmentManagementRecord, calendar: Calendar) -> [String] {
        let sameDayKey = record.dayKey
        let nextDay = calendar.date(byAdding: .day, value: 1, to: record.date) ?? record.date
        let nextDayKey = dayKey(for: nextDay, calendar: calendar)
        let updatedHour = calendar.component(.hour, from: record.updatedAt)
        return updatedHour >= 18 ? [nextDayKey] : [sameDayKey, nextDayKey]
    }
}
