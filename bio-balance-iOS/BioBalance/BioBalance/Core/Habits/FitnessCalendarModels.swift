import Foundation

enum HabitCalendarScope: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week:
            return String(localized: "周")
        case .month:
            return String(localized: "月")
        }
    }
}

struct HabitTrendPoint: Identifiable, Hashable {
    let date: Date
    let value: Double

    var id: TimeInterval { date.timeIntervalSince1970 }
}

enum FitnessCheckinMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case workout
    case recovery
    case rest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout:
            return String(localized: "完成训练")
        case .recovery:
            return "轻恢复"
        case .rest:
            return String(localized: "休息日")
        }
    }

    var shortTitle: String {
        switch self {
        case .workout:
            return String(localized: "训练")
        case .recovery:
            return "恢复"
        case .rest:
            return String(localized: "休息")
        }
    }

    var symbol: String {
        switch self {
        case .workout:
            return "bolt.heart.fill"
        case .recovery:
            return "leaf.fill"
        case .rest:
            return "moon.stars.fill"
        }
    }

    var tintHex: String {
        switch self {
        case .workout:
            return "58CC6A"
        case .recovery:
            return "2AA7A1"
        case .rest:
            return "94A3C3"
        }
    }

    var countsForRhythm: Bool { true }

    var countsForTraining: Bool {
        self == .workout
    }
}

enum WorkoutEffortLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case moderate
    case hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            return String(localized: "轻松")
        case .moderate:
            return String(localized: "中等")
        case .hard:
            return String(localized: "高强度")
        }
    }

    var tintHex: String {
        switch self {
        case .light:
            return "73C8E8"
        case .moderate:
            return "F4B46B"
        case .hard:
            return "F06A7B"
        }
    }
}

/// 当日心情档位：保存在本地记录里，并可写回健康 App 的“心理状态（每日心情）”。
enum DailyMoodLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case veryUnpleasant
    case unpleasant
    case neutral
    case pleasant
    case veryPleasant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .veryUnpleasant:
            return String(localized: "很差")
        case .unpleasant:
            return String(localized: "低落")
        case .neutral:
            return String(localized: "一般")
        case .pleasant:
            return String(localized: "不错")
        case .veryPleasant:
            return String(localized: "很好")
        }
    }

    var emoji: String {
        switch self {
        case .veryUnpleasant:
            return "😣"
        case .unpleasant:
            return "😕"
        case .neutral:
            return "😐"
        case .pleasant:
            return "🙂"
        case .veryPleasant:
            return "😄"
        }
    }

    var tintHex: String {
        switch self {
        case .veryUnpleasant:
            return "F06A7B"
        case .unpleasant:
            return "F4B46B"
        case .neutral:
            return "94A3C3"
        case .pleasant:
            return "73C8E8"
        case .veryPleasant:
            return "58CC6A"
        }
    }

    /// HealthKit State of Mind 的效价（-1 到 1）。
    var valence: Double {
        switch self {
        case .veryUnpleasant:
            return -1.0
        case .unpleasant:
            return -0.5
        case .neutral:
            return 0
        case .pleasant:
            return 0.5
        case .veryPleasant:
            return 1.0
        }
    }
}

/// 健身详情页“补充记录”一次保存提交的全部内容。
struct FitnessDayDetailDraft: Hashable, Sendable {
    var mode: FitnessCheckinMode?
    var minutes: Int
    var distanceKm: Double
    var effort: WorkoutEffortLevel?
    var mood: DailyMoodLevel?
    var note: String
    var isShared: Bool
    var syncToHealthApp: Bool
}

struct LocalActionDayRecord: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let date: Date
    var completedActions: [SharedActionKind]
    var waterMl: Int
    var caffeineMg: Int
    var sunlightMinutes: Int
    var mindfulnessMinutes: Int
    var standHours: Int
    var isShared: Bool
    var fitnessCheckinMode: FitnessCheckinMode?
    var manualWorkoutMinutes: Int
    var manualWorkoutDistanceKm: Double
    var manualWorkoutEffort: WorkoutEffortLevel?
    var dailyMood: DailyMoodLevel?
    var fitnessNote: String
    var checkedInAt: Date?
    // 本 App 写入健康 App 的样本引用（仅本地保存），再次编辑时用于替换旧样本、避免重复。
    var healthKitWorkoutUUID: String?
    var healthKitMoodUUID: String?
    var updatedAt: Date

    var hasManualFitnessCheckin: Bool {
        fitnessCheckinMode != nil
    }

    var hasTrainingNote: Bool {
        !fitnessNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: String,
        date: Date,
        completedActions: [SharedActionKind],
        waterMl: Int,
        caffeineMg: Int,
        sunlightMinutes: Int,
        mindfulnessMinutes: Int,
        standHours: Int,
        isShared: Bool,
        fitnessCheckinMode: FitnessCheckinMode? = nil,
        manualWorkoutMinutes: Int = 0,
        manualWorkoutDistanceKm: Double = 0,
        manualWorkoutEffort: WorkoutEffortLevel? = nil,
        dailyMood: DailyMoodLevel? = nil,
        fitnessNote: String = "",
        checkedInAt: Date? = nil,
        healthKitWorkoutUUID: String? = nil,
        healthKitMoodUUID: String? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.date = date
        self.completedActions = completedActions
        self.waterMl = waterMl
        self.caffeineMg = caffeineMg
        self.sunlightMinutes = sunlightMinutes
        self.mindfulnessMinutes = mindfulnessMinutes
        self.standHours = standHours
        self.isShared = isShared
        self.fitnessCheckinMode = fitnessCheckinMode
        self.manualWorkoutMinutes = manualWorkoutMinutes
        self.manualWorkoutDistanceKm = manualWorkoutDistanceKm
        self.manualWorkoutEffort = manualWorkoutEffort
        self.dailyMood = dailyMood
        self.fitnessNote = fitnessNote
        self.checkedInAt = checkedInAt
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.healthKitMoodUUID = healthKitMoodUUID
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case completedActions
        case waterMl
        case caffeineMg
        case sunlightMinutes
        case mindfulnessMinutes
        case standHours
        case isShared
        case fitnessCheckinMode
        case manualWorkoutMinutes
        case manualWorkoutDistanceKm
        case manualWorkoutEffort
        case dailyMood
        case fitnessNote
        case checkedInAt
        case healthKitWorkoutUUID
        case healthKitMoodUUID
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        completedActions = try container.decodeIfPresent([SharedActionKind].self, forKey: .completedActions) ?? []
        waterMl = try container.decodeIfPresent(Int.self, forKey: .waterMl) ?? 0
        caffeineMg = try container.decodeIfPresent(Int.self, forKey: .caffeineMg) ?? 0
        sunlightMinutes = try container.decodeIfPresent(Int.self, forKey: .sunlightMinutes) ?? 0
        mindfulnessMinutes = try container.decodeIfPresent(Int.self, forKey: .mindfulnessMinutes) ?? 0
        standHours = try container.decodeIfPresent(Int.self, forKey: .standHours) ?? 0
        isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
        fitnessCheckinMode = try container.decodeIfPresent(FitnessCheckinMode.self, forKey: .fitnessCheckinMode)
        manualWorkoutMinutes = try container.decodeIfPresent(Int.self, forKey: .manualWorkoutMinutes) ?? 0
        manualWorkoutDistanceKm = try container.decodeIfPresent(Double.self, forKey: .manualWorkoutDistanceKm) ?? 0
        manualWorkoutEffort = try container.decodeIfPresent(WorkoutEffortLevel.self, forKey: .manualWorkoutEffort)
        dailyMood = try container.decodeIfPresent(DailyMoodLevel.self, forKey: .dailyMood)
        fitnessNote = try container.decodeIfPresent(String.self, forKey: .fitnessNote) ?? ""
        checkedInAt = try container.decodeIfPresent(Date.self, forKey: .checkedInAt)
        healthKitWorkoutUUID = try container.decodeIfPresent(String.self, forKey: .healthKitWorkoutUUID)
        healthKitMoodUUID = try container.decodeIfPresent(String.self, forKey: .healthKitMoodUUID)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
    }
}

struct HabitFitnessCalendarDay: Identifiable, Hashable {
    let date: Date
    let dayLabel: String
    let numberLabel: String
    let activeEnergyText: String
    let workoutLabel: String?
    let statusText: String
    let highlightHex: String
    let isInDisplayedMonth: Bool
    let isFuture: Bool
    let isSelected: Bool
    let exerciseMinutes: Int
    let activeEnergy: Int
    let standHours: Int
    let hrvValue: Double?
    let checkinMode: FitnessCheckinMode?
    let manualWorkoutMinutes: Int
    let manualWorkoutEffort: WorkoutEffortLevel?
    let fitnessNote: String
    let isShared: Bool
    let checkedInAt: Date?
    let isInferredWorkoutOnly: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }

    var displayWorkoutMinutes: Int {
        max(exerciseMinutes, manualWorkoutMinutes)
    }

    init(
        date: Date,
        dayLabel: String,
        numberLabel: String,
        activeEnergyText: String,
        workoutLabel: String?,
        statusText: String,
        highlightHex: String,
        isInDisplayedMonth: Bool,
        isFuture: Bool,
        isSelected: Bool,
        exerciseMinutes: Int,
        activeEnergy: Int,
        standHours: Int,
        hrvValue: Double?,
        checkinMode: FitnessCheckinMode? = nil,
        manualWorkoutMinutes: Int = 0,
        manualWorkoutEffort: WorkoutEffortLevel? = nil,
        fitnessNote: String = "",
        isShared: Bool = false,
        checkedInAt: Date? = nil,
        isInferredWorkoutOnly: Bool = false
    ) {
        self.date = date
        self.dayLabel = dayLabel
        self.numberLabel = numberLabel
        self.activeEnergyText = activeEnergyText
        self.workoutLabel = workoutLabel
        self.statusText = statusText
        self.highlightHex = highlightHex
        self.isInDisplayedMonth = isInDisplayedMonth
        self.isFuture = isFuture
        self.isSelected = isSelected
        self.exerciseMinutes = exerciseMinutes
        self.activeEnergy = activeEnergy
        self.standHours = standHours
        self.hrvValue = hrvValue
        self.checkinMode = checkinMode
        self.manualWorkoutMinutes = manualWorkoutMinutes
        self.manualWorkoutEffort = manualWorkoutEffort
        self.fitnessNote = fitnessNote
        self.isShared = isShared
        self.checkedInAt = checkedInAt
        self.isInferredWorkoutOnly = isInferredWorkoutOnly
    }
}

struct HabitFitnessCalendarModel {
    let scope: HabitCalendarScope
    let rangeTitle: String
    let streakText: String
    let summaryPills: [String]
    let days: [HabitFitnessCalendarDay]
}

struct HabitFitnessStatsCardModel: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let detailText: String
    let progress: Double?
    let tintHex: String
    let symbol: String
}

struct FitnessOverviewStatItem: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let tintHex: String
    let symbol: String
}

struct FitnessOverviewModel {
    let title: String
    let subtitle: String
    let bestDayText: String
    let coachTip: String
    let statItems: [FitnessOverviewStatItem]
}

struct FitnessWorkoutReviewMetric: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let unitText: String
    let symbol: String
    let tintHex: String
}

struct FitnessWorkoutReviewModel {
    let date: Date?
    let workoutTitle: String
    let dateText: String
    let badgeText: String
    let headline: String
    let detailText: String
    let intensityText: String
    let recoveryText: String
    let accentHex: String
    let metrics: [FitnessWorkoutReviewMetric]

    var hasWorkout: Bool { date != nil }
}

struct FitnessSharedHighlightItem: Identifiable {
    let date: Date
    let title: String
    let subtitle: String
    let badgeText: String
    let tintHex: String
    let day: HabitFitnessCalendarDay?

    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct FitnessRecoveryInsightModel {
    let title: String
    let statusText: String
    let detailText: String
    let accentHex: String
}

struct FitnessNextStepModel {
    let title: String
    let headline: String
    let detailText: String
    let primaryActionTitle: String
    let primaryMode: FitnessCheckinMode?
    let secondaryActionTitle: String
    let accentHex: String
    let symbol: String
    let chips: [String]
}

struct ActionDayDetailStatItem: Identifiable, Hashable {
    let title: String
    let valueText: String
    let tintHex: String

    var id: String { title }
}

struct ActionDayDetailStatusTag: Identifiable, Hashable {
    let title: String
    let tintHex: String

    var id: String { title }
}

enum WorkoutReportKind: Hashable {
    case swimming
    case running
    case walking
    case hiking
    case cycling
    case strength
    case highIntensity
    case yoga
    case rowing
    case elliptical
    case dance
    case core
    case other

    static func recognized(from workoutTitle: String) -> WorkoutReportKind {
        if workoutTitle.contains("游泳") { return .swimming }
        if workoutTitle.contains("跑") { return .running }
        if workoutTitle.contains("徒步") { return .hiking }
        if workoutTitle.contains("走") || workoutTitle.contains("步行") { return .walking }
        if workoutTitle.contains("骑") { return .cycling }
        if workoutTitle.contains("高强度") || workoutTitle.contains("间歇") { return .highIntensity }
        if workoutTitle.contains("力量") { return .strength }
        if workoutTitle.contains("瑜伽") { return .yoga }
        if workoutTitle.contains("划船") { return .rowing }
        if workoutTitle.contains("椭圆") { return .elliptical }
        if workoutTitle.contains("舞") { return .dance }
        if workoutTitle.contains("核心") { return .core }
        return .other
    }

    var reportTitle: String {
        switch self {
        case .swimming: return String(localized: "游泳报告")
        case .running: return String(localized: "跑步报告")
        case .walking: return String(localized: "步行报告")
        case .hiking: return String(localized: "徒步报告")
        case .cycling: return String(localized: "骑行报告")
        case .strength: return String(localized: "力量训练报告")
        case .highIntensity: return String(localized: "高强度训练报告")
        case .yoga: return String(localized: "瑜伽报告")
        case .rowing: return String(localized: "划船报告")
        case .elliptical: return String(localized: "椭圆机报告")
        case .dance: return String(localized: "舞蹈报告")
        case .core: return String(localized: "核心训练报告")
        case .other: return String(localized: "运动报告")
        }
    }

    var symbol: String {
        switch self {
        case .swimming: return "figure.pool.swim"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling: return "figure.outdoor.cycle"
        case .strength: return "dumbbell.fill"
        case .highIntensity: return "bolt.heart.fill"
        case .yoga: return "figure.yoga"
        case .rowing: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .dance: return "figure.dance"
        case .core: return "figure.core.training"
        case .other: return "figure.mixed.cardio"
        }
    }

    var accentHex: String {
        switch self {
        case .swimming: return "168FA3"
        case .running: return "EF6B4D"
        case .walking: return "3C9B72"
        case .hiking: return "708D55"
        case .cycling: return "4C79D8"
        case .strength: return "7B61B9"
        case .highIntensity: return "D94F68"
        case .yoga: return "9A6BB5"
        case .rowing: return "367F92"
        case .elliptical: return "467EAE"
        case .dance: return "C05D9F"
        case .core: return "C27A3D"
        case .other: return "526F82"
        }
    }
}

struct ActionDayDetailModel: Identifiable, Hashable {
    let date: Date
    let title: String
    let workoutTitle: String
    let movementSummary: String
    let statItems: [ActionDayDetailStatItem]
    let statusTags: [ActionDayDetailStatusTag]
    let trendPoints: [HabitTrendPoint]
    let insightText: String
    let isShared: Bool
    let checkinMode: FitnessCheckinMode?
    let manualWorkoutMinutes: Int
    let manualWorkoutDistanceKm: Double
    let manualWorkoutEffort: WorkoutEffortLevel?
    let dailyMood: DailyMoodLevel?
    let fitnessNote: String
    let checkedInAt: Date?
    let trainingLoadScore: Int?
    let recoveryScore: Int?
    let workoutCount: Int?
    let distanceKilometers: Double?
    let averagePaceText: String?
    let swimmingReport: SwimmingWorkoutReport?
    let workoutReportKind: WorkoutReportKind?

    init(
        date: Date,
        title: String,
        workoutTitle: String,
        movementSummary: String,
        statItems: [ActionDayDetailStatItem],
        statusTags: [ActionDayDetailStatusTag] = [],
        trendPoints: [HabitTrendPoint],
        insightText: String = "",
        isShared: Bool,
        checkinMode: FitnessCheckinMode? = nil,
        manualWorkoutMinutes: Int = 0,
        manualWorkoutDistanceKm: Double = 0,
        manualWorkoutEffort: WorkoutEffortLevel? = nil,
        dailyMood: DailyMoodLevel? = nil,
        fitnessNote: String = "",
        checkedInAt: Date? = nil,
        trainingLoadScore: Int? = nil,
        recoveryScore: Int? = nil,
        workoutCount: Int? = nil,
        distanceKilometers: Double? = nil,
        averagePaceText: String? = nil,
        swimmingReport: SwimmingWorkoutReport? = nil,
        workoutReportKind: WorkoutReportKind? = nil
    ) {
        self.date = date
        self.title = title
        self.workoutTitle = workoutTitle
        self.movementSummary = movementSummary
        self.statItems = statItems
        self.statusTags = statusTags
        self.trendPoints = trendPoints
        self.insightText = insightText
        self.isShared = isShared
        self.checkinMode = checkinMode
        self.manualWorkoutMinutes = manualWorkoutMinutes
        self.manualWorkoutDistanceKm = manualWorkoutDistanceKm
        self.manualWorkoutEffort = manualWorkoutEffort
        self.dailyMood = dailyMood
        self.fitnessNote = fitnessNote
        self.checkedInAt = checkedInAt
        self.trainingLoadScore = trainingLoadScore
        self.recoveryScore = recoveryScore
        self.workoutCount = workoutCount
        self.distanceKilometers = distanceKilometers
        self.averagePaceText = averagePaceText
        self.swimmingReport = swimmingReport
        self.workoutReportKind = workoutReportKind
    }

    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct FitnessAchievementCardModel {
    let rhythmStreak: Int
    let trainingStreak: Int
    let weeklyTrainingDays: Int
    let weeklyGoal: Int
    let todayMode: FitnessCheckinMode?
    let mascotTitle: String
    let mascotSubtitle: String
    let ctaText: String
}

struct FitnessCheckinOpeningModel {
    let currentStreak: Int
    let longestStreak: Int
    let startDate: Date
    let monthTitle: String
    let todayStatusTitle: String
    let todayMode: FitnessCheckinMode?
    let days: [HabitFitnessCalendarDay]
}

enum FitnessLiveWorkoutState: Equatable {
    case idle
    case running(startedAt: Date, effort: WorkoutEffortLevel)
    case saving(startedAt: Date, endedAt: Date, effort: WorkoutEffortLevel)

    var isActive: Bool {
        switch self {
        case .running, .saving:
            return true
        case .idle:
            return false
        }
    }

    var effort: WorkoutEffortLevel? {
        switch self {
        case .running(_, let effort), .saving(_, _, let effort):
            return effort
        case .idle:
            return nil
        }
    }
}

struct FitnessSelectedDayContextModel {
    let date: Date
    let title: String
    let statusText: String
    let summaryText: String
    let trainingText: String
    let energyText: String
    let recoveryText: String
    let loadText: String
    let accentHex: String
    let isShared: Bool
    let day: HabitFitnessCalendarDay?
}

struct FitnessBadgeModel: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tintHex: String
    let isUnlocked: Bool
}

struct FitnessTrainingLogItem: Identifiable {
    let date: Date
    let mode: FitnessCheckinMode?
    let title: String
    let subtitle: String
    let statsLine: String
    let note: String
    let isShared: Bool
    let day: HabitFitnessCalendarDay?

    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct FitnessRecoveryFocusItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let tintHex: String
    let symbol: String
}

struct FitnessRecoveryManagementModel {
    let title: String
    let scoreText: String
    let statusText: String
    let detailText: String
    let accentHex: String
    let focusItems: [FitnessRecoveryFocusItem]
}

struct FitnessLoadRecoveryDayModel: Identifiable {
    let date: Date
    let label: String
    let loadScore: Int
    let recoveryScore: Int
    let stateText: String
    let tintHex: String
    let isSelected: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct FitnessLoadRecoveryLinkModel {
    let title: String
    let headline: String
    let detailText: String
    let actionText: String
    let accentHex: String
    let days: [FitnessLoadRecoveryDayModel]
}

enum FitnessPerformanceTrackRange: String, CaseIterable, Identifiable {
    case recent7
    case currentPeriod

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent7:
            return String(localized: "近 7 天")
        case .currentPeriod:
            return String(localized: "当前周期")
        }
    }
}

struct FitnessPerformanceTrackRangeModel: Identifiable {
    let range: FitnessPerformanceTrackRange
    let scoreText: String
    let changeText: String
    let statusText: String
    let detailText: String
    let accentHex: String

    var id: String { range.rawValue }
}

struct FitnessPerformanceTrackModel {
    let title: String
    let scoreText: String
    let changeText: String
    let statusText: String
    let detailText: String
    let accentHex: String
    let ranges: [FitnessPerformanceTrackRangeModel]
}

struct FitnessPerformanceReviewItem: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let detailText: String
    let tintHex: String
}

struct FitnessPerformanceReviewModel {
    let title: String
    let badgeText: String
    let summaryText: String
    let accentHex: String
    let items: [FitnessPerformanceReviewItem]
    let bestDay: HabitFitnessCalendarDay?
}
