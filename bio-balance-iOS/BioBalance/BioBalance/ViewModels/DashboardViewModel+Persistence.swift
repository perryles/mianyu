import Foundation
import SwiftUI
import HealthKit
import WidgetKit
import OSLog


/// DashboardViewModel Widget / Watch 持久化链路。
/// 从原 DashboardViewModel.swift 拆出，对外接口不变。

@MainActor
extension DashboardViewModel {

    func persistForWidgets(
        _ data: RealtimeHealth,
        syncToHealthDataManager: Bool = true
    ) {
        guard shouldPersistWidgetSnapshot(for: data) else { return }
        let trend = history?.stressPoints.suffix(2).map(\.value) ?? []
        let trendLabel: String
        if trend.count == 2 {
            trendLabel = trend[1] > trend[0] ? "Increasing" : (trend[1] < trend[0] ? "Decreasing" : "Stable")
        } else {
            trendLabel = "Stable"
        }
        AppGroupManager.shared.saveHeartRate(Double(data.bpm))
        AppGroupManager.shared.saveHRV(data.hrv)
        AppGroupManager.shared.saveStress(currentStressAssessment.score.map(Double.init), trend: trendLabel)
        let context = HealthAIContextBuilder().makeContext(
            assessment: dailyStressAssessment,
            realtimeHealth: realtimeHealth,
            restingHeartRate: restingHeartRate,
            avgHrvToday: avgHrvToday,
            recentAvgHrv: recentAvgHrv,
            recentAvgRestingHeartRate: recentAvgRestingHeartRate,
            sleepData: nil,
            sleepInterval: nil,
            nightlyHrv: nil,
            nightlyRespiratoryRate: nil,
            sleepingWristTemperature: nil,
            sedentaryState: sedentaryState,
            sedentarySummary: sedentaryTodaySummary,
            activityPoints: todayActivityPoints,
            walkingSpeedMpsToday: todayWalkingSpeedMps,
            waterMlToday: AppGroupManager.shared.getWaterIntakeMl().map { Int($0.rounded()) },
            caffeineConsumedTodayMg: nil,
            daylightMinutesToday: AppGroupManager.shared.getValue(forKey: AppGroupManager.Keys.sunlightMinutesToday)
        )
        if let script = context.recoveryScriptPlan {
            AppGroupManager.shared.saveHealthSummary(script.widgetSummary)
        } else if let vo2MaxAssessment {
            AppGroupManager.shared.saveVO2Summary(
                value: vo2MaxAssessment.value,
                confidence: vo2MaxAssessment.confidence,
                trend: vo2MaxAssessment.trend.rawValue,
                fitnessLevel: vo2MaxAssessment.fitnessLevel.title,
                source: vo2MaxAssessment.source.rawValue,
                driverSummary: vo2MaxAssessment.drivers.first?.explanation
            )
            AppGroupManager.shared.saveHealthSummary(vo2MaxAssessment.summaryText)
        }
        persistStressHistoryForWatch(realtime: data)
        WidgetRefreshCoordinator.refresh([.overall, .stress, .vitals, .complication], reason: .healthUpdate)
        if syncToHealthDataManager {
            HealthDataManager.shared.pushRealtimeToWatch(data)
        }
    }

    func applyVO2Assessments(_ assessments: [VO2MaxDailyAssessment], on referenceDate: Date) {
        let weeklyCandidates = VO2MaxRules.assessmentsInDashboardRollingWeek(
            onOrBefore: referenceDate,
            in: assessments
        )
        let selectedAssessment = weeklyCandidates.last
        vo2MaxHistory = assessments
        vo2MaxAssessment = selectedAssessment
        vo2Max = vo2MaxAssessment?.value
        recentAvgVo2Max = Self.recentMeasuredVO2Average(
            before: vo2MaxAssessment,
            in: assessments
        )
        vo2MaxIsEstimated = vo2MaxAssessment?.source == .engineEstimated
        let source = selectedAssessment?.source.rawValue ?? "none"
        let selectedAgeDays = selectedAssessment.map {
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: $0.date),
                to: Calendar.current.startOfDay(for: referenceDate)
            ).day ?? -1
        } ?? -1
        Self.signalsLogger.info(
            "[Today][VO2Max] operation=applyWeekly windowDays=\(VO2MaxRules.dashboardRollingWindowDays, privacy: .public) assessmentCount=\(assessments.count, privacy: .public) weeklyCandidateCount=\(weeklyCandidates.count, privacy: .public) selected=\(selectedAssessment != nil, privacy: .public) selectedAgeDays=\(selectedAgeDays, privacy: .public) source=\(source, privacy: .public)"
        )
    }

    static func recentMeasuredVO2Average(
        before current: VO2MaxDailyAssessment?,
        in assessments: [VO2MaxDailyAssessment],
        calendar: Calendar = .current
    ) -> Double? {
        guard let current else { return nil }
        let currentDay = calendar.startOfDay(for: current.date)
        let measuredValues = assessments.compactMap { assessment -> Double? in
            guard assessment.date < currentDay, assessment.value > 0 else { return nil }
            switch assessment.source {
            case .healthKitActual, .engineBlended:
                return assessment.value
            case .engineEstimated:
                return nil
            }
        }
        return averagePositive(measuredValues)
    }

    func resolvedVO2Assessments(days: Int, endDate: Date) async -> [VO2MaxDailyAssessment] {
        let assessments = await VO2MaxEngine.shared.assessSeries(days: days, endDate: endDate)
        Self.signalsLogger.info(
            "[Today][VO2Max] operation=resolveAssessments requestedDays=\(days, privacy: .public) assessmentCount=\(assessments.count, privacy: .public)"
        )
        return assessments
    }

    func persistStressHistoryForWatch(realtime: RealtimeHealth? = nil) {
        let calendar = Calendar.current
        let now = Date()
        let todayPoints = (history?.stressPoints ?? [])
            .filter { calendar.isDate($0.date, inSameDayAs: now) && $0.value > 0 }
            .sorted { $0.timestamp < $1.timestamp }

        var watchPoints = todayPoints.map {
            WatchStressHistoryPoint(
                timestamp: Int($0.timestamp),
                value: max(0, min(100, $0.value))
            )
        }

        let currentRealtime = realtime ?? realtimeHealth
        if let currentRealtime, currentRealtime.stress_value > 0 {
            let currentPoint = WatchStressHistoryPoint(
                timestamp: Int(currentRealtime.timestamp),
                value: max(0, min(100, currentRealtime.stress_value))
            )
            if let last = watchPoints.last {
                if abs(last.timestamp - currentPoint.timestamp) > 300 || last.value != currentPoint.value {
                    watchPoints.append(currentPoint)
                }
            } else {
                watchPoints.append(currentPoint)
            }
        }

        AppGroupManager.shared.saveStressHistory(Array(watchPoints.suffix(96)))
    }

    /// PEN-3 P0-1：对 Widget / Watch 持久化链路做节流合并。
    /// 至少间隔 10s 才允许一次全量持久化；窗口内仅当实时数据发生有意义变化
    /// （压力 ±3 / 心率 ±5 BPM / HRV ±1ms）时提前刷新，避免每秒重复重活。
    private func shouldPersistWidgetSnapshot(for data: RealtimeHealth) -> Bool {
        let now = Date()
        if let lastAt = lastWidgetPersistAt,
           now.timeIntervalSince(lastAt) < Self.widgetPersistMinInterval {
            guard let last = lastWidgetPersistedRealtime else { return false }
            let meaningfulChange =
                abs(last.stress_value - data.stress_value) >= 3
                || abs(last.bpm - data.bpm) >= 5
                || abs(last.hrv - data.hrv) >= 1
            if meaningfulChange {
                lastWidgetPersistAt = now
                lastWidgetPersistedRealtime = data
            }
            return meaningfulChange
        }
        lastWidgetPersistAt = now
        lastWidgetPersistedRealtime = data
        return true
    }
}
