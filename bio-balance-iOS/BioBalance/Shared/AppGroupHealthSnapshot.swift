import Foundation

nonisolated enum SharedWidgetRecoveryActionRole: String, Codable, Sendable, Hashable {
    case main
    case supporting
}

nonisolated enum SharedWidgetRecoveryActionState: String, Codable, Sendable, Hashable {
    case pending
    case completed
    case snoozed
    case skipped
    case notApplicable

    var isTerminal: Bool {
        switch self {
        case .completed, .skipped, .notApplicable:
            return true
        case .pending, .snoozed:
            return false
        }
    }
}

nonisolated struct SharedWidgetRecoveryAction: Codable, Sendable, Hashable, Identifiable {
    let actionID: String
    let title: String
    let role: SharedWidgetRecoveryActionRole
    let state: SharedWidgetRecoveryActionState

    var id: String { actionID }
}

nonisolated struct SharedWidgetRecoveryPlan: Codable, Sendable, Hashable {
    let planID: String
    let dayStart: Int
    let updatedAt: Date
    let actions: [SharedWidgetRecoveryAction]

    var processedActionCount: Int {
        actions.filter { $0.state.isTerminal }.count
    }

    var nextAction: SharedWidgetRecoveryAction? {
        actions.first { $0.state == .pending }
            ?? actions.first { $0.state == .snoozed }
    }

    func isValid(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let actionIDs = actions.map(\.actionID)
        guard !planID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              dayStart > 0,
              (1...3).contains(actions.count),
              actions.filter({ $0.role == .main }).count == 1,
              Set(actionIDs).count == actionIDs.count,
              actions.allSatisfy({
                  !$0.actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            return false
        }
        return calendar.isDate(
            Date(timeIntervalSince1970: TimeInterval(dayStart)),
            inSameDayAs: date
        )
    }
}

protocol HealthSnapshotSource {
    var bpm: Int { get }
    var hrv: Double { get }
    var stress: Int { get }
    var stressState: String? { get }
    var stressExplanationCode: String? { get }
    var stressConfidence: Double? { get }
    var stressQuality: String? { get }
    var stressAlgorithmVersion: String? { get }
    var dailyStress: Int? { get }
    var dailyStressQuality: String? { get }
    var dailyStressAlgorithmVersion: String? { get }
    var stressTrend: String { get }
    var timestamp: Int { get }
    var steps: Int { get }
    var stepsGoal: Int { get }
    var activeEnergy: Int { get }
    var activeEnergyGoal: Int { get }
    var exerciseMinutes: Int { get }
    var exerciseMinutesGoal: Int { get }
    var standHours: Int { get }
    var standHoursGoal: Int { get }
    var walkingSpeedMps: Double? { get }
    var walkingPaceSecondsPerKm: Int? { get }
    var sedentaryElapsedMinutes: Int { get }
    var sedentaryIsCounting: Bool { get }
    var sleepDurationMinutes: Int { get }
    var sleepScore: Int { get }
    var sleepSnoreIntensity: String? { get }
    var sleepSnoreDurationMinutes: Double? { get }
    var lateNightRecoveryPrompt: String? { get }
    var lateNightRecoverySeverity: String? { get }
    var sleepEnvironmentCompletionRate: Double? { get }
    var sleepEnvironmentPrompt: String? { get }
    var waterIntakeMl: Int { get }
    var waterTargetMl: Int { get }
    var waterCompletionRate: Double { get }
    var caffeineRemainedMg: Int { get }
    var bodyAgeValueYears: Double? { get }
    var bodyAgeStatusText: String? { get }
    var vo2MaxValue: Double? { get }
    var vo2MaxConfidence: Int? { get }
    var vo2MaxTrend: String? { get }
    var vo2MaxFitnessLevel: String? { get }
    var vo2MaxSource: String? { get }
    var vo2MaxDriverSummary: String? { get }
    var stressHistory: [WatchStressHistoryPoint] { get }
    var widgetRecoveryPlan: SharedWidgetRecoveryPlan? { get }
}

extension HealthSnapshotSource {
    var stressQuality: String? { nil }
    var stressAlgorithmVersion: String? { nil }
    var dailyStress: Int? { nil }
    var dailyStressQuality: String? { nil }
    var dailyStressAlgorithmVersion: String? { nil }
}

extension HealthSnapshotSource {
    var sleepSnoreIntensity: String? { nil }
    var sleepSnoreDurationMinutes: Double? { nil }
    var lateNightRecoveryPrompt: String? { nil }
    var lateNightRecoverySeverity: String? { nil }
    var sleepEnvironmentCompletionRate: Double? { nil }
    var sleepEnvironmentPrompt: String? { nil }
    var widgetRecoveryPlan: SharedWidgetRecoveryPlan? { nil }
}

nonisolated struct SharedWidgetStressHistoryPoint: Codable, Sendable, Hashable, Identifiable {
    let timestamp: Int
    let value: Int

    var id: Int { timestamp }
}

nonisolated struct AppGroupHealthSnapshot: Codable, Sendable, Hashable {
    static let currentSchemaVersion = 6

    struct MetricFreshness: Codable, Sendable, Hashable {
        let updatedAt: Date?
        let staleAfter: TimeInterval

        static func combined(_ values: [MetricFreshness]) -> MetricFreshness {
            let availableValues = values.filter { $0.updatedAt != nil }
            guard let oldestUpdate = availableValues.compactMap(\.updatedAt).min() else {
                return MetricFreshness(updatedAt: nil, staleAfter: 0)
            }

            let earliestStaleDate = availableValues.compactMap { freshness -> Date? in
                guard let updatedAt = freshness.updatedAt else { return nil }
                return updatedAt.addingTimeInterval(freshness.staleAfter)
            }.min()
            let combinedStaleAfter = max(0, earliestStaleDate?.timeIntervalSince(oldestUpdate) ?? 0)
            return MetricFreshness(updatedAt: oldestUpdate, staleAfter: combinedStaleAfter)
        }

        func nextRefreshDate(from now: Date) -> Date? {
            guard let updatedAt else { return nil }
            return updatedAt.addingTimeInterval(staleAfter)
        }

        func isStale(at now: Date) -> Bool {
            guard let updatedAt else { return true }
            return now.timeIntervalSince(updatedAt) > staleAfter
        }
    }

    struct Vitals: Codable, Sendable, Hashable {
        let heartRate: Double?
        let hrv: Double?
        let stress: Double?
        let stressState: String?
        let stressExplanationCode: String?
        let stressConfidence: Double?
        var stressQuality: String? = nil
        var stressAlgorithmVersion: String? = nil
        var dailyStress: Double? = nil
        var dailyStressQuality: String? = nil
        var dailyStressAlgorithmVersion: String? = nil
        let stressTrend: String?
        let stressHistory: [SharedWidgetStressHistoryPoint]
        let freshness: MetricFreshness
    }

    struct Hydration: Codable, Sendable, Hashable {
        let waterIntakeMl: Double?
        let waterTargetMl: Int?
        let waterCompletionRate: Double?
        let caffeineRemainedMg: Double?
        let freshness: MetricFreshness
    }

    struct Activity: Codable, Sendable, Hashable {
        let steps: Int?
        let stepsGoal: Int?
        let activeEnergy: Int?
        let activeEnergyGoal: Int?
        let exerciseMinutes: Int?
        let exerciseMinutesGoal: Int?
        let standHours: Int?
        let standHoursGoal: Int?
        let walkingSpeedMps: Double?
        let walkingPaceSecondsPerKm: Int?
        let sedentaryElapsedMinutes: Int?
        let sedentaryIsCounting: Bool?
        let freshness: MetricFreshness
    }

    struct Sleep: Codable, Sendable, Hashable {
        let durationMinutes: Int?
        let score: Int?
        let snoreIntensity: String?
        let snoreDurationMinutes: Double?
        let lateNightRecoveryPrompt: String?
        let lateNightRecoverySeverity: String?
        let environmentCompletionRate: Double?
        let environmentPrompt: String?
        let freshness: MetricFreshness
    }

    struct Summary: Codable, Sendable, Hashable {
        let healthSummary: String?
        let bodyAgeValueYears: Double?
        let bodyAgeStatusText: String?
        let vo2MaxValue: Double?
        let vo2MaxConfidence: Int?
        let vo2MaxTrend: String?
        let vo2MaxFitnessLevel: String?
        let vo2MaxSource: String?
        let vo2MaxDriverSummary: String?
        let freshness: MetricFreshness
    }

    let schemaVersion: Int
    let generatedAt: Date
    let vitals: Vitals
    let hydration: Hydration
    let activity: Activity
    let sleep: Sleep
    let summary: Summary
    let recoveryPlan: SharedWidgetRecoveryPlan?

    init(
        schemaVersion: Int,
        generatedAt: Date,
        vitals: Vitals,
        hydration: Hydration,
        activity: Activity,
        sleep: Sleep,
        summary: Summary,
        recoveryPlan: SharedWidgetRecoveryPlan? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.vitals = vitals
        self.hydration = hydration
        self.activity = activity
        self.sleep = sleep
        self.summary = summary
        self.recoveryPlan = recoveryPlan
    }

    @MainActor static func fromSource(_ source: some HealthSnapshotSource, healthSummary: String?) -> AppGroupHealthSnapshot {
        let updatedAt = Date(timeIntervalSince1970: TimeInterval(max(source.timestamp, 1)))
        let vitalsUpdatedAt = (source.bpm > 0 || source.hrv > 0 || source.stress > 0 || source.stressState != nil) ? updatedAt : nil
        let hydrationUpdatedAt = (source.waterIntakeMl > 0 || source.waterCompletionRate > 0 || source.caffeineRemainedMg > 0) ? updatedAt : nil
        let activityUpdatedAt = (source.steps > 0 || source.activeEnergy > 0 || source.exerciseMinutes > 0 || source.standHours > 0 || source.walkingSpeedMps != nil || source.walkingPaceSecondsPerKm != nil) ? updatedAt : nil
        let hasSleepGuidance = source.lateNightRecoveryPrompt != nil
            || source.sleepEnvironmentCompletionRate != nil
            || source.sleepEnvironmentPrompt != nil
        let hasSnoreSummary = source.sleepSnoreIntensity != nil || source.sleepSnoreDurationMinutes != nil
        let sleepUpdatedAt = (source.sleepDurationMinutes > 0 || source.sleepScore > 0 || hasSleepGuidance || hasSnoreSummary) ? updatedAt : nil
        let summaryUpdatedAt = (source.bodyAgeValueYears != nil || source.bodyAgeStatusText != nil || source.vo2MaxValue != nil || healthSummary != nil) ? updatedAt : nil

        return AppGroupHealthSnapshot(
            schemaVersion: currentSchemaVersion,
            generatedAt: updatedAt,
            vitals: .init(
                heartRate: source.bpm > 0 ? Double(source.bpm) : nil,
                hrv: source.hrv > 0 ? source.hrv : nil,
                stress: source.stress > 0 || source.stressState != nil ? Double(source.stress) : nil,
                stressState: source.stressState,
                stressExplanationCode: source.stressExplanationCode,
                stressConfidence: source.stressConfidence,
                stressQuality: source.stressQuality,
                stressAlgorithmVersion: source.stressAlgorithmVersion,
                dailyStress: source.dailyStress.map(Double.init),
                dailyStressQuality: source.dailyStressQuality,
                dailyStressAlgorithmVersion: source.dailyStressAlgorithmVersion,
                stressTrend: source.stressTrend.isEmpty ? nil : source.stressTrend,
                stressHistory: source.stressHistory.map {
                    SharedWidgetStressHistoryPoint(timestamp: $0.timestamp, value: $0.value)
                },
                freshness: .init(updatedAt: vitalsUpdatedAt, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter)
            ),
            hydration: .init(
                waterIntakeMl: source.waterIntakeMl > 0 ? Double(source.waterIntakeMl) : nil,
                waterTargetMl: source.waterTargetMl > 0 ? source.waterTargetMl : nil,
                waterCompletionRate: source.waterCompletionRate > 0 ? source.waterCompletionRate : nil,
                caffeineRemainedMg: source.caffeineRemainedMg > 0 ? Double(source.caffeineRemainedMg) : nil,
                freshness: .init(updatedAt: hydrationUpdatedAt, staleAfter: AppGroupSchema.Freshness.hydrationStaleAfter)
            ),
            activity: .init(
                steps: source.steps > 0 ? source.steps : nil,
                stepsGoal: source.stepsGoal > 0 ? source.stepsGoal : nil,
                activeEnergy: source.activeEnergy > 0 ? source.activeEnergy : nil,
                activeEnergyGoal: source.activeEnergyGoal > 0 ? source.activeEnergyGoal : nil,
                exerciseMinutes: source.exerciseMinutes > 0 ? source.exerciseMinutes : nil,
                exerciseMinutesGoal: source.exerciseMinutesGoal > 0 ? source.exerciseMinutesGoal : nil,
                standHours: source.standHours > 0 ? source.standHours : nil,
                standHoursGoal: source.standHoursGoal > 0 ? source.standHoursGoal : nil,
                walkingSpeedMps: source.walkingSpeedMps,
                walkingPaceSecondsPerKm: source.walkingPaceSecondsPerKm,
                sedentaryElapsedMinutes: source.sedentaryElapsedMinutes > 0 ? source.sedentaryElapsedMinutes : nil,
                sedentaryIsCounting: source.sedentaryIsCounting,
                freshness: .init(updatedAt: activityUpdatedAt, staleAfter: AppGroupSchema.Freshness.activityStaleAfter)
            ),
            sleep: .init(
                durationMinutes: source.sleepDurationMinutes > 0 ? source.sleepDurationMinutes : nil,
                score: source.sleepScore > 0 ? source.sleepScore : nil,
                snoreIntensity: source.sleepSnoreIntensity,
                snoreDurationMinutes: source.sleepSnoreDurationMinutes,
                lateNightRecoveryPrompt: source.lateNightRecoveryPrompt,
                lateNightRecoverySeverity: source.lateNightRecoverySeverity,
                environmentCompletionRate: source.sleepEnvironmentCompletionRate,
                environmentPrompt: source.sleepEnvironmentPrompt,
                freshness: .init(updatedAt: sleepUpdatedAt, staleAfter: AppGroupSchema.Freshness.sleepStaleAfter)
            ),
            summary: .init(
                healthSummary: healthSummary,
                bodyAgeValueYears: source.bodyAgeValueYears,
                bodyAgeStatusText: source.bodyAgeStatusText,
                vo2MaxValue: source.vo2MaxValue,
                vo2MaxConfidence: source.vo2MaxConfidence,
                vo2MaxTrend: source.vo2MaxTrend,
                vo2MaxFitnessLevel: source.vo2MaxFitnessLevel,
                vo2MaxSource: source.vo2MaxSource,
                vo2MaxDriverSummary: source.vo2MaxDriverSummary,
                freshness: .init(updatedAt: summaryUpdatedAt, staleAfter: AppGroupSchema.Freshness.summaryStaleAfter)
            ),
            recoveryPlan: source.widgetRecoveryPlan
        )
    }

    static func empty(generatedAt: Date = Date()) -> AppGroupHealthSnapshot {
        AppGroupHealthSnapshot(
            schemaVersion: currentSchemaVersion,
            generatedAt: generatedAt,
            vitals: .init(
                heartRate: nil,
                hrv: nil,
                stress: nil,
                stressState: nil,
                stressExplanationCode: nil,
                stressConfidence: nil,
                stressTrend: nil,
                stressHistory: [],
                freshness: .init(updatedAt: nil, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter)
            ),
            hydration: .init(
                waterIntakeMl: nil,
                waterTargetMl: nil,
                waterCompletionRate: nil,
                caffeineRemainedMg: nil,
                freshness: .init(updatedAt: nil, staleAfter: AppGroupSchema.Freshness.hydrationStaleAfter)
            ),
            activity: .init(
                steps: nil,
                stepsGoal: nil,
                activeEnergy: nil,
                activeEnergyGoal: nil,
                exerciseMinutes: nil,
                exerciseMinutesGoal: nil,
                standHours: nil,
                standHoursGoal: nil,
                walkingSpeedMps: nil,
                walkingPaceSecondsPerKm: nil,
                sedentaryElapsedMinutes: nil,
                sedentaryIsCounting: nil,
                freshness: .init(updatedAt: nil, staleAfter: AppGroupSchema.Freshness.activityStaleAfter)
            ),
            sleep: .init(
                durationMinutes: nil,
                score: nil,
                snoreIntensity: nil,
                snoreDurationMinutes: nil,
                lateNightRecoveryPrompt: nil,
                lateNightRecoverySeverity: nil,
                environmentCompletionRate: nil,
                environmentPrompt: nil,
                freshness: .init(updatedAt: nil, staleAfter: AppGroupSchema.Freshness.sleepStaleAfter)
            ),
            summary: .init(
                healthSummary: nil,
                bodyAgeValueYears: nil,
                bodyAgeStatusText: nil,
                vo2MaxValue: nil,
                vo2MaxConfidence: nil,
                vo2MaxTrend: nil,
                vo2MaxFitnessLevel: nil,
                vo2MaxSource: nil,
                vo2MaxDriverSummary: nil,
                freshness: .init(updatedAt: nil, staleAfter: AppGroupSchema.Freshness.summaryStaleAfter)
            )
        )
    }

    func replacingRecoveryPlan(_ recoveryPlan: SharedWidgetRecoveryPlan?) -> AppGroupHealthSnapshot {
        AppGroupHealthSnapshot(
            schemaVersion: Self.currentSchemaVersion,
            generatedAt: generatedAt,
            vitals: vitals,
            hydration: hydration,
            activity: activity,
            sleep: sleep,
            summary: summary,
            recoveryPlan: recoveryPlan
        )
    }

    /// A refresh can legitimately miss one HealthKit domain while other domains
    /// have already been projected. Keep the last domain snapshot in that case
    /// so a transient empty refresh does not turn a synced widget back into
    /// "waiting for sync". Explicit cache deletion still goes through
    /// `AppGroupSnapshotStore.clear`.
    func preservingPreviouslySyncedDomains(from previous: AppGroupHealthSnapshot) -> AppGroupHealthSnapshot {
        AppGroupHealthSnapshot(
            schemaVersion: max(schemaVersion, previous.schemaVersion),
            generatedAt: generatedAt,
            vitals: vitals.freshness.updatedAt == nil && canPreserve(previous.vitals.freshness)
                ? previous.vitals
                : vitals,
            hydration: hydration.freshness.updatedAt == nil && canPreserve(previous.hydration.freshness, sameDayOnly: true)
                ? previous.hydration
                : hydration,
            activity: activity.freshness.updatedAt == nil && canPreserve(previous.activity.freshness, sameDayOnly: true)
                ? previous.activity
                : activity,
            sleep: sleep.freshness.updatedAt == nil && canPreserve(previous.sleep.freshness)
                ? previous.sleep
                : sleep,
            summary: summary.freshness.updatedAt == nil && canPreserve(previous.summary.freshness)
                ? previous.summary
                : summary,
            recoveryPlan: recoveryPlan
        )
    }

    private func canPreserve(
        _ freshness: MetricFreshness,
        sameDayOnly: Bool = false,
        calendar: Calendar = .current
    ) -> Bool {
        guard let updatedAt = freshness.updatedAt,
              !freshness.isStale(at: generatedAt) else {
            return false
        }
        return !sameDayOnly || calendar.isDate(updatedAt, inSameDayAs: generatedAt)
    }

    func replacingHydration(
        waterIntakeMl: Double,
        waterTargetMl: Int,
        waterCompletionRate: Double,
        caffeineRemainedMg: Double?,
        updatedAt: Date
    ) -> AppGroupHealthSnapshot {
        AppGroupHealthSnapshot(
            schemaVersion: Self.currentSchemaVersion,
            generatedAt: max(generatedAt, updatedAt),
            vitals: vitals,
            hydration: .init(
                waterIntakeMl: max(0, waterIntakeMl),
                waterTargetMl: max(1, waterTargetMl),
                waterCompletionRate: min(max(0, waterCompletionRate), 1),
                caffeineRemainedMg: caffeineRemainedMg,
                freshness: .init(
                    updatedAt: updatedAt,
                    staleAfter: AppGroupSchema.Freshness.hydrationStaleAfter
                )
            ),
            activity: activity,
            sleep: sleep,
            summary: summary,
            recoveryPlan: recoveryPlan
        )
    }

    func freshness(for template: SharedComplicationTemplate) -> MetricFreshness {
        switch template {
        case .overview:
            return .combined([vitals.freshness, sleep.freshness, activity.freshness])
        case .recovery:
            return .combined([vitals.freshness, sleep.freshness])
        case .sleep:
            return sleep.freshness
        case .activity:
            return activity.freshness
        case .hydration:
            return hydration.freshness
        case .bodyAge:
            return summary.freshness
        }
    }
}
