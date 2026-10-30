import Foundation
import HealthKit

/// 健康 Repository 派生数据的缓存键。
///
/// Repository 只负责键设计、失效时机、数据转换和刷新策略；
/// 这里不复制 AppDataCacheManager 的展示/清理能力，而是把持久化入口收敛为
/// 一个可由 Cache Architecture 挂进现有缓存管理分类的稳定存储键。
nonisolated struct HealthKitRepositoryCacheKey: Hashable, Sendable {
    let domain: String
    let name: String
    let parameters: String
    let algorithmVersion: String?

    init(
        domain: String,
        name: String,
        parameters: String,
        algorithmVersion: String? = nil
    ) {
        self.domain = domain
        self.name = name
        self.parameters = parameters
        self.algorithmVersion = algorithmVersion
    }

    var storageKey: String {
        "\(domain)|\(name)|\(parameters)|\(algorithmVersion ?? "")"
    }
}

/// HealthKit Repository 本地派生缓存。
///
/// 只缓存由 HealthKit 原始样本转换后的日级摘要、最近值或算法输入，不缓存
/// 原始 `HKQuantitySample`、RR 间期、ECG 电压等明细。失效复用现有
/// `HKObserverQuery` 与授权协调流程：观察者回调按 HealthKit 类型所属域置脏，
/// 权限变化走 `invalidateAll()`，下一次读取自然回退到 HealthKit。
nonisolated final class HealthKitRepositoryCache: @unchecked Sendable {
    nonisolated static let shared = HealthKitRepositoryCache()

    /// AppDataCacheManager 需要把该键加入 localPageSnapshots 的清理/统计清单。
    nonisolated static let storageKey = "health.repository.cache.v1"

    nonisolated static let defaultTTL: TimeInterval = 15 * 60
    nonisolated static let realtimeTTL: TimeInterval = 5 * 60
    nonisolated static let algorithmTTL: TimeInterval = 30 * 60

    nonisolated private static let globalEpochKey = "health.repository.globalEpoch.v1"
    nonisolated private static let domainEpochsKey = "health.repository.domainEpochs.v1"

    private let lock = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 缓存命中优先；forceRefresh、TTL、算法版本或失效 epoch 不满足时返回 nil。
    func value<Value: Codable>(
        for key: HealthKitRepositoryCacheKey,
        ttl: TimeInterval = HealthKitRepositoryCache.defaultTTL,
        forceRefresh: Bool = false,
        now: Date = Date()
    ) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard !forceRefresh,
              let envelope = entries()[key.storageKey],
              envelope.savedEpoch == currentEpoch(for: key.domain),
              matchesAlgorithmVersion(key.algorithmVersion, envelope.algorithmVersion),
              now.timeIntervalSince(envelope.fetchedAt) < ttl,
              let valueData = try? JSONDecoder().decode(
                  HealthKitRepositoryValue<Value>.self,
                  from: envelope.valueData
              ) else {
            return nil
        }
        return valueData.value
    }

    /// 写入转换后的派生值，并把当前失效 epoch 一并落盘。
    func store<Value: Codable>(
        _ value: Value,
        for key: HealthKitRepositoryCacheKey,
        algorithmVersion: String? = nil,
        now: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard let valueData = try? JSONEncoder().encode(
            HealthKitRepositoryValue(value: value)
        ) else {
            return
        }
        var entries = entries()
        entries[key.storageKey] = CacheEnvelope(
            valueData: valueData,
            fetchedAt: now,
            savedEpoch: currentEpoch(for: key.domain),
            algorithmVersion: algorithmVersion
        )
        save(entries)
    }

    /// 按 HealthKit 数据域失效。观察者回调只失效实际发生变化的域，避免全量重刷。
    func invalidate(domains: Set<String>) {
        guard !domains.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var epochs = domainEpochs()
        for domain in domains {
            epochs[domain, default: 0] += 1
        }
        if let data = try? JSONEncoder().encode(epochs) {
            defaults.set(data, forKey: Self.domainEpochsKey)
        }
    }

    /// 全局失效：权限变化、强制同步或清理时使用，任何旧派生值都不再命中。
    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        let epoch = (defaults.object(forKey: Self.globalEpochKey) as? NSNumber)?.intValue ?? 0
        defaults.set(epoch + 1, forKey: Self.globalEpochKey)
    }

    /// 清空持久化缓存与 epoch。AppDataCacheManager 清理页面缓存时由
    /// HealthDataManager.clearLocalCaches() 调用，保证现有清理入口同步覆盖。
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.globalEpochKey)
        defaults.removeObject(forKey: Self.domainEpochsKey)
    }

    /// 数据最小化：定期丢弃超过保留期的旧派生摘要，避免历史键无限累积。
    func prune(olderThan: TimeInterval = 7 * 24 * 60 * 60, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        let entries = entries().filter { now.timeIntervalSince($0.value.fetchedAt) < olderThan }
        save(entries)
    }

    // MARK: - HealthKit 类型映射到仓库领域

    static func domain(for sampleType: HKSampleType) -> String {
        if let quantityType = sampleType as? HKQuantityType {
            return domain(for: HKQuantityTypeIdentifier(rawValue: quantityType.identifier))
        }
        if let categoryType = sampleType as? HKCategoryType {
            return domain(for: HKCategoryTypeIdentifier(rawValue: categoryType.identifier))
        }
        if sampleType.identifier == HKObjectType.workoutType().identifier {
            return "workout"
        }
        if sampleType.identifier == HKObjectType.electrocardiogramType().identifier {
            return "heart.rhythm"
        }
        if sampleType.identifier == HKObjectType.stateOfMindType().identifier {
            return "wellness"
        }
        return "health"
    }

    static func domain(for identifier: HKQuantityTypeIdentifier) -> String {
        switch identifier {
        case .heartRate,
             .restingHeartRate,
             .walkingHeartRateAverage,
             .heartRateVariabilitySDNN,
             .respiratoryRate,
             .oxygenSaturation,
             .bloodPressureSystolic,
             .bloodPressureDiastolic,
             .atrialFibrillationBurden:
            return "heart"
        case .stepCount,
             .activeEnergyBurned,
             .basalEnergyBurned,
             .appleExerciseTime,
             .appleStandTime,
             .walkingSpeed,
             .walkingAsymmetryPercentage,
             .walkingStepLength,
             .walkingDoubleSupportPercentage,
             .stairAscentSpeed,
             .stairDescentSpeed,
             .appleWalkingSteadiness,
             .distanceWalkingRunning,
             .flightsClimbed,
             .dietaryWater,
             .dietaryCaffeine:
            return "activity"
        case .bodyMass,
             .bodyMassIndex,
             .bodyFatPercentage,
             .height,
             .leanBodyMass,
             .waistCircumference,
             .appleSleepingWristTemperature:
            return "body"
        case .vo2Max:
            return "cardio"
        case .timeInDaylight,
             .environmentalAudioExposure,
             .headphoneAudioExposure,
             .appleSleepingBreathingDisturbances:
            return "wellness"
        default:
            return "health"
        }
    }

    static func domain(for identifier: HKCategoryTypeIdentifier) -> String {
        switch identifier {
        case .sleepAnalysis:
            return "sleep"
        case .appleStandHour, .mindfulSession:
            return "activity"
        case .irregularHeartRhythmEvent, .highHeartRateEvent, .lowHeartRateEvent:
            return "heart.rhythm"
        default:
            return "health"
        }
    }

    // MARK: - 私有实现

    private struct CacheEnvelope: Codable {
        let valueData: Data
        let fetchedAt: Date
        let savedEpoch: Int
        let algorithmVersion: String?
    }

    private struct HealthKitRepositoryValue<Value: Codable>: Codable {
        let value: Value
    }

    private func entries() -> [String: CacheEnvelope] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([String: CacheEnvelope].self, from: data) else {
            return [:]
        }
        return entries
    }

    private func save(_ entries: [String: CacheEnvelope]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func currentEpoch(for domain: String) -> Int {
        let global = (defaults.object(forKey: Self.globalEpochKey) as? NSNumber)?.intValue ?? 0
        let domain = domainEpochs()[domain] ?? 0
        return global + domain
    }

    private func domainEpochs() -> [String: Int] {
        guard let data = defaults.data(forKey: Self.domainEpochsKey),
              let epochs = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return epochs
    }

    private func matchesAlgorithmVersion(_ expected: String?, _ stored: String?) -> Bool {
        guard let expected else { return true }
        return stored == expected
    }
}
