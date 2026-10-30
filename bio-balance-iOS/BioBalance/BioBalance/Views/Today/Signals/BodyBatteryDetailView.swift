import SwiftUI

/// 今日页「身体电量」的独立二级页面入口。
struct BodyBatteryDetailView: View {
    let assessment: StressPresentationAssessment
    let history: HealthHistory?
    let recentAvgHrv: Double?
    let restingHeartRate: Double?
    let recentAvgRestingHeartRate: Double?
    let recoveryScore: Int?
    let recoveryInput: StressBodyBatteryRecoveryInput?
    let wakeDate: Date?
    let currentValue: Int?
    let loadInput: StressBodyBatteryLoadInput
    let trendPoints: [TimeSeriesPoint]
    let heartRhythmResult: HeartRhythmStabilityResult
    let initialDate: Date
    var showsDismissButton = false

    var body: some View {
        BodySignalDetailContentView(
            detail: .bodyBattery,
            assessment: assessment,
            focusCapacityAssessment: unavailableFocusAssessment,
            history: history,
            recentAvgHrv: recentAvgHrv,
            restingHeartRate: restingHeartRate,
            recentAvgRestingHeartRate: recentAvgRestingHeartRate,
            bodyBatteryRecoveryScore: recoveryScore,
            bodyBatteryRecoveryInput: recoveryInput,
            bodyBatteryWakeDate: wakeDate,
            bodyBatteryCurrentValue: currentValue,
            bodyBatteryLoadInput: loadInput,
            bodyBatteryTrendPoints: trendPoints,
            heartRhythmResult: heartRhythmResult,
            focusCapacityTrendSnapshot: unavailableFocusTrend,
            initialDate: initialDate,
            showsDismissButton: showsDismissButton
        )
    }

    private var unavailableFocusAssessment: StressFocusCapacityAssessment {
        StressFocusCapacityEngine.evaluate(input: StressFocusCapacityInput(
            now: initialDate,
            stressScore: nil,
            bodyBatteryScore: currentValue,
            stressConfidence: nil,
            stressQuality: .low
        ))
    }

    private var unavailableFocusTrend: StressFocusCapacityTrendSnapshot {
        StressFocusCapacityTrendSnapshot(
            assessment: unavailableFocusAssessment,
            stressPoints: [],
            now: initialDate
        )
    }
}
