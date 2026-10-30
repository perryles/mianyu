import Foundation

nonisolated enum StressDailyEngine {
    static func evaluate(input: StressDailyInput) -> StressEvaluation {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: input.now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
        let valid = input.samples.filter {
            $0.score >= 0 && $0.score <= 100
                && $0.date >= startOfDay && $0.date < endOfDay
                && $0.algorithmVersion == StressResult.currentAlgorithmVersion
                && $0.source == .realtime
                && $0.quality != .unavailable
        }
        guard !valid.isEmpty else { return .unavailable(.noDailySamples) }

        let startTimestamp = Int64(startOfDay.timeIntervalSince1970)
        let buckets = Dictionary(grouping: valid) {
            ($0.timestamp - startTimestamp) / StressRules.dailyBucketSeconds
        }
        let bucketSamples = buckets.values.compactMap(resolveBucket).sorted { $0.timestamp < $1.timestamp }
        guard bucketSamples.count >= StressRules.minimumDailyBuckets,
              let first = bucketSamples.first,
              let latest = bucketSamples.last,
              latest.date.timeIntervalSince(first.date) >= StressRules.minimumDailySpan else {
            return .unavailable(.insufficientDailyCoverage)
        }

        let scores = bucketSamples.map { Double($0.score) }
        let average = scores.reduce(0, +) / Double(scores.count)
        let peak = percentile(scores, percentile: 0.90)
        let resolved = StressRules.clamp(average * 0.70 + Double(latest.score) * 0.20 + peak * 0.10)
        let score = Int(resolved.rounded())
        let confidenceMean = bucketSamples.map(\.confidence).reduce(0, +) / Double(bucketSamples.count)
        let coverageConfidence = min(1, Double(bucketSamples.count) / 12)
        let confidence = StressRules.clamp(confidenceMean * 0.75 + coverageConfidence * 0.25, lower: 0, upper: 1)
        let dominantDrivers = mostFrequentDrivers(in: bucketSamples)
        let dominant = dominantDrivers.first ?? .hrvDeviation
        let explanation: StressExplanationCode
        if peak >= 70, peak - average >= 12 {
            explanation = .dailyPeakElevated
        } else if average >= 50 {
            explanation = .dailyAverageElevated
        } else {
            explanation = .stableDailyLoad
        }
        let state = StressRules.state(for: score)
        let recovery = StressRecoverySnapshot(
            recoveryScore: 50,
            recoveryDebt: 50,
            sleepMinutes: nil,
            sleepEfficiency: nil,
            nightlyHrv: nil,
            overnightMinHeartRate: nil
        )
        let result = StressResult(
            timestamp: latest.timestamp,
            rawScore: score,
            smoothedScore: score,
            state: state,
            band: StressRules.band(for: score),
            dominantDriver: dominant,
            dominantDrivers: dominantDrivers,
            explanationCode: explanation,
            confidence: confidence,
            quality: StressRules.quality(for: confidence),
            algorithmVersion: StressResult.currentAlgorithmVersion,
            recovery: recovery,
            workout: .inactive,
            components: StressComponentScores(
                hrvDeviation: 0,
                hrDeviation: 0,
                hrvTrend: 0,
                hrTrend: 0,
                recoveryDebt: 0,
                circadian: 0,
                workoutLoad: 0,
                mentalRaw: Int(average.rounded()),
                physicalRaw: Int(peak.rounded()),
                rawScore: score,
                smoothedScore: score
            )
        )
        return .available(result)
    }

    static func instantaneousStress(
        hrv: Double,
        heartRate: Double,
        restingHeartRate: Double?,
        recentAvgHrv: Double? = nil,
        priorHeartRate: Double? = nil
    ) -> Int {
        guard hrv > 0 || heartRate > 0 else { return 0 }

        let hrvComponent: Double? = {
            guard hrv > 0 else { return nil }
            if let recentAvgHrv {
                return StressSignalScoring.hrvDeviation(current: hrv, baseline: recentAvgHrv)
            }
            // 历史视图可能没有个人 HRV 基线；保留
            // 旧的纯 HRV 估算以维持图表连续性，但设备未提供 HRV 时
            // 绝不能虚构 HRV 贡献。
            return StressSignalScoring.historicalHrvWithoutBaseline(hrv)
        }()
        let heartRateComponent = restingHeartRate.flatMap {
            StressSignalScoring.heartRateDeviation(current: heartRate, baseline: $0)
        }
        let heartRateTrend = priorHeartRate.flatMap {
            StressSignalScoring.heartRateTrend(recent: heartRate, prior: $0)
        }
        let resolved = StressSignalScoring.weightedMean([
            (hrvComponent, 0.32),
            (heartRateComponent, 0.22),
            (heartRateTrend, 0.10)
        ])

        guard let resolved else { return 0 }
        return max(1, StressRules.clamp(Int(resolved.rounded())))
    }

    static func nearestHeartRate(to date: Date, in points: [TimeSeriesPoint]) -> Double? {
        let points = points.sorted { $0.timestamp < $1.timestamp }
        return nearestHeartRate(to: date, inSorted: points)
    }

    static func resolvedRestingHeartRateBaseline(
        measured: Double?,
        historical: Double?,
        heartRate: [TimeSeriesPoint]
    ) -> Double? {
        let validRange = HealthBaselineMetric.restingHeartRate.validRange
        if let measured, measured.isFinite, validRange.contains(measured) {
            return measured
        }
        if let historical, historical.isFinite, validRange.contains(historical) {
            return historical
        }

        let validHeartRates = heartRate
            .map { Double($0.value) }
            .filter { $0.isFinite && validRange.contains($0) }
            .sorted()
        guard validHeartRates.count >= 3 else { return nil }

        let lowerSampleCount = max(1, Int(ceil(Double(validHeartRates.count) * 0.20)))
        return median(Array(validHeartRates.prefix(lowerSampleCount)))
    }

    private static func nearestHeartRate(to date: Date, inSorted points: [TimeSeriesPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        let target = Int64(date.timeIntervalSince1970)
        let insertion = lowerBound(in: points, timestamp: target)
        if insertion == points.count { return Double(points[points.count - 1].value) }
        var nearest = points[insertion]
        if insertion > 0, abs(points[insertion - 1].timestamp - target) < abs(nearest.timestamp - target) {
            nearest = points[insertion - 1]
        }
        return Double(nearest.value)
    }

    static func sevenMinuteStressPoints(
        hrv: [TimeSeriesPointDouble],
        heartRate: [TimeSeriesPoint],
        restingHeartRate: Double?,
        restingHeartRateBaseline: Double? = nil,
        hrvBaseline: Double? = nil,
        in interval: DateInterval
    ) -> [TimeSeriesPoint] {
        let hrvPoints = hrv.filter { $0.value > 0 && interval.contains($0.date) }.sorted { $0.timestamp < $1.timestamp }
        let heartRatePoints = heartRate.filter { $0.value > 0 && interval.contains($0.date) }.sorted { $0.timestamp < $1.timestamp }
        let start = Int64(interval.start.timeIntervalSince1970)
        let heartBuckets = Dictionary(grouping: heartRatePoints) { ($0.timestamp - start) / StressRules.dailyBucketSeconds }
        let hrvBuckets = Dictionary(grouping: hrvPoints) { ($0.timestamp - start) / StressRules.dailyBucketSeconds }
        let resolvedHrvBaseline = hrvBaseline.flatMap { $0 > 0 ? $0 : nil } ?? median(hrvPoints.map(\.value))
        let resolvedRestingHeartRateBaseline = Self.resolvedRestingHeartRateBaseline(
            measured: restingHeartRate,
            historical: restingHeartRateBaseline,
            heartRate: heartRatePoints
        )

        return Set(heartBuckets.keys).union(hrvBuckets.keys).sorted().compactMap { bucket in
            let timestamp = start + bucket * StressRules.dailyBucketSeconds
            let midpoint = Date(timeIntervalSince1970: TimeInterval(timestamp + StressRules.dailyBucketSeconds / 2))
            let bucketHeartRates = heartBuckets[bucket]?.map { Double($0.value) } ?? []
            let heartRate = average(bucketHeartRates) ?? nearestHeartRate(to: midpoint, inSorted: heartRatePoints)
            let midpointTimestamp = Int64(midpoint.timeIntervalSince1970)
            let priorHeartRates = values(
                inSorted: heartRatePoints,
                from: midpointTimestamp - 30 * 60,
                to: midpointTimestamp - 5 * 60
            )
            let bucketHrv = hrvBuckets[bucket]?.map(\.value) ?? []
            let hrv = average(bucketHrv) ?? nearestFreshHrv(to: midpoint, inSorted: hrvPoints) ?? 0
            guard heartRate != nil || hrv > 0 else { return nil }
            let score = instantaneousStress(
                hrv: hrv,
                heartRate: heartRate ?? 0,
                restingHeartRate: resolvedRestingHeartRateBaseline,
                recentAvgHrv: resolvedHrvBaseline,
                priorHeartRate: median(priorHeartRates)
            )
            return score > 0 ? TimeSeriesPoint(timestamp: timestamp, value: score) : nil
        }
    }

    private static func resolveBucket(_ samples: [StressDailySample]) -> StressDailySample? {
        guard !samples.isEmpty else { return nil }
        let scores = samples.map(\.score).sorted()
        let confidence = samples.map(\.confidence).reduce(0, +) / Double(samples.count)
        let quality = samples.map(\.quality).min() ?? .unavailable
        let latest = samples.max { $0.timestamp < $1.timestamp }!
        return StressDailySample(
            timestamp: latest.timestamp,
            score: scores[scores.count / 2],
            confidence: confidence,
            quality: quality,
            algorithmVersion: StressResult.currentAlgorithmVersion,
            source: .realtime,
            dominantDriver: latest.dominantDriver
        )
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double {
        let values = values.sorted()
        guard !values.isEmpty else { return 0 }
        let index = min(values.count - 1, max(0, Int(ceil(percentile * Double(values.count))) - 1))
        return values[index]
    }

    private static func mostFrequentDrivers(in samples: [StressDailySample]) -> [StressDominantDriver] {
        let counts = Dictionary(grouping: samples.compactMap(\.dominantDriver), by: { $0 }).mapValues(\.count)
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
        }.prefix(2).map(\.key)
    }

    private static func nearestFreshHrv(to date: Date, inSorted points: [TimeSeriesPointDouble]) -> Double? {
        guard !points.isEmpty else { return nil }
        let target = Int64(date.timeIntervalSince1970)
        let insertion = lowerBound(in: points, timestamp: target)
        let nearest: TimeSeriesPointDouble
        if insertion == points.count {
            nearest = points[points.count - 1]
        } else if insertion > 0,
                  abs(points[insertion - 1].timestamp - target) < abs(points[insertion].timestamp - target) {
            nearest = points[insertion - 1]
        } else {
            nearest = points[insertion]
        }
        guard abs(nearest.date.timeIntervalSince(date)) <= StressRules.hrvMaximumFreshness else { return nil }
        return nearest.value
    }

    private static func values(
        inSorted points: [TimeSeriesPoint],
        from startTimestamp: Int64,
        to endTimestamp: Int64
    ) -> [Double] {
        guard startTimestamp < endTimestamp, !points.isEmpty else { return [] }
        let startIndex = lowerBound(in: points, timestamp: startTimestamp)
        let endIndex = lowerBound(in: points, timestamp: endTimestamp)
        guard startIndex < endIndex else { return [] }
        return points[startIndex..<endIndex].map { Double($0.value) }
    }

    private static func lowerBound(in points: [TimeSeriesPoint], timestamp: Int64) -> Int {
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if points[middle].timestamp < timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func lowerBound(in points: [TimeSeriesPointDouble], timestamp: Int64) -> Int {
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if points[middle].timestamp < timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let values = values.sorted()
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}
