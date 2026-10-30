import Foundation
import HealthKit

// MARK: - Activity, Energy, Walking Metrics & Daily Series

extension HealthKitManager {

    // MARK: 步态不对称（最新值）

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestWalkingAsymmetryPercentage() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .walkingAsymmetryPercentage) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let unit = HKUnit.percent()
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "walkingAsymmetryPercentage.latest",
            status: samples.isEmpty ? .noData : .dataAvailable
        )
        guard let sample = samples.first else {
            return nil
        }
        return sample.quantity.doubleValue(for: unit)
    }

    // MARK: 步数

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchStepsCount() async throws -> Int {
        try await fetchStepsCount(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchStepsCount(on date: Date) async throws -> Int {
        (try await fetchStepsCountOptional(on: date)) ?? 0
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchStepsCountOptional() async throws -> Int? {
        try await fetchStepsCountOptional(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchStepsCountOptional(on date: Date) async throws -> Int? {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "activity",
            name: "stepsCount",
            parameters: parameters
        ) {
            guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
                throw HealthKitError.dataTypeNotAvailable
            }

            guard let interval = dayInterval(for: date) else {
                return nil
            }
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: stepType, predicate: predicate),
                options: .cumulativeSum
            )
            let result = try await descriptor.result(for: healthStore)
            logHealthKitRead(
                metric: "stepCount",
                status: result?.sumQuantity() == nil ? .noData : .dataAvailable
            )
            guard let sum = result?.sumQuantity() else {
                return nil
            }
            return Int(sum.doubleValue(for: HKUnit.count()))
        }
    }

    // MARK: 活动能量

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchActiveEnergyBurned() async throws -> Int {
        try await fetchActiveEnergyBurned(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchActiveEnergyBurned(on date: Date) async throws -> Int {
        (try await fetchActiveEnergyBurnedOptional(on: date)) ?? 0
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchActiveEnergyBurnedOptional() async throws -> Int? {
        try await fetchActiveEnergyBurnedOptional(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchActiveEnergyBurnedOptional(on date: Date) async throws -> Int? {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "activity",
            name: "activeEnergy",
            parameters: parameters
        ) {
            guard let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
                throw HealthKitError.dataTypeNotAvailable
            }

            guard let interval = dayInterval(for: date) else {
                return nil
            }
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: activeEnergyType, predicate: predicate),
                options: .cumulativeSum
            )
            let result = try await descriptor.result(for: healthStore)
            logHealthKitRead(
                metric: "activeEnergyBurned",
                status: result?.sumQuantity() == nil ? .noData : .dataAvailable
            )
            guard let sum = result?.sumQuantity() else {
                return nil
            }
            return Int(sum.doubleValue(for: HKUnit.kilocalorie()))
        }
    }

    // MARK: 饮食数据（饮水与咖啡因）

    /// 方法说明：读取某天写入健康 App 的饮水总量。
    func fetchDietaryWaterIntake(on date: Date) async throws -> Int {
        guard let type = HKObjectType.quantityType(forIdentifier: .dietaryWater) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        guard let interval = dayInterval(for: date) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let result = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "dietaryWater",
            status: result?.sumQuantity() == nil ? .noData : .dataAvailable
        )
        let value = result?.sumQuantity()?.doubleValue(for: HKUnit.literUnit(with: .milli)) ?? 0
        return Int(value.rounded())
    }

    /// 方法说明：读取某天写入健康 App 的咖啡因总量。
    func fetchDietaryCaffeine(on date: Date) async throws -> Int {
        guard let type = HKObjectType.quantityType(forIdentifier: .dietaryCaffeine) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        guard let interval = dayInterval(for: date) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let result = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "dietaryCaffeine",
            status: result?.sumQuantity() == nil ? .noData : .dataAvailable
        )
        let value = result?.sumQuantity()?.doubleValue(for: .gramUnit(with: .milli)) ?? 0
        return Int(value.rounded())
    }

    // MARK: 基础能量

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchBasalEnergyBurned() async throws -> Int {
        try await fetchBasalEnergyBurned(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchBasalEnergyBurned(on date: Date) async throws -> Int {
        (try await fetchBasalEnergyBurnedOptional(on: date)) ?? 0
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchBasalEnergyBurnedOptional(on date: Date) async throws -> Int? {
        guard let basalEnergyType = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        guard let interval = dayInterval(for: date) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: basalEnergyType, predicate: predicate),
            options: .cumulativeSum
        )
        let result = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "basalEnergyBurned",
            status: result?.sumQuantity() == nil ? .noData : .dataAvailable
        )
        guard let sum = result?.sumQuantity() else {
            return nil
        }
        return Int(sum.doubleValue(for: HKUnit.kilocalorie()))
    }

    // MARK: 锻炼时间

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchExerciseTime() async throws -> Int {
        try await fetchExerciseTime(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchExerciseTime(on date: Date) async throws -> Int {
        (try await fetchExerciseTimeOptional(on: date)) ?? 0
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchExerciseTimeOptional() async throws -> Int? {
        try await fetchExerciseTimeOptional(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchExerciseTimeOptional(on date: Date) async throws -> Int? {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "activity",
            name: "exerciseTime",
            parameters: parameters
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
                throw HealthKitError.dataTypeNotAvailable
            }
            guard let interval = dayInterval(for: date) else {
                return nil
            }
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: type, predicate: predicate),
                options: .cumulativeSum
            )
            let result = try await descriptor.result(for: healthStore)
            logHealthKitRead(
                metric: "appleExerciseTime",
                status: result?.sumQuantity() == nil ? .noData : .dataAvailable
            )
            guard let sum = result?.sumQuantity() else {
                return nil
            }
            return Int(sum.doubleValue(for: HKUnit.minute()))
        }
    }

    // MARK: 站立小时

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchStandHours() async throws -> Int {
        try await fetchStandHours(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchStandHours(on date: Date) async throws -> Int {
        (try await fetchStandHoursOptional(on: date)) ?? 0
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchStandHoursOptional() async throws -> Int? {
        try await fetchStandHoursOptional(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchStandHoursOptional(on date: Date) async throws -> Int? {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "activity",
            name: "standHours",
            parameters: parameters
        ) {
            guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
                throw HealthKitError.dataTypeNotAvailable
            }
            guard let interval = dayInterval(for: date) else {
                return nil
            }
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: type, predicate: predicate)],
                sortDescriptors: [],
                limit: HKObjectQueryNoLimit
            )
            let standSamples = try await descriptor.result(for: healthStore)
            logHealthKitRead(
                metric: "appleStandHour",
                status: standSamples.isEmpty ? .noData : .dataAvailable
            )
            guard !standSamples.isEmpty else {
                return nil
            }
            return standSamples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
        }
    }

    // MARK: 每日步行指标

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchAverageWalkingSpeedToday() async throws -> Double? {
        try await cachedRepositoryValue(
            domain: "activity",
            name: "walkingSpeedToday",
            parameters: "\(Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970))"
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .walkingSpeed) else {
                throw HealthKitError.dataTypeNotAvailable
            }
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
            let unit = HKUnit.meter().unitDivided(by: HKUnit.second())

            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: type, predicate: predicate),
                options: .discreteAverage
            )
            let result = try await descriptor.result(for: healthStore)
            guard let avg = result?.averageQuantity() else {
                return nil
            }
            return avg.doubleValue(for: unit)
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchWalkingAsymmetryPercentage(on date: Date = Date()) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .walkingAsymmetryPercentage) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        guard let interval = dayInterval(for: date) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let unit = HKUnit.percent()

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        let result = try await descriptor.result(for: healthStore)
        guard let avg = result?.averageQuantity() else {
            return nil
        }
        return avg.doubleValue(for: unit)
    }

    /// 读取指定日期内的步态不对称原始样本，保留 HealthKit 的真实采样时间。
    func fetchWalkingAsymmetrySamples(on date: Date = Date()) async throws -> [TimeSeriesPointDouble] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .walkingAsymmetryPercentage) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        guard let interval = dayInterval(for: date) else { return [] }

        let end = Calendar.current.isDateInToday(date) ? min(Date(), interval.end) : interval.end
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: end,
            options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples = try await fetchQuantitySamples(type: type, predicate: predicate, sort: [sort])
        let unit = HKUnit.percent()

        logHealthKitRead(
            metric: "walkingAsymmetryPercentage.samples",
            status: samples.isEmpty ? .noData : .dataAvailable
        )

        return samples.compactMap { sample in
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite, value >= 0 else { return nil }
            return TimeSeriesPointDouble(
                timestamp: Int64(sample.startDate.timeIntervalSince1970),
                value: value
            )
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchWalkingStepLength(on date: Date = Date()) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .walkingStepLength) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        guard let interval = dayInterval(for: date) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let unit = HKUnit.meter()

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        let result = try await descriptor.result(for: healthStore)
        guard let avg = result?.averageQuantity() else {
            return nil
        }
        return avg.doubleValue(for: unit)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchWalkingDoubleSupportPercentage(on date: Date = Date()) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .walkingDoubleSupportPercentage) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        guard let interval = dayInterval(for: date) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let unit = HKUnit.percent()

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        let result = try await descriptor.result(for: healthStore)
        guard let avg = result?.averageQuantity() else {
            return nil
        }
        return avg.doubleValue(for: unit)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchWalkingSteadiness(on date: Date = Date()) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleWalkingSteadiness) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        guard let interval = dayInterval(for: date) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let unit = HKUnit.percent()

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        let result = try await descriptor.result(for: healthStore)
        guard let avg = result?.averageQuantity() else {
            return nil
        }
        return avg.doubleValue(for: unit)
    }

    // MARK: 活动每日序列

    func fetchDailyWalkingSpeedAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .walkingSpeed, unit: HKUnit.meter().unitDivided(by: HKUnit.second()), options: .discreteAverage, days: days)
    }

    func fetchDailyWalkingSpeedAverages(days: Int = 30, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .walkingSpeed, unit: HKUnit.meter().unitDivided(by: HKUnit.second()), options: .discreteAverage, days: days, endDate: endDate)
    }

    func fetchDailyWalkingAsymmetryAverages(days: Int = 7) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyWalkingAsymmetryAverages(days: days, endDate: Date())
    }

    func fetchDailyWalkingAsymmetryAverages(days: Int = 7, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .walkingAsymmetryPercentage, unit: .percent(), options: .discreteAverage, days: days, endDate: endDate)
    }

    func fetchDailyWalkingStepLengthAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .walkingStepLength, unit: .meter(), options: .discreteAverage, days: days)
    }

    func fetchDailyWalkingDoubleSupportAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .walkingDoubleSupportPercentage, unit: .percent(), options: .discreteAverage, days: days)
    }

    func fetchDailyStairAscentSpeedAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .stairAscentSpeed, unit: HKUnit.meter().unitDivided(by: HKUnit.second()), options: .discreteAverage, days: days)
    }

    func fetchDailyStairDescentSpeedAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .stairDescentSpeed, unit: HKUnit.meter().unitDivided(by: HKUnit.second()), options: .discreteAverage, days: days)
    }

    func fetchDailyWalkingSteadinessAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .appleWalkingSteadiness, unit: .percent(), options: .discreteAverage, days: days)
    }

    func fetchDailyStepSums(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .stepCount, unit: .count(), options: .cumulativeSum, days: days)
    }

    /// 方法说明：负责按指定结束日期读取步数日汇总，便于历史日回看与日级趋势对齐。
    func fetchDailyStepSums(days: Int = 30, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .stepCount, unit: .count(), options: .cumulativeSum, days: days, endDate: endDate)
    }

    func fetchDailyDistanceWalkingRunningSums(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .distanceWalkingRunning, unit: .meter(), options: .cumulativeSum, days: days)
    }

    func fetchDailyFlightsClimbedSums(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .flightsClimbed, unit: .count(), options: .cumulativeSum, days: days)
    }

    func fetchDailyActiveEnergySums(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, days: days)
    }

    /// 方法说明：读取最近几天写入健康 App 的饮水日总量。
    func fetchDailyDietaryWaterSums(days: Int = 30, endDate: Date = Date()) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .dietaryWater, unit: HKUnit.literUnit(with: .milli), options: .cumulativeSum, days: days, endDate: endDate)
    }

    /// 方法说明：读取最近几天写入健康 App 的咖啡因日总量。
    func fetchDailyDietaryCaffeineSums(days: Int = 30, endDate: Date = Date()) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .dietaryCaffeine, unit: .gramUnit(with: .milli), options: .cumulativeSum, days: days, endDate: endDate)
    }

    func fetchDailyActiveEnergySums(days: Int = 30, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, days: days, endDate: endDate)
    }

    func fetchDailyBasalEnergySums(days: Int = 30, endDate: Date = Date()) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .basalEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, days: days, endDate: endDate)
    }

    func fetchDailyExerciseTimeSums(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .appleExerciseTime, unit: .minute(), options: .cumulativeSum, days: days)
    }

    func fetchDailyExerciseTimeSums(days: Int = 30, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .appleExerciseTime, unit: .minute(), options: .cumulativeSum, days: days, endDate: endDate)
    }

    func fetchDailyStandHours(days: Int = 30, endDate: Date = Date()) async throws -> [TimeSeriesPointDouble] {
        let calendar = Calendar.current
        let normalizedEnd = calendar.startOfDay(for: endDate)
        let key = HealthKitRepositoryCacheKey(
            domain: "activity",
            name: "dailyStandHours",
            parameters: "\(Int64(normalizedEnd.timeIntervalSince1970)).\(max(days, 1))"
        )
        if let cached: [TimeSeriesPointDouble] = HealthKitRepositoryCache.shared.value(for: key) {
            return cached
        }

        guard let startDate = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: normalizedEnd) else {
            return []
        }

        var points: [TimeSeriesPointDouble] = []
        for offset in 0..<max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let count = try await fetchStandHoursOptional(on: day) ?? 0
            let normalized = calendar.startOfDay(for: day)
            points.append(TimeSeriesPointDouble(timestamp: Int64(normalized.timeIntervalSince1970), value: Double(count)))
        }
        HealthKitRepositoryCache.shared.store(points, for: key)
        return points
    }
}
