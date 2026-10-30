import Foundation

enum RecoveryChallengeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case sleepEarly
    case lowCaffeine
    case sunlight

    var id: String { rawValue }

    var definition: RecoveryChallengeDefinition {
        switch self {
        case .sleepEarly:
            return RecoveryChallengeDefinition(
                kind: self,
                title: "7 天早睡挑战",
                subtitle: "把主睡眠入睡时间连续 7 天守在 00:30 前。",
                ruleText: "主睡眠入睡时间不晚于 00:30",
                symbol: "moon.stars.fill",
                tintHex: "5E7BFF",
                successTitle: "7 天早睡挑战完成",
                successSubtitle: "你把晚间收尾节奏真正稳下来了。",
                reminderHour: 21,
                reminderMinute: 30
            )
        case .lowCaffeine:
            return RecoveryChallengeDefinition(
                kind: self,
                title: "7 天低咖啡因挑战",
                subtitle: "连续 7 天把咖啡因总量控制在恢复友好区间。",
                ruleText: "当日咖啡因总量不超过 200 mg",
                symbol: "cup.and.saucer.fill",
                tintHex: "A2845E",
                successTitle: "7 天低咖啡因挑战完成",
                successSubtitle: "这周的刺激输入控制得很克制。",
                reminderHour: 14,
                reminderMinute: 0
            )
        case .sunlight:
            return RecoveryChallengeDefinition(
                kind: self,
                title: "7 天日照挑战",
                subtitle: "连续 7 天给白天补上稳定的自然光暴露。",
                ruleText: "当日日照时长不少于 20 分钟",
                symbol: "sun.max.fill",
                tintHex: "F3A53B",
                successTitle: "7 天日照挑战完成",
                successSubtitle: "你的白天清醒信号已经更稳了。",
                reminderHour: 10,
                reminderMinute: 0
            )
        }
    }
}

struct RecoveryChallengeDefinition: Equatable, Sendable {
    let kind: RecoveryChallengeKind
    let title: String
    let subtitle: String
    let ruleText: String
    let symbol: String
    let tintHex: String
    let successTitle: String
    let successSubtitle: String
    let reminderHour: Int
    let reminderMinute: Int
}

enum RecoveryChallengeRecordStatus: String, Codable, Sendable {
    case active
    case completed
    case failed
    case abandoned

    var title: String {
        switch self {
        case .active:
            return String(localized: "进行中")
        case .completed:
            return String(localized: "已完成")
        case .failed:
            return "已失败"
        case .abandoned:
            return String(localized: "已结束")
        }
    }
}

enum RecoveryChallengeDayStatus: String, Codable, Sendable {
    case pending
    case completed
    case failed

    var title: String {
        switch self {
        case .pending:
            return String(localized: "等待完成")
        case .completed:
            return String(localized: "已达标")
        case .failed:
            return String(localized: "未达标")
        }
    }
}

struct RecoveryChallengeDayProgress: Codable, Equatable, Sendable, Identifiable {
    let date: Date
    var status: RecoveryChallengeDayStatus
    var isFinal: Bool
    var rawValue: Double?
    var rawValueText: String
    var targetText: String
    var detailText: String
    var failureReason: String?
    var badgeText: String
    var updatedAt: Date

    var id: TimeInterval { date.timeIntervalSince1970 }

    static func placeholder(for date: Date, targetText: String) -> RecoveryChallengeDayProgress {
        RecoveryChallengeDayProgress(
            date: date,
            status: .pending,
            isFinal: false,
            rawValue: nil,
            rawValueText: "等待记录",
            targetText: targetText,
            detailText: "今天还没有形成足够样本。",
            failureReason: nil,
            badgeText: "等待中",
            updatedAt: date
        )
    }
}

struct RecoveryChallengeRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let kind: RecoveryChallengeKind
    let startDate: Date
    let targetDays: Int
    var currentStreak: Int
    var status: RecoveryChallengeRecordStatus
    var reminderEnabled: Bool
    var dayProgresses: [RecoveryChallengeDayProgress]
    let createdAt: Date
    var completedAt: Date?
    var failedAt: Date?
    var abandonedAt: Date?

    init(
        id: UUID = UUID(),
        kind: RecoveryChallengeKind,
        startDate: Date,
        targetDays: Int = 7,
        currentStreak: Int = 0,
        status: RecoveryChallengeRecordStatus = .active,
        reminderEnabled: Bool = true,
        dayProgresses: [RecoveryChallengeDayProgress],
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        failedAt: Date? = nil,
        abandonedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.startDate = startDate
        self.targetDays = max(1, targetDays)
        self.currentStreak = max(0, currentStreak)
        self.status = status
        self.reminderEnabled = reminderEnabled
        self.dayProgresses = dayProgresses
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.failedAt = failedAt
        self.abandonedAt = abandonedAt
    }

    var definition: RecoveryChallengeDefinition { kind.definition }

    var latestRelevantDate: Date {
        completedAt ?? failedAt ?? abandonedAt ?? dayProgresses.last?.date ?? startDate
    }

    var currentDayIndex: Int {
        min(targetDays, max(1, currentStreak + (status == .completed ? 0 : 1)))
    }

    var progressFraction: Double {
        Double(currentStreak) / Double(max(targetDays, 1))
    }

    var todayProgress: RecoveryChallengeDayProgress? {
        let today = Calendar.current.startOfDay(for: Date())
        return dayProgresses.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })
    }
}

struct RecoveryChallengeSelectionCardModel: Identifiable {
    let kind: RecoveryChallengeKind
    let title: String
    let subtitle: String
    let ruleText: String
    let symbol: String
    let tintHex: String

    var id: String { kind.rawValue }
}

struct RecoveryChallengeHistoryPreviewItem: Identifiable {
    let recordID: UUID
    let title: String
    let subtitle: String
    let statusText: String
    let tintHex: String
    let dateText: String
    let status: RecoveryChallengeRecordStatus
    let kind: RecoveryChallengeKind

    var id: UUID { recordID }
}
