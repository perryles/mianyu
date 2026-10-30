/// HealthKitManager Period Extension — 经期/月经周期数据同步与处理。
import Foundation
import HealthKit

extension HealthKitManager: PeriodHealthSyncing {
    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyMenstrualFlowLevels(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: end) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: calendar.date(byAdding: .day, value: 1, to: end), options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let samples = try await fetchCategorySamples(type: type, predicate: predicate, sort: sort)
        let records = aggregateMenstrualFlowSamples(samples)

        return records
            .map {
                TimeSeriesPointDouble(
                    timestamp: Int64(calendar.startOfDay(for: $0.day).timeIntervalSince1970),
                    value: Double($0.flowLevel)
                )
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func refreshPeriodData(days: Int) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let flowType = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else {
            return false
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lookbackDays = max(days, 365)
        let start = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today) ?? today
        let end = Date()

        do {
            async let flowSamples = fetchCategorySamples(
                type: flowType,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            )
            async let crampsSamples = fetchOptionalCategorySamples(
                identifier: .abdominalCramps,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            )
            async let moodSamples = fetchOptionalCategorySamples(
                identifier: .moodChanges,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            )
            async let sexualActivitySamples = fetchOptionalCategorySamples(
                identifier: .sexualActivity,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            )
            async let spottingSamples = fetchOptionalCategorySamples(
                identifier: .intermenstrualBleeding,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            )
            async let ovulationSamples = fetchOptionalCategorySamples(
                identifier: .ovulationTestResult,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            )
            async let cervicalMucusSamples = fetchOptionalCategorySamples(
                identifier: .cervicalMucusQuality,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            )
            async let pregnancyTestSamples = fetchOptionalCategorySamples(
                identifier: .pregnancyTestResult,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            )

            let dailyRecords = aggregateMenstrualFlowSamples(try await flowSamples)
            let symptomRecords = aggregatePeriodHealthSignals(
                crampsSamples: try await crampsSamples,
                moodSamples: try await moodSamples,
                sexualActivitySamples: try await sexualActivitySamples,
                spottingSamples: try await spottingSamples,
                ovulationSamples: try await ovulationSamples,
                cervicalMucusSamples: try await cervicalMucusSamples,
                pregnancyTestSamples: try await pregnancyTestSamples
            )
            let cycles = buildHealthImportCycles(from: dailyRecords)
            let dayLogs = mergePeriodHealthDayLogs(flowRecords: dailyRecords, signalRecords: symptomRecords)
            PeriodStore.shared.saveHealthKitSnapshot(cycles: cycles, dayLogs: dayLogs)
            return !dailyRecords.isEmpty || !dayLogs.isEmpty
        } catch {
            return false
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func syncCycle(startDate: Date, endDate: Date?) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else {
            return
        }
        guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
            return
        }

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate ?? Date())
        guard endDay >= startDay else { return }

        let dayCount = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        guard dayCount >= 0 else { return }

        for offset in 0...dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            await upsertMenstrualFlowSample(
                type: type,
                day: day,
                value: Self.unspecifiedMenstrualFlowRawValue,
                isCycleStart: offset == 0
            )
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func syncFlow(date: Date, flowLevel: Int) async {
        await syncFlow(date: date, flowLevel: flowLevel, isCycleStart: false)
    }

    /// 方法说明：同步单日出血量，并在首日样本上写入 HealthKit 周期起始标记。
    func syncFlow(date: Date, flowLevel: Int, isCycleStart: Bool) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else {
            return
        }
        guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
            return
        }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        if flowLevel <= 0 {
            await deleteSyncedCategorySample(type: type, day: day, syncKey: "bb.menstrualFlow")
            return
        }

        let value = Self.menstrualFlowRawValue(for: flowLevel)
        await upsertMenstrualFlowSample(type: type, day: day, value: value, isCycleStart: isCycleStart)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func syncSymptoms(date: Date, painLevel: Int, moodLevel: Int) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        if let type = HKObjectType.categoryType(forIdentifier: .abdominalCramps),
           healthStore.authorizationStatus(for: type) == .sharingAuthorized {
            if painLevel > 0 {
                await upsertSeverityCategorySample(type: type, day: day, value: healthSeverityValue(from: painLevel), syncKey: "bb.period.abdominalCramps")
            } else {
                await deleteSyncedCategorySample(type: type, day: day, syncKey: "bb.period.abdominalCramps")
            }
        }

        if let type = HKObjectType.categoryType(forIdentifier: .moodChanges),
           healthStore.authorizationStatus(for: type) == .sharingAuthorized {
            if moodLevel > 0 {
                await upsertSeverityCategorySample(type: type, day: day, value: healthSeverityValue(from: moodLevel), syncKey: "bb.period.moodChanges")
            } else {
                await deleteSyncedCategorySample(type: type, day: day, syncKey: "bb.period.moodChanges")
            }
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func syncReproductiveEvents(
        date: Date,
        hasSexualActivity: Bool,
        hasIntermenstrualBleeding: Bool,
        pregnancyTestResult: String?,
        ovulationTestResult: String?,
        cervicalMucusQuality: String?
    ) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        if let type = HKObjectType.categoryType(forIdentifier: .sexualActivity),
           healthStore.authorizationStatus(for: type) == .sharingAuthorized,
           hasSexualActivity {
            await upsertBinaryCategorySample(type: type, day: day, syncKey: "bb.period.sexualActivity")
        }

        if let type = HKObjectType.categoryType(forIdentifier: .intermenstrualBleeding),
           healthStore.authorizationStatus(for: type) == .sharingAuthorized,
           hasIntermenstrualBleeding {
            await upsertBinaryCategorySample(type: type, day: day, syncKey: "bb.period.intermenstrualBleeding")
        }

        if let result = pregnancyTestResult,
           let type = HKObjectType.categoryType(forIdentifier: .pregnancyTestResult),
           healthStore.authorizationStatus(for: type) == .sharingAuthorized,
           let value = healthPregnancyTestValue(from: result) {
            await upsertCategoryValueSample(type: type, day: day, value: value, syncKey: "bb.period.pregnancyTestResult")
        }

        if let result = ovulationTestResult,
           let type = HKObjectType.categoryType(forIdentifier: .ovulationTestResult),
           healthStore.authorizationStatus(for: type) == .sharingAuthorized,
           let value = healthOvulationTestValue(from: result) {
            await upsertCategoryValueSample(type: type, day: day, value: value, syncKey: "bb.period.ovulationTestResult")
        }

        if let quality = cervicalMucusQuality,
           let type = HKObjectType.categoryType(forIdentifier: .cervicalMucusQuality),
           healthStore.authorizationStatus(for: type) == .sharingAuthorized,
           let value = healthCervicalMucusValue(from: quality) {
            await upsertCategoryValueSample(type: type, day: day, value: value, syncKey: "bb.period.cervicalMucusQuality")
        }
    }

    // MARK: - 私有辅助方法

    private func upsertMenstrualFlowSample(type: HKCategoryType, day: Date, value: Int, isCycleStart: Bool) async {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return }
        let syncIdentifier = "bb.menstrualFlow." + Self.periodDayFormatter.string(from: day)

        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier])
        _ = await deleteObjects(type: type, predicate: predicate)

        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: syncIdentifier,
            HKMetadataKeySyncVersion: 1,
            HKMetadataKeyWasUserEntered: true,
            HKMetadataKeyMenstrualCycleStart: isCycleStart
        ]
        let sample = HKCategorySample(type: type, value: value, start: day, end: end, metadata: metadata)
        _ = await saveObject(sample)
    }

    private func upsertSeverityCategorySample(type: HKCategoryType, day: Date, value: Int, syncKey: String) async {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return }
        let syncIdentifier = syncKey + "." + Self.periodDayFormatter.string(from: day)

        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier])
        _ = await deleteObjects(type: type, predicate: predicate)

        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: syncIdentifier,
            HKMetadataKeySyncVersion: 1,
            HKMetadataKeyWasUserEntered: true
        ]
        let sample = HKCategorySample(type: type, value: value, start: day, end: end, metadata: metadata)
        _ = await saveObject(sample)
    }

    private func deleteSyncedCategorySample(type: HKCategoryType, day: Date, syncKey: String) async {
        let syncIdentifier = syncKey + "." + Self.periodDayFormatter.string(from: day)
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: [syncIdentifier]
        )
        _ = await deleteObjects(type: type, predicate: predicate)
    }

    private func upsertBinaryCategorySample(type: HKCategoryType, day: Date, syncKey: String) async {
        await upsertCategoryValueSample(type: type, day: day, value: 0, syncKey: syncKey)
    }

    private func upsertCategoryValueSample(type: HKCategoryType, day: Date, value: Int, syncKey: String) async {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return }
        let syncIdentifier = syncKey + "." + Self.periodDayFormatter.string(from: day)

        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier])
        _ = await deleteObjects(type: type, predicate: predicate)

        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: syncIdentifier,
            HKMetadataKeySyncVersion: 1,
            HKMetadataKeyWasUserEntered: true
        ]
        let sample = HKCategorySample(type: type, value: value, start: day, end: end, metadata: metadata)
        _ = await saveObject(sample)
    }

    private func healthPregnancyTestValue(from value: String) -> Int? {
        switch value {
        case "negative": return HKCategoryValuePregnancyTestResult.negative.rawValue
        case "positive": return HKCategoryValuePregnancyTestResult.positive.rawValue
        case "inconclusive": return HKCategoryValuePregnancyTestResult.indeterminate.rawValue
        default: return nil
        }
    }

    private func healthOvulationTestValue(from value: String) -> Int? {
        switch value {
        case "negative": return HKCategoryValueOvulationTestResult.negative.rawValue
        case "positive": return HKCategoryValueOvulationTestResult.estrogenSurge.rawValue
        case "peak": return HKCategoryValueOvulationTestResult.luteinizingHormoneSurge.rawValue
        case "inconclusive": return HKCategoryValueOvulationTestResult.indeterminate.rawValue
        default: return nil
        }
    }

    private func healthCervicalMucusValue(from value: String) -> Int? {
        switch value {
        case "dry": return HKCategoryValueCervicalMucusQuality.dry.rawValue
        case "sticky": return HKCategoryValueCervicalMucusQuality.sticky.rawValue
        case "creamy": return HKCategoryValueCervicalMucusQuality.creamy.rawValue
        case "watery": return HKCategoryValueCervicalMucusQuality.watery.rawValue
        case "eggWhite": return HKCategoryValueCervicalMucusQuality.eggWhite.rawValue
        default: return nil
        }
    }

    private func aggregateMenstrualFlowSamples(_ samples: [HKCategorySample]) -> [MenstrualFlowDayRecord] {
        let calendar = Calendar.current
        var recordsByDay: [Date: MenstrualFlowDayRecord] = [:]

        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            let flowLevel = flowLevel(from: sample.value)
            let isCycleStart = (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? NSNumber)?.boolValue ?? false

            if var existing = recordsByDay[day] {
                existing.flowLevel = max(existing.flowLevel, flowLevel)
                existing.isCycleStart = existing.isCycleStart || isCycleStart
                recordsByDay[day] = existing
            } else {
                recordsByDay[day] = MenstrualFlowDayRecord(day: day, flowLevel: flowLevel, isCycleStart: isCycleStart)
            }
        }

        return recordsByDay.values.sorted { $0.day < $1.day }
    }

    private func buildHealthImportCycles(from records: [MenstrualFlowDayRecord]) -> [PeriodStore.HealthImportCycle] {
        guard !records.isEmpty else { return [] }

        let calendar = Calendar.current
        var cycles: [PeriodStore.HealthImportCycle] = []
        var currentStart = records[0].day
        var previousDay = records[0].day

        for record in records.dropFirst() {
            let gap = calendar.dateComponents([.day], from: previousDay, to: record.day).day ?? 0
            let shouldStartNewCycle = gap > 1 || record.isCycleStart
            if shouldStartNewCycle {
                cycles.append(PeriodStore.HealthImportCycle(startDate: currentStart, endDate: previousDay))
                currentStart = record.day
            }
            previousDay = record.day
        }

        cycles.append(PeriodStore.HealthImportCycle(startDate: currentStart, endDate: previousDay))
        return cycles
    }

    private func flowLevel(from healthValue: Int) -> Int {
        guard let bleeding = HKCategoryValueVaginalBleeding(rawValue: healthValue) else { return 1 }
        switch bleeding {
        case .none: return 0
        case .heavy: return 3
        case .medium: return 2
        case .light, .unspecified: return 1
        default: return 1
        }
    }

    private static var unspecifiedMenstrualFlowRawValue: Int {
        HKCategoryValueVaginalBleeding.unspecified.rawValue
    }

    private static func menstrualFlowRawValue(for flowLevel: Int) -> Int {
        switch flowLevel {
        case 1: return HKCategoryValueVaginalBleeding.light.rawValue
        case 2: return HKCategoryValueVaginalBleeding.medium.rawValue
        case 3...: return HKCategoryValueVaginalBleeding.heavy.rawValue
        default: return HKCategoryValueVaginalBleeding.unspecified.rawValue
        }
    }

    private func mergePeriodHealthDayLogs(
        flowRecords: [MenstrualFlowDayRecord],
        signalRecords: [Date: PeriodHealthSignalRecord]
    ) -> [PeriodStore.HealthImportDayLog] {
        let allDays = Set(flowRecords.map(\.day)).union(signalRecords.keys)

        return allDays.sorted().map { day in
            let flowLevel = flowRecords.first(where: { $0.day == day })?.flowLevel
            let signal = signalRecords[day]
            return PeriodStore.HealthImportDayLog(
                date: day,
                flowLevel: flowLevel,
                painLevel: signal?.painLevel,
                moodLevel: signal?.moodLevel,
                hasSexualActivity: signal?.hasSexualActivity,
                hasIntermenstrualBleeding: signal?.hasIntermenstrualBleeding,
                pregnancyTestResult: signal?.pregnancyTestResult,
                ovulationTestResult: signal?.ovulationTestResult,
                cervicalMucusQuality: signal?.cervicalMucusQuality,
                note: signal?.note
            )
        }
    }

    private func aggregatePeriodHealthSignals(
        crampsSamples: [HKCategorySample],
        moodSamples: [HKCategorySample],
        sexualActivitySamples: [HKCategorySample],
        spottingSamples: [HKCategorySample],
        ovulationSamples: [HKCategorySample],
        cervicalMucusSamples: [HKCategorySample],
        pregnancyTestSamples: [HKCategorySample]
    ) -> [Date: PeriodHealthSignalRecord] {
        let calendar = Calendar.current
        var records: [Date: PeriodHealthSignalRecord] = [:]

        func upsert(day: Date, transform: (inout PeriodHealthSignalRecord) -> Void) {
            let normalized = calendar.startOfDay(for: day)
            var record = records[normalized] ?? PeriodHealthSignalRecord(day: normalized)
            transform(&record)
            records[normalized] = record
        }

        for sample in crampsSamples {
            upsert(day: sample.startDate) { record in
                record.painLevel = max(record.painLevel ?? 0, severityLevel(from: sample.value))
            }
        }
        for sample in moodSamples {
            upsert(day: sample.startDate) { record in
                record.moodLevel = max(record.moodLevel ?? 0, severityLevel(from: sample.value))
            }
        }
        for sample in sexualActivitySamples {
            upsert(day: sample.startDate) { record in record.hasSexualActivity = true }
        }
        for sample in spottingSamples {
            upsert(day: sample.startDate) { record in record.hasIntermenstrualBleeding = true }
        }
        for sample in ovulationSamples {
            let result = ovulationTestResultValue(for: sample.value)
            guard !result.isEmpty else { continue }
            upsert(day: sample.startDate) { record in record.ovulationTestResult = result }
        }
        for sample in cervicalMucusSamples {
            let result = cervicalMucusValue(for: sample.value)
            guard !result.isEmpty else { continue }
            upsert(day: sample.startDate) { record in record.cervicalMucusQuality = result }
        }
        for sample in pregnancyTestSamples {
            let result = pregnancyTestResultValue(for: sample.value)
            guard !result.isEmpty else { continue }
            upsert(day: sample.startDate) { record in record.pregnancyTestResult = result }
        }
        for key in records.keys {
            var record = records[key] ?? PeriodHealthSignalRecord(day: key)
            record.note = periodSignalFallbackNote(from: record)
            records[key] = record
        }
        return records
    }

    private func severityLevel(from healthValue: Int) -> Int { min(max(healthValue + 1, 1), 5) }
    private func healthSeverityValue(from level: Int) -> Int { min(max(level - 1, 0), 4) }

    private func cervicalMucusValue(for healthValue: Int) -> String {
        switch HKCategoryValueCervicalMucusQuality(rawValue: healthValue) {
        case .dry: return "dry"
        case .sticky: return "sticky"
        case .creamy: return "creamy"
        case .watery: return "watery"
        case .eggWhite: return "eggWhite"
        default: return ""
        }
    }

    private func ovulationTestResultValue(for healthValue: Int) -> String {
        switch HKCategoryValueOvulationTestResult(rawValue: healthValue) {
        case .negative: return "negative"
        case .luteinizingHormoneSurge: return "peak"
        case .indeterminate: return "inconclusive"
        case .estrogenSurge: return "positive"
        default: return ""
        }
    }

    private func pregnancyTestResultValue(for healthValue: Int) -> String {
        switch HKCategoryValuePregnancyTestResult(rawValue: healthValue) {
        case .negative: return "negative"
        case .positive: return "positive"
        case .indeterminate: return "inconclusive"
        default: return ""
        }
    }

    private func periodSignalFallbackNote(from record: PeriodHealthSignalRecord) -> String? {
        var parts: [String] = []
        if record.hasSexualActivity == true { parts.append("性行为") }
        if record.hasIntermenstrualBleeding == true { parts.append("点滴出血") }
        if let result = record.pregnancyTestResult {
            let title = pregnancyTestDisplayTitle(for: result)
            if !title.isEmpty { parts.append(title) }
        }
        if let result = record.ovulationTestResult {
            let title = ovulationTestDisplayTitle(for: result)
            if !title.isEmpty { parts.append(title) }
        }
        if let quality = record.cervicalMucusQuality {
            let title = cervicalMucusDisplayTitle(for: quality)
            if !title.isEmpty { parts.append(title) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func cervicalMucusDisplayTitle(for value: String) -> String {
        switch value {
        case "dry": return "宫颈黏液偏干"
        case "sticky": return "宫颈黏液黏稠"
        case "creamy": return "宫颈黏液乳霜样"
        case "watery": return "宫颈黏液水样"
        case "eggWhite": return "宫颈黏液蛋清样"
        default: return ""
        }
    }

    private func ovulationTestDisplayTitle(for value: String) -> String {
        switch value {
        case "negative": return "排卵测试阴性"
        case "positive": return "排卵测试阳性"
        case "peak": return "排卵峰值提示"
        case "inconclusive": return "排卵测试待确认"
        default: return ""
        }
    }

    private func pregnancyTestDisplayTitle(for value: String) -> String {
        switch value {
        case "negative": return "妊娠测试阴性"
        case "positive": return "妊娠测试阳性"
        case "inconclusive": return "妊娠测试待确认"
        default: return ""
        }
    }

    func deleteObjects(type: HKSampleType, predicate: NSPredicate) async -> Bool {
        await withCheckedContinuation { continuation in
            healthStore.deleteObjects(of: type, predicate: predicate) { success, _, _ in
                continuation.resume(returning: success)
            }
        }
    }

    func saveObject(_ object: HKObject) async -> Bool {
        await withCheckedContinuation { continuation in
            healthStore.save(object) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    static let periodDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private struct MenstrualFlowDayRecord {
        let day: Date
        var flowLevel: Int
        var isCycleStart: Bool
    }

    struct PeriodHealthSignalRecord {
        let day: Date
        var painLevel: Int? = nil
        var moodLevel: Int? = nil
        var hasSexualActivity: Bool? = nil
        var hasIntermenstrualBleeding: Bool? = nil
        var pregnancyTestResult: String? = nil
        var ovulationTestResult: String? = nil
        var cervicalMucusQuality: String? = nil
        var note: String? = nil
    }
}
