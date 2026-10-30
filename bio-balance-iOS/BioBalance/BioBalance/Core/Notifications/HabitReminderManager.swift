/// Habit Reminder Manager 负责通知相关能力，管理本地提醒、通知调度和习惯提醒触发逻辑。
import Foundation

public struct HabitReminderSettings: Codable, Sendable, Equatable {
    public var waterDailyEnabled: Bool
    public var waterDailyHour: Int
    public var waterDailyMinute: Int
    public var waterNudgeEnabled: Bool
    public var waterNudgeIntervalMinutes: Int

    public var moodDailyEnabled: Bool
    public var moodDailyHour: Int
    public var moodDailyMinute: Int

    public init(
        waterDailyEnabled: Bool = false,
        waterDailyHour: Int = 10,
        waterDailyMinute: Int = 0,
        waterNudgeEnabled: Bool = false,
        waterNudgeIntervalMinutes: Int = 120,
        moodDailyEnabled: Bool = false,
        moodDailyHour: Int = 21,
        moodDailyMinute: Int = 0
    ) {
        self.waterDailyEnabled = waterDailyEnabled
        self.waterDailyHour = waterDailyHour
        self.waterDailyMinute = waterDailyMinute
        self.waterNudgeEnabled = waterNudgeEnabled
        self.waterNudgeIntervalMinutes = waterNudgeIntervalMinutes
        self.moodDailyEnabled = moodDailyEnabled
        self.moodDailyHour = moodDailyHour
        self.moodDailyMinute = moodDailyMinute
    }
}

public final class HabitReminderManager {
    public static let shared = HabitReminderManager()

    public enum Identifier {
        public static let waterDaily = "habit.reminder.water.daily"
        public static let waterNudge = "habit.reminder.water.nudge"
        public static let moodDaily = "habit.reminder.mood.daily"
    }

    private let settingsKey = "habitReminderSettings.v1"
    private let defaults: UserDefaults

    private init() {
        defaults = .standard
    }

    public func load() -> HabitReminderSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let value = try? JSONDecoder().decode(HabitReminderSettings.self, from: data) else {
            return HabitReminderSettings()
        }
        return value
    }

    public func save(_ settings: HabitReminderSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    public func apply(_ settings: HabitReminderSettings) {
        guard NotificationManagementPreferencesStore.shared.load().habitNudgesEnabled else {
            LocalNotificationScheduler.cancel(identifiers: [Identifier.waterDaily, Identifier.waterNudge, Identifier.moodDaily])
            return
        }

        if settings.waterDailyEnabled {
            LocalNotificationScheduler.scheduleDaily(
                identifier: Identifier.waterDaily,
                hour: settings.waterDailyHour,
                minute: settings.waterDailyMinute,
                title: String(localized: "💧 该喝水啦"),
                body: String(localized: "身体的小水库快见底了，来一杯，给专注力续个杯～")
            )
        } else {
            LocalNotificationScheduler.cancel(identifiers: [Identifier.waterDaily])
        }

        if settings.moodDailyEnabled {
            LocalNotificationScheduler.scheduleDaily(
                identifier: Identifier.moodDaily,
                hour: settings.moodDailyHour,
                minute: settings.moodDailyMinute,
                title: String(localized: "🌙 今天心情几分？"),
                body: String(localized: "花 30 秒给今天的心情盖个章，攒多了还能看出小趋势哦。")
            )
        } else {
            LocalNotificationScheduler.cancel(identifiers: [Identifier.moodDaily])
        }
    }

    public func scheduleWaterNudgeIfNeeded(settings: HabitReminderSettings) {
        guard settings.waterNudgeEnabled, NotificationManagementPreferencesStore.shared.load().habitNudgesEnabled else { return }
        LocalNotificationScheduler.cancel(identifiers: [Identifier.waterNudge])
        LocalNotificationScheduler.scheduleAfter(
            identifier: Identifier.waterNudge,
            seconds: TimeInterval(max(1, settings.waterNudgeIntervalMinutes)) * 60,
            title: String(localized: "💧 水杯在喊你"),
            body: String(localized: "距离上次喝水有点久了，抿一口，让细胞们欢呼一下。")
        )
    }

    public func cancelWaterNudge() {
        LocalNotificationScheduler.cancel(identifiers: [Identifier.waterNudge])
    }

    public func reloadWidgets() {
        WidgetRefreshCoordinator.refresh(reason: .reminders)
    }
}
