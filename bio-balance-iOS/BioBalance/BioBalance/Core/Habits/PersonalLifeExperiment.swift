import Foundation

nonisolated enum PersonalLifeExperimentKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case caffeineCutoff
    case bedtimeRoutine
    case daylight20Minutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caffeineCutoff: return String(localized: "14:00 后不摄入咖啡因")
        case .bedtimeRoutine: return String(localized: "固定睡前准备")
        case .daylight20Minutes: return String(localized: "白天日照 20 分钟")
        }
    }

    var symbol: String {
        switch self {
        case .caffeineCutoff: return "cup.and.saucer.fill"
        case .bedtimeRoutine: return "moon.stars.fill"
        case .daylight20Minutes: return "sun.max.fill"
        }
    }
}

nonisolated enum PersonalLifeExperimentStatus: String, Codable, Sendable {
    case active
    case completed
    case ended
}

nonisolated struct PersonalLifeExperimentCheckIn: Codable, Hashable, Sendable, Identifiable {
    var date: Date
    var followedPlan: Bool
    var feelingScore: Int?
    var updatedAt: Date

    var id: Date { date }
}

nonisolated struct PersonalLifeExperimentRecord: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var kind: PersonalLifeExperimentKind
    var startDate: Date
    var durationDays: Int
    var status: PersonalLifeExperimentStatus
    var checkIns: [PersonalLifeExperimentCheckIn]
    var createdAt: Date
    var updatedAt: Date
    var endedAt: Date?

    init(kind: PersonalLifeExperimentKind, startDate: Date) {
        id = UUID()
        self.kind = kind
        self.startDate = startDate
        durationDays = 7
        status = .active
        checkIns = []
        createdAt = Date()
        updatedAt = createdAt
        endedAt = nil
    }
}

nonisolated enum PersonalLifeExperimentDirection: Equatable, Sendable {
    case higher
    case close
    case lower
}

nonisolated struct PersonalLifeExperimentSummary: Sendable {
    let recordedDays: Int
    let followedDays: Int
    let feelingSampleCount: Int
    let executionRate: Double?
    let averageFeeling: Double?
    let direction: PersonalLifeExperimentDirection?
}

nonisolated enum PersonalLifeExperimentEngine {
    static func make(
        record: PersonalLifeExperimentRecord,
        calendar: Calendar = .current
    ) -> PersonalLifeExperimentSummary {
        let checkIns = record.checkIns.filter { checkIn in
            let day = calendar.startOfDay(for: checkIn.date)
            guard let offset = calendar.dateComponents([.day], from: record.startDate, to: day).day else { return false }
            return (0..<record.durationDays).contains(offset)
        }
        let scores = checkIns.compactMap(\.feelingScore).filter { (1...5).contains($0) }
        let average = scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)

        let segmentAverage: (ClosedRange<Int>) -> Double? = { range in
            let values = checkIns.compactMap { checkIn -> Int? in
                guard let offset = calendar.dateComponents(
                    [.day],
                    from: record.startDate,
                    to: calendar.startOfDay(for: checkIn.date)
                ).day, range.contains(offset), let score = checkIn.feelingScore else { return nil }
                return score
            }
            guard values.count >= 2 else { return nil }
            return Double(values.reduce(0, +)) / Double(values.count)
        }

        let early = segmentAverage(0...2)
        let late = segmentAverage(4...6)
        let direction: PersonalLifeExperimentDirection?
        if let early, let late {
            let delta = late - early
            direction = abs(delta) < 0.5 ? .close : (delta > 0 ? .higher : .lower)
        } else {
            direction = nil
        }

        return PersonalLifeExperimentSummary(
            recordedDays: checkIns.count,
            followedDays: checkIns.filter(\.followedPlan).count,
            feelingSampleCount: scores.count,
            executionRate: checkIns.isEmpty ? nil : Double(checkIns.filter(\.followedPlan).count) / Double(checkIns.count),
            averageFeeling: average,
            direction: direction
        )
    }
}
