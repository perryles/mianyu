import AVFoundation
import Foundation
import SwiftUI

nonisolated struct SnoreAnalysisLayoutMetrics: Equatable {
    let containerWidth: CGFloat

    init(containerWidth: CGFloat) {
        self.containerWidth = containerWidth.isFinite && containerWidth > 0 ? containerWidth : 320
    }

    var maximumContentWidth: CGFloat { min(containerWidth, 720) }
    var contentHorizontalPadding: CGFloat { containerWidth < 420 ? 16 : 20 }
    var contentWidth: CGFloat { max(0, maximumContentWidth - contentHorizontalPadding * 2) }
    var usesWideSummary: Bool { contentWidth >= 580 }
    var distributionColumnCount: Int { usesWideSummary ? 4 : 2 }
    var weekItemSpacing: CGFloat { usesWideSummary ? 12 : 4 }
    var weekCardHorizontalPadding: CGFloat { 14 }
    var dayIndicatorDiameter: CGFloat {
        let available = max(0, contentWidth - weekCardHorizontalPadding * 2 - weekItemSpacing * 6)
        return min(usesWideSummary ? 52 : 42, max(28, available / 7))
    }
    var weekSelectorRequiredWidth: CGFloat {
        dayIndicatorDiameter * 7 + weekItemSpacing * 6 + weekCardHorizontalPadding * 2
    }
    var scoreRingDiameter: CGFloat {
        guard !usesWideSummary else { return 224 }
        return min(188, max(156, contentWidth - 40))
    }
}

nonisolated enum SnoreAnalysisSummarySelector {
    static func resolve(selectedDate: Date, latestSummary: SleepSessionSummary?, calendar: Calendar) -> SnoreAnalysisSummary? {
        guard let latestSummary,
              calendar.isDate(latestSummary.sourceDate, inSameDayAs: selectedDate) else { return nil }
        let snoreSummary = latestSummary.snoreSummary
        return snoreSummary == .empty ? nil : snoreSummary
    }
}

enum SnoreAnalysisScreenState: Equatable {
    case loading
    case empty
    case noSleepData
    case noPermission
    case recording(startedAt: Date)
    case processing
    case completed
    case failed(message: String)
}

enum SnoreMicrophonePermission: Equatable {
    case undetermined
    case granted
    case denied
}

nonisolated enum SnoreSeverity: String, CaseIterable, Sendable {
    case quiet
    case mild
    case noticeable
    case loud

    var title: String {
        switch self {
        case .quiet: String(localized: "安静")
        case .mild: String(localized: "轻微")
        case .noticeable: String(localized: "较明显")
        case .loud: String(localized: "响亮")
        }
    }
}

nonisolated enum SnorePattern: String, Sendable {
    case occasional
    case continuous
    case clustered
    case periodic
    case intermittent

    var title: String {
        switch self {
        case .occasional: String(localized: "偶发型")
        case .continuous: String(localized: "连续型")
        case .clustered: String(localized: "集中型")
        case .periodic: String(localized: "周期型")
        case .intermittent: String(localized: "间歇型")
        }
    }

    var explanation: String {
        switch self {
        case .occasional: String(localized: "鼾声事件较少，整夜分布相对零散。")
        case .continuous: String(localized: "鼾声呈连续成组出现，事件间隔相对稳定。")
        case .clustered: String(localized: "鼾声集中在少数时段，其余时间相对安静。")
        case .periodic: String(localized: "鼾声以相近间隔反复出现，呈现一定周期。")
        case .intermittent: String(localized: "鼾声在整夜多次出现与中断，节律变化较大。")
        }
    }
}

nonisolated struct SnoreEvent: Identifiable, Equatable, Sendable {
    let id: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    /// 当前检测管线提供 1...12 的相对峰值桶，并非经校准的声压级。
    let loudnessBucket: Int
    let severity: SnoreSeverity
    let confidence: Double
    let audioURL: URL?
    let waveform: [Double]

    var estimatedLoudnessText: String {
        switch severity {
        case .quiet: String(localized: "环境声")
        case .mild: String(localized: "轻微响度")
        case .noticeable: String(localized: "中等响度")
        case .loud: String(localized: "较高响度")
        }
    }
}

nonisolated struct SnoreStageCorrelation: Identifiable, Equatable, Sendable {
    let stage: String
    let durationMinutes: Int
    let eventCount: Int
    var id: String { stage }

    var eventsPerHour: Double? {
        guard durationMinutes >= 10 else { return nil }
        return Double(eventCount) / (Double(durationMinutes) / 60)
    }
}

nonisolated struct SnoreSession: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let startTime: Date
    let endTime: Date
    let sleepDurationMinutes: Int
    let snoreScore: Int
    let severity: SnoreSeverity
    let snoreDurationMinutes: Double
    let eventsPerHour: Double
    let events: [SnoreEvent]
    let histogram: [Int]
    let pattern: SnorePattern
    let regularityScore: Int?
    let averageIntervalSeconds: Double?
    let groupCount: Int
    let averageEventsPerGroup: Double?
    let stageCorrelation: [SnoreStageCorrelation]

    var eventCount: Int { events.count }
    var peakLoudnessBucket: Int { events.map(\.loudnessBucket).max() ?? 0 }
    var averageLoudnessBucket: Int {
        guard !events.isEmpty else { return 0 }
        return events.reduce(0) { $0 + $1.loudnessBucket } / events.count
    }
    var snorePercentage: Double {
        guard sleepDurationMinutes > 0 else { return 0 }
        return min(100, max(0, snoreDurationMinutes / Double(sleepDurationMinutes) * 100))
    }
    var averageEventDuration: Double? {
        guard !events.isEmpty else { return nil }
        return events.reduce(0) { $0 + $1.duration } / Double(events.count)
    }
    var longestEventDuration: Double? { events.map(\.duration).max() }
    var hasAudio: Bool { events.contains { $0.audioURL != nil } }

    static func make(from summary: SleepSessionSummary, stages: [SleepStage] = []) -> SnoreSession? {
        let raw = summary.snoreSummary
        guard raw != .empty else { return nil }
        let events = raw.segments.map(SnoreEvent.make)
        let gaps = zip(events, events.dropFirst()).map { max(0, $1.startTime.timeIntervalSince($0.endTime)) }
        let averageGap = gaps.isEmpty ? nil : gaps.reduce(0, +) / Double(gaps.count)
        let regularity = regularityScore(gaps: gaps)
        let groups = grouped(events: events)
        return SnoreSession(
            id: summary.sessionId,
            date: summary.sourceDate,
            startTime: summary.startTime,
            endTime: summary.endTime,
            sleepDurationMinutes: summary.sleepDurationMinutes,
            snoreScore: max(0, min(100, 100 - raw.disturbanceScore)),
            severity: severity(raw.intensity),
            snoreDurationMinutes: max(0, raw.snoreDurationMinutes),
            eventsPerHour: max(0, raw.snoreFrequencyPerHour),
            events: events,
            histogram: normalizedHistogram(raw.histogram),
            pattern: pattern(events: events, histogram: raw.histogram, regularity: regularity),
            regularityScore: regularity,
            averageIntervalSeconds: averageGap,
            groupCount: groups.count,
            averageEventsPerGroup: groups.isEmpty ? nil : Double(events.count) / Double(groups.count),
            stageCorrelation: stageCorrelation(events: events, stages: stages)
        )
    }

    private static func normalizedHistogram(_ values: [Int]) -> [Int] {
        Array((values + Array(repeating: 0, count: 6)).prefix(6)).map { max(0, $0) }
    }

    private static func severity(_ value: SleepSnoreIntensity) -> SnoreSeverity {
        switch value {
        case .none: .quiet
        case .low: .mild
        case .medium: .noticeable
        case .high: .loud
        }
    }

    private static func regularityScore(gaps: [Double]) -> Int? {
        guard gaps.count >= 2 else { return nil }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        guard mean > 0 else { return 100 }
        let variance = gaps.reduce(0) { $0 + pow($1 - mean, 2) } / Double(gaps.count)
        return max(0, min(100, Int((100 - sqrt(variance) / mean * 70).rounded())))
    }

    private static func grouped(events: [SnoreEvent]) -> [[SnoreEvent]] {
        guard let first = events.first else { return [] }
        return events.dropFirst().reduce(into: [[first]]) { groups, event in
            if let last = groups.last?.last, event.startTime.timeIntervalSince(last.endTime) <= 45 {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
            }
        }
    }

    private static func pattern(events: [SnoreEvent], histogram: [Int], regularity: Int?) -> SnorePattern {
        guard events.count >= 4 else { return .occasional }
        let total = max(histogram.reduce(0, +), 1)
        if Double(histogram.max() ?? 0) / Double(total) >= 0.58 { return .clustered }
        if let regularity, regularity >= 72 { return .periodic }
        let groups = grouped(events: events)
        if groups.count <= max(1, events.count / 6) { return .continuous }
        return .intermittent
    }

    private static func stageCorrelation(events: [SnoreEvent], stages: [SleepStage]) -> [SnoreStageCorrelation] {
        let validStages = stages.filter { $0.startDate != nil && $0.endDate != nil && $0.duration > 0 }
        guard !validStages.isEmpty else { return [] }
        let definitions: [(String, [String])] = [
            (String(localized: "清醒"), ["Awake", "清醒"]),
            (String(localized: "浅睡"), ["Core", "Light", "核心", "浅睡"]),
            (String(localized: "深睡"), ["Deep", "深睡"]),
            ("REM", ["REM", "快速眼动"])
        ]
        return definitions.compactMap { title, aliases in
            let samples = validStages.filter { aliases.contains($0.stage) }
            let duration = samples.reduce(0) { $0 + $1.duration }
            guard duration > 0 else { return nil }
            let count = events.filter { event in
                samples.contains { sample in
                    guard let start = sample.startDate, let end = sample.endDate else { return false }
                    return event.startTime >= start && event.startTime < end
                }
            }.count
            return SnoreStageCorrelation(stage: title, durationMinutes: duration, eventCount: count)
        }
    }
}

private extension SnoreEvent {
    nonisolated static func make(from segment: SnoreSegmentSummary) -> SnoreEvent {
        let severity: SnoreSeverity = switch segment.intensity {
        case .none: .quiet
        case .low: .mild
        case .medium: .noticeable
        case .high: .loud
        }
        let seed = max(1, segment.peakDbfsBucket)
        let waveform = (0..<18).map { index in
            let value = abs(sin(Double(index + seed) * 1.37)) * (0.35 + segment.confidence * 0.65)
            return min(1, max(0.12, value))
        }
        return SnoreEvent(
            id: segment.id,
            startTime: segment.segmentStart,
            endTime: segment.segmentEnd,
            duration: max(0, segment.durationSeconds),
            loudnessBucket: max(0, segment.peakDbfsBucket),
            severity: severity,
            confidence: min(1, max(0, segment.confidence)),
            audioURL: nil,
            waveform: waveform
        )
    }
}

nonisolated struct SnoreTrendPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let score: Double
    let durationMinutes: Double
    let eventCount: Double
    let eventsPerHour: Double
    let peakLoudnessBucket: Double
    var id: Date { date }

    init(session: SnoreSession) {
        date = session.date
        score = Double(session.snoreScore)
        durationMinutes = session.snoreDurationMinutes
        eventCount = Double(session.eventCount)
        eventsPerHour = session.eventsPerHour
        peakLoudnessBucket = Double(session.events.map(\.loudnessBucket).max() ?? 0)
    }
}

@MainActor
@Observable
final class SnoreAnalysisViewModel {
    private(set) var sessions: [SnoreSession] = []
    private(set) var isLoading = true
    private(set) var permission: SnoreMicrophonePermission = .undetermined
    private(set) var monitoringState = SleepMonitoringState()
    /// 检测进行中的实时环境声音电平（RMS），由 Timer 轮询采集服务刷新。
    private(set) var liveEnvironmentRMS: Double = 0
    var selectedSessionID: String?

    @ObservationIgnored private let sleepViewModel: SleepViewModel
    @ObservationIgnored private var rmsPollingTimer: Timer?

    init(sleepViewModel: SleepViewModel) {
        self.sleepViewModel = sleepViewModel
        monitoringState = sleepViewModel.monitoringState
        permission = Self.resolvePermission()
    }

    var selectedSession: SnoreSession? {
        if let selectedSessionID, let selected = sessions.first(where: { $0.id == selectedSessionID }) { return selected }
        return sessions.first
    }

    /// 今晚已有的鼾声摘要（sourceDate 为今天）；没有时返回 nil。
    /// 用于「无检测结果」状态下仍允许用户查看今晚报告（各模块以空态呈现）。
    var tonightSession: SnoreSession? {
        guard let session = sessions.first(where: { Calendar.current.isDateInToday($0.date) }) else { return nil }
        return session
    }

    var state: SnoreAnalysisScreenState {
        if isLoading { return .loading }
        if permission == .denied { return .noPermission }
        if let error = monitoringState.lastErrorDescription, !error.isEmpty { return .failed(message: error) }
        switch monitoringState.phase {
        case .monitoring, .armed:
            return .recording(startedAt: monitoringState.startedAt ?? Date())
        case .finalizing:
            return .processing
        case .idle, .synced, .surfaced:
            if !sessions.isEmpty { return .completed }
            let hasSleepData = (sleepViewModel.sleepData?.duration_minutes ?? 0) > 0
                || (sleepViewModel.latestSleepSummary?.sleepDurationMinutes ?? 0) > 0
            if !hasSleepData { return .noSleepData }
            return .empty
        }
    }

    /// 检测进行中页面的追踪任务负责启动轮询；离开页面或停止检测时停止。
    func startLiveAudioPolling() {
        guard rmsPollingTimer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in
                guard model.monitoringState.isAudioMonitoringActive else { return }
                model.liveEnvironmentRMS = SleepMonitoringOrchestrator.shared.latestEnvironmentRMS
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rmsPollingTimer = timer
    }

    func stopLiveAudioPolling() {
        rmsPollingTimer?.invalidate()
        rmsPollingTimer = nil
        liveEnvironmentRMS = 0
    }

    var trendPoints: [SnoreTrendPoint] {
        sessions.map(SnoreTrendPoint.init).sorted { $0.date < $1.date }
    }

    func refresh() async {
        isLoading = true
        permission = Self.resolvePermission()
        await SleepMonitoringOrchestrator.shared.restoreState()
        monitoringState = SleepMonitoringOrchestrator.shared.state
        sleepViewModel.monitoringState = monitoringState
        // 打开今日页时 SleepViewModel 可能仍在完成本地收尾。
        // 显式合并最新摘要，避免仓库列表与视图模型更新发生竞态时报告错误显示为空。
        var summaries = await SleepMonitoringOrchestrator.shared.recentSummaries(limit: 90)
        if let latest = sleepViewModel.latestSleepSummary,
           latest.snoreSummary != .empty,
           !summaries.contains(where: { $0.sessionId == latest.sessionId }) {
            summaries.append(latest)
        }
        summaries.sort { $0.endTime > $1.endTime }
        sessions = summaries.compactMap { summary in
            let stages = Calendar.current.isDate(summary.sourceDate, inSameDayAs: sleepViewModel.latestSleepSummary?.sourceDate ?? .distantPast)
                ? (sleepViewModel.sleepData?.stages ?? []) : []
            return SnoreSession.make(from: summary, stages: stages)
        }
        if selectedSessionID == nil || !sessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = sessions.first?.id
        }
        isLoading = false
    }

    func startDetection() async {
        permission = Self.resolvePermission()
        await SleepMonitoringOrchestrator.shared.armForSleep(
            source: .manual,
            watchConnected: HealthDataManager.shared.isWatchReachable,
            watchConfidence: 0.35
        )
        await SleepMonitoringOrchestrator.shared.startMonitoringIfNeeded()
        monitoringState = SleepMonitoringOrchestrator.shared.state
        sleepViewModel.monitoringState = monitoringState
        permission = Self.resolvePermission()
    }

    func stopDetection() async {
        let capturedState = SleepMonitoringOrchestrator.shared.state
        guard capturedState.phase == .monitoring,
              capturedState.isAudioMonitoringActive else {
            await SleepMonitoringOrchestrator.shared.stopMonitoringAndReset()
            monitoringState = SleepMonitoringOrchestrator.shared.state
            sleepViewModel.monitoringState = monitoringState
            stopLiveAudioPolling()
            return
        }

        let end = Date()
        let start = min(capturedState.startedAt ?? end.addingTimeInterval(-60), end.addingTimeInterval(-1))
        let interval = SleepInterval(start: start, end: end)
        let durationMinutes = max(1, Int(ceil(end.timeIntervalSince(start) / 60)))
        let overlappingStages: [SleepStage]
        if let sleepInterval = sleepViewModel.sleepInterval,
           sleepInterval.start < end,
           sleepInterval.end > start {
            overlappingStages = sleepViewModel.sleepData?.stages ?? []
        } else {
            overlappingStages = []
        }

        // 手动检测拥有真实的采集区间，停止时必须完成该区间的收尾，
        // 让推断窗口得到分析和持久化，而不是被普通重置丢弃；同时不得创建 HealthKit 睡眠记录。
        await SleepMonitoringOrchestrator.shared.finalizeSleepSession(
            interval: interval,
            durationMinutes: durationMinutes,
            stages: overlappingStages,
            nightlyHrv: sleepViewModel.nightlyHrv,
            awakeCount: sleepViewModel.sleepData?.awake_count ?? 0,
            allowsHealthKitWriteback: false
        )
        monitoringState = SleepMonitoringOrchestrator.shared.state
        sleepViewModel.monitoringState = monitoringState
        sleepViewModel.latestSleepSummary = SleepMonitoringOrchestrator.shared.latestSummary
        stopLiveAudioPolling()
        await refresh()
    }


    private static func resolvePermission() -> SnoreMicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .denied
        }
    }

    isolated deinit {
        rmsPollingTimer?.invalidate()
        rmsPollingTimer = nil
    }
}
