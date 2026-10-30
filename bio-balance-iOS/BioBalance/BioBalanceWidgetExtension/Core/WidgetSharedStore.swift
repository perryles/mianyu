import Foundation
import WidgetKit

enum WidgetSharedKeys {
    static let latestHeartRate = AppGroupSchema.Keys.latestHeartRate
    static let latestHRV = AppGroupSchema.Keys.latestHRV
    static let latestStress = AppGroupSchema.Keys.latestStress
    static let stressTrend = AppGroupSchema.Keys.stressTrend
    static let stressHistoryData = AppGroupSchema.Keys.stressHistoryData
    static let lastSyncTime = AppGroupSchema.Keys.lastSyncTime
    static let waterIntakeMl = AppGroupSchema.Keys.waterIntakeMl
    static let waterTargetMl = AppGroupSchema.Keys.waterTargetMl
    static let waterCompletionRate = AppGroupSchema.Keys.waterCompletionRate
    static let caffeineRemainedMg = AppGroupSchema.Keys.caffeineRemainedMg
    static let steps = AppGroupSchema.Keys.steps
    static let stepsGoal = AppGroupSchema.Keys.stepsGoal
    static let activeEnergy = AppGroupSchema.Keys.activeEnergy
    static let activeEnergyGoal = AppGroupSchema.Keys.activeEnergyGoal
    static let exerciseMinutes = AppGroupSchema.Keys.exerciseMinutes
    static let exerciseMinutesGoal = AppGroupSchema.Keys.exerciseMinutesGoal
    static let standHours = AppGroupSchema.Keys.standHours
    static let standHoursGoal = AppGroupSchema.Keys.standHoursGoal
    static let sleepDurationMinutes = AppGroupSchema.Keys.sleepDurationMinutes
    static let sleepScore = AppGroupSchema.Keys.sleepScore
    static let sleepGoalMinutes = AppGroupSchema.Keys.sleepGoalMinutes
    static let lateNightRecoveryPrompt = AppGroupSchema.Keys.lateNightRecoveryPrompt
    static let lateNightRecoverySeverity = AppGroupSchema.Keys.lateNightRecoverySeverity
    static let sleepEnvironmentCompletionRate = AppGroupSchema.Keys.sleepEnvironmentCompletionRate
    static let sleepEnvironmentPrompt = AppGroupSchema.Keys.sleepEnvironmentPrompt
    static let stepsCompletionRate = AppGroupSchema.Keys.stepsCompletionRate
    static let activeEnergyCompletionRate = AppGroupSchema.Keys.activeEnergyCompletionRate
    static let exerciseMinutesCompletionRate = AppGroupSchema.Keys.exerciseMinutesCompletionRate
    static let standHoursCompletionRate = AppGroupSchema.Keys.standHoursCompletionRate
    static let sleepDurationCompletionRate = AppGroupSchema.Keys.sleepDurationCompletionRate
    static let activityCompletionRate = AppGroupSchema.Keys.activityCompletionRate
    static let walkingSpeedMps = AppGroupSchema.Keys.walkingSpeedMps
    static let walkingPaceSecondsPerKm = AppGroupSchema.Keys.walkingPaceSecondsPerKm
    static let healthSummary = AppGroupSchema.Keys.healthSummary
    static let sedentaryElapsedMinutes = AppGroupSchema.Keys.sedentaryElapsedMinutes
    static let sedentaryIsCounting = AppGroupSchema.Keys.sedentaryIsCounting
    static let bodyAgeValueYears = AppGroupSchema.Keys.bodyAgeValueYears
    static let bodyAgeStatusText = AppGroupSchema.Keys.bodyAgeStatusText
    static let widgetSnapshotV2 = AppGroupSchema.Keys.widgetSnapshotV2
}

struct WidgetStressHistoryPoint: Codable, Sendable, Hashable, Identifiable {
    let timestamp: Int
    let value: Int

    var id: Int { timestamp }
}

struct WidgetHealthSnapshot: Codable, Sendable, Hashable {
    struct MetricFreshness: Codable, Sendable, Hashable {
        var updatedAt: Date?
        var staleAfter: TimeInterval

        init(updatedAt: Date? = nil, staleAfter: TimeInterval = 6 * 60 * 60) {
            self.updatedAt = updatedAt
            self.staleAfter = staleAfter
        }

        func state(referenceDate: Date) -> WidgetDataState {
            guard let updatedAt else { return .missing }
            return referenceDate.timeIntervalSince(updatedAt) > staleAfter ? .stale : .fresh
        }
    }

    struct Vitals: Codable, Sendable, Hashable {
        var heartRate: Double?
        var hrv: Double?
        var stress: Double?
        var stressState: String?
        var stressQuality: String?
        var stressAlgorithmVersion: String?
        var dailyStress: Double?
        var dailyStressQuality: String?
        var dailyStressAlgorithmVersion: String?
        var stressTrend: String?
        var stressHistory: [WidgetStressHistoryPoint]
        var freshness: MetricFreshness
        var recoveryScore: Int?
        var recoveryStatus: String?
        var recoveryTrend: String?
        var restingHeartRate: Double?
        var respirationRate: Double?
        var wristTemperatureDelta: Double?

        init(
            heartRate: Double? = nil,
            hrv: Double? = nil,
            stress: Double? = nil,
            stressState: String? = nil,
            stressQuality: String? = nil,
            stressAlgorithmVersion: String? = nil,
            dailyStress: Double? = nil,
            dailyStressQuality: String? = nil,
            dailyStressAlgorithmVersion: String? = nil,
            stressTrend: String? = nil,
            stressHistory: [WidgetStressHistoryPoint] = [],
            freshness: MetricFreshness = .init(),
            recoveryScore: Int? = nil,
            recoveryStatus: String? = nil,
            recoveryTrend: String? = nil,
            restingHeartRate: Double? = nil,
            respirationRate: Double? = nil,
            wristTemperatureDelta: Double? = nil
        ) {
            self.heartRate = heartRate
            self.hrv = hrv
            self.stress = stress
            self.stressState = stressState
            self.stressQuality = stressQuality
            self.stressAlgorithmVersion = stressAlgorithmVersion
            self.dailyStress = dailyStress
            self.dailyStressQuality = dailyStressQuality
            self.dailyStressAlgorithmVersion = dailyStressAlgorithmVersion
            self.stressTrend = stressTrend
            self.stressHistory = stressHistory
            self.freshness = freshness
            self.recoveryScore = recoveryScore
            self.recoveryStatus = recoveryStatus
            self.recoveryTrend = recoveryTrend
            self.restingHeartRate = restingHeartRate
            self.respirationRate = respirationRate
            self.wristTemperatureDelta = wristTemperatureDelta
        }
    }

    struct Hydration: Codable, Sendable, Hashable {
        var waterIntakeMl: Double?
        var waterTargetMl: Int?
        var waterCompletionRate: Double?
        var caffeineRemainedMg: Double?
        var freshness: MetricFreshness

        init(
            waterIntakeMl: Double? = nil,
            waterTargetMl: Int? = nil,
            waterCompletionRate: Double? = nil,
            caffeineRemainedMg: Double? = nil,
            freshness: MetricFreshness = .init()
        ) {
            self.waterIntakeMl = waterIntakeMl
            self.waterTargetMl = waterTargetMl
            self.waterCompletionRate = waterCompletionRate
            self.caffeineRemainedMg = caffeineRemainedMg
            self.freshness = freshness
        }
    }

    struct Activity: Codable, Sendable, Hashable {
        var steps: Int?
        var stepsGoal: Int?
        var activeEnergy: Int?
        var activeEnergyGoal: Int?
        var exerciseMinutes: Int?
        var exerciseMinutesGoal: Int?
        var standHours: Int?
        var standHoursGoal: Int?
        var stepsCompletionRate: Double?
        var activeEnergyCompletionRate: Double?
        var exerciseMinutesCompletionRate: Double?
        var standHoursCompletionRate: Double?
        var activityCompletionRate: Double?
        var walkingSpeedMps: Double?
        var walkingPaceSecondsPerKm: Int?
        var sedentaryElapsedMinutes: Int?
        var sedentaryIsCounting: Bool?
        var freshness: MetricFreshness

        init(
            steps: Int? = nil,
            stepsGoal: Int? = nil,
            activeEnergy: Int? = nil,
            activeEnergyGoal: Int? = nil,
            exerciseMinutes: Int? = nil,
            exerciseMinutesGoal: Int? = nil,
            standHours: Int? = nil,
            standHoursGoal: Int? = nil,
            stepsCompletionRate: Double? = nil,
            activeEnergyCompletionRate: Double? = nil,
            exerciseMinutesCompletionRate: Double? = nil,
            standHoursCompletionRate: Double? = nil,
            activityCompletionRate: Double? = nil,
            walkingSpeedMps: Double? = nil,
            walkingPaceSecondsPerKm: Int? = nil,
            sedentaryElapsedMinutes: Int? = nil,
            sedentaryIsCounting: Bool? = nil,
            freshness: MetricFreshness = .init()
        ) {
            self.steps = steps
            self.stepsGoal = stepsGoal
            self.activeEnergy = activeEnergy
            self.activeEnergyGoal = activeEnergyGoal
            self.exerciseMinutes = exerciseMinutes
            self.exerciseMinutesGoal = exerciseMinutesGoal
            self.standHours = standHours
            self.standHoursGoal = standHoursGoal
            self.stepsCompletionRate = stepsCompletionRate
            self.activeEnergyCompletionRate = activeEnergyCompletionRate
            self.exerciseMinutesCompletionRate = exerciseMinutesCompletionRate
            self.standHoursCompletionRate = standHoursCompletionRate
            self.activityCompletionRate = activityCompletionRate
            self.walkingSpeedMps = walkingSpeedMps
            self.walkingPaceSecondsPerKm = walkingPaceSecondsPerKm
            self.sedentaryElapsedMinutes = sedentaryElapsedMinutes
            self.sedentaryIsCounting = sedentaryIsCounting
            self.freshness = freshness
        }
    }

    struct Sleep: Codable, Sendable, Hashable {
        var durationMinutes: Int?
        var score: Int?
        var goalMinutes: Int?
        var completionRate: Double?
        var lateNightRecoveryPrompt: String?
        var lateNightRecoverySeverity: String?
        var environmentCompletionRate: Double?
        var environmentPrompt: String?
        var freshness: MetricFreshness

        init(
            durationMinutes: Int? = nil,
            score: Int? = nil,
            goalMinutes: Int? = nil,
            completionRate: Double? = nil,
            lateNightRecoveryPrompt: String? = nil,
            lateNightRecoverySeverity: String? = nil,
            environmentCompletionRate: Double? = nil,
            environmentPrompt: String? = nil,
            freshness: MetricFreshness = .init(staleAfter: 18 * 60 * 60)
        ) {
            self.durationMinutes = durationMinutes
            self.score = score
            self.goalMinutes = goalMinutes
            self.completionRate = completionRate
            self.lateNightRecoveryPrompt = lateNightRecoveryPrompt
            self.lateNightRecoverySeverity = lateNightRecoverySeverity
            self.environmentCompletionRate = environmentCompletionRate
            self.environmentPrompt = environmentPrompt
            self.freshness = freshness
        }
    }

    struct Summary: Codable, Sendable, Hashable {
        var healthSummary: String?
        var bodyAgeValueYears: Double?
        var bodyAgeStatusText: String?
        var vo2MaxValue: Double?
        var vo2MaxConfidence: Int?
        var vo2MaxTrend: String?
        var vo2MaxFitnessLevel: String?
        var vo2MaxSource: String?
        var vo2MaxDriverSummary: String?
        var freshness: MetricFreshness

        init(
            healthSummary: String? = nil,
            bodyAgeValueYears: Double? = nil,
            bodyAgeStatusText: String? = nil,
            vo2MaxValue: Double? = nil,
            vo2MaxConfidence: Int? = nil,
            vo2MaxTrend: String? = nil,
            vo2MaxFitnessLevel: String? = nil,
            vo2MaxSource: String? = nil,
            vo2MaxDriverSummary: String? = nil,
            freshness: MetricFreshness = .init()
        ) {
            self.healthSummary = healthSummary
            self.bodyAgeValueYears = bodyAgeValueYears
            self.bodyAgeStatusText = bodyAgeStatusText
            self.vo2MaxValue = vo2MaxValue
            self.vo2MaxConfidence = vo2MaxConfidence
            self.vo2MaxTrend = vo2MaxTrend
            self.vo2MaxFitnessLevel = vo2MaxFitnessLevel
            self.vo2MaxSource = vo2MaxSource
            self.vo2MaxDriverSummary = vo2MaxDriverSummary
            self.freshness = freshness
        }
    }

    struct Sunlight: Codable, Sendable, Hashable {
        var minutesToday: Int?
        var goalMinutes: Int?
        var completionRate: Double?
        var morningMinutes: Int?
        var afternoonMinutes: Int?
        var lastExposureAt: Date?
        var freshness: MetricFreshness

        init(
            minutesToday: Int? = nil,
            goalMinutes: Int? = nil,
            completionRate: Double? = nil,
            morningMinutes: Int? = nil,
            afternoonMinutes: Int? = nil,
            lastExposureAt: Date? = nil,
            freshness: MetricFreshness = .init(updatedAt: nil, staleAfter: 24 * 60 * 60)
        ) {
            self.minutesToday = minutesToday
            self.goalMinutes = goalMinutes
            self.completionRate = completionRate
            self.morningMinutes = morningMinutes
            self.afternoonMinutes = afternoonMinutes
            self.lastExposureAt = lastExposureAt
            self.freshness = freshness
        }
    }

    var schemaVersion: Int
    var generatedAt: Date
    var vitals: Vitals
    var hydration: Hydration
    var activity: Activity
    var sleep: Sleep
    var summary: Summary
    var sunlight: Sunlight
    var recoveryPlan: SharedWidgetRecoveryPlan?

    init(
        schemaVersion: Int = 2,
        generatedAt: Date = .now,
        vitals: Vitals = .init(),
        hydration: Hydration = .init(),
        activity: Activity = .init(),
        sleep: Sleep = .init(),
        summary: Summary = .init(),
        sunlight: Sunlight = .init(),
        recoveryPlan: SharedWidgetRecoveryPlan? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.vitals = vitals
        self.hydration = hydration
        self.activity = activity
        self.sleep = sleep
        self.summary = summary
        self.sunlight = sunlight
        self.recoveryPlan = recoveryPlan
    }

    var lastSyncTime: Date? {
        [
            vitals.freshness.updatedAt,
            hydration.freshness.updatedAt,
            activity.freshness.updatedAt,
            sleep.freshness.updatedAt,
            summary.freshness.updatedAt,
            recoveryPlan?.updatedAt
        ]
        .compactMap { $0 }
        .max()
    }

    var heartRate: Double? { vitals.heartRate }
    var hrv: Double? { vitals.hrv }
    var stress: Double? { vitals.stress }
    var stressState: String? { vitals.stressState }
    var stressQuality: String? { vitals.stressQuality }
    var stressAlgorithmVersion: String? { vitals.stressAlgorithmVersion }
    var dailyStress: Double? { vitals.dailyStress }
    var dailyStressQuality: String? { vitals.dailyStressQuality }
    var dailyStressAlgorithmVersion: String? { vitals.dailyStressAlgorithmVersion }
    var stressTrend: String? { vitals.stressTrend }
    var stressHistory: [WidgetStressHistoryPoint] { vitals.stressHistory }
    var waterIntakeMl: Double? { hydration.waterIntakeMl }
    var waterTargetMl: Int? { hydration.waterTargetMl }
    var waterCompletionRate: Double? { hydration.waterCompletionRate }
    var caffeineRemainedMg: Double? { hydration.caffeineRemainedMg }
    var steps: Int? { activity.steps }
    var stepsGoal: Int? { activity.stepsGoal }
    var activeEnergy: Int? { activity.activeEnergy }
    var activeEnergyGoal: Int? { activity.activeEnergyGoal }
    var exerciseMinutes: Int? { activity.exerciseMinutes }
    var exerciseMinutesGoal: Int? { activity.exerciseMinutesGoal }
    var standHours: Int? { activity.standHours }
    var standHoursGoal: Int? { activity.standHoursGoal }
    var sleepDurationMinutes: Int? { sleep.durationMinutes }
    var sleepScore: Int? { sleep.score }
    var sleepGoalMinutes: Int? { sleep.goalMinutes }
    var stepsCompletionRate: Double? { activity.stepsCompletionRate }
    var activeEnergyCompletionRate: Double? { activity.activeEnergyCompletionRate }
    var exerciseMinutesCompletionRate: Double? { activity.exerciseMinutesCompletionRate }
    var standHoursCompletionRate: Double? { activity.standHoursCompletionRate }
    var sleepDurationCompletionRate: Double? { sleep.completionRate }
    var activityCompletionRate: Double? { activity.activityCompletionRate }
    var walkingSpeedMps: Double? { activity.walkingSpeedMps }
    var walkingPaceSecondsPerKm: Int? { activity.walkingPaceSecondsPerKm }
    var healthSummary: String? { summary.healthSummary }
    var bodyAgeValueYears: Double? { summary.bodyAgeValueYears }
    var bodyAgeStatusText: String? { summary.bodyAgeStatusText }
    var vo2MaxValue: Double? { summary.vo2MaxValue }
    var vo2MaxConfidence: Int? { summary.vo2MaxConfidence }
    var vo2MaxTrend: String? { summary.vo2MaxTrend }
    var vo2MaxFitnessLevel: String? { summary.vo2MaxFitnessLevel }
    var vo2MaxSource: String? { summary.vo2MaxSource }
    var vo2MaxDriverSummary: String? { summary.vo2MaxDriverSummary }
    var sunlightMinutesToday: Int? { sunlight.minutesToday }
    var sunlightGoalMinutes: Int? { sunlight.goalMinutes }
    var sunlightCompletionRate: Double? { sunlight.completionRate }
    var sunlightMorningMinutes: Int? { sunlight.morningMinutes }
    var sunlightAfternoonMinutes: Int? { sunlight.afternoonMinutes }
    var sunlightLastExposureAt: Date? { sunlight.lastExposureAt }

    func dataState(referenceDate: Date) -> WidgetDataState {
        if recoveryPlan?.isValid(at: referenceDate) == true {
            return .fresh
        }
        let states = [
            vitals.freshness.state(referenceDate: referenceDate),
            hydration.freshness.state(referenceDate: referenceDate),
            activity.freshness.state(referenceDate: referenceDate),
            sleep.freshness.state(referenceDate: referenceDate),
            summary.freshness.state(referenceDate: referenceDate)
        ]

        if states.contains(.fresh) {
            return .fresh
        }
        if states.contains(.stale) {
            return .stale
        }
        return .missing
    }

    func isMetricFresh(_ metric: WidgetMetricDomain, referenceDate: Date) -> Bool {
        freshness(for: metric).state(referenceDate: referenceDate) == .fresh
    }

    func freshness(for metric: WidgetMetricDomain) -> MetricFreshness {
        switch metric {
        case .vitals:
            return vitals.freshness
        case .hydration:
            return hydration.freshness
        case .activity:
            return activity.freshness
        case .sleep:
            return sleep.freshness
        case .summary:
            return summary.freshness
        }
    }

    var isStale: Bool {
        dataState(referenceDate: generatedAt) == .stale
    }

    var hasAnyFreshMetric: Bool {
        if recoveryPlan?.isValid(at: generatedAt) == true {
            return true
        }
        return [
            vitals.freshness.state(referenceDate: generatedAt),
            hydration.freshness.state(referenceDate: generatedAt),
            activity.freshness.state(referenceDate: generatedAt),
            sleep.freshness.state(referenceDate: generatedAt),
            summary.freshness.state(referenceDate: generatedAt)
        ]
        .contains(.fresh)
    }
}

enum WidgetMetricDomain: CaseIterable {
    case vitals
    case hydration
    case activity
    case sleep
    case summary
}

enum WidgetSharedStore {
    static func loadSnapshot(now: Date = Date()) -> WidgetHealthSnapshot {
        if let sharedSnapshot = AppGroupSnapshotStore.load() {
            return loadSharedSnapshot(sharedSnapshot)
        }

        return loadLegacySnapshot(now: now)
    }

    private static func loadSharedSnapshot(_ sharedSnapshot: AppGroupHealthSnapshot) -> WidgetHealthSnapshot {
        let stepsGoal = sharedSnapshot.activity.stepsGoal ?? SharedStorageReader.int(forKey: WidgetSharedKeys.stepsGoal)
        let activeEnergyGoal = sharedSnapshot.activity.activeEnergyGoal ?? SharedStorageReader.int(forKey: WidgetSharedKeys.activeEnergyGoal)
        let exerciseMinutesGoal = sharedSnapshot.activity.exerciseMinutesGoal ?? SharedStorageReader.int(forKey: WidgetSharedKeys.exerciseMinutesGoal)
        let standHoursGoal = sharedSnapshot.activity.standHoursGoal ?? SharedStorageReader.int(forKey: WidgetSharedKeys.standHoursGoal)
        let sleepGoalMinutes = SharedStorageReader.int(forKey: WidgetSharedKeys.sleepGoalMinutes)
        let stepsRate = SharedStorageReader.double(forKey: WidgetSharedKeys.stepsCompletionRate)
            ?? completionRate(value: sharedSnapshot.activity.steps, goal: stepsGoal)
        let activeEnergyRate = SharedStorageReader.double(forKey: WidgetSharedKeys.activeEnergyCompletionRate)
            ?? completionRate(value: sharedSnapshot.activity.activeEnergy, goal: activeEnergyGoal)
        let exerciseMinutesRate = SharedStorageReader.double(forKey: WidgetSharedKeys.exerciseMinutesCompletionRate)
            ?? completionRate(value: sharedSnapshot.activity.exerciseMinutes, goal: exerciseMinutesGoal)
        let standHoursRate = SharedStorageReader.double(forKey: WidgetSharedKeys.standHoursCompletionRate)
            ?? completionRate(value: sharedSnapshot.activity.standHours, goal: standHoursGoal)
        let activityRate = SharedStorageReader.double(forKey: WidgetSharedKeys.activityCompletionRate)
            ?? averageRate([stepsRate, activeEnergyRate, exerciseMinutesRate, standHoursRate])
        let sleepRate = SharedStorageReader.double(forKey: WidgetSharedKeys.sleepDurationCompletionRate)
            ?? completionRate(value: sharedSnapshot.sleep.durationMinutes, goal: sleepGoalMinutes)
        let sunlightUpdatedAt = SharedStorageReader.date(forKey: AppGroupSchema.Keys.sunlightUpdatedAt)

        return WidgetHealthSnapshot(
            schemaVersion: max(3, sharedSnapshot.schemaVersion),
            generatedAt: sharedSnapshot.generatedAt,
            vitals: .init(
                heartRate: sharedSnapshot.vitals.heartRate,
                hrv: sharedSnapshot.vitals.hrv,
                stress: sharedSnapshot.vitals.stress,
                stressState: sharedSnapshot.vitals.stressState,
                stressQuality: sharedSnapshot.vitals.stressQuality,
                stressAlgorithmVersion: sharedSnapshot.vitals.stressAlgorithmVersion,
                dailyStress: sharedSnapshot.vitals.dailyStress,
                dailyStressQuality: sharedSnapshot.vitals.dailyStressQuality,
                dailyStressAlgorithmVersion: sharedSnapshot.vitals.dailyStressAlgorithmVersion,
                stressTrend: sharedSnapshot.vitals.stressTrend,
                stressHistory: sharedSnapshot.vitals.stressHistory.map {
                    WidgetStressHistoryPoint(timestamp: $0.timestamp, value: $0.value)
                },
                freshness: .init(
                    updatedAt: sharedSnapshot.vitals.freshness.updatedAt,
                    staleAfter: sharedSnapshot.vitals.freshness.staleAfter
                ),
                recoveryScore: deriveRecoveryScore(
                    hrv: sharedSnapshot.vitals.hrv,
                    stress: sharedSnapshot.vitals.stress
                ),
                recoveryStatus: deriveRecoveryStatus(
                    hrv: sharedSnapshot.vitals.hrv,
                    stress: sharedSnapshot.vitals.stress
                )
            ),
            hydration: .init(
                waterIntakeMl: sharedSnapshot.hydration.waterIntakeMl,
                waterTargetMl: sharedSnapshot.hydration.waterTargetMl,
                waterCompletionRate: sharedSnapshot.hydration.waterCompletionRate,
                caffeineRemainedMg: sharedSnapshot.hydration.caffeineRemainedMg,
                freshness: .init(
                    updatedAt: sharedSnapshot.hydration.freshness.updatedAt,
                    staleAfter: sharedSnapshot.hydration.freshness.staleAfter
                )
            ),
            activity: .init(
                steps: sharedSnapshot.activity.steps,
                stepsGoal: stepsGoal,
                activeEnergy: sharedSnapshot.activity.activeEnergy,
                activeEnergyGoal: activeEnergyGoal,
                exerciseMinutes: sharedSnapshot.activity.exerciseMinutes,
                exerciseMinutesGoal: exerciseMinutesGoal,
                standHours: sharedSnapshot.activity.standHours,
                standHoursGoal: standHoursGoal,
                stepsCompletionRate: stepsRate,
                activeEnergyCompletionRate: activeEnergyRate,
                exerciseMinutesCompletionRate: exerciseMinutesRate,
                standHoursCompletionRate: standHoursRate,
                activityCompletionRate: activityRate,
                walkingSpeedMps: sharedSnapshot.activity.walkingSpeedMps,
                walkingPaceSecondsPerKm: sharedSnapshot.activity.walkingPaceSecondsPerKm,
                sedentaryElapsedMinutes: sharedSnapshot.activity.sedentaryElapsedMinutes,
                sedentaryIsCounting: sharedSnapshot.activity.sedentaryIsCounting,
                freshness: .init(
                    updatedAt: sharedSnapshot.activity.freshness.updatedAt,
                    staleAfter: sharedSnapshot.activity.freshness.staleAfter
                )
            ),
            sleep: .init(
                durationMinutes: sharedSnapshot.sleep.durationMinutes,
                score: sharedSnapshot.sleep.score,
                goalMinutes: sleepGoalMinutes,
                completionRate: sleepRate,
                lateNightRecoveryPrompt: sharedSnapshot.sleep.lateNightRecoveryPrompt,
                lateNightRecoverySeverity: sharedSnapshot.sleep.lateNightRecoverySeverity,
                environmentCompletionRate: sharedSnapshot.sleep.environmentCompletionRate,
                environmentPrompt: sharedSnapshot.sleep.environmentPrompt,
                freshness: .init(
                    updatedAt: sharedSnapshot.sleep.freshness.updatedAt,
                    staleAfter: sharedSnapshot.sleep.freshness.staleAfter
                )
            ),
            summary: .init(
                healthSummary: sharedSnapshot.summary.healthSummary,
                bodyAgeValueYears: sharedSnapshot.summary.bodyAgeValueYears,
                bodyAgeStatusText: sharedSnapshot.summary.bodyAgeStatusText,
                vo2MaxValue: sharedSnapshot.summary.vo2MaxValue,
                vo2MaxConfidence: sharedSnapshot.summary.vo2MaxConfidence,
                vo2MaxTrend: sharedSnapshot.summary.vo2MaxTrend,
                vo2MaxFitnessLevel: sharedSnapshot.summary.vo2MaxFitnessLevel,
                vo2MaxSource: sharedSnapshot.summary.vo2MaxSource,
                vo2MaxDriverSummary: sharedSnapshot.summary.vo2MaxDriverSummary,
                freshness: .init(
                    updatedAt: sharedSnapshot.summary.freshness.updatedAt,
                    staleAfter: sharedSnapshot.summary.freshness.staleAfter
                )
            ),
            sunlight: .init(
                minutesToday: SharedStorageReader.int(forKey: AppGroupSchema.Keys.sunlightMinutesToday),
                goalMinutes: SharedStorageReader.int(forKey: AppGroupSchema.Keys.sunlightGoalMinutes),
                completionRate: SharedStorageReader.double(forKey: AppGroupSchema.Keys.sunlightCompletionRate),
                morningMinutes: nil,
                afternoonMinutes: nil,
                lastExposureAt: sunlightUpdatedAt,
                freshness: .init(updatedAt: sunlightUpdatedAt, staleAfter: 24 * 60 * 60)
            ),
            recoveryPlan: sharedSnapshot.recoveryPlan
        )
    }

    private static func loadLegacySnapshot(now: Date) -> WidgetHealthSnapshot {
        guard let defaults = SharedStorageReader.userDefaults() else {
            return WidgetHealthSnapshot(generatedAt: now)
        }

        let fallbackUpdatedAt = loadDate(defaults: defaults, key: WidgetSharedKeys.lastSyncTime)
        let stressHistory = loadStressHistory(defaults: defaults)

        let vitals = WidgetHealthSnapshot.Vitals(
            heartRate: defaults.object(forKey: WidgetSharedKeys.latestHeartRate) as? Double,
            hrv: defaults.object(forKey: WidgetSharedKeys.latestHRV) as? Double,
            stress: defaults.object(forKey: WidgetSharedKeys.latestStress) as? Double,
            stressTrend: defaults.string(forKey: WidgetSharedKeys.stressTrend),
            stressHistory: stressHistory,
            freshness: .init(updatedAt: fallbackUpdatedAt, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter),
            recoveryScore: deriveRecoveryScore(
                hrv: defaults.object(forKey: WidgetSharedKeys.latestHRV) as? Double,
                stress: defaults.object(forKey: WidgetSharedKeys.latestStress) as? Double
            ),
            recoveryStatus: deriveRecoveryStatus(
                hrv: defaults.object(forKey: WidgetSharedKeys.latestHRV) as? Double,
                stress: defaults.object(forKey: WidgetSharedKeys.latestStress) as? Double
            )
        )

        let hydration = WidgetHealthSnapshot.Hydration(
            waterIntakeMl: defaults.object(forKey: WidgetSharedKeys.waterIntakeMl) as? Double,
            waterTargetMl: defaults.object(forKey: WidgetSharedKeys.waterTargetMl) as? Int,
            waterCompletionRate: defaults.object(forKey: WidgetSharedKeys.waterCompletionRate) as? Double,
            caffeineRemainedMg: defaults.object(forKey: WidgetSharedKeys.caffeineRemainedMg) as? Double,
            freshness: .init(updatedAt: fallbackUpdatedAt, staleAfter: AppGroupSchema.Freshness.hydrationStaleAfter)
        )

        let activity = WidgetHealthSnapshot.Activity(
            steps: defaults.object(forKey: WidgetSharedKeys.steps) as? Int,
            stepsGoal: defaults.object(forKey: WidgetSharedKeys.stepsGoal) as? Int,
            activeEnergy: defaults.object(forKey: WidgetSharedKeys.activeEnergy) as? Int,
            activeEnergyGoal: defaults.object(forKey: WidgetSharedKeys.activeEnergyGoal) as? Int,
            exerciseMinutes: defaults.object(forKey: WidgetSharedKeys.exerciseMinutes) as? Int,
            exerciseMinutesGoal: defaults.object(forKey: WidgetSharedKeys.exerciseMinutesGoal) as? Int,
            standHours: defaults.object(forKey: WidgetSharedKeys.standHours) as? Int,
            standHoursGoal: defaults.object(forKey: WidgetSharedKeys.standHoursGoal) as? Int,
            stepsCompletionRate: defaults.object(forKey: WidgetSharedKeys.stepsCompletionRate) as? Double,
            activeEnergyCompletionRate: defaults.object(forKey: WidgetSharedKeys.activeEnergyCompletionRate) as? Double,
            exerciseMinutesCompletionRate: defaults.object(forKey: WidgetSharedKeys.exerciseMinutesCompletionRate) as? Double,
            standHoursCompletionRate: defaults.object(forKey: WidgetSharedKeys.standHoursCompletionRate) as? Double,
            activityCompletionRate: defaults.object(forKey: WidgetSharedKeys.activityCompletionRate) as? Double,
            walkingSpeedMps: defaults.object(forKey: WidgetSharedKeys.walkingSpeedMps) as? Double,
            walkingPaceSecondsPerKm: defaults.object(forKey: WidgetSharedKeys.walkingPaceSecondsPerKm) as? Int,
            sedentaryElapsedMinutes: defaults.object(forKey: WidgetSharedKeys.sedentaryElapsedMinutes) as? Int,
            sedentaryIsCounting: defaults.object(forKey: WidgetSharedKeys.sedentaryIsCounting) as? Bool,
            freshness: .init(updatedAt: fallbackUpdatedAt, staleAfter: AppGroupSchema.Freshness.activityStaleAfter)
        )

        let sleep = WidgetHealthSnapshot.Sleep(
            durationMinutes: defaults.object(forKey: WidgetSharedKeys.sleepDurationMinutes) as? Int,
            score: defaults.object(forKey: WidgetSharedKeys.sleepScore) as? Int,
            goalMinutes: defaults.object(forKey: WidgetSharedKeys.sleepGoalMinutes) as? Int,
            completionRate: defaults.object(forKey: WidgetSharedKeys.sleepDurationCompletionRate) as? Double,
            lateNightRecoveryPrompt: defaults.string(forKey: WidgetSharedKeys.lateNightRecoveryPrompt),
            lateNightRecoverySeverity: defaults.string(forKey: WidgetSharedKeys.lateNightRecoverySeverity),
            environmentCompletionRate: defaults.object(forKey: WidgetSharedKeys.sleepEnvironmentCompletionRate) as? Double,
            environmentPrompt: defaults.string(forKey: WidgetSharedKeys.sleepEnvironmentPrompt),
            freshness: .init(updatedAt: fallbackUpdatedAt, staleAfter: AppGroupSchema.Freshness.sleepStaleAfter)
        )

        let summary = WidgetHealthSnapshot.Summary(
            healthSummary: defaults.string(forKey: WidgetSharedKeys.healthSummary),
            bodyAgeValueYears: defaults.object(forKey: WidgetSharedKeys.bodyAgeValueYears) as? Double,
            bodyAgeStatusText: defaults.string(forKey: WidgetSharedKeys.bodyAgeStatusText),
            freshness: .init(updatedAt: fallbackUpdatedAt, staleAfter: AppGroupSchema.Freshness.summaryStaleAfter)
        )

        let sunlightUpdatedAt = loadDate(defaults: defaults, key: AppGroupSchema.Keys.sunlightUpdatedAt)
        let sunlight = WidgetHealthSnapshot.Sunlight(
            minutesToday: defaults.object(forKey: AppGroupSchema.Keys.sunlightMinutesToday) as? Int,
            goalMinutes: defaults.object(forKey: AppGroupSchema.Keys.sunlightGoalMinutes) as? Int,
            completionRate: defaults.object(forKey: AppGroupSchema.Keys.sunlightCompletionRate) as? Double,
            morningMinutes: nil,
            afternoonMinutes: nil,
            lastExposureAt: sunlightUpdatedAt,
            freshness: .init(updatedAt: sunlightUpdatedAt, staleAfter: 24 * 60 * 60)
        )

        return WidgetHealthSnapshot(
            generatedAt: now,
            vitals: vitals,
            hydration: hydration,
            activity: activity,
            sleep: sleep,
            summary: summary,
            sunlight: sunlight
        )
    }

    private static func loadDate(defaults: UserDefaults, key: String) -> Date? {
        guard let timestamp = defaults.object(forKey: key) as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func loadStressHistory(defaults: UserDefaults) -> [WidgetStressHistoryPoint] {
        guard let data = defaults.data(forKey: WidgetSharedKeys.stressHistoryData),
              let points = try? JSONDecoder().decode([WidgetStressHistoryPoint].self, from: data) else {
            return []
        }
        return points.sorted { $0.timestamp < $1.timestamp }
    }

    private static func deriveRecoveryScore(hrv: Double?, stress: Double?) -> Int? {
        guard let hrv else { return nil }
        let normalizedHRV = min(max(Int(hrv.rounded()), 0), 100)
        let stressPenalty = stress.map { Int(($0 / 100 * 30).rounded()) } ?? 0
        return max(0, min(100, normalizedHRV - stressPenalty + 18))
    }

    private static func deriveRecoveryStatus(hrv: Double?, stress: Double?) -> String? {
        guard let score = deriveRecoveryScore(hrv: hrv, stress: stress) else { return nil }
        switch score {
        case 75...:
            return String(localized: "可推进")
        case 50..<75:
            return String(localized: "留余量")
        default:
            return String(localized: "先恢复")
        }
    }

    private static func completionRate(value: Int?, goal: Int?) -> Double? {
        guard let value, let goal, goal > 0 else { return nil }
        return min(1.0, Double(value) / Double(goal))
    }

    private static func averageRate(_ values: [Double?]) -> Double? {
        let resolved = values.compactMap { $0 }
        guard !resolved.isEmpty else { return nil }
        return min(1.0, resolved.reduce(0.0, +) / Double(resolved.count))
    }
}

enum WidgetTimelineRefreshReason {
    case healthUpdate
    case watchSync
    case settings
    case manual
}

enum WidgetTimelineRefreshCoordinator {
    static func refreshAll(reason: WidgetTimelineRefreshReason = .healthUpdate) {
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupSchema.Kind.overall)
        for kind in AppGroupSchema.Kind.allComplicationKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
