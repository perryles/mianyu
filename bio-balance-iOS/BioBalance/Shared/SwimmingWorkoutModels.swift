import Foundation

/// Measurement units accepted for an indoor swimming pool length.
enum SwimmingPoolLengthUnit: String, CaseIterable, Equatable, Hashable, Sendable {
    case meters
    case yards

    var symbol: String {
        switch self {
        case .meters: "m"
        case .yards: "yd"
        }
    }

    fileprivate var metersPerUnit: Double {
        switch self {
        case .meters: 1
        case .yards: 0.9144
        }
    }
}

/// A validated pool length. Custom lengths are accepted from 0 (exclusive) to 400 m.
struct SwimmingPoolLength: Equatable, Sendable {
    static let meters25 = SwimmingPoolLength(value: 25, unit: .meters)!
    static let meters50 = SwimmingPoolLength(value: 50, unit: .meters)!
    static let yards25 = SwimmingPoolLength(value: 25, unit: .yards)!

    static let presets: [SwimmingPoolLength] = [meters25, meters50, yards25]

    let value: Double
    let unit: SwimmingPoolLengthUnit

    var metersValue: Double {
        value * unit.metersPerUnit
    }

    /// Compact display text suitable for a pool-length picker (for example, “25 m”).
    var displayTitle: String {
        let number = value.rounded() == value ? String(Int(value)) : String(value)
        return "\(number) \(unit.symbol)"
    }

    init?(value: Double, unit: SwimmingPoolLengthUnit) {
        let metersValue = value * unit.metersPerUnit
        guard value.isFinite,
              value > 0,
              metersValue.isFinite,
              metersValue <= 400 else {
            return nil
        }

        self.value = value
        self.unit = unit
    }
}

enum SwimmingWorkoutPhase: String, CaseIterable, Equatable, Hashable, Sendable {
    case idle
    case preparing
    case running
    case paused
    case ending
    case finished
    case failed
}

/// Defines the allowed state changes for one swimming workout.
enum SwimmingWorkoutLifecycle {
    static func canTransition(from current: SwimmingWorkoutPhase, to next: SwimmingWorkoutPhase) -> Bool {
        switch current {
        case .idle:
            next == .preparing
        case .preparing:
            next == .running || next == .ending || next == .idle || next == .failed
        case .running:
            next == .paused || next == .ending || next == .failed
        case .paused:
            next == .running || next == .ending || next == .failed
        case .ending:
            next == .finished || next == .failed
        case .finished, .failed:
            next == .idle
        }
    }
}

/// The source location for a swimming workout.
enum SwimmingWorkoutLocation: String, CaseIterable, Equatable, Hashable, Sendable {
    case pool
    case openWater
}

/// The user-selected settings needed to configure one HealthKit swimming session.
struct SwimmingSessionConfiguration: Equatable, Sendable {
    let location: SwimmingWorkoutLocation
    /// Required for pool sessions; intentionally nil for open water.
    let poolLength: SwimmingPoolLength?

    var isPool: Bool { location == .pool }

    nonisolated private init(location: SwimmingWorkoutLocation, poolLength: SwimmingPoolLength?) {
        self.location = location
        self.poolLength = poolLength
    }

    nonisolated static func pool(_ length: SwimmingPoolLength) -> SwimmingSessionConfiguration {
        SwimmingSessionConfiguration(location: .pool, poolLength: length)
    }

    static let openWater = SwimmingSessionConfiguration(location: .openWater, poolLength: nil)
}

/// Pure, testable calculations shared by the Watch live UI and the iPhone report.
enum SwimmingMetricsCalculator {
    nonisolated static func paceSecondsPer100Meters(
        duration: TimeInterval?,
        distanceMeters: Double?
    ) -> TimeInterval? {
        guard let duration, let distanceMeters,
              duration.isFinite, duration > 0,
              distanceMeters.isFinite, distanceMeters > 0 else { return nil }
        let pace = duration / (distanceMeters / 100)
        return pace.isFinite && pace > 0 ? pace : nil
    }

    nonisolated static func strokesPerMinute(
        strokeCount: Int?,
        duration: TimeInterval?
    ) -> Double? {
        guard let strokeCount, strokeCount > 0,
              let duration, duration.isFinite, duration > 0 else { return nil }
        let rate = Double(strokeCount) / duration * 60
        return rate.isFinite && rate > 0 ? rate : nil
    }

    nonisolated static func durationText(_ duration: TimeInterval?) -> String? {
        guard let duration, duration.isFinite, duration >= 0 else { return nil }
        let totalSeconds = Int(duration.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    nonisolated static func paceText(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Live values remain nil until HealthKit supplies a corresponding measurement.
struct SwimmingLiveMetrics: Equatable, Sendable {
    var duration: TimeInterval?
    var distanceMeters: Double?
    var currentHeartRateBPM: Double?
    var averageHeartRateBPM: Double?
    var activeEnergyKilocalories: Double?
    var strokeCount: Int?
    var lapCount: Int?
    var averagePaceSecondsPer100Meters: Double?

    static let empty = SwimmingLiveMetrics(
        duration: nil,
        distanceMeters: nil,
        currentHeartRateBPM: nil,
        averageHeartRateBPM: nil,
        activeEnergyKilocalories: nil,
        strokeCount: nil,
        lapCount: nil,
        averagePaceSecondsPer100Meters: nil
    )
}
