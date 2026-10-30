import Foundation

/// 所有强类型健康测量值共享的单位与原始数值契约。
nonisolated protocol HealthMeasurementValue: Codable, Equatable, Sendable {
    static var unit: HealthMetricUnit { get }
    var rawValue: Double { get }
}

/// Apple Health 的 HRV SDNN 值，单位为毫秒。
nonisolated struct HRVSDNNMilliseconds: Codable, Equatable, Hashable, Comparable, Sendable {
    static let validRange = 5.0...250.0
    static let unit = HealthMetricUnit.milliseconds

    let value: Double

    init?(_ value: Double) {
        guard value.isFinite, Self.validRange.contains(value) else { return nil }
        self.value = value
    }

    init?(_ value: Double?) {
        guard let value else { return nil }
        self.init(value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode(Double.self, forKey: .value)
        guard let value = Self(decoded) else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "HRV SDNN must be within \(Self.validRange)."
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    var rawValue: Double { value }

    private enum CodingKeys: String, CodingKey { case value }
}

extension HRVSDNNMilliseconds: HealthMeasurementValue {}

/// 心率值，单位为每分钟心跳次数；构造时拒绝非生理范围数据。
nonisolated struct HeartRateBPM: Codable, Equatable, Hashable, Comparable, Sendable {
    static let validRange = 25.0...220.0
    static let unit = HealthMetricUnit.beatsPerMinute

    let value: Double

    init?(_ value: Double) {
        guard value.isFinite, Self.validRange.contains(value) else { return nil }
        self.value = value
    }

    init?(_ value: Int) {
        self.init(Double(value))
    }

    init?(_ value: Int?) {
        guard let value else { return nil }
        self.init(value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode(Double.self, forKey: .value)
        guard let value = Self(decoded) else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Heart rate must be within \(Self.validRange) bpm."
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    var rawValue: Double { value }
    var roundedValue: Int { Int(value.rounded()) }

    private enum CodingKeys: String, CodingKey { case value }
}

extension HeartRateBPM: HealthMeasurementValue {}

/// 睡眠时长，单位为分钟；最大值限制为 16 小时。
nonisolated struct SleepDurationMinutes: Codable, Equatable, Hashable, Comparable, Sendable {
    static let validRange = 1...960
    static let unit = HealthMetricUnit.minutes

    let value: Int

    init?(_ value: Int) {
        guard Self.validRange.contains(value) else { return nil }
        self.value = value
    }

    init?(_ value: Int?) {
        guard let value else { return nil }
        self.init(value)
    }

    init?(_ value: Double) {
        guard value.isFinite else { return nil }
        self.init(Int(value.rounded()))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode(Int.self, forKey: .value)
        guard let value = Self(decoded) else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Sleep duration must be within \(Self.validRange) minutes."
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    var rawValue: Double { Double(value) }

    private enum CodingKeys: String, CodingKey { case value }
}

extension SleepDurationMinutes: HealthMeasurementValue {}

/// 确定性健康指标允许使用的单位集合。
nonisolated enum HealthMetricUnit: String, Codable, Sendable {
    case milliseconds = "ms"
    case beatsPerMinute = "bpm"
    case minutes = "min"
    case score

    var title: String { rawValue }
}

/// 携带单位约束的指标值，防止不同健康量纲被直接混用。
nonisolated enum HealthMetricTypedValue: Equatable, Sendable {
    case hrvSDNN(HRVSDNNMilliseconds)
    case beatsPerMinute(HeartRateBPM)
    case minutes(SleepDurationMinutes)
    case score(Double)

    var rawValue: Double {
        switch self {
        case .hrvSDNN(let value): return value.rawValue
        case .beatsPerMinute(let value): return value.rawValue
        case .minutes(let value): return value.rawValue
        case .score(let value): return value
        }
    }

    var unit: HealthMetricUnit {
        switch self {
        case .hrvSDNN: return .milliseconds
        case .beatsPerMinute: return .beatsPerMinute
        case .minutes: return .minutes
        case .score: return .score
        }
    }
}
