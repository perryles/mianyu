import Foundation
import HealthKit

/// 心律信号的轻量可缓存 DTO：只保留计数、百分比与 ECG 结论分类，不包含电压明细。
struct HealthKitHeartRhythmSignalsCacheValue: Codable, Equatable, Sendable {
    let atrialFibrillationBurdenPercent: Double?
    let atrialFibrillationBurdenDate: Date?
    let irregularRhythmEventCount: Int
    let lastIrregularRhythmDate: Date?
    let highHeartRateEventCount: Int
    let lowHeartRateEventCount: Int
    let ecgClassifications: [HeartRhythmECGClassification]
    let ecgDates: [Date]
    let observationDays: Int

    init(signals: HeartRhythmSignals) {
        atrialFibrillationBurdenPercent = signals.atrialFibrillationBurdenPercent
        atrialFibrillationBurdenDate = signals.atrialFibrillationBurdenDate
        irregularRhythmEventCount = signals.irregularRhythmEventCount
        lastIrregularRhythmDate = signals.lastIrregularRhythmDate
        highHeartRateEventCount = signals.highHeartRateEventCount
        lowHeartRateEventCount = signals.lowHeartRateEventCount
        ecgClassifications = signals.ecgReadings.map(\.classification)
        ecgDates = signals.ecgReadings.map(\.date)
        observationDays = signals.observationDays
    }

    var signals: HeartRhythmSignals {
        HeartRhythmSignals(
            atrialFibrillationBurdenPercent: atrialFibrillationBurdenPercent,
            atrialFibrillationBurdenDate: atrialFibrillationBurdenDate,
            irregularRhythmEventCount: irregularRhythmEventCount,
            lastIrregularRhythmDate: lastIrregularRhythmDate,
            highHeartRateEventCount: highHeartRateEventCount,
            lowHeartRateEventCount: lowHeartRateEventCount,
            ecgReadings: zip(ecgClassifications, ecgDates).map {
                HeartRhythmECGReading(classification: $0.0, date: $0.1)
            },
            observationDays: observationDays
        )
    }
}

// MARK: - Heart Rhythm Stability Signals

extension HealthKitManager {

    /// 读取最近一段观察窗口内的心律相关信号，组装为算法层可消费的 `HeartRhythmSignals`。
    ///
    /// 采集范围：房颤负担、心律不齐通知、高/低心率事件计数与轻量 ECG 结论（不加载电压明细）。
    /// 数据主要来自 Apple Watch，未佩戴或未开启相关功能时返回 `.empty`。
    func fetchHeartRhythmSignals(
        referenceDate: Date = Date(),
        observationDays: Int = 7,
        forceRefresh: Bool = false
    ) async -> HeartRhythmSignals {
        let days = max(1, observationDays)
        let parameters = "\(days).\(Int64(Calendar.current.startOfDay(for: referenceDate).timeIntervalSince1970))"
        let key = HealthKitRepositoryCacheKey(
            domain: "heart.rhythm",
            name: "heartRhythmSignals",
            parameters: parameters,
            algorithmVersion: HeartRhythmStabilityEngine.algorithmVersion
        )
        if !forceRefresh,
           let cached: HealthKitHeartRhythmSignalsCacheValue = HealthKitRepositoryCache.shared.value(
               for: key,
               ttl: HealthKitRepositoryCache.algorithmTTL
           ) {
            return cached.signals
        }

        let end = referenceDate
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end.addingTimeInterval(-Double(days) * 86_400)

        async let burden = fetchAtrialFibrillationBurden(on: referenceDate)
        async let irregular = fetchIrregularRhythmEvents(start: start, end: end)
        async let highLow = fetchHighLowHeartRateEventCounts(start: start, end: end)
        async let ecg = fetchHeartRhythmECGReadings(start: start, end: end)

        let burdenResult = await burden
        let irregularResult = await irregular
        let highLowResult = await highLow
        let ecgReadings = await ecg

        let signals = HeartRhythmSignals(
            atrialFibrillationBurdenPercent: burdenResult?.percent,
            atrialFibrillationBurdenDate: burdenResult?.date,
            irregularRhythmEventCount: irregularResult.count,
            lastIrregularRhythmDate: irregularResult.lastDate,
            highHeartRateEventCount: highLowResult.high,
            lowHeartRateEventCount: highLowResult.low,
            ecgReadings: ecgReadings,
            observationDays: days
        )
        HealthKitRepositoryCache.shared.store(
            HealthKitHeartRhythmSignalsCacheValue(signals: signals),
            for: key,
            algorithmVersion: HeartRhythmStabilityEngine.algorithmVersion
        )
        return signals
    }

    /// 读取指定日期的房颤负担百分比（0...100），取窗口内最新有效值。
    func fetchAtrialFibrillationBurden(on date: Date = Date()) async -> (percent: Double, date: Date)? {
        guard let type = HKObjectType.quantityType(forIdentifier: .atrialFibrillationBurden) else {
            return nil
        }
        // 房颤负担为跨日累积指标，向前放宽到 30 天以取最近有效值。
        let end = date
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end.addingTimeInterval(-30 * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        do {
            let samples = try await fetchQuantitySamples(type: type, predicate: predicate, sort: [sort])
            guard let latest = samples.first else { return nil }
            // .percent() 返回 0...1 的分数，转换为 0...100 百分比。
            let fraction = latest.quantity.doubleValue(for: .percent())
            return (percent: fraction * 100.0, date: latest.startDate)
        } catch {
            return nil
        }
    }

    /// 读取心律不齐通知事件计数与最近发生时间。
    func fetchIrregularRhythmEvents(start: Date, end: Date) async -> (count: Int, lastDate: Date?) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        do {
            let samples = try await fetchOptionalCategorySamples(
                identifier: .irregularHeartRhythmEvent,
                predicate: predicate,
                sort: [sort]
            )
            return (count: samples.count, lastDate: samples.first?.startDate)
        } catch {
            return (count: 0, lastDate: nil)
        }
    }

    /// 读取高/低心率事件计数。
    func fetchHighLowHeartRateEventCounts(start: Date, end: Date) async -> (high: Int, low: Int) {
        async let highSamples = fetchOptionalCategorySamples(
            identifier: .highHeartRateEvent,
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        )
        async let lowSamples = fetchOptionalCategorySamples(
            identifier: .lowHeartRateEvent,
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        )

        let high = (try? await highSamples)?.count ?? 0
        let low = (try? await lowSamples)?.count ?? 0
        return (high: high, low: low)
    }

    /// 读取观察窗口内的轻量 ECG 结论（分类 + 时间），不加载电压明细。
    func fetchHeartRhythmECGReadings(start: Date, end: Date) async -> [HeartRhythmECGReading] {
        let sampleType = HKObjectType.electrocardiogramType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: sampleType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            let samples = try await descriptor.result(for: healthStore)
            logHealthKitRead(
                metric: "heartRhythm.ecgReadings",
                status: samples.isEmpty ? .noData : .dataAvailable
            )
            return samples
                .compactMap { $0 as? HKElectrocardiogram }
                .map {
                    HeartRhythmECGReading(
                        classification: mapECGClassification($0.classification),
                        date: $0.startDate
                    )
                }
        } catch {
            return []
        }
    }

    /// 把 HealthKit 的 ECG 分类映射为算法层的去 HealthKit 化分类。
    private func mapECGClassification(_ classification: HKElectrocardiogram.Classification) -> HeartRhythmECGClassification {
        switch classification {
        case .sinusRhythm:
            return .sinusRhythm
        case .atrialFibrillation:
            return .atrialFibrillation
        case .inconclusiveLowHeartRate, .inconclusiveHighHeartRate, .inconclusiveOther:
            return .inconclusive
        case .inconclusivePoorReading:
            // 信号质量不足属数据质量问题、非心律异常，单独归类，不计入疑似早搏、不扣分。
            return .inconclusivePoorReading
        case .unrecognized, .notSet:
            return .unclassified
        @unknown default:
            return .unclassified
        }
    }
}
