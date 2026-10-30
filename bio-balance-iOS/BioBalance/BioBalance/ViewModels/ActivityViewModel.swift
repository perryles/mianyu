import Foundation
import HealthKit

/// 健康数据Missing原因枚举 作为视图模型层里的状态与分类定义。
/// 负责描述界面状态管理与业务编排过程中会用到的状态、分类或分支。
nonisolated enum HealthDataMissingReason: Equatable {
    case notAuthorized
    case noData
}

/// Activity视图模型 作为视图模型层里的界面状态管理入口。
/// 负责界面状态管理与业务编排。
@MainActor
@Observable
class ActivityViewModel {
    var activityData: ActivityData?
    var isLoading: Bool = false
    var missingReason: HealthDataMissingReason?
    var lastUpdatedAt: Date?
    var dailySteps: [TimeSeriesPointDouble] = []
    var dailyActiveEnergy: [TimeSeriesPointDouble] = []
    var dailyExerciseMinutes: [TimeSeriesPointDouble] = []
    var dailyStandHours: [TimeSeriesPointDouble] = []
    var dailyWalkingSpeed: [TimeSeriesPointDouble] = []
    
    func loadData() {
        isLoading = true
        
        Task {
            let hk = HealthKitManager.shared
            // authorizationStatus(for:) 只表示写入权限，不能用于判断这些只读指标。
            // 一次性授权模式下，以完整授权集合是否仍需展示系统弹窗作为唯一可知信号。
            let needsAuth = await hk.fullAuthorizationRequestStatus() == .shouldRequest

            let fetchedSteps = try? await hk.fetchStepsCountOptional()
            let fetchedActiveEnergy = try? await hk.fetchActiveEnergyBurnedOptional()
            let fetchedExerciseTime = try? await hk.fetchExerciseTimeOptional()
            let fetchedStandHours = try? await hk.fetchStandHoursOptional()
            let fetchedWalkingSpeed = try? await hk.fetchAverageWalkingSpeedToday()
            let fetchedEnvironmentalDb = try? await hk.fetchEnvironmentalAudioExposure()
            let fetchedHeadphoneDb = try? await hk.fetchHeadphoneAudioExposureToday()
            async let stepSeries = try? hk.fetchDailyStepSums(days: 30)
            async let energySeries = try? hk.fetchDailyActiveEnergySums(days: 30)
            async let exerciseSeries = try? hk.fetchDailyExerciseTimeSums(days: 30)
            async let standSeries = try? hk.fetchDailyStandHours(days: 30)
            async let walkingSpeedSeries = try? hk.fetchDailyWalkingSpeedAverages(days: 30)
            
            let steps = fetchedSteps ?? 0
            let activeEnergy = fetchedActiveEnergy ?? 0
            let exerciseTime = fetchedExerciseTime ?? 0
            let standHours = fetchedStandHours ?? 0
            
            self.activityData = ActivityData(
                steps: steps,
                active_energy: activeEnergy,
                exercise_time: exerciseTime,
                stand_hours: standHours,
                walking_speed_mps: fetchedWalkingSpeed ?? nil,
                environmental_audio_exposure_db: fetchedEnvironmentalDb ?? nil,
                headphone_audio_exposure_db: fetchedHeadphoneDb ?? nil
            )
            self.dailySteps = (await stepSeries) ?? []
            self.dailyActiveEnergy = (await energySeries) ?? []
            self.dailyExerciseMinutes = (await exerciseSeries) ?? []
            self.dailyStandHours = (await standSeries) ?? []
            self.dailyWalkingSpeed = (await walkingSpeedSeries) ?? []

            let hasAnyData = !(fetchedSteps == nil && fetchedActiveEnergy == nil && fetchedExerciseTime == nil && fetchedStandHours == nil && fetchedWalkingSpeed == nil && fetchedEnvironmentalDb == nil && fetchedHeadphoneDb == nil) ||
                !self.dailySteps.isEmpty ||
                !self.dailyActiveEnergy.isEmpty ||
                !self.dailyExerciseMinutes.isEmpty ||
                !self.dailyStandHours.isEmpty ||
                !self.dailyWalkingSpeed.isEmpty
            self.missingReason = Self.resolveMissingReason(needsAuth: needsAuth, hasAnyData: hasAnyData)
            self.lastUpdatedAt = Date()
            
            let resolvedExerciseGoal = UserDefaults.standard.integer(forKey: "onboarding_goal_exerciseMinutes")
            let resolvedStandGoal = UserDefaults.standard.integer(forKey: "onboarding_goal_standHours")
            AppGroupManager.shared.saveActivitySummary(
                steps: fetchedSteps,
                activeEnergy: fetchedActiveEnergy,
                exerciseMinutes: fetchedExerciseTime,
                standHours: fetchedStandHours,
                exerciseMinutesGoal: resolvedExerciseGoal > 0 ? resolvedExerciseGoal : nil,
                standHoursGoal: resolvedStandGoal > 0 ? resolvedStandGoal : nil
            )
            WidgetRefreshCoordinator.refresh([.overall, .activity, .activityConfigurable], reason: .healthUpdate)
            
            self.isLoading = false
        }
    }

    nonisolated static func resolveMissingReason(needsAuth: Bool, hasAnyData: Bool) -> HealthDataMissingReason? {
        if needsAuth { return .notAuthorized }
        if !hasAnyData { return .noData }
        return nil
    }
}
