import Foundation
import HealthKit

private struct VO2MaxFeatureSet: Sendable {
    let date: Date
    let actualVO2Max: Double?
    let bodyProfile: VO2MaxBodyProfile
    let restingHeartRate: Double?
    let recentRestingHeartRateBaseline: Double?
    let nightlyHrv: Double?
    let recentNightlyHrvBaseline: Double?
    let nightlyAverageHeartRate: Double?
    let sleepScore: Int?
    let walkingInputs: [WalkingFitnessInput]
    let runningInputs: [RunningFitnessInput]
    let heartRateRecoveryOneMinute: Double?
}

private struct VO2MaxRawAssessment: Sendable {
    let date: Date
    let value: Double
    let source: VO2MaxSource
    let age: Int?
    let sex: String?
    let drivers: [VO2MaxDriver]
    let components: VO2MaxComponentBreakdown
    let inputs: VO2MaxInputCoverage
    let confidenceBreakdown: VO2MaxConfidenceBreakdown
}

final class VO2MaxEngine {
    static let shared = VO2MaxEngine()
    static let minimumSmoothingContextDays = 31

    private let healthKit: HealthKitManager
    private let store: VO2MaxAssessmentStore
    private let calendar: Calendar

    init(
        healthKit: HealthKitManager = .shared,
        store: VO2MaxAssessmentStore = VO2MaxAssessmentStore(),
        calendar: Calendar = .current
    ) {
        self.healthKit = healthKit
        self.store = store
        self.calendar = calendar
    }

    func assess(on date: Date = Date()) async -> VO2MaxDailyAssessment? {
        let series = await assessSeries(days: 1, endDate: date)
        return series.last { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func assessSeries(days: Int = 30, endDate: Date = Date()) async -> [VO2MaxDailyAssessment] {
        let requestedDays = max(days, 1)
        let calculationDays = max(requestedDays, Self.minimumSmoothingContextDays)
        let cached = store.load()
        let raw = await rawAssessments(days: calculationDays, endDate: endDate)

        if !raw.isEmpty {
            let fresh = smooth(raw, previousAssessments: cached)
            let cachedContext = assessmentsInWindow(cached, days: calculationDays, endDate: endDate)
            let mergedContext = mergedAssessments(cached: cachedContext, fresh: fresh)
            store.save(applyTrend(to: mergedContext))
        }

        return assessmentsInWindow(store.load(), days: requestedDays, endDate: endDate)
    }

    func cachedAssessments() -> [VO2MaxDailyAssessment] {
        store.load()
    }

    func assessSessions(on date: Date = Date()) async -> [VO2MaxSessionAssessment] {
        let bodyProfile = await healthKit.fetchBodyProfile()
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let historyStart = calendar.date(byAdding: .day, value: -30, to: day) ?? day

        async let actualSeriesTask = try? healthKit.fetchVo2MaxSamples(on: day)
        async let restingSeriesTask = try? healthKit.fetchDailyRestingHeartRateAverages(days: 30, endDate: day)
        async let walkingSpeedSeriesTask = try? healthKit.fetchDailyWalkingSpeedAverages(days: 30, endDate: day)
        async let walkingHeartRateSeriesTask = try? healthKit.fetchDailyWalkingHeartRateAverages(days: 30, endDate: day)
        async let nightlyHrvSeriesTask = try? healthKit.fetchNightlyHRVAverages(days: 14, endDate: day)
        async let nightlyHeartRateSeriesTask = try? healthKit.fetchNightlyHeartRateAverages(days: 14, endDate: day)
        async let sleepScoreSeriesTask = try? healthKit.fetchDailySleepScoreSeries(days: 30, endDate: day)
        async let runningWorkoutsTask = try? healthKit.fetchRunningWorkouts(start: historyStart, end: nextDay)
        async let outdoorWalkingWorkoutsTask = try? healthKit.fetchOutdoorWalkingWorkouts(start: historyStart, end: nextDay)

        let actualSeries = await actualSeriesTask ?? []
        let restingSeries = await restingSeriesTask ?? []
        let walkingSpeedSeries = await walkingSpeedSeriesTask ?? []
        let walkingHeartRateSeries = await walkingHeartRateSeriesTask ?? []
        let nightlyHrvSeries = await nightlyHrvSeriesTask ?? []
        let nightlyHeartRateSeries = await nightlyHeartRateSeriesTask ?? []
        let sleepScoreSeries = await sleepScoreSeriesTask ?? []
        let runningWorkouts = await runningWorkoutsTask ?? []
        let outdoorWalkingWorkouts = await outdoorWalkingWorkoutsTask ?? []

        let restingByDay = dictionaryByDay(restingSeries)
        let walkingSpeedByDay = dictionaryByDay(walkingSpeedSeries)
        let walkingHeartRateByDay = dictionaryByDay(walkingHeartRateSeries)
        let nightlyHrvByDay = dictionaryByDay(nightlyHrvSeries.map {
            TimeSeriesPointDouble(timestamp: Int64($0.date.timeIntervalSince1970), value: $0.avgMs)
        })
        let nightlyHeartRateByDay = dictionaryByDay(nightlyHeartRateSeries.map {
            TimeSeriesPointDouble(timestamp: Int64($0.date.timeIntervalSince1970), value: $0.averageValue)
        })
        let sleepScoreByDay = dictionaryByDay(sleepScoreSeries)
        let allWorkouts = (runningWorkouts + outdoorWalkingWorkouts).sorted { $0.startDate < $1.startDate }
        let workouts = allWorkouts.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
        let workoutsByDay = Dictionary(grouping: allWorkouts) { calendar.startOfDay(for: $0.startDate) }

        guard !workouts.isEmpty else {
            return actualSessionAssessments(from: actualSeries, bodyProfile: bodyProfile)
        }

        let recentRestingBaseline = baselineValue(before: day, in: restingByDay, limit: 30)
        let recentNightlyHrvBaseline = baselineValue(before: day, in: nightlyHrvByDay, limit: 14)
        let restingHeartRate = restingByDay[day].flatMap { $0 > 0 ? $0 : nil }
        let nightlyHrv = nightlyHrvByDay[day].flatMap { $0 > 0 ? $0 : nil }
        let nightlyAverageHeartRate = nightlyHeartRateByDay[day].flatMap { $0 > 0 ? $0 : nil }
        let sleepScore = sleepScoreByDay[day].flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        let walkingBaseline = walkingBaselineRatio(
            before: day,
            walkingSpeedByDay: walkingSpeedByDay,
            walkingHeartRateByDay: walkingHeartRateByDay
        )
        let runningBaseline = runningBaselineEfficiency(before: day, workoutsByDay: workoutsByDay)

        let workoutAssessments: [VO2MaxSessionAssessment] = workouts.compactMap { workout in
            let actualVO2 = actualVO2(near: workout, samples: actualSeries)
            let runningInput: RunningFitnessInput? = {
                guard workout.activityType == .running else { return nil }
                guard let pace = workout.paceSecondsPerKilometer,
                      let averageHeartRate = workout.averageHeartRate,
                      let distance = workout.distanceKilometers else { return nil }
                return RunningFitnessInput(
                    paceSecondsPerKm: pace,
                    averageHeartRate: averageHeartRate,
                    distanceKilometers: distance,
                    durationMinutes: workout.durationMinutes,
                    baselineEfficiency: runningBaseline
                )
            }()

            let walkingInput: WalkingFitnessInput? = {
                guard workout.activityType == .walking || workout.activityType == .hiking,
                      let distance = workout.distanceKilometers,
                      workout.durationMinutes > 0 else { return nil }
                let speed = distance * 1_000 / (workout.durationMinutes * 60)
                return WalkingFitnessInput(
                    speedMps: speed,
                    paceSecondsPerKm: workout.paceSecondsPerKilometer,
                    averageHeartRate: workout.averageHeartRate,
                    restingHeartRate: restingHeartRate ?? recentRestingBaseline,
                    distanceKilometers: distance,
                    durationMinutes: workout.durationMinutes,
                    baselineRatio: walkingBaseline,
                    age: bodyProfile.age,
                    sex: bodyProfile.sex
                )
            }()

            if runningInput == nil && walkingInput == nil && actualVO2 == nil {
                return nil
            }

            let rhrComponent = rhrComponent(
                restingHeartRate: restingHeartRate,
                baseline: recentRestingBaseline,
                age: bodyProfile.age,
                sex: bodyProfile.sex
            )
            let hrvComponent = hrvComponent(
                nightlyHrv: nightlyHrv,
                baseline: recentNightlyHrvBaseline
            )
            let walkingComponent = walkingInput.flatMap { walkingFitnessIndex(input: $0) }
            let runningComponent = runningInput.flatMap { aggregatedRunningFitness(inputs: [$0]) }
            let recoveryComponent = recoveryFitnessIndex(
                input: RecoveryFitnessInput(
                    sleepScore: sleepScore,
                    nightlyHrv: nightlyHrv,
                    recentNightlyHrvBaseline: recentNightlyHrvBaseline,
                    nightlyAverageHeartRate: nightlyAverageHeartRate,
                    heartRateRecoveryOneMinute: workout.heartRateRecoveryOneMinute
                )
            )

            let inputs = VO2MaxInputCoverage(
                actualVO2: actualVO2 != nil,
                rhr: restingHeartRate != nil,
                hrv: nightlyHrv != nil,
                walking: walkingComponent != nil,
                running: runningComponent != nil,
                recovery: recoveryComponent != nil
            )

            guard VO2MaxRules.hasMinimumEvidence(
                actualVO2: actualVO2,
                hasRestingHeartRate: inputs.rhr,
                hasHrv: inputs.hrv,
                hasWalking: inputs.walking,
                hasRunning: inputs.running,
                hasRecovery: inputs.recovery
            ) else { return nil }
            let componentScore = VO2MaxRules.weightedScore(
                rhr: rhrComponent,
                hrv: hrvComponent,
                walking: walkingComponent,
                running: runningComponent,
                recovery: recoveryComponent
            )
            guard let mappingScore = componentScore ?? (inputs.actualVO2 ? 50 : nil) else { return nil }

            let confidence = confidenceBreakdown(
                actualVO2: actualVO2,
                inputs: inputs,
                runningSampleCount: runningInput == nil ? 0 : 1,
                walkingSampleCount: walkingInput.map(hasWalkingHeartRateContext) == true ? 1 : 0
            )

            let estimatedValue = mapScoreToVO2Max(
                score: mappingScore,
                profile: bodyProfile,
                runningComponent: runningComponent,
                walkingComponent: walkingComponent
            )
            guard let resolution = VO2MaxRules.resolveValue(
                actualVO2: actualVO2,
                estimatedValue: estimatedValue,
                hasInterpretiveContext: inputs.running || inputs.walking || inputs.recovery
            ) else { return nil }
            let source = resolution.source
            let resolvedValue = resolution.value

            let featureSet = VO2MaxFeatureSet(
                date: workout.startDate,
                actualVO2Max: actualVO2,
                bodyProfile: bodyProfile,
                restingHeartRate: restingHeartRate,
                recentRestingHeartRateBaseline: recentRestingBaseline,
                nightlyHrv: nightlyHrv,
                recentNightlyHrvBaseline: recentNightlyHrvBaseline,
                nightlyAverageHeartRate: nightlyAverageHeartRate,
                sleepScore: sleepScore,
                walkingInputs: walkingInput.map { [$0] } ?? [],
                runningInputs: runningInput.map { [$0] } ?? [],
                heartRateRecoveryOneMinute: workout.heartRateRecoveryOneMinute
            )
            let drivers = buildDrivers(
                rhrComponent: rhrComponent,
                hrvComponent: hrvComponent,
                walkingComponent: walkingComponent,
                runningComponent: runningComponent,
                recoveryComponent: recoveryComponent,
                inputs: featureSet
            )
            let level = fitnessLevel(value: resolvedValue, age: bodyProfile.age, sex: bodyProfile.sex)

            return VO2MaxSessionAssessment(
                date: workout.startDate,
                value: resolvedValue,
                source: source,
                confidence: confidence.finalScore,
                fitnessLevel: level,
                drivers: drivers,
                components: VO2MaxComponentBreakdown(
                    rhrComponent: rhrComponent,
                    hrvComponent: hrvComponent,
                    walkingEfficiencyComponent: walkingComponent,
                    runningEfficiencyComponent: runningComponent,
                    recoveryComponent: recoveryComponent,
                    finalWeightedScore: componentScore ?? 0
                ),
                inputs: inputs,
                confidenceBreakdown: confidence,
                summaryText: makeSummary(
                    value: resolvedValue,
                    source: source,
                    level: level,
                    confidence: confidence.finalScore,
                    drivers: drivers
                ),
                activityType: workout.activityType
            )
        }

        let standaloneActualAssessments = actualSessionAssessments(
            from: unassociatedActualSamples(samples: actualSeries, workouts: workouts),
            bodyProfile: bodyProfile
        )
        return (workoutAssessments + standaloneActualAssessments)
            .sorted { $0.date < $1.date }
    }

    private func rawAssessments(days: Int, endDate: Date) async -> [VO2MaxRawAssessment] {
        let historyDays = days + 30
        let workoutEnd = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: endDate)
        ) ?? endDate
        async let bodyProfileTask = healthKit.fetchBodyProfile()
        async let actualSeriesTask = try? healthKit.fetchDailyVo2MaxAverages(days: days, endDate: endDate)
        async let restingSeriesTask = try? healthKit.fetchDailyRestingHeartRateAverages(days: historyDays, endDate: endDate)
        async let walkingSpeedSeriesTask = try? healthKit.fetchDailyWalkingSpeedAverages(days: historyDays, endDate: endDate)
        async let walkingHeartRateSeriesTask = try? healthKit.fetchDailyWalkingHeartRateAverages(days: historyDays, endDate: endDate)
        async let nightlyHrvSeriesTask = try? healthKit.fetchNightlyHRVAverages(days: days + 14, endDate: endDate)
        async let nightlyHeartRateSeriesTask = try? healthKit.fetchNightlyHeartRateAverages(days: days + 14, endDate: endDate)
        async let sleepScoreSeriesTask = try? healthKit.fetchDailySleepScoreSeries(days: historyDays, endDate: endDate)
        async let runningWorkoutsTask = try? healthKit.fetchRunningWorkouts(start: startDate(days: historyDays, endDate: endDate), end: workoutEnd)
        async let outdoorWalkingWorkoutsTask = try? healthKit.fetchOutdoorWalkingWorkouts(start: startDate(days: historyDays, endDate: endDate), end: workoutEnd)

        let bodyProfile = await bodyProfileTask
        let actualSeries = await actualSeriesTask ?? []
        let restingSeries = await restingSeriesTask ?? []
        let walkingSpeedSeries = await walkingSpeedSeriesTask ?? []
        let walkingHeartRateSeries = await walkingHeartRateSeriesTask ?? []
        let nightlyHrvSeries = await nightlyHrvSeriesTask ?? []
        let nightlyHeartRateSeries = await nightlyHeartRateSeriesTask ?? []
        let sleepScoreSeries = await sleepScoreSeriesTask ?? []
        let runningWorkouts = await runningWorkoutsTask ?? []
        let outdoorWalkingWorkouts = await outdoorWalkingWorkoutsTask ?? []

        let actualByDay = dictionaryByDay(actualSeries)
        let restingByDay = dictionaryByDay(restingSeries)
        let walkingSpeedByDay = dictionaryByDay(walkingSpeedSeries)
        let walkingHeartRateByDay = dictionaryByDay(walkingHeartRateSeries)
        let nightlyHrvByDay = dictionaryByDay(nightlyHrvSeries.map {
            TimeSeriesPointDouble(timestamp: Int64($0.date.timeIntervalSince1970), value: $0.avgMs)
        })
        let nightlyHeartRateByDay = dictionaryByDay(nightlyHeartRateSeries.map {
            TimeSeriesPointDouble(timestamp: Int64($0.date.timeIntervalSince1970), value: $0.averageValue)
        })
        let sleepScoreByDay = dictionaryByDay(sleepScoreSeries)
        let workoutsByDay = Dictionary(grouping: runningWorkouts + outdoorWalkingWorkouts) { calendar.startOfDay(for: $0.startDate) }

        let dateWindow = strideDays(days: days, endDate: endDate)
        var results: [VO2MaxRawAssessment] = []
        results.reserveCapacity(dateWindow.count)

        for day in dateWindow {
            let normalizedDay = calendar.startOfDay(for: day)
            let featureSet = buildFeatureSet(
                day: normalizedDay,
                bodyProfile: bodyProfile,
                actualByDay: actualByDay,
                restingByDay: restingByDay,
                walkingSpeedByDay: walkingSpeedByDay,
                walkingHeartRateByDay: walkingHeartRateByDay,
                nightlyHrvByDay: nightlyHrvByDay,
                nightlyHeartRateByDay: nightlyHeartRateByDay,
                sleepScoreByDay: sleepScoreByDay,
                workoutsByDay: workoutsByDay
            )
            if let assessment = estimate(featureSet) {
                results.append(assessment)
            }
        }

        return results.sorted { $0.date < $1.date }
    }

    private func estimate(_ featureSet: VO2MaxFeatureSet) -> VO2MaxRawAssessment? {
        let rhrComponent = rhrComponent(
            restingHeartRate: featureSet.restingHeartRate,
            baseline: featureSet.recentRestingHeartRateBaseline,
            age: featureSet.bodyProfile.age,
            sex: featureSet.bodyProfile.sex
        )
        let hrvComponent = hrvComponent(
            nightlyHrv: featureSet.nightlyHrv,
            baseline: featureSet.recentNightlyHrvBaseline
        )
        let walkingComponent = aggregatedWalkingFitness(inputs: featureSet.walkingInputs)
        let runningComponent = aggregatedRunningFitness(inputs: featureSet.runningInputs)
        let recoveryComponent = recoveryFitnessIndex(
            input: RecoveryFitnessInput(
                sleepScore: featureSet.sleepScore,
                nightlyHrv: featureSet.nightlyHrv,
                recentNightlyHrvBaseline: featureSet.recentNightlyHrvBaseline,
                nightlyAverageHeartRate: featureSet.nightlyAverageHeartRate,
                heartRateRecoveryOneMinute: featureSet.heartRateRecoveryOneMinute
            )
        )

        let inputs = VO2MaxInputCoverage(
            actualVO2: VO2MaxRules.validActual(featureSet.actualVO2Max) != nil,
            rhr: featureSet.restingHeartRate != nil,
            hrv: featureSet.nightlyHrv != nil,
            walking: walkingComponent != nil,
            running: runningComponent != nil,
            recovery: recoveryComponent != nil
        )

        guard VO2MaxRules.hasMinimumEvidence(
            actualVO2: featureSet.actualVO2Max,
            hasRestingHeartRate: inputs.rhr,
            hasHrv: inputs.hrv,
            hasWalking: inputs.walking,
            hasRunning: inputs.running,
            hasRecovery: inputs.recovery
        ) else { return nil }
        let componentScore = VO2MaxRules.weightedScore(
            rhr: rhrComponent,
            hrv: hrvComponent,
            walking: walkingComponent,
            running: runningComponent,
            recovery: recoveryComponent
        )
        guard let mappingScore = componentScore ?? (inputs.actualVO2 ? 50 : nil) else { return nil }

        let confidenceBreakdown = confidenceBreakdown(
            actualVO2: featureSet.actualVO2Max,
            inputs: inputs,
            runningSampleCount: featureSet.runningInputs.count,
            walkingSampleCount: featureSet.walkingInputs.filter(hasWalkingHeartRateContext).count
        )

        let estimatedValue = mapScoreToVO2Max(
            score: mappingScore,
            profile: featureSet.bodyProfile,
            runningComponent: runningComponent,
            walkingComponent: walkingComponent
        )
        guard let resolution = VO2MaxRules.resolveValue(
            actualVO2: featureSet.actualVO2Max,
            estimatedValue: estimatedValue,
            hasInterpretiveContext: inputs.running || inputs.walking || inputs.recovery
        ) else { return nil }
        let source = resolution.source
        let resolvedValue = resolution.value

        let drivers = buildDrivers(
            rhrComponent: rhrComponent,
            hrvComponent: hrvComponent,
            walkingComponent: walkingComponent,
            runningComponent: runningComponent,
            recoveryComponent: recoveryComponent,
            inputs: featureSet
        )

        return VO2MaxRawAssessment(
            date: featureSet.date,
            value: resolvedValue,
            source: source,
            age: featureSet.bodyProfile.age,
            sex: featureSet.bodyProfile.sex,
            drivers: drivers,
            components: VO2MaxComponentBreakdown(
                rhrComponent: rhrComponent,
                hrvComponent: hrvComponent,
                walkingEfficiencyComponent: walkingComponent,
                runningEfficiencyComponent: runningComponent,
                recoveryComponent: recoveryComponent,
                finalWeightedScore: componentScore ?? 0
            ),
            inputs: inputs,
            confidenceBreakdown: confidenceBreakdown
        )
    }

    private func buildFeatureSet(
        day: Date,
        bodyProfile: VO2MaxBodyProfile,
        actualByDay: [Date: Double],
        restingByDay: [Date: Double],
        walkingSpeedByDay: [Date: Double],
        walkingHeartRateByDay: [Date: Double],
        nightlyHrvByDay: [Date: Double],
        nightlyHeartRateByDay: [Date: Double],
        sleepScoreByDay: [Date: Double],
        workoutsByDay: [Date: [VO2MaxWorkoutSample]]
    ) -> VO2MaxFeatureSet {
        let recentRestingBaseline = baselineValue(before: day, in: restingByDay, limit: 30)
        let recentNightlyHrvBaseline = baselineValue(before: day, in: nightlyHrvByDay, limit: 14)

        let walkingInputs = walkingInputs(for: day, restingByDay: restingByDay, walkingSpeedByDay: walkingSpeedByDay, walkingHeartRateByDay: walkingHeartRateByDay, bodyProfile: bodyProfile)
        let runningInputs = runningInputs(for: day, workoutsByDay: workoutsByDay)
        let hrr = latestHeartRateRecovery(for: day, workoutsByDay: workoutsByDay)

        return VO2MaxFeatureSet(
            date: day,
            actualVO2Max: VO2MaxRules.validActual(actualByDay[day]),
            bodyProfile: bodyProfile,
            restingHeartRate: restingByDay[day].flatMap { $0 > 0 ? $0 : nil },
            recentRestingHeartRateBaseline: recentRestingBaseline,
            nightlyHrv: nightlyHrvByDay[day].flatMap { $0 > 0 ? $0 : nil },
            recentNightlyHrvBaseline: recentNightlyHrvBaseline,
            nightlyAverageHeartRate: nightlyHeartRateByDay[day].flatMap { $0 > 0 ? $0 : nil },
            sleepScore: sleepScoreByDay[day].flatMap { $0 > 0 ? Int($0.rounded()) : nil },
            walkingInputs: walkingInputs,
            runningInputs: runningInputs,
            heartRateRecoveryOneMinute: hrr
        )
    }

    private func mapScoreToVO2Max(
        score: Double,
        profile: VO2MaxBodyProfile,
        runningComponent: Double?,
        walkingComponent: Double?
    ) -> Double {
        let base = 22.0 + score * 0.28
        let sexBonus: Double
        switch profile.sex {
        case "男":
            sexBonus = 1.2
        case "女":
            sexBonus = -0.4
        default:
            sexBonus = 0
        }

        let agePenalty: Double
        if let age = profile.age {
            agePenalty = max(0, Double(age - 30) * 0.08)
        } else {
            agePenalty = 0.6
        }

        let sizeAdjustment = bodySizeAdjustment(heightCm: profile.heightCm, weightKg: profile.weightKg)
        let runningBonus = runningComponent.map { ($0 - 50) * 0.05 } ?? 0
        let walkingBonus = walkingComponent.map { ($0 - 50) * 0.03 } ?? 0

        return roundToOneDecimal(clamp(base + sexBonus - agePenalty + sizeAdjustment + runningBonus + walkingBonus, lower: 18, upper: 65))
    }

    private func fitnessLevel(value: Double, age: Int?, sex: String?) -> VO2MaxFitnessLevel {
        VO2MaxRules.fitnessLevel(value: value, age: age, sex: sex)
    }

    private func confidenceBreakdown(
        actualVO2: Double?,
        inputs: VO2MaxInputCoverage,
        runningSampleCount: Int,
        walkingSampleCount: Int
    ) -> VO2MaxConfidenceBreakdown {
        VO2MaxRules.confidenceBreakdown(
            actualVO2: actualVO2,
            inputs: inputs,
            runningSampleCount: runningSampleCount,
            walkingSampleCount: walkingSampleCount
        )
    }

    private func buildDrivers(
        rhrComponent: Double?,
        hrvComponent: Double?,
        walkingComponent: Double?,
        runningComponent: Double?,
        recoveryComponent: Double?,
        inputs: VO2MaxFeatureSet
    ) -> [VO2MaxDriver] {
        var drivers: [VO2MaxDriver] = []

        if let runningComponent {
            let direction = VO2MaxRules.driverDirection(for: runningComponent)
            drivers.append(
                VO2MaxDriver(
                    title: "跑步效率",
                    direction: direction,
                    impact: Int(abs(runningComponent - 50).rounded()),
                    explanation: directionalExplanation(
                        direction,
                        positive: "最近跑步配速与心率配合更高效，是当前 VO₂ Max 的主要加分项。",
                        neutral: "最近跑步配速与心率成本接近个人基线，对当前估算影响较小。",
                        negative: "最近跑步配速相对心率成本偏高，拖住了 VO₂ Max 的估算上限。"
                    )
                )
            )
        }

        if let walkingComponent, drivers.count < 3 {
            let direction = VO2MaxRules.driverDirection(for: walkingComponent)
            drivers.append(
                VO2MaxDriver(
                    title: "步行效率",
                    direction: direction,
                    impact: Int(abs(walkingComponent - 50).rounded()),
                    explanation: directionalExplanation(
                        direction,
                        positive: "同等步行速度下心率负担较低，说明基础有氧效率不错。",
                        neutral: "步行速度与心率成本接近个人近期基线。",
                        negative: "步行样本显示当前轻活动成本偏高，更适合先把基础有氧打稳。"
                    )
                )
            )
        }

        if let recoveryComponent, drivers.count < 3 {
            let direction = VO2MaxRules.driverDirection(for: recoveryComponent)
            drivers.append(
                VO2MaxDriver(
                    title: "恢复状态",
                    direction: direction,
                    impact: Int(abs(recoveryComponent - 50).rounded()),
                    explanation: directionalExplanation(
                        direction,
                        positive: "睡眠与夜间恢复信号稳定，给了当前估算更高的上限和更高可信度。",
                        neutral: "恢复信号接近个人近期基线，对当前估算影响有限。",
                        negative: "近几天恢复偏弱，系统会保守抑制 VO₂ Max 的短期上行。"
                    )
                )
            )
        }

        if let rhrComponent, drivers.count < 3 {
            let direction = VO2MaxRules.driverDirection(for: rhrComponent)
            drivers.append(
                VO2MaxDriver(
                    title: "静息心率",
                    direction: direction,
                    impact: Int(abs(rhrComponent - 50).rounded()),
                    explanation: directionalExplanation(
                        direction,
                        positive: "静息心率相对自身基线更稳，说明静息效率在支持当前体能。",
                        neutral: "静息心率接近个人近期基线。",
                        negative: "静息心率相对近期基线偏高，当前更像处在恢复承压阶段。"
                    )
                )
            )
        }

        if let hrvComponent, drivers.count < 3 {
            let direction = VO2MaxRules.driverDirection(for: hrvComponent)
            drivers.append(
                VO2MaxDriver(
                    title: "夜间 HRV",
                    direction: direction,
                    impact: Int(abs(hrvComponent - 50).rounded()),
                    explanation: directionalExplanation(
                        direction,
                        positive: "夜间 HRV 高于近期基线，说明恢复质量在支撑适能输出。",
                        neutral: "夜间 HRV 接近个人近期基线。",
                        negative: "夜间 HRV 低于近期基线，恢复质量暂时限制了体能判断。"
                    )
                )
            )
        }

        if drivers.isEmpty {
            drivers.append(
                VO2MaxDriver(
                    title: "样本不足",
                    direction: .neutral,
                    impact: 0,
                    explanation: "当前主要依赖有限样本做保守估算，继续累积步行、跑步和恢复记录会更准。"
                )
            )
        }

        return Array(drivers.prefix(3))
    }

    private func directionalExplanation(
        _ direction: VO2MaxDriverDirection,
        positive: String,
        neutral: String,
        negative: String
    ) -> String {
        switch direction {
        case .positive: return positive
        case .neutral: return neutral
        case .negative: return negative
        }
    }

    private func makeSummary(
        value: Double,
        source: VO2MaxSource,
        level: VO2MaxFitnessLevel,
        confidence: Int,
        drivers: [VO2MaxDriver]
    ) -> String {
        let sourceText: String
        switch source {
        case .healthKitActual:
            sourceText = "Apple Health 真实样本"
        case .engineEstimated:
            sourceText = "本地引擎估算"
        case .engineBlended:
            sourceText = "真实样本 + 本地解释"
        }

        let driverText = drivers.first?.title ?? "综合体能"
        return String(format: String(localized: "%.1f ml/kg/min，%@，可信度 %@。当前主要受%@影响，结果来源为%@。"), value, level.localizedTitle, localizedPercent(confidence), driverText, sourceText)
    }

    private func smooth(
        _ raw: [VO2MaxRawAssessment],
        previousAssessments: [VO2MaxDailyAssessment]
    ) -> [VO2MaxDailyAssessment] {
        let firstDate = raw.first?.date
        var previousAssessment = firstDate.flatMap { firstDate in
            previousAssessments
                .filter { $0.date < firstDate }
                .max { $0.date < $1.date }
        }

        return raw.map { item in
            let daysSincePrevious = previousAssessment.flatMap {
                calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: $0.date),
                    to: calendar.startOfDay(for: item.date)
                ).day
            }
            let smoothedValue = VO2MaxRules.smoothedValue(
                current: item.value,
                source: item.source,
                previous: previousAssessment?.value,
                previousSource: previousAssessment?.source,
                daysSincePrevious: daysSincePrevious
            )
            let smoothedLevel = fitnessLevel(value: smoothedValue, age: item.age, sex: item.sex)
            let assessment = VO2MaxDailyAssessment(
                date: item.date,
                value: roundToOneDecimal(smoothedValue),
                source: item.source,
                confidence: item.confidenceBreakdown.finalScore,
                trend: .stable,
                fitnessLevel: smoothedLevel,
                drivers: item.drivers,
                components: item.components,
                inputs: item.inputs,
                confidenceBreakdown: item.confidenceBreakdown,
                summaryText: makeSummary(
                    value: smoothedValue,
                    source: item.source,
                    level: smoothedLevel,
                    confidence: item.confidenceBreakdown.finalScore,
                    drivers: item.drivers
                )
            )
            previousAssessment = assessment
            return assessment
        }
    }

    private func mergedAssessments(
        cached: [VO2MaxDailyAssessment],
        fresh: [VO2MaxDailyAssessment]
    ) -> [VO2MaxDailyAssessment] {
        var assessmentsByID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        for assessment in fresh {
            assessmentsByID[assessment.id] = assessment
        }
        return assessmentsByID.values.sorted { $0.date < $1.date }
    }

    private func assessmentsInWindow(
        _ assessments: [VO2MaxDailyAssessment],
        days: Int,
        endDate: Date
    ) -> [VO2MaxDailyAssessment] {
        let endDay = calendar.startOfDay(for: endDate)
        let startDay = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: endDay) ?? endDay
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDate
        return assessments
            .filter { $0.date >= startDay && $0.date < endExclusive }
            .sorted { $0.date < $1.date }
    }

    private func applyTrend(to assessments: [VO2MaxDailyAssessment]) -> [VO2MaxDailyAssessment] {
        guard !assessments.isEmpty else { return [] }

        let values = assessments.map(\.value)
        let trend = resolveTrend(for: assessments)
        return assessments.enumerated().map { index, assessment in
            let refinedTrend = index == assessments.count - 1 ? trend : assessment.trend
            let updatedSummary = makeSummary(
                value: assessment.value,
                source: assessment.source,
                level: assessment.fitnessLevel,
                confidence: assessment.confidence,
                drivers: assessment.drivers
            )
            return VO2MaxDailyAssessment(
                date: assessment.date,
                value: values[index],
                source: assessment.source,
                confidence: assessment.confidence,
                trend: refinedTrend,
                fitnessLevel: assessment.fitnessLevel,
                drivers: assessment.drivers,
                components: assessment.components,
                inputs: assessment.inputs,
                confidenceBreakdown: assessment.confidenceBreakdown,
                summaryText: updatedSummary
            )
        }
    }

    private func resolveTrend(for assessments: [VO2MaxDailyAssessment]) -> VO2MaxTrend {
        VO2MaxRules.trend(
            samples: assessments.map {
                VO2MaxRules.TrendSample(
                    date: $0.date,
                    value: $0.value,
                    confidence: $0.confidence
                )
            },
            calendar: calendar
        )
    }

    private func rhrComponent(restingHeartRate: Double?, baseline: Double?, age: Int?, sex: String?) -> Double? {
        guard let restingHeartRate, restingHeartRate > 0 else { return nil }
        if let baseline, baseline > 0 {
            let ratio = clamp((baseline - restingHeartRate) / baseline, lower: -0.20, upper: 0.20)
            return clamp(55 + ratio * 120, lower: 0, upper: 100)
        }
        let reference = fallbackRestingReference(age: age, sex: sex)
        return clamp(60 + (reference - restingHeartRate) * 2.2, lower: 0, upper: 100)
    }

    private func hrvComponent(nightlyHrv: Double?, baseline: Double?) -> Double? {
        guard let nightlyHrv, nightlyHrv > 0 else { return nil }
        if let baseline, baseline > 0 {
            let ratio = clamp((nightlyHrv - baseline) / baseline, lower: -0.35, upper: 0.35)
            return clamp(52 + ratio * 95, lower: 0, upper: 100)
        }
        return clamp(38 + nightlyHrv * 0.85, lower: 0, upper: 100)
    }

    func walkingFitnessIndex(input: WalkingFitnessInput) -> Double? {
        let hasQualifiedWorkout = (input.distanceKilometers ?? 0) >= 1.0
            || (input.durationMinutes ?? 0) >= 12.0
        let isDailyAggregate = input.distanceKilometers == nil && input.durationMinutes == nil
        guard input.speedMps.isFinite,
              (0.4...3.0).contains(input.speedMps),
              hasQualifiedWorkout || isDailyAggregate else {
            return nil
        }

        let heartRateContext: (average: Double, resting: Double)? = {
            guard let average = input.averageHeartRate,
                  let resting = input.restingHeartRate,
                  average.isFinite,
                  resting.isFinite,
                  average > resting,
                  (40...220).contains(average),
                  (35...130).contains(resting) else { return nil }
            return (average, resting)
        }()
        let base: Double
        if let heartRateContext,
           let baselineRatio = input.baselineRatio,
           baselineRatio.isFinite,
           baselineRatio > 0 {
            let ratio = input.speedMps / heartRateContext.average
            let relative = clamp((ratio - baselineRatio) / baselineRatio, lower: -0.25, upper: 0.25)
            base = clamp(54 + relative * 120, lower: 0, upper: 100)
        } else if let heartRateContext {
            let speedScore = clamp(50 + (input.speedMps - 1.35) * 50, lower: 20, upper: 85)
            let heartRateDelta = heartRateContext.average - heartRateContext.resting
            let costScore = clamp(55 + (35 - heartRateDelta) * 1.2, lower: 20, upper: 85)
            base = speedScore * 0.55 + costScore * 0.45
        } else {
            base = clamp(50 + (input.speedMps - 1.25) * 45, lower: 25, upper: 78)
        }
        let qualityPenalty = walkingQualityPenalty(
            distanceKilometers: input.distanceKilometers,
            durationMinutes: input.durationMinutes,
            heartRateDelta: heartRateContext.map { $0.average - $0.resting }
        )
        let missingHeartRatePenalty = heartRateContext == nil ? 8.0 : 0
        return clamp(base - qualityPenalty - missingHeartRatePenalty, lower: 0, upper: 100)
    }

    func runningFitnessIndex(input: RunningFitnessInput) -> Double? {
        guard VO2MaxRules.isQualifiedRunningSample(
            durationMinutes: input.durationMinutes,
            distanceKilometers: input.distanceKilometers,
            averageHeartRate: input.averageHeartRate,
            paceSecondsPerKm: input.paceSecondsPerKm
        ) else {
            return nil
        }

        let speedMps = 1000.0 / input.paceSecondsPerKm
        let efficiency = speedMps / input.averageHeartRate
        let baseline = input.baselineEfficiency ?? efficiency
        let relative = baseline > 0 ? clamp((efficiency - baseline) / baseline, lower: -0.25, upper: 0.25) : 0
        let paceBonus = clamp((360.0 - input.paceSecondsPerKm) / 90.0, lower: -1.0, upper: 1.0) * 10
        return clamp(56 + relative * 130 + paceBonus, lower: 0, upper: 100)
    }

    func recoveryFitnessIndex(input: RecoveryFitnessInput) -> Double? {
        var sum = 0.0
        var weight = 0.0

        if let sleepScore = input.sleepScore, sleepScore > 0 {
            sum += Double(sleepScore) * 0.35
            weight += 0.35
        }

        if let nightlyHrv = input.nightlyHrv, nightlyHrv > 0 {
            let hrvScore: Double
            if let baseline = input.recentNightlyHrvBaseline, baseline > 0 {
                let relative = clamp((nightlyHrv - baseline) / baseline, lower: -0.35, upper: 0.35)
                hrvScore = clamp(50 + relative * 100, lower: 0, upper: 100)
            } else {
                hrvScore = clamp(40 + nightlyHrv * 0.9, lower: 0, upper: 100)
            }
            sum += hrvScore * 0.40
            weight += 0.40
        }

        if let heartRateRecovery = input.heartRateRecoveryOneMinute, heartRateRecovery > 0 {
            let recoveryScore = clamp(20 + heartRateRecovery * 2.2, lower: 0, upper: 100)
            sum += recoveryScore * 0.25
            weight += 0.25
        }

        if let nightlyAverageHeartRate = input.nightlyAverageHeartRate,
           nightlyAverageHeartRate.isFinite,
           nightlyAverageHeartRate > 0 {
            let reserveScore = clamp(70 - (nightlyAverageHeartRate - 55) * 1.8, lower: 0, upper: 100)
            if weight == 0 {
                sum += reserveScore * 0.20
                weight += 0.20
            } else {
                sum += reserveScore * 0.08
                weight += 0.08
            }
        }

        guard weight > 0 else { return nil }
        return clamp(sum / weight, lower: 0, upper: 100)
    }

    private func aggregatedWalkingFitness(inputs: [WalkingFitnessInput]) -> Double? {
        let scores = inputs.compactMap { walkingFitnessIndex(input: $0) }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func aggregatedRunningFitness(inputs: [RunningFitnessInput]) -> Double? {
        let scores = inputs.compactMap { runningFitnessIndex(input: $0) }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func bodySizeAdjustment(heightCm: Double?, weightKg: Double?) -> Double {
        guard let heightCm, let weightKg,
              heightCm.isFinite, weightKg.isFinite,
              (120...230).contains(heightCm),
              (30...300).contains(weightKg) else { return 0 }
        let heightM = heightCm / 100.0
        let bmi = weightKg / (heightM * heightM)
        if bmi < 19 {
            return -0.4
        }
        if bmi > 29 {
            return -0.9
        }
        return 0.3
    }

    private func fallbackRestingReference(age: Int?, sex: String?) -> Double {
        let resolvedAge = age ?? 35
        let sexOffset = sex == "女" ? 2.0 : 0.0
        return max(58, 66.0 + Double(resolvedAge - 35) * 0.06 + sexOffset)
    }

    private func walkingQualityPenalty(distanceKilometers: Double?, durationMinutes: Double?, heartRateDelta: Double?) -> Double {
        var penalty = 0.0
        if let distanceKilometers, distanceKilometers < 1.2 {
            penalty += (1.2 - distanceKilometers) * 12
        }
        if let durationMinutes, durationMinutes < 14 {
            penalty += (14 - durationMinutes) * 1.3
        }
        if let heartRateDelta, heartRateDelta > 42 {
            penalty += min(12, (heartRateDelta - 42) * 0.45)
        }
        return penalty
    }

    private func hasWalkingHeartRateContext(_ input: WalkingFitnessInput) -> Bool {
        guard let average = input.averageHeartRate,
              let resting = input.restingHeartRate else { return false }
        return average.isFinite
            && resting.isFinite
            && average > resting
            && (40...220).contains(average)
            && (35...130).contains(resting)
    }

    private func baselineValue(before day: Date, in values: [Date: Double], limit: Int) -> Double? {
        let candidates = values
            .filter { $0.key < day && $0.value.isFinite && $0.value > 0 }
            .sorted { $0.key < $1.key }
            .suffix(limit)
            .map { $0.value }
            .sorted()
        guard candidates.count >= 3 else { return nil }
        let middle = candidates.count / 2
        if candidates.count.isMultiple(of: 2) {
            return (candidates[middle - 1] + candidates[middle]) / 2
        }
        return candidates[middle]
    }

    private func walkingInputs(
        for day: Date,
        restingByDay: [Date: Double],
        walkingSpeedByDay: [Date: Double],
        walkingHeartRateByDay: [Date: Double],
        bodyProfile: VO2MaxBodyProfile
    ) -> [WalkingFitnessInput] {
        let dayKey = calendar.startOfDay(for: day)
        guard let speed = walkingSpeedByDay[dayKey], speed > 0 else { return [] }
        let heartRate = walkingHeartRateByDay[dayKey].flatMap { $0 > 0 ? $0 : nil }
        let resting = (restingByDay[dayKey] ?? baselineValue(before: dayKey, in: restingByDay, limit: 14))
            .flatMap { $0 > 0 ? $0 : nil }

        return [WalkingFitnessInput(
            speedMps: speed,
            paceSecondsPerKm: 1000.0 / speed,
            averageHeartRate: heartRate,
            restingHeartRate: resting,
            distanceKilometers: nil,
            durationMinutes: nil,
            baselineRatio: walkingBaselineRatio(
                before: dayKey,
                walkingSpeedByDay: walkingSpeedByDay,
                walkingHeartRateByDay: walkingHeartRateByDay
            ),
            age: bodyProfile.age,
            sex: bodyProfile.sex
        )]
    }

    private func runningInputs(for day: Date, workoutsByDay: [Date: [VO2MaxWorkoutSample]]) -> [RunningFitnessInput] {
        let dayKey = calendar.startOfDay(for: day)
        let allWorkouts = workoutsByDay[dayKey] ?? []
        let baseline = runningBaselineEfficiency(before: dayKey, workoutsByDay: workoutsByDay)

        return allWorkouts.compactMap { workout in
            guard workout.activityType == .running,
                  let pace = workout.paceSecondsPerKilometer,
                  let averageHeartRate = workout.averageHeartRate,
                  let distance = workout.distanceKilometers,
                  VO2MaxRules.isQualifiedRunningSample(
                    durationMinutes: workout.durationMinutes,
                    distanceKilometers: distance,
                    averageHeartRate: averageHeartRate,
                    paceSecondsPerKm: pace
                  ) else {
                return nil
            }
            return RunningFitnessInput(
                paceSecondsPerKm: pace,
                averageHeartRate: averageHeartRate,
                distanceKilometers: distance,
                durationMinutes: workout.durationMinutes,
                baselineEfficiency: baseline
            )
        }
    }

    private func latestHeartRateRecovery(for day: Date, workoutsByDay: [Date: [VO2MaxWorkoutSample]]) -> Double? {
        let dayKey = calendar.startOfDay(for: day)
        return (workoutsByDay[dayKey] ?? [])
            .sorted { $0.endDate > $1.endDate }
            .compactMap(\.heartRateRecoveryOneMinute)
            .first
    }

    func actualVO2(
        near workout: VO2MaxWorkoutSample,
        samples: [TimeSeriesPointDouble]
    ) -> Double? {
        return samples
            .compactMap { sample -> (date: Date, value: Double)? in
                guard isActualSample(sample, associatedWith: workout),
                      let value = VO2MaxRules.validActual(sample.value) else { return nil }
                return (sample.date, value)
            }
            .min(by: {
                abs($0.date.timeIntervalSince(workout.endDate))
                    < abs($1.date.timeIntervalSince(workout.endDate))
            })?.value
    }

    func unassociatedActualSamples(
        samples: [TimeSeriesPointDouble],
        workouts: [VO2MaxWorkoutSample]
    ) -> [TimeSeriesPointDouble] {
        samples
            .filter { sample in
                VO2MaxRules.validActual(sample.value) != nil
                    && !workouts.contains { isActualSample(sample, associatedWith: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    private func isActualSample(
        _ sample: TimeSeriesPointDouble,
        associatedWith workout: VO2MaxWorkoutSample
    ) -> Bool {
        let windowStart = workout.startDate.addingTimeInterval(-30 * 60)
        let windowEnd = workout.endDate.addingTimeInterval(2 * 60 * 60)
        return sample.date >= windowStart && sample.date <= windowEnd
    }

    private func actualSessionAssessments(
        from samples: [TimeSeriesPointDouble],
        bodyProfile: VO2MaxBodyProfile
    ) -> [VO2MaxSessionAssessment] {
        samples.compactMap { sample in
            guard let actualValue = VO2MaxRules.validActual(sample.value) else { return nil }
            let level = fitnessLevel(value: actualValue, age: bodyProfile.age, sex: bodyProfile.sex)
            let confidence = VO2MaxConfidenceBreakdown(
                sourceScore: 95,
                coverageScore: 55,
                qualityScore: 55,
                finalScore: 90
            )
            return VO2MaxSessionAssessment(
                date: sample.date,
                value: actualValue,
                source: .healthKitActual,
                confidence: confidence.finalScore,
                fitnessLevel: level,
                drivers: [
                    VO2MaxDriver(
                        title: "真实样本",
                        direction: .neutral,
                        impact: 0,
                        explanation: "当前时间点直接使用 HealthKit 的 VO2 Max 样本。"
                    )
                ],
                components: VO2MaxComponentBreakdown(
                    rhrComponent: nil,
                    hrvComponent: nil,
                    walkingEfficiencyComponent: nil,
                    runningEfficiencyComponent: nil,
                    recoveryComponent: nil,
                    finalWeightedScore: 0
                ),
                inputs: VO2MaxInputCoverage(
                    actualVO2: true,
                    rhr: false,
                    hrv: false,
                    walking: false,
                    running: false,
                    recovery: false
                ),
                confidenceBreakdown: confidence,
                summaryText: makeSummary(
                    value: actualValue,
                    source: .healthKitActual,
                    level: level,
                    confidence: confidence.finalScore,
                    drivers: []
                ),
                activityType: nil
            )
        }
    }

    private func walkingBaselineRatio(
        before day: Date,
        walkingSpeedByDay: [Date: Double],
        walkingHeartRateByDay: [Date: Double]
    ) -> Double? {
        let ratios = walkingSpeedByDay.keys
            .filter { $0 < day }
            .sorted()
            .suffix(14)
            .compactMap { date -> Double? in
                guard let speed = walkingSpeedByDay[date], speed.isFinite, speed > 0,
                      let heartRate = walkingHeartRateByDay[date], heartRate.isFinite, heartRate > 0 else {
                    return nil
                }
                return speed / heartRate
            }
        guard ratios.count >= 3 else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    private func runningBaselineEfficiency(
        before day: Date,
        workoutsByDay: [Date: [VO2MaxWorkoutSample]]
    ) -> Double? {
        let lowerBound = calendar.date(byAdding: .day, value: -28, to: day) ?? .distantPast
        let efficiencies = workoutsByDay
            .filter { $0.key >= lowerBound && $0.key < day }
            .flatMap { $0.value }
            .compactMap { workout -> Double? in
                guard workout.activityType == .running,
                      let pace = workout.paceSecondsPerKilometer,
                      let heartRate = workout.averageHeartRate,
                      let distance = workout.distanceKilometers,
                      VO2MaxRules.isQualifiedRunningSample(
                        durationMinutes: workout.durationMinutes,
                        distanceKilometers: distance,
                        averageHeartRate: heartRate,
                        paceSecondsPerKm: pace
                      ) else { return nil }
                return (1_000 / pace) / heartRate
            }
        guard efficiencies.count >= 2 else { return nil }
        return efficiencies.reduce(0, +) / Double(efficiencies.count)
    }

    private func startDate(days: Int, endDate: Date) -> Date {
        let normalizedEnd = calendar.startOfDay(for: endDate)
        return calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: normalizedEnd) ?? normalizedEnd
    }

    private func strideDays(days: Int, endDate: Date) -> [Date] {
        let normalizedEnd = calendar.startOfDay(for: endDate)
        guard let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: normalizedEnd) else {
            return [normalizedEnd]
        }
        return (0..<max(days, 1)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func dictionaryByDay(_ points: [TimeSeriesPointDouble]) -> [Date: Double] {
        points.reduce(into: [Date: Double]()) { result, point in
            guard point.value.isFinite else { return }
            result[calendar.startOfDay(for: point.date)] = point.value
        }
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func roundToOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
