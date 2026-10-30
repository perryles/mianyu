import SwiftUI

// MARK: - 报告摘要视图模型

/// 报告摘要视图模型
/// 负责从 HealthKit 加载多日健康数据，计算综合评分、分项拆解、趋势上下文和行动建议。
/// 所有报告页面（日报、周报、月报、详情页）共用同一个 ViewModel 实例。
@MainActor
@Observable
final class ReportSummaryViewModel {
    /// 所有已加载的每日摘要（按日期升序）
    var days: [ReportDaySummary] = []
    /// 是否正在加载数据
    var isLoading = false

    /// 获取最近一条有数据的摘要（用于首页展示）
    var latest: ReportDaySummary? {
        days.last { $0.hasData }
    }

    /// 加载最近 N 天的报告数据
    func load(days count: Int = 30) {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let summaries = await Self.fetchSummaries(days: count)
            self.days = summaries
            self.isLoading = false
        }
    }

    /// 获取指定日期的单日摘要
    func summary(for date: Date) -> ReportDaySummary? {
        let target = Calendar.current.startOfDay(for: date)
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: target) }
    }

    /// 获取指定时间区间内的所有摘要
    func summaries(for interval: DateInterval) -> [ReportDaySummary] {
        days.filter { interval.contains($0.date) }
    }

    // MARK: - 共享计算辅助

    /// 获取指定日期前 7 天有评分的摘要序列（日报和详情页共用）
    func nearbyPoints(for reportDate: Date) -> [ReportDaySummary] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: reportDate)),
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reportDate)) else {
            return []
        }
        return summaries(for: DateInterval(start: start, end: end)).filter { $0.score != nil }
    }

    /// 计算指定日期近 7 天的平均 HRV（排除当天，用于轻养生评分）
    func recentAverageHrv(from nearbyPoints: [ReportDaySummary], excluding reportDate: Date) -> Double? {
        let calendar = Calendar.current
        let values = nearbyPoints
            .filter { !calendar.isDate($0.date, inSameDayAs: reportDate) }
            .compactMap { point in
                point.hrv.flatMap { $0 > 0 ? $0 : nil }
            }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - 数据加载与评分计算

    /// 从 HealthKit 拉取原始数据并组装为每日摘要序列
    private static func fetchSummaries(days count: Int) async -> [ReportDaySummary] {
        async let sleep = try? HealthKitManager.shared.fetchSleepDurationSeries(days: count)
        async let hrv = try? HealthKitManager.shared.fetchDailyHRVAverages(days: count)
        async let hr = try? HealthKitManager.shared.fetchDailyHeartRateAverages(days: count)
        async let rhr = try? HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: count)
        async let steps = try? HealthKitManager.shared.fetchDailyStepSums(days: count)
        async let energy = try? HealthKitManager.shared.fetchDailyActiveEnergySums(days: count)
        async let caffeine = try? HealthKitManager.shared.fetchDailyDietaryCaffeineSums(days: count)
        async let heartRate = try? HealthKitManager.shared.fetchDailyHeartRateAverages(days: count)
        async let distance = try? HealthKitManager.shared.fetchDailyDistanceWalkingRunningSums(days: count)

        let sleepPoints = await sleep ?? []
        let hrvPoints = await hrv ?? []
        let heartRatePoints = await hr ?? []
        let restingPoints = await rhr ?? []
        let stepPoints = await steps ?? []
        let energyPoints = await energy ?? []
        let caffeinePoints = await caffeine ?? []
        let dailyHeartRatePoints = await heartRate ?? []
        let distancePoints = await distance ?? []
        let stressPoints = HealthStressEstimator.estimateDailyStress(hrv: hrvPoints, heartRate: heartRatePoints, restingHeartRate: restingPoints)

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(max(count, 1) - 1), to: end) else { return [] }

        let sleepByDay = valuesByDay(sleepPoints)
        let hrvByDay = valuesByDay(hrvPoints)
        let stressByDay = valuesByDay(stressPoints)
        let stepsByDay = valuesByDay(stepPoints)
        let energyByDay = valuesByDay(energyPoints)
        let caffeineByDay = valuesByDay(caffeinePoints)
        let heartRateByDay = valuesByDay(dailyHeartRatePoints)
        let distanceByDay = valuesByDay(distancePoints)

        let rawSummaries: [ReportDaySummary] = (0..<max(count, 1)).compactMap { offset -> ReportDaySummary? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let normalized = calendar.startOfDay(for: day)
            let sleepHours = sleepByDay[normalized].map { $0 / 60.0 }
            let hrvValue = hrvByDay[normalized]
            let stressValue = stressByDay[normalized]
            let stepsValue = stepsByDay[normalized]
            let energyValue = energyByDay[normalized]
            let heartRateValue = heartRateByDay[normalized]
            let distanceValue = distanceByDay[normalized]
            let score = scoreFor(sleepHours: sleepHours, stress: stressValue, hrv: hrvValue, steps: stepsValue)
            let scoreBreakdown = ReportInterpretationEngine.makeBreakdown(
                sleepHours: sleepHours,
                stress: stressValue,
                hrv: hrvValue,
                steps: stepsValue,
                activeEnergy: energyValue
            )
            let caffeineTotal = Int((caffeineByDay[normalized] ?? 0).rounded())
            let context = HealthAIContext(
                dateText: ISO8601DateFormatter().string(from: normalized),
                sleep: .init(
                    durationMinutes: sleepHours.map { Int(($0 * 60.0).rounded()) },
                    score: score,
                    startLocalTime: nil,
                    endLocalTime: nil,
                    awakeCount: nil,
                    deepMinutes: nil,
                    remMinutes: nil
                ),
                recoveryVitals: .init(
                    nightlyHrvMs: hrvValue,
                    nightlyAverageHeartRate: nil,
                    nightlyRespiratoryRate: nil,
                    wristTemperatureCelsius: nil
                ),
                todayVitals: .init(
                    currentHeartRate: nil,
                    restingHeartRate: nil,
                    recentAverageRestingHeartRate: nil,
                    todayAverageHrv: hrvValue,
                    recentAverageHrv: hrvValue
                ),
                stress: .init(
                    score: stressValue.map { Int($0.rounded()) },
                    currentScore: nil,
                    dailyScore: stressValue.map { Int($0.rounded()) },
                    band: "report",
                    title: "日报回顾",
                    summary: "用于回看当天恢复节律。"
                ),
                activity: .init(
                    stepsToday: stepsValue.map { Int($0.rounded()) },
                    exerciseMinutesToday: nil,
                    standHoursToday: nil,
                    walkingSpeedMpsToday: nil
                ),
                recoveryBehavior: .init(
                    sedentaryElapsedMinutesCurrent: nil,
                    sedentaryTotalMinutesToday: nil,
                    sedentaryLongestSessionMinutesToday: nil,
                    activeBreakCountToday: nil
                ),
                caffeineConsumedTodayMg: caffeineTotal > 0 ? caffeineTotal : nil,
                caffeineEstimatedRemainingMg: caffeineTotal > 0 ? Int((Double(caffeineTotal) * 0.55).rounded()) : nil,
                daylightMinutesToday: nil,
                waterMlToday: nil,
                sleepGoalMinutes: SleepGoalResolver.goalMinutes(),
                recoveryScriptPlan: nil,
                healthProfileSummary: nil,
                disclaimer: "仅供健康管理参考，不构成医疗诊断、治疗或急救建议。如有持续不适或异常指标，请咨询医生。"
            )
            let scriptPlan = RecoveryScriptEngine().makePlan(context: context, now: normalized)
            let adviceSummary = ReportInterpretationEngine.makeAdviceSummary(
                breakdown: scoreBreakdown,
                recoveryScriptPlan: scriptPlan
            )

            return ReportDaySummary(
                id: Int64(normalized.timeIntervalSince1970),
                date: normalized,
                score: score,
                sleepHours: sleepHours,
                stress: stressValue,
                hrv: hrvValue,
                steps: stepsValue,
                activeEnergy: energyValue,
                averageHeartRate: heartRateValue,
                distanceMeters: distanceValue,
                recoveryScriptPlan: scriptPlan,
                caffeineWeeklySummary: nil,
                scoreBreakdown: scoreBreakdown,
                adviceSummary: adviceSummary,
                trendContext: nil
            )
        }

        // 第二轮：为每天补充趋势上下文（需要完整序列才能计算）
        return rawSummaries.enumerated().map { index, summary in
            ReportDaySummary(
                id: summary.id,
                date: summary.date,
                score: summary.score,
                sleepHours: summary.sleepHours,
                stress: summary.stress,
                hrv: summary.hrv,
                steps: summary.steps,
                activeEnergy: summary.activeEnergy,
                averageHeartRate: summary.averageHeartRate,
                distanceMeters: summary.distanceMeters,
                recoveryScriptPlan: summary.recoveryScriptPlan,
                caffeineWeeklySummary: summary.caffeineWeeklySummary,
                scoreBreakdown: summary.scoreBreakdown,
                adviceSummary: summary.adviceSummary,
                trendContext: ReportInterpretationEngine.makeTrendContext(currentIndex: index, summaries: rawSummaries)
            )
        }
    }

    /// 将时间序列按天聚合为字典
    private static func valuesByDay(_ points: [TimeSeriesPointDouble]) -> [Date: Double] {
        let calendar = Calendar.current
        return Dictionary(uniqueKeysWithValues: points.map { (calendar.startOfDay(for: $0.date), $0.value) })
    }

    /// 加权平均评分算法（睡眠 0.35、压力 0.25、HRV 0.20、活动 0.20）
    private static func scoreFor(sleepHours: Double?, stress: Double?, hrv: Double?, steps: Double?) -> Int? {
        var weighted = 0.0
        var weight = 0.0

        if let sleepHours, sleepHours > 0 {
            let sleepScore = max(0, min(100, 100 - abs(sleepHours - 7.5) * 16))
            weighted += sleepScore * 0.35
            weight += 0.35
        }
        if let stress, stress > 0 {
            weighted += max(0, 100 - stress) * 0.25
            weight += 0.25
        }
        if let hrv, hrv > 0 {
            weighted += max(0, min(100, hrv * 1.4)) * 0.20
            weight += 0.20
        }
        if let steps, steps > 0 {
            weighted += max(0, min(100, steps / 80.0)) * 0.20
            weight += 0.20
        }

        guard weight > 0 else { return nil }
        return max(1, min(100, Int((weighted / weight).rounded())))
    }
}
