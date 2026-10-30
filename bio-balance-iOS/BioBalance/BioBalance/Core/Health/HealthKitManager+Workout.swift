import Foundation
import HealthKit

// MARK: - VO2 Max, Workouts & Physical Effort

extension HealthKitManager {

    // MARK: 最大摄氧量

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestVo2Max() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        let unit = HKUnit(from: "ml/kg*min")
        return try await fetchLatestQuantityValue(type: type, unit: unit)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchVo2Max(on date: Date = Date()) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        guard let interval = dayInterval(for: date) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let unit = HKUnit(from: "ml/kg*min")

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        let result = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "vo2Max.latest",
            status: result?.averageQuantity() == nil ? .noData : .dataAvailable
        )
        guard let average = result?.averageQuantity() else {
            return nil
        }
        return average.doubleValue(for: unit)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchVo2MaxSamples(on date: Date = Date()) async throws -> [TimeSeriesPointDouble] {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "cardio",
            name: "vo2MaxSamples",
            parameters: parameters
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
                throw HealthKitError.dataTypeNotAvailable
            }
            guard let interval = dayInterval(for: date) else {
                return []
            }

            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
            let unit = HKUnit(from: "ml/kg*min")

            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
                limit: HKObjectQueryNoLimit
            )
            let samples = try await descriptor.result(for: healthStore)
            return samples.compactMap { sample in
                let value = sample.quantity.doubleValue(for: unit)
                guard value > 0 else { return nil }
                return TimeSeriesPointDouble(timestamp: Int64(sample.startDate.timeIntervalSince1970), value: value)
            }
        }
    }

    func fetchDailyVo2MaxAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .vo2Max, unit: HKUnit(from: "ml/kg*min"), options: .discreteAverage, days: days)
    }

    func fetchDailyVo2MaxAverages(days: Int = 30, endDate: Date) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(quantityIdentifier: .vo2Max, unit: HKUnit(from: "ml/kg*min"), options: .discreteAverage, days: days, endDate: endDate)
    }

    func fetchResolvedVo2MaxSnapshot(on date: Date = Date()) async throws -> Vo2MaxSnapshot? {
        guard let assessment = await VO2MaxEngine.shared.assess(on: date) else { return nil }
        return Vo2MaxSnapshot(
            value: assessment.value,
            isEstimated: assessment.source == .engineEstimated
        )
    }

    func fetchDailyResolvedVo2MaxAverages(days: Int = 30, endDate: Date = Date()) async throws -> [TimeSeriesPointDouble] {
        await VO2MaxEngine.shared
            .assessSeries(days: max(days, 1), endDate: endDate)
            .map {
                TimeSeriesPointDouble(
                    timestamp: Int64($0.date.timeIntervalSince1970),
                    value: $0.value
                )
            }
    }

    func fetchBodyProfile() async -> VO2MaxBodyProfile {
        async let age = fetchChronologicalAge()
        async let sex = fetchBiologicalSexDisplayText()
        async let height = fetchLatestHeightCm()
        async let weight = fetchLatestBodyMassKg()

        return VO2MaxBodyProfile(
            age: await age,
            sex: await sex,
            heightCm: await height,
            weightKg: await weight
        )
    }

    // MARK: 训练

    func fetchRunningWorkouts(start: Date, end: Date) async throws -> [VO2MaxWorkoutSample] {
        try await fetchVO2RelevantWorkouts(start: start, end: end, activityTypes: [.running])
    }

    func fetchOutdoorWalkingWorkouts(start: Date, end: Date) async throws -> [VO2MaxWorkoutSample] {
        try await fetchVO2RelevantWorkouts(start: start, end: end, activityTypes: [.walking, .hiking])
    }

    func fetchWorkoutHeartRateSummary(for workout: HKWorkout) async throws -> (average: Double?, peak: Double?, end: Double?) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        // 官方推荐用 predicateForObjects(from:) 精确取该次训练关联的心率样本，
        // 避免同时段其他来源的心率混入。
        let workoutPredicate = HKQuery.predicateForObjects(from: workout)
        var samples = try await fetchQuantitySamples(type: heartRateType, predicate: workoutPredicate, sort: sort)
        if samples.isEmpty {
            // 第三方 App 写入的 workout 可能没有关联样本，回退到时间范围查询。
            let rangePredicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
            samples = try await fetchQuantitySamples(type: heartRateType, predicate: rangePredicate, sort: sort)
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: unit) }.filter { $0 > 0 }
        guard !values.isEmpty else {
            return (nil, nil, nil)
        }
        let average = values.reduce(0, +) / Double(values.count)
        let peak = values.max()
        let end = values.last
        return (average, peak, end)
    }

    func fetchHeartRateRecovery(for workout: HKWorkout) async throws -> (oneMinute: Double?, twoMinute: Double?) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let end = workout.endDate
        let twoMinuteEnd = end.addingTimeInterval(2 * 60)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let postPredicate = HKQuery.predicateForSamples(withStart: end, end: twoMinuteEnd, options: .strictStartDate)
        let postSamples = try await fetchQuantitySamples(type: heartRateType, predicate: postPredicate, sort: sort)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let postValues = postSamples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }.filter { $0.1 > 0 }

        let summary = try await fetchWorkoutHeartRateSummary(for: workout)
        guard let endHeartRate = summary.end ?? summary.peak else {
            return (nil, nil)
        }

        let oneMinuteTarget = end.addingTimeInterval(60)
        let twoMinuteTarget = end.addingTimeInterval(120)
        let oneMinuteHeartRate = postValues.min { abs($0.0.timeIntervalSince(oneMinuteTarget)) < abs($1.0.timeIntervalSince(oneMinuteTarget)) }?.1
        let twoMinuteHeartRate = postValues.min { abs($0.0.timeIntervalSince(twoMinuteTarget)) < abs($1.0.timeIntervalSince(twoMinuteTarget)) }?.1

        let oneMinute = oneMinuteHeartRate.map { max(0, endHeartRate - $0) }
        let twoMinute = twoMinuteHeartRate.map { max(0, endHeartRate - $0) }
        return (oneMinute, twoMinute)
    }

    func fetchDailyStrengthTrainingMinutes(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: anchorDate) else {
            return []
        }

        // 谓词下推：用 predicateForWorkouts(with:) 让 HealthKit 直接筛选力量训练，
        // 避免拉取全量 workout 后再在内存中过滤。
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining),
            HKQuery.predicateForWorkouts(with: .functionalStrengthTraining)
        ])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, typePredicate])

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        let workouts = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "workout.functionalStrength",
            status: workouts.isEmpty ? .noData : .dataAvailable
        )
        var grouped: [Date: Double] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            grouped[day, default: 0] += workout.duration / 60.0
        }
        return (0..<max(days, 1)).compactMap { offset -> TimeSeriesPointDouble? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            let normalized = calendar.startOfDay(for: day)
            return TimeSeriesPointDouble(timestamp: Int64(normalized.timeIntervalSince1970), value: grouped[normalized] ?? 0)
        }
    }

    /// 按真实起止时间读取逐次训练，供日内图表和训练时间线使用。
    func fetchWorkoutSessionSummaries(
        startDate: Date,
        endDate: Date,
        activityTypes: Set<HKWorkoutActivityType>? = nil
    ) async throws -> [WorkoutSessionSummary] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }
        guard endDate > startDate else { return [] }
        try Task.checkCancellation()

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        let workouts = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "workout.sessionSummaries",
            status: workouts.isEmpty ? .noData : .dataAvailable
        )
        var sessions: [WorkoutSessionSummary] = []
        for workout in workouts {
            guard Self.isFitnessWorkoutActivity(workout.workoutActivityType) else {
                continue
            }
            if let activityTypes, !activityTypes.contains(workout.workoutActivityType) {
                continue
            }
            let swimmingReport = try await swimmingReport(for: workout)
            sessions.append(WorkoutSessionSummary(
                id: workout.uuid,
                startDate: workout.startDate,
                endDate: workout.endDate,
                activityTitle: Self.workoutActivityTitle(for: workout),
                durationMinutes: workout.duration / 60.0,
                activeEnergyKilocalories: Self.activeEnergyBurnedQuantity(for: workout)?.doubleValue(for: .kilocalorie()),
                distanceKilometers: Self.totalDistanceQuantity(for: workout)?.doubleValue(for: .meterUnit(with: .kilo)),
                swimmingReport: swimmingReport,
                zoneSummaries: Self.zoneSummaries(for: workout)
            ))
        }
        try Task.checkCancellation()
        return sessions
    }

    /// `mindAndBody` 常被睡眠/冥想类 App 用作延长后台运行的会话，并不代表用户完成了训练。
    /// 健身复盘统一在数据入口排除它，避免睡眠时段被计入训练时长、负荷和消耗。
    nonisolated static func isFitnessWorkoutActivity(_ type: HKWorkoutActivityType) -> Bool {
        type != .mindAndBody
    }

    /// 使用 HealthKit 保存的原生训练区间，不重新扫描心率样本或在 App 内重复计算。
    /// iOS 18–26、未授权、未连接对应传感器或旧 workout 均自然降级为空数组。
    private static func zoneSummaries(for workout: HKWorkout) -> [WorkoutZoneSummary] {
        // Xcode 27 beta 尚未在项目所编译的 arm64 HealthKit 模块中导出
        // HKWorkout.zoneGroup(for:)。在 SDK 完整提供该 overlay 前保持旧系统的降级行为。
        []
    }

    private func swimmingReport(for workout: HKWorkout) async throws -> SwimmingWorkoutReport? {
        guard workout.workoutActivityType == .swimming else { return nil }
        let hasLapEvents = (workout.workoutEvents ?? []).contains { $0.type == .lap }
        guard hasLapEvents,
              let strokeType = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount) else {
            return Self.swimmingReport(for: workout, strokeSamples: [])
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let strokeSamples = try await fetchQuantitySamples(
            type: strokeType,
            predicate: HKQuery.predicateForObjects(from: workout),
            sort: [sort]
        )
        return Self.swimmingReport(for: workout, strokeSamples: strokeSamples)
    }

    private static func swimmingReport(
        for workout: HKWorkout,
        strokeSamples: [HKQuantitySample]
    ) -> SwimmingWorkoutReport? {
        guard workout.workoutActivityType == .swimming else { return nil }

        let location: SwimmingLocation
        let locationRaw = (workout.metadata?[HKMetadataKeySwimmingLocationType] as? NSNumber)?.intValue
        switch locationRaw {
        case HKWorkoutSwimmingLocationType.pool.rawValue: location = .pool
        case HKWorkoutSwimmingLocationType.openWater.rawValue: location = .openWater
        default: location = .unknown
        }

        let rawPoolLength = (workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity)?
            .doubleValue(for: .meter())
        let poolLength = location == .pool
            ? rawPoolLength.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            : nil
        let distanceMeters = totalDistanceQuantity(for: workout)?.doubleValue(for: .meter())
        let activeEnergyKilocalories: Double? = {
            guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
                  let energy = workout.statistics(for: energyType)?.sumQuantity() else { return nil }
            return energy.doubleValue(for: .kilocalorie())
        }()
        let healthKitSWOLFScore = (workout.metadata?[HKMetadataKeySWOLFScore] as? NSNumber)?.intValue
        let strokeCount: Int?
        if let strokeType = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount),
           let sum = workout.statistics(for: strokeType)?.sumQuantity() {
            let value = sum.doubleValue(for: .count())
            strokeCount = value.isFinite && value > 0 ? Int(value.rounded()) : nil
        } else {
            strokeCount = nil
        }

        let lapEvents = (workout.workoutEvents ?? [])
            .filter { $0.type == .lap }
            .sorted { $0.dateInterval.start < $1.dateInterval.start }
        let strokeCounts = swimmingStrokeCounts(
            for: lapEvents.map(\.dateInterval),
            in: strokeSamples
        )
        let laps = lapEvents.enumerated().map { offset, event in
            SwimmingLapReport(
                index: offset + 1,
                duration: max(0, event.dateInterval.duration),
                distanceMeters: poolLength,
                stroke: swimmingStroke(from: event.metadata?[HKMetadataKeySwimmingStrokeStyle]),
                strokeCount: offset < strokeCounts.count ? strokeCounts[offset] : nil
            )
        }

        return SwimmingWorkoutReport(
            workoutID: workout.uuid,
            startDate: workout.startDate,
            endDate: workout.endDate,
            deviceName: workout.device?.name,
            duration: workout.duration,
            location: location,
            poolLengthMeters: poolLength,
            distanceMeters: distanceMeters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            strokeCount: strokeCount,
            activeEnergyKilocalories: activeEnergyKilocalories.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            healthKitSWOLFScore: healthKitSWOLFScore.flatMap { $0 > 0 ? $0 : nil },
            laps: laps
        )
    }

    /// Assigns measured stroke-count samples to exact lap intervals. A sample that crosses a lap
    /// boundary is intentionally left unassigned instead of being split by an estimate.
    nonisolated static func swimmingStrokeCounts(
        for lapIntervals: [DateInterval],
        in samples: [HKQuantitySample]
    ) -> [Int?] {
        lapIntervals.map { lapInterval in
            var countedValue = 0.0
            var hasMeasuredSample = false
            for sample in samples {
                let intersectionStart = max(lapInterval.start, sample.startDate)
                let intersectionEnd = min(lapInterval.end, sample.endDate)
                guard intersectionStart < intersectionEnd else { continue }

                // A sample overlapping two laps cannot be attributed exactly to either lap.
                guard sample.startDate >= lapInterval.start, sample.endDate <= lapInterval.end else {
                    return nil
                }
                let value = sample.quantity.doubleValue(for: .count())
                guard value.isFinite, value >= 0, value < Double(Int.max) else {
                    return nil
                }
                countedValue += value
                hasMeasuredSample = true
                guard countedValue.isFinite, countedValue >= 0, countedValue < Double(Int.max) else {
                    return nil
                }
            }
            guard hasMeasuredSample else { return nil }
            return Int(countedValue.rounded())
        }
    }

    private static func swimmingStroke(from metadataValue: Any?) -> SwimmingStroke {
        guard let rawValue = (metadataValue as? NSNumber)?.intValue,
              let style = HKSwimmingStrokeStyle(rawValue: rawValue) else {
            return .unknown
        }
        switch style {
        case .mixed: return .mixed
        case .freestyle: return .freestyle
        case .backstroke: return .backstroke
        case .breaststroke: return .breaststroke
        case .butterfly: return .butterfly
        case .kickboard: return .kickboard
        default: return .unknown
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchWorkoutDaySummaries(
        startDate: Date,
        endDate: Date,
        activityTypes: Set<HKWorkoutActivityType>? = nil
    ) async throws -> [WorkoutDaySummary] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        guard let normalizedEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) else {
            return []
        }

        let sessions = try await fetchWorkoutSessionSummaries(
            startDate: normalizedStart,
            endDate: normalizedEnd,
            activityTypes: activityTypes
        )
        var groupedMinutes: [Date: Double] = [:]
        var groupedEnergy: [Date: Double] = [:]
        var groupedDistance: [Date: Double] = [:]
        var groupedEnergyMeasurementCount: [Date: Int] = [:]
        var groupedDistanceMeasurementCount: [Date: Int] = [:]
        var groupedCount: [Date: Int] = [:]
        var groupedTypes: [Date: [String: Double]] = [:]
        var groupedSwimmingReports: [Date: SwimmingWorkoutReport] = [:]

        for session in sessions {
            // 跨午夜训练按自然日切分，时长/能量/距离按占比分摊到各天，
            // 与活动环“样本落在哪天算哪天”的口径保持一致。
            let totalDuration = session.endDate.timeIntervalSince(session.startDate)
            guard totalDuration > 0 else { continue }

            var segmentStart = session.startDate
            while segmentStart < session.endDate {
                let day = calendar.startOfDay(for: segmentStart)
                let nextDayStart = calendar.date(byAdding: .day, value: 1, to: day) ?? session.endDate
                let segmentEnd = min(nextDayStart, session.endDate)
                let fraction = segmentEnd.timeIntervalSince(segmentStart) / totalDuration
                let segmentMinutes = session.durationMinutes * fraction

                groupedMinutes[day, default: 0] += segmentMinutes
                groupedCount[day, default: 0] += 1
                if let energy = session.activeEnergyKilocalories, energy.isFinite, energy >= 0 {
                    groupedEnergy[day, default: 0] += energy * fraction
                    groupedEnergyMeasurementCount[day, default: 0] += 1
                }
                if let distance = session.distanceKilometers, distance.isFinite, distance >= 0 {
                    groupedDistance[day, default: 0] += distance * fraction
                    groupedDistanceMeasurementCount[day, default: 0] += 1
                }
                groupedTypes[day, default: [:]][session.activityTitle, default: 0] += segmentMinutes
                if let report = session.swimmingReport,
                   groupedSwimmingReports[day].map({ $0.duration < report.duration }) ?? true {
                    groupedSwimmingReports[day] = report
                }
                segmentStart = segmentEnd
            }
        }

        let summaries = groupedMinutes.keys.sorted().map { day in
            let workoutCount = groupedCount[day] ?? 0
            let energyMeasuredCount = groupedEnergyMeasurementCount[day] ?? 0
            let distanceMeasuredCount = groupedDistanceMeasurementCount[day] ?? 0
            // 有测量值就累加展示，缺测量的手动记录不再让整天数据消失；
            // 部分缺测时用 hasPartial* 标记提示口径不完整。
            let dominantTitle = groupedTypes[day]?.max(by: { $0.value < $1.value })?.key
            return WorkoutDaySummary(
                date: day,
                totalMinutes: Int((groupedMinutes[day] ?? 0).rounded()),
                totalEnergyKilocalories: energyMeasuredCount > 0
                    ? groupedEnergy[day].map { Int($0.rounded()) }
                    : nil,
                totalDistanceKilometers: distanceMeasuredCount > 0
                    ? groupedDistance[day]
                    : nil,
                dominantWorkoutTitle: dominantTitle,
                durationMinutesByWorkoutTitle: groupedTypes[day] ?? [:],
                workoutCount: workoutCount,
                swimmingReport: dominantTitle == Self.workoutActivityTitle(for: .swimming)
                    ? groupedSwimmingReports[day]
                    : nil,
                hasPartialEnergyData: energyMeasuredCount > 0 && energyMeasuredCount < workoutCount,
                hasPartialDistanceData: distanceMeasuredCount > 0 && distanceMeasuredCount < workoutCount
            )
        }

        return summaries
    }

    func fetchLatestWorkoutContext(lookbackHours: Int = 12) async throws -> LatestWorkoutContext? {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        let end = Date()
        let start = end.addingTimeInterval(-Double(max(lookbackHours, 1)) * 60.0 * 60.0)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 20
        )
        let workouts = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "workout.latest",
            status: workouts.isEmpty ? .noData : .dataAvailable
        )
        guard let workout = workouts.first(where: {
            Self.isFitnessWorkoutActivity($0.workoutActivityType)
        }) else {
            return nil
        }
        let now = Date()
        let isActive = workout.endDate >= now.addingTimeInterval(-90)
        return LatestWorkoutContext(
            isActive: isActive,
            activityType: workout.workoutActivityType,
            totalMinutes: Int((workout.duration / 60.0).rounded()),
            endedAt: workout.endDate
        )
    }

    func fetchPhysicalEffortSamples(startDate: Date, endDate: Date) async throws -> [HealthPhysicalEffortSample] {
        guard endDate > startDate,
              let type = HKQuantityType.quantityType(forIdentifier: .physicalEffort) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples = try await fetchQuantitySamples(type: type, predicate: predicate, sort: [sort])
        let unit = HKUnit.kilocalorie()
            .unitDivided(by: HKUnit.gramUnit(with: .kilo))
            .unitDivided(by: HKUnit.hour())
        return samples.compactMap { sample in
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite, value > 0, sample.endDate > sample.startDate else { return nil }
            return HealthPhysicalEffortSample(
                startDate: sample.startDate,
                endDate: sample.endDate,
                metabolicEquivalent: value
            )
        }
    }

    func fetchWorkoutEffortSamples(startDate: Date, endDate: Date) async throws -> [HealthWorkoutEffortSample] {
        guard endDate > startDate,
              let scoreType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore),
              let estimatedType = HKQuantityType.quantityType(forIdentifier: .estimatedWorkoutEffortScore) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let descriptor = HKWorkoutEffortRelationshipQueryDescriptor(
            predicate: predicate,
            anchor: nil,
            option: .mostRelevant
        )
        let result = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "workout.effort",
            status: result.relationships.isEmpty ? .noData : .dataAvailable
        )
        let unit = HKUnit.appleEffortScore()

        return result.relationships.compactMap { relationship in
            let samples = relationship.samples?.compactMap { $0 as? HKQuantitySample } ?? []
            let actual = samples.first { $0.quantityType == scoreType }
            let estimated = samples.first { $0.quantityType == estimatedType }
            guard let sample = actual ?? estimated else { return nil }
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite, value > 0 else { return nil }
            return HealthWorkoutEffortSample(
                workoutID: relationship.workout.uuid,
                endedAt: relationship.workout.endDate,
                durationMinutes: relationship.workout.duration / 60,
                score: value,
                isEstimated: actual == nil
            )
        }
        .sorted { $0.endedAt < $1.endedAt }
    }

    // MARK: 私有辅助方法

    func fetchVO2RelevantWorkouts(
        start: Date,
        end: Date,
        activityTypes: Set<HKWorkoutActivityType>
    ) async throws -> [VO2MaxWorkoutSample] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        let allWorkouts = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "workout.vo2Relevant",
            status: allWorkouts.isEmpty ? .noData : .dataAvailable
        )
        let workouts = allWorkouts.filter { activityTypes.contains($0.workoutActivityType) }

        var results: [VO2MaxWorkoutSample] = []
        results.reserveCapacity(workouts.count)

        for workout in workouts {
            let summary = try? await fetchWorkoutHeartRateSummary(for: workout)
            let recovery = try? await fetchHeartRateRecovery(for: workout)
            let distanceKilometers = Self.totalDistanceQuantity(for: workout)?.doubleValue(for: .meterUnit(with: .kilo))
            let paceSecondsPerKm: Double?
            if let distanceKilometers, distanceKilometers > 0 {
                paceSecondsPerKm = (workout.duration / 60.0) > 0 ? workout.duration / distanceKilometers : nil
            } else {
                paceSecondsPerKm = nil
            }

            results.append(
                VO2MaxWorkoutSample(
                    id: workout.uuid,
                    activityType: workout.workoutActivityType,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    durationMinutes: workout.duration / 60.0,
                    distanceKilometers: distanceKilometers,
                    averageHeartRate: summary?.average,
                    peakHeartRate: summary?.peak,
                    endHeartRate: summary?.end,
                    paceSecondsPerKilometer: paceSecondsPerKm,
                    heartRateRecoveryOneMinute: recovery?.oneMinute,
                    heartRateRecoveryTwoMinute: recovery?.twoMinute
                )
            )
        }

        return results
    }
}
