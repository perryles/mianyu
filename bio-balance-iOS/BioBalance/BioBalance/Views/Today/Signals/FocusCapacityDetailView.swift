import SwiftUI

/// 今日页「专注能力」的独立二级页面入口。
struct FocusCapacityDetailView: View {
    let assessment: StressPresentationAssessment
    let focusAssessment: StressFocusCapacityAssessment
    let history: HealthHistory?
    let recentAvgHrv: Double?
    let restingHeartRate: Double?
    let recentAvgRestingHeartRate: Double?
    let bodyBatteryValue: Int?
    let trendSnapshot: StressFocusCapacityTrendSnapshot
    let initialDate: Date
    var showsDismissButton = false

    var body: some View {
        BodySignalDetailContentView(
            detail: .focusCapacity,
            assessment: assessment,
            focusCapacityAssessment: focusAssessment,
            history: history,
            recentAvgHrv: recentAvgHrv,
            restingHeartRate: restingHeartRate,
            recentAvgRestingHeartRate: recentAvgRestingHeartRate,
            bodyBatteryRecoveryScore: nil,
            bodyBatteryRecoveryInput: nil,
            bodyBatteryWakeDate: nil,
            bodyBatteryCurrentValue: bodyBatteryValue,
            bodyBatteryLoadInput: .empty,
            bodyBatteryTrendPoints: [],
            heartRhythmResult: .unavailable,
            focusCapacityTrendSnapshot: trendSnapshot,
            initialDate: initialDate,
            showsDismissButton: showsDismissButton
        )
    }
}
