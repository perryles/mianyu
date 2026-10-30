import AVFoundation
import Combine
import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

enum SleepAudioActivity: String, Equatable, Sendable {
    case quiet = "安静"
    case speechLike = "疑似语音"
    case steadyNoise = "持续噪声"
    case active = "活动声"

    /// 本地化标题：rawValue 仅作标识，UI 展示走 String Catalog。
    var displayName: String {
        switch self {
        case .quiet: return String(localized: "安静")
        case .speechLike: return String(localized: "疑似语音")
        case .steadyNoise: return String(localized: "持续噪声")
        case .active: return String(localized: "活动声")
        }
    }
}

/// Business-facing result for one analyzed sleep-audio window.
/// Keeping this type independent from the SDK makes the production sleep pipeline testable.
struct SleepAudioInferenceResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let startDate: Date
    let durationSeconds: TimeInterval
    let rootMeanSquare: Double
    let decibelsFullScale: Double
    let zeroCrossingRate: Double
    let activity: SleepAudioActivity
    let providerName: String
}

nonisolated protocol SleepAudioInferenceProviding: Sendable {
    func prepare() async throws
    func infer(samples: [Float], sampleRate: Double) async throws -> SleepAudioClassification
}

nonisolated struct SleepAudioClassification: Equatable, Sendable {
    let activity: SleepAudioActivity
    let providerName: String
}

/// Deterministic fallback used when the FluidAudio package or model is unavailable.
/// It provides a stable baseline so sleep monitoring can continue.
nonisolated struct BaselineSleepAudioInferenceProvider: SleepAudioInferenceProviding {
    static let providerName = "RMS + ZCR baseline"

    func prepare() async throws {}

    func infer(samples: [Float], sampleRate: Double) async throws -> SleepAudioClassification {
        SleepAudioClassification(
            activity: classify(samples: samples),
            providerName: Self.providerName
        )
    }

    func classify(samples: [Float]) -> SleepAudioActivity {
        guard !samples.isEmpty else { return .quiet }
        let rootMeanSquare = sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
        guard rootMeanSquare >= 0.008 else { return .quiet }

        var crossings = 0
        for index in 1..<samples.count where (samples[index] >= 0) != (samples[index - 1] >= 0) {
            crossings += 1
        }
        let zcr = Double(crossings) / Double(samples.count)
        if zcr > 0.055 && zcr < 0.22 { return .speechLike }
        // 鼾声通常是低频有声信号；若把所有
        // ZCR 低于 0.035 的窗口都视为稳定背景噪声，会过滤掉大多数
        // 真实鼾声；只有过零率极低的嗡鸣才保留为稳定噪声。
        if zcr < 0.006 { return .steadyNoise }
        return .active
    }
}

nonisolated struct SleepAudioWindowAnalyzer: Sendable {
    func analyze(
        samples: [Float],
        startDate: Date,
        sampleRate: Double,
        provider: any SleepAudioInferenceProviding
    ) async throws -> SleepAudioInferenceResult? {
        guard !samples.isEmpty else { return nil }
        let durationSeconds = Double(samples.count) / max(sampleRate, 1)
        let rootMeanSquare = sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
        let crossings = samples.dropFirst().enumerated().reduce(0) { count, pair in
            let previous = samples[pair.offset]
            return count + (((pair.element >= 0) != (previous >= 0)) ? 1 : 0)
        }
        let zeroCrossingRate = Double(crossings) / Double(samples.count)
        let decibelsFullScale = 20 * log10(max(rootMeanSquare, 0.000_01))
        let classification = try await provider.infer(samples: samples, sampleRate: sampleRate)
        return SleepAudioInferenceResult(
            startDate: startDate,
            durationSeconds: durationSeconds,
            rootMeanSquare: rootMeanSquare,
            decibelsFullScale: decibelsFullScale,
            zeroCrossingRate: zeroCrossingRate,
            activity: classification.activity,
            providerName: classification.providerName
        )
    }
}

nonisolated struct SleepAudioWindow: Sendable {
    let samples: [Float]
    let startDate: Date
    let sampleRate: Double
}

/// Serializes model access and applies backpressure independently of the audio tap.
nonisolated final class SleepAudioInferenceWorker: @unchecked Sendable {
    private let provider: any SleepAudioInferenceProviding
    private let analyzer = SleepAudioWindowAnalyzer()
    private let maximumPendingWindowCount: Int
    private let maximumStoredResultCount: Int
    private let stateLock = NSLock()
    private var pendingWindows: [SleepAudioWindow] = []
    private var storedResults: [SleepAudioInferenceResult] = []
    private var processingTask: Task<Void, Never>?

    init(
        provider: any SleepAudioInferenceProviding,
        maximumPendingWindowCount: Int = 4,
        maximumStoredResultCount: Int = 43_200
    ) {
        self.provider = provider
        self.maximumPendingWindowCount = max(1, maximumPendingWindowCount)
        self.maximumStoredResultCount = max(1, maximumStoredResultCount)
    }

    func prepare() async throws {
        try await provider.prepare()
    }

    func reset() async {
        let task = stateLock.withLock { () -> Task<Void, Never>? in
            let task = processingTask
            processingTask = nil
            pendingWindows.removeAll(keepingCapacity: true)
            return task
        }
        task?.cancel()
        await task?.value
        stateLock.withLock {
            storedResults.removeAll(keepingCapacity: true)
        }
    }

    func enqueueWindows(_ windows: [SleepAudioWindow]) {
        guard !windows.isEmpty else { return }
        stateLock.withLock {
            pendingWindows.append(contentsOf: windows)
            if pendingWindows.count > maximumPendingWindowCount {
                pendingWindows.removeFirst(pendingWindows.count - maximumPendingWindowCount)
            }
            startProcessingIfNeeded()
        }
    }

    func drainAndCollectResults() async -> [SleepAudioInferenceResult] {
        while let task = stateLock.withLock({ processingTask }) {
            await task.value
        }
        return storedResultsSnapshot()
    }

    func storedResultsSnapshot() -> [SleepAudioInferenceResult] {
        stateLock.withLock { storedResults }
    }

    /// 调用方必须持有 `stateLock`。
    private func startProcessingIfNeeded() {
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in
            await self?.processPendingWindows()
        }
    }

    private func processPendingWindows() async {
        while !Task.isCancelled, let window = nextWindow() {
            if let result = try? await analyzer.analyze(
                samples: window.samples,
                startDate: window.startDate,
                sampleRate: window.sampleRate,
                provider: provider
            ) {
                stateLock.withLock {
                    storedResults.append(result)
                    if storedResults.count > maximumStoredResultCount {
                        storedResults.removeFirst(storedResults.count - maximumStoredResultCount)
                    }
                }
            }
        }
        stateLock.withLock {
            processingTask = nil
            if !pendingWindows.isEmpty {
                startProcessingIfNeeded()
            }
        }
    }

    private func nextWindow() -> SleepAudioWindow? {
        stateLock.withLock {
            guard !pendingWindows.isEmpty else { return nil }
            return pendingWindows.removeFirst()
        }
    }
}

nonisolated enum SleepAudioInferenceProviderFactory {
    static func makeDefault() -> any SleepAudioInferenceProviding {
        #if canImport(FluidAudio)
        return ResilientSleepAudioInferenceProvider(
            primaryProvider: FluidAudioSleepAudioInferenceProvider(),
            fallbackProvider: BaselineSleepAudioInferenceProvider()
        )
        #else
        BaselineSleepAudioInferenceProvider()
        #endif
    }
}

/// Keeps sleep monitoring operational when the on-device model cannot be prepared
/// or a single inference fails.
actor ResilientSleepAudioInferenceProvider: SleepAudioInferenceProviding {
    private let primaryProvider: any SleepAudioInferenceProviding
    private let fallbackProvider: any SleepAudioInferenceProviding
    private var selectedProvider: (any SleepAudioInferenceProviding)?

    init(
        primaryProvider: any SleepAudioInferenceProviding,
        fallbackProvider: any SleepAudioInferenceProviding
    ) {
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
    }

    func prepare() async throws {
        guard selectedProvider == nil else { return }
        do {
            try await primaryProvider.prepare()
            selectedProvider = primaryProvider
        } catch {
            try await fallbackProvider.prepare()
            selectedProvider = fallbackProvider
        }
    }

    func infer(samples: [Float], sampleRate: Double) async throws -> SleepAudioClassification {
        if selectedProvider == nil {
            try await prepare()
        }

        let provider = selectedProvider ?? fallbackProvider
        do {
            return try await provider.infer(samples: samples, sampleRate: sampleRate)
        } catch {
            try await fallbackProvider.prepare()
            selectedProvider = fallbackProvider
            return try await fallbackProvider.infer(samples: samples, sampleRate: sampleRate)
        }
    }
}

#if canImport(FluidAudio)
actor FluidAudioSleepAudioInferenceProvider: SleepAudioInferenceProviding {
    private static let sampleRate = 16_000.0
    private let speechProbabilityThreshold: Float
    private var voiceActivityManager: VadManager?

    init(speechProbabilityThreshold: Float = 0.75) {
        self.speechProbabilityThreshold = speechProbabilityThreshold
    }

    func prepare() async throws {
        guard voiceActivityManager == nil else { return }
        voiceActivityManager = try await VadManager(
            config: VadConfig(defaultThreshold: speechProbabilityThreshold)
        )
    }

    func infer(samples: [Float], sampleRate: Double) async throws -> SleepAudioClassification {
        if voiceActivityManager == nil {
            try await prepare()
        }
        guard let voiceActivityManager else {
            throw SleepAudioInferenceError.providerUnavailable
        }

        let modelSamples = Self.resample(
            samples: samples,
            sourceSampleRate: sampleRate,
            destinationSampleRate: Self.sampleRate
        )
        let voiceActivityResults = try await voiceActivityManager.process(modelSamples)
        let hasSpeech = voiceActivityResults.contains {
            $0.isVoiceActive || Float($0.probability) >= speechProbabilityThreshold
        }

        let activity: SleepAudioActivity
        if hasSpeech {
            // VAD 模型常把鼾声视为语音活动；对类语音频谱仍保留
            // 语音排除规则，但允许低频
            // 有声窗口继续进入鼾声识别流程。
            let acousticActivity = BaselineSleepAudioInferenceProvider().classify(samples: modelSamples)
            activity = acousticActivity == .active ? .active : .speechLike
        } else if voiceActivityResults.isEmpty {
            activity = BaselineSleepAudioInferenceProvider().classify(samples: modelSamples)
        } else {
            activity = Self.classifyNonSpeech(samples: modelSamples)
        }

        return SleepAudioClassification(activity: activity, providerName: "FluidAudio VAD")
    }

    private static func classifyNonSpeech(samples: [Float]) -> SleepAudioActivity {
        guard !samples.isEmpty else { return .quiet }
        let rootMeanSquare = sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
        guard rootMeanSquare >= 0.008 else { return .quiet }

        var crossings = 0
        for index in 1..<samples.count where (samples[index] >= 0) != (samples[index - 1] >= 0) {
            crossings += 1
        }
        let zeroCrossingRate = Double(crossings) / Double(samples.count)
        return zeroCrossingRate < 0.006 ? .steadyNoise : .active
    }

    private static func resample(
        samples: [Float],
        sourceSampleRate: Double,
        destinationSampleRate: Double
    ) -> [Float] {
        guard !samples.isEmpty, sourceSampleRate > 0, destinationSampleRate > 0 else { return [] }
        guard abs(sourceSampleRate - destinationSampleRate) >= 1 else { return samples }

        let outputCount = max(1, Int((Double(samples.count) * destinationSampleRate / sourceSampleRate).rounded()))
        let sourceStep = sourceSampleRate / destinationSampleRate
        return (0..<outputCount).map { outputIndex in
            let sourcePosition = Double(outputIndex) * sourceStep
            let lowerIndex = min(Int(sourcePosition), samples.count - 1)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            return samples[lowerIndex] + (samples[upperIndex] - samples[lowerIndex]) * fraction
        }
    }
}
#endif

nonisolated enum SleepAudioInferenceError: LocalizedError {
    case providerUnavailable
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return String(localized: "睡眠音频推理服务尚未准备完成。")
        case .microphonePermissionDenied:
            return String(localized: "麦克风权限尚未开启，无法进行本地睡眠音频分析。")
        }
    }
}

enum FluidAudioPackageAvailability {
    #if canImport(FluidAudio)
    static let isAvailable = true
    #else
    static let isAvailable = false
    #endif
}

@MainActor
@Observable
final class SleepAudioInferenceService {
    private(set) var results: [SleepAudioInferenceResult] = []
    private(set) var isRunning = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var errorMessage: String?

    let isFluidAudioPackageAvailable = FluidAudioPackageAvailability.isAvailable

    private let engine = AVAudioEngine()
    private let inferenceProvider: any SleepAudioInferenceProviding
    private let windowAnalyzer = SleepAudioWindowAnalyzer()
    private var captureTask: Task<Void, Never>?
    private var currentWindowSamples: [Float] = []
    private var windowStartDate: Date?
    private var sessionStartDate: Date?
    private var inputSampleRate: Double = 16_000
    private var analysisGeneration = UUID()

    init(inferenceProvider: any SleepAudioInferenceProviding = SleepAudioInferenceProviderFactory.makeDefault()) {
        self.inferenceProvider = inferenceProvider
    }

    deinit {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func start(duration: TimeInterval = 10) async {
        guard !isRunning else { return }
        errorMessage = nil

        let permission = AVAudioApplication.shared.recordPermission
        if permission == .undetermined {
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else {
                errorMessage = "麦克风权限未开启。"
                return
            }
        } else if permission != .granted {
            errorMessage = "麦克风权限未开启，请在系统设置中允许眠屿使用麦克风。"
            return
        }

        do {
            try await inferenceProvider.prepare()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.mixWithOthers])
            try session.setPreferredSampleRate(inputSampleRate)
            try session.setPreferredIOBufferDuration(0.025)
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)
            inputSampleRate = format.sampleRate
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?.pointee else { return }
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                Task { @MainActor [weak self] in
                    self?.append(samples: samples)
                }
            }

            results = []
            analysisGeneration = UUID()
            currentWindowSamples = []
            windowStartDate = Date()
            sessionStartDate = Date()
            elapsed = 0
            isRunning = true
            engine.prepare()
            try engine.start()

            captureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let end = Date().addingTimeInterval(duration)
                while !Task.isCancelled && self.isRunning && Date() < end {
                    self.elapsed = Date().timeIntervalSince(self.sessionStartDate ?? Date())
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if self.isRunning { self.stop() }
            }
        } catch {
            stop()
            errorMessage = "无法启动音频采集：\(error.localizedDescription)"
        }
    }

    func stop() {
        guard isRunning || !currentWindowSamples.isEmpty else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if !currentWindowSamples.isEmpty { submitCurrentWindow() }
        isRunning = false
        captureTask?.cancel()
        captureTask = nil
    }

    /// 由提示框关闭按钮调用，保持错误状态的修改封装在 MainActor 服务内部。
    func clearError() {
        errorMessage = nil
    }

    private func append(samples: [Float]) {
        guard isRunning, !samples.isEmpty else { return }
        if windowStartDate == nil { windowStartDate = Date() }
        currentWindowSamples.append(contentsOf: samples)
        let windowLength = max(1, Int(inputSampleRate))
        while currentWindowSamples.count >= windowLength {
            let samples = Array(currentWindowSamples.prefix(windowLength))
            currentWindowSamples.removeFirst(windowLength)
            submit(samples: samples)
        }
    }

    private func submitCurrentWindow() {
        guard !currentWindowSamples.isEmpty else { return }
        let samples = currentWindowSamples
        currentWindowSamples = []
        submit(samples: samples)
    }

    private func submit(samples: [Float]) {
        let startDate = windowStartDate ?? Date()
        let sampleRate = inputSampleRate
        let generation = analysisGeneration
        windowStartDate = startDate.addingTimeInterval(Double(samples.count) / sampleRate)

        let analysisTask = Task.detached(priority: .utility) { [
            windowAnalyzer = self.windowAnalyzer,
            inferenceProvider = self.inferenceProvider
        ] in
            try? await windowAnalyzer.analyze(
                samples: samples,
                startDate: startDate,
                sampleRate: sampleRate,
                provider: inferenceProvider
            )
        }
        Task { @MainActor [weak self] in
            guard let result = await analysisTask.value,
                  let self,
                  self.analysisGeneration == generation else { return }
            self.results.append(result)
            self.results.sort { $0.startDate < $1.startDate }
        }
    }
}
