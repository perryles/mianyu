import Foundation

/// 把 HealthKit 读取层组装的 `HeartRhythmSignals` 映射为算法引擎输入。
///
/// 语义映射约定：
/// - ECG 房颤结论计入"疑似房颤"（与心律不齐通知合并统计）。
/// - ECG 结果不确定（心率过高/过低/其它）视为异常搏动线索，计入"疑似早搏"。
/// - ECG 信号质量不足（poor reading）属数据质量问题、非心律异常，单独计数、不计入分类、不扣分。
/// - ECG 窦性心律结论计入"未见异常"。
/// - 无法识别/未给出结论的 ECG 不计入任何分类。
enum HeartRhythmStabilityHealthKitAdapter {
    static func makeInput(
        from signals: HeartRhythmSignals,
        referenceDate: Date = Date()
    ) -> HeartRhythmStabilityInput {
        var afibCount = 0
        var inconclusiveCount = 0
        var sinusCount = 0
        var poorReadingCount = 0

        for reading in signals.ecgReadings {
            switch reading.classification {
            case .atrialFibrillation:
                afibCount += 1
            case .inconclusive:
                inconclusiveCount += 1
            case .sinusRhythm:
                sinusCount += 1
            case .inconclusivePoorReading:
                poorReadingCount += 1
            case .unclassified:
                break
            }
        }

        let lastEcgDate = signals.ecgReadings.map(\.date).max()

        return HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            observationDays: signals.observationDays,
            atrialFibrillationBurdenPercent: signals.atrialFibrillationBurdenPercent,
            irregularRhythmEventCount: signals.irregularRhythmEventCount,
            lastIrregularRhythmDate: signals.lastIrregularRhythmDate,
            highHeartRateEventCount: signals.highHeartRateEventCount,
            lowHeartRateEventCount: signals.lowHeartRateEventCount,
            ecgAtrialFibrillationCount: afibCount,
            ecgInconclusiveCount: inconclusiveCount,
            ecgSinusCount: sinusCount,
            ecgPoorReadingCount: poorReadingCount,
            lastEcgDate: lastEcgDate
        )
    }

    /// 组合入口：把读取层信号一步映射并评估为结果。
    static func evaluate(
        signals: HeartRhythmSignals,
        referenceDate: Date = Date()
    ) -> HeartRhythmStabilityResult {
        guard signals.hasAnySignal else { return .unavailable }
        let input = makeInput(from: signals, referenceDate: referenceDate)
        return HeartRhythmStabilityEngine.evaluate(input: input)
    }
}
