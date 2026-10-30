import Foundation
import HealthKit

enum VO2MaxSource: String, Codable, Sendable {
    case healthKitActual
    case engineEstimated
    case engineBlended
}

enum VO2MaxTrend: String, Codable, Sendable {
    case improving
    case stable
    case declining
}

enum VO2MaxFitnessLevel: String, Codable, Sendable {
    case excellent
    case good
    case average
    case belowAverage
    case poor

    var title: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .average: return "Average"
        case .belowAverage: return "Below Average"
        case .poor: return "Poor"
        }
    }

    var localizedTitle: String {
        switch self {
        case .excellent: return "优秀"
        case .good: return "良好"
        case .average: return "一般"
        case .belowAverage: return "偏弱"
        case .poor: return "较低"
        }
    }
}

enum VO2MaxDriverDirection: String, Codable, Sendable {
    case positive
    case negative
    case neutral
}

struct VO2MaxDriver: Codable, Equatable, Sendable {
    let title: String
    let direction: VO2MaxDriverDirection
    let impact: Int
    let explanation: String
}

struct VO2MaxComponentBreakdown: Codable, Equatable, Sendable {
    let rhrComponent: Double?
    let hrvComponent: Double?
    let walkingEfficiencyComponent: Double?
    let runningEfficiencyComponent: Double?
    let recoveryComponent: Double?
    let finalWeightedScore: Double
}

struct VO2MaxInputCoverage: Codable, Equatable, Sendable {
    let actualVO2: Bool
    let rhr: Bool
    let hrv: Bool
    let walking: Bool
    let running: Bool
    let recovery: Bool
}

struct VO2MaxConfidenceBreakdown: Codable, Equatable, Sendable {
    let sourceScore: Int
    let coverageScore: Int
    let qualityScore: Int
    let finalScore: Int
}

struct VO2MaxDailyAssessment: Codable, Equatable, Sendable, Identifiable {
    static let currentAlgorithmVersion = "3.1"

    var id: Int64 { Int64(date.timeIntervalSince1970) }
    var algorithmVersion: String { Self.currentAlgorithmVersion }
    let date: Date
    let value: Double
    let source: VO2MaxSource
    let confidence: Int
    let trend: VO2MaxTrend
    let fitnessLevel: VO2MaxFitnessLevel
    let drivers: [VO2MaxDriver]
    let components: VO2MaxComponentBreakdown
    let inputs: VO2MaxInputCoverage
    let confidenceBreakdown: VO2MaxConfidenceBreakdown
    let summaryText: String
}

struct VO2MaxSessionAssessment: Equatable, Sendable, Identifiable {
    var id: Int64 { Int64(date.timeIntervalSince1970) }
    var algorithmVersion: String { VO2MaxDailyAssessment.currentAlgorithmVersion }
    let date: Date
    let value: Double
    let source: VO2MaxSource
    let confidence: Int
    let fitnessLevel: VO2MaxFitnessLevel
    let drivers: [VO2MaxDriver]
    let components: VO2MaxComponentBreakdown
    let inputs: VO2MaxInputCoverage
    let confidenceBreakdown: VO2MaxConfidenceBreakdown
    let summaryText: String
    let activityType: HKWorkoutActivityType?
}

struct VO2MaxBodyProfile: Codable, Equatable, Sendable {
    let age: Int?
    let sex: String?
    let heightCm: Double?
    let weightKg: Double?
}

struct VO2MaxWorkoutSample: Equatable, Sendable, Identifiable {
    let id: UUID
    let activityType: HKWorkoutActivityType
    let startDate: Date
    let endDate: Date
    let durationMinutes: Double
    let distanceKilometers: Double?
    let averageHeartRate: Double?
    let peakHeartRate: Double?
    let endHeartRate: Double?
    let paceSecondsPerKilometer: Double?
    let heartRateRecoveryOneMinute: Double?
    let heartRateRecoveryTwoMinute: Double?
}

struct WalkingFitnessInput: Equatable, Sendable {
    let speedMps: Double
    let paceSecondsPerKm: Double?
    let averageHeartRate: Double?
    let restingHeartRate: Double?
    let distanceKilometers: Double?
    let durationMinutes: Double?
    let baselineRatio: Double?
    let age: Int?
    let sex: String?
}

struct RunningFitnessInput: Equatable, Sendable {
    let paceSecondsPerKm: Double
    let averageHeartRate: Double
    let distanceKilometers: Double
    let durationMinutes: Double
    let baselineEfficiency: Double?
}

struct RecoveryFitnessInput: Equatable, Sendable {
    let sleepScore: Int?
    let nightlyHrv: Double?
    let recentNightlyHrvBaseline: Double?
    let nightlyAverageHeartRate: Double?
    let heartRateRecoveryOneMinute: Double?
}
