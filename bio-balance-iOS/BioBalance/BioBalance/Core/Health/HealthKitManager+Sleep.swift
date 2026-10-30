/// HealthKitManager Sleep Extension — 睡眠相关数据读取与处理。
import Foundation
import HealthKit

/// 睡眠区间的可缓存派生值，不落盘任何睡眠阶段原始样本。
struct HealthKitSleepIntervalCacheValue: Codable, Equatable, Sendable {
    let start: Date
    let end: Date
}

// MARK: - Sleep

extension HealthKitManager {
    // MARK: 私有辅助方法

    struct SleepSession: Sendable {
        let day: Date
        let start: Date
        let end: Date
        let asleepMinutes: Double
    }

    func fetchSleepSamples(start: Date, end: Date) async throws -> [HKCategorySample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await fetchCategorySamples(type: sleepType, predicate: predicate, sort: [sort])
    }

    /// 官方推荐用 `allAsleepValues` 判定 asleep 样本，系统未来新增睡眠阶段值时不会被遗漏。
    static let asleepRawValues: Set<Int> = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))

    func isAsleepSleepSample(_ sample: HKCategorySample) -> Bool {
        Self.asleepRawValues.contains(sample.value)
    }

    /// 统一的睡眠日归属口径：会话按结束时间所在日历日归属，所有睡眠查询共用，避免口径漂移。
    func sleepDayAnchor(for sessionEnd: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: sessionEnd)
    }

    func primarySleepCluster(
        in clusters: [[HKCategorySample]],
        on targetDate: Date,
        calendar: Calendar = .current
    ) -> [HKCategorySample]? {
        let targetDay = calendar.startOfDay(for: targetDate)
        return clusters
            .filter { cluster in
                guard let sessionEnd = cluster.map(\.endDate).max() else { return false }
                return sleepDayAnchor(for: sessionEnd, calendar: calendar) == targetDay
            }
            .max { lhs, rhs in
                let lhsMinutes = displaySleepMinutes(in: lhs)
                let rhsMinutes = displaySleepMinutes(in: rhs)
                if lhsMinutes != rhsMinutes { return lhsMinutes < rhsMinutes }
                return (lhs.map(\.endDate).max() ?? .distantPast) < (rhs.map(\.endDate).max() ?? .distantPast)
            }
    }

    func isInBedOrAsleepSleepSample(_ sample: HKCategorySample) -> Bool {
        if isAsleepSleepSample(sample) { return true }
        return sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue
    }

    func clusterSleepSamples(_ samples: [HKCategorySample]) -> [[HKCategorySample]] {
        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }
        guard !sortedSamples.isEmpty else { return [] }
        var clusters: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        for sample in sortedSamples {
            guard let last = current.last else {
                current = [sample]
                continue
            }
            let gap = sample.startDate.timeIntervalSince(last.endDate)
            if gap <= 2 * 3600 {
                current.append(sample)
            } else {
                clusters.append(current)
                current = [sample]
            }
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }

    /// 多来源（Watch/iPhone/第三方 App）的睡眠样本区间可能互相重叠，
    /// 官方文档要求先做区间并集再累计时长，避免同一段睡眠被双重计数。
    nonisolated func mergedSleepIntervals(of samples: [HKCategorySample]) -> [DateInterval] {
        let sorted = samples
            .filter { $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }
        var merged: [DateInterval] = []
        for sample in sorted {
            if let last = merged.last, sample.startDate <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, sample.endDate))
            } else {
                merged.append(DateInterval(start: sample.startDate, end: sample.endDate))
            }
        }
        return merged
    }

    /// 区间并集后的总分钟数。
    nonisolated func mergedSleepMinutes(of samples: [HKCategorySample]) -> Int {
        Int(mergedSleepIntervals(of: samples).reduce(0) { $0 + $1.duration } / 60.0)
    }

    func sleepMinutes(in cluster: [HKCategorySample]) -> Int {
        mergedSleepMinutes(of: cluster)
    }

    /// 可展示的睡眠分钟数：优先计算 asleep 阶段的并集；当该 cluster 只有 inBed 记录
    /// （部分数据源/午睡不写阶段明细）时回退计入 inBed 时长，避免“有睡眠但显示 0”。
    func displaySleepMinutes(in cluster: [HKCategorySample]) -> Int {
        let asleep = cluster.filter(isAsleepSleepSample)
        if !asleep.isEmpty {
            return sleepMinutes(in: asleep)
        }
        return sleepMinutes(in: cluster)
    }

    func isAsleepSample(_ sample: HKCategorySample) -> Bool {
        guard sample.categoryType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue else { return false }
        return isAsleepSleepSample(sample)
    }

    func isCurrentlyAsleep(at date: Date) async throws -> Bool {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        let lookbackStart = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-24 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: lookbackStart, end: date, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let samples = try await fetchCategorySamples(type: sleepType, predicate: predicate, sort: sort)
        return samples.contains { sample in
            isAsleepSample(sample) && sample.startDate <= date && sample.endDate > date
        }
    }

    // MARK: 睡眠区间与时长

    /// 方法说明：读取最近一晚主睡眠会话的时间区间。
    func fetchLatestSleepInterval() async throws -> SleepInterval? {
        let cached: HealthKitSleepIntervalCacheValue? = try await cachedRepositoryValue(
            domain: "sleep",
            name: "latestSleepInterval",
            parameters: "latest",
            ttl: HealthKitRepositoryCache.realtimeTTL
        ) {
            let calendar = Calendar.current
            let now = Date()
            let startOfToday = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? Date.distantPast
            let samples = try await fetchSleepSamples(start: start, end: now)
            let relevant = samples.filter(isInBedOrAsleepSleepSample)
            let clusters = clusterSleepSamples(relevant)
            guard let best = clusters.max(by: { lhs, rhs in
                let lhsMinutes = displaySleepMinutes(in: lhs)
                let rhsMinutes = displaySleepMinutes(in: rhs)
                if lhsMinutes != rhsMinutes { return lhsMinutes < rhsMinutes }
                return (lhs.map(\.endDate).max() ?? .distantPast) < (rhs.map(\.endDate).max() ?? .distantPast)
            }) else { return nil }
            guard let sessionStart = best.map(\.startDate).min(),
                  let sessionEnd = best.map(\.endDate).max(),
                  sessionEnd > sessionStart else { return nil }
            return HealthKitSleepIntervalCacheValue(start: sessionStart, end: sessionEnd)
        }
        guard let cached else { return nil }
        return SleepInterval(start: cached.start, end: cached.end)
    }

    /// 读取归属于目标睡眠日的主睡眠会话，供“今日”类计算避免回退到旧夜晚。
    func fetchPrimarySleepInterval(on date: Date) async throws -> SleepInterval? {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        let cached: HealthKitSleepIntervalCacheValue? = try await cachedRepositoryValue(
            domain: "sleep",
            name: "primarySleepInterval",
            parameters: "\(Int64(targetDay.timeIntervalSince1970))",
            ttl: HealthKitRepositoryCache.realtimeTTL
        ) {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: targetDay) ?? date
            let end = min(dayEnd, Date())
            let start = calendar.date(byAdding: .day, value: -1, to: targetDay) ?? Date.distantPast
            guard end > start else { return nil }
            let samples = try await fetchSleepSamples(start: start, end: end)
            let relevant = samples.filter(isInBedOrAsleepSleepSample)
            let clusters = clusterSleepSamples(relevant)
            guard let best = primarySleepCluster(in: clusters, on: targetDay, calendar: calendar) else { return nil }
            guard let sessionStart = best.map(\.startDate).min(),
                  let sessionEnd = best.map(\.endDate).max(),
                  sessionEnd > sessionStart else { return nil }
            return HealthKitSleepIntervalCacheValue(start: sessionStart, end: sessionEnd)
        }
        guard let cached else { return nil }
        return SleepInterval(start: cached.start, end: cached.end)
    }

    /// 读取与请求日期重叠的所有睡眠时段，包括白天小睡。
    func fetchSleepIntervals(on date: Date = Date()) async throws -> [SleepInterval] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let queryStart = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        let samples = try await fetchSleepSamples(start: queryStart, end: dayEnd)
        return clusterSleepSamples(samples.filter(isInBedOrAsleepSleepSample)).compactMap { cluster in
            guard let rawStart = cluster.map(\.startDate).min(),
                  let rawEnd = cluster.map(\.endDate).max(),
                  rawEnd > dayStart,
                  rawStart < dayEnd else { return nil }
            // 保留原始时间边界，避免跨夜睡眠被显示为从请求日期的午夜开始。
            return SleepInterval(start: rawStart, end: rawEnd)
        }.sorted { $0.start < $1.start }
    }

    func fetchSleepDurationInMinutes() async throws -> Int {
        try await fetchSleepDurationInMinutes(on: Date())
    }

    /// 方法说明：读取指定日期对应的所有 asleep 总时长（含午睡）。
    func fetchSleepDurationInMinutes(on date: Date) async throws -> Int {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "sleep",
            name: "sleepDuration",
            parameters: parameters
        ) {
            let calendar = Calendar.current
            let targetDay = calendar.startOfDay(for: date)
            guard let sleepWindowStart = calendar.date(byAdding: .day, value: -1, to: targetDay),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: targetDay) else {
                throw HealthKitError.dataFetchFailed
            }
            let end = min(dayEnd, Date())
            if end < sleepWindowStart { return 0 }
            let samples = try await fetchSleepSamples(start: sleepWindowStart, end: end)
            // 与 fetchSleepIntervals 使用同一批样本口径（inBed + asleep 都参与分簇），
            // 归属按“与目标日重叠”，避免只有 inBed 无 asleep 阶段的数据源被统计成 0。
            let clusters = clusterSleepSamples(samples.filter(isInBedOrAsleepSleepSample))
            return clusters
                .filter { cluster in
                    guard let rawStart = cluster.map(\.startDate).min(),
                          let rawEnd = cluster.map(\.endDate).max() else { return false }
                    return rawEnd > targetDay && rawStart < dayEnd
                }
                .reduce(0) { acc, cluster in acc + displaySleepMinutes(in: cluster) }
        }
    }

    /// 读取指定日期的主睡眠（当日最长段）时长：asleep 优先、inBed 兜底，不含午睡。
    /// 睡眠详情页的“主睡眠”与各分析模块统一使用该口径；`fetchSleepDurationInMinutes` 仍返回当日总量（含午睡）。
    func fetchMainSleepDurationInMinutes(on date: Date = Date()) async throws -> Int {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        guard let sleepWindowStart = calendar.date(byAdding: .day, value: -1, to: targetDay),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: targetDay) else {
            throw HealthKitError.dataFetchFailed
        }
        let end = min(dayEnd, Date())
        if end < sleepWindowStart { return 0 }
        let samples = try await fetchSleepSamples(start: sleepWindowStart, end: end)
        let clusters = clusterSleepSamples(samples.filter(isInBedOrAsleepSleepSample))
        guard let best = primarySleepCluster(in: clusters, on: targetDay, calendar: calendar) else { return 0 }
        return displaySleepMinutes(in: best)
    }

    /// 方法说明：在用户允许的前提下，为缺失主睡眠记录的夜晚补写一条最小睡眠摘要。
    func saveSupplementalSleepSession(start: Date, end: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.notAvailableOnDevice }
        guard end > start, let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        let sample = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: start, end: end)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error { continuation.resume(throwing: error); return }
                if success { continuation.resume() } else { continuation.resume(throwing: HealthKitError.authorizationFailed) }
            }
        }
    }

    // MARK: 睡眠阶段

    func fetchDetailedSleepStages() async throws -> [SleepStage] {
        try await cachedRepositoryValue(
            domain: "sleep",
            name: "detailedSleepStages",
            parameters: "latest",
            ttl: HealthKitRepositoryCache.realtimeTTL
        ) {
            // 先定位最近一晚主睡眠会话，只解析该会话内的样本，
            // 避免把前一天午睡或窗口内其他零散样本混入阶段时间轴。
            guard let interval = try await fetchLatestSleepInterval() else { return [] }
            let samples = try await fetchSleepSamples(start: interval.start, end: interval.end)
                .filter { $0.startDate >= interval.start }
            var stages: [SleepStage] = []
            for sample in samples {
                let minutes = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
                guard minutes > 0 else { continue }
                let stageName: String?
                let sourceType: String
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .awake: stageName = "清醒"; sourceType = ".awake"
                case .asleepCore: stageName = "浅睡"; sourceType = ".asleepCore"
                case .asleepDeep: stageName = "深睡"; sourceType = ".asleepDeep"
                case .asleepREM: stageName = "快速眼动"; sourceType = ".asleepREM"
                case .asleepUnspecified: stageName = "浅睡"; sourceType = ".asleep"
                case .inBed: stageName = nil; sourceType = ".inBed"
                default: stageName = nil; sourceType = ".unknown\(sample.value))"
                }
                guard let stageName else { continue }
                stages.append(SleepStage(stage: stageName, duration: minutes, startDate: sample.startDate, endDate: sample.endDate, sourceType: sourceType))
            }
            return stages
        }
    }

    /// 按 cluster（连续睡眠段，间隔 >2 小时即拆分）返回真实会话：
    /// 夜间主睡眠与白天午睡各自独立成会话，不再按天粗暴合并成一条伪会话；
    /// asleepMinutes 使用区间并集去重，day 统一用 sleepDayAnchor 归属。
    func fetchSleepSessions(days: Int) async throws -> [SleepSession] {
        let calendar = Calendar.current
        let end = Date()
        let windowDays = max(days, 1)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: end)) else { return [] }
        let samples = try await fetchSleepSamples(start: start, end: end)
        // 与 fetchSleepIntervals 口径一致：inBed + asleep 都参与分簇，
        // 只有 inBed 记录的数据源同样产生可展示的会话时长。
        let relevant = samples.filter(isInBedOrAsleepSleepSample)
        return clusterSleepSamples(relevant).compactMap { cluster -> SleepSession? in
            guard let sessionStart = cluster.map(\.startDate).min(),
                  let sessionEnd = cluster.map(\.endDate).max(),
                  sessionEnd > sessionStart else { return nil }
            return SleepSession(
                day: sleepDayAnchor(for: sessionEnd, calendar: calendar),
                start: sessionStart,
                end: sessionEnd,
                asleepMinutes: Double(displaySleepMinutes(in: cluster))
            )
        }.sorted { $0.start < $1.start }
    }

    /// 每天的主睡眠会话（asleepMinutes 最长者），用于就寝一致性、夜间生命体征等
    /// 不应被午睡污染的场景。
    func primarySleepSessions(days: Int) async throws -> [SleepSession] {
        let sessions = try await fetchSleepSessions(days: days)
        let grouped = Dictionary(grouping: sessions, by: \.day)
        return grouped.values.compactMap { daySessions in
            daySessions.max { lhs, rhs in
                if lhs.asleepMinutes != rhs.asleepMinutes { return lhs.asleepMinutes < rhs.asleepMinutes }
                return lhs.end < rhs.end
            }
        }.sorted { $0.day < $1.day }
    }

    // MARK: 夜间生命体征聚合

    /// cluster 化后每天取主会话窗口，夜间生命体征只在主睡眠区间内统计，
    /// 避免午睡把统计窗口拉长污染夜间数据；日归属统一用 sleepDayAnchor。
    private func primaryNightWindows(days: Int, endDate: Date) async throws -> [(day: Date, start: Date, end: Date)] {
        let calendar = Calendar.current
        // 窗口截止到 endDate 当天正午，完整覆盖当天早晨结束的主睡眠。
        let end = calendar.startOfDay(for: endDate).addingTimeInterval(12 * 3600)
        guard let start = calendar.date(byAdding: .day, value: -max(1, days + 1), to: end) else { return [] }
        let samples = try await fetchSleepSamples(start: start, end: end)
        // 与主睡眠口径一致：inBed + asleep 都参与分簇，asleep 优先、inBed 兜底，
        // 保证只有 inBed 记录时夜间生命体征仍落在主睡眠窗口（而非午睡）。
        let relevant = samples.filter(isInBedOrAsleepSleepSample)
        var bestByDay: [Date: (start: Date, end: Date, minutes: Int)] = [:]
        for cluster in clusterSleepSamples(relevant) {
            guard let sessionStart = cluster.map(\.startDate).min(),
                  let sessionEnd = cluster.map(\.endDate).max(),
                  sessionEnd > sessionStart else { continue }
            let day = sleepDayAnchor(for: sessionEnd, calendar: calendar)
            let minutes = displaySleepMinutes(in: cluster)
            if minutes > (bestByDay[day]?.minutes ?? -1) {
                bestByDay[day] = (sessionStart, sessionEnd, minutes)
            }
        }
        return bestByDay.keys.sorted().suffix(max(1, days)).compactMap { day in
            guard let window = bestByDay[day] else { return nil }
            return (day: day, start: window.start, end: window.end)
        }
    }

    func fetchNightlyHRVAverages(days: Int = 14) async throws -> [NightlyHRV] {
        try await fetchNightlyHRVAverages(days: days, endDate: Date())
    }

    func fetchNightlyHRVAverages(days: Int = 14, endDate: Date) async throws -> [NightlyHRV] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { throw HealthKitError.dataTypeNotAvailable }
        let sessions = try await primaryNightWindows(days: days, endDate: endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.secondUnit(with: .milli)
        var result: [NightlyHRV] = []
        result.reserveCapacity(sessions.count)
        for session in sessions {
            let hrvPredicate = HKQuery.predicateForSamples(withStart: session.start, end: session.end, options: .strictStartDate)
            let hrvSamples = try await fetchQuantitySamples(type: hrvType, predicate: hrvPredicate, sort: [sort])
            let values = hrvSamples.map { $0.quantity.doubleValue(for: unit) }.filter { $0 > 0 }
            guard !values.isEmpty else { continue }
            result.append(NightlyHRV(date: session.day, start: session.start, end: session.end, avgMs: values.reduce(0, +) / Double(values.count), sampleCount: values.count))
        }
        return result
    }

    func fetchNightlyHeartRateAverages(days: Int = 14) async throws -> [NightlyAverageVital] {
        guard let t = HKQuantityType.quantityType(forIdentifier: .heartRate) else { throw HealthKitError.dataTypeNotAvailable }
        return try await fetchNightlyAverages(quantityType: t, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), days: days, endDate: Date())
    }

    func fetchNightlyHeartRateAverages(days: Int = 14, endDate: Date) async throws -> [NightlyAverageVital] {
        guard let t = HKQuantityType.quantityType(forIdentifier: .heartRate) else { throw HealthKitError.dataTypeNotAvailable }
        return try await fetchNightlyAverages(quantityType: t, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), days: days, endDate: endDate)
    }

    func fetchNightlyRespiratoryRateAverages(days: Int = 14) async throws -> [NightlyAverageVital] {
        guard let t = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else { throw HealthKitError.dataTypeNotAvailable }
        return try await fetchNightlyAverages(quantityType: t, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), days: days, endDate: Date())
    }

    private func fetchNightlyAverages(quantityType: HKQuantityType, unit: HKUnit, days: Int, endDate: Date) async throws -> [NightlyAverageVital] {
        let sessions = try await primaryNightWindows(days: days, endDate: endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        var result: [NightlyAverageVital] = []
        result.reserveCapacity(sessions.count)
        for session in sessions {
            let predicate = HKQuery.predicateForSamples(withStart: session.start, end: session.end, options: .strictStartDate)
            let samples = try await fetchQuantitySamples(type: quantityType, predicate: predicate, sort: [sort])
            let values = samples.map { $0.quantity.doubleValue(for: unit) }.filter { $0 > 0 }
            guard !values.isEmpty else { continue }
            result.append(NightlyAverageVital(date: session.day, start: session.start, end: session.end, averageValue: values.reduce(0, +) / Double(values.count), sampleCount: values.count))
        }
        return result
    }

    func fetchOvernightMinimumHeartRate(interval: SleepInterval?) async throws -> Double? {
        guard let interval else { return nil }
        let points = try await fetchHeartRateSeries(start: interval.start, end: interval.end, maxPoints: 240)
        return points.map { Double($0.value) }.filter { $0 > 0 }.min()
    }

    // MARK: 睡眠趋势序列

    func fetchDailySleepScoreSeries(days: Int = 30, endDate: Date = Date()) async throws -> [TimeSeriesPointDouble] {
        let summaries = try await fetchSleepNightSummaries(days: days, endDate: endDate)
        return summaries.map { TimeSeriesPointDouble(timestamp: Int64(Calendar.current.startOfDay(for: $0.day).timeIntervalSince1970), value: Double($0.sleepScoreEstimate)) }
    }

    func fetchSleepDurationSeries(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await cachedRepositoryValue(
            domain: "sleep",
            name: "sleepDurationSeries",
            parameters: "\(max(days, 1))"
        ) {
            // 时长系列按天聚合当日全部会话（含午睡），与“睡眠总时长”口径一致。
            let sessions = try await fetchSleepSessions(days: days)
            let grouped = Dictionary(grouping: sessions, by: \.day)
            return grouped
                .map { day, daySessions in
                    TimeSeriesPointDouble(
                        timestamp: Int64(day.timeIntervalSince1970),
                        value: daySessions.reduce(0) { $0 + $1.asleepMinutes }
                    )
                }
                .sorted { $0.timestamp < $1.timestamp }
        }
    }

    func fetchSleepConsistencySeries(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await cachedRepositoryValue(
            domain: "sleep",
            name: "sleepConsistencySeries",
            parameters: "\(max(days, 1))"
        ) {
            // 就寝一致性只看每天主睡眠的入睡时刻，午睡不参与计算。
            let sessions = try await primarySleepSessions(days: days)
            guard sessions.count >= 2 else { return [] }
            var points: [TimeSeriesPointDouble] = []
            for index in sessions.indices.dropFirst() {
                let window = Array(sessions[max(0, index - 2)...index])
                let bedtimes = window.map { s -> Double in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: s.start)
                    return Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0)
                }
                let mean = bedtimes.reduce(0, +) / Double(bedtimes.count)
                let deviation = bedtimes.map { abs($0 - mean) }.reduce(0, +) / Double(bedtimes.count)
                points.append(TimeSeriesPointDouble(timestamp: Int64(sessions[index].day.timeIntervalSince1970), value: max(0, 100 - deviation)))
            }
            return points
        }
    }

    func fetchSleepNightSummaries(days: Int = 30) async throws -> [SleepTrendNightSummary] {
        try await fetchSleepNightSummaries(days: days, endDate: Date())
    }

    func fetchSleepNightSummaries(days: Int = 30, endDate: Date) async throws -> [SleepTrendNightSummary] {
        let parameters = "\(max(days, 1)).\(Int64(Calendar.current.startOfDay(for: endDate).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "sleep",
            name: "sleepNightSummaries",
            parameters: parameters
        ) {
            let calendar = Calendar.current
            let end = min(endDate, Date())
            let windowDays = max(days, 1)
            guard let start = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: end)) else { return [] }
            let samples = try await fetchSleepSamples(start: start, end: end)
            // 每天取 asleep 时长最长的主会话，午睡不再与夜间主睡眠混入同一条摘要。
            var primaryByDay: [Date: [HKCategorySample]] = [:]
            var primaryAsleepByDay: [Date: Int] = [:]
            for cluster in clusterSleepSamples(samples) {
                guard let sessionEnd = cluster.map(\.endDate).max() else { continue }
                let day = sleepDayAnchor(for: sessionEnd, calendar: calendar)
                let asleepMinutes = mergedSleepMinutes(of: cluster.filter(isAsleepSleepSample))
                if asleepMinutes > (primaryAsleepByDay[day] ?? -1) {
                    primaryByDay[day] = cluster
                    primaryAsleepByDay[day] = asleepMinutes
                }
            }
            return primaryByDay.keys.sorted().suffix(windowDays).compactMap { day -> SleepTrendNightSummary? in
                guard let cluster = primaryByDay[day],
                      let sessionStart = cluster.map(\.startDate).min(),
                      let sessionEnd = cluster.map(\.endDate).max(),
                      sessionEnd > sessionStart else { return nil }
                // 各阶段分别做区间并集去重，多来源重叠样本不会双重计数。
                func stageMinutes(_ rawValues: Set<Int>) -> Int {
                    mergedSleepMinutes(of: cluster.filter { rawValues.contains($0.value) })
                }
                let inBedSamples = cluster.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
                let awake = stageMinutes([HKCategoryValueSleepAnalysis.awake.rawValue])
                // asleepUnspecified 维持原口径计入浅睡。
                let core = stageMinutes([HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue])
                let deep = stageMinutes([HKCategoryValueSleepAnalysis.asleepDeep.rawValue])
                let rem = stageMinutes([HKCategoryValueSleepAnalysis.asleepREM.rawValue])
                let asleep = mergedSleepMinutes(of: cluster.filter(isAsleepSleepSample))
                return SleepTrendNightSummary(
                    day: day,
                    startTime: sessionStart,
                    endTime: sessionEnd,
                    inBedMinutes: inBedSamples.isEmpty ? nil : mergedSleepMinutes(of: inBedSamples),
                    asleepMinutes: asleep,
                    awakeMinutes: awake,
                    coreMinutes: core,
                    deepMinutes: deep,
                    remMinutes: rem
                )
            }.sorted { $0.day < $1.day }
        }
    }

    func fetchStressHabitualSleepWindow(days: Int = 7) async throws -> StressHabitualSleepWindow {
        try await cachedRepositoryValue(
            domain: "sleep",
            name: "habitualSleepWindow",
            parameters: "\(max(days, 1))",
            ttl: HealthKitRepositoryCache.algorithmTTL
        ) {
            // 惯常睡眠窗口只看每天主睡眠，午睡不应干扰中位数。
            let sessions = try await primarySleepSessions(days: max(days, 1))
            guard !sessions.isEmpty else { return .fallback }
            let startMin = sessions.map { let c = Calendar.current.dateComponents([.hour, .minute], from: $0.start); return (c.hour ?? 23) * 60 + (c.minute ?? 0) }.sorted()
            let endMin = sessions.map { let c = Calendar.current.dateComponents([.hour, .minute], from: $0.end); return (c.hour ?? 7) * 60 + (c.minute ?? 0) }.sorted()
            guard let ms = medianMinute(startMin), let me = medianMinute(endMin) else { return .fallback }
            return StressHabitualSleepWindow(startHour: ms / 60, startMinute: ms % 60, endHour: me / 60, endMinute: me % 60)
        }
    }

    // MARK: 睡眠腕温

    func fetchLatestSleepingWristTemperature() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else { throw HealthKitError.dataTypeNotAvailable }
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "appleSleepingWristTemperature.latest",
            status: samples.isEmpty ? .noData : .dataAvailable
        )
        guard let sample = samples.first else { return nil }
        return sample.quantity.doubleValue(for: HKUnit.degreeCelsius())
    }

    func fetchDailySleepingWristTemperatureAverages(days: Int = 7) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailySleepingWristTemperatureAverages(days: days, endDate: Date())
    }

    func fetchDailySleepingWristTemperatureAverages(days: Int = 7, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        let parameters = "\(max(days, 1)).\(Int64(Calendar.current.startOfDay(for: endDate).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "body",
            name: "sleepingWristTemperature",
            parameters: parameters
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else { throw HealthKitError.dataTypeNotAvailable }
            let calendar = Calendar.current
            let normalizedEnd = calendar.startOfDay(for: endDate)
            let end = calendar.date(byAdding: .day, value: 1, to: normalizedEnd) ?? normalizedEnd
            let start = calendar.date(byAdding: .day, value: -(max(days, 1) + 1), to: normalizedEnd) ?? Date.distantPast
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let unit = HKUnit.degreeCelsius()
            let samples = try await fetchQuantitySamples(type: type, predicate: predicate, sort: [sort])
            let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.endDate) }
            return grouped.keys.sorted().suffix(max(days, 1)).compactMap { day in
                let values = (grouped[day] ?? []).map { $0.quantity.doubleValue(for: unit) }.filter { $0 > 0 }
                guard !values.isEmpty else { return nil }
                return TimeSeriesPointDouble(timestamp: Int64(day.timeIntervalSince1970), value: values.reduce(0, +) / Double(values.count))
            }
        }
    }

    func fetchDailySleepingBreathingDisturbanceAverages(
        days: Int = 21,
        endDate: Date = Date()
    ) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .appleSleepingBreathingDisturbances,
            unit: .count(),
            options: .discreteAverage,
            days: days,
            endDate: endDate
        )
        .filter { $0.value.isFinite && $0.value >= 0 }
    }
}
