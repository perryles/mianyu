import SwiftUI

enum SleepDayDataSelector {
    nonisolated static func latest<Value>(
        in values: [Value],
        matching targetDate: Date,
        calendar: Calendar,
        date: KeyPath<Value, Date>
    ) -> Value? {
        values.last { value in
            calendar.isDate(value[keyPath: date], inSameDayAs: targetDate)
        }
    }
}

enum SleepPageFocusTone: String, Equatable, Sendable {
    case building
    case attention
    case recovery
    case stable
}

struct SleepPageFocus: Equatable, Sendable {
    let badgeText: String
    let title: String
    let reason: String
    let context: String
    let action: String
    let tone: SleepPageFocusTone
}

enum SleepPageFocusBuilder {
    nonisolated static func make(
        data: SleepData?,
        latestSummary: SleepSessionSummary?,
        lateNightSummary: LateNightRecoverySummary = .init(isActive: false, hasNoSleepData: true, plan: nil),
        goalMinutes: Int,
        recentNights: [SleepTrendNightSummary] = []
    ) -> SleepPageFocus {
        guard let data, data.duration_minutes > 0 else {
            return SleepPageFocus(
                badgeText: String(localized: "建立中"),
                title: String(localized: "先完成一次可用睡眠记录"),
                reason: String(localized: "当前还没有读取到可用于判断昨夜状态的主睡眠样本。"),
                context: String(localized: "当前没有可用于比较的夜间样本。"),
                action: String(localized: "今晚保持设备佩戴与睡眠权限开启，明早再回来查看。"),
                tone: .building
            )
        }

        let context = trendContext(recentNights: recentNights, goalMinutes: goalMinutes)

        if lateNightSummary.isActive, let plan = lateNightSummary.plan {
            let reason = plan.detection.reasons.prefix(2).joined(separator: "；")
            let action = plan.eveningActions.first?.detail
                ?? String(localized: "今晚按恢复计划提前收尾，先减少睡前刺激。")
            return SleepPageFocus(
                badgeText: lateNightBadge(for: plan.detection.severity),
                title: plan.headline,
                reason: reason.isEmpty ? String(localized: "昨夜作息与睡眠时长触发了恢复判断。") : reason,
                context: context,
                action: action,
                tone: .recovery
            )
        }

        if let latestSummary, summaryMatches(latestSummary, data: data) {
            let insight = latestSummary.insight
            return SleepPageFocus(
                badgeText: badgeText(for: insight.riskFlag),
                title: insight.headline,
                reason: insight.summary,
                context: context,
                action: insight.recommendationText,
                tone: tone(for: insight.riskFlag, score: data.sleep_score)
            )
        }

        let normalizedGoal = max(goalMinutes, 1)
        let deficit = max(0, normalizedGoal - data.duration_minutes)
        if Double(data.duration_minutes) / Double(normalizedGoal) < 0.82 {
            return SleepPageFocus(
                badgeText: String(localized: "优先补足"),
                title: String(localized: "昨夜睡眠时长偏短"),
                reason: String(localized: "主睡眠比当前目标少约 \(durationText(deficit))，今天的恢复储备可能偏保守。"),
                context: context,
                action: String(localized: "今晚先把入睡时间提前 20 到 30 分钟，不急着追求阶段比例。"),
                tone: .recovery
            )
        }

        if data.sleep_score > 0, data.sleep_score < 70 {
            return SleepPageFocus(
                badgeText: String(localized: "需要恢复"),
                title: String(localized: "昨夜恢复完成度偏低"),
                reason: String(localized: "睡眠评分为 \(data.sleep_score) 分，时长以外的连续性或结构仍有改善空间。"),
                context: context,
                action: String(localized: "今晚固定入睡窗口，并减少睡前两小时内的强刺激。"),
                tone: .recovery
            )
        }

        let deepMinutes = stageMinutes(named: ["Deep", "深睡"], in: data.stages)
        if deepMinutes > 0,
           Double(deepMinutes) / Double(max(data.duration_minutes, 1)) < 0.15 {
            let recentDeep = Array(recentNights.suffix(3)).filter { $0.asleepMinutes > 0 && $0.deepMinutes > 0 }
            let recentLowDeepCount = recentDeep.filter { ($0.deepRatio ?? 1) < 0.15 }.count
            let isRepeated = recentDeep.count >= 3 && recentLowDeepCount >= 2
            return SleepPageFocus(
                badgeText: String(localized: "观察结构"),
                title: isRepeated
                    ? String(localized: "近几晚深睡结构持续偏低")
                    : String(localized: "昨夜深睡占比较低"),
                reason: isRepeated
                    ? String(localized: "近 3 晚有 \(recentLowDeepCount) 晚深睡占比低于 15%，更适合继续观察连续趋势。")
                    : String(localized: "昨夜深睡约 \(deepMinutes) 分钟，单晚比例容易波动，暂不据此判断恢复问题。"),
                context: context,
                action: String(localized: "今晚保持固定作息和低刺激环境，继续观察结构是否回升。"),
                tone: .attention
            )
        }

        let usableRecentNights = Array(recentNights.suffix(7)).filter { $0.asleepMinutes > 0 }
        let recentShortCount = usableRecentNights.filter { $0.asleepMinutes < normalizedGoal }.count
        if usableRecentNights.count >= 3, recentShortCount >= 2 {
            return SleepPageFocus(
                badgeText: String(localized: "继续观察"),
                title: String(localized: "昨夜尚可，近期时长仍不稳"),
                reason: String(localized: "近 \(usableRecentNights.count) 晚有 \(recentShortCount) 晚没有达到当前睡眠目标，暂不把单晚回升当作稳定改善。"),
                context: context,
                action: String(localized: "继续固定入睡与起床窗口，先把一周内的多数夜晚稳定下来。"),
                tone: .attention
            )
        }

        return SleepPageFocus(
            badgeText: String(localized: "保持"),
            title: String(localized: "昨夜睡眠基础较稳"),
            reason: String(localized: "时长和恢复评分没有出现需要优先修复的明显短板。"),
            context: context,
            action: String(localized: "继续保持当前入睡与起床窗口，观察一周趋势是否稳定。"),
            tone: .stable
        )
    }

    private nonisolated static func summaryMatches(
        _ summary: SleepSessionSummary,
        data: SleepData
    ) -> Bool {
        guard summary.sleepDurationMinutes > 0,
              summary.insight.recommendationCode != "sleep_waiting" else { return false }
        if let rawEndTime = data.end_time, rawEndTime > 0 {
            let seconds = rawEndTime > 10_000_000_000 ? TimeInterval(rawEndTime) / 1_000 : TimeInterval(rawEndTime)
            let dataEnd = Date(timeIntervalSince1970: seconds)
            guard abs(summary.endTime.timeIntervalSince(dataEnd)) <= 18 * 60 * 60 else { return false }
        }
        let allowedDifference = max(45, Int(Double(data.duration_minutes) * 0.12))
        return abs(summary.sleepDurationMinutes - data.duration_minutes) <= allowedDifference
    }

    private nonisolated static func trendContext(
        recentNights: [SleepTrendNightSummary],
        goalMinutes: Int
    ) -> String {
        let usable = Array(recentNights.suffix(7)).filter { $0.asleepMinutes > 0 }
        guard usable.count >= 3 else {
            return String(localized: "当前主要依据昨夜记录，连续趋势仍在积累。")
        }
        let average = usable.reduce(0) { $0 + $1.asleepMinutes } / usable.count
        let shortCount = usable.filter { $0.asleepMinutes < max(goalMinutes, 1) }.count
        return String(localized: "近 \(usable.count) 晚平均 \(durationText(average))，其中 \(shortCount) 晚未达到当前睡眠目标。")
    }

    private nonisolated static func badgeText(for risk: SleepInsightRiskFlag) -> String {
        switch risk {
        case .elevated: return String(localized: "优先留意")
        case .monitor: return String(localized: "继续观察")
        case .none: return String(localized: "保持")
        }
    }

    private nonisolated static func lateNightBadge(for severity: LateNightSeverity) -> String {
        switch severity {
        case .mild: return String(localized: "轻度熬夜")
        case .moderate: return String(localized: "明显熬夜")
        case .severe: return String(localized: "严重熬夜")
        }
    }

    private nonisolated static func tone(
        for risk: SleepInsightRiskFlag,
        score: Int
    ) -> SleepPageFocusTone {
        switch risk {
        case .elevated: return .recovery
        case .monitor: return .attention
        case .none: return score >= 80 ? .stable : .attention
        }
    }

    private nonisolated static func stageMinutes(named names: [String], in stages: [SleepStage]) -> Int {
        stages
            .filter { names.contains($0.stage) }
            .reduce(0) { $0 + max($1.duration, 0) }
    }

    private nonisolated static func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return String(localized: "\(minutes) 分钟") }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return String(localized: "\(hours) 小时") }
        return String(localized: "\(hours) 小时 \(remainder) 分钟")
    }
}

/// 睡眠视图模型 作为视图模型层里的界面状态管理入口。
/// 负责连接界面与底层数据源，处理状态管理、业务计算和用户操作响应。
@MainActor
@Observable
class SleepViewModel {
    var sleepData: SleepData?
    var sleepInterval: SleepInterval?
    var sleepIntervals: [SleepInterval] = []
    var sleepHeartRatePoints: [TimeSeriesPoint] = []
    var nightlyHrv: Double?
    var baselineNightlyHrv: Double?
    var overnightAverageHeartRate: Double?
    var baselineOvernightHeartRate: Double?
    var nightlyRespirationRate: Double?
    var baselineNightlyRespirationRate: Double?
    var sleepingWristTemperature: Double?
    var baselineSleepingWristTemperature: Double?
    var sleepingBreathingDisturbances: Double?
    var baselineSleepingBreathingDisturbances: Double?
    var recentNightSummaries: [SleepTrendNightSummary] = []
    var monitoringState: SleepMonitoringState = SleepMonitoringState()
    var latestSleepSummary: SleepSessionSummary?
    var sleepEnvironmentManagementSummary: SleepEnvironmentManagementSummary?
    var sleepRhythmProtectionSummary: SleepRhythmProtectionSummary?
    var lateNightRecoverySummary: LateNightRecoverySummary = .init(isActive: false, hasNoSleepData: true, plan: nil)
    var sleepEnvironmentTrendSummary: SleepEnvironmentTrendSummary?
    @ObservationIgnored @AppStorage("daily_sleep_goal_hours") private var sleepGoalHours: Double = 8.0
    @ObservationIgnored @AppStorage("sleepLackReminderEnabled") private var sleepLackReminderEnabled: Bool = true
    private let sleepEnvironmentManagementStore = SleepEnvironmentManagementStore.shared
    private let sleepRhythmProtectionStore = SleepRhythmProtectionStore.shared
    private let caffeineDoseEventStore = CaffeineDoseEventStore.shared
    
    var sleepGoalMinutes: Int { Int(sleepGoalHours * 60.0) }

    var pageFocus: SleepPageFocus {
        SleepPageFocusBuilder.make(
            data: sleepData,
            latestSummary: latestSleepSummary,
            lateNightSummary: lateNightRecoverySummary,
            goalMinutes: sleepGoalMinutes,
            recentNights: recentNightSummaries
        )
    }

    func loadData() {
        Task {
            await SleepMonitoringOrchestrator.shared.restoreState()
            let orchestrator = SleepMonitoringOrchestrator.shared
            let restoredState = orchestrator.state
            let restoredSummary = orchestrator.latestSummary ?? AppGroupManager.shared.getSleepLatestSummary()
            await MainActor.run {
                self.monitoringState = restoredState
                self.latestSleepSummary = restoredSummary
            }
        }

        Task { [weak self] in
            let data: SleepData? = nil
            do {
                    let referenceDate = Date()
                    let calendar = Calendar.current
                    // 卡片/详情各模块统一用主睡眠（最长段）时长；午睡单独在分段卡与“含午睡”提示展示。
                    let realDuration = try await HealthKitManager.shared.fetchMainSleepDurationInMinutes(on: referenceDate)
                    let stages = try? await HealthKitManager.shared.fetchDetailedSleepStages()
                    async let intervalTask = try? HealthKitManager.shared.fetchPrimarySleepInterval(on: referenceDate)
                    async let intervalsTask = try? HealthKitManager.shared.fetchSleepIntervals(on: referenceDate)
                    let interval = await intervalTask
                    let intervals = await intervalsTask ?? []
                    let durationSeries = (try? await HealthKitManager.shared.fetchSleepDurationSeries(days: 30)) ?? []
                    let nightSummaries = (try? await HealthKitManager.shared.fetchSleepNightSummaries(days: 14)) ?? []
                    let hrPoints: [TimeSeriesPoint]
                    let respiratoryAverage: Double?
                    if let interval {
                        hrPoints = (try? await HealthKitManager.shared.fetchHeartRateSeries(start: interval.start, end: interval.end)) ?? []
                        let respiratorySeries = (try? await HealthKitManager.shared.fetchRespiratoryRateSeries(start: interval.start, end: interval.end, maxPoints: 120)) ?? []
                        let respiratoryValues = respiratorySeries.map(\.value).filter { $0 > 0 }
                        respiratoryAverage = respiratoryValues.isEmpty ? nil : respiratoryValues.reduce(0, +) / Double(respiratoryValues.count)
                    } else {
                        hrPoints = []
                        respiratoryAverage = nil
                    }
                    let nightlyHrvSeries = (try? await HealthKitManager.shared.fetchNightlyHRVAverages(days: 21)) ?? []
                    let nightlyHeartRateSeries = (try? await HealthKitManager.shared.fetchNightlyHeartRateAverages(days: 21)) ?? []
                    let nightlyRespiratorySeries = (try? await HealthKitManager.shared.fetchNightlyRespiratoryRateAverages(days: 21)) ?? []
                    let wristTemperatureSeries = (try? await HealthKitManager.shared.fetchDailySleepingWristTemperatureAverages(days: 21)) ?? []
                    let breathingDisturbanceSeries = (try? await HealthKitManager.shared.fetchDailySleepingBreathingDisturbanceAverages(days: 21)) ?? []
                    let sleepDay = calendar.startOfDay(for: interval?.end ?? referenceDate)
                    let nightlyHrv = SleepDayDataSelector.latest(
                        in: nightlyHrvSeries,
                        matching: sleepDay,
                        calendar: calendar,
                        date: \.date
                    )?.avgMs
                    let nightlyHeartRate = SleepDayDataSelector.latest(
                        in: nightlyHeartRateSeries,
                        matching: sleepDay,
                        calendar: calendar,
                        date: \.date
                    )?.averageValue
                    let nightlyRespiratoryRate = SleepDayDataSelector.latest(
                        in: nightlyRespiratorySeries,
                        matching: sleepDay,
                        calendar: calendar,
                        date: \.date
                    )?.averageValue
                    let overnightHeartRateValues = hrPoints.map { Double($0.value) }.filter { $0 > 0 }
                    let overnightHeartRate = overnightHeartRateValues.isEmpty
                        ? nightlyHeartRate
                        : overnightHeartRateValues.reduce(0, +) / Double(overnightHeartRateValues.count)
                    let wristTemperature = SleepDayDataSelector.latest(
                        in: wristTemperatureSeries,
                        matching: sleepDay,
                        calendar: calendar,
                        date: \.date
                    )?.value
                    let breathingDisturbances = SleepDayDataSelector.latest(
                        in: breathingDisturbanceSeries,
                        matching: sleepDay,
                        calendar: calendar,
                        date: \.date
                    )?.value
                    
                    await MainActor.run {
                        let server = data
                        guard let self else { return }
                        // 有些数据源把跨午夜的主睡眠归到前一日，导致“按今天”
                        // 查询为空；夜间摘要已按真实会话结束时间聚合，作为可靠回退。
                        let latestNight = nightSummaries.max { $0.endTime < $1.endTime }
                        let resolvedDuration = self.resolvedSleepDuration(
                            primary: realDuration,
                            series: durationSeries,
                            referenceDate: referenceDate,
                            calendar: calendar,
                            fallbackMinutes: latestNight?.asleepMinutes
                        )
                        let resolvedStages = self.resolvedSleepStages(primary: stages ?? [], durationMinutes: resolvedDuration)
                        let resolvedScore = self.resolvedSleepScore(serverScore: server?.sleep_score ?? 0, durationMinutes: resolvedDuration)
                        let resolvedInterval = interval ?? latestNight.map {
                            SleepInterval(start: $0.startTime, end: $0.endTime)
                        }
                        self.sleepInterval = resolvedInterval
                        self.sleepIntervals = intervals
                        self.sleepHeartRatePoints = hrPoints
                        self.nightlyHrv = nightlyHrv.flatMap { $0 > 0 ? $0 : nil }
                        self.baselineNightlyHrv = StressBodyBatteryEngine.personalBaseline(nightlyHrvSeries.map(\.avgMs))
                        self.overnightAverageHeartRate = overnightHeartRate.flatMap { $0 > 0 ? $0 : nil }
                        self.baselineOvernightHeartRate = StressBodyBatteryEngine.personalBaseline(nightlyHeartRateSeries.map(\.averageValue))
                        self.nightlyRespirationRate = respiratoryAverage
                            ?? nightlyRespiratoryRate
                            ?? server?.avg_respiration_rate
                        self.baselineNightlyRespirationRate = StressBodyBatteryEngine.personalBaseline(nightlyRespiratorySeries.map(\.averageValue))
                        self.sleepingWristTemperature = wristTemperature
                        self.baselineSleepingWristTemperature = StressBodyBatteryEngine.personalBaseline(wristTemperatureSeries.map(\.value))
                        self.sleepingBreathingDisturbances = breathingDisturbances
                        self.baselineSleepingBreathingDisturbances = StressBodyBatteryEngine.personalBaseline(
                            breathingDisturbanceSeries.map(\.value),
                            allowsZero: true
                        )
                        self.recentNightSummaries = nightSummaries
                        self.monitoringState = SleepMonitoringOrchestrator.shared.state
                        if resolvedDuration > 0 {
                            let resolvedNightlyHrv = self.nightlyHrv
                            let merged = SleepData(
                                sleep_score: resolvedScore,
                                duration_minutes: resolvedDuration,
                                stages: resolvedStages,
                                avg_heart_rate: server?.avg_heart_rate,
                                avg_respiration_rate: server?.avg_respiration_rate,
                                awake_count: server?.awake_count,
                                start_time: server?.start_time ?? resolvedInterval.map { Int($0.start.timeIntervalSince1970) },
                                end_time: server?.end_time ?? resolvedInterval.map { Int($0.end.timeIntervalSince1970) }
                            )
                            self.sleepData = merged
                            Task {
                                await SleepMonitoringOrchestrator.shared.finalizeSleepSession(
                                    interval: resolvedInterval,
                                    durationMinutes: merged.duration_minutes,
                                    stages: merged.stages,
                                    nightlyHrv: resolvedNightlyHrv,
                                    awakeCount: merged.awake_count ?? 0,
                                    recentBedtimes: nightSummaries.map(\.startTime)
                                )
                                let summary = SleepMonitoringOrchestrator.shared.latestSummary
                                let monitoringState = SleepMonitoringOrchestrator.shared.state
                                await MainActor.run {
                                    self.latestSleepSummary = summary
                                    self.monitoringState = monitoringState
                                    AppGroupManager.shared.saveSleepLatestSummary(summary)
                                    AppGroupManager.shared.saveSleepMonitoringState(monitoringState)
                                }
                            }
                            AppGroupManager.shared.saveSleepSummary(
                                durationMinutes: merged.duration_minutes > 0 ? merged.duration_minutes : nil,
                                score: merged.sleep_score > 0 ? merged.sleep_score : nil
                            )
                            WidgetRefreshCoordinator.refresh([.overall, .sleep], reason: .healthUpdate)
                            self.handleSleepLackReminderIfNeeded(merged)
                            self.refreshRhythmProtectionSummary(mode: .rhythmTraining)
                            self.refreshSleepEnvironmentManagementSummary(environmentInsight: nil)
                            self.refreshLateNightRecovery()
                            self.refreshEnvironmentTrend()
                            Task {
                                await PersonalizedReminderCenter.shared.evaluateAndReschedule()
                            }
                            return
                        }
                        let fallback = server ?? SleepData(sleep_score: 0, duration_minutes: 0, stages: [])
                        self.sleepData = fallback
                        self.latestSleepSummary = AppGroupManager.shared.getSleepLatestSummary()
                        AppGroupManager.shared.saveSleepSummary(
                            durationMinutes: fallback.duration_minutes > 0 ? fallback.duration_minutes : nil,
                            score: fallback.sleep_score > 0 ? fallback.sleep_score : nil
                        )
                        WidgetRefreshCoordinator.refresh([.overall, .sleep], reason: .healthUpdate)
                        self.handleSleepLackReminderIfNeeded(fallback)
                        self.refreshRhythmProtectionSummary(mode: .rhythmTraining)
                        self.refreshSleepEnvironmentManagementSummary(environmentInsight: nil)
                        self.refreshLateNightRecovery()
                        self.refreshEnvironmentTrend()
                        Task {
                            await PersonalizedReminderCenter.shared.evaluateAndReschedule()
                        }
                    }
                } catch {
                    await MainActor.run {
                        self?.sleepInterval = nil
                        self?.sleepIntervals = []
                        self?.sleepHeartRatePoints = []
                        self?.nightlyHrv = nil
                        self?.baselineNightlyHrv = nil
                        self?.overnightAverageHeartRate = nil
                        self?.baselineOvernightHeartRate = nil
                        self?.nightlyRespirationRate = nil
                        self?.baselineNightlyRespirationRate = nil
                        self?.sleepingWristTemperature = nil
                        self?.baselineSleepingWristTemperature = nil
                        self?.sleepingBreathingDisturbances = nil
                        self?.baselineSleepingBreathingDisturbances = nil
                        self?.recentNightSummaries = []
                        self?.monitoringState = SleepMonitoringOrchestrator.shared.state
                        self?.latestSleepSummary = AppGroupManager.shared.getSleepLatestSummary()
                        let fallback = data ?? SleepData(sleep_score: 0, duration_minutes: 0, stages: [])
                        self?.sleepData = fallback
                        AppGroupManager.shared.saveSleepSummary(
                            durationMinutes: fallback.duration_minutes > 0 ? fallback.duration_minutes : nil,
                            score: fallback.sleep_score > 0 ? fallback.sleep_score : nil
                        )
                        WidgetRefreshCoordinator.refresh([.overall, .sleep], reason: .healthUpdate)
                        self?.handleSleepLackReminderIfNeeded(fallback)
                        self?.refreshRhythmProtectionSummary(mode: .rhythmTraining)
                        self?.refreshSleepEnvironmentManagementSummary(environmentInsight: nil)
                        self?.refreshLateNightRecovery()
                        self?.refreshEnvironmentTrend()
                        Task {
                            await PersonalizedReminderCenter.shared.evaluateAndReschedule()
                        }
                    }
                }
        }
    }

    private func resolvedSleepDuration(
        primary: Int,
        series: [TimeSeriesPointDouble],
        referenceDate: Date,
        calendar: Calendar,
        fallbackMinutes: Int?
    ) -> Int {
        if primary > 0 {
            return primary
        }
        let positiveSeries = series.filter { $0.value > 0 }
        if let latest = SleepDayDataSelector.latest(
            in: positiveSeries,
            matching: referenceDate,
            calendar: calendar,
            date: \.date
        ) {
            return max(0, Int(latest.value.rounded()))
        }
        return max(0, fallbackMinutes ?? 0)
    }

    private func resolvedSleepStages(primary: [SleepStage], durationMinutes: Int) -> [SleepStage] {
        // 只展示 HealthKit 真实阶段数据；无阶段样本时返回空，
        // UI 走无阶段兼容布局，不再按固定比例合成伪阶段。
        primary.filter { $0.duration > 0 }
    }

    private func resolvedSleepScore(serverScore: Int, durationMinutes: Int) -> Int {
        if serverScore > 0 {
            return serverScore
        }
        guard durationMinutes > 0 else {
            return 0
        }

        let ratio = Double(durationMinutes) / Double(max(sleepGoalMinutes, 1))
        switch ratio {
        case 1.0...:
            return 86
        case 0.9..<1.0:
            return 79
        case 0.8..<0.9:
            return 72
        case 0.7..<0.8:
            return 65
        default:
            return 58
        }
    }

    private func handleSleepLackReminderIfNeeded(_ data: SleepData) {
        guard sleepLackReminderEnabled else { return }
        let goalMinutes = Int(sleepGoalHours * 60.0)
        guard goalMinutes > 0, data.duration_minutes > 0 else { return }
        guard data.duration_minutes < goalMinutes else { return }

        let key = "sleep_lack_reminder_day"
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: key)
        if last == today {
            return
        }
        UserDefaults.standard.set(today, forKey: key)

        let diff = goalMinutes - data.duration_minutes
        LocalNotificationScheduler.scheduleAfter(
            identifier: "sleep_lack_today",
            seconds: 2,
            title: String(localized: "😴 昨晚睡少了点"),
            body: String(localized: "比目标少睡了 \(diff) 分钟，今天咖啡少点、晚上早点钻被窝，把觉补回来！")
        )
    }

    func armSleepMonitoringFromToday() {
        Task {
            await SleepMonitoringOrchestrator.shared.armForSleep(
                source: .manual,
                watchConnected: HealthDataManager.shared.isWatchReachable,
                watchConfidence: 0.35
            )
            await SleepMonitoringOrchestrator.shared.startMonitoringIfNeeded()
            let state = SleepMonitoringOrchestrator.shared.state
            await MainActor.run {
                self.monitoringState = state
                AppGroupManager.shared.saveSleepMonitoringState(state)
            }
        }
    }

    func startSnoreAnalysisFlow() {
        armSleepMonitoringFromToday()
    }

    func makeRhythmRebuildPlan(mode: SleepRhythmTrainingMode, data: SleepData?) -> SleepRhythmRebuildPlan {
        let hasSleepData = (data?.duration_minutes ?? 0) > 0
        let score = hasSleepData ? rhythmStabilityScore(data: data) : nil
        let targetBedtime = recommendedTargetBedtime()
        let lateNights = recentLateNightCount()
        let awakeRisk = nightAwakeRiskLevel(data: data)
        let targetText = targetBedtime.map(shortTimeText) ?? "23:30"

        switch mode {
        case .rhythmTraining:
            return SleepRhythmRebuildPlan(
                headline: score.map { "节律稳定度 \($0)" } ?? "等待样本",
                score: score,
                title: "7 天睡眠节律训练",
                summary: "今晚先把入睡目标守在 \(targetText) 附近，连续几晚固定窗口，比单次补觉更容易拉回节律。",
                targetBedtime: targetBedtime,
                estimatedDays: 7,
                phaseTitle: rhythmTrainingPhaseTitle(score: score),
                phaseDetail: "目标不是今晚立刻完美，而是连续 7 天把入睡和起床锚点压回可预测范围。",
                diagnosisTitle: rhythmDiagnosisTitle(score: score, lateNights: lateNights, awakeRisk: awakeRisk),
                diagnosisDetail: rhythmTrainingDiagnosisDetail(score: score, lateNights: lateNights),
                rescueTitle: "如果今晚晚了",
                rescueDetail: "明早仍按固定起床锚点启动，午后不要补太长觉，晚上继续回到同一目标窗口。",
                actions: [
                    "固定入睡窗口：目标前后 30 分钟内上床。",
                    "固定起床锚点：即使昨晚偏晚，也尽量不要大幅赖床。",
                    "上午补自然光：起床后 1 小时内安排一次轻量户外暴露。"
                ],
                routineSteps: SleepRhythmRoutineStep.steps(for: mode)
            )
        case .lateNightRecovery:
            return SleepRhythmRebuildPlan(
                headline: lateNights == 0 ? "本周晚睡较少" : "本周晚睡 \(lateNights) 次",
                score: score,
                title: "晚睡 / 夜醒纠偏",
                summary: awakeRisk.summary(lateNightCount: lateNights),
                targetBedtime: targetBedtime,
                estimatedDays: max(2, min(5, lateNights + awakeRisk.days)),
                phaseTitle: lateNights >= 2 ? "先止住连续晚睡" : "防止晚睡复发",
                phaseDetail: "今晚重点是降低睡前唤醒度和夜醒后的二次刺激，先让前半夜变安静。",
                diagnosisTitle: "晚睡 \(lateNights) 次 · 夜醒\(awakeRisk.label)",
                diagnosisDetail: "近 7 天晚睡次数和昨夜清醒阶段一起决定纠偏强度；今晚先压低刺激，再处理夜醒后的二次清醒。",
                rescueTitle: "如果夜里醒了",
                rescueDetail: "先保持低光和静止，超过 20 分钟仍清醒时离床做低刺激活动，困意回来再上床。",
                actions: [
                    "今晚提前 45 分钟收尾，先减少屏幕和工作切换。",
                    "如果夜里醒来，先保持低光，不立刻看时间或刷手机。",
                    "下午后减少咖啡因，把提神需求前移到上午。"
                ],
                routineSteps: SleepRhythmRoutineStep.steps(for: mode)
            )
        case .travelReset:
            return SleepRhythmRebuildPlan(
                headline: "3 天重建",
                score: score,
                title: "时差 / 出差作息重建",
                summary: "先按本地时间固定起床，再把入睡时间每天前移 30-45 分钟，避免一次性硬拉太多。",
                targetBedtime: targetBedtime,
                estimatedDays: 3,
                phaseTitle: "本地时间重新锚定",
                phaseDetail: "先固定明早起床和日照，再让今晚入睡逐步靠近目标窗口。",
                diagnosisTitle: "保守 3 天过渡",
                diagnosisDetail: "不引入时区和航班输入时，默认用低风险节奏重建：先稳起床点，再逐晚移动入睡窗口。",
                rescueTitle: "如果时差感很强",
                rescueDetail: "先不要强迫提前太多，守住明早本地起床和上午日照，下一晚再前移 30 分钟。",
                actions: [
                    "第 1 天：按本地时间起床，白天用自然光把清醒节律拉起来。",
                    "第 2 天：晚间减少应酬和强光，入睡目标前移 30 分钟。",
                    "第 3 天：保持固定起床点，睡前流程完整做一遍。"
                ],
                routineSteps: SleepRhythmRoutineStep.steps(for: mode)
            )
        case .bedtimeRoutine:
            return SleepRhythmRebuildPlan(
                headline: "睡前流程",
                score: score,
                title: "今晚睡前流程管理",
                summary: "不用把今晚做得很复杂，按顺序完成四步，让身体知道该从白天模式切回夜间恢复。",
                targetBedtime: targetBedtime,
                estimatedDays: 1,
                phaseTitle: "今晚执行",
                phaseDetail: "把流程完成度当作今晚的主要目标，睡着本身交给身体慢慢接管。",
                diagnosisTitle: "流程信号优先",
                diagnosisDetail: "当数据不足或状态波动大时，先用固定流程给身体一个稳定的夜间切换信号。",
                rescueTitle: "如果流程没做完",
                rescueDetail: "保留最后两步：低光收尾和呼吸放松。少做一点，也比完全放弃更能维持信号。",
                actions: [
                    "按目标入睡时间倒推流程，不临睡前才开始准备。",
                    "完成流程后只保留低刺激活动，例如轻阅读或呼吸练习。",
                    "如果今晚状态很亢奋，宁可先降刺激，不强迫自己立刻睡着。"
                ],
                routineSteps: SleepRhythmRoutineStep.steps(for: mode)
            )
        }
    }

    func refreshSleepEnvironmentManagementSummary(environmentInsight: SleepEnvironmentSnoreInsight?) {
        sleepEnvironmentManagementSummary = SleepEnvironmentManagementEngine().build(
            input: SleepEnvironmentManagementEngine.Input(
                environmentInsight: environmentInsight,
                todayRecord: sleepEnvironmentManagementStore.record(),
                recentRecords: sleepEnvironmentManagementStore.recentRecords(days: 7),
                sleepData: sleepData,
                sleepSummary: latestSleepSummary
            )
        )
    }

    func refreshLateNightRecovery() {
        let caffeineEvents = caffeineDoseEventStore.allEvents()
        let stressValue = AppGroupManager.shared.getLatestStress().map { Int($0) }
        lateNightRecoverySummary = LateNightRecoveryEngine().makeSummary(
            sleepData: sleepData,
            sleepInterval: sleepInterval,
            sleepGoalMinutes: sleepGoalMinutes,
            caffeineEvents: caffeineEvents,
            stressLevel: stressValue
        )
        persistSleepGuidanceSnapshot()
    }

    func refreshEnvironmentTrend() {
        let envRecords = sleepEnvironmentManagementStore.recentRecords(days: 14)
        sleepEnvironmentTrendSummary = SleepEnvironmentTrendEngine().analyze(
            input: .make(
                environmentRecords: envRecords,
                sleepNightSummaries: recentNightSummaries
            )
        )
        persistSleepGuidanceSnapshot()
    }

    private func persistSleepGuidanceSnapshot() {
        let lateNightPrompt = lateNightRecoverySummary.plan?.watchPrompt
        let lateNightSeverity = lateNightRecoverySummary.severity?.rawValue
        let environmentRate = sleepEnvironmentTrendSummary?.recentCompletionRate
        let environmentPrompt = sleepEnvironmentTrendSummary?.watchPrompt ?? sleepEnvironmentTrendSummary?.suggestion

        AppGroupManager.shared.saveSleepGuidance(
            lateNightRecoveryPrompt: lateNightPrompt,
            lateNightRecoverySeverity: lateNightSeverity,
            environmentCompletionRate: environmentRate,
            environmentPrompt: environmentPrompt
        )

        let snapshot = WatchSyncSnapshotFactory(
            latestBodyAgeSummary: nil,
            realtimeHealth: nil,
            currentActivity: nil,
            currentSleep: sleepData,
            currentStress: nil
        ).makeSnapshot(realtime: nil)
        AppGroupSnapshotStore.save(
            AppGroupHealthSnapshot.fromSource(
                snapshot,
                healthSummary: AppGroupManager.shared.getHealthSummary()
            )
        )
        WidgetRefreshCoordinator.refresh([.overall, .sleep, .complication], reason: .insight)
    }

    func toggleSleepEnvironmentChecklistItem(_ itemID: String, completed: Bool, environmentInsight: SleepEnvironmentSnoreInsight?) {
        sleepEnvironmentManagementStore.setChecklistItem(itemID, completed: completed)
        refreshSleepEnvironmentManagementSummary(environmentInsight: environmentInsight)
        refreshEnvironmentTrend()
    }

    func refreshRhythmProtectionSummary(mode: SleepRhythmTrainingMode) {
        let plan = makeRhythmRebuildPlan(mode: mode, data: sleepData)
        let active = sleepRhythmProtectionStore.activePlan()
        let record = active?.mode == mode ? active : sleepRhythmProtectionStore.latestPlan(for: mode)
        sleepRhythmProtectionSummary = SleepRhythmProtectionEngine().build(
            input: SleepRhythmProtectionEngine.Input(
                mode: mode,
                plan: plan,
                record: record,
                now: Date(),
                calendar: .current
            )
        )
    }

    func ensureRhythmProtectionPlan(mode: SleepRhythmTrainingMode) {
        _ = sleepRhythmProtectionStore.ensureActivePlan(mode: mode)
        refreshRhythmProtectionSummary(mode: mode)
    }

    func startRhythmProtectionPlan(mode: SleepRhythmTrainingMode) {
        _ = sleepRhythmProtectionStore.start(mode: mode)
        refreshRhythmProtectionSummary(mode: mode)
    }

    func toggleRhythmProtectionStep(_ stepID: String, mode: SleepRhythmTrainingMode) {
        _ = sleepRhythmProtectionStore.ensureActivePlan(mode: mode)
        _ = sleepRhythmProtectionStore.toggleStep(stepID)
        refreshRhythmProtectionSummary(mode: mode)
    }

    func toggleRhythmProtectionToday(mode: SleepRhythmTrainingMode) {
        _ = sleepRhythmProtectionStore.ensureActivePlan(mode: mode)
        _ = sleepRhythmProtectionStore.toggleTodayCompleted()
        refreshRhythmProtectionSummary(mode: mode)
    }

    func adjustRhythmProtectionTargetOffset(_ delta: Int?, mode: SleepRhythmTrainingMode) {
        _ = sleepRhythmProtectionStore.ensureActivePlan(mode: mode)
        let baseTarget = makeRhythmRebuildPlan(mode: mode, data: sleepData).targetBedtime
        _ = sleepRhythmProtectionStore.adjustTargetOffset(by: delta, baseTargetBedtime: baseTarget)
        refreshRhythmProtectionSummary(mode: mode)
    }

    func toggleRhythmProtectionReminder(_ enabled: Bool, mode: SleepRhythmTrainingMode) {
        _ = sleepRhythmProtectionStore.ensureActivePlan(mode: mode)
        let target = sleepRhythmProtectionSummary?.targetBedtime ?? makeRhythmRebuildPlan(mode: mode, data: sleepData).targetBedtime
        _ = sleepRhythmProtectionStore.toggleReminderEnabled(enabled, targetBedtime: target)
        refreshRhythmProtectionSummary(mode: mode)
    }

    func recommendedTargetBedtime() -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let bedtime = habitualBedtimeMinutes().map { minutes -> Date? in
            dateTodayOrTomorrow(minutesFromMidnight: minutes, now: now, calendar: calendar)
        } ?? defaultBedtime(now: now, calendar: calendar)

        guard let bedtime else { return nil }
        if bedtime < now {
            return calendar.date(byAdding: .day, value: 1, to: bedtime)
        }
        return bedtime
    }

    private func rhythmStabilityScore(data: SleepData?) -> Int {
        let summaries = recentNightSummaries.suffix(7)
        var score = 82

        if let data, data.duration_minutes > 0 {
            let durationRatio = Double(data.duration_minutes) / Double(max(sleepGoalMinutes, 1))
            if durationRatio >= 0.95 {
                score += 8
            } else if durationRatio >= 0.82 {
                score += 2
            } else {
                score -= 12
            }
        }

        let lateNights = recentLateNightCount()
        score -= min(24, lateNights * 7)

        if let variancePenalty = bedtimeVariancePenalty(summaries: Array(summaries)) {
            score -= variancePenalty
        }

        if let data {
            score -= nightAwakeRiskLevel(data: data).scorePenalty
        }

        return min(100, max(30, score))
    }

    private func rhythmTrainingPhaseTitle(score: Int?) -> String {
        guard let score else { return "建立基础样本" }
        if score >= 82 { return "巩固稳定窗口" }
        if score >= 68 { return "收窄入睡波动" }
        return String(localized: "先重建固定锚点")
    }

    private func rhythmDiagnosisTitle(score: Int?, lateNights: Int, awakeRisk: SleepRhythmAwakeRisk) -> String {
        guard let score else { return "等待完整样本" }
        if lateNights >= 2 { return "晚睡是主要扰动" }
        if awakeRisk != .low && awakeRisk != .unknown { return "夜醒风险需要压低" }
        if score >= 82 { return "节律基础不错" }
        return "入睡窗口仍有波动"
    }

    private func rhythmTrainingDiagnosisDetail(score: Int?, lateNights: Int) -> String {
        guard let score else {
            return String(localized: "还没有足够睡眠样本时，不急着判断问题归因，先把今晚目标和明早起床锚点固定下来。")
        }
        if lateNights >= 2 {
            return String(localized: "近 7 天已经出现多次晚睡，训练重点不是补觉，而是连续几晚把入睡时间拉回同一窗口。")
        }
        if score >= 82 {
            return String(localized: "当前稳定度较好，今晚更适合做巩固训练：少改动、固定窗口、避免临睡前刺激。")
        }
        return String(localized: "稳定度还在恢复区间，今晚先把目标窗口缩到 30 分钟内，不追求一次性提前太多。")
    }

    private func recentLateNightCount() -> Int {
        recentNightSummaries
            .suffix(7)
            .filter { isLateNight($0.startTime) }
            .count
    }

    private func nightAwakeRiskLevel(data: SleepData?) -> SleepRhythmAwakeRisk {
        guard let data else { return .unknown }
        let awakeCount = data.awake_count ?? 0
        let awakeMinutes = stageMinutes(named: "Awake", in: data.stages)
        let awakeRatio = data.stageDistributionTotalMinutes > 0
            ? Double(awakeMinutes) / Double(data.stageDistributionTotalMinutes)
            : 0

        if awakeCount >= 3 || awakeRatio >= 0.12 {
            return .high
        }
        if awakeCount >= 1 || awakeRatio >= 0.07 {
            return .medium
        }
        return .low
    }

    private func habitualBedtimeMinutes() -> Int? {
        let values = recentNightSummaries.suffix(7).map { bedtimeMinutesForCircadianDay($0.startTime) }
        guard !values.isEmpty else {
            return sleepInterval.map { bedtimeMinutesForCircadianDay($0.start) }
        }
        let average = values.reduce(0, +) / values.count
        return max(21 * 60, min(24 * 60 + 30, average - 20))
    }

    private func bedtimeVariancePenalty(summaries: [SleepTrendNightSummary]) -> Int? {
        let values = summaries.map { Double(bedtimeMinutesForCircadianDay($0.startTime)) }
        guard values.count >= 3 else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        let meanDistance = values.map { abs($0 - average) }.reduce(0, +) / Double(values.count)
        if meanDistance >= 90 { return 14 }
        if meanDistance >= 60 { return 9 }
        if meanDistance >= 35 { return 5 }
        return 0
    }

    private func isLateNight(_ date: Date) -> Bool {
        let minutes = bedtimeMinutesForCircadianDay(date)
        return minutes >= 25 * 60
    }

    private func bedtimeMinutesForCircadianDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let raw = hour * 60 + minute
        return raw < 12 * 60 ? raw + 24 * 60 : raw
    }

    private func dateTodayOrTomorrow(minutesFromMidnight: Int, now: Date, calendar: Calendar) -> Date? {
        let normalized = minutesFromMidnight >= 24 * 60 ? minutesFromMidnight - 24 * 60 : minutesFromMidnight
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = normalized / 60
        components.minute = normalized % 60
        components.second = 0
        guard let today = calendar.date(from: components) else { return nil }
        return minutesFromMidnight >= 24 * 60 ? calendar.date(byAdding: .day, value: 1, to: today) : today
    }

    private func defaultBedtime(now: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 23
        components.minute = 30
        components.second = 0
        return calendar.date(from: components)
    }

    private func stageMinutes(named name: String, in stages: [SleepStage]) -> Int {
        stages.reduce(0) { partialResult, stage in
            guard canonicalSleepStageName(stage.stage) == name else { return partialResult }
            return partialResult + max(0, stage.duration)
        }
    }

    private func canonicalSleepStageName(_ stage: String) -> String {
        if stage.contains("清醒") || stage.caseInsensitiveCompare("Awake") == .orderedSame {
            return "Awake"
        }
        if stage.contains("深") || stage.caseInsensitiveCompare("Deep") == .orderedSame {
            return "Deep"
        }
        if stage.contains("快速") || stage.caseInsensitiveCompare("REM") == .orderedSame {
            return "REM"
        }
        return "Core"
    }

    private func shortTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private enum SleepRhythmAwakeRisk {
    case unknown
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .unknown:
            return String(localized: "待观察")
        case .low:
            return String(localized: "较低")
        case .medium:
            return String(localized: "中等")
        case .high:
            return String(localized: "偏高")
        }
    }

    var scorePenalty: Int {
        switch self {
        case .unknown:
            return 0
        case .low:
            return 0
        case .medium:
            return 7
        case .high:
            return 15
        }
    }

    var days: Int {
        switch self {
        case .unknown, .low:
            return 2
        case .medium:
            return 3
        case .high:
            return 5
        }
    }

    func summary(lateNightCount: Int) -> String {
        switch self {
        case .unknown:
            return lateNightCount > 0 ? "最近有晚睡迹象，今晚先从提前收尾开始。" : "夜醒样本还不完整，先用保守流程稳住今晚。"
        case .low:
            return lateNightCount > 0 ? "夜醒压力不高，重点是别让晚睡连续化。" : "昨夜连续性不错，今晚继续守住同一入睡窗口。"
        case .medium:
            return String(localized: "昨夜有一定夜醒或清醒占比，今晚优先降低睡前刺激，别额外压缩前半夜。")
        case .high:
            return String(localized: "夜间中断偏明显，今晚先做低刺激纠偏，训练和咖啡因都适合放轻。")
        }
    }
}
