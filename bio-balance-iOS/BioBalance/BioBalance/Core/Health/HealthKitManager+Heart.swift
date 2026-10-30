import Foundation
import HealthKit

// MARK: - Heart Rate, HRV, Respiratory, Blood Pressure & ECG

extension HealthKitManager {

    // MARK: 最新值

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestHeartRate() async throws -> Double {
        try await cachedRepositoryValue(
            domain: "heart",
            name: "latestHeartRate",
            parameters: "latest",
            ttl: HealthKitRepositoryCache.realtimeTTL
        ) {
            guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
                throw HealthKitError.dataTypeNotAvailable
            }

            let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: heartRateType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            let samples = try await descriptor.result(for: healthStore)
            let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
            logHealthKitRead(
                metric: "heartRate.latest",
                status: samples.isEmpty ? .noData : .dataAvailable
            )
            guard let sample = samples.first else {
                throw HealthKitError.dataFetchFailed
            }
            return sample.quantity.doubleValue(for: heartRateUnit)
        }
    }
    
    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestHRV() async throws -> Double {
        try await cachedRepositoryValue(
            domain: "heart",
            name: "latestHRV",
            parameters: "latest",
            ttl: HealthKitRepositoryCache.realtimeTTL
        ) {
            guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
                throw HealthKitError.dataTypeNotAvailable
            }

            let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: hrvType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            let samples = try await descriptor.result(for: healthStore)
            let hrvUnit = HKUnit.secondUnit(with: .milli)
            logHealthKitRead(
                metric: "heartRateVariabilitySDNN.latest",
                status: samples.isEmpty ? .noData : .dataAvailable
            )
            guard let sample = samples.first else {
                throw HealthKitError.dataFetchFailed
            }
            return sample.quantity.doubleValue(for: hrvUnit)
        }
    }
    
    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestRespiratoryRate() async throws -> Double {
        try await cachedRepositoryValue(
            domain: "heart",
            name: "latestRespiratoryRate",
            parameters: "latest",
            ttl: HealthKitRepositoryCache.realtimeTTL
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
                throw HealthKitError.dataTypeNotAvailable
            }

            let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            let samples = try await descriptor.result(for: healthStore)
            let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
            logHealthKitRead(
                metric: "respiratoryRate.latest",
                status: samples.isEmpty ? .noData : .dataAvailable
            )
            guard let sample = samples.first else {
                throw HealthKitError.dataFetchFailed
            }
            return sample.quantity.doubleValue(for: unit)
        }
    }

    // MARK: HRV 平均值与样本

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchAverageHRVToday() async throws -> Double {
        try await fetchAverageHRV(on: Date())
    }

    /// 方法说明：负责按指定日期读取 HRV 日均值，便于历史日回看与日级复用。
    func fetchAverageHRV(on date: Date) async throws -> Double {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "heart",
            name: "averageHRV",
            parameters: parameters
        ) {
            guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
                throw HealthKitError.dataTypeNotAvailable
            }

            guard let interval = dayInterval(for: date) else {
                return 0.0
            }
            let end = Calendar.current.isDateInToday(date) ? Date() : interval.end
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: end, options: .strictStartDate)

            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: hrvType, predicate: predicate),
                options: .discreteAverage
            )
            let result = try await descriptor.result(for: healthStore)
            logHealthKitRead(
                metric: "heartRateVariabilitySDNN.average",
                status: result?.averageQuantity() == nil ? .noData : .dataAvailable
            )
            var avgMs = 0.0
            if let avg = result?.averageQuantity() {
                let unit = HKUnit.secondUnit(with: .milli)
                avgMs = avg.doubleValue(for: unit)
            }
            return avgMs
        }
    }

    /// Today HRV Samples 方法，负责读取当天 HRV 明细点列，用于配合外层趋势图展示与授权管理。
    func fetchTodayHRVSamples() async throws -> [TimeSeriesPointDouble] {
        try await fetchHRVSamples(on: Date())
    }

    /// HRV Samples On Day 方法，负责读取指定日期的 HRV 明细点列，用于日级回看与趋势复用。
    func fetchHRVSamples(on date: Date) async throws -> [TimeSeriesPointDouble] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        guard let interval = dayInterval(for: date) else {
            return []
        }
        let end = Calendar.current.isDateInToday(date) ? Date() : interval.end
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples = try await fetchQuantitySamples(type: hrvType, predicate: predicate, sort: [sort])
        let unit = HKUnit.secondUnit(with: .milli)

        return samples.map {
            TimeSeriesPointDouble(
                timestamp: Int64($0.startDate.timeIntervalSince1970),
                value: $0.quantity.doubleValue(for: unit)
            )
        }
        .filter { $0.value > 0 }
    }

    /// HRV Samples 方法，负责按指定时间区间读取 HRV 明细点列，用于睡眠窗口内的恢复趋势绘制。
    func fetchHRVSamples(start: Date, end: Date, maxPoints: Int = 240) async throws -> [TimeSeriesPointDouble] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples = try await fetchQuantitySamples(type: hrvType, predicate: predicate, sort: [sort])
        let unit = HKUnit.secondUnit(with: .milli)

        var points = samples.compactMap { sample -> TimeSeriesPointDouble? in
            let value = sample.quantity.doubleValue(for: unit)
            guard value > 0 else { return nil }
            return TimeSeriesPointDouble(
                timestamp: Int64(sample.startDate.timeIntervalSince1970),
                value: value
            )
        }

        guard maxPoints > 0, points.count > maxPoints else { return points }
        let strideCount = Int(ceil(Double(points.count) / Double(maxPoints)))
        points = points.enumerated().compactMap { idx, point in
            idx % strideCount == 0 ? point : nil
        }
        return points
    }

    func fetchRecentHRVSamples(minutes: Int = 30, maxPoints: Int = 120) async throws -> [TimeSeriesPointDouble] {
        let end = Date()
        let start = end.addingTimeInterval(-Double(max(minutes, 1)) * 60.0)
        return try await fetchHRVSamples(start: start, end: end, maxPoints: maxPoints)
    }

    // MARK: 辅助结构

    /// Nightly HRV 结构体，作为内部辅助类型，用于配合外层健康数据读取与授权管理。
    struct NightlyHRV: Identifiable, Sendable {
        let id: String
        let date: Date
        let start: Date
        let end: Date
        let avgMs: Double
        let sampleCount: Int
        
        /// 方法说明：负责初始化当前类型并准备后续健康数据读取与授权管理。
        init(date: Date, start: Date, end: Date, avgMs: Double, sampleCount: Int) {
            self.date = date
            self.start = start
            self.end = end
            self.avgMs = avgMs
            self.sampleCount = sampleCount
            self.id = "\(date.timeIntervalSince1970)"
        }
    }

    /// Nightly Average Vital 结构体，作为内部辅助类型，用于配合外层健康数据读取与授权管理。
    struct NightlyAverageVital: Identifiable, Sendable {
        let id: String
        let date: Date
        let start: Date
        let end: Date
        let averageValue: Double
        let sampleCount: Int

        /// 方法说明：负责初始化当前类型并准备后续健康数据读取与授权管理。
        init(date: Date, start: Date, end: Date, averageValue: Double, sampleCount: Int) {
            self.date = date
            self.start = start
            self.end = end
            self.averageValue = averageValue
            self.sampleCount = sampleCount
            self.id = "\(date.timeIntervalSince1970)"
        }
    }

    // MARK: 心率序列

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchHeartRateSeries(start: Date, end: Date, maxPoints: Int = 240) async throws -> [TimeSeriesPoint] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples = try await fetchQuantitySamples(type: heartRateType, predicate: predicate, sort: [sort])
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())

        var points = samples.compactMap { sample -> TimeSeriesPoint? in
            let value = Int(sample.quantity.doubleValue(for: unit).rounded())
            guard value > 0 else { return nil }
            return TimeSeriesPoint(timestamp: Int64(sample.startDate.timeIntervalSince1970), value: value)
        }

        guard maxPoints > 0, points.count > maxPoints else { return points }
        let strideCount = Int(ceil(Double(points.count) / Double(maxPoints)))
        points = points.enumerated().compactMap { idx, p in
            idx % strideCount == 0 ? p : nil
        }
        return points
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchHeartRateSeries(on date: Date, maxPoints: Int = 180) async throws -> [TimeSeriesPoint] {
        guard let interval = dayInterval(for: date) else {
            return []
        }
        return try await fetchHeartRateSeries(start: interval.start, end: interval.end, maxPoints: maxPoints)
    }

    func fetchRecentHeartRateSeries(minutes: Int = 30, maxPoints: Int = 180) async throws -> [TimeSeriesPoint] {
        let end = Date()
        let start = end.addingTimeInterval(-Double(max(minutes, 1)) * 60.0)
        return try await fetchHeartRateSeries(start: start, end: end, maxPoints: maxPoints)
    }

    // MARK: 呼吸频率序列

    /// Respiratory Rate Point 结构体，作为内部辅助类型，用于配合外层健康数据读取与授权管理。
    struct RespiratoryRatePoint: Identifiable, Sendable {
        let id: String
        let date: Date
        let value: Double
        
        /// 方法说明：负责初始化当前类型并准备后续健康数据读取与授权管理。
        init(date: Date, value: Double) {
            self.date = date
            self.value = value
            self.id = "\(date.timeIntervalSince1970)"
        }
    }
    
    /// Respiratory Rate Series 方法，负责按时间区间读取呼吸频率点列，用于配合外层趋势图展示与授权管理。
    func fetchRespiratoryRateSeries(start: Date, end: Date, maxPoints: Int = 240) async throws -> [RespiratoryRatePoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples = try await fetchQuantitySamples(type: type, predicate: predicate, sort: [sort])
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        
        var points = samples.compactMap { sample -> RespiratoryRatePoint? in
            let value = sample.quantity.doubleValue(for: unit)
            guard value > 0 else { return nil }
            return RespiratoryRatePoint(date: sample.startDate, value: value)
        }
        
        guard maxPoints > 0, points.count > maxPoints else { return points }
        let strideCount = Int(ceil(Double(points.count) / Double(maxPoints)))
        points = points.enumerated().compactMap { idx, p in
            idx % strideCount == 0 ? p : nil
        }
        return points
    }

    /// Respiratory Rate Time Series 方法，负责将呼吸频率点列转换为通用双精度时序结构，用于睡眠恢复图表复用。
    func fetchRespiratoryRateTimeSeries(start: Date, end: Date, maxPoints: Int = 240) async throws -> [TimeSeriesPointDouble] {
        try await fetchRespiratoryRateSeries(start: start, end: end, maxPoints: maxPoints).map {
            TimeSeriesPointDouble(
                timestamp: Int64($0.date.timeIntervalSince1970),
                value: $0.value
            )
        }
    }

    // MARK: 静息心率

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchRestingHeartRate() async throws -> Double {
        try await fetchRestingHeartRate(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchRestingHeartRate(on date: Date) async throws -> Double {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "heart",
            name: "restingHeartRate",
            parameters: parameters
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
                throw HealthKitError.dataTypeNotAvailable
            }

            guard let interval = dayInterval(for: date) else {
                return 0.0
            }
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            let samples = try await descriptor.result(for: healthStore)
            logHealthKitRead(
                metric: "heartRate.latestForDate",
                status: samples.isEmpty ? .noData : .dataAvailable
            )
            guard let sample = samples.first else {
                return 0.0
            }
            let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
            return sample.quantity.doubleValue(for: unit)
        }
    }

    // MARK: 步行心率

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchWalkingHeartRateAverage(on date: Date = Date()) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .walkingHeartRateAverage) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        guard let interval = dayInterval(for: date) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        let result = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "walkingHeartRateAverage",
            status: result?.averageQuantity() == nil ? .noData : .dataAvailable
        )
        guard let avg = result?.averageQuantity() else {
            return nil
        }
        return avg.doubleValue(for: unit)
    }

    // MARK: 血压

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestBloodPressure() async throws -> (systolic: Double?, diastolic: Double?, sampledAt: Date?) {
        let systolicIdentifier = HKQuantityTypeIdentifier(rawValue: "BloodPressureSystolic")
        let diastolicIdentifier = HKQuantityTypeIdentifier(rawValue: "BloodPressureDiastolic")
        guard
            let systolicType = HKObjectType.quantityType(forIdentifier: systolicIdentifier),
            let diastolicType = HKObjectType.quantityType(forIdentifier: diastolicIdentifier)
        else {
            throw HealthKitError.dataTypeNotAvailable
        }

        async let systolicSample = fetchLatestQuantitySample(
            type: systolicType,
            sortDescriptor: NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        )
        async let diastolicSample = fetchLatestQuantitySample(
            type: diastolicType,
            sortDescriptor: NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        )

        let systolic = try await systolicSample
        let diastolic = try await diastolicSample
        let sampledAt = [systolic?.startDate, diastolic?.startDate].compactMap { $0 }.max()
        let unit = HKUnit.millimeterOfMercury()

        return (
            systolic: systolic?.quantity.doubleValue(for: unit),
            diastolic: diastolic?.quantity.doubleValue(for: unit),
            sampledAt: sampledAt
        )
    }

    // MARK: 心电图

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestElectrocardiograms(limit: Int = 3) async throws -> [HeartECGSample] {
        let sampleType = HKObjectType.electrocardiogramType()

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: sampleType, predicate: nil)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        let samples = try await descriptor.result(for: healthStore)
        let electrocardiograms = samples.compactMap { $0 as? HKElectrocardiogram }

        var results: [HeartECGSample] = []
        for electrocardiogram in electrocardiograms {
            let measurements = try await fetchVoltageMeasurements(for: electrocardiogram)
            let averageHeartRate = electrocardiogram.averageHeartRate?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let samplingFrequency = electrocardiogram.samplingFrequency?.doubleValue(for: .hertz())
            results.append(
                HeartECGSample(
                    id: electrocardiogram.uuid,
                    sampledAt: electrocardiogram.startDate,
                    classification: ecgClassificationText(electrocardiogram.classification),
                    averageHeartRate: averageHeartRate,
                    symptomsStatus: ecgSymptomsText(electrocardiogram.symptomsStatus),
                    samplingFrequencyHz: samplingFrequency,
                    voltageMeasurements: measurements
                )
            )
        }
        return results
    }

    // MARK: 心脏相关每日平均值

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyRestingHeartRateAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyRestingHeartRateAverages(days: Int = 30, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
            options: .discreteAverage,
            days: days,
            endDate: endDate
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyHeartRateAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyHeartRateAverages(days: Int = 30, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
            options: .discreteAverage,
            days: days,
            endDate: endDate
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyHRVAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyHRVAverages(days: Int = 30, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            options: .discreteAverage,
            days: days,
            endDate: endDate
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyWalkingHeartRateAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .walkingHeartRateAverage,
            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyWalkingHeartRateAverages(days: Int = 30, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .walkingHeartRateAverage,
            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
            options: .discreteAverage,
            days: days,
            endDate: endDate
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyRespiratoryRateAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyOxygenSaturationAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .oxygenSaturation,
            unit: .percent(),
            options: .discreteAverage,
            days: days
        )
    }
}
