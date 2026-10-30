import Foundation

// MARK: - 单次训练深度分析模型
//
// 这些模型只承载 HealthKit 原始样本的本机计算结果：路线 GPS/气压海拔、训练关联心率样本、
// 爬升记录。全部为内存态，不持久化、不入 App Group、不入 CloudKit；缺失指标由 UI 明确降级。

/// 详情页定位一次具体训练会话的锚点（来自当日 `WorkoutDaySummary` 的会话引用）。
struct WorkoutSessionReference: Sendable, Hashable, Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let activityTitle: String
    let durationMinutes: Double

    var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }
}

/// 海拔曲线绘制点。
struct WorkoutElevationSample: Sendable, Hashable, Identifiable {
    let offset: TimeInterval
    let elevationMeters: Double

    var id: TimeInterval { offset }
}

/// One heart-rate sample associated with a single HealthKit workout.
struct SwimmingHeartRateSample: Sendable, Hashable, Identifiable {
    let index: Int
    let offset: TimeInterval
    let beatsPerMinute: Double

    var id: Int { index }
}

/// In-memory heart-rate analysis for one swim. Samples remain linked to the exact HealthKit workout.
struct SwimmingWorkoutAnalysis: Sendable, Hashable {
    let workoutID: UUID
    let averageHeartRate: Double?
    let peakHeartRate: Double?
    let heartRateSamples: [SwimmingHeartRateSample]

    var hasHeartRateChart: Bool { heartRateSamples.count >= 2 }
}

/// Same-year swimming history for one workout: its rank inside the calendar month plus yearly totals.
/// Distances come from workout-level HealthKit statistics only; no lap or heart-rate samples are read.
struct SwimmingWorkoutHistorySummary: Sendable, Hashable {
    let workoutID: UUID
    let monthRank: Int
    let yearlyWorkoutCount: Int
    let yearlyDistanceMeters: Double
}

/// 一个分段（按 1 公里或按 5 分钟切分）的汇总。距离缺失时配速为 nil，不使用估算补位。
struct WorkoutSplitSummary: Sendable, Hashable, Identifiable {
    let index: Int
    let duration: TimeInterval
    let distanceKilometers: Double?
    let elevationGainMeters: Double?
    let averageHeartRate: Double?

    var paceSecondsPerKilometer: Double? {
        guard let distanceKilometers, distanceKilometers > 0.01, duration > 0 else { return nil }
        return duration / distanceKilometers
    }

    var id: Int { index }
}

/// 单次训练的深度分析报告。
struct WorkoutAnalysisReport: Sendable, Hashable {
    enum SplitKind: String, Sendable, Hashable {
        case distance
        case time

        var unitTitle: String {
            switch self {
            case .distance: return String(localized: "公里")
            case .time: return String(localized: "分钟")
            }
        }
    }

    let workoutID: UUID
    let startedAt: Date
    let duration: TimeInterval
    let totalDistanceKilometers: Double?
    let maxElevationMeters: Double?
    let totalAscentMeters: Double?
    let averageHeartRate: Double?
    let peakHeartRate: Double?
    let elevationProfile: [WorkoutElevationSample]
    let splits: [WorkoutSplitSummary]
    let splitKind: SplitKind

    var hasElevation: Bool { elevationProfile.count >= 2 }
    var hasSplits: Bool { splits.count >= 2 }
}

/// 训练深度分析的纯计算部分：只依赖样本数组，方便聚焦单测。
enum WorkoutAnalysisComputation {

    /// 分段时长：按时间切分时每段 5 分钟。
    static let timeSplitInterval: TimeInterval = 5 * 60
    /// 海拔计爬升的滞回阈值：累计上涨超过该值才计一次爬升，过滤气压抖动。
    static let ascentNoiseMeters: Double = 2

    // MARK: 报告组装

    /// 由原始轨迹样本组装报告；样本不足以构成分析时返回 nil，由调用方降级。
    static func buildReport(
        workoutID: UUID,
        startedAt: Date,
        duration: TimeInterval,
        totalDistanceKilometers: Double?,
        distanceTrack: [(offset: TimeInterval, kilometers: Double)],
        heartRateTrack: [(offset: TimeInterval, beatsPerMinute: Double)],
        elevationTrack: [(offset: TimeInterval, meters: Double)],
        recordedAscentMeters: Double?
    ) -> WorkoutAnalysisReport? {
        guard duration > 0 else { return nil }
        let hasTrackData = distanceTrack.count >= 2 || heartRateTrack.count >= 2 || elevationTrack.count >= 2
        guard hasTrackData else { return nil }

        let profile = elevationProfile(from: elevationTrack)
        let totalAscent = ascentGain(from: elevationTrack, minimumGainMeters: ascentNoiseMeters)
            ?? recordedAscentMeters

        let splitKind: WorkoutAnalysisReport.SplitKind
        let splits: [WorkoutSplitSummary]
        if let totalDistanceKilometers, totalDistanceKilometers >= 1,
           let byDistance = distanceSplits(
            distanceTrack: distanceTrack,
            heartRateTrack: heartRateTrack,
            elevationTrack: elevationTrack,
            totalDistanceKilometers: totalDistanceKilometers
           ), !byDistance.isEmpty {
            splitKind = .distance
            splits = byDistance
        } else {
            splitKind = .time
            splits = timeSplits(
                distanceTrack: distanceTrack,
                heartRateTrack: heartRateTrack,
                elevationTrack: elevationTrack,
                duration: duration
            )
        }

        let heartRates = heartRateTrack.map(\.beatsPerMinute).filter { $0 > 0 }
        let elevationValues = elevationTrack.map(\.meters)

        return WorkoutAnalysisReport(
            workoutID: workoutID,
            startedAt: startedAt,
            duration: duration,
            totalDistanceKilometers: totalDistanceKilometers,
            maxElevationMeters: elevationValues.max(),
            totalAscentMeters: totalAscent,
            averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
            peakHeartRate: heartRates.max(),
            elevationProfile: profile,
            splits: splits,
            splitKind: splitKind
        )
    }

    // MARK: 分段

    /// 按 1 公里切分分段。距离轨迹不足以定位分段边界时返回 nil。
    static func distanceSplits(
        distanceTrack: [(offset: TimeInterval, kilometers: Double)],
        heartRateTrack: [(offset: TimeInterval, beatsPerMinute: Double)],
        elevationTrack: [(offset: TimeInterval, meters: Double)],
        totalDistanceKilometers: Double
    ) -> [WorkoutSplitSummary]? {
        guard distanceTrack.count >= 2, totalDistanceKilometers >= 1 else { return nil }
        let track = distanceTrack.sorted { $0.offset < $1.offset }
        guard track.first?.kilometers == 0 || track.first!.kilometers < 1 else { return nil }

        let splitCount = Int(totalDistanceKilometers.rounded(.down))
        guard splitCount >= 1 else { return nil }

        var splits: [WorkoutSplitSummary] = []
        for index in 1...splitCount {
            guard let startOffset = offset(atKilometers: Double(index - 1), track: track),
                  let endOffset = offset(atKilometers: Double(index), track: track) else { break }
            let segmentDuration = endOffset - startOffset
            guard segmentDuration > 0 else { break }
            splits.append(
                WorkoutSplitSummary(
                    index: index,
                    duration: segmentDuration,
                    distanceKilometers: 1.0,
                    elevationGainMeters: ascentGain(
                        from: elevationTrack,
                        inOffsetRange: startOffset...endOffset,
                        minimumGainMeters: ascentNoiseMeters
                    ),
                    averageHeartRate: averageHeartRate(
                        from: heartRateTrack,
                        inOffsetRange: startOffset...endOffset
                    )
                )
            )
        }
        return splits
    }

    /// 按固定时长切分分段（最后一段允许不足整段）。样本覆盖不足时仍按时间轴输出，指标可为空。
    static func timeSplits(
        distanceTrack: [(offset: TimeInterval, kilometers: Double)],
        heartRateTrack: [(offset: TimeInterval, beatsPerMinute: Double)],
        elevationTrack: [(offset: TimeInterval, meters: Double)],
        duration: TimeInterval,
        interval: TimeInterval = timeSplitInterval
    ) -> [WorkoutSplitSummary] {
        guard duration >= interval, interval > 0 else { return [] }
        let track = distanceTrack.sorted { $0.offset < $1.offset }
        let splitCount = Int((duration / interval).rounded(.up))

        return (0..<splitCount).compactMap { index in
            let startOffset = TimeInterval(index) * interval
            let endOffset = min(startOffset + interval, duration)
            let segmentDuration = endOffset - startOffset
            guard segmentDuration > 0 else { return nil }
            let segmentDistance = distanceKilometers(atOffsetRange: startOffset...endOffset, track: track)
            return WorkoutSplitSummary(
                index: index + 1,
                duration: segmentDuration,
                distanceKilometers: segmentDistance,
                elevationGainMeters: ascentGain(
                    from: elevationTrack,
                    inOffsetRange: startOffset...endOffset,
                    minimumGainMeters: ascentNoiseMeters
                ),
                averageHeartRate: averageHeartRate(
                    from: heartRateTrack,
                    inOffsetRange: startOffset...endOffset
                )
            )
        }
    }

    // MARK: 海拔

    /// 海拔曲线：超长轨迹按等距抽样压缩到 maxCount 个点，保留首尾。
    static func elevationProfile(
        from track: [(offset: TimeInterval, meters: Double)],
        maxCount: Int = 90
    ) -> [WorkoutElevationSample] {
        let sorted = track.sorted { $0.offset < $1.offset }
        guard !sorted.isEmpty, maxCount >= 2 else { return [] }
        guard sorted.count > maxCount else {
            return sorted.map { WorkoutElevationSample(offset: $0.offset, elevationMeters: $0.meters) }
        }
        let stride = Double(sorted.count - 1) / Double(maxCount - 1)
        var samples: [WorkoutElevationSample] = []
        samples.reserveCapacity(maxCount)
        for step in 0..<maxCount {
            let index = Int((Double(step) * stride).rounded())
            let entry = sorted[min(index, sorted.count - 1)]
            samples.append(WorkoutElevationSample(offset: entry.offset, elevationMeters: entry.meters))
        }
        return samples
    }

    /// 累计爬升：滞回法过滤气压噪声——累计上涨超过噪声阈值才结算一段爬升，下坡后重置参考点。
    static func ascentGain(
        from track: [(offset: TimeInterval, meters: Double)],
        minimumGainMeters: Double = ascentNoiseMeters
    ) -> Double? {
        guard track.count >= 2 else { return nil }
        return ascentGain(from: track, inOffsetRange: nil, minimumGainMeters: minimumGainMeters)
    }

    static func averageHeartRate(
        from track: [(offset: TimeInterval, beatsPerMinute: Double)],
        inOffsetRange range: ClosedRange<TimeInterval>
    ) -> Double? {
        let values = track
            .filter { range.contains($0.offset) && $0.beatsPerMinute > 0 }
            .map(\.beatsPerMinute)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: 私有辅助方法

    /// 在分段窗口内计算爬升；窗口内样本不足 2 个时返回 nil。
    private static func ascentGain(
        from track: [(offset: TimeInterval, meters: Double)],
        inOffsetRange range: ClosedRange<TimeInterval>?,
        minimumGainMeters: Double
    ) -> Double? {
        let samples = track
            .sorted { $0.offset < $1.offset }
            .filter { sample in range.map { $0.contains(sample.offset) } ?? true }
            .map(\.meters)
        guard samples.count >= 2, minimumGainMeters >= 0 else { return nil }

        var gain = 0.0
        var reference = samples[0]
        for value in samples.dropFirst() {
            if value >= reference + minimumGainMeters {
                gain += value - reference
                reference = value
            } else if value < reference {
                reference = value
            }
        }
        return gain > 0 ? gain : (range == nil ? 0 : nil)
    }

    /// 定位累计距离首次达到目标公里数的时间点，段间线性插值。
    private static func offset(atKilometers target: Double, track: [(offset: TimeInterval, kilometers: Double)]) -> TimeInterval? {
        guard let first = track.first, let last = track.last else { return nil }
        if target <= first.kilometers { return first.offset }
        // 目标公里恰好等于全程距离时，边界就在最后一个采样点；只有超出全程才不可定位。
        if target > last.kilometers { return nil }

        var previous = first
        for entry in track.dropFirst() {
            defer { previous = entry }
            guard previous.kilometers < target, entry.kilometers >= target else { continue }
            let span = entry.kilometers - previous.kilometers
            guard span > 0 else { return entry.offset }
            let ratio = (target - previous.kilometers) / span
            return previous.offset + (entry.offset - previous.offset) * ratio
        }
        return last.offset
    }

    private static func distanceKilometers(
        atOffsetRange range: ClosedRange<TimeInterval>,
        track: [(offset: TimeInterval, kilometers: Double)]
    ) -> Double? {
        guard track.count >= 2 else { return nil }
        guard let startDistance = kilometers(atOffset: range.lowerBound, track: track),
              let endDistance = kilometers(atOffset: range.upperBound, track: track) else { return nil }
        let segment = endDistance - startDistance
        return segment > 0.01 ? segment : nil
    }

    private static func kilometers(atOffset target: TimeInterval, track: [(offset: TimeInterval, kilometers: Double)]) -> Double? {
        guard let first = track.first, let last = track.last else { return nil }
        if target <= first.offset { return first.kilometers }
        if target >= last.offset { return last.kilometers }

        var previous = first
        for entry in track.dropFirst() {
            defer { previous = entry }
            guard previous.offset < target, entry.offset >= target else { continue }
            let span = entry.offset - previous.offset
            guard span > 0 else { return entry.kilometers }
            let ratio = (target - previous.offset) / span
            return previous.kilometers + (entry.kilometers - previous.kilometers) * ratio
        }
        return nil
    }
}
