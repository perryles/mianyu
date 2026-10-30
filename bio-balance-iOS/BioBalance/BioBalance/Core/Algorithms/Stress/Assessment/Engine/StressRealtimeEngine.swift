import Foundation
import OSLog

struct StressRealtimeEngine: StressRealtimeEvaluating {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "Stress")

    private struct WeightedAccumulator {
        private(set) var weighted = 0.0
        private(set) var totalWeight = 0.0

        mutating func add(_ value: Double?, weight: Double) {
            guard let value, weight > 0 else { return }
            weighted += value * weight
            totalWeight += weight
        }

        var resolved: Double? {
            totalWeight > 0 ? weighted / totalWeight : nil
        }
    }

    private enum Constants {
        static let durationTargetMinutes = 450.0
        static let defaultRestingHeartRate = 62.0
        static let fallbackAge = 30.0
        static let rapidAlpha = 0.32
        static let baseAlpha = 0.20
        static let stableAlpha = 0.12
    }

    func evaluate(input: StressRealtimeInput, previous: StressResult?) -> StressEvaluation {
        let heartRate = freshHeartRate(input.heartRate, now: input.now)
        let hrvResolution = freshHrv(input.hrv, now: input.now)
        let hrv = hrvResolution.sample
        let hrvFreshnessWeight = hrvResolution.weight
        let hrvBaseline = input.hrvBaseline.isUsable ? input.hrvBaseline.value : nil
        let restingBaseline = input.restingHeartRateBaseline.isUsable ? input.restingHeartRateBaseline.value : nil
        let hrvTrend = hrvTrendScore(points: input.hrvPoints30m, baselineHrv: hrvBaseline, now: input.now)
        let hrTrend = hrTrendScore(points: input.heartRatePoints30m, now: input.now)

        let hasAnchoredHeartRate = heartRate != nil && restingBaseline != nil
        let hasAnchoredHrv = hrv != nil && hrvBaseline != nil
        let hasTrendAnchoredHeartRate = heartRate != nil && hrTrend != nil
        guard hasAnchoredHeartRate || hasAnchoredHrv || hasTrendAnchoredHeartRate else {
            let reason = unavailableReason(input: input, heartRate: heartRate, hrv: hrv)
            Self.logger.info("[Stress] operation=evaluate")
            return .unavailable(reason)
        }

        let age = Double(input.chronologicalAge ?? Int(Constants.fallbackAge))
        let comparisonRhr = restingBaseline
        let workoutRhr = restingBaseline ?? input.restingHeartRate ?? Constants.defaultRestingHeartRate

        let hrvDeviation = hrvDeviationScore(currentHrv: hrv?.value, baselineHrv: hrvBaseline)
        let hrDeviation = hrDeviationScore(currentHeartRate: heartRate?.value, baselineRhr: comparisonRhr)
        let circadian = circadianScore(
            now: input.now,
            sleepInterval: input.sleepInterval,
            habitualSleepWindow: input.habitualSleepWindow
        )
        let workoutLoad = physicalContextScore(
            workout: input.workout,
            currentHeartRate: heartRate?.value,
            baselineRhr: workoutRhr,
            age: age
        )
        let recoveryResult = recoverySnapshot(
            sleepMinutes: input.sleepMinutes,
            sleepEfficiency: input.sleepEfficiency,
            nightlyHrv: input.nightlyHrv,
            overnightMinHeartRate: input.overnightMinHeartRate,
            baselineHrv: hrvBaseline,
            baselineRhr: restingBaseline
        )
        let recovery = recoveryResult.snapshot

        let includeWorkoutLoad = input.workout.workoutBlend > 0
        let mentalSuppression = 1.0 - input.workout.workoutBlend * 0.65

        var mental = WeightedAccumulator()
        mental.add(hrvDeviation, weight: 0.32 * hrvFreshnessWeight)
        mental.add(hrDeviation, weight: 0.22)
        mental.add(hrvTrend, weight: 0.14)
        mental.add(hrTrend, weight: 0.10)
        mental.add(recoveryResult.completeness > 0 ? Double(recovery.recoveryDebt) : nil, weight: 0.14)
        mental.add(Double(circadian), weight: 0.08)

        var physical = WeightedAccumulator()
        physical.add(hrDeviation, weight: 0.28)
        physical.add(hrTrend, weight: 0.18)
        physical.add(hrvDeviation, weight: 0.14 * hrvFreshnessWeight)
        physical.add(includeWorkoutLoad ? Double(workoutLoad) : nil, weight: 0.28)
        physical.add(recoveryResult.completeness > 0 ? Double(recovery.recoveryDebt) : nil, weight: 0.12)

        let mentalRaw = mental.resolved.map { $0 * mentalSuppression }
        let physicalRaw = physical.resolved
        guard mentalRaw != nil || physicalRaw != nil else {
            Self.logger.info("[Stress] operation=evaluate")
            return .unavailable(.noPhysiologicalSignal)
        }

        let rawScore = clampInt(resolveRawScore(
            mentalRaw: mentalRaw,
            physicalRaw: physicalRaw,
            workoutBlend: input.workout.workoutBlend
        ))
        let alpha = smoothingAlpha(
            rawScore: rawScore,
            previous: previous,
            workout: input.workout,
            hrvPoints: input.hrvPoints30m,
            hrPoints: input.heartRatePoints30m
        )
        let smoothedScore = previous.map {
            clampInt(alpha * Double(rawScore) + (1 - alpha) * Double($0.smoothedScore))
        } ?? rawScore
        let state = nextState(smoothedScore: smoothedScore, rawScore: rawScore, previous: previous)

        let drivers = dominantDrivers(
            hrvDeviation: hrvDeviation,
            hrvFreshnessWeight: hrvFreshnessWeight,
            hrDeviation: hrDeviation,
            hrvTrend: hrvTrend,
            hrTrend: hrTrend,
            recoveryDebt: recovery.recoveryDebt,
            recoveryAvailable: recoveryResult.completeness > 0,
            circadian: circadian,
            workoutLoad: workoutLoad,
            workout: input.workout
        )
        let dominant = drivers.first ?? (hasAnchoredHrv ? .hrvDeviation : (hasAnchoredHeartRate ? .hrDeviation : .hrTrend))
        let explanation = explanationCode(
            dominantDriver: dominant,
            workout: input.workout,
            recoveryDebt: recovery.recoveryDebt,
            recoveryAvailable: recoveryResult.completeness > 0,
            hasElevatingDriver: !drivers.isEmpty
        )
        let confidence = confidenceScore(
            input: input,
            heartRate: heartRate,
            hrv: hrv,
            hrvFreshnessWeight: hrvFreshnessWeight,
            recoveryCompleteness: recoveryResult.completeness
        )
        let result = StressResult(
            timestamp: Int64(input.now.timeIntervalSince1970),
            rawScore: rawScore,
            smoothedScore: smoothedScore,
            state: state,
            band: StressRules.band(for: state),
            dominantDriver: dominant,
            dominantDrivers: drivers,
            explanationCode: explanation,
            confidence: confidence,
            quality: StressRules.quality(for: confidence),
            algorithmVersion: StressResult.currentAlgorithmVersion,
            recovery: recovery,
            workout: input.workout,
            components: StressComponentScores(
                hrvDeviation: clampInt(hrvDeviation ?? 0),
                hrDeviation: clampInt(hrDeviation ?? 0),
                hrvTrend: clampInt(hrvTrend ?? 0),
                hrTrend: clampInt(hrTrend ?? 0),
                recoveryDebt: recovery.recoveryDebt,
                circadian: circadian,
                workoutLoad: workoutLoad,
                mentalRaw: clampInt(mentalRaw ?? 0),
                physicalRaw: clampInt(physicalRaw ?? 0),
                rawScore: rawScore,
                smoothedScore: smoothedScore
            )
        )

        Self.logger.info("[Stress] operation=evaluate")
        return .available(result)
    }

    private func freshHeartRate(_ sample: StressMetricSample?, now: Date) -> StressMetricSample? {
        guard let sample, sample.value > 0, sample.age(at: now) <= StressRules.heartRateFreshness else { return nil }
        return sample
    }

    private func freshHrv(_ sample: StressMetricSample?, now: Date) -> (sample: StressMetricSample?, weight: Double) {
        guard let sample, sample.value > 0 else { return (nil, 0) }
        let age = sample.age(at: now)
        guard age <= StressRules.hrvMaximumFreshness else { return (nil, 0) }
        guard age > StressRules.hrvFullWeightFreshness else { return (sample, 1) }
        let decayWindow = StressRules.hrvMaximumFreshness - StressRules.hrvFullWeightFreshness
        return (sample, StressRules.clamp(1 - (age - StressRules.hrvFullWeightFreshness) / decayWindow, lower: 0, upper: 1))
    }

    private func unavailableReason(
        input: StressRealtimeInput,
        heartRate: StressMetricSample?,
        hrv: StressMetricSample?
    ) -> StressUnavailableReason {
        if heartRate != nil || hrv != nil { return .baselineCalibrating }
        if let sample = input.heartRate, sample.age(at: input.now) > StressRules.heartRateFreshness { return .staleHeartRate }
        if let sample = input.hrv, sample.age(at: input.now) > StressRules.hrvMaximumFreshness { return .staleHrv }
        return .noPhysiologicalSignal
    }

    private func hrvDeviationScore(currentHrv: Double?, baselineHrv: Double?) -> Double? {
        guard let currentHrv, let baselineHrv else { return nil }
        return StressSignalScoring.hrvDeviation(current: currentHrv, baseline: baselineHrv)
    }

    private func hrDeviationScore(currentHeartRate: Double?, baselineRhr: Double?) -> Double? {
        guard let currentHeartRate, let baselineRhr else { return nil }
        return StressSignalScoring.heartRateDeviation(current: currentHeartRate, baseline: baselineRhr)
    }

    private func hrvTrendScore(points: [StressMetricSample], baselineHrv: Double?, now: Date) -> Double? {
        let recent = median(points.filter { $0.age(at: now) <= 10 * 60 }.map(\.value))
        let prior = median(points.filter {
            let age = $0.age(at: now)
            return age > 10 * 60 && age <= 30 * 60
        }.map(\.value))
        guard let recent, let prior, let baselineHrv, baselineHrv > 0 else { return nil }
        let ratio = StressRules.clamp((prior - recent) / baselineHrv, lower: -0.20, upper: 0.60)
        return StressRules.clamp(50 + ratio * 140)
    }

    private func hrTrendScore(points: [StressMetricSample], now: Date) -> Double? {
        let recent = median(points.filter { $0.age(at: now) <= 5 * 60 }.map(\.value))
        let prior = median(points.filter {
            let age = $0.age(at: now)
            return age > 5 * 60 && age <= 30 * 60
        }.map(\.value))
        guard let recent, let prior else { return nil }
        return StressSignalScoring.heartRateTrend(recent: recent, prior: prior)
    }

    private func circadianScore(
        now: Date,
        sleepInterval: StressDateInterval?,
        habitualSleepWindow: StressHabitualSleepWindow
    ) -> Int {
        if let sleepInterval, now >= sleepInterval.start && now <= sleepInterval.end { return 35 }
        if let sleepInterval,
           let wakeWindowEnd = Calendar.current.date(byAdding: .minute, value: 90, to: sleepInterval.end),
           now >= sleepInterval.end, now <= wakeWindowEnd {
            return 45
        }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let minutesOfDay = hour * 60 + minute
        let sleepStart = habitualSleepWindow.startHour * 60 + habitualSleepWindow.startMinute
        let sleepEnd = habitualSleepWindow.endHour * 60 + habitualSleepWindow.endMinute
        let inSleepWindow = sleepStart <= sleepEnd
            ? (minutesOfDay >= sleepStart && minutesOfDay <= sleepEnd)
            : (minutesOfDay >= sleepStart || minutesOfDay <= sleepEnd)
        if inSleepWindow { return 75 }

        let twoHoursBeforeSleep = (sleepStart - 120 + 1440) % 1440
        let beforeSleep = twoHoursBeforeSleep <= sleepStart
            ? (minutesOfDay >= twoHoursBeforeSleep && minutesOfDay < sleepStart)
            : (minutesOfDay >= twoHoursBeforeSleep || minutesOfDay < sleepStart)
        if beforeSleep { return 60 }
        return (17..<21).contains(hour) ? 55 : 50
    }

    private func physicalContextScore(
        workout: StressWorkoutContext,
        currentHeartRate: Double?,
        baselineRhr: Double,
        age: Double
    ) -> Int {
        let base: Double
        switch workout.kind {
        case .running: base = 65
        case .cycling: base = 62
        case .strength: base = 58
        case .highIntensityIntervalTraining: base = 78
        case .other: base = 60
        case .none: base = 20
        }
        guard workout.isActive, let currentHeartRate else { return clampInt(base) }
        let reserve = max((208 - 0.7 * age) - baselineRhr, 1)
        let intensity = StressRules.clamp((currentHeartRate - baselineRhr) / reserve, lower: 0, upper: 1)
        return clampInt(base + intensity * 25)
    }

    private func recoverySnapshot(
        sleepMinutes: Int?,
        sleepEfficiency: Double?,
        nightlyHrv: Double?,
        overnightMinHeartRate: Double?,
        baselineHrv: Double?,
        baselineRhr: Double?
    ) -> (snapshot: StressRecoverySnapshot, completeness: Double) {
        var accumulator = WeightedAccumulator()
        accumulator.add(sleepMinutes.map { StressRules.clamp(Double(max($0, 0)) / Constants.durationTargetMinutes * 100) }, weight: 0.30)
        accumulator.add(sleepEfficiency.map { StressRules.clamp(($0 - 0.70) / 0.25 * 100) }, weight: 0.25)
        if let nightlyHrv, nightlyHrv > 0, let baselineHrv, baselineHrv > 0 {
            let ratio = StressRules.clamp((nightlyHrv - baselineHrv) / baselineHrv, lower: -0.50, upper: 0.40)
            accumulator.add(StressRules.clamp(60 + ratio * 100), weight: 0.25)
        }
        if let overnightMinHeartRate, overnightMinHeartRate > 0, let baselineRhr, baselineRhr > 0 {
            let rise = StressRules.clamp((overnightMinHeartRate - baselineRhr) / baselineRhr, lower: -0.10, upper: 0.25)
            accumulator.add(StressRules.clamp(75 - rise * 200), weight: 0.20)
        }
        let score = clampInt(accumulator.resolved ?? 50)
        return (
            StressRecoverySnapshot(
                recoveryScore: score,
                recoveryDebt: 100 - score,
                sleepMinutes: sleepMinutes,
                sleepEfficiency: sleepEfficiency,
                nightlyHrv: nightlyHrv,
                overnightMinHeartRate: overnightMinHeartRate
            ),
            StressRules.clamp(accumulator.totalWeight, lower: 0, upper: 1)
        )
    }

    private func resolveRawScore(mentalRaw: Double?, physicalRaw: Double?, workoutBlend: Double) -> Double {
        switch (mentalRaw, physicalRaw) {
        case let (mental?, physical?): return mental * (1 - workoutBlend) + physical * workoutBlend
        case let (mental?, nil): return mental
        case let (nil, physical?): return physical
        case (nil, nil): return 0
        }
    }

    private func smoothingAlpha(
        rawScore: Int,
        previous: StressResult?,
        workout: StressWorkoutContext,
        hrvPoints: [StressMetricSample],
        hrPoints: [StressMetricSample]
    ) -> Double {
        guard let previous else { return Constants.baseAlpha }
        let jumped = abs(previous.rawScore - rawScore) >= 15
        let stateJump = abs(StressRules.rank(of: previous.state) - StressRules.rank(of: StressRules.state(for: rawScore))) >= 2
        if jumped || stateJump || workout.isActive { return Constants.rapidAlpha }
        if standardDeviation(hrvPoints.map(\.value)) < 6, standardDeviation(hrPoints.map(\.value)) < 6 {
            return Constants.stableAlpha
        }
        return Constants.baseAlpha
    }

    private func nextState(smoothedScore: Int, rawScore: Int, previous: StressResult?) -> StressState {
        let candidate = StressRules.state(for: smoothedScore)
        guard let previous, candidate != previous.state else { return candidate }
        if StressRules.rank(of: candidate) > StressRules.rank(of: previous.state) {
            return rawScore >= StressRules.thresholdLowerBound(for: candidate) ? candidate : previous.state
        }
        let releaseThreshold = StressRules.thresholdLowerBound(for: previous.state) - StressRules.downwardHysteresis
        return smoothedScore < releaseThreshold ? candidate : previous.state
    }

    private func dominantDrivers(
        hrvDeviation: Double?,
        hrvFreshnessWeight: Double,
        hrDeviation: Double?,
        hrvTrend: Double?,
        hrTrend: Double?,
        recoveryDebt: Int,
        recoveryAvailable: Bool,
        circadian: Int,
        workoutLoad: Int,
        workout: StressWorkoutContext
    ) -> [StressDominantDriver] {
        var contributions: [(StressDominantDriver, Double)] = []
        if let hrvDeviation {
            contributions.append((.hrvDeviation, max(0, hrvDeviation - 50) * 0.32 * hrvFreshnessWeight))
        }
        if let hrDeviation {
            contributions.append((.hrDeviation, max(0, hrDeviation - 50) * 0.22))
        }
        if let hrvTrend {
            contributions.append((.hrvTrend, max(0, hrvTrend - 50) * 0.14))
        }
        if let hrTrend {
            contributions.append((.hrTrend, max(0, hrTrend - 50) * 0.10))
        }
        if recoveryAvailable {
            contributions.append((.recoveryDebt, max(0, Double(recoveryDebt) - 50) * 0.14))
        }
        contributions.append((.circadian, max(0, Double(circadian) - 50) * 0.08))
        if workout.workoutBlend > 0 {
            contributions.append((.workoutLoad, max(0, Double(workoutLoad) - 50) * 0.28 * workout.workoutBlend))
        }
        return contributions
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map(\.0)
    }

    private func explanationCode(
        dominantDriver: StressDominantDriver,
        workout: StressWorkoutContext,
        recoveryDebt: Int,
        recoveryAvailable: Bool,
        hasElevatingDriver: Bool
    ) -> StressExplanationCode {
        guard hasElevatingDriver else { return .stablePhysiology }
        if workout.isActive && dominantDriver == .workoutLoad { return .physicalWorkoutLoad }
        if recoveryAvailable && recoveryDebt >= 65 { return .recoveryDebtElevated }
        switch dominantDriver {
        case .hrvDeviation: return .hrvBelowBaseline
        case .hrDeviation: return .heartRateAboveBaseline
        case .hrvTrend: return .hrvTrendingDown
        case .hrTrend: return .heartRateTrendingUp
        case .recoveryDebt: return .recoveryDebtElevated
        case .circadian: return .circadianLoadWindow
        case .workoutLoad: return .physicalWorkoutLoad
        }
    }

    private func confidenceScore(
        input: StressRealtimeInput,
        heartRate: StressMetricSample?,
        hrv: StressMetricSample?,
        hrvFreshnessWeight: Double,
        recoveryCompleteness: Double
    ) -> Double {
        var score = 0.0
        var possible = 0.0
        possible += 0.25
        if heartRate != nil { score += 0.25 }
        possible += 0.25
        if hrv != nil { score += 0.25 * hrvFreshnessWeight }
        possible += 0.20
        score += 0.10 * input.restingHeartRateBaseline.confidence
        score += 0.10 * input.hrvBaseline.confidence
        possible += 0.15
        let trendCoverage = min(1, Double(input.heartRatePoints30m.count + input.hrvPoints30m.count) / 12)
        score += 0.15 * trendCoverage
        possible += 0.15
        score += 0.15 * StressRules.clamp(recoveryCompleteness, lower: 0, upper: 1)
        return StressRules.clamp(score / max(possible, 1), lower: 0, upper: 1)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let values = values.sorted()
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count))
    }

    private func clampInt(_ value: Double) -> Int {
        StressRules.clamp(Int(value.rounded()))
    }
}
