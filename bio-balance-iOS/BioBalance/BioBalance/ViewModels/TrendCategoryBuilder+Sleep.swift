import Foundation
import HealthKit

/// TrendCategoryBuilder Sleep 子模块。
/// 从 TrendCategoryBuilder.swift 按职责拆分，对外接口不变。

extension TrendCategoryBuilder {

    static func sleepRatioSeries(
        from nights: [SleepTrendNightSummary],
        ratio: KeyPath<SleepTrendNightSummary, Double?>
    ) -> [TimeSeriesPointDouble] {
        nights.compactMap { night in
            guard let value = night[keyPath: ratio] else { return nil }
            return TimeSeriesPointDouble(
                timestamp: Int64(night.day.timeIntervalSince1970),
                value: value * 100.0
            )
        }
    }

    static func sleepEfficiencySeries(from nights: [SleepTrendNightSummary]) -> [TimeSeriesPointDouble] {
        nights.compactMap { night in
            guard let efficiency = night.efficiency else { return nil }
            return TimeSeriesPointDouble(
                timestamp: Int64(night.day.timeIntervalSince1970),
                value: efficiency * 100.0
            )
        }
    }

    static func sleepCompositeScoreSeries(
        from nights: [SleepTrendNightSummary],
        nightlyHeartRateValues: [HealthKitManager.NightlyAverageVital],
        sleepConsistencyPoints: [TimeSeriesPointDouble],
        nightlyHrvValues: [HealthKitManager.NightlyHRV]
    ) -> [SleepCompositeScoreBreakdown] {
        let heartRateByDay = Dictionary(uniqueKeysWithValues: nightlyHeartRateValues.map {
            (Calendar.current.startOfDay(for: $0.date), $0.averageValue)
        })
        let hrvByDay = Dictionary(uniqueKeysWithValues: nightlyHrvValues.map {
            (Calendar.current.startOfDay(for: $0.date), $0.avgMs)
        })
        let regularityByDay = Dictionary(uniqueKeysWithValues: sleepConsistencyPoints.map {
            (Calendar.current.startOfDay(for: $0.date), $0.value)
        })

        return nights.compactMap { night -> SleepCompositeScoreBreakdown? in
            let normalizedDay = Calendar.current.startOfDay(for: night.day)
            guard let regularity = regularityByDay[normalizedDay],
                  let efficiency = night.efficiency,
                  let deepRatio = night.deepRatio,
                  let remRatio = night.remRatio,
                  let physiologicalRecoveryScore = physiologicalRecoveryScore(
                      day: normalizedDay,
                      currentHeartRate: heartRateByDay[normalizedDay],
                      allHeartRates: heartRateByDay,
                      currentHrv: hrvByDay[normalizedDay],
                      allHrv: hrvByDay
                  ) else {
                return nil
            }

            let durationScore = sleepDurationScore(for: night)
            let sleepRegularityScore = min(100.0, max(0.0, regularity))
            let sleepEfficiencyScore = min(100.0, max(0.0, efficiency * 100.0))
            let deepRecoveryScore = deepRecoveryScore(for: deepRatio)
            let mentalRecoveryScore = mentalRecoveryScore(for: remRatio)
            let overallScore =
                durationScore * 0.18 +
                sleepRegularityScore * 0.16 +
                sleepEfficiencyScore * 0.16 +
                deepRecoveryScore * 0.16 +
                mentalRecoveryScore * 0.16 +
                physiologicalRecoveryScore * 0.18

            return SleepCompositeScoreBreakdown(
                day: normalizedDay,
                sleepDurationScore: durationScore,
                sleepRegularityScore: sleepRegularityScore,
                sleepEfficiencyScore: sleepEfficiencyScore,
                deepRecoveryScore: deepRecoveryScore,
                mentalRecoveryScore: mentalRecoveryScore,
                physiologicalRecoveryScore: physiologicalRecoveryScore,
                overallScore: min(100.0, max(0.0, overallScore.rounded()))
            )
        }
    }

    static func sleepDurationScore(for night: SleepTrendNightSummary) -> Double {
        let sleepHours = Double(night.asleepMinutes) / 60.0
        switch sleepHours {
        case 7.5...8.8:
            return 92.0 + min(8.0, (sleepHours - 7.5) * 6.0)
        case 6.5..<7.5:
            return 78.0 + (sleepHours - 6.5) * 14.0
        case 5.5..<6.5:
            return 60.0 + (sleepHours - 5.5) * 18.0
        case 8.8..<10.0:
            return max(72.0, 96.0 - (sleepHours - 8.8) * 14.0)
        default:
            return max(30.0, min(88.0, sleepHours / 8.0 * 100.0))
        }
    }

    static func deepRecoveryScore(for ratio: Double) -> Double {
        let deepRatio = ratio * 100.0
        return min(100.0, max(0.0, deepRatio / 20.0 * 100.0))
    }

    static func mentalRecoveryScore(for ratio: Double) -> Double {
        let remRatio = ratio * 100.0
        return min(100.0, max(0.0, remRatio / 24.0 * 100.0))
    }

    static func physiologicalRecoveryScore(
        day: Date,
        currentHeartRate: Double?,
        allHeartRates: [Date: Double],
        currentHrv: Double?,
        allHrv: [Date: Double]
    ) -> Double? {
        let heartRateScore = physiologicalHeartRateScore(
            for: day,
            current: currentHeartRate,
            allHeartRates: allHeartRates
        )
        let hrvScore = physiologicalHrvScore(
            for: day,
            current: currentHrv,
            allHrv: allHrv
        )

        switch (heartRateScore, hrvScore) {
        case let (.some(heartRateScore), .some(hrvScore)):
            return min(100.0, max(0.0, heartRateScore * 0.45 + hrvScore * 0.55))
        case let (.some(heartRateScore), .none):
            return min(100.0, max(0.0, heartRateScore))
        case let (.none, .some(hrvScore)):
            return min(100.0, max(0.0, hrvScore))
        case (.none, .none):
            return nil
        }
    }

    static func physiologicalHeartRateScore(
        for day: Date,
        current: Double?,
        allHeartRates: [Date: Double]
    ) -> Double? {
        guard let current, current > 0 else { return nil }

        let baselineDays = allHeartRates.keys
            .filter { $0 < day }
            .sorted()
            .suffix(6)
        let baselineValues = baselineDays.compactMap { allHeartRates[$0] }
            .filter { $0 > 0 }
        guard !baselineValues.isEmpty else { return nil }

        let baseline = baselineValues.reduce(0, +) / Double(baselineValues.count)
        let delta = current - baseline
        if delta <= 0 {
            return min(100.0, 84.0 + abs(delta) * 2.4)
        }
        return max(38.0, 84.0 - delta * 4.8)
    }

    static func physiologicalHrvScore(
        for day: Date,
        current: Double?,
        allHrv: [Date: Double]
    ) -> Double? {
        guard let current, current > 0 else { return nil }

        let baselineDays = allHrv.keys
            .filter { $0 < day }
            .sorted()
            .suffix(6)
        let baselineValues = baselineDays.compactMap { allHrv[$0] }
            .filter { $0 > 0 }
        guard !baselineValues.isEmpty else { return nil }

        let baseline = baselineValues.reduce(0, +) / Double(baselineValues.count)
        let delta = current - baseline
        if delta >= 0 {
            return min(100.0, 82.0 + delta * 1.8)
        }
        return max(38.0, 82.0 - abs(delta) * 2.2)
    }

    /// Nightly Vital Series 方法，负责把夜间平均生命体征结果转换为按日时序点列，用于周月趋势展示。
    static func nightlyVitalSeries(from values: [HealthKitManager.NightlyAverageVital]) -> [TimeSeriesPointDouble] {
        values.map { value in
            TimeSeriesPointDouble(
                timestamp: Int64(value.date.timeIntervalSince1970),
                value: value.averageValue
            )
        }
    }

    /// Nightly HRV Series 方法，负责把夜间平均 HRV 结果转换为按日时序点列，用于周月趋势展示。
    static func nightlyHrvSeries(from values: [HealthKitManager.NightlyHRV]) -> [TimeSeriesPointDouble] {
        values.map { value in
            TimeSeriesPointDouble(
                timestamp: Int64(value.date.timeIntervalSince1970),
                value: value.avgMs
            )
        }
    }

    /// Sleep Recovery Metric Points 方法，负责在日视图优先读取睡眠窗口内明细样本，并在缺失时回退到夜间聚合点列。
    static func sleepRecoveryMetricPoints(
        range: TrendsRange,
        sleepInterval: SleepInterval?,
        fallback: [TimeSeriesPointDouble],
        loader: (SleepInterval) async throws -> [TimeSeriesPointDouble]
    ) async -> [TimeSeriesPointDouble] {
        guard range == .day, let sleepInterval else {
            return fallback
        }

        let points = (try? await loader(sleepInterval))?
            .filter { $0.date >= sleepInterval.start && $0.date <= sleepInterval.end }
            .sorted { $0.date < $1.date } ?? []

        return points.isEmpty ? fallback : points
    }

    static func sleepConsistencySummary(from points: [TimeSeriesPointDouble]) -> String? {
        guard let latest = points.last else { return nil }
        switch latest.value {
        case 80...:
            return "规律稳定"
        case 65..<80:
            return String(localized: "轻度波动")
        default:
            return String(localized: "作息不稳")
        }
    }

    static func ratioSummary(from points: [TimeSeriesPointDouble]) -> String? {
        guard let latest = points.last else { return nil }
        return "\(Int(latest.value.rounded()))%"
    }

    static func efficiencySummary(from points: [TimeSeriesPointDouble]) -> String? {
        guard let latest = points.last else { return nil }
        return "\(Int(latest.value.rounded()))%"
    }

    static func scoreSummary(from breakdowns: [SleepCompositeScoreBreakdown]) -> String? {
        guard let latest = breakdowns.last else { return nil }
        return String(localized: "时长 \(Int(latest.sleepDurationScore.rounded())) / 规律性 \(Int(latest.sleepRegularityScore.rounded())) / 效率 \(Int(latest.sleepEfficiencyScore.rounded())) / 深度 \(Int(latest.deepRecoveryScore.rounded())) / 精神 \(Int(latest.mentalRecoveryScore.rounded())) / 生理 \(Int(latest.physiologicalRecoveryScore.rounded())) / 综合 \(Int(latest.overallScore.rounded()))分")
    }

    static func buildSleepClinicalSummary(
        nights: [SleepTrendNightSummary],
        sleepPoints: [TimeSeriesPointDouble],
        consistencyPoints: [TimeSeriesPointDouble],
        sleepScorePoints: [TimeSeriesPointDouble],
        stages: [SleepStage]
    ) -> SleepTrendClinicalSummaryModel? {
        let averageSleep = averageValue(for: sleepPoints)
        let averageConsistency = averageValue(for: consistencyPoints)
        let lastNight = nights.last
        let deepRatio = lastNight?.deepRatio.map { $0 * 100.0 }
        let remRatio = lastNight?.remRatio.map { $0 * 100.0 }

        let headline: String
        if sleepPoints.isEmpty {
            headline = "睡眠恢复趋势还在建立，继续记录后会更容易看清结构问题。"
        } else if let deepRatio, deepRatio < 15 {
            headline = "最近已经睡够一些，但真正拖累恢复的还是深睡偏少。"
        } else if let averageConsistency, averageConsistency < 70 {
            headline = "最近恢复压力更多来自节律波动，不只是单晚睡得够不够。"
        } else {
            headline = "最近睡眠恢复底盘基本稳定，下一步重点看结构质量还能不能继续变好。"
        }

        let explanation: String
        if stages.isEmpty {
            explanation = "先用睡眠时长、规律性和恢复评分判断整体方向，阶段样本补齐后再确认问题到底出在结构还是节律。"
        } else {
            explanation = "先判断昨夜恢复有没有卡在结构上，再结合最近时长、规律性和评分变化看这是单晚波动还是连续趋势。"
        }

        var heroItems: [TrendHeroSummaryItem] = []
        if let averageSleep {
            heroItems.append(
                TrendHeroSummaryItem(
                    title: "平均睡眠时长",
                    value: durationText(minutes: averageSleep),
                    detail: averageSleep < 390 ? "恢复底盘还偏短，先把睡够放在第一位" : "恢复底盘已经有了，问题不主要在时长"
                )
            )
        }
        let averageSleepScore = averageValue(for: sleepScorePoints)
        if let averageSleepScore {
            heroItems.append(
                TrendHeroSummaryItem(
                    title: "睡眠评分",
                    value: "\(Int(averageSleepScore.rounded()))分",
                    detail: averageSleepScore < 70 ? "整体恢复完成度还没站稳" : "整体恢复完成度已经进入可读区间"
                )
            )
        }
        if let averageConsistency {
            heroItems.append(
                TrendHeroSummaryItem(
                    title: "睡眠规律性",
                    value: "\(Int(averageConsistency.rounded()))分",
                    detail: averageConsistency < 70 ? "作息波动正在削弱恢复连续性" : "最近节律比较稳，干扰相对较小"
                )
            )
        }
        if let deepRatio {
            heroItems.append(
                TrendHeroSummaryItem(
                    title: "昨夜深睡占比",
                    value: "\(Int(deepRatio.rounded()))%",
                    detail: deepRatio < 15 ? "身体恢复这一段偏弱，是当前最该盯的点" : "身体恢复段基本在线，没有明显短板"
                )
            )
        } else if let remRatio {
            heroItems.append(
                TrendHeroSummaryItem(
                    title: "昨夜 REM 占比",
                    value: "\(Int(remRatio.rounded()))%",
                    detail: remRatio < 18 ? "精神恢复段还不够完整" : "精神恢复段没有明显短板"
                )
            )
        }

        let stageHeadline: String
        if let lastNight {
            stageHeadline = Self.stageHeadline(for: lastNight)
        } else {
            stageHeadline = "阶段样本不足时，先把关注点放在时长与规律性。"
        }

        let stageHighlights = buildStageHighlights(from: lastNight)

        return SleepTrendClinicalSummaryModel(
            headline: headline,
            explanation: explanation,
            heroItems: Array(heroItems.prefix(4)),
            stageHeadline: stageHeadline,
            stageHighlights: Array(stageHighlights.prefix(4))
        )
    }

    static func durationText(minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        let hours = rounded / 60
        let mins = rounded % 60
        if mins == 0 {
            return String(localized: "\(hours)小时")
        }
        return String(localized: "\(hours)小时\(mins)分")
    }

    static func stageHeadline(for night: SleepTrendNightSummary) -> String {
        if let deepRatio = night.deepRatio, deepRatio < 0.15 {
            return String(localized: "昨夜深睡占比偏低，恢复性睡眠结构仍然偏弱。")
        }
        if let remRatio = night.remRatio, remRatio < 0.18 {
            return String(localized: "昨夜 REM 占比偏低，睡眠结构完整性还有提升空间。")
        }
        if let efficiency = night.efficiency, efficiency < 0.85 {
            return String(localized: "昨夜在床与实际入睡之间仍有损耗，睡眠效率不够稳定。")
        }
        return String(localized: "昨夜阶段结构整体完整，可以继续对照恢复指标看是否真正受益。")
    }

    static func buildStageHighlights(from night: SleepTrendNightSummary?) -> [TrendSummaryPillModel] {
        guard let night else { return [] }
        var items: [TrendSummaryPillModel] = [
            TrendSummaryPillModel(title: "清醒", value: "\(night.awakeMinutes)分"),
            TrendSummaryPillModel(title: "浅睡", value: "\(night.coreMinutes)分"),
            TrendSummaryPillModel(title: "深睡", value: "\(night.deepMinutes)分"),
            TrendSummaryPillModel(title: "REM", value: "\(night.remMinutes)分")
        ]
        if let efficiency = night.efficiency {
            items.append(TrendSummaryPillModel(title: "效率", value: "\(Int((efficiency * 100).rounded()))%"))
        }
        return items
    }

}
