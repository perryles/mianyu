import AVFoundation
import Combine
import CloudKit
import Foundation
import HealthKit
import os

struct SleepAudioFrameFeatures: Sendable {
    let rms: Double
    let spectralFlux: Double
    let dominantBandHz: Double
    let mfcc: [Double]
    let melBands: [Double]
}

protocol SleepSessionRepository: Sendable {
    func latestSummary() async -> SleepSessionSummary?
    func recentSummaries(limit: Int) async -> [SleepSessionSummary]
    func save(summary: SleepSessionSummary) async
    func save(state: SleepMonitoringState) async
    func latestState() async -> SleepMonitoringState?
    func save(snoreSegments: [SnoreSegmentSummary], for sessionId: String) async
}

extension SleepSessionRepository {
    func recentSummaries(limit: Int) async -> [SleepSessionSummary] {
        guard limit > 0, let latest = await latestSummary() else { return [] }
        return [latest]
    }
}

protocol SleepAudioFeatureStore: Sendable {
    func replaceLatest(features: [SleepAudioFrameFeatures]) async
    func latestFeatures() async -> [SleepAudioFrameFeatures]
}

protocol SleepCloudSyncing: Sendable {
    func sync(summary: SleepSessionSummary) async throws
    func restoreLatestSummary() async throws -> SleepSessionSummary?
}

extension SleepCloudSyncing {
    func restoreLatestSummary() async throws -> SleepSessionSummary? { nil }
}

protocol SleepHealthKitWriting: Sendable {
    func shouldWriteSupplementalSleep(for summary: SleepSessionSummary) async -> Bool
    func writeSupplementalSleep(summary: SleepSessionSummary) async throws
}

nonisolated final class InMemorySleepAudioFeatureStore: SleepAudioFeatureStore, @unchecked Sendable {
    private var latest: [SleepAudioFrameFeatures] = []
    private let lock = NSLock()

    func replaceLatest(features: [SleepAudioFrameFeatures]) async {
        lock.withLock {
            latest = features
        }
    }

    func latestFeatures() async -> [SleepAudioFrameFeatures] {
        lock.withLock {
            latest
        }
    }
}

nonisolated final class LocalSleepSessionStore: SleepSessionRepository, @unchecked Sendable {
    private enum Keys {
        static let latestSummary = "sleep.monitoring.latestSummary.v1"
        static let summaryHistory = "sleep.monitoring.summaryHistory.v1"
        static let latestState = "sleep.monitoring.latestState.v1"
        static let segments = "sleep.monitoring.latestSegments.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? .standard
    }

    func latestSummary() async -> SleepSessionSummary? {
        guard let data = defaults.data(forKey: Keys.latestSummary) else { return nil }
        return try? JSONDecoder().decode(SleepSessionSummary.self, from: data)
    }

    func save(summary: SleepSessionSummary) async {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        defaults.set(data, forKey: Keys.latestSummary)

        var history = await recentSummaries(limit: 90)
        history.removeAll { $0.sessionId == summary.sessionId }
        history.append(summary)
        history.sort { $0.endTime > $1.endTime }
        history = Array(history.prefix(90))
        if let historyData = try? JSONEncoder().encode(history) {
            defaults.set(historyData, forKey: Keys.summaryHistory)
        }
    }

    func recentSummaries(limit: Int) async -> [SleepSessionSummary] {
        guard limit > 0 else { return [] }
        var summaries: [SleepSessionSummary] = []
        if let data = defaults.data(forKey: Keys.summaryHistory),
           let decoded = try? JSONDecoder().decode([SleepSessionSummary].self, from: data) {
            summaries = decoded
        }
        if let latest = await latestSummary(), !summaries.contains(where: { $0.sessionId == latest.sessionId }) {
            summaries.append(latest)
        }
        return Array(summaries.sorted { $0.endTime > $1.endTime }.prefix(limit))
    }

    func save(state: SleepMonitoringState) async {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Keys.latestState)
    }

    func latestState() async -> SleepMonitoringState? {
        guard let data = defaults.data(forKey: Keys.latestState) else { return nil }
        return try? JSONDecoder().decode(SleepMonitoringState.self, from: data)
    }

    func save(snoreSegments: [SnoreSegmentSummary], for sessionId: String) async {
        let payload = ["sessionId": sessionId, "segments": snoreSegments] as [String : Any]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        defaults.set(data, forKey: Keys.segments)
    }
}

nonisolated struct SleepScoringEngine {
    /// 根据已标准化的传感器输入构建完整且确定性的摘要。
    ///
    /// - Important: `now` is the evaluation clock. Callers replaying historical
    ///   输入必须传入原始评估时间，不能依赖
    ///   默认值。
    func makeSummary(
        sleepInterval: SleepInterval?,
        sleepDurationMinutes: Int,
        watchConfidence: Double,
        existingStages: [SleepStage],
        nightlyHrv: Double?,
        awakeCount: Int,
        snoreSummary: SnoreAnalysisSummary,
        source: SleepMonitorActivationSource,
        recentBedtimes: [Date] = [],
        sleepGoalMinutes: Int = SleepGoalResolver.goalMinutes(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SleepSessionSummary {
        let normalizedDuration = max(0, sleepDurationMinutes)
        let stageSummary = inferStages(durationMinutes: normalizedDuration, awakeCount: awakeCount, existingStages: existingStages)
        let temporalEvidence = SleepTemporalEvidenceAdapter().resolve(
            sleepInterval: sleepInterval,
            durationMinutes: normalizedDuration,
            stages: existingStages
        )
        let regularityEvidence = SleepRegularityEvidenceAdapter().resolve(
            currentBedtime: temporalEvidence.timeInBedMinutes == nil ? nil : sleepInterval?.start,
            recentBedtimes: recentBedtimes,
            calendar: calendar
        )
        let breakdown = score(
            durationMinutes: normalizedDuration,
            continuityScore: stageSummary.continuityScore,
            timeInBedMinutes: temporalEvidence.timeInBedMinutes,
            wakeAfterSleepOnsetMinutes: temporalEvidence.wakeAfterSleepOnsetMinutes,
            snoreSummary: snoreSummary,
            deepMinutes: stageSummary.deepSleepMinutesEstimated,
            remMinutes: stageSummary.remSleepMinutesEstimated,
            hasMeasuredStages: !existingStages.isEmpty,
            bedtimeDeviationMinutes: regularityEvidence.bedtimeDeviationMinutes,
            sleepGoalMinutes: sleepGoalMinutes
        )
        let insight = makeInsight(
            score: breakdown.sleepScore,
            durationMinutes: normalizedDuration,
            snoreSummary: snoreSummary,
            continuityScore: breakdown.continuityScore,
            generatedAt: now
        )

        return SleepSessionSummary(
            sessionId: Self.sessionId(for: sleepInterval?.start ?? now, end: sleepInterval?.end ?? now),
            sourceDate: calendar.startOfDay(for: sleepInterval?.end ?? now),
            startTime: sleepInterval?.start ?? calendar.date(byAdding: .minute, value: -normalizedDuration, to: now) ?? now,
            endTime: sleepInterval?.end ?? now,
            sleepDurationMinutes: normalizedDuration,
            sleepScore: breakdown.sleepScore,
            sleepContinuityScore: breakdown.continuityScore,
            stageSummary: stageSummary,
            snoreSummary: snoreSummary,
            insight: insight,
            watchConfidence: max(0, min(1, watchConfidence)),
            deviceSource: "watch+iphone",
            analysisVersion: HealthEngineVersion.sleepScoring,
            createdAt: now,
            updatedAt: now,
            source: source
        )
    }

    private func inferStages(durationMinutes: Int, awakeCount: Int, existingStages: [SleepStage]) -> SleepStageInferenceSummary {
        let duration = max(0, durationMinutes)
        let wakes = max(0, awakeCount)

        if !existingStages.isEmpty {
            // HealthKit 通常会为每个阶段返回多个样本；应汇总
            // 所有非负区间，而不是只取第一个。
            let deep = stageMinutes(in: existingStages) { $0.contains("深") || $0.localizedCaseInsensitiveContains("deep") }
            let light = stageMinutes(in: existingStages) { $0.contains("浅") || $0.localizedCaseInsensitiveContains("core") || $0.localizedCaseInsensitiveContains("light") }
            let rem = stageMinutes(in: existingStages) { $0.contains("快速") || $0.localizedCaseInsensitiveContains("rem") }
            let normalized = normalizeStages(deep: deep, light: light, rem: rem, duration: duration)
            let continuity = max(45, min(100, 100 - wakes * 8))
            return SleepStageInferenceSummary(
                deepSleepMinutesEstimated: normalized.deep,
                lightSleepMinutesEstimated: normalized.light,
                remSleepMinutesEstimated: normalized.rem,
                wakeCount: wakes,
                sleepLatencyMinutes: wakes > 0 ? 18 : 12,
                continuityScore: continuity
            )
        }

        // 基于比例的推断保证阶段总时长永远不会
        // 超过观测到的睡眠时长，包含小睡和零时长输入。
        let deep = Double(duration) * 0.22
        let rem = Double(duration) * 0.24
        let light = max(0, Double(duration) - deep - rem)
        return SleepStageInferenceSummary(
            deepSleepMinutesEstimated: deep,
            lightSleepMinutesEstimated: light,
            remSleepMinutesEstimated: rem,
            wakeCount: wakes,
            sleepLatencyMinutes: wakes > 1 ? 20 : 14,
            continuityScore: max(42, min(100, 94 - wakes * 7))
        )
    }

    private func stageMinutes(in stages: [SleepStage], matching predicate: (String) -> Bool) -> Double {
        Double(stages.reduce(into: 0) { total, stage in
            if predicate(stage.stage) {
                total += max(0, stage.duration)
            }
        })
    }

    private func normalizeStages(
        deep: Double,
        light: Double,
        rem: Double,
        duration: Int
    ) -> (deep: Double, light: Double, rem: Double) {
        guard duration > 0 else { return (0, 0, 0) }
        let observedTotal = deep + light + rem
        guard observedTotal > 0 else {
            let total = Double(duration)
            return (total * 0.22, total * 0.54, total * 0.24)
        }
        let target = Double(duration)
        if observedTotal > target {
            let scale = target / observedTotal
            return (deep * scale, light * scale, rem * scale)
        }
        // 未分类的睡眠时间按浅睡处理；这是恢复类别中
        // 最不具体的一类，避免虚构深睡或 REM 证据。
        return (deep, light + target - observedTotal, rem)
    }

    private func score(
        durationMinutes: Int,
        continuityScore: Int,
        timeInBedMinutes: Int?,
        wakeAfterSleepOnsetMinutes: Int?,
        snoreSummary: SnoreAnalysisSummary,
        deepMinutes: Double,
        remMinutes: Double,
        hasMeasuredStages: Bool,
        bedtimeDeviationMinutes: Double?,
        sleepGoalMinutes: Int
    ) -> SleepQualityBreakdown {
        let durationRatio = min(1.0, Double(durationMinutes) / Double(max(sleepGoalMinutes, 1)))
        let durationScore = Int((durationRatio * 100.0).rounded())
        let restorativeRatio = min(1.0, max(0.0, (deepMinutes + remMinutes) / Double(max(durationMinutes, 1))))
        let restorativeScore = Int((restorativeRatio / 0.46 * 100.0).rounded())
        let snoreImpactScore = max(0, 100 - snoreSummary.disturbanceScore)
        let hasDisturbanceEvidence = snoreSummary.snoreDetected
            || snoreSummary.disturbanceScore > 0
            || !snoreSummary.segments.isEmpty
        let rhythmResult = SleepRhythmScoringEngine().evaluate(
            SleepRhythmScoreInput(
                durationMinutes: durationMinutes,
                goalMinutes: sleepGoalMinutes,
                timeInBedMinutes: timeInBedMinutes,
                wakeAfterSleepOnsetMinutes: wakeAfterSleepOnsetMinutes,
                fallbackContinuityScore: continuityScore,
                deepSleepMinutes: deepMinutes,
                remSleepMinutes: remMinutes,
                stageEvidence: hasMeasuredStages ? .measured : .inferred,
                bedtimeDeviationMinutes: bedtimeDeviationMinutes,
                regularityEvidence: .derived,
                disturbanceScore: hasDisturbanceEvidence ? snoreSummary.disturbanceScore : nil
            )
        )
        return SleepQualityBreakdown(
            sleepScore: rhythmResult.score ?? 0,
            snoreImpactScore: snoreImpactScore,
            continuityScore: continuityScore,
            durationScore: durationScore,
            restorativeScore: max(0, min(100, restorativeScore))
        )
    }

    private func makeInsight(
        score: Int,
        durationMinutes: Int,
        snoreSummary: SnoreAnalysisSummary,
        continuityScore: Int,
        generatedAt: Date
    ) -> SleepInsightSnapshot {
        let headline: String
        let summary: String
        let code: String
        let recommendation: String
        let risk: SleepInsightRiskFlag

        if snoreSummary.intensity == .high || snoreSummary.disturbanceScore >= 55 {
            headline = "鼾声干扰偏明显"
            summary = "昨夜睡眠被鼾声与夜间中断影响，恢复质量偏保守。"
            code = "snore_reduce_disturbance"
            recommendation = "今晚尽量侧睡，避免临睡前饮酒，并继续观察连续几晚是否都出现明显鼾声。"
            risk = .elevated
        } else if score >= 82 && continuityScore >= 80 {
            headline = "昨夜恢复较稳"
            summary = "睡眠时长与连续性都在较理想区间，夜间干扰不明显。"
            code = "sleep_keep_rhythm"
            recommendation = "继续保持当前作息节奏，白天尽量把咖啡因和高强度训练放到更早时段。"
            risk = .none
        } else if durationMinutes < 390 {
            headline = "时长仍偏短"
            summary = "昨夜主睡眠不算太差，但总时长不足会拖慢今天的恢复储备。"
            code = "sleep_extend_duration"
            recommendation = "今晚优先把入睡时间提前 20 到 30 分钟，先补足整体时长。"
            risk = .monitor
        } else {
            headline = "节律还可以更稳"
            summary = "昨夜基础睡眠已形成，但连续性和恢复深度还有优化空间。"
            code = "sleep_stabilize_rhythm"
            recommendation = "今晚保持固定入睡时间，并减少睡前 2 小时内的刺激与噪声。"
            risk = snoreSummary.snoreDetected ? .monitor : .none
        }

        return SleepInsightSnapshot(
            headline: headline,
            summary: summary,
            recommendationCode: code,
            recommendationText: recommendation,
            riskFlag: risk,
            generatedAt: generatedAt,
            modelVersion: "sleep-insight-v1"
        )
    }

    private static func sessionId(for start: Date, end: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return "\(formatter.string(from: start))__\(formatter.string(from: end))"
    }
}

nonisolated final class SleepAudioCaptureService {
    private let engine = AVAudioEngine()
    private let inferenceWorker: SleepAudioInferenceWorker
    private let stateLock = NSLock()
    private var isMonitoringStorage = false
    private var latestWindowRMSStorage: Double = 0
    private var inputSampleRate: Double = 16_000
    private var currentWindowSamples: [Float] = []
    private var currentWindowStartDate: Date?

    nonisolated init(inferenceProvider: any SleepAudioInferenceProviding = SleepAudioInferenceProviderFactory.makeDefault()) {
        inferenceWorker = SleepAudioInferenceWorker(provider: inferenceProvider)
    }

    var isMonitoring: Bool {
        stateLock.withLock { isMonitoringStorage }
    }

    var latestWindowRMS: Double {
        stateLock.withLock { latestWindowRMSStorage }
    }

    func startMonitoring() async throws {
        guard !isMonitoring else { return }
        try await Self.requestMicrophonePermission()
        await inferenceWorker.reset()
        try await inferenceWorker.prepare()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setPreferredSampleRate(16_000)
        try session.setPreferredIOBufferDuration(0.025)
        try session.setActive(true, options: [])

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        stateLock.withLock {
            inputSampleRate = format.sampleRate
            currentWindowSamples = []
            currentWindowStartDate = Date()
            latestWindowRMSStorage = 0
            isMonitoringStorage = true
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?.pointee else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: frameLength))
            self?.append(samples: samples)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            stateLock.withLock { isMonitoringStorage = false }
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            throw error
        }
    }

    @MainActor
    private static func requestMicrophonePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw SleepAudioInferenceError.microphonePermissionDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else {
                throw SleepAudioInferenceError.microphonePermissionDenied
            }
        @unknown default:
            throw SleepAudioInferenceError.microphonePermissionDenied
        }
    }

    @discardableResult
    func stopMonitoring() async -> [SleepAudioInferenceResult] {
        if isMonitoring {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }

        let finalWindow = stateLock.withLock { () -> SleepAudioWindow? in
            isMonitoringStorage = false
            return takeCurrentWindowIfNeeded()
        }
        if let finalWindow {
            inferenceWorker.enqueueWindows([finalWindow])
        }
        return await inferenceWorker.drainAndCollectResults()
    }

    private func append(samples: [Float]) {
        guard !samples.isEmpty else { return }
        let completedWindows = stateLock.withLock { () -> [SleepAudioWindow] in
            guard isMonitoringStorage else { return [] }
            if currentWindowStartDate == nil { currentWindowStartDate = Date() }
            currentWindowSamples.append(contentsOf: samples)

            let sumSquares = samples.reduce(0.0) { partial, sample in
                let value = Double(sample)
                return partial + value * value
            }
            latestWindowRMSStorage = sqrt(sumSquares / Double(samples.count))

            let windowLength = max(1, Int(inputSampleRate))
            var windows: [SleepAudioWindow] = []
            while currentWindowSamples.count >= windowLength {
                let windowStartDate = currentWindowStartDate ?? Date()
                windows.append(
                    SleepAudioWindow(
                        samples: Array(currentWindowSamples.prefix(windowLength)),
                        startDate: windowStartDate,
                        sampleRate: inputSampleRate
                    )
                )
                currentWindowSamples.removeFirst(windowLength)
                currentWindowStartDate = windowStartDate.addingTimeInterval(
                    Double(windowLength) / inputSampleRate
                )
            }
            return windows
        }
        inferenceWorker.enqueueWindows(completedWindows)
    }

    /// 调用方必须持有 `stateLock`。
    private func takeCurrentWindowIfNeeded() -> SleepAudioWindow? {
        guard !currentWindowSamples.isEmpty else { return nil }
        let window = SleepAudioWindow(
            samples: currentWindowSamples,
            startDate: currentWindowStartDate ?? Date(),
            sampleRate: inputSampleRate
        )
        currentWindowSamples = []
        currentWindowStartDate = nil
        return window
    }
}

nonisolated struct SnoreDetectionPipeline {
    private static let minimumNormalizedActivity = 0.16
    private static let maximumMergeGapSeconds: TimeInterval = 3
    private static let minimumEventEvidenceSeconds: TimeInterval = 2

    private struct CandidateEvent {
        var start: Date
        var end: Date
        var activeDurationSeconds: TimeInterval
        var peakNormalizedActivity: Double

        mutating func merge(
            start candidateStart: Date,
            end candidateEnd: Date,
            normalizedActivity: Double
        ) {
            let nonOverlappingDuration = max(0, candidateEnd.timeIntervalSince(max(candidateStart, end)))
            activeDurationSeconds += nonOverlappingDuration
            end = max(end, candidateEnd)
            peakNormalizedActivity = max(peakNormalizedActivity, normalizedActivity)
        }
    }

    func analyze(
        inferenceResults: [SleepAudioInferenceResult],
        durationHours: Double,
        stageSummary: SleepStageInferenceSummary,
        interval: SleepInterval?
    ) -> SnoreAnalysisSummary {
        guard durationHours > 0, !inferenceResults.isEmpty else {
            return .empty
        }

        let events = makeCandidateEvents(from: inferenceResults, interval: interval).filter {
            $0.activeDurationSeconds >= Self.minimumEventEvidenceSeconds
        }
        guard !events.isEmpty else { return .empty }

        let segments = events.map(makeSegment)
        let normalized = events.map(\.peakNormalizedActivity).max() ?? 0
        let snoreMinutes = events.reduce(0) { $0 + $1.activeDurationSeconds } / 60
        let disturbances = min(
            100,
            Int((normalized * 68.0 + Double(stageSummary.wakeCount * 5)).rounded())
        )
        let intensity = intensity(for: normalized)
        let start = interval?.start
            ?? inferenceResults.map(\.startDate).min()
            ?? events[0].start
        let histogram = makeHistogram(segments: segments, start: start)
        let risk: SleepInsightRiskFlag = intensity == .high || disturbances >= 55
            ? .elevated
            : .monitor

        return SnoreAnalysisSummary(
            snoreDetected: true,
            snoreDurationMinutes: snoreMinutes,
            snoreFrequencyPerHour: Double(segments.count) / durationHours,
            intensity: intensity,
            disturbanceScore: disturbances,
            riskFlag: risk,
            segments: segments,
            histogram: histogram
        )
    }

    private func makeCandidateEvents(
        from inferenceResults: [SleepAudioInferenceResult],
        interval: SleepInterval?
    ) -> [CandidateEvent] {
        let candidates = inferenceResults
            .filter { result in
                let candidateEnd = result.startDate.addingTimeInterval(result.durationSeconds)
                let isInsideSession = interval.map {
                    result.startDate >= $0.start && candidateEnd <= $0.end
                } ?? true
                return result.activity == .active
                    && result.rootMeanSquare.isFinite
                    && result.durationSeconds.isFinite
                    && result.durationSeconds > 0
                    && isInsideSession
                    && normalizedActivity(for: result) > Self.minimumNormalizedActivity
            }
            .sorted { $0.startDate < $1.startDate }

        var events: [CandidateEvent] = []
        for candidate in candidates {
            let candidateEnd = candidate.startDate.addingTimeInterval(candidate.durationSeconds)
            let normalized = normalizedActivity(for: candidate)
            if var current = events.last,
               candidate.startDate.timeIntervalSince(current.end) <= Self.maximumMergeGapSeconds {
                current.merge(
                    start: candidate.startDate,
                    end: candidateEnd,
                    normalizedActivity: normalized
                )
                events[events.count - 1] = current
            } else {
                events.append(CandidateEvent(
                    start: candidate.startDate,
                    end: candidateEnd,
                    activeDurationSeconds: candidate.durationSeconds,
                    peakNormalizedActivity: normalized
                ))
            }
        }
        return events
    }

    private func normalizedActivity(for result: SleepAudioInferenceResult) -> Double {
        min(1, max(0, result.rootMeanSquare * 12))
    }

    private func makeSegment(from event: CandidateEvent) -> SnoreSegmentSummary {
        let normalized = event.peakNormalizedActivity
        return SnoreSegmentSummary(
            segmentStart: event.start,
            segmentEnd: event.end,
            durationSeconds: event.activeDurationSeconds,
            intensity: intensity(for: normalized),
            peakDbfsBucket: min(12, max(1, Int((normalized * 12).rounded()))),
            confidence: min(0.98, max(0.52, normalized + min(0.2, event.activeDurationSeconds / 20))),
            disturbanceWeight: min(1, max(0.18, normalized))
        )
    }

    private func intensity(for normalized: Double) -> SleepSnoreIntensity {
        switch normalized {
        case ..<Self.minimumNormalizedActivity: return .none
        case ..<0.33: return .low
        case ..<0.58: return .medium
        default: return .high
        }
    }

    private func makeHistogram(segments: [SnoreSegmentSummary], start: Date) -> [Int] {
        var histogram = Array(repeating: 0, count: 6)
        let bucketSize: TimeInterval = 90 * 60
        for segment in segments {
            let idx = min(5, max(0, Int(segment.segmentStart.timeIntervalSince(start) / bucketSize)))
            histogram[idx] += 1
        }
        return histogram
    }
}

nonisolated final class SleepFocusTriggerService {
    private let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? .standard
    }

    func shouldAutoArm() -> Bool {
        defaults.object(forKey: "sleepMonitoringAutoArmEnabled") as? Bool ?? true
    }

    func setAutoArmEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "sleepMonitoringAutoArmEnabled")
    }
}

/// 睡眠会话摘要の CloudKit 跨设备同步服务。
///
/// ## 数据隔离
/// - Zone：`CloudKitDataPolicy.Zone.sleep`（独立 private zone，用户可控）。
/// - Record type：`BBSleepSession`，每次监测结束后以 `sessionId` 作为 record name
///   写入一条不可变摘要。仅包含数值型结构化字段（时长、评分、连续性分数等），不含
///   音频、音频特征、打鼾片段、详细阶段估计或本地自然语言解释。
///
/// ## 同步开关
/// `PreferenceKey.sleepSummarySyncEnabled` 默认开启；用户关闭后不再上传或恢复摘要。
///
/// ## 账号绑定
/// 通过 `AccountBindingKey.sleepSummary` 绑定上次成功同步的 Apple ID；
/// 账号变更时静默停止自动上传，用户重新开启后才绑定新账号。
///
/// ## 失败不阻塞
/// CloudKit 失败不会影响本地睡眠分析或 HealthKit 回写。
///
/// ## CKSyncEngine 迁移路径（iOS 17+）
/// 当睡眠记录数量显著增长或需要实时增量推送时，可通过调用
/// `CloudKitSyncTransportResolver.enableSyncEngine(forZone: CloudKitDataPolicy.Zone.sleep)`
/// 启用增量同步模式。zone / record type 保持不变，仅替换底层 transport。
nonisolated final class SleepCloudKitSyncService: SleepCloudSyncing, @unchecked Sendable {
    private enum Schema {
        // Zone 与 record type 集中登记在 CloudKitDataPolicy，保证与已部署 schema 一致。
        static let zoneName = CloudKitDataPolicy.Zone.sleep
        static let sessionRecordType = CloudKitDataPolicy.RecordType.sleepSession
        static let currentVersion: Int64 = 2
        static let accountBindingKey = CloudKitDataPolicy.AccountBindingKey.sleepSummary

        static let sessionID = "sessionId"
        static let sourceDate = "sourceDate"
        static let startTime = "startTime"
        static let endTime = "endTime"
        static let sleepDurationMinutes = "sleepDurationMinutes"
        static let sleepScore = "sleepScore"
        static let sleepContinuityScore = "sleepContinuityScore"
        static let watchConfidence = "watchConfidence"
        static let analysisVersion = "analysisVersion"
        static let deviceSource = "deviceSource"
        static let recommendationCode = "recommendationCode"
        static let riskFlag = "riskFlag"
    }

    private let container: CKContainer
    private let client: CloudKitClientProtocol
    private let executor: CloudKitOperationExecutor
    private let database: CKDatabase
    private let preferences: UserDefaults
    private let zoneID = CKRecordZone.ID(
        zoneName: Schema.zoneName,
        ownerName: CKCurrentUserDefaultName
    )

    /// 当前传输模式：legacy（全量查询）或 syncEngine（增量同步）。
    private let transportMode: CloudKitSyncTransportMode

    /// CKSyncEngine 传输层实例（仅在 `.syncEngine` 模式下非 nil）。
    private var syncEngineTransport: AnyObject?

    nonisolated init(
        container: CKContainer? = nil,
        client: CloudKitClientProtocol? = nil,
        executor: CloudKitOperationExecutor? = nil,
        preferences: UserDefaults? = nil,
        transportMode: CloudKitSyncTransportMode? = nil
    ) {
        let resolvedContainer = container ?? CloudKitDataPolicy.makeContainer()
        self.container = resolvedContainer
        self.client = client ?? CloudKitClient()
        self.executor = executor ?? CloudKitOperationExecutor()
        self.database = resolvedContainer.privateCloudDatabase
        self.preferences = preferences ?? .standard
        self.transportMode = transportMode
            ?? CloudKitSyncTransportResolver.resolveMode(forZone: Schema.zoneName)
    }

    func sync(summary: SleepSessionSummary) async throws {
        // 敏感健康摘要必须由用户主动开启；历史版本没有该 key 时保持关闭。
        guard preferences.bool(forKey: CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled) else {
            return
        }

        let accountIdentifier = try await preparePrivateDatabase()
        let sessionRecordID = CKRecord.ID(recordName: summary.sessionId, zoneID: zoneID)
        let sessionRecord = CKRecord(recordType: Schema.sessionRecordType, recordID: sessionRecordID)

        // 只同步可恢复的结构化摘要。音频、音频特征、打鼾片段、详细阶段估计和
        // 本地生成的自然语言解释均不得进入 CloudKit。
        sessionRecord[Schema.sessionID] = summary.sessionId as CKRecordValue
        sessionRecord[Schema.sourceDate] = summary.sourceDate as CKRecordValue
        sessionRecord[Schema.startTime] = summary.startTime as CKRecordValue
        sessionRecord[Schema.endTime] = summary.endTime as CKRecordValue
        sessionRecord[Schema.sleepDurationMinutes] = Int64(summary.sleepDurationMinutes) as CKRecordValue
        sessionRecord[Schema.sleepScore] = Int64(summary.sleepScore) as CKRecordValue
        sessionRecord[Schema.sleepContinuityScore] = Int64(summary.sleepContinuityScore) as CKRecordValue
        sessionRecord[Schema.watchConfidence] = summary.watchConfidence as CKRecordValue
        sessionRecord[Schema.analysisVersion] = summary.analysisVersion as CKRecordValue
        sessionRecord[Schema.deviceSource] = summary.deviceSource as CKRecordValue
        sessionRecord[Schema.recommendationCode] = summary.insight.recommendationCode as CKRecordValue
        sessionRecord[Schema.riskFlag] = summary.insight.riskFlag.rawValue as CKRecordValue
        sessionRecord[CloudKitDataPolicy.MetadataField.createdAt] = summary.createdAt as CKRecordValue
        sessionRecord[CloudKitDataPolicy.MetadataField.updatedAt] = summary.updatedAt as CKRecordValue
        sessionRecord[CloudKitDataPolicy.MetadataField.schemaVersion] = Schema.currentVersion as CKRecordValue

        _ = try await executor.run(
            context: CloudKitLoggerContext(
                operation: "save-sleep-summary",
                database: .private,
                zoneID: zoneID.zoneName,
                recordID: sessionRecordID.recordName
            )
        ) { [container, client, database] in
            let current = try await client.fetchUserRecordID(container: container)
            guard current.recordName == accountIdentifier else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            return try await client.modify(
                recordsToSave: [sessionRecord],
                recordIDsToDelete: [],
                savePolicy: .changedKeys,
                in: database
            )
        }
        try await verifyCurrentAccount(accountIdentifier)
        preferences.set(accountIdentifier, forKey: Schema.accountBindingKey)
    }

    /// 恢复最近一条跨设备摘要。云端只保存最小摘要，因此详细阶段、鼾声片段和
    /// 自然语言分析仍保持本机专属；恢复失败也不会覆盖已有的本地结果。
    func restoreLatestSummary() async throws -> SleepSessionSummary? {
        guard preferences.bool(forKey: CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled) else {
            return nil
        }

        let accountIdentifier = try await preparePrivateDatabase()
        let records = try await fetchAllSessionRecords()
        try await verifyCurrentAccount(accountIdentifier)
        preferences.set(accountIdentifier, forKey: Schema.accountBindingKey)

        return records
            .compactMap(Self.decodeSummary)
            .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
    }

    private func preparePrivateDatabase() async throws -> String {
        let status = try await executor.run(
            context: CloudKitLoggerContext(operation: "sleep-account-status", database: .private)
        ) { [container, client] in
            try await client.accountStatus(container: container)
        }
        guard status == .available else {
            throw CloudKitDomainError.iCloudUnavailable
        }

        let accountIdentifier = try await executor.run(
            context: CloudKitLoggerContext(operation: "sleep-account-identity", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }
        try validateAccountBinding(accountIdentifier)

        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await executor.run(
            context: CloudKitLoggerContext(
                operation: "prepare-sleep-zone",
                database: .private,
                zoneID: zoneID.zoneName
            )
        ) { [container, client, database] in
            let current = try await client.fetchUserRecordID(container: container)
            guard current.recordName == accountIdentifier else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            return try await client.save(zone: zone, in: database)
        }
        return accountIdentifier
    }

    private func validateAccountBinding(_ accountIdentifier: String) throws {
        guard let previous = preferences.string(forKey: Schema.accountBindingKey),
              previous != accountIdentifier else { return }

        // 不把上一 Apple ID 的本机摘要自动写入新账号。用户需要再次主动开启同步，
        // 才会建立新的账号绑定。
        preferences.set(false, forKey: CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled)
        preferences.removeObject(forKey: Schema.accountBindingKey)
        throw CloudKitDomainError.iCloudUnavailable
    }

    private func verifyCurrentAccount(_ accountIdentifier: String) async throws {
        let current = try await executor.run(
            context: CloudKitLoggerContext(operation: "verify-sleep-account", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }
        guard current == accountIdentifier else {
            preferences.set(false, forKey: CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled)
            preferences.removeObject(forKey: Schema.accountBindingKey)
            throw CloudKitDomainError.iCloudUnavailable
        }
    }

    private func fetchAllSessionRecords() async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        do {
            repeat {
                let currentCursor = cursor
                let page = try await executor.run(
                    context: CloudKitLoggerContext(
                        operation: "fetch-sleep-summaries",
                        database: .private,
                        zoneID: zoneID.zoneName
                    )
                ) { [client, database, zoneID] in
                    try await client.runQuery(
                        query: currentCursor == nil
                            ? CKQuery(recordType: Schema.sessionRecordType, predicate: NSPredicate(value: true))
                            : nil,
                        cursor: currentCursor,
                        zoneID: zoneID,
                        in: database
                    )
                }
                records.append(contentsOf: page.records)
                cursor = page.cursor
            } while cursor != nil
            return records
        } catch CloudKitDomainError.unknownItem {
            return []
        }
    }

    nonisolated static func decodeSummary(_ record: CKRecord) -> SleepSessionSummary? {
        guard let sourceDate = record[Schema.sourceDate] as? Date,
              let startTime = record[Schema.startTime] as? Date,
              let endTime = record[Schema.endTime] as? Date,
              let duration = record[Schema.sleepDurationMinutes] as? NSNumber,
              let score = record[Schema.sleepScore] as? NSNumber,
              let continuity = record[Schema.sleepContinuityScore] as? NSNumber else {
            return nil
        }

        let createdAt = record[CloudKitDataPolicy.MetadataField.createdAt] as? Date
            ?? record.creationDate
            ?? sourceDate
        let updatedAt = record[CloudKitDataPolicy.MetadataField.updatedAt] as? Date
            ?? record.modificationDate
            ?? createdAt
        let riskFlag = (record[Schema.riskFlag] as? String)
            .flatMap(SleepInsightRiskFlag.init(rawValue:))
            ?? .none
        let recommendationCode = record[Schema.recommendationCode] as? String ?? "sleep_cloud_summary"

        return SleepSessionSummary(
            sessionId: record[Schema.sessionID] as? String ?? record.recordID.recordName,
            sourceDate: sourceDate,
            startTime: startTime,
            endTime: endTime,
            sleepDurationMinutes: duration.intValue,
            sleepScore: score.intValue,
            sleepContinuityScore: continuity.intValue,
            stageSummary: .empty,
            snoreSummary: .empty,
            insight: SleepInsightSnapshot(
                headline: "iCloud 睡眠摘要",
                summary: "已恢复睡眠时段、评分和连续性；详细阶段与本机分析不会上传。",
                recommendationCode: recommendationCode,
                recommendationText: "在本机完成新一次睡眠分析后可查看完整建议。",
                riskFlag: riskFlag,
                generatedAt: updatedAt,
                modelVersion: "sleep-cloud-summary-v2"
            ),
            watchConfidence: (record[Schema.watchConfidence] as? NSNumber)?.doubleValue ?? 0,
            deviceSource: record[Schema.deviceSource] as? String ?? "icloud",
            analysisVersion: record[Schema.analysisVersion] as? String ?? "sleep-analysis-v1",
            createdAt: createdAt,
            updatedAt: updatedAt,
            source: .manual
        )
    }

    // MARK: - CKSyncEngine 模式支持

    /// 初始化 CKSyncEngine 传输层（仅 `.syncEngine` 模式时生效）。
    ///
    /// 首次迁移时 CKSyncEngine 将执行一次全量 fetch，保证已有云端数据不丢失。
    func initializeSyncEngineIfNeeded() {
        guard transportMode == .syncEngine else { return }
        let config = CloudKitDataPolicy.syncEngineConfig(
            forZone: Schema.zoneName,
            recordTypes: [Schema.sessionRecordType],
            conflictPolicy: .lastWriteWins
        )
        let handler = SleepSyncEventHandler()
        let transport = CloudKitSyncEngineTransport(
            config: config,
            container: container,
            preferences: preferences,
            eventHandler: handler
        )
        transport.initialize()
        syncEngineTransport = transport
    }

    /// 在 SyncEngine 模式下通知有新的睡眠摘要待上传。
    func notifyLocalChange(sessionRecordID: CKRecord.ID) {
        guard transportMode == .syncEngine else { return }
        (syncEngineTransport as? CloudKitSyncEngineTransport)?.scheduleSend(recordIDs: [sessionRecordID])
    }

    /// 在 SyncEngine 模式下手动触发一次增量 fetch。
    func fetchRemoteChanges() async throws {
        guard transportMode == .syncEngine else { return }
        try await (syncEngineTransport as? CloudKitSyncEngineTransport)?.fetchChanges()
    }
}

// MARK: - Sleep SyncEngine 事件处理

/// 睡眠仓储的 CKSyncEngine 事件处理实现。
nonisolated final class SleepSyncEventHandler: CloudKitSyncEngineEventHandler, @unchecked Sendable {
    func didReceiveRemoteChanges(_ records: [CKRecord], deletedRecordIDs: [CKRecord.ID]) async {
        guard !records.isEmpty || !deletedRecordIDs.isEmpty else { return }
        NotificationCenter.default.post(
            name: .sleepSummaryRemoteChangeReceived,
            object: nil,
            userInfo: [
                "savedRecords": records,
                "deletedRecordIDs": deletedRecordIDs
            ]
        )
    }

    func pendingRecordsToSave() async -> [CKRecord] { [] }
    func pendingRecordIDsToDelete() async -> [CKRecord.ID] { [] }

    func didSaveRecords(_ savedRecords: [CKRecord]) async {
        NotificationCenter.default.post(
            name: .sleepSummarySyncDidComplete,
            object: nil,
            userInfo: ["savedRecords": savedRecords]
        )
    }

    func didDeleteRecordIDs(_ deletedIDs: [CKRecord.ID]) async {}
}

extension Notification.Name {
    /// CKSyncEngine 模式下收到远程睡眠摘要变更。
    nonisolated static let sleepSummaryRemoteChangeReceived = Notification.Name("sleepSummaryRemoteChangeReceived")
    /// CKSyncEngine 模式下睡眠摘要上传完成。
    nonisolated static let sleepSummarySyncDidComplete = Notification.Name("sleepSummarySyncDidComplete")
}

nonisolated struct SleepHealthKitWriter: SleepHealthKitWriting {
    nonisolated init() {}

    func shouldWriteSupplementalSleep(for summary: SleepSessionSummary) async -> Bool {
        guard UserDefaults.standard.bool(forKey: "sleepMonitoringHealthKitWritebackEnabled") else {
            return false
        }
        guard summary.sleepDurationMinutes > 0 else { return false }
        let current = try? await HealthKitManager.shared.fetchLatestSleepInterval()
        guard let current else { return true }
        return abs(current.start.timeIntervalSince(summary.startTime)) > 45 * 60
            || abs(current.end.timeIntervalSince(summary.endTime)) > 45 * 60
    }

    func writeSupplementalSleep(summary: SleepSessionSummary) async throws {
        try await HealthKitManager.shared.saveSupplementalSleepSession(start: summary.startTime, end: summary.endTime)
    }
}

@MainActor
@Observable
final class SleepMonitoringOrchestrator {
    @MainActor static let shared = SleepMonitoringOrchestrator()
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "SleepCloudKit")

    private(set) var state: SleepMonitoringState = SleepMonitoringState()
    private(set) var latestSummary: SleepSessionSummary?

    private let triggerService: SleepFocusTriggerService
    private let audioCaptureService: SleepAudioCaptureService
    private let audioFeatureStore: SleepAudioFeatureStore
    private let sessionRepository: SleepSessionRepository
    private let cloudSyncer: SleepCloudSyncing
    private let healthKitWriter: SleepHealthKitWriting
    private let scoringEngine = SleepScoringEngine()
    private let snorePipeline = SnoreDetectionPipeline()

    @MainActor
    private init(
        triggerService: SleepFocusTriggerService? = nil,
        audioCaptureService: SleepAudioCaptureService? = nil,
        audioFeatureStore: SleepAudioFeatureStore? = nil,
        sessionRepository: SleepSessionRepository? = nil,
        cloudSyncer: SleepCloudSyncing? = nil,
        healthKitWriter: SleepHealthKitWriting? = nil
    ) {
        self.triggerService = triggerService ?? SleepFocusTriggerService()
        self.audioCaptureService = audioCaptureService ?? SleepAudioCaptureService()
        self.audioFeatureStore = audioFeatureStore ?? InMemorySleepAudioFeatureStore()
        self.sessionRepository = sessionRepository ?? LocalSleepSessionStore()
        self.cloudSyncer = cloudSyncer ?? SleepCloudKitSyncService()
        self.healthKitWriter = healthKitWriter ?? SleepHealthKitWriter()
        Task { await restoreState() }
    }

    func restoreState() async {
        state = await sessionRepository.latestState() ?? SleepMonitoringState()
        // 睡眠数据只从本地读取（本机 Store / HealthKit），不向 CloudKit 拉取恢复，
        // 避免云端旧摘要覆盖或干扰本机睡眠展示。CloudKit 仅保留可选备份上传。
        latestSummary = await sessionRepository.latestSummary()
    }

    func recentSummaries(limit: Int = 90) async -> [SleepSessionSummary] {
        await sessionRepository.recentSummaries(limit: limit)
    }

    /// 检测进行中的实时环境声音电平（设备端窗口 RMS），仅供 UI 呈现当前安静程度。
    var latestEnvironmentRMS: Double { audioCaptureService.latestWindowRMS }

    func armForSleep(source: SleepMonitorActivationSource, watchConnected: Bool, watchConfidence: Double) async {
        let newState = SleepMonitoringState(
            phase: .armed,
            activationSource: source,
            startedAt: Date(),
            updatedAt: Date(),
            watchConnected: watchConnected,
            watchConfidence: watchConfidence,
            isAudioMonitoringActive: false,
            lastErrorDescription: nil
        )
        state = newState
        await sessionRepository.save(state: newState)
    }

    func startMonitoringIfNeeded() async {
        guard state.phase == .armed || state.phase == .monitoring else { return }
        do {
            try await audioCaptureService.startMonitoring()
            let newState = SleepMonitoringState(
                phase: .monitoring,
                activationSource: state.activationSource,
                startedAt: state.startedAt ?? Date(),
                updatedAt: Date(),
                watchConnected: state.watchConnected,
                watchConfidence: state.watchConfidence,
                isAudioMonitoringActive: true,
                lastErrorDescription: nil
            )
            state = newState
            await sessionRepository.save(state: newState)
        } catch {
            let failed = SleepMonitoringState(
                phase: .armed,
                activationSource: state.activationSource,
                startedAt: state.startedAt,
                updatedAt: Date(),
                watchConnected: state.watchConnected,
                watchConfidence: state.watchConfidence,
                isAudioMonitoringActive: false,
                lastErrorDescription: error.localizedDescription
            )
            state = failed
            await sessionRepository.save(state: failed)
        }
    }

    func finalizeSleepSession(
        interval: SleepInterval?,
        durationMinutes: Int,
        stages: [SleepStage],
        nightlyHrv: Double?,
        awakeCount: Int,
        recentBedtimes: [Date] = [],
        allowsHealthKitWriteback: Bool = true
    ) async {
        guard durationMinutes > 0 else { return }
        let finalizing = SleepMonitoringState(
            phase: .finalizing,
            activationSource: state.activationSource,
            startedAt: state.startedAt,
            updatedAt: Date(),
            watchConnected: state.watchConnected,
            watchConfidence: state.watchConfidence,
            isAudioMonitoringActive: false,
            lastErrorDescription: nil
        )
        state = finalizing
        await sessionRepository.save(state: finalizing)

        let inferenceResults = await audioCaptureService.stopMonitoring()

        let stageSummary = scoringEngine.makeSummary(
            sleepInterval: interval,
            sleepDurationMinutes: durationMinutes,
            watchConfidence: finalizing.watchConfidence,
            existingStages: stages,
            nightlyHrv: nightlyHrv,
            awakeCount: awakeCount,
            snoreSummary: .empty,
            source: finalizing.activationSource,
            recentBedtimes: recentBedtimes
        ).stageSummary
        let snoreSummary = snorePipeline.analyze(
            inferenceResults: inferenceResults,
            durationHours: Double(durationMinutes) / 60.0,
            stageSummary: stageSummary,
            interval: interval
        )
        let summary = scoringEngine.makeSummary(
            sleepInterval: interval,
            sleepDurationMinutes: durationMinutes,
            watchConfidence: finalizing.watchConfidence,
            existingStages: stages,
            nightlyHrv: nightlyHrv,
            awakeCount: awakeCount,
            snoreSummary: snoreSummary,
            source: finalizing.activationSource,
            recentBedtimes: recentBedtimes
        )
        latestSummary = summary
        await sessionRepository.save(summary: summary)
        await sessionRepository.save(snoreSegments: snoreSummary.segments, for: summary.sessionId)

        if allowsHealthKitWriteback,
           await healthKitWriter.shouldWriteSupplementalSleep(for: summary) {
            try? await healthKitWriter.writeSupplementalSleep(summary: summary)
        }
        do {
            try await cloudSyncer.sync(summary: summary)
        } catch {
            // 本地睡眠结果已经提交成功，iCloud 失败不能回滚或隐藏本地记录。
            Self.logger.error("[SleepCloudKit] summary sync failed error=\(error.localizedDescription, privacy: .public)")
        }

        let synced = SleepMonitoringState(
            phase: .surfaced,
            activationSource: finalizing.activationSource,
            startedAt: finalizing.startedAt,
            updatedAt: Date(),
            watchConnected: finalizing.watchConnected,
            watchConfidence: finalizing.watchConfidence,
            isAudioMonitoringActive: false,
            lastErrorDescription: nil
        )
        state = synced
        await sessionRepository.save(state: synced)
    }

    func stopMonitoringAndReset() async {
        await audioCaptureService.stopMonitoring()
        let idle = SleepMonitoringState(
            phase: .idle,
            activationSource: state.activationSource,
            startedAt: nil,
            updatedAt: Date(),
            watchConnected: state.watchConnected,
            watchConfidence: state.watchConfidence,
            isAudioMonitoringActive: false,
            lastErrorDescription: nil
        )
        state = idle
        await sessionRepository.save(state: idle)
    }

    func autoArmIfEnabled(watchConnected: Bool, watchConfidence: Double) async {
        guard triggerService.shouldAutoArm() else { return }
        await armForSleep(source: .sleepFocusAutomation, watchConnected: watchConnected, watchConfidence: watchConfidence)
    }
}
