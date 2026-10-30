import Foundation
import HealthKit

// MARK: - Mindfulness, Audio Exposure, State of Mind & Mental Assessments

extension HealthKitManager {

    // MARK: 正念

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchMindfulnessMinutes(on date: Date = Date()) async throws -> Int {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "activity",
            name: "mindfulnessMinutes",
            parameters: parameters
        ) {
            guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
                throw HealthKitError.dataTypeNotAvailable
            }

            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: type, predicate: predicate)],
                sortDescriptors: [],
                limit: HKObjectQueryNoLimit
            )
            let samples = try await descriptor.result(for: healthStore)
            var totalMinutes = 0.0
            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                totalMinutes += duration / 60.0
            }
            return Int(totalMinutes)
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchTimeInDaylightMinutes(on date: Date = Date()) async throws -> Int? {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "wellness",
            name: "timeInDaylight",
            parameters: parameters
        ) {
            guard let interval = dayInterval(for: date) else {
                return nil
            }

            let points = try await fetchTimeInDaylightSeries(
                start: interval.start,
                end: interval.end,
                interval: DateComponents(day: 1)
            )
            let total = points.reduce(0) { $0 + $1.value }
            return points.isEmpty ? nil : Int(total.rounded())
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchTimeInDaylightSeries(start: Date, end: Date, interval: DateComponents) async throws -> [TimeSeriesPointDouble] {
        return try await fetchStatisticsCollection(
            quantityIdentifier: .timeInDaylight,
            unit: .minute(),
            options: .cumulativeSum,
            startDate: start,
            endDate: end,
            interval: interval
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func saveMindfulSession(start: Date, end: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession), end > start else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let sample = HKCategorySample(type: type, value: 0, start: start, end: end)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationFailed)
                }
            }
        }
    }

    // MARK: 心境状态

    /// State Of Mind Snapshot 结构体，作为内部辅助类型，用于配合外层健康数据读取与授权管理。
    struct StateOfMindSnapshot: Sendable {
        let title: String
        let detail: String
        let intensity: Int
        let date: Date
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestStateOfMind() async throws -> StateOfMindSnapshot? {
        try await fetchLatestStateOfMind(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestStateOfMind(on date: Date) async throws -> StateOfMindSnapshot? {
        guard HKHealthStore.isHealthDataAvailable() else {
            return nil
        }

        let type = HKObjectType.stateOfMindType()
        let predicate = dayInterval(for: date).map {
            HKQuery.predicateForSamples(withStart: $0.start, end: $0.end, options: .strictStartDate)
        }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "stateOfMind.latest",
            status: samples.isEmpty ? .noData : .dataAvailable
        )
        guard let sample = samples.first as? HKStateOfMind else {
            return nil
        }

        let title = stateOfMindTitle(for: sample.valence)
        let kindDescription = String(describing: sample.kind)
        let detail = kindDescription.contains("dailyMood") ? "来自健康 App 的每日心情" : "来自健康 App 的瞬时情绪"
        let intensity = Int(((sample.valence + 1.0) / 2.0 * 100.0).rounded())
        return StateOfMindSnapshot(title: title, detail: detail, intensity: intensity, date: sample.startDate)
    }

    func stateOfMindTitle(for valence: Double) -> String {
        switch valence {
        case ..<(-0.6): return "很难受"
        case ..<(-0.2): return "不舒服"
        case ..<0.2: return "平静"
        case ..<0.6: return "愉快"
        default: return "非常愉快"
        }
    }

    /// 方法说明：把健身详情页选择的当日心情写入健康 App（State of Mind 每日心情）。
    /// - replacingUUID 传入本 App 之前写入的样本时，先删旧再写新，保证一天只有一条本 App 的每日心情；
    /// - 返回新样本 UUID，供本地记录保存引用。
    @discardableResult
    func saveDailyMood(
        valence: Double,
        on date: Date,
        replacingUUID: UUID? = nil
    ) async throws -> UUID {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        if let replacingUUID {
            await deleteAppWrittenStateOfMind(uuid: replacingUUID)
        }

        // 每日心情样本落在当天：今天用当前时刻，补记历史日用当天中午，避免跨天。
        let calendar = Calendar.current
        let sampleDate = calendar.isDateInToday(date)
            ? Date()
            : calendar.startOfDay(for: date).addingTimeInterval(12 * 3600)

        let clamped = max(-1.0, min(1.0, valence))
        let sample = HKStateOfMind(
            date: sampleDate,
            kind: .dailyMood,
            valence: clamped,
            labels: [],
            associations: [.fitness]
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationFailed)
                }
            }
        }
        return sample.uuid
    }

    /// 方法说明：按 UUID 删除本 App 写入的心理状态样本；其他来源的记录不动。
    private func deleteAppWrittenStateOfMind(uuid: UUID) async {
        let type = HKObjectType.stateOfMindType()
        let predicate = HKQuery.predicateForObject(with: uuid)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: type, predicate: predicate)],
            sortDescriptors: [],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: healthStore).first,
              sample.sourceRevision.source.bundleIdentifier == HKSource.default().bundleIdentifier else {
            return
        }
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            healthStore.delete(sample) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: 音频暴露

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchEnvironmentalAudioExposure() async throws -> Double? {
        try await fetchEnvironmentalAudioExposure(on: Date())
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchEnvironmentalAudioExposure(on date: Date) async throws -> Double? {
        let parameters = "\(Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await cachedRepositoryValue(
            domain: "wellness",
            name: "environmentalAudio",
            parameters: parameters
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .environmentalAudioExposure) else {
                throw HealthKitError.dataTypeNotAvailable
            }

            guard let interval = dayInterval(for: date) else {
                return nil
            }
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)

            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: type, predicate: predicate),
                options: .discreteAverage
            )
            let result = try await descriptor.result(for: healthStore)
            logHealthKitRead(
                metric: "environmentalAudioExposure",
                status: result?.averageQuantity() == nil ? .noData : .dataAvailable
            )
            guard let avg = result?.averageQuantity() else {
                return nil
            }
            return avg.doubleValue(for: HKUnit.decibelAWeightedSoundPressureLevel())
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchHeadphoneAudioExposureToday() async throws -> Double? {
        try await cachedRepositoryValue(
            domain: "wellness",
            name: "headphoneAudioToday",
            parameters: "\(Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970))",
            ttl: HealthKitRepositoryCache.realtimeTTL
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else {
                throw HealthKitError.dataTypeNotAvailable
            }
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
            let unit = HKUnit.decibelAWeightedSoundPressureLevel()

            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: type, predicate: predicate),
                options: .discreteAverage
            )
            let result = try await descriptor.result(for: healthStore)
            logHealthKitRead(
                metric: "headphoneAudioExposure",
                status: result?.averageQuantity() == nil ? .noData : .dataAvailable
            )
            guard let avg = result?.averageQuantity() else {
                return nil
            }
            return avg.doubleValue(for: unit)
        }
    }

    // MARK: 心理评估

    func fetchLatestMentalAssessmentResult(for kind: MentalAssessmentKind) async throws -> MentalAssessmentResult? {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        switch kind {
        case .gad7:
            let type = HKScoredAssessmentType(.GAD7)
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.sample(type: type, predicate: nil)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            guard let sample = try await descriptor.result(for: healthStore).first as? HKGAD7Assessment else {
                return nil
            }
            return MentalAssessmentResult(
                kind: .gad7,
                recordedAt: sample.startDate,
                answers: sample.answers.map(\.rawValue),
                score: sample.score,
                source: .healthKit,
                syncedToHealthKitAt: sample.startDate
            )

        case .phq9:
            let type = HKScoredAssessmentType(.PHQ9)
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.sample(type: type, predicate: nil)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            guard let sample = try await descriptor.result(for: healthStore).first as? HKPHQ9Assessment else {
                return nil
            }
            return MentalAssessmentResult(
                kind: .phq9,
                recordedAt: sample.startDate,
                answers: sample.answers.map(\.rawValue),
                score: sample.score,
                source: .healthKit,
                syncedToHealthKitAt: sample.startDate
            )
        }
    }

    func saveMentalAssessmentResult(_ result: MentalAssessmentResult) async throws -> Date {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        switch result.kind {
        case .gad7:
            let type = HKScoredAssessmentType(.GAD7)
            guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
                throw HealthKitError.authorizationFailed
            }
            let answers = result.answers.compactMap { HKGAD7Assessment.Answer(rawValue: $0) }
            guard answers.count == 7 else {
                throw HealthKitError.dataFetchFailed
            }
            let sample = HKGAD7Assessment(date: result.recordedAt, answers: answers, metadata: [:])
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.save(sample) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HealthKitError.authorizationFailed)
                    }
                }
            }
            return result.recordedAt

        case .phq9:
            let type = HKScoredAssessmentType(.PHQ9)
            guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
                throw HealthKitError.authorizationFailed
            }
            let answers = result.answers.compactMap { HKPHQ9Assessment.Answer(rawValue: $0) }
            guard answers.count == 9 else {
                throw HealthKitError.dataFetchFailed
            }
            let sample = HKPHQ9Assessment(date: result.recordedAt, answers: answers, metadata: [:])
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.save(sample) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HealthKitError.authorizationFailed)
                    }
                }
            }
            return result.recordedAt
        }
    }

    // MARK: 健康每日序列

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyEnvironmentalAudioExposureAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .environmentalAudioExposure,
            unit: HKUnit.decibelAWeightedSoundPressureLevel(),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyHeadphoneAudioExposureAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .headphoneAudioExposure,
            unit: HKUnit.decibelAWeightedSoundPressureLevel(),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyHeadphoneAudioExposureDurations(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let calendar = Calendar.current
        let normalizedEnd = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: normalizedEnd),
              let endDate = calendar.date(byAdding: .day, value: 1, to: normalizedEnd) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        let samples = try await descriptor.result(for: healthStore)

        var durationByDay: [Date: Double] = [:]
        for sample in samples {
            let clippedStart = max(sample.startDate, startDate)
            let clippedEnd = min(sample.endDate, endDate)
            guard clippedEnd > clippedStart else { continue }

            var segmentStart = clippedStart
            while segmentStart < clippedEnd {
                let dayStart = calendar.startOfDay(for: segmentStart)
                guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                let segmentEnd = min(clippedEnd, nextDayStart)
                let durationMinutes = segmentEnd.timeIntervalSince(segmentStart) / 60.0
                durationByDay[dayStart, default: 0] += durationMinutes
                segmentStart = segmentEnd
            }
        }

        return durationByDay.map { day, value in
            TimeSeriesPointDouble(timestamp: Int64(day.timeIntervalSince1970), value: value)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchHourlyHeadphoneAudioExposureDurationsForToday() async throws -> [TimeSeriesPointDouble] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        guard endDate > startDate else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        let samples = try await descriptor.result(for: healthStore)

        var durationByHour: [Date: Double] = [:]
        for sample in samples {
            let clippedStart = max(sample.startDate, startDate)
            let clippedEnd = min(sample.endDate, endDate)
            guard clippedEnd > clippedStart else { continue }

            var segmentStart = clippedStart
            while segmentStart < clippedEnd {
                let hourStart = calendar.dateInterval(of: .hour, for: segmentStart)?.start ?? segmentStart
                guard let nextHourStart = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { break }
                let segmentEnd = min(clippedEnd, nextHourStart)
                let durationMinutes = segmentEnd.timeIntervalSince(segmentStart) / 60.0
                durationByHour[hourStart, default: 0] += durationMinutes
                segmentStart = segmentEnd
            }
        }

        return durationByHour.map { hour, value in
            TimeSeriesPointDouble(timestamp: Int64(hour.timeIntervalSince1970), value: value)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyDaylightDurationSums(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        return try await fetchDailyStatistics(
            quantityIdentifier: .timeInDaylight,
            unit: .minute(),
            options: .cumulativeSum,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyMindfulMinutes(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: end) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: calendar.date(byAdding: .day, value: 1, to: end),
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [],
            limit: HKObjectQueryNoLimit
        )
        let mindfulSamples = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "mindfulSession",
            status: mindfulSamples.isEmpty ? .noData : .dataAvailable
        )
        var grouped: [Date: Double] = [:]
        for sample in mindfulSamples {
            let day = calendar.startOfDay(for: sample.startDate)
            grouped[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60.0
        }

        return grouped.map { day, value in
            TimeSeriesPointDouble(timestamp: Int64(day.timeIntervalSince1970), value: value)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyStateOfMindAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        guard HKHealthStore.isHealthDataAvailable() else {
            return []
        }

        let type = HKObjectType.stateOfMindType()
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: end) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: calendar.date(byAdding: .day, value: 1, to: end),
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        let samples = try await descriptor.result(for: healthStore)

        var grouped: [Date: [Double]] = [:]
        for case let sample as HKStateOfMind in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            let value = ((sample.valence + 1.0) / 2.0 * 100.0)
            grouped[day, default: []].append(value)
        }

        return grouped.compactMap { day, values -> TimeSeriesPointDouble? in
            guard !values.isEmpty else { return nil }
            let average = values.reduce(0, +) / Double(values.count)
            return TimeSeriesPointDouble(timestamp: Int64(day.timeIntervalSince1970), value: average)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }
}
