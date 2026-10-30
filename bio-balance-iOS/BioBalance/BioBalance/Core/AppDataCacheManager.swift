import Foundation
import SwiftData

nonisolated enum AppDataCacheCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case localPageSnapshots
    case sharedWidgetSnapshots
    case watchTransportSnapshots

    var title: String {
        switch self {
        case .localPageSnapshots:
            return String(localized: "页面派生快照")
        case .sharedWidgetSnapshots:
            return String(localized: "Widget / Watch 展示快照")
        case .watchTransportSnapshots:
            return String(localized: "Watch 传输缓存")
        }
    }

    var detail: String {
        switch self {
        case .localPageSnapshots:
            return String(localized: "今日、健康、趋势页可重建数据")
        case .sharedWidgetSnapshots:
            return String(localized: "小组件和表盘读取的共享展示数据")
        case .watchTransportSnapshots:
            return String(localized: "最近一次待发送到手表的同步包")
        }
    }
}

nonisolated struct AppDataCacheItem: Equatable, Sendable {
    let category: AppDataCacheCategory
    let key: String
    let title: String
    let sizeBytes: Int
    let updatedAt: Date?
}

nonisolated struct AppDataCacheCategorySnapshot: Equatable, Sendable {
    let category: AppDataCacheCategory
    let items: [AppDataCacheItem]

    var itemCount: Int { items.count }
    var totalBytes: Int { items.reduce(0) { $0 + $1.sizeBytes } }
    var lastUpdatedAt: Date? {
        items.compactMap(\.updatedAt).max()
    }
}

nonisolated struct AppDataCacheSnapshot: Equatable, Sendable {
    let categories: [AppDataCacheCategorySnapshot]
    let generatedAt: Date

    var totalItemCount: Int {
        categories.reduce(0) { $0 + $1.itemCount }
    }

    var totalBytes: Int {
        categories.reduce(0) { $0 + $1.totalBytes }
    }

    func category(_ category: AppDataCacheCategory) -> AppDataCacheCategorySnapshot {
        categories.first { $0.category == category } ?? AppDataCacheCategorySnapshot(category: category, items: [])
    }
}

nonisolated struct AppDataCacheClearResult: Equatable, Sendable {
    let categories: Set<AppDataCacheCategory>
    let removedItemCount: Int
    let removedBytes: Int
    let clearedAt: Date
    let remainingSnapshot: AppDataCacheSnapshot
}

// MARK: - Cache policy and key

nonisolated enum CacheInvalidationStrategy: String, CaseIterable, Codable, Sendable {
    case timeBased
    case versioned
    case forceRefresh
    case onWrite
}

nonisolated struct CachePolicy: Equatable, Sendable {
    static let currentAlgorithmVersion = 1

    static let standard = CachePolicy(ttl: 6 * 60 * 60)
    static let pageSnapshot = CachePolicy(ttl: 4 * 60 * 60)
    static let widgetSnapshot = CachePolicy(ttl: 6 * 60 * 60)
    static let watchTransport = CachePolicy(
        ttl: 30 * 60,
        invalidation: .onWrite,
        persistsInSwiftData: true,
        cachesToFile: false,
        usesURLCache: false
    )
    static let networkResponse = CachePolicy(
        ttl: 15 * 60,
        persistsInSwiftData: false,
        cachesToFile: false,
        usesURLCache: true
    )
    static let shortLived = CachePolicy(ttl: 5 * 60)
    static let persistentOnly = CachePolicy(
        ttl: 24 * 60 * 60,
        cachesToFile: false,
        usesURLCache: false
    )
    static let neverExpires = CachePolicy(
        ttl: nil,
        persistsInSwiftData: true,
        cachesToFile: true,
        usesURLCache: false
    )

    let ttl: TimeInterval?
    let algorithmVersion: Int
    let invalidation: CacheInvalidationStrategy
    let persistsInSwiftData: Bool
    let cachesToFile: Bool
    let usesURLCache: Bool

    init(
        ttl: TimeInterval?,
        algorithmVersion: Int = CachePolicy.currentAlgorithmVersion,
        invalidation: CacheInvalidationStrategy = .timeBased,
        persistsInSwiftData: Bool = true,
        cachesToFile: Bool = true,
        usesURLCache: Bool = true
    ) {
        self.ttl = ttl
        self.algorithmVersion = algorithmVersion
        self.invalidation = invalidation
        self.persistsInSwiftData = persistsInSwiftData
        self.cachesToFile = cachesToFile
        self.usesURLCache = usesURLCache
    }

    func expiryDate(from now: Date) -> Date? {
        ttl.map { now.addingTimeInterval($0) }
    }

    func isValid(
        algorithmVersion storedVersion: Int?,
        expiresAt: Date?,
        now: Date
    ) -> Bool {
        if let storedVersion, storedVersion != algorithmVersion {
            return false
        }
        if invalidation == .forceRefresh {
            return false
        }
        if let expiresAt, expiresAt <= now {
            return false
        }
        return true
    }
}

nonisolated struct CacheKey: Hashable, Codable, Sendable {
    let category: AppDataCacheCategory
    let namespace: String
    let identifier: String
    let version: Int

    init(
        category: AppDataCacheCategory,
        namespace: String,
        identifier: String,
        version: Int = CachePolicy.currentAlgorithmVersion
    ) {
        self.category = category
        self.namespace = namespace
        self.identifier = identifier
        self.version = version
    }

    var stableKey: String {
        "\(category.rawValue)::\(namespace)::\(version)::\(identifier)"
    }

    var persistentRecordID: String {
        "\(namespace)::\(version)::\(identifier)"
    }

    var fileComponent: String {
        stableKey
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}

// MARK: - Layer metrics

nonisolated enum CacheLayer: String, CaseIterable, Hashable, Sendable {
    case memory
    case persistent
    case file
    case network
    case appGroup
}

nonisolated struct CacheLayerMetrics: Equatable, Sendable {
    let layer: CacheLayer
    let itemCount: Int
    let byteCount: Int
    let lastUpdatedAt: Date?
    let available: Bool
}

nonisolated struct CacheLayerMetricsSet: Equatable, Sendable {
    let memory: CacheLayerMetrics
    let persistent: CacheLayerMetrics
    let file: CacheLayerMetrics
    let network: CacheLayerMetrics
    let appGroup: CacheLayerMetrics
    let generatedAt: Date
}

nonisolated struct CacheHitStatistics: Equatable, Sendable {
    let hits: Int
    let misses: Int
    let errors: Int

    var total: Int { hits + misses + errors }
    var hitRate: Double {
        total == 0 ? 0 : Double(hits) / Double(total)
    }
}

nonisolated struct CacheClearHistory: Equatable, Sendable {
    let lastFullClearAt: Date?
    let lastClearByCategory: [AppDataCacheCategory: Date]

    func lastClear(for category: AppDataCacheCategory) -> Date? {
        lastClearByCategory[category] ?? lastFullClearAt
    }
}

nonisolated enum CacheReadSource: String, Sendable {
    case memory
    case file
    case persistent
    case none
}

nonisolated struct CacheReadOutcome: Equatable, Sendable {
    let data: Data?
    let source: CacheReadSource
}

// MARK: - Persistent and file envelopes

nonisolated struct CachePersistedEnvelope: Codable, Sendable {
    let cacheVersion: Int
    let algorithmVersion: Int
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date?
    let data: Data
}

nonisolated struct CacheFileEnvelope: Codable, Sendable {
    let cacheVersion: Int
    let algorithmVersion: Int
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date?
    let data: Data
}

// MARK: - Memory cache

nonisolated struct CacheMemoryMetadata: Sendable {
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date?
    let algorithmVersion: Int
    let byteCount: Int
}

nonisolated struct CacheMemoryEntry: Sendable {
    let data: Data
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date?
    let algorithmVersion: Int
}

actor CacheMemoryStore {
    final class EntryBox: @unchecked Sendable {
        let entry: CacheMemoryEntry

        init(entry: CacheMemoryEntry) {
            self.entry = entry
        }
    }

    final class Storage: @unchecked Sendable {
        let cache = NSCache<NSString, EntryBox>()

        init() {
            cache.totalCostLimit = 8 * 1024 * 1024
            cache.countLimit = 512
        }
    }

    private let storage: Storage
    private var metadata: [String: CacheMemoryMetadata] = [:]

    init(storage: Storage = Storage()) {
        self.storage = storage
    }

    func value(for key: CacheKey) -> CacheMemoryEntry? {
        guard let box = storage.cache.object(forKey: key.stableKey as NSString) else {
            metadata.removeValue(forKey: key.stableKey)
            return nil
        }
        if metadata[key.stableKey] == nil {
            metadata[key.stableKey] = CacheMemoryMetadata(
                createdAt: box.entry.createdAt,
                updatedAt: box.entry.updatedAt,
                expiresAt: box.entry.expiresAt,
                algorithmVersion: box.entry.algorithmVersion,
                byteCount: box.entry.data.count
            )
        }
        return CacheMemoryEntry(
            data: box.entry.data,
            createdAt: box.entry.createdAt,
            updatedAt: box.entry.updatedAt,
            expiresAt: box.entry.expiresAt,
            algorithmVersion: box.entry.algorithmVersion
        )
    }

    func set(_ entry: CacheMemoryEntry, for key: CacheKey) {
        metadata[key.stableKey] = CacheMemoryMetadata(
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            expiresAt: entry.expiresAt,
            algorithmVersion: entry.algorithmVersion,
            byteCount: entry.data.count
        )
        storage.cache.setObject(
            EntryBox(entry: entry),
            forKey: key.stableKey as NSString,
            cost: max(1, entry.data.count)
        )
    }

    func remove(for key: CacheKey) {
        storage.cache.removeObject(forKey: key.stableKey as NSString)
        metadata.removeValue(forKey: key.stableKey)
    }

    func remove(category: AppDataCacheCategory) {
        let prefix = category.rawValue + "::"
        let keys = Array(metadata.keys)
        for key in keys where key.hasPrefix(prefix) {
            storage.cache.removeObject(forKey: key as NSString)
            metadata.removeValue(forKey: key)
        }
    }

    func removeAll() {
        storage.cache.removeAllObjects()
        metadata.removeAll()
    }

    func removeExpired(now: Date) {
        let keys = Array(metadata.keys)
        for key in keys {
            guard let expiresAt = metadata[key]?.expiresAt, expiresAt <= now else { continue }
            storage.cache.removeObject(forKey: key as NSString)
            metadata.removeValue(forKey: key)
        }
    }

    func metrics() -> CacheLayerMetrics {
        reconcileEvicted()
        var bytes = 0
        var lastUpdatedAt: Date?
        for meta in metadata.values {
            bytes += meta.byteCount
            if lastUpdatedAt == nil || meta.updatedAt > lastUpdatedAt! {
                lastUpdatedAt = meta.updatedAt
            }
        }
        return CacheLayerMetrics(
            layer: .memory,
            itemCount: metadata.count,
            byteCount: bytes,
            lastUpdatedAt: lastUpdatedAt,
            available: true
        )
    }

    private func reconcileEvicted() {
        let keys = Array(metadata.keys)
        for key in keys where storage.cache.object(forKey: key as NSString) == nil {
            metadata.removeValue(forKey: key)
        }
    }
}

// MARK: - File cache

actor CacheFileStore {
    private let directory: URL

    init(directory: URL? = nil) {
        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BioBalanceCache")
        self.directory = directory ?? caches?.appendingPathComponent("BioBalanceCache", isDirectory: true) ?? fallback
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: CacheKey) -> URL {
        directory
            .appendingPathComponent(key.category.rawValue, isDirectory: true)
            .appendingPathComponent(key.fileComponent + ".bbcache")
    }

    func read(for key: CacheKey, now: Date) -> CacheFileEnvelope? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(CacheFileEnvelope.self, from: data) else {
            return nil
        }
        if let expiresAt = envelope.expiresAt, expiresAt <= now {
            remove(for: key)
            return nil
        }
        return envelope
    }

    func write(_ envelope: CacheFileEnvelope, for key: CacheKey) {
        let url = fileURL(for: key)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func remove(for key: CacheKey) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func remove(category: AppDataCacheCategory) {
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(category.rawValue, isDirectory: true)
        )
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func metrics() -> CacheLayerMetrics {
        let fileManager = FileManager.default
        let categoryURLs = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var itemCount = 0
        var byteCount = 0
        var lastUpdatedAt: Date?

        for categoryURL in categoryURLs where categoryURL.hasDirectoryPath {
            let fileURLs = (try? fileManager.contentsOfDirectory(
                at: categoryURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for fileURL in fileURLs where fileURL.pathExtension == "bbcache" {
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                itemCount += 1
                byteCount += values?.fileSize ?? 0
                if let date = values?.contentModificationDate,
                   lastUpdatedAt == nil || date > lastUpdatedAt! {
                    lastUpdatedAt = date
                }
            }
        }

        return CacheLayerMetrics(
            layer: .file,
            itemCount: itemCount,
            byteCount: byteCount,
            lastUpdatedAt: lastUpdatedAt,
            available: true
        )
    }

    func pruneExpired(now: Date) -> Int {
        let fileManager = FileManager.default
        let categoryURLs = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var removed = 0

        for categoryURL in categoryURLs where categoryURL.hasDirectoryPath {
            let fileURLs = (try? fileManager.contentsOfDirectory(
                at: categoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for fileURL in fileURLs where fileURL.pathExtension == "bbcache" {
                guard let data = try? Data(contentsOf: fileURL),
                      let envelope = try? JSONDecoder().decode(CacheFileEnvelope.self, from: data),
                      let expiresAt = envelope.expiresAt,
                      expiresAt <= now else {
                    continue
                }
                try? fileManager.removeItem(at: fileURL)
                removed += 1
            }
        }
        return removed
    }
}

// MARK: - Cache manager

@MainActor
final class CacheManager {
    static let shared = CacheManager()
    static let currentCacheVersion = 1
    static let persistentDomain = "app-data-cache"
    static let maximumPersistentItemsPerCategory = 512

    private let memoryStore: CacheMemoryStore
    private let fileStore: CacheFileStore
    private let persistentStore: SwiftDataRecordStore
    private let networkCache: URLCache

    private var hitCounts: [String: Int] = [:]
    private var missCounts: [String: Int] = [:]
    private var errorCounts: [String: Int] = [:]
    private var lastClearedAt: [AppDataCacheCategory: Date] = [:]
    private var lastFullClearAt: Date?
    private var networkEntryKeys: Set<String> = []

    init(
        memoryStore: CacheMemoryStore = CacheMemoryStore(),
        fileStore: CacheFileStore = CacheFileStore(),
        persistentStore: SwiftDataRecordStore? = nil,
        networkCache: URLCache? = nil
    ) {
        self.memoryStore = memoryStore
        self.fileStore = fileStore
        self.persistentStore = persistentStore ?? SwiftDataRecordStore(container: MianyuModelContainer.shared)
        let configuredCache = networkCache ?? URLCache(
            memoryCapacity: 4 * 1024 * 1024,
            diskCapacity: 32 * 1024 * 1024,
            diskPath: "BioBalanceNetworkCache"
        )
        self.networkCache = configuredCache
        URLCache.shared = configuredCache
    }

    func readData(for key: CacheKey, policy: CachePolicy, now: Date = Date()) async -> CacheReadOutcome {
        if key.version != policy.algorithmVersion {
            missCounts[key.namespace, default: 0] += 1
            await remove(key: key)
            return CacheReadOutcome(data: nil, source: .none)
        }

        if let memoryEntry = await memoryStore.value(for: key),
           policy.isValid(
               algorithmVersion: memoryEntry.algorithmVersion,
               expiresAt: memoryEntry.expiresAt,
               now: now
           ) {
            hitCounts[key.namespace, default: 0] += 1
            return CacheReadOutcome(data: memoryEntry.data, source: .memory)
        }

        if policy.cachesToFile,
           let fileEnvelope = await fileStore.read(for: key, now: now),
           policy.isValid(
               algorithmVersion: fileEnvelope.algorithmVersion,
               expiresAt: fileEnvelope.expiresAt,
               now: now
           ) {
            hitCounts[key.namespace, default: 0] += 1
            await memoryStore.set(
                CacheMemoryEntry(
                    data: fileEnvelope.data,
                    createdAt: fileEnvelope.createdAt,
                    updatedAt: fileEnvelope.updatedAt,
                    expiresAt: fileEnvelope.expiresAt,
                    algorithmVersion: fileEnvelope.algorithmVersion
                ),
                for: key
            )
            return CacheReadOutcome(data: fileEnvelope.data, source: .file)
        }

        if policy.persistsInSwiftData,
           let persisted = persistentEnvelope(for: key),
           policy.isValid(
               algorithmVersion: persisted.algorithmVersion,
               expiresAt: persisted.expiresAt,
               now: now
           ) {
            hitCounts[key.namespace, default: 0] += 1
            await writeToMemoryAndFile(persisted, for: key, policy: policy)
            return CacheReadOutcome(data: persisted.data, source: .persistent)
        }

        missCounts[key.namespace, default: 0] += 1
        if policy.invalidation == .versioned {
            await remove(key: key)
        }
        return CacheReadOutcome(data: nil, source: .none)
    }

    func writeData(
        _ data: Data,
        for key: CacheKey,
        policy: CachePolicy,
        now: Date = Date()
    ) async {
        let expiresAt = policy.expiryDate(from: now)
        let envelope = CachePersistedEnvelope(
            cacheVersion: Self.currentCacheVersion,
            algorithmVersion: policy.algorithmVersion,
            createdAt: now,
            updatedAt: now,
            expiresAt: expiresAt,
            data: data
        )

        if policy.persistsInSwiftData {
            guard let payload = try? JSONEncoder().encode(envelope) else {
                errorCounts[key.namespace, default: 0] += 1
                return
            }
            let seed = LocalDataRecordSeed(
                domain: Self.persistentDomain,
                recordID: key.persistentRecordID,
                kind: key.category.rawValue,
                occurredAt: now,
                updatedAt: now,
                payload: payload
            )
            guard persistentStore.upsert(
                seed,
                keepingNewest: Self.maximumPersistentItemsPerCategory
            ) else {
                errorCounts[key.namespace, default: 0] += 1
                return
            }
        }

        if policy.cachesToFile {
            await fileStore.write(
                CacheFileEnvelope(
                    cacheVersion: envelope.cacheVersion,
                    algorithmVersion: envelope.algorithmVersion,
                    createdAt: envelope.createdAt,
                    updatedAt: envelope.updatedAt,
                    expiresAt: envelope.expiresAt,
                    data: data
                ),
                for: key
            )
        }

        await memoryStore.set(
            CacheMemoryEntry(
                data: data,
                createdAt: now,
                updatedAt: now,
                expiresAt: expiresAt,
                algorithmVersion: policy.algorithmVersion
            ),
            for: key
        )
    }

    func cachedValue<T: Codable & Sendable>(
        _ type: T.Type,
        for key: CacheKey,
        policy: CachePolicy,
        forceRefresh: Bool = false,
        loader: (() async throws -> T)? = nil
    ) async -> T? {
        if forceRefresh {
            await remove(key: key)
        } else {
            let outcome = await readData(for: key, policy: policy)
            if let data = outcome.data,
               let value = try? JSONDecoder().decode(T.self, from: data) {
                return value
            }
        }

        guard let loader else { return nil }
        do {
            let value = try await loader()
            if let data = try? JSONEncoder().encode(value) {
                await writeData(data, for: key, policy: policy)
            }
            return value
        } catch {
            errorCounts[key.namespace, default: 0] += 1
            return nil
        }
    }

    func remove(key: CacheKey) async {
        await memoryStore.remove(for: key)
        await fileStore.remove(for: key)
        _ = persistentStore.remove(stableKey: Self.stableKey(for: key))
    }

    func remove(category: AppDataCacheCategory) async {
        await memoryStore.remove(category: category)
        await fileStore.remove(category: category)
        _ = persistentStore.clear(domain: Self.persistentDomain, kind: category.rawValue)
        lastClearedAt[category] = Date()
    }

    func clear(categories: Set<AppDataCacheCategory>, clearingNetwork: Bool) async {
        for category in categories {
            await remove(category: category)
        }
        if clearingNetwork {
            removeNetworkCache()
            lastFullClearAt = Date()
        }
    }

    func clearAll() async {
        await memoryStore.removeAll()
        await fileStore.removeAll()
        _ = persistentStore.clear(domain: Self.persistentDomain)
        removeNetworkCache()
        let now = Date()
        lastFullClearAt = now
        for category in AppDataCacheCategory.allCases {
            lastClearedAt[category] = now
        }
    }

    func layerMetrics(appGroup: CacheLayerMetrics) async -> CacheLayerMetricsSet {
        let memory = await memoryStore.metrics()
        let file = await fileStore.metrics()
        return CacheLayerMetricsSet(
            memory: memory,
            persistent: persistentMetrics(),
            file: file,
            network: networkMetrics(),
            appGroup: appGroup,
            generatedAt: Date()
        )
    }

    func memoryMetrics() async -> CacheLayerMetrics {
        await memoryStore.metrics()
    }

    func fileMetrics() async -> CacheLayerMetrics {
        await fileStore.metrics()
    }

    func persistentMetrics() -> CacheLayerMetrics {
        guard let rows = persistentStore.records(domain: Self.persistentDomain) else {
            return CacheLayerMetrics(
                layer: .persistent,
                itemCount: 0,
                byteCount: 0,
                lastUpdatedAt: nil,
                available: false
            )
        }
        var byteCount = 0
        var lastUpdatedAt: Date?
        for row in rows {
            byteCount += row.payload.count
            if lastUpdatedAt == nil || row.updatedAt > lastUpdatedAt! {
                lastUpdatedAt = row.updatedAt
            }
        }
        return CacheLayerMetrics(
            layer: .persistent,
            itemCount: rows.count,
            byteCount: byteCount,
            lastUpdatedAt: lastUpdatedAt,
            available: true
        )
    }

    func networkMetrics() -> CacheLayerMetrics {
        let memoryBytes = networkCache.currentMemoryUsage
        let diskBytes = networkCache.currentDiskUsage
        let estimatedCount = networkEntryKeys.count
            + (memoryBytes > 0 ? 1 : 0)
            + (diskBytes > 0 ? 1 : 0)
        return CacheLayerMetrics(
            layer: .network,
            itemCount: estimatedCount,
            byteCount: memoryBytes + diskBytes,
            lastUpdatedAt: nil,
            available: true
        )
    }

    func cacheURLResponse(
        _ response: URLResponse,
        data: Data,
        for request: URLRequest,
        key: CacheKey
    ) {
        networkCache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        networkEntryKeys.insert(key.stableKey)
    }

    func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        networkCache.cachedResponse(for: request)
    }

    func removeNetworkCache() {
        networkCache.removeAllCachedResponses()
        networkEntryKeys.removeAll()
    }

    func statistics() -> CacheHitStatistics {
        CacheHitStatistics(
            hits: hitCounts.values.reduce(0, +),
            misses: missCounts.values.reduce(0, +),
            errors: errorCounts.values.reduce(0, +)
        )
    }

    func resetStatistics() {
        hitCounts.removeAll()
        missCounts.removeAll()
        errorCounts.removeAll()
    }

    func clearHistory() -> CacheClearHistory {
        CacheClearHistory(
            lastFullClearAt: lastFullClearAt,
            lastClearByCategory: lastClearedAt
        )
    }

    func pruneExpired(now: Date = Date()) async {
        _ = await fileStore.pruneExpired(now: now)
        await memoryStore.removeExpired(now: now)
        removeExpiredPersistent(now: now)
    }

    private func writeToMemoryAndFile(
        _ envelope: CachePersistedEnvelope,
        for key: CacheKey,
        policy: CachePolicy
    ) async {
        await memoryStore.set(
            CacheMemoryEntry(
                data: envelope.data,
                createdAt: envelope.createdAt,
                updatedAt: envelope.updatedAt,
                expiresAt: envelope.expiresAt,
                algorithmVersion: envelope.algorithmVersion
            ),
            for: key
        )
        if policy.cachesToFile {
            await fileStore.write(
                CacheFileEnvelope(
                    cacheVersion: envelope.cacheVersion,
                    algorithmVersion: envelope.algorithmVersion,
                    createdAt: envelope.createdAt,
                    updatedAt: envelope.updatedAt,
                    expiresAt: envelope.expiresAt,
                    data: envelope.data
                ),
                for: key
            )
        }
    }

    private func persistentEnvelope(for key: CacheKey) -> CachePersistedEnvelope? {
        guard let rows = persistentStore.records(
            domain: Self.persistentDomain,
            kind: key.category.rawValue
        ) else {
            return nil
        }
        guard let row = rows.first(where: { $0.recordID == key.persistentRecordID }),
              let envelope = try? JSONDecoder().decode(CachePersistedEnvelope.self, from: row.payload) else {
            return nil
        }
        return envelope
    }

    private func removeExpiredPersistent(now: Date) {
        guard let rows = persistentStore.records(domain: Self.persistentDomain) else { return }
        for row in rows {
            guard let envelope = try? JSONDecoder().decode(CachePersistedEnvelope.self, from: row.payload),
                  let expiresAt = envelope.expiresAt,
                  expiresAt <= now else {
                continue
            }
            _ = persistentStore.remove(stableKey: row.stableKey)
        }
    }

    private static func stableKey(for key: CacheKey) -> String {
        "\(persistentDomain)::\(key.category.rawValue)::\(key.persistentRecordID)"
    }
}

// MARK: - Details and sync status

nonisolated struct AppDataCacheDetails: Equatable, Sendable {
    let legacySnapshot: AppDataCacheSnapshot
    let layers: CacheLayerMetricsSet
    let statistics: CacheHitStatistics
    let lastClear: CacheClearHistory
    let widgetSync: WidgetWatchSyncStatus
    let generatedAt: Date
}

nonisolated struct WidgetWatchSyncStatus: Equatable, Sendable {
    let appGroupSnapshot: AppGroupSnapshotCacheStatus
    let lastSyncAt: Date?
    let watchTransportCached: Bool
    let watchPaired: Bool
    let watchReachable: Bool
    let watchActivationState: String?
}

// MARK: - AppDataCacheManager

nonisolated final class AppDataCacheDefaultsBox: @unchecked Sendable {
    let local: UserDefaults
    let shared: UserDefaults?

    init(local: UserDefaults, shared: UserDefaults?) {
        self.local = local
        self.shared = shared
    }
}

@MainActor
final class AppDataCacheManager {
    static let shared = AppDataCacheManager(resetRuntimeStateOnClear: true)

    private let localDefaults: UserDefaults
    private let sharedDefaults: UserDefaults?
    private let resetRuntimeStateOnClear: Bool
    private let cacheManager: CacheManager
    private nonisolated let defaultsBox: AppDataCacheDefaultsBox

    init(
        localDefaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults? = AppGroupManager.userDefaults(),
        resetRuntimeStateOnClear: Bool = false,
        cacheManager: CacheManager? = nil
    ) {
        self.localDefaults = localDefaults
        self.sharedDefaults = sharedDefaults
        self.resetRuntimeStateOnClear = resetRuntimeStateOnClear
        self.cacheManager = cacheManager ?? .shared
        self.defaultsBox = AppDataCacheDefaultsBox(local: localDefaults, shared: sharedDefaults)
    }

    var repositoryCache: CacheManager {
        cacheManager
    }

    nonisolated func snapshot() -> AppDataCacheSnapshot {
        Self.makeSnapshot(localDefaults: defaultsBox.local, sharedDefaults: defaultsBox.shared)
    }

    func cacheDetails() async -> AppDataCacheDetails {
        let layers = await cacheManager.layerMetrics(appGroup: appGroupLayerMetrics())
        return AppDataCacheDetails(
            legacySnapshot: snapshot(),
            layers: layers,
            statistics: cacheManager.statistics(),
            lastClear: cacheManager.clearHistory(),
            widgetSync: widgetWatchSyncStatus(),
            generatedAt: Date()
        )
    }

    @MainActor
    func clear() -> AppDataCacheClearResult {
        clear(categories: Set(AppDataCacheCategory.allCases))
    }

    @MainActor
    func clear(categories: Set<AppDataCacheCategory>) -> AppDataCacheClearResult {
        let result = clearLegacyCategories(categories)
        let isFullClear = categories == Set(AppDataCacheCategory.allCases)
        Task { [cacheManager] in
            await cacheManager.clear(categories: categories, clearingNetwork: isFullClear)
        }
        return result
    }

    func clearAllCaches() async -> AppDataCacheClearResult {
        let result = clearLegacyCategories(Set(AppDataCacheCategory.allCases))
        await cacheManager.clearAll()
        return result
    }

    func clearCategory(_ category: AppDataCacheCategory) async -> AppDataCacheClearResult {
        let result = clearLegacyCategories([category])
        await cacheManager.remove(category: category)
        return result
    }

    func refreshAllCaches() async {
        await cacheManager.pruneExpired()
    }

    func memoryCacheMetrics() async -> CacheLayerMetrics {
        await cacheManager.memoryMetrics()
    }

    func fileCacheMetrics() async -> CacheLayerMetrics {
        await cacheManager.fileMetrics()
    }

    func persistentCacheMetrics() -> CacheLayerMetrics {
        cacheManager.persistentMetrics()
    }

    func networkCacheMetrics() -> CacheLayerMetrics {
        cacheManager.networkMetrics()
    }

    func appGroupCacheMetrics() -> CacheLayerMetrics {
        appGroupLayerMetrics()
    }

    func cacheStatistics() async -> CacheHitStatistics {
        cacheManager.statistics()
    }

    func resetCacheStatistics() {
        cacheManager.resetStatistics()
    }

    func clearNetworkCache() {
        cacheManager.removeNetworkCache()
    }

    func widgetWatchSyncStatus() -> WidgetWatchSyncStatus {
        let watchService = WatchConnectivitySyncService.shared
        return WidgetWatchSyncStatus(
            appGroupSnapshot: AppGroupSnapshotStore.status(),
            lastSyncAt: AppGroupManager.shared.getLastSyncTime() ?? watchService.lastWatchSyncDate,
            watchTransportCached: localDefaults.data(forKey: WatchConnectivitySyncService.cachedPayloadKey) != nil,
            watchPaired: watchService.isWatchPaired,
            watchReachable: watchService.isWatchReachable,
            watchActivationState: String(describing: watchService.watchActivationState)
        )
    }

    private func clearLegacyCategories(_ categories: Set<AppDataCacheCategory>) -> AppDataCacheClearResult {
        let before = Self.makeSnapshot(localDefaults: localDefaults, sharedDefaults: sharedDefaults)

        if categories.contains(.localPageSnapshots) {
            remove(Self.localPageSnapshotKeys, from: localDefaults)
            if resetRuntimeStateOnClear {
                HealthDataManager.shared.clearLocalCaches()
            }
        }

        if categories.contains(.sharedWidgetSnapshots), let sharedDefaults {
            remove(AppGroupManager.pageCacheKeys, from: sharedDefaults)
            remove(Self.sharedWidgetSnapshotKeys, from: sharedDefaults)
            AppGroupSnapshotStore.clear(defaults: sharedDefaults)

            // 迁移后这些缓存存放在 SwiftData 中；清理时同时删除已迁移记录和旧 UserDefaults 残留。
            localDefaults.removeObject(forKey: DailyDeterministicHealthSnapshotStore.storageKey)
            localDefaults.removeObject(forKey: LocalSyncOutbox.storageKey)
            DailyDeterministicHealthSnapshotStore.shared.clear()
            LocalSyncOutbox.shared.clear()
        }

        if categories.contains(.watchTransportSnapshots) {
            remove(Self.watchTransportKeys, from: localDefaults)
            if resetRuntimeStateOnClear {
                WatchConnectivitySyncService.shared.clearCachedState()
            }
        }

        let after = Self.makeSnapshot(localDefaults: localDefaults, sharedDefaults: sharedDefaults)
        return AppDataCacheClearResult(
            categories: categories,
            removedItemCount: selectedItemCount(in: before, categories: categories) - selectedItemCount(in: after, categories: categories),
            removedBytes: max(0, selectedBytes(in: before, categories: categories) - selectedBytes(in: after, categories: categories)),
            clearedAt: Date(),
            remainingSnapshot: after
        )
    }

    nonisolated private static var localPageSnapshotKeys: [String] {
        HealthDataManager.LocalCacheKeys.all + [
            StressStore.cacheKey,
            VO2MaxAssessmentStore.cacheKey
        ]
    }

    nonisolated private static var sharedWidgetSnapshotKeys: [String] {
        AppGroupManager.pageCacheKeys + [
            AppGroupSnapshotStore.widgetSnapshotV2Key,
            AppGroupSnapshotStore.legacyWidgetSnapshotV2Key,
            AppGroupSnapshotStore.lastSnapshotWriteKey,
            DailyDeterministicHealthSnapshotStore.storageKey,
            LocalSyncOutbox.storageKey
        ]
    }

    nonisolated private static var watchTransportKeys: [String] {
        [WatchConnectivitySyncService.cachedPayloadKey]
    }

    nonisolated private static var timestampKeys: Set<String> {
        [
            AppGroupManager.Keys.lastSyncTime,
            AppGroupManager.Keys.sunlightUpdatedAt,
            AppGroupManager.Keys.sedentaryUpdatedAt,
            AppGroupSnapshotStore.lastSnapshotWriteKey
        ]
    }

    nonisolated private static func makeSnapshot(
        localDefaults: UserDefaults,
        sharedDefaults: UserDefaults?
    ) -> AppDataCacheSnapshot {
        AppDataCacheSnapshot(
            categories: AppDataCacheCategory.allCases.map { category in
                AppDataCacheCategorySnapshot(
                    category: category,
                    items: items(
                        for: category,
                        localDefaults: localDefaults,
                        sharedDefaults: sharedDefaults
                    )
                )
            },
            generatedAt: Date()
        )
    }

    nonisolated private static func items(
        for category: AppDataCacheCategory,
        localDefaults: UserDefaults,
        sharedDefaults: UserDefaults?
    ) -> [AppDataCacheItem] {
        let defaults: UserDefaults?
        let keys: [String]

        switch category {
        case .localPageSnapshots:
            defaults = localDefaults
            keys = localPageSnapshotKeys
        case .sharedWidgetSnapshots:
            defaults = sharedDefaults
            keys = sharedWidgetSnapshotKeys
        case .watchTransportSnapshots:
            defaults = localDefaults
            keys = watchTransportKeys
        }

        guard let defaults else { return [] }

        return keys.compactMap { key in
            guard let value = defaults.object(forKey: key) else { return nil }
            return AppDataCacheItem(
                category: category,
                key: key,
                title: title(for: key),
                sizeBytes: estimatedSize(of: value),
                updatedAt: updatedAt(for: key, value: value)
            )
        }
    }

    private func remove(_ keys: [String], from defaults: UserDefaults) {
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    private func selectedItemCount(in snapshot: AppDataCacheSnapshot, categories: Set<AppDataCacheCategory>) -> Int {
        categories.reduce(0) { $0 + snapshot.category($1).itemCount }
    }

    private func selectedBytes(in snapshot: AppDataCacheSnapshot, categories: Set<AppDataCacheCategory>) -> Int {
        categories.reduce(0) { $0 + snapshot.category($1).totalBytes }
    }

    private func appGroupLayerMetrics() -> CacheLayerMetrics {
        let category = snapshot().category(.sharedWidgetSnapshots)
        return CacheLayerMetrics(
            layer: .appGroup,
            itemCount: category.itemCount,
            byteCount: category.totalBytes,
            lastUpdatedAt: category.lastUpdatedAt,
            available: true
        )
    }

    nonisolated private static func updatedAt(for key: String, value: Any) -> Date? {
        guard timestampKeys.contains(key) else { return nil }

        if let date = value as? Date {
            return date
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let interval = value as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        if let string = value as? String, let interval = TimeInterval(string) {
            return Date(timeIntervalSince1970: interval)
        }
        return nil
    }

    nonisolated private static func estimatedSize(of value: Any) -> Int {
        if let data = value as? Data {
            return data.count
        }
        if let string = value as? String {
            return string.utf8.count
        }
        if value is NSNumber || value is Date {
            return 8
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value) {
            return data.count
        }
        return String(describing: value).utf8.count
    }

    nonisolated private static func title(for key: String) -> String {
        Self.keyTitles[key] ?? key
    }

    nonisolated private static let keyTitles: [String: String] = [
        HealthDataManager.LocalCacheKeys.activity: "活动页本地快照",
        HealthDataManager.LocalCacheKeys.stress: "压力页本地快照",
        HealthDataManager.LocalCacheKeys.sleep: "睡眠页本地快照",
        HealthDataManager.LocalCacheKeys.realtime: "实时健康本地快照",
        StressStore.cacheKey: "今日压力评估缓存",
        VO2MaxAssessmentStore.cacheKey: "VO2 派生评估缓存",
        LocalSyncOutbox.storageKey: "iCloud 待同步 Outbox",
        AppGroupManager.Keys.latestHeartRate: "共享心率",
        AppGroupManager.Keys.latestHRV: "共享 HRV",
        AppGroupManager.Keys.latestStress: "共享压力",
        AppGroupManager.Keys.stressHistoryData: "共享压力历史",
        AppGroupManager.Keys.healthSummary: "共享健康摘要",
        AppGroupManager.Keys.waterIntakeMl: "共享饮水进度",
        AppGroupManager.Keys.caffeineRemainedMg: "共享咖啡因余量",
        AppGroupManager.Keys.steps: "共享步数",
        AppGroupManager.Keys.activeEnergy: "共享活动能量",
        AppGroupManager.Keys.exerciseMinutes: "共享锻炼分钟",
        AppGroupManager.Keys.standHours: "共享站立小时",
        AppGroupManager.Keys.sleepDurationMinutes: "共享睡眠时长",
        AppGroupManager.Keys.sleepScore: "共享睡眠评分",
        AppGroupManager.Keys.sunlightMinutesToday: "共享日照分钟",
        AppGroupManager.Keys.sedentaryElapsedMinutes: "共享久坐状态",
        AppGroupManager.Keys.bodyAgeValueYears: "共享身体年龄",
        AppGroupManager.Keys.vo2MaxValue: "共享 VO2 摘要",
        AppGroupSnapshotStore.widgetSnapshotV2Key: "Widget v2 快照",
        AppGroupSnapshotStore.legacyWidgetSnapshotV2Key: "Widget 旧版快照",
        AppGroupSnapshotStore.lastSnapshotWriteKey: "Widget 快照写入时间",
        WatchConnectivitySyncService.cachedPayloadKey: "Watch 同步传输包"
    ]
}
