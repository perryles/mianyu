import Foundation

/// Converts the app's legacy zero-filled sleep placeholder into optional
/// evidence without changing the engine's support for a measured zero score.
nonisolated enum StressFocusCapacitySleepAdapter {
    nonisolated struct Evidence: Sendable, Equatable {
        let minutes: Int?
        let score: Int?
    }

    static func evidence(durationMinutes: Int?, score: Int?) -> Evidence {
        let minutes = durationMinutes.flatMap { $0 > 0 ? $0 : nil }
        let resolvedScore = score.flatMap { value -> Int? in
            guard value >= 0 else { return nil }
            if value == 0, minutes == nil { return nil }
            return value
        }
        return Evidence(minutes: minutes, score: resolvedScore)
    }
}
