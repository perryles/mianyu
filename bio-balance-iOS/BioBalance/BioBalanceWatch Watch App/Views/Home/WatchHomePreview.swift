import SwiftUI

// MARK: - 首页预览

#Preview("Recovery") {
    WatchHomePreviewContainer(snapshot: .previewRecovery, isReachable: true)
}

#Preview("High Stress") {
    WatchHomePreviewContainer(snapshot: .previewHighStress, isReachable: true)
}

#Preview("Waiting") {
    WatchHomePreviewContainer(snapshot: nil, isReachable: false)
}

// MARK: - 组件预览

#Preview("Vitals Dial") {
    WatchVitalsDialView(snapshot: .previewRecovery)
        .padding()
}

#Preview("Mascot - Joey") {
    WatchAnimatedMascotView(
        themeId: "joey",
        hrv: 56,
        stressValue: 24,
        stressState: "recovery",
        accent: Color(hex: "68D4A2")
    )
}

#Preview("Mascot - Tiger") {
    WatchAnimatedMascotView(
        themeId: "tiger",
        hrv: 22,
        stressValue: 76,
        stressState: "highStress",
        accent: Color(hex: "FFD85E")
    )
}

// MARK: - 预览容器

private struct WatchHomePreviewContainer: View {
    let snapshot: WatchRealtimeHealth?
    let isReachable: Bool
    @State private var swimmingWorkoutManager = SwimmingWorkoutManager()

    var body: some View {
        NavigationStack {
            WatchHomeView(
                hrManager: WatchHeartRateManager(),
                receiver: previewReceiver,
                swimmingWorkoutManager: swimmingWorkoutManager
            )
        }
    }

    private var previewReceiver: WatchConnectivityReceiver {
        let receiver = WatchConnectivityReceiver.shared
        receiver.latest = snapshot
        receiver.isReachable = isReachable
        receiver.lastSyncDate = snapshot == nil ? nil : Date()
        return receiver
    }
}

// MARK: - 预览数据

private extension WatchRealtimeHealth {
    static let previewRecovery = WatchRealtimeHealth(
        bpm: 68,
        hrv: 56,
        stress_value: 24,
        stressState: "recovery",
        stressExplanationCode: "hrv_below_baseline",
        stressConfidence: 0.84,
        stressTrend: "下降",
        timestamp: Int(Date().timeIntervalSince1970),
        steps: 6380,
        activeEnergy: 420,
        exerciseMinutes: 21,
        standHours: 8,
        walkingSpeedMps: 1.29,
        walkingPaceSecondsPerKm: 775,
        stepsGoal: 8000,
        activeEnergyGoal: 500,
        exerciseMinutesGoal: 30,
        standHoursGoal: 12,
        sleepDurationMinutes: 456,
        sleepScore: 84,
        lateNightRecoveryPrompt: nil,
        lateNightRecoverySeverity: nil,
        sleepEnvironmentCompletionRate: 0.78,
        sleepEnvironmentPrompt: "今晚继续保留低光和安静环境。",
        recoveryPlan: WatchRecoveryPlanSnapshot(
            planID: "preview-recovery-plan",
            dayStart: Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970),
            actions: [
                WatchRecoveryActionSnapshot(
                    actionID: "preview-main-rhythm",
                    title: "稳住全天节律",
                    role: .main,
                    state: .pending
                ),
                WatchRecoveryActionSnapshot(
                    actionID: "preview-support-water",
                    title: "补一杯水",
                    role: .supporting,
                    state: .completed
                ),
                WatchRecoveryActionSnapshot(
                    actionID: "preview-support-walk",
                    title: "午后轻走 5 分钟",
                    role: .supporting,
                    state: .pending
                )
            ]
        ),
        waterIntakeMl: 1400,
        waterTargetMl: 2000,
        waterCompletionRate: 0.7,
        caffeineRemainedMg: 60,
        sedentaryElapsedMinutes: 32,
        sedentaryIsCounting: true,
        sedentaryPausedBySleep: false,
        sedentarySeatedStartAt: 0,
        sedentaryLastActivityAt: 0,
        sedentaryUpdatedAt: Int(Date().timeIntervalSince1970),
        sedentaryBreakIsActive: false,
        sedentaryBreakDurationMinutes: 0,
        sedentaryBreakStartedAt: 0,
        periodPhase: nil,
        periodCycleDay: nil,
        periodIsFertile: false,
        periodNextStart: nil,
        periodFertileStart: nil,
        periodFertileEnd: nil,
        periodPredictionSource: nil,
        defaultComplicationTemplate: "overview",
        watchThemeId: "joey",
        bodyAgeValueYears: 27.4,
        bodyAgeStatusText: "年轻于实际年龄",
        bodyAgeComparisonText: "恢复和睡眠表现正在拉低身体年龄。",
        bodyAgeSuggestionText: "继续保持睡眠和白天活动节奏。",
        bodyAgeCoverageText: "覆盖度 82%",
        bodyAgeDirectionText: "近 2 周回升",
        vo2MaxValue: 44.1,
        vo2MaxConfidence: 83,
        vo2MaxTrend: "improving",
        vo2MaxFitnessLevel: "Good",
        vo2MaxSource: "engineEstimated",
        vo2MaxDriverSummary: "最近跑步配速与心率配合更高效",
        stressHistory: [],
        sleepMonitoringPhase: SleepMonitoringPhase.surfaced.rawValue,
        sleepMonitoringActive: false,
        sleepSnoreIntensity: SleepSnoreIntensity.low.rawValue,
        sleepSnoreDurationMinutes: 12,
        sleepInsightHeadline: "昨夜恢复较稳",
        sleepWatchConfidence: 0.72
    )

    static let previewHighStress = WatchRealtimeHealth(
        bpm: 94,
        hrv: 22,
        stress_value: 76,
        stressState: "highStress",
        stressExplanationCode: "recovery_debt_elevated",
        stressConfidence: 0.88,
        stressTrend: "上升",
        timestamp: Int(Date().timeIntervalSince1970),
        steps: 2410,
        activeEnergy: 160,
        exerciseMinutes: 8,
        standHours: 4,
        walkingSpeedMps: 0.86,
        walkingPaceSecondsPerKm: 1163,
        stepsGoal: 8000,
        activeEnergyGoal: 500,
        exerciseMinutesGoal: 30,
        standHoursGoal: 12,
        sleepDurationMinutes: 322,
        sleepScore: 61,
        lateNightRecoveryPrompt: "午后不要补咖啡，今晚提前收尾。",
        lateNightRecoverySeverity: "moderate",
        sleepEnvironmentCompletionRate: 0.32,
        sleepEnvironmentPrompt: "今晚先完成环境清单。",
        recoveryPlan: WatchRecoveryPlanSnapshot(
            planID: "preview-protection-plan",
            dayStart: Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970),
            actions: [
                WatchRecoveryActionSnapshot(
                    actionID: "preview-main-load",
                    title: "先降负荷",
                    role: .main,
                    state: .completed
                ),
                WatchRecoveryActionSnapshot(
                    actionID: "preview-support-break",
                    title: "起身放松 3 分钟",
                    role: .supporting,
                    state: .pending
                ),
                WatchRecoveryActionSnapshot(
                    actionID: "preview-support-close",
                    title: "今晚提前收尾",
                    role: .supporting,
                    state: .snoozed
                )
            ]
        ),
        waterIntakeMl: 700,
        waterTargetMl: 2000,
        waterCompletionRate: 0.35,
        caffeineRemainedMg: 20,
        sedentaryElapsedMinutes: 74,
        sedentaryIsCounting: true,
        sedentaryPausedBySleep: false,
        sedentarySeatedStartAt: 0,
        sedentaryLastActivityAt: 0,
        sedentaryUpdatedAt: Int(Date().timeIntervalSince1970),
        sedentaryBreakIsActive: false,
        sedentaryBreakDurationMinutes: 0,
        sedentaryBreakStartedAt: 0,
        periodPhase: nil,
        periodCycleDay: nil,
        periodIsFertile: false,
        periodNextStart: nil,
        periodFertileStart: nil,
        periodFertileEnd: nil,
        periodPredictionSource: nil,
        defaultComplicationTemplate: "recovery",
        watchThemeId: "tiger",
        bodyAgeValueYears: nil,
        bodyAgeStatusText: nil,
        bodyAgeComparisonText: nil,
        bodyAgeSuggestionText: nil,
        bodyAgeCoverageText: nil,
        bodyAgeDirectionText: nil,
        vo2MaxValue: 39.2,
        vo2MaxConfidence: 58,
        vo2MaxTrend: "stable",
        vo2MaxFitnessLevel: "Average",
        vo2MaxSource: "engineEstimated",
        vo2MaxDriverSummary: "近几天恢复偏弱，系统对上行保持保守",
        stressHistory: [],
        sleepMonitoringPhase: SleepMonitoringPhase.monitoring.rawValue,
        sleepMonitoringActive: true,
        sleepSnoreIntensity: SleepSnoreIntensity.medium.rawValue,
        sleepSnoreDurationMinutes: 24,
        sleepInsightHeadline: "iPhone 正在分析昨夜声音摘要",
        sleepWatchConfidence: 0.81
    )
}
