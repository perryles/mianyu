import Foundation
import HealthKit

/// 趋势分类卡片 / 详情构建器：从 TrendsViewModel.swift 拆出的独立子模块。
/// 原为 private struct TrendCategoryBuilder（同文件私有），拆分为独立文件后提升为 internal，
/// 仅由 TrendsViewModel 内部调用，对外接口不变。

struct TrendCategoryBuilder {
    let healthKitManager: HealthKitManager

    enum EventAggregation {
        case sum
        case average
    }

    func build(range: TrendsRange) async -> (cards: [TrendCategoryCardModel], details: [TrendCategoryID: TrendCategoryDetailModel]) {
        let days = range.windowDays
        async let heartRate = fetchHeartRateSeries(range: range)
        async let restingHeartRate = fetchRestingHeartRateSeries(range: range)
        async let hrv = fetchHRVSeries(range: range)
        async let walkingHeartRate = fetchWalkingHeartRateSeries(range: range)
        async let ecgSamples = try? healthKitManager.fetchLatestElectrocardiograms(limit: 3)
        async let bloodPressure = try? healthKitManager.fetchLatestBloodPressure()
        async let irregularHeartRhythmDate = try? healthKitManager.fetchLatestCategoryEventDate(rawValue: "IrregularHeartRhythmEvent")
        async let highHeartRateEventDate = try? healthKitManager.fetchLatestCategoryEventDate(rawValue: "HighHeartRateEvent")
        async let lowHeartRateEventDate = try? healthKitManager.fetchLatestCategoryEventDate(rawValue: "LowHeartRateEvent")
        async let hypertensionEventDate = try? healthKitManager.fetchLatestCategoryEventDate(rawValue: "HypertensionEvent")
        async let bodyMass = try? healthKitManager.fetchDailyBodyMassAverages(days: days)
        async let leanBodyMass = try? healthKitManager.fetchDailyLeanBodyMassAverages(days: days)
        async let height = try? healthKitManager.fetchDailyHeightAverages(days: days)
        async let bmi = try? healthKitManager.fetchDailyBodyMassIndexAverages(days: days)
        async let bodyFat = try? healthKitManager.fetchDailyBodyFatPercentageAverages(days: days)
        async let steps = fetchStepPoints(range: range)
        async let walkingDistance = fetchWalkingDistancePoints(range: range)
        async let sleep = try? healthKitManager.fetchSleepDurationSeries(days: days)
        async let sleepConsistency = try? healthKitManager.fetchSleepConsistencySeries(days: days)
        async let sleepStages = try? healthKitManager.fetchDetailedSleepStages()
        async let sleepNightSummaries = try? healthKitManager.fetchSleepNightSummaries(days: days)
        async let nightlySleepHrv = try? healthKitManager.fetchNightlyHRVAverages(days: days)
        async let nightlyHeartRate = try? healthKitManager.fetchNightlyHeartRateAverages(days: days)
        async let nightlyRespiratoryRate = try? healthKitManager.fetchNightlyRespiratoryRateAverages(days: days)
        async let latestSleepInterval = try? healthKitManager.fetchLatestSleepInterval()
        async let walkingSpeed = fetchWalkingSpeedSeries(range: range)
        async let walkingAsymmetry = try? healthKitManager.fetchDailyWalkingAsymmetryAverages(days: days)
        async let walkingStepLength = try? healthKitManager.fetchDailyWalkingStepLengthAverages(days: days)
        async let walkingDoubleSupport = try? healthKitManager.fetchDailyWalkingDoubleSupportAverages(days: days)
        async let stairAscentSpeed = try? healthKitManager.fetchDailyStairAscentSpeedAverages(days: days)
        async let stairDescentSpeed = try? healthKitManager.fetchDailyStairDescentSpeedAverages(days: days)
        async let walkingSteadiness = try? healthKitManager.fetchDailyWalkingSteadinessAverages(days: days)
        async let respiratory = try? healthKitManager.fetchDailyRespiratoryRateAverages(days: days)
        async let oxygenSaturation = try? healthKitManager.fetchDailyOxygenSaturationAverages(days: days)
        async let wristTemperature = try? healthKitManager.fetchDailySleepingWristTemperatureAverages(days: days)
        async let workoutSummaries = try? healthKitManager.fetchWorkoutDaySummaries(
            startDate: Calendar.current.date(byAdding: .day, value: -(max(days, 1) - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date(),
            endDate: Date()
        )
        async let runningWorkoutSummaries = try? healthKitManager.fetchWorkoutDaySummaries(
            startDate: Calendar.current.date(byAdding: .day, value: -(max(days, 1) - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date(),
            endDate: Date(),
            activityTypes: [.running]
        )
        async let cyclingWorkoutSummaries = try? healthKitManager.fetchWorkoutDaySummaries(
            startDate: Calendar.current.date(byAdding: .day, value: -(max(days, 1) - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date(),
            endDate: Date(),
            activityTypes: [.cycling]
        )
        async let swimmingWorkoutSummaries = try? healthKitManager.fetchWorkoutDaySummaries(
            startDate: Calendar.current.date(byAdding: .day, value: -(max(days, 1) - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date(),
            endDate: Date(),
            activityTypes: [.swimming]
        )
        async let environmentalAudio = fetchEnvironmentalAudioPoints(for: range, healthKit: healthKitManager)
        async let headphoneExposureLevel = fetchHeadphoneExposureLevelPoints(for: range, healthKit: healthKitManager)
        async let daylight = fetchEnvironmentDaylightPoints(for: range, healthKit: healthKitManager)
        async let headphoneExposureDuration = fetchHeadphoneExposureDurationPoints(for: range, healthKit: healthKitManager)
        async let dailyHabitAnalytics = fetchDailyHabitAnalytics(days: days)
        async let period = try? healthKitManager.fetchDailyMenstrualFlowLevels(days: days)
        async let stateOfMind = try? healthKitManager.fetchDailyStateOfMindAverages(days: days)
        async let mindful = try? healthKitManager.fetchDailyMindfulMinutes(days: days)
        async let remotePeriodSummary = fetchRemotePeriodSummary(days: max(days, 90))

        let heartPoints = await heartRate
        let restingPoints = await restingHeartRate
        let hrvPoints = await hrv
        let walkingHeartRatePoints = await walkingHeartRate
        let latestECGSamples = (await ecgSamples) ?? []
        let latestBloodPressure = await bloodPressure
        let latestIrregularHeartRhythmDate = (await irregularHeartRhythmDate) ?? nil
        let latestHighHeartRateEventDate = (await highHeartRateEventDate) ?? nil
        let latestLowHeartRateEventDate = (await lowHeartRateEventDate) ?? nil
        let latestHypertensionEventDate = (await hypertensionEventDate) ?? nil
        let bodyMassPoints = (await bodyMass) ?? []
        let leanBodyMassPoints = (await leanBodyMass) ?? []
        let heightPoints = (await height) ?? []
        let bmiPoints = (await bmi) ?? []
        let bodyFatPoints = (await bodyFat) ?? []
        let stepPoints = await steps
        let walkingDistancePoints = await walkingDistance
        let sleepPoints = (await sleep) ?? []
        let sleepConsistencyPoints = (await sleepConsistency) ?? []
        let sleepStageValues = (await sleepStages) ?? []
        let sleepNightSummaryValues = (await sleepNightSummaries) ?? []
        let nightlySleepHrvValues = (await nightlySleepHrv) ?? []
        let nightlyHeartRateValues = (await nightlyHeartRate) ?? []
        let nightlyRespiratoryRateValues = (await nightlyRespiratoryRate) ?? []
        let latestSleepIntervalValue = (await latestSleepInterval) ?? nil
        let walkingSpeedPoints = await walkingSpeed
        let walkingAsymmetryPoints = Self.convertPercentToPercentage((await walkingAsymmetry) ?? [])
        let walkingStepLengthPoints = (await walkingStepLength) ?? []
        let walkingDoubleSupportPoints = Self.convertPercentToPercentage((await walkingDoubleSupport) ?? [])
        let stairAscentSpeedPoints = (await stairAscentSpeed) ?? []
        let stairDescentSpeedPoints = (await stairDescentSpeed) ?? []
        let walkingSteadinessPoints = Self.convertPercentToPercentage((await walkingSteadiness) ?? [])
        let respiratoryPoints = (await respiratory) ?? []
        let oxygenSaturationPoints = Self.convertPercentToPercentage((await oxygenSaturation) ?? [])
        let wristTemperaturePoints = (await wristTemperature) ?? []
        let workoutSummaryValues = (await workoutSummaries) ?? []
        let runningWorkoutSummaryValues = (await runningWorkoutSummaries) ?? []
        let cyclingWorkoutSummaryValues = (await cyclingWorkoutSummaries) ?? []
        let swimmingWorkoutSummaryValues = (await swimmingWorkoutSummaries) ?? []
        let daylightPoints = await daylight
        let environmentalAudioPoints = await environmentalAudio
        let headphoneExposureLevelPoints = await headphoneExposureLevel
        let headphoneExposureDurationPoints = await headphoneExposureDuration
        let dailyHabitAnalyticsValues = await dailyHabitAnalytics
        let periodPoints = (await period) ?? []
        let stateOfMindPoints = (await stateOfMind) ?? []
        let mindfulPoints = (await mindful) ?? []
        let periodSummary = mergedPeriodSummary(
            local: PeriodStore.shared.summary(days: max(days, 90)),
            remote: await remotePeriodSummary
        )

        var details: [TrendCategoryID: TrendCategoryDetailModel] = [:]

        let heartCardioStatus = statusFor(
            coreMetrics: [heartPoints, restingPoints, hrvPoints, walkingHeartRatePoints]
        )

        let heartMetrics = [
            metric("心率", "次/分", heartPoints, accent: "F05275"),
            metric("静息心率", "次/分", restingPoints, accent: "FF7A59"),
            metric("心率变异性（HRV）", "ms", hrvPoints, accent: "5E5CE6"),
            metric("步行平均心率", "次/分", walkingHeartRatePoints, accent: "FFB340")
        ]
        let heartECGRecords = Self.buildHeartECGRecords(from: latestECGSamples)
        let heartECGSummary = Self.buildHeartECGSummary(
            records: heartECGRecords,
            overall: heartCardioStatus
        )
        let heartClinicalMonitorSummary = Self.buildHeartClinicalMonitorSummary(
            bloodPressure: latestBloodPressure,
            irregularHeartRhythmDate: latestIrregularHeartRhythmDate,
            highHeartRateEventDate: latestHighHeartRateEventDate,
            lowHeartRateEventDate: latestLowHeartRateEventDate,
            hypertensionEventDate: latestHypertensionEventDate
        )

        details[.heartCardio] = makeDetail(
            category: .heartCardio,
            status: heartCardioStatus,
            headerSummary: summaryText(prefix: "把心率、静息心率、心率变异性与步行平均心率放在一起看，更适合判断日常心率负荷、恢复弹性与节律稳定性。", points: [heartPoints, restingPoints, hrvPoints, walkingHeartRatePoints]),
            metrics: heartMetrics,
            heartECGSummary: heartECGSummary,
            heartECGRecords: heartECGRecords,
            heartClinicalMonitorSummary: heartClinicalMonitorSummary
        )

        let bodyMetricsStatus = statusFor(
            coreMetrics: [bodyMassPoints, leanBodyMassPoints, heightPoints, bmiPoints, bodyFatPoints]
        )

        details[.bodyMetrics] = makeDetail(
            category: .bodyMetrics,
            status: bodyMetricsStatus,
            headerSummary: summaryText(prefix: "身高、体重、瘦体重、BMI 和体脂率放在一起看，更适合判断体型变化、目标距离与身体成分节奏。", points: [bodyMassPoints, leanBodyMassPoints, heightPoints, bmiPoints, bodyFatPoints]),
            metrics: [
                metric("体重", "kg", bodyMassPoints, accent: "7CD992"),
                metric("瘦体重", "kg", leanBodyMassPoints, accent: "FFB340"),
                metric("身高", "cm", heightPoints, accent: "91C783"),
                metric("BMI", "", bmiPoints, accent: "5DADE2"),
                metric("体脂率", "%", bodyFatPoints, accent: "8EC5FF")
            ]
        )

        let dailyActivityStatus = statusFor(
            coreMetrics: [walkingSpeedPoints, stepPoints, walkingDistancePoints]
        )

        details[.dailyActivity] = makeDetail(
            category: .dailyActivity,
            status: dailyActivityStatus,
            headerSummary: summaryText(prefix: "把步行速度、步数和步行距离放在一起看，更适合判断最近移动效率和日常步行节律有没有变化。", points: [walkingSpeedPoints, stepPoints, walkingDistancePoints]),
            metrics: [
                metric("步行速度", "m/s", walkingSpeedPoints, accent: "5DADE2"),
                metric("步数", "步", stepPoints, accent: "7CD992"),
                metric("步行距离", "km", walkingDistancePoints, accent: "32ADE6")
            ]
        )

        let sleepRecoveryStatus = statusFor(
            coreMetrics: [sleepPoints, sleepConsistencyPoints]
        )

        let deepRatioPoints = Self.sleepRatioSeries(from: sleepNightSummaryValues, ratio: \.deepRatio)
        let remRatioPoints = Self.sleepRatioSeries(from: sleepNightSummaryValues, ratio: \.remRatio)
        let sleepEfficiencyPoints = Self.sleepEfficiencySeries(from: sleepNightSummaryValues)
        let sleepCompositeScores = Self.sleepCompositeScoreSeries(
            from: sleepNightSummaryValues,
            nightlyHeartRateValues: nightlyHeartRateValues,
            sleepConsistencyPoints: sleepConsistencyPoints,
            nightlyHrvValues: nightlySleepHrvValues
        )
        let sleepScorePoints = sleepCompositeScores.map {
            TimeSeriesPointDouble(
                timestamp: Int64($0.day.timeIntervalSince1970),
                value: $0.overallScore
            )
        }
        let nightlySleepHrvPoints = await Self.sleepRecoveryMetricPoints(
            range: range,
            sleepInterval: latestSleepIntervalValue,
            fallback: Self.nightlyHrvSeries(from: nightlySleepHrvValues)
        ) {
            try await healthKitManager.fetchHRVSamples(start: $0.start, end: $0.end)
        }
        let nightlyHeartRatePoints = await Self.sleepRecoveryMetricPoints(
            range: range,
            sleepInterval: latestSleepIntervalValue,
            fallback: Self.nightlyVitalSeries(from: nightlyHeartRateValues)
        ) {
            let samples = try await healthKitManager.fetchHeartRateSeries(start: $0.start, end: $0.end)
            return samples.map { TimeSeriesPointDouble(timestamp: $0.timestamp, value: Double($0.value)) }
        }
        let nightlyRespiratoryRatePoints = await Self.sleepRecoveryMetricPoints(
            range: range,
            sleepInterval: latestSleepIntervalValue,
            fallback: Self.nightlyVitalSeries(from: nightlyRespiratoryRateValues)
        ) {
            try await healthKitManager.fetchRespiratoryRateTimeSeries(start: $0.start, end: $0.end)
        }
        let sleepCoreMetrics = [
            metric("睡眠总时长", "分钟", sleepPoints, accent: "7D8BFF"),
            metric("睡眠规律性", "分", sleepConsistencyPoints, accent: "9B7DFF", summaryOverride: Self.sleepConsistencySummary(from: sleepConsistencyPoints)),
            metric("深睡占比", "%", deepRatioPoints, accent: "4B48B8", summaryOverride: Self.ratioSummary(from: deepRatioPoints)),
            metric("REM 占比", "%", remRatioPoints, accent: "57C7D4", summaryOverride: Self.ratioSummary(from: remRatioPoints)),
            metric("睡眠效率", "%", sleepEfficiencyPoints, accent: "5FC8BE", summaryOverride: Self.efficiencySummary(from: sleepEfficiencyPoints)),
            metric("睡眠评分", "分", sleepScorePoints, accent: "FFB340", statusOverride: Self.metricStatus(for: sleepScorePoints), summaryOverride: Self.scoreSummary(from: sleepCompositeScores))
        ]
        let recoveryMetrics = [
            metric("睡眠 HRV", "ms", nightlySleepHrvPoints, accent: "5E5CE6", statusOverride: Self.metricStatus(for: nightlySleepHrvPoints)),
            metric("夜间心率", "次/分", nightlyHeartRatePoints, accent: "FF7A59", statusOverride: Self.metricStatus(for: nightlyHeartRatePoints)),
            metric("呼吸频率", "次/分", nightlyRespiratoryRatePoints, accent: "57C7B6", statusOverride: Self.metricStatus(for: nightlyRespiratoryRatePoints))
        ]
        let sleepClinicalSummary = Self.buildSleepClinicalSummary(
            nights: sleepNightSummaryValues,
            sleepPoints: sleepPoints,
            consistencyPoints: sleepConsistencyPoints,
            sleepScorePoints: sleepScorePoints,
            stages: sleepStageValues
        )
        let sleepAIInsight = Self.buildSleepAIInsight(
            nights: sleepNightSummaryValues,
            sleepPoints: sleepPoints,
            consistencyPoints: sleepConsistencyPoints,
            sleepScorePoints: sleepScorePoints,
            hrvPoints: nightlySleepHrvPoints,
            nightlyHeartRatePoints: nightlyHeartRatePoints
        )
        details[.sleepRecovery] = makeDetail(
            category: .sleepRecovery,
            status: sleepRecoveryStatus,
            headerSummary: sleepClinicalSummary?.headline ?? (sleepPoints.isEmpty ? "继续佩戴设备记录睡眠后，这里会形成睡眠恢复趋势。" : "睡眠总时长、综合恢复完成度和夜间恢复信号会一起显示，方便判断恢复质量。"),
            metrics: sleepCoreMetrics + recoveryMetrics,
            sleepStages: sleepStageValues,
            sleepClinicalSummary: sleepClinicalSummary,
            sleepAIInsight: sleepAIInsight,
            sleepCompositeScores: sleepCompositeScores,
            sleepNightSummaries: sleepNightSummaryValues,
            sleepCoreMetrics: sleepCoreMetrics,
            sleepRecoveryMetrics: recoveryMetrics
        )

        let mobilityGaitStatus = statusFor(
            coreMetrics: [
                walkingStepLengthPoints,
                walkingSpeedPoints,
                walkingAsymmetryPoints,
                walkingDoubleSupportPoints,
                walkingSteadinessPoints,
                stairAscentSpeedPoints,
                stairDescentSpeedPoints
            ]
        )
        let mobilityMetrics = [
            metric("步行步长", "m", walkingStepLengthPoints, accent: "8EC5FF"),
            metric("步行速度", "m/s", walkingSpeedPoints, accent: "5DADE2"),
            metric("步伐不对称", "%", walkingAsymmetryPoints, accent: "FFB340"),
            metric("双足支撑时间", "%", walkingDoubleSupportPoints, accent: "FF7A59"),
            metric("步行稳定性", "%", walkingSteadinessPoints, accent: "7CD992"),
            metric("爬坡速度：上楼", "m/s", stairAscentSpeedPoints, accent: "5B8CFF"),
            metric("爬坡速度：下楼", "m/s", stairDescentSpeedPoints, accent: "57C7B6")
        ]
        let mobilityAIInsight = Self.buildMobilityAIInsight(
            walkingStepLengthPoints: walkingStepLengthPoints,
            walkingSpeedPoints: walkingSpeedPoints,
            walkingAsymmetryPoints: walkingAsymmetryPoints,
            walkingDoubleSupportPoints: walkingDoubleSupportPoints,
            walkingSteadinessPoints: walkingSteadinessPoints
        )

        details[.mobilityGait] = makeDetail(
            category: .mobilityGait,
            status: mobilityGaitStatus,
            headerSummary: summaryText(
                prefix: "把步行步长、速度、平衡、双足支撑和稳定性放在一起，更适合判断最近行动能力有没有连续偏移。",
                points: [
                    walkingStepLengthPoints,
                    walkingSpeedPoints,
                    walkingAsymmetryPoints,
                    walkingDoubleSupportPoints,
                    walkingSteadinessPoints,
                    stairAscentSpeedPoints,
                    stairDescentSpeedPoints
                ]
            ),
            metrics: mobilityMetrics,
            mobilityAIInsight: mobilityAIInsight
        )

        let reproductiveStatus = Self.reproductiveStatus(summary: periodSummary)
        let reproductiveDetail = Self.buildReproductiveDetail(summary: periodSummary)
        let reproductiveMetrics = Self.reproductiveMetrics(
            from: periodSummary,
            fallbackPoints: periodPoints
        )

        details[.reproductive] = makeDetail(
            category: .reproductive,
            status: reproductiveStatus,
            headerSummary: Self.reproductiveHeaderSummary(summary: periodSummary),
            metrics: reproductiveMetrics,
            reproductiveDetail: reproductiveDetail
        )

        let vitalsRespiratoryStatus = statusFor(
            coreMetrics: [respiratoryPoints, wristTemperaturePoints, oxygenSaturationPoints]
        )

        details[.vitalsRespiratory] = makeDetail(
            category: .vitalsRespiratory,
            status: vitalsRespiratoryStatus,
            headerSummary: summaryText(prefix: "把呼吸率、血氧和睡眠腕温放在一起，观察基础生命体征是否持续偏离个人基线。", points: [respiratoryPoints, wristTemperaturePoints, oxygenSaturationPoints]),
            metrics: [
                metric("呼吸率", "次/分", respiratoryPoints, accent: "FF9F0A"),
                metric("血氧饱和度", "%", oxygenSaturationPoints, accent: "32ADE6"),
                metric("睡眠腕温", "°C", wristTemperaturePoints, accent: "FF7A59")
            ]
        )

        let runningDurationPoints = Self.convertWorkoutSummaries(runningWorkoutSummaryValues)
        let runningCountPoints = Self.convertWorkoutCounts(runningWorkoutSummaryValues)
        let runningDistancePoints = Self.convertWorkoutDistances(runningWorkoutSummaryValues)
        let runningEnergyPoints = Self.convertWorkoutEnergy(runningWorkoutSummaryValues)
        let runningPacePoints = Self.convertWorkoutPace(runningWorkoutSummaryValues)
        let runningStatus = statusFor(
            coreMetrics: [runningDurationPoints, runningCountPoints, runningDistancePoints, runningEnergyPoints, runningPacePoints]
        )
        let runningMetrics = [
            metric("跑步总时长", "分钟", runningDurationPoints, accent: "FF7A59"),
            metric("跑步次数", "次", runningCountPoints, accent: "F36F45"),
            metric("跑步距离", "km", runningDistancePoints, accent: "32ADE6"),
            metric("跑步能量", "kcal", runningEnergyPoints, accent: "FFB340"),
            metric("平均配速", "分/公里", runningPacePoints, accent: "8EC5FF", summaryOverride: Self.runningPaceSummary(from: runningPacePoints))
        ]
        details[.runningDynamics] = makeDetail(
            category: .runningDynamics,
            status: runningStatus,
            headerSummary: Self.runningHeaderSummary(
                durationPoints: runningDurationPoints,
                countPoints: runningCountPoints,
                distancePoints: runningDistancePoints
            ),
            metrics: runningMetrics
        )

        let cyclingDurationPoints = Self.convertWorkoutSummaries(cyclingWorkoutSummaryValues)
        let cyclingCountPoints = Self.convertWorkoutCounts(cyclingWorkoutSummaryValues)
        let cyclingDistancePoints = Self.convertWorkoutDistances(cyclingWorkoutSummaryValues)
        let cyclingEnergyPoints = Self.convertWorkoutEnergy(cyclingWorkoutSummaryValues)
        let cyclingSpeedPoints = Self.convertWorkoutSpeed(cyclingWorkoutSummaryValues)
        let cyclingStatus = statusFor(
            coreMetrics: [cyclingDurationPoints, cyclingCountPoints, cyclingDistancePoints, cyclingEnergyPoints, cyclingSpeedPoints]
        )

        let cyclingMetrics = [
            metric("骑行总时长", "分钟", cyclingDurationPoints, accent: "32ADE6"),
            metric("骑行次数", "次", cyclingCountPoints, accent: "27C2FF"),
            metric("骑行距离", "km", cyclingDistancePoints, accent: "5DADE2"),
            metric("骑行能量", "kcal", cyclingEnergyPoints, accent: "FFB340"),
            metric("平均速度", "km/h", cyclingSpeedPoints, accent: "7CD992", summaryOverride: Self.cyclingSpeedSummary(from: cyclingSpeedPoints))
        ]

        details[.cyclingStats] = makeDetail(
            category: .cyclingStats,
            status: cyclingStatus,
            headerSummary: Self.cyclingHeaderSummary(
                durationPoints: cyclingDurationPoints,
                countPoints: cyclingCountPoints,
                distancePoints: cyclingDistancePoints
            ),
            metrics: cyclingMetrics
        )

        let swimmingDurationPoints = Self.convertWorkoutSummaries(swimmingWorkoutSummaryValues)
        let swimmingCountPoints = Self.convertWorkoutCounts(swimmingWorkoutSummaryValues)
        let swimmingDistancePoints = Self.convertWorkoutDistances(swimmingWorkoutSummaryValues)
        let swimmingEnergyPoints = Self.convertWorkoutEnergy(swimmingWorkoutSummaryValues)
        let swimmingSpeedPoints = Self.convertWorkoutSpeed(swimmingWorkoutSummaryValues)
        let swimmingStatus = statusFor(
            coreMetrics: [swimmingDurationPoints, swimmingCountPoints, swimmingDistancePoints, swimmingEnergyPoints, swimmingSpeedPoints]
        )

        let swimmingMetrics = [
            metric("游泳总时长", "分钟", swimmingDurationPoints, accent: "27C2FF"),
            metric("游泳次数", "次", swimmingCountPoints, accent: "32ADE6"),
            metric("游泳距离", "km", swimmingDistancePoints, accent: "5DADE2"),
            metric("游泳能量", "kcal", swimmingEnergyPoints, accent: "FFB340"),
            metric("平均速度", "km/h", swimmingSpeedPoints, accent: "7CD992", summaryOverride: Self.cyclingSpeedSummary(from: swimmingSpeedPoints))
        ]

        details[.swimmingWater] = makeDetail(
            category: .swimmingWater,
            status: swimmingStatus,
            headerSummary: Self.swimmingHeaderSummary(
                durationPoints: swimmingDurationPoints,
                countPoints: swimmingCountPoints,
                distancePoints: swimmingDistancePoints
            ),
            metrics: swimmingMetrics
        )

        let workoutDurationPoints = Self.convertWorkoutSummaries(workoutSummaryValues)
        let workoutCountPoints = Self.convertWorkoutCounts(workoutSummaryValues)
        let workoutTitle = Self.dominantWorkoutTitle(from: workoutSummaryValues)
        let workoutsTrainingStatus = statusFor(
            coreMetrics: [workoutDurationPoints, workoutCountPoints]
        )
        let workoutsTrainingHeaderSummary: String
        if workoutDurationPoints.isEmpty && workoutCountPoints.isEmpty {
            workoutsTrainingHeaderSummary = workoutSummaryValues.isEmpty
            ? "当前区间还没有健身记录，继续记录后这里会形成你的健身节律。"
            : "训练记录已进入趋势页，但当前区间没有可聚合的时长和次数点位，建议检查筛选范围。"
        } else if workoutSummaryValues.count <= 1 {
            workoutsTrainingHeaderSummary = "当前只有少量训练样本，先把训练时长和训练次数放在一起看，观察最近节奏是否连续。"
        } else {
            workoutsTrainingHeaderSummary = "先用训练时长和训练次数观察整体运动节奏，当前主训练类型\(workoutTitle)。"
        }

        details[.workoutsTraining] = makeDetail(
            category: .workoutsTraining,
            status: workoutsTrainingStatus,
            headerSummary: workoutsTrainingHeaderSummary,
            metrics: [
                metric("训练总时长", "分钟", workoutDurationPoints, accent: "7CD992"),
                metric("训练次数", "次", workoutCountPoints, accent: "32ADE6")
            ]
        )

        let environmentSensesStatus = statusFor(
            coreMetrics: [daylightPoints, environmentalAudioPoints, headphoneExposureLevelPoints, headphoneExposureDurationPoints]
        )

        details[.environmentSenses] = makeDetail(
            category: .environmentSenses,
            status: environmentSensesStatus,
            headerSummary: environmentSensesStatus == .noData
                ? "当前区间还没有环境样本，继续记录后这里会形成环境感官趋势。"
                : summaryText(prefix: "把日照和耳机收听分开看，更容易判断自然输入与听觉暴露是不是在各自累积。", points: [daylightPoints, environmentalAudioPoints, headphoneExposureDurationPoints]),
            metrics: [
                metric("日照时长", "分钟", daylightPoints, accent: "FFB340", summaryOverride: daylightPoints.isEmpty ? "暂无记录" : nil),
                metric("环境音量", "dB", environmentalAudioPoints, accent: "75C7E8", summaryOverride: environmentalAudioPoints.isEmpty ? "暂无记录" : nil),
                metric("耳机暴露量", "dB", headphoneExposureLevelPoints, accent: "B58AF3", summaryOverride: headphoneExposureLevelPoints.isEmpty ? "暂无记录" : nil),
                metric(
                    "耳机暴露时长",
                    "分钟",
                    headphoneExposureDurationPoints,
                    accent: "FF8F1C",
                    statusOverride: Self.metricStatusForPositiveValues(in: headphoneExposureDurationPoints),
                    summaryOverride: headphoneExposureDurationPoints.allSatisfy { $0.value <= 0 } ? "暂无记录" : nil
                )
            ]
        )

        let hydrationPoints = Self.mergeDailyHabitValues(
            remoteValues: dailyHabitAnalyticsValues,
            metric: \.water_intake_ml,
            localValue: { Double($0.waterMl) },
            range: range
        )
        let hydrationCompletionPoints = Self.mergeDailyHabitCompletionRates(
            remoteValues: dailyHabitAnalyticsValues,
            localRecords: ActionRecordStore.shared.allRecords(),
            defaultTargetMl: AppGroupManager.shared.getWaterTargetMl() ?? 2000,
            range: range
        )
        let caffeineResidualPoints = Self.mergeDailyHabitValues(
            remoteValues: dailyHabitAnalyticsValues,
            metric: \.caffeine_remained_mg,
            localValue: { Double($0.caffeineMg) },
            range: range
        )
        let mealRecords = DrinkExperienceStore.shared.allMealRecords()
        let mealCaloriePoints = Self.mealRecognitionSeries(
            records: mealRecords,
            range: range,
            value: { Double(max(0, $0.estimatedCalories)) },
            aggregation: .sum
        )
        let mealCountPoints = Self.mealRecognitionSeries(
            records: mealRecords,
            range: range,
            value: { _ in 1 },
            aggregation: .sum
        )
        let nutritionHydrationStatus = statusFor(
            coreMetrics: [mealCaloriePoints, mealCountPoints, hydrationPoints, hydrationCompletionPoints, caffeineResidualPoints]
        )

        details[.nutritionHydration] = makeDetail(
            category: .nutritionHydration,
            status: nutritionHydrationStatus,
            headerSummary: Self.nutritionHeaderSummary(
                range: range,
                mealCaloriePoints: mealCaloriePoints,
                mealCountPoints: mealCountPoints,
                hydrationPoints: hydrationPoints,
                completionPoints: hydrationCompletionPoints,
                caffeinePoints: caffeineResidualPoints
            ),
            metrics: [
                metric("餐食热量", "kcal", mealCaloriePoints, accent: "E57B3C"),
                metric("餐食记录", "餐", mealCountPoints, accent: "287A58"),
                metric("饮水量", "ml", hydrationPoints, accent: "32ADE6"),
                metric("饮水达标率", "%", hydrationCompletionPoints, accent: "7CD992", summaryOverride: Self.percentSummary(from: hydrationCompletionPoints)),
                metric("咖啡因残留", "mg", caffeineResidualPoints, accent: "A2845E")
            ]
        )

        let mindfulnessMentalStatus = statusFor(
            coreMetrics: [mindfulPoints, stateOfMindPoints]
        )

        details[.mindfulnessMental] = makeDetail(
            category: .mindfulnessMental,
            status: mindfulnessMentalStatus,
            headerSummary: summaryText(prefix: "把正念时长和心理状态放在一起看，更容易判断调节投入和心理波动是不是同步变化。", points: [mindfulPoints, stateOfMindPoints]),
            metrics: [
                metric("正念时长", "分钟", mindfulPoints, accent: "5E5CE6"),
                metric("心理状态", "分", stateOfMindPoints, accent: "C98BFF")
            ]
        )

        let allSymptomRecords = SelfObservationStore.shared.allRecords().filter(\.isSymptomObservation)
        let symptomRecordPoints = Self.symptomRecordSeries(
            records: allSymptomRecords,
            range: range,
            value: { _ in 1 },
            aggregation: .sum
        )
        let symptomSeverityPoints = Self.symptomRecordSeries(
            records: allSymptomRecords,
            range: range,
            value: { Double($0.symptomSeverity) },
            aggregation: .average
        )
        let allMedicationEntries = MedicationStore.shared.allEntries()
        let medicationEntryPoints = Self.medicationEntrySeries(entries: allMedicationEntries, range: range)
        let prescriptionRecords = MedicationPrescriptionStore.shared.allRecords()
        let symptomsIllnessStatus: TrendCategoryStatus
        if !symptomRecordPoints.isEmpty || !medicationEntryPoints.isEmpty {
            symptomsIllnessStatus = .ready
        } else if !allSymptomRecords.isEmpty || !allMedicationEntries.isEmpty || !prescriptionRecords.isEmpty {
            symptomsIllnessStatus = .partial
        } else {
            symptomsIllnessStatus = .noData
        }

        details[.symptomsIllness] = makeDetail(
            category: .symptomsIllness,
            status: symptomsIllnessStatus,
            headerSummary: Self.symptomsIllnessHeaderSummary(
                range: range,
                symptomRecords: allSymptomRecords,
                medicationEntryPoints: medicationEntryPoints,
                prescriptionCount: prescriptionRecords.count
            ),
            metrics: [
                metric("症状记录", "次", symptomRecordPoints, accent: "C98BFF"),
                metric("症状强度", "级", symptomSeverityPoints, accent: "F3A53B"),
                metric("用药记录", "次", medicationEntryPoints, accent: "5DADE2")
            ]
        )

        let orderedCategories = TrendCategoryID.allCases
        let cards = orderedCategories.compactMap { category -> TrendCategoryCardModel? in
            guard let detail = details[category] else { return nil }
            let primaryValueText: String = {
                if category == .bodyMetrics {
                    return detail.metrics.first?.summary ?? detail.status.title
                }
                return detail.metrics.first?.summary ?? detail.status.title
            }()
            let highlights: [String] = detail.metrics.prefix(3).compactMap { metric in
                if category == .bodyMetrics {
                    return nil
                }
                return "\(metric.title) · \(metric.summary)"
            }
            return TrendCategoryCardModel(
                category: category,
                status: detail.status,
                primaryValueText: primaryValueText,
                summary: category == .bodyMetrics ? "" : detail.headerSummary,
                highlights: highlights
            )
        }

        return (cards, details)
    }

    /// Trend Detail Heart Rate Series 方法，负责趋势分析展示。用于趋势页面的‘核心心血管日视图小时级取样’
    private func fetchHeartRateSeries(range: TrendsRange) async -> [TimeSeriesPointDouble] {
        if range.isIntraday {
            return (try? await healthKitManager.fetchHourlyStatisticsForToday(
                quantityIdentifier: .heartRate,
                unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                options: .discreteAverage
            )) ?? []
        }
        return (try? await healthKitManager.fetchDailyHeartRateAverages(days: range.windowDays)) ?? []
    }

    /// Trend Detail Resting Heart Rate Series 方法，负责趋势分析展示。用于趋势页面的‘静息心率日视图小时级取样’
    private func fetchRestingHeartRateSeries(range: TrendsRange) async -> [TimeSeriesPointDouble] {
        if range.isIntraday {
            return (try? await healthKitManager.fetchHourlyStatisticsForToday(
                quantityIdentifier: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                options: .discreteAverage
            )) ?? []
        }
        return (try? await healthKitManager.fetchDailyRestingHeartRateAverages(days: range.windowDays)) ?? []
    }

    /// Trend Detail HRV Series 方法，负责趋势分析展示。用于趋势页面的‘睡眠恢复与核心心血管日视图小时级取样’
    private func fetchHRVSeries(range: TrendsRange) async -> [TimeSeriesPointDouble] {
        if range.isIntraday {
            return (try? await healthKitManager.fetchHourlyStatisticsForToday(
                quantityIdentifier: .heartRateVariabilitySDNN,
                unit: HKUnit.secondUnit(with: .milli),
                options: .discreteAverage
            )) ?? []
        }
        return (try? await healthKitManager.fetchDailyHRVAverages(days: range.windowDays)) ?? []
    }

    /// Trend Detail Walking Heart Rate Series 方法，负责趋势分析展示。用于趋势页面的‘步行平均心率日视图小时级取样’
    private func fetchWalkingHeartRateSeries(range: TrendsRange) async -> [TimeSeriesPointDouble] {
        if range.isIntraday {
            return (try? await healthKitManager.fetchHourlyStatisticsForToday(
                quantityIdentifier: .walkingHeartRateAverage,
                unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                options: .discreteAverage
            )) ?? []
        }
        return (try? await healthKitManager.fetchDailyWalkingHeartRateAverages(days: range.windowDays)) ?? []
    }

    private func fetchEnvironmentalAudioPoints(for range: TrendsRange, healthKit hk: HealthKitManager) async -> [TimeSeriesPointDouble] {
        if range.isIntraday {
            return (try? await hk.fetchHourlyStatisticsForToday(
                quantityIdentifier: .environmentalAudioExposure,
                unit: HKUnit.decibelAWeightedSoundPressureLevel(),
                options: .discreteAverage
            )) ?? []
        }
        return (try? await hk.fetchDailyEnvironmentalAudioExposureAverages(days: range.windowDays)) ?? []
    }

    private func fetchHeadphoneExposureLevelPoints(for range: TrendsRange, healthKit hk: HealthKitManager) async -> [TimeSeriesPointDouble] {
        if range.isIntraday {
            return (try? await hk.fetchHourlyStatisticsForToday(
                quantityIdentifier: .headphoneAudioExposure,
                unit: HKUnit.decibelAWeightedSoundPressureLevel(),
                options: .discreteAverage
            )) ?? []
        }
        return (try? await hk.fetchDailyHeadphoneAudioExposureAverages(days: range.windowDays)) ?? []
    }

    private func fetchHeadphoneExposureDurationPoints(for range: TrendsRange, healthKit hk: HealthKitManager) async -> [TimeSeriesPointDouble] {
        if range.isIntraday {
            return (try? await hk.fetchHourlyHeadphoneAudioExposureDurationsForToday()) ?? []
        }
        return (try? await hk.fetchDailyHeadphoneAudioExposureDurations(days: range.windowDays)) ?? []
    }

    private func fetchEnvironmentDaylightPoints(for range: TrendsRange, healthKit hk: HealthKitManager) async -> [TimeSeriesPointDouble] {
        let bounds = environmentDaylightBounds(for: range, anchorDate: Date())
        let interval: DateComponents

        switch range {
        case .day:
            interval = DateComponents(hour: 1)
        case .week, .month:
            interval = DateComponents(day: 1)
        }

        return (try? await hk.fetchTimeInDaylightSeries(
            start: bounds.start,
            end: bounds.end,
            interval: interval
        )) ?? []
    }

    private func environmentDaylightBounds(for range: TrendsRange, anchorDate: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            return (start, end)
        case .week, .month:
            let today = calendar.startOfDay(for: anchorDate)
            let start = calendar.date(byAdding: .day, value: -(range.windowDays - 1), to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
            return (start, end)
        }
    }

    private func fetchStepPoints(range: TrendsRange) async -> [TimeSeriesPointDouble] {
        if range.isIntraday {
            let hourly = (try? await healthKitManager.fetchHourlyStatisticsForToday(
                quantityIdentifier: .stepCount,
                unit: .count(),
                options: .cumulativeSum
            )) ?? []
            if !hourly.isEmpty {
                return hourly
            }
            return (try? await healthKitManager.fetchDailyStepSums(days: 1)) ?? []
        }
        return (try? await healthKitManager.fetchDailyStepSums(days: range.windowDays)) ?? []
    }

    private func fetchWalkingDistancePoints(range: TrendsRange) async -> [TimeSeriesPointDouble] {
        let rawPoints: [TimeSeriesPointDouble]
        if range.isIntraday {
            let hourly = (try? await healthKitManager.fetchHourlyStatisticsForToday(
                quantityIdentifier: .distanceWalkingRunning,
                unit: .meter(),
                options: .cumulativeSum
            )) ?? []
            rawPoints = hourly.isEmpty ? ((try? await healthKitManager.fetchDailyDistanceWalkingRunningSums(days: 1)) ?? []) : hourly
        } else {
            rawPoints = (try? await healthKitManager.fetchDailyDistanceWalkingRunningSums(days: range.windowDays)) ?? []
        }
        return Self.convertMetersToKilometers(rawPoints)
    }

    private func fetchWalkingSpeedSeries(range: TrendsRange) async -> [TimeSeriesPointDouble] {
        if range.isIntraday {
            let hourly = (try? await healthKitManager.fetchHourlyStatisticsForToday(
                quantityIdentifier: .walkingSpeed,
                unit: HKUnit.meter().unitDivided(by: HKUnit.second()),
                options: .discreteAverage
            )) ?? []
            if !hourly.isEmpty {
                return hourly
            }
            return (try? await healthKitManager.fetchDailyWalkingSpeedAverages(days: 1)) ?? []
        }
        return (try? await healthKitManager.fetchDailyWalkingSpeedAverages(days: range.windowDays)) ?? []
    }

    private func fetchDailyHabitAnalytics(days: Int) async -> [DailySleepStressAnalytics] {
        // 本地优先：无自建后端，习惯分析以本机 HealthKit 数据为准。
        []
    }

    private func fetchRemotePeriodSummary(days: Int) async -> PeriodSummary? {
        // 本地优先：无自建后端，周期摘要以本机 PeriodStore 为准。
        nil
    }

    private func mergedPeriodSummary(local: PeriodSummary, remote: PeriodSummary?) -> PeriodSummary {
        guard let remote else { return local }
        PeriodStore.shared.saveRemoteSnapshot(remote)
        let mergedLocal = PeriodStore.shared.summary(days: 365)
        return PeriodSummary(
            current: remote.current ?? mergedLocal.current ?? local.current,
            predictions: remote.predictions ?? mergedLocal.predictions ?? local.predictions,
            overlayRanges: !(remote.overlayRanges ?? []).isEmpty ? remote.overlayRanges : (mergedLocal.overlayRanges ?? local.overlayRanges),
            dayLogs: !(remote.dayLogs ?? []).isEmpty ? remote.dayLogs : (mergedLocal.dayLogs ?? local.dayLogs),
            cycles: !(remote.cycles ?? []).isEmpty ? remote.cycles : (mergedLocal.cycles ?? local.cycles)
        )
    }


    private func makeDetail(
        category: TrendCategoryID,
        status: TrendCategoryStatus,
        headerSummary: String,
        metrics: [TrendCategoryMetricModel],
        sleepStages: [SleepStage] = [],
        sleepClinicalSummary: SleepTrendClinicalSummaryModel? = nil,
        sleepAIInsight: SleepTrendAIInsightModel? = nil,
        sleepCompositeScores: [SleepCompositeScoreBreakdown] = [],
        sleepNightSummaries: [SleepTrendNightSummary] = [],
        sleepCoreMetrics: [TrendCategoryMetricModel] = [],
        sleepRecoveryMetrics: [TrendCategoryMetricModel] = [],
        genericAIInsight: GenericTrendAIInsightModel? = nil,
        mobilityAIInsight: MobilityTrendAIInsightModel? = nil,
        reproductiveDetail: ReproductiveTrendDetailModel? = nil,
        heartECGSummary: HeartECGSummaryModel? = nil,
        heartECGRecords: [HeartECGRecordModel] = [],
        heartClinicalMonitorSummary: HeartClinicalMonitorSummary? = nil
    ) -> TrendCategoryDetailModel {
        let resolvedGenericAIInsight = genericAIInsight ?? Self.buildGenericAIInsight(
            category: category,
            metrics: metrics,
            headerSummary: headerSummary,
            heartECGSummary: heartECGSummary,
            heartClinicalMonitorSummary: heartClinicalMonitorSummary
        )
        return TrendCategoryDetailModel(
            category: category,
            headerSummary: headerSummary,
            metrics: metrics,
            status: status,
            sleepStages: sleepStages,
            sleepClinicalSummary: sleepClinicalSummary,
            sleepAIInsight: sleepAIInsight,
            sleepCompositeScores: sleepCompositeScores,
            sleepNightSummaries: sleepNightSummaries,
            sleepCoreMetrics: sleepCoreMetrics,
            sleepRecoveryMetrics: sleepRecoveryMetrics,
            genericAIInsight: resolvedGenericAIInsight,
            mobilityAIInsight: mobilityAIInsight,
            reproductiveDetail: reproductiveDetail,
            heartECGSummary: heartECGSummary,
            heartECGRecords: heartECGRecords,
            heartClinicalMonitorSummary: heartClinicalMonitorSummary
        )
    }

    private func metric(
        _ title: String,
        _ unit: String,
        _ points: [TimeSeriesPointDouble],
        accent: String,
        statusOverride: TrendCategoryStatus? = nil,
        summaryOverride: String? = nil
    ) -> TrendCategoryMetricModel {
        let status = statusOverride ?? (points.isEmpty ? .noData : .ready)
        let summary = summaryOverride ?? points.last.map { latest in
            if unit == "分/公里" {
                return latest.value.isFinite && latest.value > 0
                    ? TrendMetricValueFormatter.string(for: latest.value, unit: unit)
                    : "暂无"
            }
            return TrendMetricValueFormatter.string(for: latest.value, unit: unit)
        } ?? (title == "训练总时长" || title == "训练次数" ? "暂无记录" : "暂无")
        let isWorkoutMetric = title == "训练总时长" || title == "训练次数"
        return TrendCategoryMetricModel(
            title: title,
            unit: unit,
            points: points,
            secondaryPoints: [],
            status: status,
            emptyMessage: isWorkoutMetric
                ? "当前区间还没有训练样本，继续记录后这里会形成趋势。"
                : "暂无记录，继续同步健康 App 数据后这里会显示趋势。",
            accentHex: accent,
            summary: summary
        )
    }

    private func summaryText(prefix: String, points: [[TimeSeriesPointDouble]]) -> String {
        let dataCount = points.flatMap { $0 }.count
        if dataCount == 0 {
            return String(localized: "继续在健康 App 中记录后，这里会开始形成分类趋势。")
        }
        return prefix
    }


    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()


    private func statusFor(coreMetrics: [[TimeSeriesPointDouble]]) -> TrendCategoryStatus {
        let populatedMetricCount = coreMetrics.count { !$0.isEmpty }
        if populatedMetricCount == coreMetrics.count, !coreMetrics.isEmpty {
            return .ready
        }
        if populatedMetricCount > 0 {
            return .partial
        }
        return .noData
    }
}
