import Foundation

nonisolated enum AppGroupSchema {
    static let appGroupIdentifier = "group.com.biobalance.shared"

    enum Kind {
        static let overall = "BioBalanceWidget"
        static let sunlight = "SunlightWidget"
        static let sleep = "SleepWidget"
        static let stress = "StressWidget"
        static let vitals = "VitalsWidget"
        static let activity = "ActivityWidget"
        static let activityConfigurable = "ActivityConfigurableWidget"
        static let complication = "BioBalanceComplicationWidget"
        static let complicationRelevance = "com.boundesu.BioBalance.watch.relevance"
        static let complicationOverviewRectangular = "BioBalanceComplicationOverviewRectangularWidget"
        static let complicationOverviewCircular = "BioBalanceComplicationOverviewCircularWidget"
        static let complicationOverviewCorner = "BioBalanceComplicationOverviewCornerWidget"
        static let complicationRecoveryRectangular = "BioBalanceComplicationRecoveryRectangularWidget"
        static let complicationRecoveryCorner = "BioBalanceComplicationRecoveryCornerWidget"
        static let complicationSleepRectangular = "BioBalanceComplicationSleepRectangularWidget"
        static let complicationSleepCorner = "BioBalanceComplicationSleepCornerWidget"
        static let complicationActivityRectangular = "BioBalanceComplicationActivityRectangularWidget"
        static let complicationSleepCircular = "BioBalanceComplicationSleepCircularWidget"
        static let complicationActivityCircular = "BioBalanceComplicationActivityCircularWidget"
        static let complicationRecoveryCircular = "BioBalanceComplicationRecoveryCircularWidget"
        static let complicationHydrationRectangular = "BioBalanceComplicationHydrationRectangularWidget"
        static let complicationHydrationCircular = "BioBalanceComplicationHydrationCircularWidget"
        static let complicationHydrationCorner = "BioBalanceComplicationHydrationCornerWidget"
        static let complicationBodyAgeRectangular = "BioBalanceComplicationBodyAgeRectangularWidget"
        static let complicationBodyAgeCircular = "BioBalanceComplicationBodyAgeCircularWidget"
        static let complicationBodyAgeCorner = "BioBalanceComplicationBodyAgeCornerWidget"
        static let complicationActivityCorner = "BioBalanceComplicationActivityCornerWidget"

        static let allComplicationKinds = [
            complication,
            complicationOverviewRectangular,
            complicationOverviewCircular,
            complicationOverviewCorner,
            complicationRecoveryRectangular,
            complicationRecoveryCircular,
            complicationRecoveryCorner,
            complicationSleepRectangular,
            complicationSleepCircular,
            complicationSleepCorner,
            complicationActivityRectangular,
            complicationActivityCircular,
            complicationActivityCorner,
            complicationHydrationRectangular,
            complicationHydrationCircular,
            complicationHydrationCorner,
            complicationBodyAgeRectangular,
            complicationBodyAgeCircular,
            complicationBodyAgeCorner
        ]
    }

    enum Freshness {
        static let vitalsStaleAfter: TimeInterval = 2 * 60 * 60
        static let hydrationStaleAfter: TimeInterval = 6 * 60 * 60
        static let activityStaleAfter: TimeInterval = 4 * 60 * 60
        static let sleepStaleAfter: TimeInterval = 18 * 60 * 60
        static let summaryStaleAfter: TimeInterval = 12 * 60 * 60
        static let sunlightStaleAfter: TimeInterval = 24 * 60 * 60
        static let generalStaleAfter: TimeInterval = 6 * 60 * 60
    }

    enum Keys {
        static let latestHeartRate = "latestHeartRate"
        static let latestHRV = "latestHRV"
        static let lastSyncTime = "lastSyncTime"
        static let latestStress = "latestStress"
        static let stressQuality = "stressQuality"
        static let stressAlgorithmVersion = "stressAlgorithmVersion"
        static let dailyStress = "dailyStress"
        static let dailyStressQuality = "dailyStressQuality"
        static let dailyStressAlgorithmVersion = "dailyStressAlgorithmVersion"
        static let stressTrend = "stressTrend"
        static let stressHistoryData = "stressHistoryData"
        static let healthSummary = "healthSummary"
        static let waterIntakeMl = "waterIntakeMl"
        static let waterTargetMl = "waterTargetMl"
        static let waterCompletionRate = "waterCompletionRate"
        static let caffeineRemainedMg = "caffeineRemainedMg"
        static let steps = "steps"
        static let activeEnergy = "activeEnergy"
        static let exerciseMinutes = "exerciseMinutes"
        static let standHours = "standHours"
        static let sleepDurationMinutes = "sleepDurationMinutes"
        static let sleepScore = "sleepScore"
        static let sleepMonitoringState = "sleepMonitoringState"
        static let sleepLatestSummary = "sleepLatestSummary"
        static let sleepSnoreDurationMinutes = "sleepSnoreDurationMinutes"
        static let sleepSnoreIntensity = "sleepSnoreIntensity"
        static let sleepInsightHeadline = "sleepInsightHeadline"
        static let sleepWatchConfidence = "sleepWatchConfidence"
        static let lateNightRecoveryPrompt = "lateNightRecoveryPrompt"
        static let lateNightRecoverySeverity = "lateNightRecoverySeverity"
        static let sleepEnvironmentCompletionRate = "sleepEnvironmentCompletionRate"
        static let sleepEnvironmentPrompt = "sleepEnvironmentPrompt"
        static let stepsGoal = "stepsGoal"
        static let activeEnergyGoal = "activeEnergyGoal"
        static let exerciseMinutesGoal = "exerciseMinutesGoal"
        static let standHoursGoal = "standHoursGoal"
        static let sleepGoalMinutes = "sleepGoalMinutes"
        static let stepsCompletionRate = "stepsCompletionRate"
        static let activeEnergyCompletionRate = "activeEnergyCompletionRate"
        static let exerciseMinutesCompletionRate = "exerciseMinutesCompletionRate"
        static let standHoursCompletionRate = "standHoursCompletionRate"
        static let sleepDurationCompletionRate = "sleepDurationCompletionRate"
        static let activityCompletionRate = "activityCompletionRate"
        static let walkingSpeedMps = "walkingSpeedMps"
        static let walkingPaceSecondsPerKm = "walkingPaceSecondsPerKm"
        static let sunlightMinutesToday = "sunlightMinutesToday"
        static let sunlightGoalMinutes = "sunlightGoalMinutes"
        static let sunlightCompletionRate = "sunlightCompletionRate"
        static let sunlightUpdatedAt = "sunlightUpdatedAt"
        static let sedentaryElapsedMinutes = "sedentaryElapsedMinutes"
        static let sedentaryIsCounting = "sedentaryIsCounting"
        static let sedentaryPausedBySleep = "sedentaryPausedBySleep"
        static let sedentarySeatedStartAt = "sedentarySeatedStartAt"
        static let sedentaryLastActivityAt = "sedentaryLastActivityAt"
        static let sedentaryUpdatedAt = "sedentaryUpdatedAt"
        static let sedentaryBreakIsActive = "sedentaryBreakIsActive"
        static let sedentaryBreakDurationMinutes = "sedentaryBreakDurationMinutes"
        static let sedentaryBreakStartedAt = "sedentaryBreakStartedAt"
        static let periodPhase = "periodPhase"
        static let periodCycleDay = "periodCycleDay"
        static let periodIsFertile = "periodIsFertile"
        static let periodNextStart = "periodNextStart"
        static let periodFertileStart = "periodFertileStart"
        static let periodFertileEnd = "periodFertileEnd"
        static let periodPredictionSource = "periodPredictionSource"
        static let defaultComplicationTemplate = "defaultComplicationTemplate"
        static let defaultComplicationTemplateUpdatedAt = "defaultComplicationTemplateUpdatedAt"
        static let watchThemeId = "watchThemeId"
        static let watchMascotEnabled = "watchMascotEnabled"
        static let watchMascotMessage = "watchMascotMessage"
        static let watchCustomThemeId = "watchCustomThemeId"
        static let bodyAgeValueYears = "bodyAgeValueYears"
        static let bodyAgeStatusText = "bodyAgeStatusText"
        static let bodyAgeComparisonText = "bodyAgeComparisonText"
        static let bodyAgeSuggestionText = "bodyAgeSuggestionText"
        static let bodyAgeCoverageText = "bodyAgeCoverageText"
        static let bodyAgeDirectionText = "bodyAgeDirectionText"
        static let vo2MaxValue = "vo2MaxValue"
        static let vo2MaxConfidence = "vo2MaxConfidence"
        static let vo2MaxTrend = "vo2MaxTrend"
        static let vo2MaxFitnessLevel = "vo2MaxFitnessLevel"
        static let vo2MaxSource = "vo2MaxSource"
        static let vo2MaxDriverSummary = "vo2MaxDriverSummary"
        static let appFontScaleLevel = "appFontScaleLevel"
        static let widgetSnapshotV2 = "widgetSnapshotV2"
    }
}
