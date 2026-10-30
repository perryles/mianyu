import Foundation

enum NotificationContentDetailLevel: String, Codable, CaseIterable, Identifiable {
    case brief
    case balanced
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brief: return String(localized: "简短")
        case .balanced: return String(localized: "适中")
        case .detailed: return String(localized: "详细")
        }
    }

    var subtitle: String {
        switch self {
        case .brief: return String(localized: "只保留最重要的动作")
        case .balanced: return String(localized: "动作和理由都给一点")
        case .detailed: return String(localized: "加入更多背景和趋势线索")
        }
    }
}

enum NotificationDeliveryStyle: String, Codable, CaseIterable, Identifiable {
    case quiet
    case standard
    case focused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet: return String(localized: "轻提醒")
        case .standard: return String(localized: "标准")
        case .focused: return String(localized: "重点")
        }
    }

    var subtitle: String {
        switch self {
        case .quiet: return String(localized: "减少声音，只保留必要提示")
        case .standard: return String(localized: "按常规方式送达")
        case .focused: return String(localized: "健康异常和恢复提醒更醒目")
        }
    }
}

struct NotificationManagementPreferences: Codable, Equatable, Sendable {
    var healthAlertsEnabled: Bool
    var recoveryAdviceEnabled: Bool
    var habitNudgesEnabled: Bool
    var summaryReportsEnabled: Bool
    var socialCareEnabled: Bool
    var productUpdatesEnabled: Bool

    var includeHealthValues: Bool
    var includeActionSuggestion: Bool
    var includeReasonExplanation: Bool
    var includeTrendSummary: Bool

    var contentDetailLevel: NotificationContentDetailLevel
    var deliveryStyle: NotificationDeliveryStyle
    var quietHoursEnabled: Bool
    var quietStartHour: Int
    var quietStartMinute: Int
    var quietEndHour: Int
    var quietEndMinute: Int
    var criticalAlertsBypassQuietHours: Bool

    init(
        healthAlertsEnabled: Bool = true,
        recoveryAdviceEnabled: Bool = true,
        habitNudgesEnabled: Bool = true,
        summaryReportsEnabled: Bool = true,
        socialCareEnabled: Bool = true,
        productUpdatesEnabled: Bool = false,
        includeHealthValues: Bool = true,
        includeActionSuggestion: Bool = true,
        includeReasonExplanation: Bool = true,
        includeTrendSummary: Bool = true,
        contentDetailLevel: NotificationContentDetailLevel = .balanced,
        deliveryStyle: NotificationDeliveryStyle = .standard,
        quietHoursEnabled: Bool = true,
        quietStartHour: Int = 0,
        quietStartMinute: Int = 0,
        quietEndHour: Int = 8,
        quietEndMinute: Int = 0,
        criticalAlertsBypassQuietHours: Bool = false
    ) {
        self.healthAlertsEnabled = healthAlertsEnabled
        self.recoveryAdviceEnabled = recoveryAdviceEnabled
        self.habitNudgesEnabled = habitNudgesEnabled
        self.summaryReportsEnabled = summaryReportsEnabled
        self.socialCareEnabled = socialCareEnabled
        self.productUpdatesEnabled = productUpdatesEnabled
        self.includeHealthValues = includeHealthValues
        self.includeActionSuggestion = includeActionSuggestion
        self.includeReasonExplanation = includeReasonExplanation
        self.includeTrendSummary = includeTrendSummary
        self.contentDetailLevel = contentDetailLevel
        self.deliveryStyle = deliveryStyle
        self.quietHoursEnabled = quietHoursEnabled
        self.quietStartHour = Self.clampedHour(quietStartHour)
        self.quietStartMinute = Self.clampedMinute(quietStartMinute)
        self.quietEndHour = Self.clampedHour(quietEndHour)
        self.quietEndMinute = Self.clampedMinute(quietEndMinute)
        self.criticalAlertsBypassQuietHours = criticalAlertsBypassQuietHours
    }

    enum CodingKeys: String, CodingKey {
        case healthAlertsEnabled
        case recoveryAdviceEnabled
        case habitNudgesEnabled
        case summaryReportsEnabled
        case socialCareEnabled
        case productUpdatesEnabled
        case includeHealthValues
        case includeActionSuggestion
        case includeReasonExplanation
        case includeTrendSummary
        case contentDetailLevel
        case deliveryStyle
        case quietHoursEnabled
        case quietStartHour
        case quietStartMinute
        case quietEndHour
        case quietEndMinute
        case criticalAlertsBypassQuietHours
    }

    init(from decoder: Decoder) throws {
        let defaults = NotificationManagementPreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        healthAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthAlertsEnabled) ?? defaults.healthAlertsEnabled
        recoveryAdviceEnabled = try container.decodeIfPresent(Bool.self, forKey: .recoveryAdviceEnabled) ?? defaults.recoveryAdviceEnabled
        habitNudgesEnabled = try container.decodeIfPresent(Bool.self, forKey: .habitNudgesEnabled) ?? defaults.habitNudgesEnabled
        summaryReportsEnabled = try container.decodeIfPresent(Bool.self, forKey: .summaryReportsEnabled) ?? defaults.summaryReportsEnabled
        socialCareEnabled = try container.decodeIfPresent(Bool.self, forKey: .socialCareEnabled) ?? defaults.socialCareEnabled
        productUpdatesEnabled = try container.decodeIfPresent(Bool.self, forKey: .productUpdatesEnabled) ?? defaults.productUpdatesEnabled
        includeHealthValues = try container.decodeIfPresent(Bool.self, forKey: .includeHealthValues) ?? defaults.includeHealthValues
        includeActionSuggestion = try container.decodeIfPresent(Bool.self, forKey: .includeActionSuggestion) ?? defaults.includeActionSuggestion
        includeReasonExplanation = try container.decodeIfPresent(Bool.self, forKey: .includeReasonExplanation) ?? defaults.includeReasonExplanation
        includeTrendSummary = try container.decodeIfPresent(Bool.self, forKey: .includeTrendSummary) ?? defaults.includeTrendSummary
        contentDetailLevel = try container.decodeIfPresent(NotificationContentDetailLevel.self, forKey: .contentDetailLevel) ?? defaults.contentDetailLevel
        deliveryStyle = try container.decodeIfPresent(NotificationDeliveryStyle.self, forKey: .deliveryStyle) ?? defaults.deliveryStyle
        quietHoursEnabled = try container.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? defaults.quietHoursEnabled
        quietStartHour = Self.clampedHour(try container.decodeIfPresent(Int.self, forKey: .quietStartHour) ?? defaults.quietStartHour)
        quietStartMinute = Self.clampedMinute(try container.decodeIfPresent(Int.self, forKey: .quietStartMinute) ?? defaults.quietStartMinute)
        quietEndHour = Self.clampedHour(try container.decodeIfPresent(Int.self, forKey: .quietEndHour) ?? defaults.quietEndHour)
        quietEndMinute = Self.clampedMinute(try container.decodeIfPresent(Int.self, forKey: .quietEndMinute) ?? defaults.quietEndMinute)
        criticalAlertsBypassQuietHours = try container.decodeIfPresent(Bool.self, forKey: .criticalAlertsBypassQuietHours) ?? defaults.criticalAlertsBypassQuietHours
    }

    var enabledReceiveTypeCount: Int {
        [
            healthAlertsEnabled,
            recoveryAdviceEnabled,
            habitNudgesEnabled,
            summaryReportsEnabled,
            socialCareEnabled,
            productUpdatesEnabled
        ].filter { $0 }.count
    }

    var contentSummary: String {
        var parts: [String] = [contentDetailLevel.title]
        if includeActionSuggestion {
            parts.append(String(localized: "行动建议"))
        }
        if includeHealthValues {
            parts.append(String(localized: "关键数值"))
        }
        if includeTrendSummary {
            parts.append(String(localized: "趋势"))
        }
        return parts.joined(separator: " · ")
    }

    var quietHoursSummary: String {
        guard quietHoursEnabled else { return String(localized: "未开启免打扰") }
        return quietHoursTimeRangeText
    }

    var quietHoursTimeRangeText: String {
        "\(quietStartTimeText)-\(quietEndTimeText)"
    }

    var quietStartTimeText: String {
        Self.timeText(hour: quietStartHour, minute: quietStartMinute)
    }

    var quietEndTimeText: String {
        Self.timeText(hour: quietEndHour, minute: quietEndMinute)
    }

    var quietStartTotalMinutes: Int {
        quietStartHour * 60 + quietStartMinute
    }

    var quietEndTotalMinutes: Int {
        quietEndHour * 60 + quietEndMinute
    }

    mutating func setQuietStart(totalMinutes: Int) {
        let normalized = Self.normalizedMinuteOfDay(totalMinutes)
        quietStartHour = normalized / 60
        quietStartMinute = normalized % 60
    }

    mutating func setQuietEnd(totalMinutes: Int) {
        let normalized = Self.normalizedMinuteOfDay(totalMinutes)
        quietEndHour = normalized / 60
        quietEndMinute = normalized % 60
    }

    static func timeText(hour: Int, minute: Int) -> String {
        "\(String(format: "%02d", clampedHour(hour))):\(String(format: "%02d", clampedMinute(minute)))"
    }

    private static func clampedHour(_ hour: Int) -> Int {
        min(23, max(0, hour))
    }

    private static func clampedMinute(_ minute: Int) -> Int {
        min(59, max(0, minute))
    }

    private static func normalizedMinuteOfDay(_ totalMinutes: Int) -> Int {
        let minutesPerDay = 24 * 60
        return ((totalMinutes % minutesPerDay) + minutesPerDay) % minutesPerDay
    }
}

final class NotificationManagementPreferencesStore {
    static let shared = NotificationManagementPreferencesStore()

    private let defaults: UserDefaults
    private let key = "notificationManagement.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> NotificationManagementPreferences {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(NotificationManagementPreferences.self, from: data) else {
            return NotificationManagementPreferences()
        }
        return value
    }

    func save(_ preferences: NotificationManagementPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
