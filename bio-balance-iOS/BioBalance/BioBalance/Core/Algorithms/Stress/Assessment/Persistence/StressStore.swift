import Foundation

struct StressStore {
    nonisolated static let cacheKey = "stressSnapshot.v3"
    private static let obsoleteCacheKeys = ["todayStressAssessment.v1", "stressSnapshot.v2"]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.obsoleteCacheKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    func save(_ snapshot: StressSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }

    func load() throws -> StressSnapshot? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        let snapshot = try JSONDecoder().decode(StressSnapshot.self, from: data)
        guard snapshot.schemaVersion == StressSnapshot.schemaVersion,
              isCurrentAlgorithmVersion(snapshot.current),
              isCurrentAlgorithmVersion(snapshot.daily) else {
            return nil
        }
        return snapshot
    }

    func clear() {
        defaults.removeObject(forKey: Self.cacheKey)
        Self.obsoleteCacheKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    private func isCurrentAlgorithmVersion(_ evaluation: StressEvaluation) -> Bool {
        switch evaluation {
        case .available(let result):
            return result.algorithmVersion == StressResult.currentAlgorithmVersion
        case .unavailable:
            return true
        }
    }
}
