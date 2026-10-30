import Foundation

struct VO2MaxAssessmentStore {
    nonisolated static let cacheKey = "vo2MaxDailyAssessment.v3_1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ assessments: [VO2MaxDailyAssessment]) {
        guard !assessments.isEmpty else { return }
        var assessmentsByID = Dictionary(uniqueKeysWithValues: load().map { ($0.id, $0) })
        for assessment in assessments {
            assessmentsByID[assessment.id] = assessment
        }
        let merged = Array(assessmentsByID.values.sorted { $0.date < $1.date }.suffix(400))
        guard let data = try? JSONEncoder().encode(merged) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }

    func load() -> [VO2MaxDailyAssessment] {
        guard let data = defaults.data(forKey: Self.cacheKey),
              let decoded = try? JSONDecoder().decode([VO2MaxDailyAssessment].self, from: data) else {
            return []
        }
        return decoded
    }

    func clear() {
        defaults.removeObject(forKey: Self.cacheKey)
    }
}
