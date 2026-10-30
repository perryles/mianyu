import Foundation

@MainActor
final class HealthProfileSummaryStore {
    static let shared = HealthProfileSummaryStore()

    private let engine: HealthProfileEngine
    private let cacheTTL: TimeInterval
    private var cachedSummaries: [HealthProfileRange: CachedSummary] = [:]
    private var inFlightTasks: [HealthProfileRange: Task<HealthProfileSummary, Never>] = [:]
    private var activeGenerations: [HealthProfileRange: UInt64] = [:]
    private var nextGeneration: UInt64 = 0

    init(engine: HealthProfileEngine? = nil, cacheTTL: TimeInterval = 600) {
        self.engine = engine ?? HealthProfileEngine()
        self.cacheTTL = cacheTTL
    }

    func summary(range: HealthProfileRange = .thirtyDays, forceRefresh: Bool = false) async -> HealthProfileSummary {
        if !forceRefresh, let cached = cachedSummaries[range], Date().timeIntervalSince(cached.loadedAt) < cacheTTL {
            return cached.summary
        }

        if !forceRefresh, let task = inFlightTasks[range] {
            return await task.value
        }

        if forceRefresh {
            inFlightTasks[range]?.cancel()
        }

        nextGeneration &+= 1
        let generation = nextGeneration
        activeGenerations[range] = generation

        let task = Task {
            await engine.generate(range: range)
        }
        inFlightTasks[range] = task
        let summary = await task.value
        if activeGenerations[range] == generation {
            cachedSummaries[range] = CachedSummary(summary: summary, loadedAt: Date())
            inFlightTasks[range] = nil
            activeGenerations[range] = nil
        }
        return summary
    }

    func invalidate() {
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        activeGenerations.removeAll()
        cachedSummaries.removeAll()
    }
}

private struct CachedSummary {
    let summary: HealthProfileSummary
    let loadedAt: Date
}
