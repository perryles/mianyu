import Foundation

extension HealthKitManager {
    /// 统一缓存读取入口：命中优先，未命中则执行 HealthKit 读取并把派生值落盘。
    func cachedRepositoryValue<Value: Codable>(
        domain: String,
        name: String,
        parameters: String,
        algorithmVersion: String? = nil,
        ttl: TimeInterval = HealthKitRepositoryCache.defaultTTL,
        forceRefresh: Bool = false,
        fallback: () async throws -> Value
    ) async rethrows -> Value {
        let key = HealthKitRepositoryCacheKey(
            domain: domain,
            name: name,
            parameters: parameters,
            algorithmVersion: algorithmVersion
        )
        if !forceRefresh,
           let cached: Value = HealthKitRepositoryCache.shared.value(for: key, ttl: ttl) {
            return cached
        }

        let value = try await fallback()
        HealthKitRepositoryCache.shared.store(
            value,
            for: key,
            algorithmVersion: algorithmVersion
        )
        return value
    }
}
