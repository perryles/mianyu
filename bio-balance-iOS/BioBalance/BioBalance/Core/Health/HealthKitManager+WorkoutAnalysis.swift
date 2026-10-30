import Foundation
import HealthKit
import CoreLocation

// MARK: - 训练深度分析读取
//
// 负责把一次 HKWorkout 关联的原始样本（GPS 路线、心率、海拔爬升）读出来，
// 交给 WorkoutAnalysisComputation 做本机计算。只读内存，不落盘、不上云。

extension HealthKitManager {

    /// 读取指定日期区间内训练会话的轻量引用（id + 起止时间 + 标题），供详情页选择分析对象。
    func fetchWorkoutSessionReferences(
        startDate: Date,
        endDate: Date
    ) async throws -> [WorkoutSessionReference] {
        try await fetchWorkoutSessionSummaries(startDate: startDate, endDate: endDate)
            .map { session in
                WorkoutSessionReference(
                    id: session.id,
                    startDate: session.startDate,
                    endDate: session.endDate,
                    activityTitle: session.activityTitle,
                    durationMinutes: session.durationMinutes
                )
            }
    }

    /// 单次训练深度分析：路线海拔曲线 + 最高海拔 + 累计爬升 + 分段（优先按公里，缺距离则按 5 分钟）。
    ///
    /// 数据可得性：
    /// - 海拔曲线：优先 GPS 路线定位高度（户外训练由系统写入）；无路线时回退
    ///   workout/distance 样本 metadata 里的 `HKMetadataKeyElevationAscended` 累积曲线；
    ///   两者都缺失则海拔维度整体降级为空。
    /// - 累计爬升：优先用海拔轨迹滞回法计算；轨迹缺失时回退 metadata 记录值。
    /// - 分段：有距离轨迹（样本或路线）按 1 km 切分并给配速；无距离但时长足够按 5 分钟切分。
    /// - 心率：训练关联样本按时间窗口聚合到分段。
    func fetchWorkoutAnalysisReport(for reference: WorkoutSessionReference) async throws -> WorkoutAnalysisReport? {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        let workout = try await workout(matching: reference.id)
        let workoutPredicate = HKQuery.predicateForObjects(from: workout)

        let distanceTrackSamples = try await cumulativeDistanceSamples(
            for: workout,
            predicate: workoutPredicate
        )

        let routeLocations = await fetchRouteLocations(for: workout)
        logHealthKitRead(
            metric: "workout.analysisRoute",
            status: routeLocations.isEmpty ? .noData : .dataAvailable
        )

        let heartRateSamples = (try? await fetchQuantitySamples(
            type: Self.requiredQuantityType(.heartRate),
            predicate: workoutPredicate,
            sort: [Self.startAscendingSort]
        )) ?? []

        let duration = workout.duration
        let startedAt = workout.startDate
        let totalDistance = Self.totalDistanceQuantity(for: workout)?
            .doubleValue(for: .meterUnit(with: .kilo))

        // 海拔：路线定位高度优先（以起点为基准，只表现相对起伏）；无路线时回退 metadata 爬升。
        var elevationTrack: [(offset: TimeInterval, meters: Double)] = []
        var recordedAscent: Double?
        if let first = routeLocations.first {
            let baseAltitude = first.altitude
            elevationTrack = routeLocations.map { location in
                (location.timestamp.timeIntervalSince(startedAt), location.altitude - baseAltitude)
            }
        } else {
            elevationTrack = Self.cumulativeElevationFromMetadata(
                workout: workout,
                distanceSamples: distanceTrackSamples,
                startedAt: startedAt
            )
            if !elevationTrack.isEmpty {
                recordedAscent = elevationTrack.last?.meters
            }
        }

        // 距离轨迹：距离样本优先；没有样本但有路线时，用相邻定位点水平距离累积补齐。
        let distanceTrack = !distanceTrackSamples.isEmpty
            ? Self.cumulativeDistanceTrack(from: distanceTrackSamples)
            : Self.cumulativeDistanceTrack(from: routeLocations)

        return WorkoutAnalysisComputation.buildReport(
            workoutID: workout.uuid,
            startedAt: startedAt,
            duration: duration,
            totalDistanceKilometers: totalDistance,
            distanceTrack: distanceTrack,
            heartRateTrack: heartRateSamples.map { sample in
                (sample.startDate.timeIntervalSince(startedAt),
                 sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
            },
            elevationTrack: elevationTrack,
            recordedAscentMeters: recordedAscent
        )
    }

    /// Reads heart-rate samples linked to this exact swimming workout; no device-wide time-range query.
    func fetchSwimmingWorkoutAnalysis(for workoutID: UUID) async throws -> SwimmingWorkoutAnalysis? {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        let workout = try await workout(matching: workoutID)
        guard workout.workoutActivityType == .swimming else { return nil }

        let samples = try await fetchQuantitySamples(
            type: Self.requiredQuantityType(.heartRate),
            predicate: HKQuery.predicateForObjects(from: workout),
            sort: [Self.startAscendingSort]
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        let wallClockDuration = workout.endDate.timeIntervalSince(workout.startDate)
        let validSamples = samples.compactMap { sample -> (offset: TimeInterval, bpm: Double)? in
            let bpm = sample.quantity.doubleValue(for: unit)
            let offset = sample.startDate.timeIntervalSince(workout.startDate)
            guard bpm.isFinite, bpm > 0, offset.isFinite,
                  offset >= 0, offset <= wallClockDuration else { return nil }
            return (offset, bpm)
        }

        let allValues = validSamples.map(\.bpm)
        let chartSamples = Self.downsampleHeartRate(validSamples, maximumCount: 180)
        return SwimmingWorkoutAnalysis(
            workoutID: workout.uuid,
            averageHeartRate: allValues.isEmpty ? nil : allValues.reduce(0, +) / Double(allValues.count),
            peakHeartRate: allValues.max(),
            heartRateSamples: chartSamples.enumerated().map { index, sample in
                SwimmingHeartRateSample(index: index, offset: sample.offset, beatsPerMinute: sample.bpm)
            }
        )
    }

    /// Reads the swim ranking inside its calendar month plus same-year totals.
    ///
    /// Data minimization: only workout-level type, start date and total-distance statistics are read;
    /// per-lap samples, heart rate and routes are deliberately not queried for this ranking card.
    func fetchSwimmingWorkoutHistorySummary(for workoutID: UUID) async throws -> SwimmingWorkoutHistorySummary? {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        let workout = try await workout(matching: workoutID)
        guard workout.workoutActivityType == .swimming else { return nil }

        let calendar = Calendar.current
        let year = calendar.component(.year, from: workout.startDate)
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let nextYearStart = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: yearStart,
            end: nextYearStart,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        let swims = try await descriptor.result(for: healthStore)
            .filter { $0.workoutActivityType == .swimming }
        logHealthKitRead(
            metric: "workout.swimmingHistory",
            status: swims.isEmpty ? .noData : .dataAvailable
        )

        let month = calendar.component(.month, from: workout.startDate)
        let monthRank = swims.filter { candidate in
            calendar.component(.year, from: candidate.startDate) == year &&
            calendar.component(.month, from: candidate.startDate) == month &&
            candidate.startDate <= workout.startDate
        }.count
        let yearlyDistanceMeters = swims.reduce(0) { partial, candidate in
            partial + (Self.totalDistanceQuantity(for: candidate)?.doubleValue(for: .meter()) ?? 0)
        }

        return SwimmingWorkoutHistorySummary(
            workoutID: workout.uuid,
            monthRank: monthRank,
            yearlyWorkoutCount: swims.count,
            yearlyDistanceMeters: yearlyDistanceMeters
        )
    }

    // MARK: 私有辅助方法

    static func downsampleHeartRate(
        _ samples: [(offset: TimeInterval, bpm: Double)],
        maximumCount: Int
    ) -> [(offset: TimeInterval, bpm: Double)] {
        guard maximumCount > 1, samples.count > maximumCount else { return samples }
        let lastIndex = samples.count - 1
        return (0..<maximumCount).map { index in
            let sourceIndex = Int((Double(index) * Double(lastIndex) / Double(maximumCount - 1)).rounded(.up))
            return samples[sourceIndex]
        }
    }

    private func workout(matching id: UUID) async throws -> HKWorkout {
        let predicate = HKQuery.predicateForObjects(with: [id])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 1
        )
        guard let workout = try await descriptor.result(for: healthStore).first else {
            throw HealthKitError.dataTypeNotAvailable
        }
        return workout
    }

    /// 按运动类型解析对应的距离样本类型；类型不可用时返回空。
    private func cumulativeDistanceSamples(
        for workout: HKWorkout,
        predicate: NSPredicate
    ) async throws -> [HKQuantitySample] {
        let identifier: HKQuantityTypeIdentifier
        switch workout.workoutActivityType {
        case .cycling: identifier = .distanceCycling
        case .swimming: identifier = .distanceSwimming
        case .rowing: identifier = .distanceRowing
        case .paddleSports: identifier = .distancePaddleSports
        case .crossCountrySkiing: identifier = .distanceCrossCountrySkiing
        case .downhillSkiing, .snowboarding: identifier = .distanceDownhillSnowSports
        case .skatingSports: identifier = .distanceSkatingSports
        case .wheelchairRunPace: identifier = .distanceWheelchair
        default: identifier = .distanceWalkingRunning
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }
        return try await fetchQuantitySamples(
            type: type,
            predicate: predicate,
            sort: [Self.startAscendingSort]
        )
    }

    /// 读取路线定位点：先用 HKSampleQueryDescriptor 找到该 workout 的 HKWorkoutRoute 样本，
    /// 再用 HKWorkoutRouteQueryDescriptor（iOS 15.4+）以异步序列读出全部定位点。
    private func fetchRouteLocations(for workout: HKWorkout) async -> [CLLocation] {
        do {
            let routeDescriptor = HKSampleQueryDescriptor(
                predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
                limit: 1
            )
            guard let route = try await routeDescriptor.result(for: healthStore).first else {
                return []
            }

            var locations: [CLLocation] = []
            var iterator = HKWorkoutRouteQueryDescriptor(route).results(for: healthStore).makeAsyncIterator()
            while let location = try await iterator.next() {
                locations.append(location)
            }
            return locations
        } catch {
            return []
        }
    }

    private static var startAscendingSort: NSSortDescriptor {
        NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
    }

    private static func requiredQuantityType(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            fatalError("HealthKit 保证存在的 QuantityType 不可用: \(identifier.rawValue)")
        }
        return type
    }

    /// 把逐条距离样本累积成 (offset, 累计公里) 轨迹，供分段边界定位。
    private static func cumulativeDistanceTrack(
        from samples: [HKQuantitySample]
    ) -> [(offset: TimeInterval, kilometers: Double)] {
        guard let startedAt = samples.first?.startDate else { return [] }
        let kilometer = HKUnit.meterUnit(with: .kilo)
        var accumulated = 0.0
        return samples.map { sample in
            accumulated += sample.quantity.doubleValue(for: kilometer)
            return (sample.startDate.timeIntervalSince(startedAt), accumulated)
        }
    }

    /// 路线定位点的相邻水平距离累积轨迹，作为距离样本缺失时的兜底。
    private static func cumulativeDistanceTrack(
        from locations: [CLLocation]
    ) -> [(offset: TimeInterval, kilometers: Double)] {
        guard locations.count >= 2, let startedAt = locations.first?.timestamp else { return [] }
        var accumulated = 0.0
        var previous: CLLocation?
        return locations.map { location in
            if let previous {
                accumulated += location.distance(from: previous)
            }
            previous = location
            return (location.timestamp.timeIntervalSince(startedAt), accumulated / 1000)
        }
    }

    /// 无 GPS 路线时从 metadata 提取累计爬升：workout 级 `HKMetadataKeyElevationAscended`
    /// 直接给总量；distance 样本逐条携带该键时按时间累积成爬升轨迹（室内跑/爬楼机常见）。
    private static func cumulativeElevationFromMetadata(
        workout: HKWorkout,
        distanceSamples: [HKQuantitySample],
        startedAt: Date
    ) -> [(offset: TimeInterval, meters: Double)] {
        let meter = HKUnit.meter()

        if let totalAscent = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
            let total = totalAscent.doubleValue(for: meter)
            guard total > 0 else { return [] }
            // 只有总量没有时间分布：两点线性轨迹仅供曲线展示，爬升总量以记录值结算。
            let duration = max(workout.duration, 1)
            return [
                (0, 0.0),
                (duration, total)
            ]
        }

        var accumulated = 0.0
        var track: [(offset: TimeInterval, meters: Double)] = []
        for sample in distanceSamples {
            guard let ascent = sample.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity else { continue }
            accumulated += ascent.doubleValue(for: meter)
            track.append((sample.startDate.timeIntervalSince(startedAt), accumulated))
        }
        return track
    }
}
