/// Health Kit Manager 负责健康数据访问与加工，管理 HealthKit 授权、查询和应用内可用数据的整理。
import Foundation
import HealthKit

enum HealthKitReadStatus: String, Sendable {
    case dataAvailable = "data_available"
    case noData = "no_data"
    case queryFailed = "query_failed"
}

enum HealthKitReadLog {
    static func message(metric: String, status _: HealthKitReadStatus) -> String {
        "[HealthKit] operation=read technicalID=\(metric)"
    }
}

/// 每次 HealthKit 查询完成后记录脱敏状态；不得传入样本值、数量或时间范围。
func logHealthKitRead(metric: String, status: HealthKitReadStatus) {
    print(HealthKitReadLog.message(metric: metric, status: status))
}

/// 健康套件错误枚举 作为健康数据能力层里的错误状态定义。
/// 负责描述健康数据读取与授权管理过程中会用到的状态、分类或分支。
enum HealthKitError: Error {
    case notAvailableOnDevice
    case dataTypeNotAvailable
    case authorizationFailed
    case dataFetchFailed
    case unsupportedOS
}

enum MedicationHealthSyncSupport: Sendable, Equatable {
    case unavailableOnDevice
    case unsupportedOS
    case available(status: HKAuthorizationStatus)

    var headline: String {
        switch self {
        case .unavailableOnDevice:
            return String(localized: "当前设备不支持健康数据")
        case .unsupportedOS:
            return String(localized: "当前系统暂不支持药物写入健康 App")
        case .available(let status):
            switch status {
            case .sharingAuthorized:
                return String(localized: "可同步到健康 App")
            case .sharingDenied:
                return String(localized: "健康 App 药物写入权限已关闭")
            case .notDetermined:
                return String(localized: "可申请同步到健康 App")
            @unknown default:
                return "健康 App 药物同步状态未知"
            }
        }
    }

    var detail: String {
        switch self {
        case .unavailableOnDevice:
            return String(localized: "这台设备当前无法使用 HealthKit，药物记录会先保存在眠屿内。")
        case .unsupportedOS:
            return String(localized: "Apple 的原生药物服用事件写入能力需要更高系统版本。当前版本会先保存在眠屿，并继续保留服药时间线。")
        case .available(let status):
            switch status {
            case .sharingAuthorized:
                return String(localized: "系统已允许写入药物记录。首次同步前，仍建议先在健康 App 里建立对应药物条目。")
            case .sharingDenied:
                return String(localized: "你可以在系统的健康权限设置里重新开启写入权限。")
            case .notDetermined:
                return String(localized: "当系统版本支持时，可以在健康权限弹窗中开启药物写入。")
            @unknown default:
                return String(localized: "系统版本支持药物写入，但当前无法确认权限状态。")
            }
        }
    }

    var timelineNote: String {
        switch self {
        case .unavailableOnDevice:
            return String(localized: "仅保存到眠屿：设备不支持健康数据。")
        case .unsupportedOS:
            return String(localized: "仅保存到眠屿：当前系统还不能把药物记录写入健康 App。")
        case .available(let status):
            switch status {
            case .sharingAuthorized:
                return String(localized: "系统已具备药物写入条件，后续可继续补健康 App 同步。")
            case .sharingDenied:
                return String(localized: "仅保存到眠屿：健康 App 药物写入权限已关闭。")
            case .notDetermined:
                return String(localized: "仅保存到眠屿：药物写入权限尚未申请。")
            @unknown default:
                return String(localized: "仅保存到眠屿：健康 App 药物同步状态未知。")
            }
        }
    }
}

/// 睡眠Interval结构体 作为健康数据能力层里的辅助类型。
/// 负责健康数据读取与授权管理。
struct SleepInterval: Sendable, Equatable {
    let start: Date
    let end: Date
}

/// 久坐健康结构体 作为健康数据能力层里的辅助类型。
/// 负责健康数据读取与授权管理。
struct SedentaryHealthState: Sendable, Equatable {
    /// Source Status 枚举，作为内部辅助类型，用于细分外层健康数据读取与授权管理中的状态或分支。
    enum SourceStatus: Sendable, Equatable {
        case ready
        case sleeping
        case needsAuthorization
        case noActivitySamples
        case unavailable
    }

    let seatedStartAt: Date?
    let lastActivityAt: Date?
    let elapsedMinutes: Int
    let isCounting: Bool
    let pausedBySleep: Bool
    let sourceStatus: SourceStatus
}

/// 久坐Timeline枚举 作为健康数据能力层里的状态与分类定义。
/// 负责久坐强度分层与展示语义。
enum SedentaryTimelineKind: String, Sendable, Equatable {
    case light
    case moderate
    case heavy
    case sleep

    var title: String {
        switch self {
        case .light:
            return String(localized: "短时久坐")
        case .moderate:
            return String(localized: "中度久坐")
        case .heavy:
            return String(localized: "重度久坐")
        case .sleep:
            return "睡眠"
        }
    }
}

/// 久坐Break枚举 作为健康数据能力层里的状态与分类定义。
/// 负责描述一次久坐被什么动作打断。
enum SedentaryBreakKind: String, Sendable, Equatable {
    case walking
    case exercise
    case standing

    var title: String {
        switch self {
        case .walking:
            return "步行"
        case .exercise:
            return "锻炼"
        case .standing:
            return "站立"
        }
    }

    var symbol: String {
        switch self {
        case .walking:
            return "figure.walk.motion"
        case .exercise:
            return "figure.run"
        case .standing:
            return "figure.stand"
        }
    }
}

/// 久坐Timeline数据模型 作为健康数据能力层里的数据载体。
/// 负责承载单段久坐区间的时间与强度信息。
struct SedentaryTimelineSegment: Identifiable, Sendable, Equatable {
    let start: Date
    let end: Date
    let durationMinutes: Int
    let kind: SedentaryTimelineKind
    let endingBreakKind: SedentaryBreakKind?
    let endingBreakMinutes: Int?
    let isOngoing: Bool

    var id: String {
        "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)-\(kind.rawValue)"
    }

    var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}

/// 久坐Day数据模型 作为健康数据能力层里的数据载体。
/// 负责承载某一天的久坐摘要、分布和时间轴数据。
struct SedentaryDaySummary: Identifiable, Sendable, Equatable {
    /// Source Status 枚举，负责标记当天摘要是正常可读还是处于异常/缺失状态。
    enum SourceStatus: Sendable, Equatable {
        case ready
        case needsAuthorization
        case noData
        case unavailable
    }

    let date: Date
    let sessions: [SedentaryTimelineSegment]
    let totalSedentaryMinutes: Int
    let activeBreakCount: Int
    let totalReliefMinutes: Int
    let longestSessionMinutes: Int
    let sourceStatus: SourceStatus
    let lastBreakKind: SedentaryBreakKind?
    let updatedAt: Date

    var id: TimeInterval { date.timeIntervalSince1970 }

    static func placeholder(on date: Date, status: SourceStatus, updatedAt: Date = Date()) -> SedentaryDaySummary {
        SedentaryDaySummary(
            date: date,
            sessions: [],
            totalSedentaryMinutes: 0,
            activeBreakCount: 0,
            totalReliefMinutes: 0,
            longestSessionMinutes: 0,
            sourceStatus: status,
            lastBreakKind: nil,
            updatedAt: updatedAt
        )
    }

    var lightMinutes: Int {
        sessions
            .filter { $0.kind == .light }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    var moderateMinutes: Int {
        sessions
            .filter { $0.kind == .moderate }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    var heavyMinutes: Int {
        sessions
            .filter { $0.kind == .heavy }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    var sleepMinutes: Int {
        sessions
            .filter { $0.kind == .sleep }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    var dominantKind: SedentaryTimelineKind? {
        let buckets: [(SedentaryTimelineKind, Int)] = [
            (.light, lightMinutes),
            (.moderate, moderateMinutes),
            (.heavy, heavyMinutes)
        ]
        return buckets.max(by: { $0.1 < $1.1 })?.1 == 0 ? nil : buckets.max(by: { $0.1 < $1.1 })?.0
    }

    var focusSession: SedentaryTimelineSegment? {
        let sedentarySessions = sessions.filter { $0.kind != .sleep }
        return sedentarySessions.last(where: \.isOngoing)
            ?? sedentarySessions.max(by: { $0.durationMinutes < $1.durationMinutes })
            ?? sedentarySessions.last
    }

    var averageReliefMinutes: Int {
        guard activeBreakCount > 0 else { return 0 }
        return Int((Double(totalReliefMinutes) / Double(activeBreakCount)).rounded())
    }

    var walkingBreakCount: Int {
        sessions.filter { $0.endingBreakKind == .walking }.count
    }

    var exerciseBreakCount: Int {
        sessions.filter { $0.endingBreakKind == .exercise }.count
    }

    var standingBreakCount: Int {
        sessions.filter { $0.endingBreakKind == .standing }.count
    }

    var dominantBreakKind: SedentaryBreakKind? {
        let buckets: [(SedentaryBreakKind, Int)] = [
            (.walking, walkingBreakCount),
            (.exercise, exerciseBreakCount),
            (.standing, standingBreakCount)
        ]
        return buckets.max(by: { $0.1 < $1.1 })?.1 == 0 ? nil : buckets.max(by: { $0.1 < $1.1 })?.0
    }

    static let sedentaryDaypartTitles = ["上午", "中午", "下午", "晚上"]

    static func sedentaryDaypartTitle(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 6..<11:
            return String(localized: "上午")
        case 11..<14:
            return String(localized: "中午")
        case 14..<18:
            return "下午"
        default:
            return "晚上"
        }
    }

    static func sedentaryDaypartDistribution(
        for summaries: [SedentaryDaySummary],
        calendar: Calendar = .current
    ) -> [SedentaryDaypartBucket] {
        var buckets = sedentaryDaypartTitles.reduce(into: [String: (minutes: Int, sessionCount: Int)]()) {
            $0[$1] = (minutes: 0, sessionCount: 0)
        }

        summaries
            .filter { $0.sourceStatus == .ready }
            .flatMap(\.sessions)
            .filter { $0.kind != .sleep && $0.end > $0.start }
            .forEach { session in
                for overlap in sedentaryDaypartOverlaps(for: session, calendar: calendar) where overlap.minutes > 0 {
                    let current = buckets[overlap.title] ?? (minutes: 0, sessionCount: 0)
                    buckets[overlap.title] = (
                        minutes: current.minutes + overlap.minutes,
                        sessionCount: current.sessionCount + 1
                    )
                }
            }

        return sedentaryDaypartTitles.map { title in
            let bucket = buckets[title] ?? (minutes: 0, sessionCount: 0)
            return SedentaryDaypartBucket(
                title: title,
                minutes: bucket.minutes,
                sessionCount: bucket.sessionCount
            )
        }
    }

    static func preferredSedentaryDaypart(
        in summaries: [SedentaryDaySummary],
        calendar: Calendar = .current
    ) -> SedentaryDaypartBucket? {
        sedentaryDaypartDistribution(for: summaries, calendar: calendar)
            .filter { $0.minutes > 0 }
            .max(by: { $0.minutes < $1.minutes })
    }

    private static func sedentaryDaypartOverlaps(
        for session: SedentaryTimelineSegment,
        calendar: Calendar
    ) -> [(title: String, minutes: Int)] {
        var cursor = session.start
        var overlaps: [(title: String, minutes: Int)] = []

        while cursor < session.end {
            let boundary = nextSedentaryDaypartBoundary(after: cursor, calendar: calendar)
            let end = min(boundary, session.end)
            let minutes = max(0, Int(end.timeIntervalSince(cursor) / 60))
            if minutes > 0 {
                overlaps.append((title: sedentaryDaypartTitle(for: cursor, calendar: calendar), minutes: minutes))
            }
            guard end > cursor else { break }
            cursor = end
        }

        return overlaps
    }

    private static func nextSedentaryDaypartBoundary(after date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)

        if hour >= 18 {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date.addingTimeInterval(24 * 60 * 60)
            return calendar.date(bySettingHour: 6, minute: 0, second: 0, of: nextDay) ?? nextDay
        }

        let boundaryHour: Int
        switch hour {
        case 0..<6:
            boundaryHour = 6
        case 6..<11:
            boundaryHour = 11
        case 11..<14:
            boundaryHour = 14
        default:
            boundaryHour = 18
        }

        return calendar.date(bySettingHour: boundaryHour, minute: 0, second: 0, of: dayStart) ?? date
    }
}

struct SedentaryDaypartBucket: Sendable, Equatable {
    let title: String
    let minutes: Int
    let sessionCount: Int
}

func sedentaryEffectiveStart(
    startOfDay: Date,
    lastActivityAt: Date?,
    lastSleepEndAt: Date?
) -> Date {
    let boundaries = [startOfDay, lastActivityAt, lastSleepEndAt].compactMap { $0 }
    return boundaries.max() ?? startOfDay
}

func sedentaryAwakeSegments(
    dayStart: Date,
    dayEnd: Date,
    excludedIntervals: [DateInterval]
) -> [DateInterval] {
    guard dayStart < dayEnd else { return [] }

    let normalizedExclusions = excludedIntervals
        .map { interval in
            let start = max(dayStart, interval.start)
            let end = min(dayEnd, interval.end)
            return DateInterval(start: start, end: end)
        }
        .filter { $0.start < $0.end }
        .sorted { $0.start < $1.start }
        .reduce(into: [DateInterval]()) { partial, interval in
            guard let last = partial.last else {
                partial.append(interval)
                return
            }

            if interval.start <= last.end {
                partial[partial.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                partial.append(interval)
            }
        }

    guard !normalizedExclusions.isEmpty else {
        return [DateInterval(start: dayStart, end: dayEnd)]
    }

    var segments: [DateInterval] = []
    var cursor = dayStart

    for excluded in normalizedExclusions {
        if cursor < excluded.start {
            segments.append(DateInterval(start: cursor, end: excluded.start))
        }
        cursor = max(cursor, excluded.end)
    }

    if cursor < dayEnd {
        segments.append(DateInterval(start: cursor, end: dayEnd))
    }

    return segments
}

/// WorkoutDay数据模型 作为健康数据能力层里的数据载体。
/// 负责健康数据读取与授权管理。
struct WorkoutDaySummary: Sendable, Equatable, Identifiable {
    let date: Date
    let totalMinutes: Int
    let totalEnergyKilocalories: Int?
    let totalDistanceKilometers: Double?
    let dominantWorkoutTitle: String?
    let durationMinutesByWorkoutTitle: [String: Double]
    let workoutCount: Int
    /// 当天主训练为游泳时，保留时长最长的一次游泳训练明细供专属报告展示。
    var swimmingReport: SwimmingWorkoutReport? = nil
    /// 当天部分训练缺能量测量值（如手动记录），总和只覆盖有测量的部分。
    var hasPartialEnergyData: Bool = false
    /// 当天部分训练缺距离测量值，总和只覆盖有测量的部分。
    var hasPartialDistanceData: Bool = false

    var id: TimeInterval { date.timeIntervalSince1970 }
}

/// 单次训练会话，保留 HealthKit workout 的真实时间和可用测量值。
/// 趋势日视图直接使用这个值类型，避免把按天聚合的数据误当成日内记录。
struct WorkoutSessionSummary: Sendable, Hashable, Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let activityTitle: String
    let durationMinutes: Double
    let activeEnergyKilocalories: Double?
    let distanceKilometers: Double?
    let swimmingReport: SwimmingWorkoutReport?
    /// iOS 27+ 由 HealthKit 计算并随 workout 保存的心率/骑行功率区间。
    let zoneSummaries: [WorkoutZoneSummary]
}

enum SwimmingLocation: String, Sendable, Hashable {
    case pool
    case openWater
    case unknown
}

enum SwimmingStroke: String, Sendable, Hashable, CaseIterable {
    case mixed
    case freestyle
    case backstroke
    case breaststroke
    case butterfly
    case kickboard
    case unknown

    var title: String {
        switch self {
        case .mixed: return String(localized: "混合泳姿")
        case .freestyle: return String(localized: "自由泳")
        case .backstroke: return String(localized: "仰泳")
        case .breaststroke: return String(localized: "蛙泳")
        case .butterfly: return String(localized: "蝶泳")
        case .kickboard: return String(localized: "浮板")
        case .unknown: return String(localized: "未识别泳姿")
        }
    }
}

struct SwimmingLapReport: Sendable, Hashable, Identifiable {
    let index: Int
    let duration: TimeInterval
    let distanceMeters: Double?
    let stroke: SwimmingStroke
    /// Only populated when HealthKit exposes a count that can be tied to this exact lap.
    let strokeCount: Int?

    var id: Int { index }

    init(
        index: Int,
        duration: TimeInterval,
        distanceMeters: Double?,
        stroke: SwimmingStroke,
        strokeCount: Int? = nil
    ) {
        self.index = index
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.stroke = stroke
        self.strokeCount = strokeCount
    }

    var paceSecondsPer100Meters: Double? {
        SwimmingMetricsCalculator.paceSecondsPer100Meters(
            duration: duration,
            distanceMeters: distanceMeters
        )
    }

    /// SWOLF is derived only when the exact lap duration and stroke count are both available.
    var swolfScore: Int? {
        guard duration > 0, let strokeCount, strokeCount > 0 else { return nil }
        return Int((duration + Double(strokeCount)).rounded())
    }
}

/// 单次游泳训练的 HealthKit 原始报告。所有可选值缺失时均由 UI 明确降级，不补估算数据。
struct SwimmingWorkoutReport: Sendable, Hashable {
    let workoutID: UUID
    let startDate: Date
    let endDate: Date
    /// The HealthKit device that produced this workout, when available.
    let deviceName: String?
    /// HealthKit's recording duration. Unlike the start/end interval, this excludes pause time.
    let duration: TimeInterval
    let location: SwimmingLocation
    let poolLengthMeters: Double?
    let distanceMeters: Double?
    let strokeCount: Int?
    /// Energy stored on this exact HealthKit workout, not the aggregate for its calendar day.
    let activeEnergyKilocalories: Double?
    /// HealthKit's workout-level SWOLF metadata, when the source workout provides it.
    let healthKitSWOLFScore: Int?
    let laps: [SwimmingLapReport]

    init(
        workoutID: UUID,
        startDate: Date,
        endDate: Date,
        deviceName: String? = nil,
        duration: TimeInterval,
        location: SwimmingLocation,
        poolLengthMeters: Double?,
        distanceMeters: Double?,
        strokeCount: Int?,
        activeEnergyKilocalories: Double? = nil,
        healthKitSWOLFScore: Int? = nil,
        laps: [SwimmingLapReport]
    ) {
        self.workoutID = workoutID
        self.startDate = startDate
        self.endDate = endDate
        self.deviceName = deviceName
        self.duration = duration.isFinite && duration >= 0 ? duration : 0
        self.location = location
        self.poolLengthMeters = poolLengthMeters
        self.distanceMeters = distanceMeters
        self.strokeCount = strokeCount
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.healthKitSWOLFScore = healthKitSWOLFScore
        self.laps = laps
    }

    var dominantStroke: SwimmingStroke? {
        let knownLaps = laps.filter { $0.stroke != .unknown }
        guard !knownLaps.isEmpty else { return nil }
        return Dictionary(grouping: knownLaps, by: \.stroke)
            .max { lhs, rhs in
                lhs.value.reduce(0) { $0 + $1.duration } < rhs.value.reduce(0) { $0 + $1.duration }
            }?.key
    }

    var averagePaceSecondsPer100Meters: Double? {
        SwimmingMetricsCalculator.paceSecondsPer100Meters(
            duration: duration,
            distanceMeters: distanceMeters
        )
    }

    var strokesPerMinute: Double? {
        SwimmingMetricsCalculator.strokesPerMinute(
            strokeCount: strokeCount,
            duration: duration
        )
    }

    var swolfScore: Int? {
        guard location == .pool else { return nil }
        if let healthKitSWOLFScore, healthKitSWOLFScore > 0 {
            return healthKitSWOLFScore
        }
        let scores = laps.compactMap(\.swolfScore)
        // Never label a partial set of measured lap scores as the workout average.
        guard !laps.isEmpty, scores.count == laps.count, !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }
}

/// HealthKit 训练区间配置的来源，避免把 iOS 27 类型泄漏到业务与展示层。
enum WorkoutZoneConfigurationSource: String, Sendable, Hashable {
    case system
    case user
    case app
}

enum WorkoutZoneMetric: String, Sendable, Hashable {
    case heartRate
    case cyclingPower
}

/// 单个训练区间及其累计停留时间；边界单位由所属摘要的 metric 决定。
struct WorkoutZone: Sendable, Hashable, Identifiable {
    let index: Int
    let duration: TimeInterval
    let minimumValue: Double?
    let maximumValue: Double?

    var id: Int { index }
}

/// 单次训练的 HealthKit 原生心率或骑行功率区间摘要。
struct WorkoutZoneSummary: Sendable, Hashable, Identifiable {
    let metric: WorkoutZoneMetric
    let source: WorkoutZoneConfigurationSource
    let zones: [WorkoutZone]

    var id: WorkoutZoneMetric { metric }

    var totalDuration: TimeInterval {
        zones.reduce(0) { $0 + max(0, $1.duration) }
    }

    var dominantZone: WorkoutZone? {
        zones.max {
            if $0.duration == $1.duration { return $0.index < $1.index }
            return $0.duration < $1.duration
        }
    }
}

struct LatestWorkoutContext: Sendable, Equatable {
    let isActive: Bool
    let activityType: HKWorkoutActivityType?
    let totalMinutes: Int
    let endedAt: Date?
}

struct HealthPhysicalEffortSample: Sendable, Equatable {
    let startDate: Date
    let endDate: Date
    let metabolicEquivalent: Double
}

struct HealthWorkoutEffortSample: Sendable, Equatable {
    let workoutID: UUID
    let endedAt: Date
    let durationMinutes: Double
    let score: Double
    let isEstimated: Bool
}

/// Vo2最大数据模型 作为健康数据能力层里的数据载体。
/// 负责健康数据读取与授权管理。
struct Vo2MaxSnapshot: Sendable, Equatable {
    let value: Double
    let isEstimated: Bool
}

/// 心率ECGSample结构体 作为健康数据能力层里的辅助类型。
/// 负责健康数据读取与授权管理。
struct HeartECGSample: Sendable, Equatable {
    let id: UUID
    let sampledAt: Date
    let classification: String
    let averageHeartRate: Double?
    let symptomsStatus: String
    let samplingFrequencyHz: Double?
    let voltageMeasurements: [HeartECGVoltageMeasurement]
}

/// 心率ECGVoltageMeasurement结构体 作为健康数据能力层里的辅助类型。
/// 负责健康数据读取与授权管理。
struct HeartECGVoltageMeasurement: Sendable, Equatable {
    let timeSinceSampleStart: Double
    let millivolts: Double
}

/// 健康套件管理器 作为健康数据能力层里的服务或调度入口。
/// 负责健康数据读取与授权管理。
final class HealthKitManager {
    static let shared = HealthKitManager()
    
    let healthStore = HKHealthStore()
    private var didRegisterObservers = false
    private let observerLock = NSLock()

    private struct SedentaryActivityEvent {
        let date: Date
        let kind: SedentaryBreakKind
        let estimatedReliefMinutes: Int
    }
    
    private init() {}
    
    /// 方法说明：负责健康数据读取、转换或授权管理。
    func isHealthDataSupported() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    /// 方法说明：负责健康数据读取、转换或授权管理。
    func isLikelyAuthorized() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        return authorizationProbeTypes.contains {
            healthStore.authorizationStatus(for: $0) == .sharingAuthorized
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func authorizationStatus(for identifier: HKQuantityTypeIdentifier) -> HKAuthorizationStatus? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return healthStore.authorizationStatus(for: type)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func authorizationStatus(for identifier: HKCategoryTypeIdentifier) -> HKAuthorizationStatus? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: identifier) else {
            return nil
        }
        return healthStore.authorizationStatus(for: type)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func authorizationStatusForCategory(rawValue: String) -> HKAuthorizationStatus? {
        guard HKHealthStore.isHealthDataAvailable(),
              let identifier = resolvedCategoryIdentifier(from: rawValue),
              let type = HKObjectType.categoryType(forIdentifier: identifier) else {
            return nil
        }
        return healthStore.authorizationStatus(for: type)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func authorizationStatusForQuantity(rawValue: String) -> HKAuthorizationStatus? {
        guard HKHealthStore.isHealthDataAvailable(),
              let identifier = resolvedQuantityIdentifier(from: rawValue),
              let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return healthStore.authorizationStatus(for: type)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func authorizationStatus(for objectType: HKObjectType) -> HKAuthorizationStatus? {
        guard HKHealthStore.isHealthDataAvailable() else {
            return nil
        }
        return healthStore.authorizationStatus(for: objectType)
    }

    func authorizationStatus(for scoredAssessmentIdentifier: HKScoredAssessmentTypeIdentifier) -> HKAuthorizationStatus? {
        guard HKHealthStore.isHealthDataAvailable() else {
            return nil
        }
        let type = HKScoredAssessmentType(scoredAssessmentIdentifier)
        return healthStore.authorizationStatus(for: type)
    }

    func medicationHealthSyncSupport() -> MedicationHealthSyncSupport {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailableOnDevice
        }

        if #available(iOS 26.0, *) {
            let medicationType = HKObjectType.medicationDoseEventType()
            let status = healthStore.authorizationStatus(for: medicationType)
            return .available(status: status)
        }

        return .unsupportedOS
    }
    
    /// 一次申请当前版本支持的全部 HealthKit 读写类型。
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }

        let authorizationTypes = try makeAuthorizationTypes()

        do {
            try await healthStore.requestAuthorization(
                toShare: authorizationTypes.typesToShare,
                read: authorizationTypes.typesToRead
            )
            HealthAuthorizationPreferences.markFlowCompleted()
            // 授权内容或权限状态变化后，旧派生缓存不得继续命中。
            HealthKitRepositoryCache.shared.invalidateAll()
        } catch {
            throw HealthKitError.authorizationFailed
        }
    }

    /// 查询全部读写类型的系统授权请求状态（启动流程用）。
    /// shouldRequest 表示系统弹窗仍然可用（首次授权或版本更新新增了数据类型）；
    /// unnecessary 表示弹窗已被消耗，再调 requestAuthorization 不会有任何界面反馈。
    func fullAuthorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        guard HKHealthStore.isHealthDataAvailable(),
              let authorizationTypes = try? makeAuthorizationTypes() else {
            return .unknown
        }

        return await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: authorizationTypes.typesToShare,
                read: authorizationTypes.typesToRead
            ) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    /// 方法说明：读探针——在核心类型里尝试取最近样本，验证授权后数据是否真的可读。
    /// 命中任一类型即返回 true；全部取不到时可能是读权限被关闭，也可能是数据源为空。
    func probeReadableSampleExists(withinDays days: Int = 7) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        var probeTypes: [HKSampleType] = []
        if let stepType = HKSampleType.quantityType(forIdentifier: .stepCount) {
            probeTypes.append(stepType)
        }
        if let heartRateType = HKSampleType.quantityType(forIdentifier: .heartRate) {
            probeTypes.append(heartRateType)
        }
        if let hrvType = HKSampleType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            probeTypes.append(hrvType)
        }
        if let sleepType = HKSampleType.categoryType(forIdentifier: .sleepAnalysis) {
            probeTypes.append(sleepType)
        }
        if let activeEnergyType = HKSampleType.quantityType(forIdentifier: .activeEnergyBurned) {
            probeTypes.append(activeEnergyType)
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())
            ?? Date().addingTimeInterval(-Double(days) * 86_400)
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: [])

        for sampleType in probeTypes {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.sample(type: sampleType, predicate: datePredicate)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            if let samples = try? await descriptor.result(for: healthStore), !samples.isEmpty {
                return true
            }
        }

        return false
    }

    private var authorizationProbeTypes: [HKObjectType] {
        var probes: [HKObjectType] = []

        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            probes.append(heartRateType)
        }
        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            probes.append(hrvType)
        }
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            probes.append(sleepType)
        }
        if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            probes.append(stepType)
        }
        if let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            probes.append(activeEnergyType)
        }
        if let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
            probes.append(standType)
        }
        if let walkingSpeedType = HKObjectType.quantityType(forIdentifier: .walkingSpeed) {
            probes.append(walkingSpeedType)
        }
        if let walkingStepLengthType = HKObjectType.quantityType(forIdentifier: .walkingStepLength) {
            probes.append(walkingStepLengthType)
        }
        if let walkingDoubleSupportType = HKObjectType.quantityType(forIdentifier: .walkingDoubleSupportPercentage) {
            probes.append(walkingDoubleSupportType)
        }
        if let stairAscentSpeedType = HKObjectType.quantityType(forIdentifier: .stairAscentSpeed) {
            probes.append(stairAscentSpeedType)
        }
        if let stairDescentSpeedType = HKObjectType.quantityType(forIdentifier: .stairDescentSpeed) {
            probes.append(stairDescentSpeedType)
        }
        if let walkingSteadinessType = HKObjectType.quantityType(forIdentifier: .appleWalkingSteadiness) {
            probes.append(walkingSteadinessType)
        }
        if let walkingAsymmetryType = HKObjectType.quantityType(forIdentifier: .walkingAsymmetryPercentage) {
            probes.append(walkingAsymmetryType)
        }
        if let walkingHeartRateType = HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage) {
            probes.append(walkingHeartRateType)
        }
        if let environmentalAudioType = HKObjectType.quantityType(forIdentifier: .environmentalAudioExposure) {
            probes.append(environmentalAudioType)
        }
        if let headphoneAudioType = HKObjectType.quantityType(forIdentifier: .headphoneAudioExposure) {
            probes.append(headphoneAudioType)
        }
        probes.append(HKObjectType.workoutType())

        return probes
    }

#if DEBUG
    /// Debug 专用：返回 App 实际申请读取的全部 HealthKit 类型。
    /// 仅供 Dashboard 首次进入时的本地控制台原始数据打印使用，Release 构建不包含。
    func debugAuthorizationReadTypes() -> Set<HKObjectType> {
        guard HKHealthStore.isHealthDataAvailable(),
              let authorizationTypes = try? makeAuthorizationTypes() else {
            return []
        }
        return authorizationTypes.typesToRead
    }
#endif

    /// 组装当前版本完整的读写授权集合，所有手动授权入口共用同一份清单。
    private func makeAuthorizationTypes() throws -> (typesToRead: Set<HKObjectType>, typesToShare: Set<HKSampleType>) {
        var typesToRead: Set<HKObjectType> = []
        var typesToShare: Set<HKSampleType> = []

        try appendCoreAuthorizationTypes(read: &typesToRead, share: &typesToShare)
        appendReproductiveHealthAuthorizationTypes(read: &typesToRead, share: &typesToShare)
        appendNutritionAuthorizationTypes(read: &typesToRead)

        guard !typesToRead.isEmpty else {
            throw HealthKitError.dataTypeNotAvailable
        }
        return (typesToRead, typesToShare)
    }

    /// 核心域：睡眠、心肺、活动、身体测量、正念与饮水/咖啡因习惯等启动即需的类型。
    private func appendCoreAuthorizationTypes(
        read typesToRead: inout Set<HKObjectType>,
        share typesToShare: inout Set<HKSampleType>
    ) throws {
        // 只申请业务实际消费的类型；全项目未使用的 niche 类型（皮电、NikeFuel、
        // 潜水深度、血酒精、胰岛素、小众运动速度等）不再请求，避免授权面板臃肿。
        appendQuantityTypes([
            "AppleSleepingWristTemperature",
            "BodyFatPercentage",
            "BodyMass",
            "BodyMassIndex",
            "Height",
            "LeanBodyMass",
            "WaistCircumference",
            "ActiveEnergyBurned",
            "AppleExerciseTime",
            "AppleMoveTime",
            "AppleStandTime",
            "BasalEnergyBurned",
            "CyclingCadence",
            "CyclingPower",
            "CyclingSpeed",
            "DistanceCrossCountrySkiing",
            "DistanceCycling",
            "DistanceDownhillSnowSports",
            "DistancePaddleSports",
            "DistanceRowing",
            "DistanceSkatingSports",
            "DistanceSwimming",
            "SwimmingStrokeCount",
            "DistanceWalkingRunning",
            "DistanceWheelchair",
            "EstimatedWorkoutEffortScore",
            "FlightsClimbed",
            "PhysicalEffort",
            "RunningPower",
            "RunningSpeed",
            "StepCount",
            "WorkoutEffortScore",
            "EnvironmentalAudioExposure",
            "EnvironmentalSoundReduction",
            "HeadphoneAudioExposure",
            "AtrialFibrillationBurden",
            "HeartRate",
            "HeartRateRecoveryOneMinute",
            "HeartRateVariabilitySDNN",
            "PeripheralPerfusionIndex",
            "RestingHeartRate",
            "VO2Max",
            "WalkingHeartRateAverage",
            "AppleWalkingSteadiness",
            "RunningGroundContactTime",
            "RunningStrideLength",
            "RunningVerticalOscillation",
            "SixMinuteWalkTestDistance",
            "StairAscentSpeed",
            "StairDescentSpeed",
            "WalkingAsymmetryPercentage",
            "WalkingDoubleSupportPercentage",
            "WalkingSpeed",
            "WalkingStepLength",
            "DietaryCaffeine",
            "DietaryWater",
            "BloodPressureDiastolic",
            "BloodPressureSystolic",
            "NumberOfAlcoholicBeverages",
            "NumberOfTimesFallen",
            "TimeInDaylight",
            "AppleSleepingBreathingDisturbances",
            "ForcedExpiratoryVolume1",
            "ForcedVitalCapacity",
            "InhalerUsage",
            "OxygenSaturation",
            "PeakExpiratoryFlowRate",
            "RespiratoryRate",
            "BloodGlucose",
            "BodyTemperature"
        ], to: &typesToRead)

        appendCategoryTypes([
            "AppleStandHour",
            "EnvironmentalAudioExposureEvent",
            "HeadphoneAudioExposureEvent",
            "HighHeartRateEvent",
            "HypertensionEvent",
            "IrregularHeartRhythmEvent",
            "LowCardioFitnessEvent",
            "LowHeartRateEvent",
            "MindfulSession",
            "AppleWalkingSteadinessEvent",
            "HandwashingEvent",
            "ToothbrushingEvent",
            "SleepApneaEvent",
            "SleepAnalysis",
            "AbdominalCramps",
            "Acne",
            "AppetiteChanges",
            "BladderIncontinence",
            "Bloating",
            "BreastPain",
            "ChestTightnessOrPain",
            "Chills",
            "Constipation",
            "Coughing",
            "Diarrhea",
            "Dizziness",
            "DrySkin",
            "Fainting",
            "Fatigue",
            "Fever",
            "GeneralizedBodyAche",
            "HairLoss",
            "Headache",
            "Heartburn",
            "HotFlashes",
            "LossOfSmell",
            "LossOfTaste",
            "LowerBackPain",
            "MemoryLapse",
            "MoodChanges",
            "Nausea",
            "NightSweats",
            "PelvicPain",
            "RapidPoundingOrFlutteringHeartbeat",
            "RunnyNose",
            "ShortnessOfBreath",
            "SinusCongestion",
            "SkippedHeartbeat",
            "SleepChanges",
            "SoreThroat",
            "VaginalDryness",
            "Vomiting",
            "Wheezing"
        ], to: &typesToRead)

        appendCharacteristicTypes([
            "ActivityMoveMode",
            "BiologicalSex",
            "BloodType",
            "DateOfBirth",
            "FitzpatrickSkinType",
            "WheelchairUse"
        ], to: &typesToRead)

        typesToRead.insert(HKObjectType.workoutType())
        typesToRead.insert(HKObjectType.activitySummaryType())

        typesToRead.insert(HKObjectType.audiogramSampleType())
        if let workoutRouteType = HKObjectType.seriesType(forIdentifier: "HKWorkoutRouteTypeIdentifier") {
            typesToRead.insert(workoutRouteType)
        }
        if let heartbeatSeriesType = HKObjectType.seriesType(forIdentifier: "HKDataTypeIdentifierHeartbeatSeries") {
            typesToRead.insert(heartbeatSeriesType)
        }
        typesToRead.insert(HKObjectType.electrocardiogramType())
        typesToRead.insert(HKObjectType.stateOfMindType())
        appendScoredAssessmentTypes([
            "GAD7",
            "PHQ9"
        ], to: &typesToRead)
        guard let mindfulSessionType = HKObjectType.categoryType(forIdentifier: .mindfulSession),
              let dietaryWaterType = HKObjectType.quantityType(forIdentifier: .dietaryWater),
              let dietaryCaffeineType = HKObjectType.quantityType(forIdentifier: .dietaryCaffeine) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        typesToShare.formUnion([mindfulSessionType, dietaryWaterType, dietaryCaffeineType])
        typesToShare.insert(HKObjectType.workoutType())
        // 健身详情页可编辑运动距离并写回健康 App，需要步行+跑步距离的写入权限。
        if let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            typesToShare.insert(distanceType)
        }
        // 健身详情页可同步当日心情到健康 App 的“心理状态”。
        typesToShare.insert(HKObjectType.stateOfMindType())
        if let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            typesToShare.insert(bodyMassType)
        }
        if let heightType = HKObjectType.quantityType(forIdentifier: .height) {
            typesToShare.insert(heightType)
        }
        if let bodyMassIndexType = HKObjectType.quantityType(forIdentifier: .bodyMassIndex) {
            typesToShare.insert(bodyMassIndexType)
        }
    }

    /// 生育健康域：经期/孕期读取与快捷记录写入，进入对应模块时再申请。
    private func appendReproductiveHealthAuthorizationTypes(
        read typesToRead: inout Set<HKObjectType>,
        share typesToShare: inout Set<HKSampleType>
    ) {
        appendQuantityTypes(["BasalBodyTemperature"], to: &typesToRead)
        appendCategoryTypes([
            "BleedingAfterPregnancy",
            "BleedingDuringPregnancy",
            "CervicalMucusQuality",
            "Contraceptive",
            "InfrequentMenstrualCycles",
            "IntermenstrualBleeding",
            "IrregularMenstrualCycles",
            "Lactation",
            "MenstrualFlow",
            "OvulationTestResult",
            "PersistentIntermenstrualBleeding",
            "Pregnancy",
            "PregnancyTestResult",
            "ProgesteroneTestResult",
            "ProlongedMenstrualPeriods",
            "SexualActivity"
        ], to: &typesToRead)

        // 经期快捷记录会把这些结果写回健康 App。
        let shareIdentifiers: [HKCategoryTypeIdentifier] = [
            .menstrualFlow,
            .sexualActivity,
            .intermenstrualBleeding,
            .ovulationTestResult,
            .cervicalMucusQuality,
            .pregnancyTestResult,
            .abdominalCramps,
            .moodChanges
        ]
        for identifier in shareIdentifiers {
            if let type = HKObjectType.categoryType(forIdentifier: identifier) {
                typesToShare.insert(type)
            }
        }
    }

    /// 膳食营养域：微量营养素读取，上线营养分析功能时再申请。
    private func appendNutritionAuthorizationTypes(read typesToRead: inout Set<HKObjectType>) {
        appendQuantityTypes([
            "DietaryBiotin",
            "DietaryCalcium",
            "DietaryCarbohydrates",
            "DietaryChloride",
            "DietaryCholesterol",
            "DietaryChromium",
            "DietaryCopper",
            "DietaryEnergyConsumed",
            "DietaryFatMonounsaturated",
            "DietaryFatPolyunsaturated",
            "DietaryFatSaturated",
            "DietaryFatTotal",
            "DietaryFiber",
            "DietaryFolate",
            "DietaryIodine",
            "DietaryIron",
            "DietaryMagnesium",
            "DietaryManganese",
            "DietaryMolybdenum",
            "DietaryNiacin",
            "DietaryPantothenicAcid",
            "DietaryPhosphorus",
            "DietaryPotassium",
            "DietaryProtein",
            "DietaryRiboflavin",
            "DietarySelenium",
            "DietarySodium",
            "DietarySugar",
            "DietaryThiamin",
            "DietaryVitaminA",
            "DietaryVitaminB12",
            "DietaryVitaminB6",
            "DietaryVitaminC",
            "DietaryVitaminD",
            "DietaryVitaminE",
            "DietaryVitaminK",
            "DietaryZinc"
        ], to: &typesToRead)
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    private func appendQuantityTypes(_ suffixes: [String], to set: inout Set<HKObjectType>) {
        for suffix in suffixes {
            let identifier = HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifier\(suffix)")
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                set.insert(type)
            }
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    private func appendCategoryTypes(_ suffixes: [String], to set: inout Set<HKObjectType>) {
        for suffix in suffixes {
            let identifier = HKCategoryTypeIdentifier(rawValue: "HKCategoryTypeIdentifier\(suffix)")
            if let type = HKObjectType.categoryType(forIdentifier: identifier) {
                set.insert(type)
            }
        }
    }

    // 趋势页有时会传事件简写，有时会传完整 HealthKit 标识，这里统一做一层兜底映射。
    /// 方法说明：负责健康数据读取、转换或授权管理。
    private func resolvedCategoryIdentifier(from rawValue: String) -> HKCategoryTypeIdentifier? {
        let candidates = [
            rawValue,
            "HKCategoryTypeIdentifier\(rawValue)"
        ]

        for candidate in candidates {
            let identifier = HKCategoryTypeIdentifier(rawValue: candidate)
            if HKObjectType.categoryType(forIdentifier: identifier) != nil {
                return identifier
            }
        }

        return nil
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    private func resolvedQuantityIdentifier(from rawValue: String) -> HKQuantityTypeIdentifier? {
        let candidates = [
            rawValue,
            "HKQuantityTypeIdentifier\(rawValue)"
        ]

        for candidate in candidates {
            let identifier = HKQuantityTypeIdentifier(rawValue: candidate)
            if HKObjectType.quantityType(forIdentifier: identifier) != nil {
                return identifier
            }
        }

        return nil
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    private func appendCharacteristicTypes(_ suffixes: [String], to set: inout Set<HKObjectType>) {
        for suffix in suffixes {
            let identifier = HKCharacteristicTypeIdentifier(rawValue: "HKCharacteristicTypeIdentifier\(suffix)")
            if let type = HKObjectType.characteristicType(forIdentifier: identifier) {
                set.insert(type)
            }
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    static func authorizationText(for status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return String(localized: "未决定")
        case .sharingDenied:
            return String(localized: "已拒绝")
        case .sharingAuthorized:
            return String(localized: "已授权")
        @unknown default:
            return String(localized: "未知")
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    private func appendScoredAssessmentTypes(_ suffixes: [String], to set: inout Set<HKObjectType>) {
        for suffix in suffixes {
            let identifier = HKScoredAssessmentTypeIdentifier(rawValue: "HKScoredAssessmentTypeIdentifier\(suffix)")
            set.insert(HKScoredAssessmentType(identifier))
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func sedentaryAuthorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime),
              let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
            return .unknown
        }

        let typesToShare: Set<HKSampleType> = []
        let typesToRead: Set<HKObjectType> = [stepType, exerciseType, standType]

        return await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: typesToShare,
                read: typesToRead
            ) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    func pressureSelfTestAuthorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            return .unknown
        }

        let typesToShare: Set<HKSampleType> = []
        let typesToRead: Set<HKObjectType> = [heartRateType, hrvType, restingHeartRateType]

        return await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: typesToShare,
                read: typesToRead
            ) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchChronologicalAge() async -> Int? {
        await withCheckedContinuation { continuation in
            do {
                let components = try healthStore.dateOfBirthComponents()
                guard let year = components.year else {
                    continuation.resume(returning: nil)
                    return
                }
                let nowYear = Calendar.current.component(.year, from: Date())
                let age = max(0, nowYear - year)
                continuation.resume(returning: age)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDateOfBirth() async -> Date? {
        await withCheckedContinuation { continuation in
            do {
                let components = try healthStore.dateOfBirthComponents()
                let calendar = Calendar.current
                continuation.resume(returning: calendar.date(from: components))
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchBiologicalSexDisplayText() async -> String? {
        await withCheckedContinuation { continuation in
            do {
                let biologicalSex = try healthStore.biologicalSex().biologicalSex
                let text: String
                switch biologicalSex {
                case .female:
                    text = "女"
                case .male:
                    text = "男"
                case .other:
                    text = "其他"
                case .notSet:
                    text = "未设置"
                @unknown default:
                    text = "未知"
                }
                continuation.resume(returning: text)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestHeightCm() async -> Double? {
        do {
            return try await fetchLatestQuantityValue(
                identifier: .height,
                unit: .meterUnit(with: .centi),
                predicate: HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
            )
        } catch {
            logHealthKitRead(metric: "height.latest", status: .queryFailed)
            return nil
        }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestBodyMassKg() async -> Double? {
        do {
            return try await fetchLatestQuantityValue(
                identifier: .bodyMass,
                unit: .gramUnit(with: .kilo),
                predicate: HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
            )
        } catch {
            logHealthKitRead(metric: "bodyMass.latest", status: .queryFailed)
            return nil
        }
    }

    func fetchLatestQuantityValue(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate?,
        forceRefresh: Bool = false
    ) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let domain = HealthKitRepositoryCache.domain(for: identifier)
        let key = HealthKitRepositoryCacheKey(
            domain: domain,
            name: "latestQuantity",
            parameters: identifier.rawValue
        )
        if !forceRefresh,
           let cached: Double? = HealthKitRepositoryCache.shared.value(
               for: key,
               ttl: HealthKitRepositoryCache.realtimeTTL
           ) {
            return cached
        }

        let effectivePredicate = predicate ?? HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: effectivePredicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "quantity.latest.\(type.identifier)",
            status: samples.isEmpty ? .noData : .dataAvailable
        )
        guard let sample = samples.first else {
            return nil
        }
        let value = sample.quantity.doubleValue(for: unit)
        HealthKitRepositoryCache.shared.store(value, for: key)
        return value
    }
    

    /// 方法说明：使用 HKSampleQueryDescriptor 读取分类样本（如睡眠阶段）。
    func fetchCategorySamples(type: HKCategoryType, predicate: NSPredicate, sort: [NSSortDescriptor]) async throws -> [HKCategorySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: sort.map { descriptor in
                let order: SortOrder = descriptor.ascending ? .forward : .reverse
                if descriptor.key == HKSampleSortIdentifierEndDate {
                    return SortDescriptor(\HKCategorySample.endDate, order: order)
                }
                return SortDescriptor(\HKCategorySample.startDate, order: order)
            },
            limit: HKObjectQueryNoLimit
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(metric: type.identifier, status: samples.isEmpty ? .noData : .dataAvailable)
        return samples
    }
    
    /// 方法说明：使用 HKSampleQueryDescriptor 读取数量样本（如心率、步数）。
    func fetchQuantitySamples(type: HKQuantityType, predicate: NSPredicate, sort: [NSSortDescriptor]) async throws -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: sort.map { descriptor in
                let order: SortOrder = descriptor.ascending ? .forward : .reverse
                if descriptor.key == HKSampleSortIdentifierEndDate {
                    return SortDescriptor(\HKQuantitySample.endDate, order: order)
                }
                return SortDescriptor(\HKQuantitySample.startDate, order: order)
            },
            limit: HKObjectQueryNoLimit
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(metric: type.identifier, status: samples.isEmpty ? .noData : .dataAvailable)
        return samples
    }

    // MARK: - 写入方法

    /// 方法说明：负责将饮水记录写入健康 App。
    func saveDietaryWater(milliliters: Int, date: Date = Date()) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }
        guard let type = HKObjectType.quantityType(forIdentifier: .dietaryWater), milliliters > 0 else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let quantity = HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: Double(milliliters))
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationFailed)
                }
            }
        }
    }

    /// 方法说明：负责将咖啡因记录写入健康 App。
    func saveDietaryCaffeine(milligrams: Int, date: Date = Date()) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }
        guard let type = HKObjectType.quantityType(forIdentifier: .dietaryCaffeine), milligrams > 0 else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let quantity = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: Double(milligrams))
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationFailed)
                }
            }
        }
    }

    /// 方法说明：负责将体重记录写入健康 App。
    func saveBodyMassKg(_ kilograms: Double, date: Date = Date()) async throws {
        try await saveQuantitySample(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            value: kilograms,
            date: date
        )
    }

    /// 方法说明：负责将身高记录写入健康 App。
    func saveHeightCm(_ centimeters: Double, date: Date = Date()) async throws {
        try await saveQuantitySample(
            identifier: .height,
            unit: .meterUnit(with: .centi),
            value: centimeters,
            date: date
        )
    }

    /// 方法说明：负责将 BMI 记录写入健康 App。
    func saveBodyMassIndex(_ value: Double, date: Date = Date()) async throws {
        try await saveQuantitySample(
            identifier: .bodyMassIndex,
            unit: .count(),
            value: value,
            date: date
        )
    }

    /// 方法说明：同时保存身高体重，并在数据完整时同步计算 BMI。
    func saveBodyProfile(heightCm: Double?, weightKg: Double?, date: Date = Date()) async throws {
        var didSave = false

        if let heightCm, heightCm > 0 {
            try await saveHeightCm(heightCm, date: date)
            didSave = true
        }

        if let weightKg, weightKg > 0 {
            try await saveBodyMassKg(weightKg, date: date)
            didSave = true
        }

        if let heightCm, let weightKg, heightCm > 0, weightKg > 0 {
            let heightM = heightCm / 100.0
            let bmi = weightKg / (heightM * heightM)
            try await saveBodyMassIndex(bmi, date: date)
            didSave = true
        }

        if !didSave {
            throw HealthKitError.dataTypeNotAvailable
        }
    }

    func saveQuantitySample(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        value: Double,
        date: Date
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }
        guard value > 0,
              let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationFailed)
                }
            }
        }
    }


    /// 方法说明：负责将训练记录写入健康/健身 App。
    /// - distanceKm 大于 0 时会把步行+跑步距离样本关联到本次训练；
    /// - replacingWorkoutUUID 传入本 App 之前写入的训练时，先删旧再写新，避免重复计入；
    /// - 返回新写入 workout 的 UUID，供本地记录保存引用。
    @discardableResult
    func saveWorkoutSession(
        start: Date,
        end: Date,
        effort: WorkoutEffortLevel?,
        note: String? = nil,
        distanceKm: Double? = nil,
        replacingWorkoutUUID: UUID? = nil
    ) async throws -> UUID {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailableOnDevice
        }
        guard end > start else {
            throw HealthKitError.dataFetchFailed
        }

        // 先清理本 App 上一次写入的同天训练；删除失败（已被用户在健康 App 里删掉等）不阻断新写入。
        if let replacingWorkoutUUID {
            await deleteAppWrittenWorkout(uuid: replacingWorkoutUUID)
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workoutActivityType(for: effort)

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)

        let metadata = workoutMetadata(for: effort, note: note)
        if !metadata.isEmpty {
            try await builder.addMetadata(metadata)
        }

        if let distanceKm, distanceKm > 0,
           let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: distanceKm),
                start: start,
                end: end
            )
            try await builder.addSamples([distanceSample])
        }

        try await builder.endCollection(at: end)

        let workout = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout, Error>) in
            builder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let workout {
                    continuation.resume(returning: workout)
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationFailed)
                }
            }
        }
        return workout.uuid
    }

    /// 方法说明：按 UUID 删除本 App 写入的训练及其关联样本（距离等）。
    /// 只允许删除本 App 作为来源的记录；其他来源（如手表）的训练不动。
    private func deleteAppWrittenWorkout(uuid: UUID) async {
        let predicate = HKQuery.predicateForObject(with: uuid)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [],
            limit: 1
        )
        guard let workout = try? await descriptor.result(for: healthStore).first,
              workout.sourceRevision.source.bundleIdentifier == HKSource.default().bundleIdentifier else {
            return
        }

        if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            let associatedPredicate = HKQuery.predicateForObjects(from: workout)
            _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                healthStore.deleteObjects(of: distanceType, predicate: associatedPredicate) { success, _, _ in
                    continuation.resume(returning: success)
                }
            }
        }

        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            healthStore.delete(workout) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }


    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestBodyFatPercentage() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        return try await fetchLatestQuantityValue(type: type, unit: .percent())
    }


    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchCurrentSedentaryState(now: Date = Date()) async throws -> SedentaryHealthState {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime),
              let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let authorizationStatus = await sedentaryAuthorizationRequestStatus()
        if authorizationStatus == .shouldRequest {
            return SedentaryHealthState(
                seatedStartAt: nil,
                lastActivityAt: nil,
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: false,
                sourceStatus: .needsAuthorization
            )
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard startOfDay <= now else {
            return SedentaryHealthState(
                seatedStartAt: nil,
                lastActivityAt: nil,
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: false,
                sourceStatus: .ready
            )
        }

        async let stepSamples = fetchQuantitySamples(
            type: stepType,
            predicate: HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate),
            sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )
        async let exerciseSamples = fetchQuantitySamples(
            type: exerciseType,
            predicate: HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate),
            sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )
        async let standSamples = fetchCategorySamples(
            type: standType,
            predicate: HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate),
            sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )
        async let sleepSessions = fetchSleepSessions(days: 2)

        let steps = try await stepSamples
        let exercises = try await exerciseSamples
        let stands = try await standSamples
        let recentSleepSessions: [SleepSession]
        do {
            recentSleepSessions = try await sleepSessions
        } catch {
            logHealthKitRead(metric: "sleepSessions.sedentary", status: .queryFailed)
            recentSleepSessions = []
        }

        let stepEvents = steps
            .filter { $0.quantity.doubleValue(for: .count()) >= 8 }
            .map(\.endDate)
        let exerciseEvents = exercises
            .filter { $0.quantity.doubleValue(for: .minute()) >= 1 }
            .map(\.endDate)
        let standEvents = stands
            .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
            .map(\.startDate)
        let lastActivityAt = (stepEvents + exerciseEvents + standEvents).max()

        if try await isCurrentlyAsleep(at: now) {
            return SedentaryHealthState(
                seatedStartAt: nil,
                lastActivityAt: lastActivityAt,
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: true,
                sourceStatus: .sleeping
            )
        }

        guard !steps.isEmpty || !exercises.isEmpty || !stands.isEmpty else {
            return SedentaryHealthState(
                seatedStartAt: nil,
                lastActivityAt: nil,
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: false,
                sourceStatus: .noActivitySamples
            )
        }

        let lastSleepEndAt = recentSleepSessions
            .filter { $0.end <= now }
            .map(\.end)
            .max()
        let seatedStartAt = sedentaryEffectiveStart(
            startOfDay: startOfDay,
            lastActivityAt: lastActivityAt,
            lastSleepEndAt: lastSleepEndAt
        )
        let elapsed = max(0, Int(now.timeIntervalSince(seatedStartAt) / 60))
        let isCounting = elapsed >= 10

        return SedentaryHealthState(
            seatedStartAt: isCounting ? seatedStartAt : nil,
            lastActivityAt: lastActivityAt,
            elapsedMinutes: isCounting ? elapsed : 0,
            isCounting: isCounting,
            pausedBySleep: false,
            sourceStatus: .ready
        )
    }

    /// 方法说明：负责生成指定日期的久坐摘要与时间轴，用于今天页和趋势页的久坐模块复用。
    func fetchSedentaryDaySummary(on date: Date, now: Date = Date()) async throws -> SedentaryDaySummary {
        let summaries = try await fetchSedentaryDaySummaries(
            startDate: Calendar.current.startOfDay(for: date),
            endDate: date,
            now: now
        )
        return summaries.first ?? SedentaryDaySummary.placeholder(on: date, status: .noData, updatedAt: now)
    }

    /// 方法说明：负责读取最近若干天的久坐摘要，供趋势页直接展示日级变化。
    func fetchSedentaryDaySummaries(days: Int = 7, endDate: Date = Date(), now: Date = Date()) async throws -> [SedentaryDaySummary] {
        let calendar = Calendar.current
        let cappedDays = max(1, days)
        let lastDay = calendar.startOfDay(for: endDate)
        let startDate = calendar.date(byAdding: .day, value: -(cappedDays - 1), to: lastDay) ?? lastDay
        return try await fetchSedentaryDaySummaries(startDate: startDate, endDate: endDate, now: now)
    }

    // MARK: - 每日统计

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyStatistics(
        quantityIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        days: Int,
        endDate: Date = Date(),
        forceRefresh: Bool = false
    ) async throws -> [TimeSeriesPointDouble] {
        guard let type = HKQuantityType.quantityType(forIdentifier: quantityIdentifier) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let calendar = Calendar.current
        let normalizedEnd = calendar.startOfDay(for: endDate)
        let key = HealthKitRepositoryCacheKey(
            domain: HealthKitRepositoryCache.domain(for: quantityIdentifier),
            name: "dailyStatistics",
            parameters: "\(quantityIdentifier.rawValue).\(unit.unitString).\(options.rawValue).\(Int64(normalizedEnd.timeIntervalSince1970)).\(max(days, 1))"
        )
        if !forceRefresh,
           let cached: [TimeSeriesPointDouble] = HealthKitRepositoryCache.shared.value(for: key),
           !cached.isEmpty {
            return cached
        }

        let anchorDate = normalizedEnd
        guard let startDate = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: anchorDate) else {
            return []
        }
        let rangeEnd = min(calendar.date(byAdding: .day, value: 1, to: normalizedEnd) ?? endDate, Date())

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: rangeEnd, options: .strictStartDate)
        let interval = DateComponents(day: 1)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: options,
            anchorDate: anchorDate,
            intervalComponents: interval
        )
        let collection = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "statistics.collection.\(quantityIdentifier.rawValue)",
            status: collection.statistics().isEmpty ? .noData : .dataAvailable
        )
        var points: [TimeSeriesPointDouble] = []
        collection.enumerateStatistics(from: startDate, to: rangeEnd) { stat, _ in
            let value: Double?
            if options.contains(.cumulativeSum) {
                value = stat.sumQuantity()?.doubleValue(for: unit)
            } else if options.contains(.discreteAverage) {
                value = stat.averageQuantity()?.doubleValue(for: unit)
            } else if options.contains(.discreteMin) {
                value = stat.minimumQuantity()?.doubleValue(for: unit)
            } else if options.contains(.discreteMax) {
                value = stat.maximumQuantity()?.doubleValue(for: unit)
            } else {
                value = nil
            }

            guard let value else { return }
            points.append(TimeSeriesPointDouble(timestamp: Int64(stat.startDate.timeIntervalSince1970), value: value))
        }
        // HealthKit 授权、设备同步和后台传输都可能在查询键不变时让原本为空的区间获得数据。
        // 因此不要对空的每日序列做负缓存，否则月视图或年视图可能持续为空，
        // 而使用另一查询键的周视图已经恢复。
        if !points.isEmpty {
            HealthKitRepositoryCache.shared.store(points, for: key)
        }
        return points
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchStatisticsCollection(
        quantityIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        startDate: Date,
        endDate: Date,
        interval: DateComponents,
        forceRefresh: Bool = false
    ) async throws -> [TimeSeriesPointDouble] {
        guard let type = HKQuantityType.quantityType(forIdentifier: quantityIdentifier) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: startDate)
        let intervalKey = [
            interval.year ?? 0,
            interval.month ?? 0,
            interval.day ?? 0,
            interval.hour ?? 0,
            interval.minute ?? 0
        ].map(String.init).joined(separator: "-")
        let key = HealthKitRepositoryCacheKey(
            domain: HealthKitRepositoryCache.domain(for: quantityIdentifier),
            name: "statisticsCollection",
            parameters: "\(quantityIdentifier.rawValue).\(unit.unitString).\(options.rawValue).\(Int64(calendar.startOfDay(for: startDate).timeIntervalSince1970)).\(Int64(calendar.startOfDay(for: endDate).timeIntervalSince1970)).\(intervalKey)"
        )
        if !forceRefresh,
           let cached: [TimeSeriesPointDouble] = HealthKitRepositoryCache.shared.value(
               for: key,
               ttl: HealthKitRepositoryCache.realtimeTTL
           ) {
            return cached
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: options,
            anchorDate: anchorDate,
            intervalComponents: interval
        )
        let collection = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "statistics.collection.\(quantityIdentifier.rawValue)",
            status: collection.statistics().isEmpty ? .noData : .dataAvailable
        )
        var points: [TimeSeriesPointDouble] = []
        collection.enumerateStatistics(from: startDate, to: endDate) { stat, _ in
            let value: Double?
            if options.contains(.cumulativeSum) {
                value = stat.sumQuantity()?.doubleValue(for: unit)
            } else if options.contains(.discreteAverage) {
                value = stat.averageQuantity()?.doubleValue(for: unit)
            } else {
                value = nil
            }

            guard let value else { return }
            points.append(TimeSeriesPointDouble(timestamp: Int64(stat.startDate.timeIntervalSince1970), value: value))
        }
        logHealthKitRead(
            metric: "statistics.\(quantityIdentifier.rawValue)",
            status: points.isEmpty ? .noData : .dataAvailable
        )
        HealthKitRepositoryCache.shared.store(points, for: key)
        return points
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchHourlyStatisticsForToday(
        quantityIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions
    ) async throws -> [TimeSeriesPointDouble] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = Date()
        return try await fetchStatisticsCollection(
            quantityIdentifier: quantityIdentifier,
            unit: unit,
            options: options,
            startDate: start,
            endDate: end,
            interval: DateComponents(hour: 1)
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchHourlyStatistics(
        quantityIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        startDate: Date,
        endDate: Date
    ) async throws -> [TimeSeriesPointDouble] {
        try await fetchStatisticsCollection(
            quantityIdentifier: quantityIdentifier,
            unit: unit,
            options: options,
            startDate: startDate,
            endDate: endDate,
            interval: DateComponents(hour: 1)
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func dayInterval(for date: Date) -> DateInterval? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let rawEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) else {
            return nil
        }
        let end = min(rawEnd, Date())
        guard end >= start else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    // MARK: - 通用分类辅助

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestCategoryEventDate(rawValue: String) async throws -> Date? {
        guard let identifier = resolvedCategoryIdentifier(from: rawValue),
              let type = HKObjectType.categoryType(forIdentifier: identifier) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: nil)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "category.latestDate.\(type.identifier)",
            status: samples.isEmpty ? .noData : .dataAvailable
        )
        return samples.first?.startDate
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchCategoryEventCount(rawValue: String, days: Int) async throws -> Int {
        guard let identifier = resolvedCategoryIdentifier(from: rawValue),
              let type = HKObjectType.categoryType(forIdentifier: identifier) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -max(days, 1), to: end) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [],
            limit: HKObjectQueryNoLimit
        )
        let samples = try await descriptor.result(for: healthStore)
        return samples.count
    }

    // MARK: - 身体成分每日序列

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyBodyFatPercentageAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .bodyFatPercentage,
            unit: .percent(),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyBodyMassAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            options: .discreteAverage,
            days: days
        )
    }

    /// 按天读取瘦体重趋势。
    func fetchDailyLeanBodyMassAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .leanBodyMass,
            unit: .gramUnit(with: .kilo),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责按天读取身高趋势。
    func fetchDailyHeightAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .height,
            unit: .meterUnit(with: .centi),
            options: .discreteAverage,
            days: days
        )
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchDailyBodyMassIndexAverages(days: Int = 30) async throws -> [TimeSeriesPointDouble] {
        try await fetchDailyStatistics(
            quantityIdentifier: .bodyMassIndex,
            unit: .count(),
            options: .discreteAverage,
            days: days
        )
    }

    // MARK: - 观察者注册

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func registerObserversIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        observerLock.lock()
        defer { observerLock.unlock() }
        guard !didRegisterObservers else { return }
        didRegisterObservers = true

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .oxygenSaturation,
            .stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .appleExerciseTime,
            .walkingSpeed,
            .walkingAsymmetryPercentage,
            .walkingStepLength,
            .walkingDoubleSupportPercentage,
            .appleWalkingSteadiness,
            .bodyMass,
            .bodyMassIndex,
            .bodyFatPercentage,
            .height,
            .leanBodyMass,
            .appleSleepingWristTemperature,
            .vo2Max,
            .timeInDaylight,
            .environmentalAudioExposure,
            .headphoneAudioExposure,
            .atrialFibrillationBurden,
            .appleSleepingBreathingDisturbances
        ]
        let categoryIdentifiers: [HKCategoryTypeIdentifier] = [
            .sleepAnalysis,
            .appleStandHour,
            .mindfulSession,
            .irregularHeartRhythmEvent,
            .highHeartRateEvent,
            .lowHeartRateEvent
        ]

        let sampleTypes: [HKSampleType] = quantityIdentifiers.compactMap {
            HKObjectType.quantityType(forIdentifier: $0)
        } + categoryIdentifiers.compactMap {
            HKObjectType.categoryType(forIdentifier: $0)
        } + [
            HKObjectType.workoutType(),
            HKObjectType.electrocardiogramType(),
            HKObjectType.stateOfMindType()
        ]

        for type in sampleTypes {
            registerObserver(for: type)
        }
    }

    /// 收到 HealthKit 更新通知后触发一次节流同步（syncAllDataIfNeeded 自带 5 分钟防抖）；
    /// 无论成功与否都必须调用 completionHandler，否则系统会指数退避并停止后台推送。
    private func registerObserver(for type: HKSampleType) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            HealthKitRepositoryCache.shared.invalidate(
                domains: [HealthKitRepositoryCache.domain(for: type)]
            )
            Task { @MainActor in
                HealthDataManager.shared.syncAllDataIfNeeded()
            }
            completionHandler()
        }
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    /// 方法说明：负责健康数据读取、转换或授权管理。
    func fetchLatestQuantityValue(
        type: HKQuantityType,
        unit: HKUnit,
        forceRefresh: Bool = false
    ) async throws -> Double? {
        let identifier = HKQuantityTypeIdentifier(rawValue: type.identifier)
        let key = HealthKitRepositoryCacheKey(
            domain: HealthKitRepositoryCache.domain(for: identifier),
            name: "latestQuantityByType",
            parameters: type.identifier
        )
        if !forceRefresh,
           let cached: Double? = HealthKitRepositoryCache.shared.value(
               for: key,
               ttl: HealthKitRepositoryCache.realtimeTTL
           ) {
            return cached
        }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: nil)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "quantity.latest.\(type.identifier)",
            status: samples.isEmpty ? .noData : .dataAvailable
        )
        guard let sample = samples.first else {
            return nil
        }
        let value = sample.quantity.doubleValue(for: unit)
        HealthKitRepositoryCache.shared.store(value, for: key)
        return value
    }

    private func fetchSedentaryDaySummaries(startDate: Date, endDate: Date, now: Date) async throws -> [SedentaryDaySummary] {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime),
              let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let calendar = Calendar.current
        let startOfFirstDay = calendar.startOfDay(for: startDate)
        let requestedLastDay = calendar.startOfDay(for: endDate)
        let dayAfterLast = calendar.date(byAdding: .day, value: 1, to: requestedLastDay) ?? requestedLastDay
        let effectiveUpperBound = min(dayAfterLast, now)
        let authorizationStatus = await sedentaryAuthorizationRequestStatus()

        let targetDays = strideDays(from: startOfFirstDay, through: requestedLastDay)
        guard authorizationStatus != .shouldRequest else {
            return targetDays.map {
                SedentaryDaySummary.placeholder(on: $0, status: .needsAuthorization, updatedAt: now)
            }
        }

        async let stepSamples = fetchQuantitySamples(
            type: stepType,
            predicate: HKQuery.predicateForSamples(withStart: startOfFirstDay, end: effectiveUpperBound, options: .strictStartDate),
            sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )
        async let exerciseSamples = fetchQuantitySamples(
            type: exerciseType,
            predicate: HKQuery.predicateForSamples(withStart: startOfFirstDay, end: effectiveUpperBound, options: .strictStartDate),
            sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )
        async let standSamples = fetchCategorySamples(
            type: standType,
            predicate: HKQuery.predicateForSamples(withStart: startOfFirstDay, end: effectiveUpperBound, options: .strictStartDate),
            sort: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )
        async let sleepSessions = fetchSleepSessions(days: max(2, targetDays.count + 1))

        do {
            let steps = try await stepSamples
            let exercises = try await exerciseSamples
            let stands = try await standSamples
            let sleepSessions = (try? await sleepSessions) ?? []

            return targetDays.map { day in
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                let effectiveDayEnd = min(dayEnd, now)
                guard day < effectiveDayEnd else {
                    return SedentaryDaySummary.placeholder(on: day, status: .noData, updatedAt: now)
                }

                let daySteps = steps.filter { sample in
                    sample.startDate < effectiveDayEnd && sample.endDate > day
                }
                let dayExercises = exercises.filter { sample in
                    sample.startDate < effectiveDayEnd && sample.endDate > day
                }
                let dayStands = stands.filter { sample in
                    sample.startDate < effectiveDayEnd && sample.endDate > day
                }
                let daySleepIntervals = sleepSessions.compactMap { session -> DateInterval? in
                    let start = max(day, session.start)
                    let end = min(effectiveDayEnd, session.end)
                    guard start < end else { return nil }
                    return DateInterval(start: start, end: end)
                }

                return buildSedentaryDaySummary(
                    dayStart: day,
                    dayEnd: effectiveDayEnd,
                    stepSamples: daySteps,
                    exerciseSamples: dayExercises,
                    standSamples: dayStands,
                    sleepIntervals: daySleepIntervals,
                    updatedAt: now
                )
            }
        } catch {
            return targetDays.map {
                SedentaryDaySummary.placeholder(on: $0, status: .unavailable, updatedAt: now)
            }
        }
    }

    private func strideDays(from start: Date, through end: Date) -> [Date] {
        let calendar = Calendar.current
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let target = calendar.startOfDay(for: end)

        while cursor <= target {
            days.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? target.addingTimeInterval(1)
        }

        return days
    }

    private func buildSedentaryDaySummary(
        dayStart: Date,
        dayEnd: Date,
        stepSamples: [HKQuantitySample],
        exerciseSamples: [HKQuantitySample],
        standSamples: [HKCategorySample],
        sleepIntervals: [DateInterval],
        updatedAt: Date
    ) -> SedentaryDaySummary {
        guard !stepSamples.isEmpty || !exerciseSamples.isEmpty || !standSamples.isEmpty else {
            return SedentaryDaySummary.placeholder(on: dayStart, status: .noData, updatedAt: updatedAt)
        }

        let activityEvents = mergedSedentaryActivityEvents(
            from: stepSamples,
            exerciseSamples: exerciseSamples,
            standSamples: standSamples,
            dayStart: dayStart,
            dayEnd: dayEnd
        )

        var sessions: [SedentaryTimelineSegment] = []
        let awakeSegments = sedentaryAwakeSegments(
            dayStart: dayStart,
            dayEnd: dayEnd,
            excludedIntervals: sleepIntervals
        )
        let normalizedSleepIntervals = sleepIntervals
            .map { interval in
                let start = max(dayStart, interval.start)
                let end = min(dayEnd, interval.end)
                return DateInterval(start: start, end: end)
            }
            .filter { $0.start < $0.end }

        for awakeSegment in awakeSegments {
            let segmentEvents = activityEvents.filter { event in
                event.date > awakeSegment.start && event.date <= awakeSegment.end
            }
            var cursor = awakeSegment.start

            for event in segmentEvents {
                let duration = max(0, Int(event.date.timeIntervalSince(cursor) / 60))
                if duration >= 10 {
                    sessions.append(
                        SedentaryTimelineSegment(
                            start: cursor,
                            end: event.date,
                            durationMinutes: duration,
                            kind: sedentaryKind(for: duration),
                            endingBreakKind: event.kind,
                            endingBreakMinutes: event.estimatedReliefMinutes,
                            isOngoing: false
                        )
                    )
                }
                cursor = max(cursor, event.date)
            }

            let trailingDuration = max(0, Int(awakeSegment.end.timeIntervalSince(cursor) / 60))
            if trailingDuration >= 10 {
                sessions.append(
                    SedentaryTimelineSegment(
                        start: cursor,
                        end: awakeSegment.end,
                        durationMinutes: trailingDuration,
                        kind: sedentaryKind(for: trailingDuration),
                        endingBreakKind: nil,
                        endingBreakMinutes: nil,
                        isOngoing: Calendar.current.isDate(dayStart, inSameDayAs: updatedAt) && awakeSegment.end == dayEnd
                    )
                )
            }
        }

        for sleepInterval in normalizedSleepIntervals {
            let duration = max(0, Int(sleepInterval.end.timeIntervalSince(sleepInterval.start) / 60))
            guard duration >= 10 else { continue }
            sessions.append(
                SedentaryTimelineSegment(
                    start: sleepInterval.start,
                    end: sleepInterval.end,
                    durationMinutes: duration,
                    kind: .sleep,
                    endingBreakKind: nil,
                    endingBreakMinutes: nil,
                    isOngoing: false
                )
            )
        }

        sessions.sort { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }

        let sedentarySessions = sessions.filter { $0.kind != .sleep }
        let totalSedentaryMinutes = sedentarySessions.reduce(0) { $0 + $1.durationMinutes }
        let totalReliefMinutes = sedentarySessions.compactMap(\.endingBreakMinutes).reduce(0, +)
        let longestSessionMinutes = sedentarySessions.map(\.durationMinutes).max() ?? 0
        let lastBreakKind = sedentarySessions.last(where: { $0.endingBreakKind != nil })?.endingBreakKind

        return SedentaryDaySummary(
            date: dayStart,
            sessions: sessions,
            totalSedentaryMinutes: totalSedentaryMinutes,
            activeBreakCount: sedentarySessions.filter { $0.endingBreakKind != nil }.count,
            totalReliefMinutes: totalReliefMinutes,
            longestSessionMinutes: longestSessionMinutes,
            sourceStatus: .ready,
            lastBreakKind: lastBreakKind,
            updatedAt: updatedAt
        )
    }

    private func mergedSedentaryActivityEvents(
        from stepSamples: [HKQuantitySample],
        exerciseSamples: [HKQuantitySample],
        standSamples: [HKCategorySample],
        dayStart: Date,
        dayEnd: Date
    ) -> [SedentaryActivityEvent] {
        let stepEvents = stepSamples.compactMap { sample -> SedentaryActivityEvent? in
            let value = sample.quantity.doubleValue(for: .count())
            guard value >= 8 else { return nil }
            let date = min(max(sample.endDate, dayStart), dayEnd)
            let duration = max(1, min(10, Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)))
            return SedentaryActivityEvent(date: date, kind: .walking, estimatedReliefMinutes: duration)
        }
        let exerciseEvents = exerciseSamples.compactMap { sample -> SedentaryActivityEvent? in
            let value = sample.quantity.doubleValue(for: .minute())
            guard value >= 1 else { return nil }
            let date = min(max(sample.endDate, dayStart), dayEnd)
            let duration = max(1, min(20, Int(value.rounded())))
            return SedentaryActivityEvent(date: date, kind: .exercise, estimatedReliefMinutes: duration)
        }
        let standEvents = standSamples.compactMap { sample -> SedentaryActivityEvent? in
            guard sample.value == HKCategoryValueAppleStandHour.stood.rawValue else { return nil }
            let date = min(max(sample.startDate, dayStart), dayEnd)
            return SedentaryActivityEvent(date: date, kind: .standing, estimatedReliefMinutes: 1)
        }

        let mergedWindow: TimeInterval = 8 * 60
        return (stepEvents + exerciseEvents + standEvents)
            .sorted { $0.date < $1.date }
            .reduce(into: [SedentaryActivityEvent]()) { partial, event in
                guard let last = partial.last else {
                    partial.append(event)
                    return
                }
                if event.date.timeIntervalSince(last.date) <= mergedWindow {
                    partial[partial.count - 1] = SedentaryActivityEvent(
                        date: max(last.date, event.date),
                        kind: preferredBreakKind(last.kind, event.kind),
                        estimatedReliefMinutes: min(20, last.estimatedReliefMinutes + event.estimatedReliefMinutes)
                    )
                } else {
                    partial.append(event)
                }
            }
    }

    private func preferredBreakKind(_ lhs: SedentaryBreakKind, _ rhs: SedentaryBreakKind) -> SedentaryBreakKind {
        func priority(for kind: SedentaryBreakKind) -> Int {
            switch kind {
            case .exercise:
                return 3
            case .walking:
                return 2
            case .standing:
                return 1
            }
        }
        return priority(for: lhs) >= priority(for: rhs) ? lhs : rhs
    }

    private func sedentaryKind(for durationMinutes: Int) -> SedentaryTimelineKind {
        switch durationMinutes {
        case 90...:
            return .heavy
        case 60...:
            return .moderate
        default:
            return .light
        }
    }


}

// MARK: - Shared Helpers (used by extension files)

extension HealthKitManager {
    func fetchOptionalCategorySamples(
        identifier: HKCategoryTypeIdentifier,
        predicate: NSPredicate,
        sort: [NSSortDescriptor]
    ) async throws -> [HKCategorySample] {
        guard let type = HKObjectType.categoryType(forIdentifier: identifier) else {
            return []
        }
        return try await fetchCategorySamples(type: type, predicate: predicate, sort: sort)
    }

    func fetchLatestQuantitySample(
        type: HKQuantityType,
        sortDescriptor: NSSortDescriptor
    ) async throws -> HKQuantitySample? {
        let order: SortOrder = sortDescriptor.ascending ? .forward : .reverse
        let sort: SortDescriptor<HKQuantitySample>
        if sortDescriptor.key == HKSampleSortIdentifierEndDate {
            sort = SortDescriptor(\.endDate, order: order)
        } else {
            sort = SortDescriptor(\.startDate, order: order)
        }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [sort],
            limit: 1
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "quantity.latestSample.\(type.identifier)",
            status: samples.isEmpty ? .noData : .dataAvailable
        )
        return samples.first
    }

    func fetchVoltageMeasurements(for electrocardiogram: HKElectrocardiogram) async throws -> [HeartECGVoltageMeasurement] {
        try await withCheckedThrowingContinuation { continuation in
            var points: [HeartECGVoltageMeasurement] = []
            let unit = HKUnit.voltUnit(with: .milli)
            let query = HKElectrocardiogramQuery(electrocardiogram) { _, result in
                switch result {
                case .measurement(let measurement):
                    points.append(
                        HeartECGVoltageMeasurement(
                            timeSinceSampleStart: measurement.timeSinceSampleStart,
                            millivolts: measurement.quantity(for: .appleWatchSimilarToLeadI)?.doubleValue(for: unit) ?? 0
                        )
                    )
                case .done:
                    continuation.resume(returning: points)
                case .error:
                    continuation.resume(throwing: HealthKitError.dataFetchFailed)
                @unknown default:
                    continuation.resume(returning: points)
                }
            }
            healthStore.execute(query)
        }
    }

    func ecgClassificationText(_ classification: HKElectrocardiogram.Classification) -> String {
        switch classification {
        case .sinusRhythm: return "窦性心律"
        case .atrialFibrillation: return "房颤提示"
        case .inconclusiveLowHeartRate: return "结果不明确 · 心率偏低"
        case .inconclusiveHighHeartRate: return "结果不明确 · 心率偏高"
        case .inconclusivePoorReading: return "结果不明确 · 记录质量不足"
        case .inconclusiveOther: return "结果不明确"
        case .unrecognized: return "无法识别"
        case .notSet: return "未提供结论"
        @unknown default: return "未提供结论"
        }
    }

    func ecgSymptomsText(_ symptomsStatus: HKElectrocardiogram.SymptomsStatus) -> String {
        switch symptomsStatus {
        case .present: return "记录时已填写症状"
        case .none: return "记录时未填症状"
        case .notSet: return "未记录症状"
        @unknown default: return "未记录症状"
        }
    }

    func medianMinute(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return Int(((Double(values[middle - 1]) + Double(values[middle])) / 2.0).rounded())
        }
        return values[middle]
    }

    static func activeEnergyBurnedQuantity(for workout: HKWorkout) -> HKQuantity? {
        guard let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }
        return workout.statistics(for: activeEnergyType)?.sumQuantity()
    }

    /// `HKWorkout.totalDistance` 已弃用，官方要求改用 `statistics(for:)` 按距离类型取 sum。
    static func totalDistanceQuantity(for workout: HKWorkout) -> HKQuantity? {
        if let identifier = distanceQuantityIdentifier(for: workout.workoutActivityType),
           let type = HKObjectType.quantityType(forIdentifier: identifier),
           let sum = workout.statistics(for: type)?.sumQuantity() {
            return sum
        }
        // 无专属映射的活动类型按常见距离类型顺序回退，取第一个有统计值的。
        let fallbacks: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming, .distanceWheelchair]
        for identifier in fallbacks {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier),
                  let sum = workout.statistics(for: type)?.sumQuantity() else { continue }
            return sum
        }
        return nil
    }

    /// 活动类型到距离量类型的映射，供 workout 距离统计使用。
    private static func distanceQuantityIdentifier(for activityType: HKWorkoutActivityType) -> HKQuantityTypeIdentifier? {
        switch activityType {
        case .running, .walking, .hiking, .elliptical, .stairClimbing: return .distanceWalkingRunning
        case .cycling, .handCycling: return .distanceCycling
        case .swimming: return .distanceSwimming
        case .wheelchairWalkPace, .wheelchairRunPace: return .distanceWheelchair
        case .rowing: return .distanceRowing
        case .paddleSports: return .distancePaddleSports
        case .crossCountrySkiing: return .distanceCrossCountrySkiing
        case .downhillSkiing, .snowboarding: return .distanceDownhillSnowSports
        default: return nil
        }
    }

    nonisolated static func workoutActivityTitlePublic(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "跑步"
        case .walking: return "步行"
        case .cycling: return "骑行"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "力量训练"
        case .highIntensityIntervalTraining: return "间歇训练"
        case .yoga: return "瑜伽"
        case .swimming: return "游泳"
        case .hiking: return "徒步"
        case .coreTraining: return "核心训练"
        case .elliptical: return "椭圆机"
        case .rowing: return "划船"
        case .dance: return "舞蹈"
        default: return "综合活动"
        }
    }

    /// HealthKit 用 `HKMetadataKeyIndoorWorkout` 区分同一种运动的室内与户外记录。
    /// Apple Watch 的“户外走路”会写入 false；保留缺少元数据的旧记录为普通“步行”。
    nonisolated static func workoutActivityTitle(for workout: HKWorkout) -> String {
        guard workout.workoutActivityType == .walking else {
            return workoutActivityTitlePublic(for: workout.workoutActivityType)
        }

        let isIndoor = (workout.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue
        switch isIndoor {
        case false: return "户外走路"
        case true: return "室内走路"
        case nil: return "步行"
        }
    }

    nonisolated static func workoutActivityTitle(for type: HKWorkoutActivityType) -> String {
        workoutActivityTitlePublic(for: type)
    }

    func workoutActivityType(for effort: WorkoutEffortLevel?) -> HKWorkoutActivityType {
        switch effort {
        case .hard: return .highIntensityIntervalTraining
        case .moderate: return .functionalStrengthTraining
        case .light, .none: return .traditionalStrengthTraining
        }
    }

    func workoutMetadata(for effort: WorkoutEffortLevel?, note: String?) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: true
        ]
        if let effort {
            metadata["BioBalanceWorkoutEffort"] = effort.rawValue
        }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["BioBalanceWorkoutNote"] = note
        }
        return metadata
    }
}
