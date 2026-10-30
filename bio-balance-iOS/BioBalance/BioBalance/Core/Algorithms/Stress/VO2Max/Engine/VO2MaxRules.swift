import Foundation

enum VO2MaxRules {
    static let algorithmVersion = VO2MaxDailyAssessment.currentAlgorithmVersion
    static let dashboardRollingWindowDays = 7
    static let estimatedRange = 18.0...65.0
    static let plausibleActualRange = 10.0...90.0
    static let minimumRunningDurationMinutes = 5.0
    static let minimumRunningDistanceKilometers = 0.5

    struct ResolvedValue: Equatable {
        let value: Double
        let source: VO2MaxSource
    }

    struct TrendSample: Equatable {
        let date: Date
        let value: Double
        let confidence: Int
    }

    static func latestAssessment(
        onOrBefore referenceDate: Date,
        in assessments: [VO2MaxDailyAssessment],
        maximumAgeDays: Int = 30,
        calendar: Calendar = .current
    ) -> VO2MaxDailyAssessment? {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let eligible = assessments
            .filter { calendar.startOfDay(for: $0.date) <= referenceDay }
        guard let latest = eligible.max(by: { $0.date < $1.date }) else { return nil }
        let latestDay = calendar.startOfDay(for: latest.date)
        let ageDays = calendar.dateComponents([.day], from: latestDay, to: referenceDay).day ?? Int.max
        return ageDays <= max(maximumAgeDays, 0) ? latest : nil
    }

    /// 今日页心肺能力按滚动 7 个自然日展示，保留低频 VO₂ Max 样本的最新一次结果。
    static func assessmentsInDashboardRollingWeek(
        onOrBefore referenceDate: Date,
        in assessments: [VO2MaxDailyAssessment],
        calendar: Calendar = .current
    ) -> [VO2MaxDailyAssessment] {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.date(
            byAdding: .day,
            value: -(dashboardRollingWindowDays - 1),
            to: referenceDay
        ) ?? referenceDay
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: referenceDay)
            ?? referenceDay.addingTimeInterval(86_400)

        return assessments
            .filter {
                $0.value.isFinite
                    && $0.value > 0
                    && $0.date >= startDay
                    && $0.date < endExclusive
            }
            .sorted { $0.date < $1.date }
    }

    static func latestAssessmentInDashboardRollingWeek(
        onOrBefore referenceDate: Date,
        in assessments: [VO2MaxDailyAssessment],
        calendar: Calendar = .current
    ) -> VO2MaxDailyAssessment? {
        assessmentsInDashboardRollingWeek(
            onOrBefore: referenceDate,
            in: assessments,
            calendar: calendar
        ).last
    }

    static func validActual(_ value: Double?) -> Double? {
        guard let value, value.isFinite, plausibleActualRange.contains(value) else { return nil }
        return roundToOneDecimal(value)
    }

    static func isQualifiedRunningSample(
        durationMinutes: Double,
        distanceKilometers: Double,
        averageHeartRate: Double,
        paceSecondsPerKm: Double
    ) -> Bool {
        durationMinutes.isFinite
            && distanceKilometers.isFinite
            && averageHeartRate.isFinite
            && paceSecondsPerKm.isFinite
            && durationMinutes >= minimumRunningDurationMinutes
            && distanceKilometers >= minimumRunningDistanceKilometers
            && averageHeartRate > 0
            && paceSecondsPerKm > 0
    }

    static func hasMinimumEvidence(
        actualVO2: Double?,
        hasRestingHeartRate: Bool,
        hasHrv: Bool,
        hasWalking: Bool,
        hasRunning: Bool,
        hasRecovery: Bool
    ) -> Bool {
        if validActual(actualVO2) != nil || hasWalking || hasRunning { return true }
        return hasRestingHeartRate && (hasHrv || hasRecovery)
    }

    static func weightedScore(
        rhr: Double?,
        hrv: Double?,
        walking: Double?,
        running: Double?,
        recovery: Double?
    ) -> Double? {
        let weightedPairs: [(Double?, Double)] = [
            (rhr, 0.20),
            (hrv, 0.15),
            (walking, 0.20),
            (running, 0.30),
            (recovery, 0.15)
        ]
        var sum = 0.0
        var totalWeight = 0.0

        for (value, weight) in weightedPairs {
            guard let value, value.isFinite else { continue }
            sum += clamp(value) * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }
        return clamp(sum / totalWeight)
    }

    static func resolveValue(
        actualVO2: Double?,
        estimatedValue: Double?,
        hasInterpretiveContext: Bool
    ) -> ResolvedValue? {
        if let actual = validActual(actualVO2) {
            return ResolvedValue(
                value: actual,
                source: hasInterpretiveContext ? .engineBlended : .healthKitActual
            )
        }
        guard let estimate = estimatedValue, estimate.isFinite else { return nil }
        return ResolvedValue(
            value: roundToOneDecimal(min(max(estimate, estimatedRange.lowerBound), estimatedRange.upperBound)),
            source: .engineEstimated
        )
    }

    static func fitnessLevel(value: Double, age: Int?, sex: String?) -> VO2MaxFitnessLevel {
        let thresholds = fitnessThresholds(age: age, sex: sex)
        switch value {
        case let value where value >= thresholds.excellent: return .excellent
        case let value where value >= thresholds.good: return .good
        case let value where value >= thresholds.average: return .average
        case let value where value >= thresholds.belowAverage: return .belowAverage
        default: return .poor
        }
    }

    static func confidenceBreakdown(
        actualVO2: Double?,
        inputs: VO2MaxInputCoverage,
        runningSampleCount: Int,
        walkingSampleCount: Int
    ) -> VO2MaxConfidenceBreakdown {
        let hasActual = validActual(actualVO2) != nil
        let sourceScore: Int
        if hasActual {
            sourceScore = 95
        } else if inputs.running {
            sourceScore = 74
        } else if inputs.walking {
            sourceScore = 62
        } else if inputs.rhr && (inputs.hrv || inputs.recovery) {
            sourceScore = 45
        } else {
            sourceScore = 25
        }

        let coverageCount = [inputs.rhr, inputs.hrv, inputs.walking, inputs.running, inputs.recovery]
            .filter { $0 }
            .count
        let coverageScore = clampInt(coverageCount * 18 + (hasActual ? 10 : 0), lower: 20, upper: 95)
        let activityQuality = min(max(runningSampleCount, 0), 4) * 12
            + min(max(walkingSampleCount, 0), 4) * 8
        let qualityScore = clampInt(activityQuality + (inputs.recovery ? 15 : 0), lower: 25, upper: 90)
        let weighted = Int((Double(sourceScore) * 0.45
            + Double(coverageScore) * 0.30
            + Double(qualityScore) * 0.25).rounded())
        let finalScore = hasActual
            ? clampInt(max(90, weighted), lower: 90, upper: 95)
            : clampInt(weighted, lower: 25, upper: 85)

        return VO2MaxConfidenceBreakdown(
            sourceScore: sourceScore,
            coverageScore: coverageScore,
            qualityScore: qualityScore,
            finalScore: finalScore
        )
    }

    static func smoothedValue(
        current: Double,
        source: VO2MaxSource,
        previous: Double?,
        previousSource: VO2MaxSource?,
        daysSincePrevious: Int?
    ) -> Double {
        guard source == .engineEstimated,
              previousSource == .engineEstimated,
              daysSincePrevious == 1,
              let previous,
              previous.isFinite else {
            return roundToOneDecimal(current)
        }
        let delta = min(max(current - previous, -0.7), 0.7)
        return roundToOneDecimal(previous + delta)
    }

    static func driverDirection(for score: Double) -> VO2MaxDriverDirection {
        if score >= 55 { return .positive }
        if score <= 45 { return .negative }
        return .neutral
    }

    static func trend(
        samples: [TrendSample],
        calendar: Calendar = .current
    ) -> VO2MaxTrend {
        let valid = samples
            .filter { $0.value.isFinite && plausibleActualRange.contains($0.value) && $0.confidence >= 50 }
            .sorted { $0.date < $1.date }
        guard let latestDate = valid.last?.date else { return .stable }
        let recentStart = calendar.date(byAdding: .day, value: -6, to: latestDate) ?? latestDate
        let previousStart = calendar.date(byAdding: .day, value: -13, to: latestDate) ?? latestDate
        let previousEnd = calendar.date(byAdding: .day, value: -7, to: latestDate) ?? latestDate
        let recent = valid.filter { $0.date >= recentStart && $0.date <= latestDate }
        let previous = valid.filter { $0.date >= previousStart && $0.date <= previousEnd }
        guard recent.count >= 3, previous.count >= 3 else { return .stable }

        let recentAverage = recent.map(\.value).reduce(0, +) / Double(recent.count)
        let previousAverage = previous.map(\.value).reduce(0, +) / Double(previous.count)
        let meaningfulDelta = max(0.8, previousAverage * 0.02)
        let delta = recentAverage - previousAverage

        if delta >= meaningfulDelta { return .improving }
        if delta <= -meaningfulDelta { return .declining }
        return .stable
    }

    private enum SexCategory {
        case male
        case female
        case unspecified
    }

    private static func fitnessThresholds(
        age: Int?,
        sex: String?
    ) -> (excellent: Double, good: Double, average: Double, belowAverage: Double) {
        let resolvedAge = min(max(age ?? 35, 18), 100)
        let male: (Double, Double, Double, Double)
        let female: (Double, Double, Double, Double)

        switch resolvedAge {
        case ..<30:
            male = (52, 46, 40, 34)
            female = (44, 39, 34, 29)
        case ..<40:
            male = (49, 43, 37, 32)
            female = (41, 36, 31, 27)
        case ..<50:
            male = (46, 40, 34, 29)
            female = (38, 33, 28, 24)
        case ..<60:
            male = (43, 37, 32, 27)
            female = (36, 31, 26, 23)
        default:
            male = (39, 34, 29, 24)
            female = (33, 28, 24, 20)
        }

        switch sexCategory(sex) {
        case .male:
            return male
        case .female:
            return female
        case .unspecified:
            return (
                (male.0 + female.0) / 2,
                (male.1 + female.1) / 2,
                (male.2 + female.2) / 2,
                (male.3 + female.3) / 2
            )
        }
    }

    private static func sexCategory(_ value: String?) -> SexCategory {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "男", "男性", "male", "m": return .male
        case "女", "女性", "female", "f": return .female
        default: return .unspecified
        }
    }

    private static func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
        min(max(value, lower), upper)
    }

    private static func clampInt(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    private static func roundToOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
