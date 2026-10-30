import Foundation

nonisolated enum StressBodyBatteryEngine {
    static let minimumLevel = StressBodyBatteryRules.minimumLevel

    static func recoveryScore(input: StressBodyBatteryRecoveryInput) -> Int? {
        var weightedTotal = 0.0
        var totalWeight = 0.0

        func add(_ value: Double?, weight: Double) {
            guard let value, value.isFinite else { return }
            weightedTotal += clamp(value) * weight
            totalWeight += weight
        }

        if let sleepMinutes = input.sleepMinutes, sleepMinutes > 0 {
            add(
                StressBodyBatteryRules.Recovery.sleepDurationScore(
                    minutes: sleepMinutes,
                    goalMinutes: input.sleepGoalMinutes
                ),
                weight: StressBodyBatteryRules.Recovery.sleepDurationWeight
            )
        }

        var hasRawSleepQuality = false
        if let sleepEfficiency = input.sleepEfficiency, sleepEfficiency > 0 {
            add(
                StressBodyBatteryRules.Recovery.sleepEfficiencyScore(sleepEfficiency),
                weight: StressBodyBatteryRules.Recovery.sleepEfficiencyWeight
            )
            hasRawSleepQuality = true
        }
        if let sleepMinutes = input.sleepMinutes, sleepMinutes > 0 {
            let restorativeMinutes = max(0, input.deepSleepMinutes ?? 0) + max(0, input.remSleepMinutes ?? 0)
            if restorativeMinutes > 0 {
                add(
                    StressBodyBatteryRules.Recovery.restorativeSleepScore(
                        minutes: restorativeMinutes,
                        sleepMinutes: sleepMinutes
                    ),
                    weight: StressBodyBatteryRules.Recovery.restorativeSleepWeight
                )
                hasRawSleepQuality = true
            }
        }
        if (input.sleepMinutes ?? 0) <= 0, !hasRawSleepQuality,
           let sleepScore = input.sleepScoreFallback, sleepScore > 0 {
            add(Double(sleepScore), weight: StressBodyBatteryRules.Recovery.sleepScoreFallbackWeight)
        }

        if let nightlyHrv = input.nightlyHrv, nightlyHrv > 0,
           let baselineHrv = input.baselineHrv, baselineHrv > 0 {
            add(
                StressBodyBatteryRules.Recovery.hrvScore(current: nightlyHrv, baseline: baselineHrv),
                weight: StressBodyBatteryRules.Recovery.hrvWeight
            )
        }

        let overnightHeartRate = pairedValue(
            primary: input.overnightHeartRate,
            primaryBaseline: input.baselineOvernightHeartRate,
            fallback: input.restingHeartRate,
            fallbackBaseline: input.baselineRestingHeartRate
        )
        if let current = overnightHeartRate?.value, let baseline = overnightHeartRate?.baseline {
            add(
                StressBodyBatteryRules.Recovery.heartRateScore(current: current, baseline: baseline),
                weight: StressBodyBatteryRules.Recovery.heartRateWeight
            )
        }

        if let respiratoryRate = input.nightlyRespiratoryRate, respiratoryRate > 0,
           let baseline = input.baselineNightlyRespiratoryRate, baseline > 0 {
            add(
                StressBodyBatteryRules.Recovery.respiratoryRateScore(
                    current: respiratoryRate,
                    baseline: baseline
                ),
                weight: StressBodyBatteryRules.Recovery.respiratoryRateWeight
            )
        }

        if let temperature = input.sleepingWristTemperature, temperature.isFinite,
           let baseline = input.baselineSleepingWristTemperature, baseline.isFinite {
            add(
                StressBodyBatteryRules.Recovery.wristTemperatureScore(
                    current: temperature,
                    baseline: baseline
                ),
                weight: StressBodyBatteryRules.Recovery.wristTemperatureWeight
            )
        }

        if let disturbances = input.sleepingBreathingDisturbances, disturbances >= 0,
           let baseline = input.baselineSleepingBreathingDisturbances, baseline >= 0 {
            add(
                StressBodyBatteryRules.Recovery.breathingDisturbancesScore(
                    current: disturbances,
                    baseline: baseline
                ),
                weight: StressBodyBatteryRules.Recovery.breathingDisturbancesWeight
            )
        }

        guard totalWeight > 0 else { return nil }
        return clampLevel(weightedTotal / totalWeight)
    }

    static func personalBaseline(_ rawValues: [Double], allowsZero: Bool = false) -> Double? {
        let values = rawValues.filter {
            $0.isFinite && (allowsZero ? $0 >= 0 : $0 > 0)
        }
        guard values.count >= StressBodyBatteryRules.Recovery.minimumBaselineValueCount else { return nil }
        let historical = Array(values.dropLast()).sorted()
        guard historical.count >= StressBodyBatteryRules.Recovery.minimumHistoricalBaselineValueCount else {
            return nil
        }
        let middle = historical.count / 2
        if historical.count.isMultiple(of: 2) {
            return (historical[middle - 1] + historical[middle]) / 2
        }
        return historical[middle]
    }

    static func recoveryScore(
        sleepMinutes: Int?,
        sleepGoalMinutes: Int = StressBodyBatteryRules.Recovery.defaultSleepGoalMinutes,
        sleepScore: Int?,
        nightlyHrv: Double?,
        baselineHrv: Double?,
        restingHeartRate: Double?,
        baselineRestingHeartRate: Double?
    ) -> Int? {
        recoveryScore(input: StressBodyBatteryRecoveryInput(
            sleepMinutes: sleepMinutes,
            sleepGoalMinutes: sleepGoalMinutes,
            sleepScoreFallback: sleepScore,
            sleepEfficiency: nil,
            deepSleepMinutes: nil,
            remSleepMinutes: nil,
            nightlyHrv: nightlyHrv,
            baselineHrv: baselineHrv,
            overnightHeartRate: nil,
            baselineOvernightHeartRate: nil,
            restingHeartRate: restingHeartRate,
            baselineRestingHeartRate: baselineRestingHeartRate,
            nightlyRespiratoryRate: nil,
            baselineNightlyRespiratoryRate: nil,
            sleepingWristTemperature: nil,
            baselineSleepingWristTemperature: nil,
            sleepingBreathingDisturbances: nil,
            baselineSleepingBreathingDisturbances: nil
        ))
    }

    static func currentValue(
        stressPoints: [TimeSeriesPoint],
        fallbackStress: Int?,
        recoveryScore: Int?,
        wakeDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        load: StressBodyBatteryLoadInput = .empty
    ) -> Int? {
        trajectory(
            stressPoints: stressPoints,
            fallbackStress: fallbackStress,
            recoveryScore: recoveryScore,
            wakeDate: wakeDate,
            endDate: now,
            calendar: calendar,
            load: load
        ).last?.value
    }

    static func trajectory(
        stressPoints: [TimeSeriesPoint],
        fallbackStress: Int?,
        recoveryScore: Int?,
        wakeDate: Date?,
        endDate: Date,
        calendar: Calendar = .current,
        load: StressBodyBatteryLoadInput = .empty
    ) -> [TimeSeriesPoint] {
        let validStressPoints = deduplicatedStressPoints(stressPoints)
            .filter { $0.value > 0 && $0.date <= endDate }
        let validPhysicalEffort = load.physicalEffortSamples.filter {
            $0.metabolicEquivalent.isFinite && $0.metabolicEquivalent > 0
                && $0.endDate > $0.startDate && $0.startDate < endDate
        }
        let validWorkoutEffort = load.workoutEffortEvents.filter {
            $0.score.isFinite && $0.score > 0 && $0.durationMinutes.isFinite
                && $0.durationMinutes > 0 && $0.endedAt <= endDate
        }
        let resolvedFallback = fallbackStress.map(clampStress)
            ?? validStressPoints.last.map { clampStress($0.value) }
        let hasLoadEvidence = !validPhysicalEffort.isEmpty || !validWorkoutEffort.isEmpty
        guard recoveryScore != nil || resolvedFallback != nil || hasLoadEvidence else { return [] }

        let dayStart = calendar.startOfDay(for: endDate)
        let defaultWake = calendar.date(
            byAdding: .hour,
            value: StressBodyBatteryRules.DayLoad.defaultWakeHour,
            to: dayStart
        ) ?? dayStart
        let resolvedWake: Date
        if let wakeDate,
           calendar.isDate(wakeDate, inSameDayAs: endDate),
           wakeDate <= endDate {
            resolvedWake = max(dayStart, wakeDate)
        } else {
            resolvedWake = min(defaultWake, endDate)
        }

        if validStressPoints.isEmpty, resolvedFallback == nil, !hasLoadEvidence, let recoveryScore {
            let level = clampLevel(Double(recoveryScore))
            let startPoint = TimeSeriesPoint(timestamp: Int64(resolvedWake.timeIntervalSince1970), value: level)
            guard resolvedWake != endDate else { return [startPoint] }
            return [startPoint, TimeSeriesPoint(timestamp: Int64(endDate.timeIntervalSince1970), value: level)]
        }

        let initialStress = validStressPoints.first.map { clampStress($0.value) }
            ?? resolvedFallback
            ?? StressBodyBatteryRules.DayLoad.defaultStress
        var level = Double(recoveryScore ?? fallbackStartingLevel(stress: initialStress))
        var cursor = resolvedWake
        var previousStress = initialStress
        let trainingLoadMultiplier = trainingLoadMultiplier(events: validWorkoutEffort, at: endDate)
        var result = [TimeSeriesPoint(
            timestamp: Int64(resolvedWake.timeIntervalSince1970),
            value: clampLevel(level)
        )]

        for point in validStressPoints where point.date >= resolvedWake {
            let stress = clampStress(point.value)
            if point.date > cursor {
                level = advancedLevel(
                    level,
                    stress: Double(previousStress + stress) / 2,
                    startDate: cursor,
                    endDate: point.date,
                    physicalEffortSamples: validPhysicalEffort,
                    workoutEffortEvents: validWorkoutEffort,
                    trainingLoadMultiplier: trainingLoadMultiplier
                )
            }
            cursor = point.date
            previousStress = stress
            let resolvedPoint = TimeSeriesPoint(timestamp: point.timestamp, value: clampLevel(level))
            if result.last?.timestamp == point.timestamp {
                result[result.count - 1] = resolvedPoint
            } else {
                result.append(resolvedPoint)
            }
        }

        if endDate > cursor {
            level = advancedLevel(
                level,
                stress: Double(resolvedFallback ?? previousStress),
                startDate: cursor,
                endDate: endDate,
                physicalEffortSamples: validPhysicalEffort,
                workoutEffortEvents: validWorkoutEffort,
                trainingLoadMultiplier: trainingLoadMultiplier
            )
        }

        let endTimestamp = Int64(endDate.timeIntervalSince1970)
        let endPoint = TimeSeriesPoint(timestamp: endTimestamp, value: clampLevel(level))
        if result.last?.timestamp == endTimestamp {
            result[result.count - 1] = endPoint
        } else {
            result.append(endPoint)
        }
        return result
    }

    static func estimatedDailyLevel(averageStress: Int) -> Int {
        StressBodyBatteryRules.DayLoad.estimatedDailyLevel(averageStress: averageStress)
    }

    private static func deduplicatedStressPoints(_ points: [TimeSeriesPoint]) -> [TimeSeriesPoint] {
        var byTimestamp: [Int64: TimeSeriesPoint] = [:]
        for point in points {
            byTimestamp[point.timestamp] = point
        }
        return byTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }

    private static func fallbackStartingLevel(stress: Int) -> Int {
        StressBodyBatteryRules.DayLoad.fallbackStartingLevel(stress: stress)
    }

    private static func advancedLevel(
        _ initialLevel: Double,
        stress: Double,
        startDate: Date,
        endDate: Date,
        physicalEffortSamples: [StressBodyBatteryPhysicalEffortSample],
        workoutEffortEvents: [StressBodyBatteryWorkoutEffortEvent],
        trainingLoadMultiplier: Double
    ) -> Double {
        guard endDate > startDate else { return initialLevel }
        let breakpoints = integrationBreakpoints(
            startDate: startDate,
            endDate: endDate,
            physicalEffortSamples: physicalEffortSamples,
            workoutEffortEvents: workoutEffortEvents
        )
        var level = initialLevel
        var cursor = startDate

        for boundary in breakpoints where boundary > cursor {
            let midpoint = cursor.addingTimeInterval(boundary.timeIntervalSince(cursor) / 2)
            let hours = boundary.timeIntervalSince(cursor) / StressBodyBatteryRules.secondsPerHour
            let physicalLoad = normalizedPhysicalEffort(at: midpoint, samples: physicalEffortSamples)
            let combinedLoad = StressBodyBatteryRules.DayLoad.combinedLoad(
                stress: stress,
                physicalLoad: physicalLoad
            )
            let postWorkoutLoad = postWorkoutLoad(at: midpoint, events: workoutEffortEvents)
            let drainPerHour = StressBodyBatteryRules.DayLoad.drainPerHour(
                combinedLoad: combinedLoad,
                postWorkoutLoad: postWorkoutLoad,
                trainingLoadMultiplier: trainingLoadMultiplier
            )
            let recoveryPerHour = StressBodyBatteryRules.DayLoad.recoveryPerHour(
                stress: stress,
                physicalLoad: physicalLoad,
                postWorkoutLoad: postWorkoutLoad
            )
            level = clamp(
                level + (recoveryPerHour - drainPerHour) * hours,
                lower: Double(minimumLevel),
                upper: Double(StressBodyBatteryRules.maximumLevel)
            )
            cursor = boundary
        }
        return level
    }

    private static func integrationBreakpoints(
        startDate: Date,
        endDate: Date,
        physicalEffortSamples: [StressBodyBatteryPhysicalEffortSample],
        workoutEffortEvents: [StressBodyBatteryWorkoutEffortEvent]
    ) -> [Date] {
        var dates: Set<Date> = [endDate]
        for sample in physicalEffortSamples where sample.endDate > startDate && sample.startDate < endDate {
            dates.insert(max(startDate, sample.startDate))
            dates.insert(min(endDate, sample.endDate))
        }
        for event in workoutEffortEvents where event.endedAt < endDate {
            for offsetHours in StressBodyBatteryRules.DayLoad.workoutIntegrationOffsetsHours {
                let date = event.endedAt.addingTimeInterval(
                    offsetHours * StressBodyBatteryRules.secondsPerHour
                )
                if date > startDate && date < endDate {
                    dates.insert(date)
                }
            }
        }
        return dates.sorted()
    }

    private static func normalizedPhysicalEffort(
        at date: Date,
        samples: [StressBodyBatteryPhysicalEffortSample]
    ) -> Double {
        let values = samples
            .filter { $0.startDate <= date && date < $0.endDate }
            .map(\.metabolicEquivalent)
        guard !values.isEmpty else { return 0 }
        let average = values.reduce(0, +) / Double(values.count)
        return StressBodyBatteryRules.DayLoad.normalizedPhysicalEffort(metabolicEquivalent: average)
    }

    private static func postWorkoutLoad(
        at date: Date,
        events: [StressBodyBatteryWorkoutEffortEvent]
    ) -> Double {
        events.reduce(0) { total, event in
            let hoursSinceEnd = date.timeIntervalSince(event.endedAt)
                / StressBodyBatteryRules.secondsPerHour
            return total + StressBodyBatteryRules.Workout.postWorkoutLoad(
                hoursSinceEnd: hoursSinceEnd,
                score: event.score,
                durationMinutes: event.durationMinutes,
                isEstimated: event.isEstimated
            )
        }
    }

    private static func trainingLoadMultiplier(
        events: [StressBodyBatteryWorkoutEffortEvent],
        at date: Date
    ) -> Double {
        let recentStart = date.addingTimeInterval(
            -StressBodyBatteryRules.Workout.recentWindowDays * StressBodyBatteryRules.secondsPerDay
        )
        let baselineStart = date.addingTimeInterval(
            -StressBodyBatteryRules.Workout.baselineWindowDays * StressBodyBatteryRules.secondsPerDay
        )
        let baselineEvents = events.filter { $0.endedAt >= baselineStart && $0.endedAt <= date }

        func load(_ event: StressBodyBatteryWorkoutEffortEvent) -> Double {
            StressBodyBatteryRules.clamp(
                event.score,
                lower: StressBodyBatteryRules.Workout.scoreRange.lowerBound,
                upper: StressBodyBatteryRules.Workout.scoreRange.upperBound
            ) * max(event.durationMinutes, StressBodyBatteryRules.Workout.minimumDurationMinutes)
        }

        let baselineLoad = baselineEvents.reduce(0) { $0 + load($1) }
        let recentLoad = baselineEvents
            .filter { $0.endedAt >= recentStart }
            .reduce(0) { $0 + load($1) }
        return StressBodyBatteryRules.Workout.trainingLoadMultiplier(
            recentLoad: recentLoad,
            baselineLoad: baselineLoad,
            baselineEventCount: baselineEvents.count
        )
    }

    private static func pairedValue(
        primary: Double?,
        primaryBaseline: Double?,
        fallback: Double?,
        fallbackBaseline: Double?
    ) -> (value: Double, baseline: Double)? {
        if let primary, primary > 0, let primaryBaseline, primaryBaseline > 0 {
            return (primary, primaryBaseline)
        }
        if let fallback, fallback > 0, let fallbackBaseline, fallbackBaseline > 0 {
            return (fallback, fallbackBaseline)
        }
        return nil
    }

    private static func clampStress(_ value: Int) -> Int {
        StressBodyBatteryRules.clampStress(value)
    }

    private static func clampLevel(_ value: Double) -> Int {
        StressBodyBatteryRules.clampLevel(value)
    }

    private static func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
        StressBodyBatteryRules.clamp(value, lower: lower, upper: upper)
    }
}
