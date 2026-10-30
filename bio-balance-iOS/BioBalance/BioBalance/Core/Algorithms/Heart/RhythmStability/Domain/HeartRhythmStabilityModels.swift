import Foundation

/// ECG 结论的去 HealthKit 化表示，供算法层在不依赖 HealthKit 的前提下消费。
nonisolated enum HeartRhythmECGClassification: String, Codable, Sendable, CaseIterable {
    /// 窦性心律，视为未见异常。
    case sinusRhythm
    /// 房颤提示。
    case atrialFibrillation
    /// 结果不确定（心率过高/过低/其它），作为需关注的异常搏动线索计入疑似早搏。
    case inconclusive
    /// 信号质量不足导致的不确定（poor reading）：属数据质量问题、非心律异常，不计分类、不扣分。
    case inconclusivePoorReading
    /// 无法识别或未给出结论，不计入任何分类。
    case unclassified
}

/// 一次 ECG 结论的轻量记录（分类 + 采样时间），不含电压明细。
nonisolated struct HeartRhythmECGReading: Sendable, Equatable {
    let classification: HeartRhythmECGClassification
    let date: Date
}

/// 心律稳定性读取层 DTO：由 HealthKitManager 组装的原始信号，纯值类型。
///
/// 只承载 Apple 健康生态可读到的心律相关事件与结论，作为算法适配器的输入来源。
nonisolated struct HeartRhythmSignals: Sendable, Equatable {
    /// 房颤负担百分比（0...100），来自 `AtrialFibrillationBurden`；缺失表示未测量。
    let atrialFibrillationBurdenPercent: Double?
    let atrialFibrillationBurdenDate: Date?
    /// 心律不齐通知事件计数与最近发生时间。
    let irregularRhythmEventCount: Int
    let lastIrregularRhythmDate: Date?
    /// 高心率事件计数。
    let highHeartRateEventCount: Int
    /// 低心率事件计数。
    let lowHeartRateEventCount: Int
    /// 观察窗口内的 ECG 结论列表。
    let ecgReadings: [HeartRhythmECGReading]
    /// 观察窗口天数（用于事件密度归一化）。
    let observationDays: Int

    static let empty = HeartRhythmSignals(
        atrialFibrillationBurdenPercent: nil,
        atrialFibrillationBurdenDate: nil,
        irregularRhythmEventCount: 0,
        lastIrregularRhythmDate: nil,
        highHeartRateEventCount: 0,
        lowHeartRateEventCount: 0,
        ecgReadings: [],
        observationDays: 7
    )

    /// 是否存在任何可用于评估的信号。
    var hasAnySignal: Bool {
        if let burden = atrialFibrillationBurdenPercent, burden.isFinite, burden >= 0 { return true }
        return irregularRhythmEventCount > 0
            || highHeartRateEventCount > 0
            || lowHeartRateEventCount > 0
            || !ecgReadings.isEmpty
    }
}

/// 心律稳定性引擎输入：将原始信号预消化为可直接评分的计数与百分比。
nonisolated struct HeartRhythmStabilityInput: Sendable, Equatable {
    let referenceDate: Date
    let observationDays: Int
    let atrialFibrillationBurdenPercent: Double?
    let irregularRhythmEventCount: Int
    let lastIrregularRhythmDate: Date?
    let highHeartRateEventCount: Int
    let lowHeartRateEventCount: Int
    /// ECG 判定为房颤的记录数。
    let ecgAtrialFibrillationCount: Int
    /// ECG 结果不确定（异常搏动线索）的记录数。
    let ecgInconclusiveCount: Int
    /// ECG 判定为窦性（未见异常）的记录数。
    let ecgSinusCount: Int
    /// ECG 信号质量不足（poor reading）的记录数：属数据质量问题，不参与评分。
    let ecgPoorReadingCount: Int
    let lastEcgDate: Date?

    init(
        referenceDate: Date = Date(),
        observationDays: Int = 7,
        atrialFibrillationBurdenPercent: Double? = nil,
        irregularRhythmEventCount: Int = 0,
        lastIrregularRhythmDate: Date? = nil,
        highHeartRateEventCount: Int = 0,
        lowHeartRateEventCount: Int = 0,
        ecgAtrialFibrillationCount: Int = 0,
        ecgInconclusiveCount: Int = 0,
        ecgSinusCount: Int = 0,
        ecgPoorReadingCount: Int = 0,
        lastEcgDate: Date? = nil
    ) {
        self.referenceDate = referenceDate
        self.observationDays = max(1, observationDays)
        self.atrialFibrillationBurdenPercent = atrialFibrillationBurdenPercent
        self.irregularRhythmEventCount = max(0, irregularRhythmEventCount)
        self.lastIrregularRhythmDate = lastIrregularRhythmDate
        self.highHeartRateEventCount = max(0, highHeartRateEventCount)
        self.lowHeartRateEventCount = max(0, lowHeartRateEventCount)
        self.ecgAtrialFibrillationCount = max(0, ecgAtrialFibrillationCount)
        self.ecgInconclusiveCount = max(0, ecgInconclusiveCount)
        self.ecgSinusCount = max(0, ecgSinusCount)
        self.ecgPoorReadingCount = max(0, ecgPoorReadingCount)
        self.lastEcgDate = lastEcgDate
    }
}

/// 心律稳定性分档，与就医提示的严重程度一一对应。
nonisolated enum HeartRhythmStabilityBand: String, Codable, Sendable, CaseIterable {
    /// 证据不足，无法评估。
    case unavailable
    /// 心律平稳，未见明显异常。
    case steady
    /// 存在少量异常线索，建议持续留意。
    case watch
    /// 异常线索较多，建议尽快就医核实。
    case elevated
}

/// 数据完整度，用于置信度与文案降级。
nonisolated enum HeartRhythmDataQuality: String, Codable, Sendable {
    case unavailable
    case low
    case medium
    case high
}

/// 参与评分的主要异常来源，用于详情页解释。
nonisolated enum HeartRhythmSignalKind: String, Codable, Sendable, CaseIterable {
    case atrialFibrillationBurden
    case irregularRhythmEvent
    case ecgAtrialFibrillation
    case ecgInconclusive
    case highHeartRateEvent
    case lowHeartRateEvent
}

/// 心律稳定性评估结果（确定性输出）。
///
/// `score` 为空表示证据不足；此时 `band == .unavailable` 且 `penaltyMultiplier == 1`。
/// 分数区间 `0...100`，`penaltyMultiplier` 区间 `0.85...1.0`。
nonisolated struct HeartRhythmStabilityResult: Sendable, Equatable {
    let score: Int?
    let band: HeartRhythmStabilityBand
    let dataQuality: HeartRhythmDataQuality
    /// 疑似房颤计数（心律不齐通知 + ECG 房颤结论）。
    let suspectedAtrialFibrillationCount: Int
    /// 疑似早搏计数（ECG 结果不确定的异常搏动线索）。
    let suspectedEctopicCount: Int
    /// 未见异常计数（ECG 窦性心律结论）。
    let normalCount: Int
    /// 高/低心率事件合计，作为附加提示。
    let heartRateEventCount: Int
    /// ECG 信号质量不足（poor reading）计数：非异常线索，仅作透明化提示，不计入三分类、不扣分。
    let poorReadingCount: Int
    let dominantSignals: [HeartRhythmSignalKind]
    /// 施加到身体电量的有界扣分乘子（0.85...1.0）。
    let penaltyMultiplier: Double
    let lastEventDate: Date?

    static let unavailable = HeartRhythmStabilityResult(
        score: nil,
        band: .unavailable,
        dataQuality: .unavailable,
        suspectedAtrialFibrillationCount: 0,
        suspectedEctopicCount: 0,
        normalCount: 0,
        heartRateEventCount: 0,
        poorReadingCount: 0,
        dominantSignals: [],
        penaltyMultiplier: 1.0,
        lastEventDate: nil
    )

    var hasData: Bool { score != nil }

    /// 三分类分布合计，用于详情页占比展示。
    var classifiedTotal: Int {
        suspectedAtrialFibrillationCount + suspectedEctopicCount + normalCount
    }
}
