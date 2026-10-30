/// ReminderRealtimePushCenter 负责提醒的实时推送展示（Live Activity / 灵动岛）。
///
/// PEN-85：长通知暂不实现——本模块不主动创建 Live Activity（长驻通知），避免提前数小时
/// 长驻打扰用户、聚焦核心功能稳定。仅保留「更新既有活动」与「清理遗留活动」能力，以及
/// dynamicIsland/锁屏短形态（MianyuWidgetLiveActivity）；基础本地通知不受影响。
import Foundation

nonisolated struct ReminderRealtimePushEvent: Sendable {
    let identifier: String
    let title: String
    let body: String
    let primaryValue: String
    let fireDate: Date?
    let symbolName: String
    let tone: String

    nonisolated var detail: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ReminderRealtimePushCenter {
    static func publishDaily(
        identifier: String,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) {
        let nextFireDate = nextDate(hour: hour, minute: minute)
        publish(
            ReminderRealtimePushEvent(
                identifier: identifier,
                title: title,
                body: body,
                primaryValue: String(localized: "每天 \(timeText(hour: hour, minute: minute))"),
                fireDate: nextFireDate,
                symbolName: symbolName(for: identifier, title: title),
                tone: tone(for: identifier)
            )
        )
    }

    static func publishOnce(identifier: String, date: Date, title: String, body: String) {
        publish(
            ReminderRealtimePushEvent(
                identifier: identifier,
                title: title,
                body: body,
                primaryValue: timeText(for: date),
                fireDate: date,
                symbolName: symbolName(for: identifier, title: title),
                tone: tone(for: identifier)
            )
        )
    }

    static func publishAfter(identifier: String, seconds: TimeInterval, title: String, body: String) {
        let fireDate = Date().addingTimeInterval(max(1, seconds))
        publish(
            ReminderRealtimePushEvent(
                identifier: identifier,
                title: title,
                body: body,
                primaryValue: relativeTimeText(seconds: seconds),
                fireDate: fireDate,
                symbolName: symbolName(for: identifier, title: title),
                tone: tone(for: identifier)
            )
        )
    }

    static func cancel(identifiers: [String]) {
        guard identifiers.isEmpty == false else { return }
        WidgetSyncService.refresh(reason: .reminders, force: true)

        #if canImport(ActivityKit) && os(iOS)
        Task {
            await ReminderLiveActivityController.shared.cancel(matching: identifiers)
        }
        #endif
    }

    /// 发布提醒的实时展示事件。
    ///
    /// PEN-85：长通知暂不实现——仅更新既有 Live Activity（如历史遗留活动），不主动创建；
    /// `WidgetSyncService.refresh` 与基础本地通知保持原行为。
    private static func publish(_ event: ReminderRealtimePushEvent) {
        WidgetSyncService.refresh(reason: .reminders, force: true)

        #if canImport(ActivityKit) && os(iOS)
        Task {
            await ReminderLiveActivityController.shared.publish(event)
        }
        #endif
    }

    private static func nextDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0
        let today = calendar.date(from: components) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    private static func timeText(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", min(max(hour, 0), 23), min(max(minute, 0), 59))
    }

    private static func timeText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private static func relativeTimeText(seconds: TimeInterval) -> String {
        let minutes = Int((max(1, seconds) / 60).rounded(.up))
        if minutes < 60 { return String(localized: "\(minutes) 分钟后") }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0
            ? String(localized: "\(hours) 小时后")
            : String(localized: "\(hours) 小时 \(remainingMinutes) 分钟后")
    }

    private static func symbolName(for identifier: String, title: String) -> String {
        let combined = "\(identifier) \(title)"
        if combined.contains("water") || combined.contains("喝水") || combined.contains("补水") {
            return "drop.fill"
        }
        if combined.contains("mood") || combined.contains("情绪") || combined.contains("压力") {
            return "heart.text.square.fill"
        }
        if combined.contains("sleep") || combined.contains("bedtime") || combined.contains("睡") {
            return "moon.stars.fill"
        }
        if combined.contains("caffeine") || combined.contains("咖啡") {
            return "cup.and.saucer.fill"
        }
        if combined.contains("medication") || combined.contains("药") || combined.contains("补录体感") {
            return "pills.fill"
        }
        return "bell.badge.fill"
    }

    private static func tone(for identifier: String) -> String {
        if identifier.contains("sleep") || identifier.contains("bedtime") {
            return "relaxed"
        }
        if identifier.contains("water") || identifier.contains("caffeine") {
            return "mild"
        }
        return "steady"
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import os.log

actor ReminderLiveActivityController {
    static let shared = ReminderLiveActivityController()
    nonisolated private static let logger = Logger(subsystem: "com.biobalance", category: "LiveActivity")

    /// 系统对应用内并发 Live Activity 数量有限制，超出时优先结束最早创建的活动
    private static let maxConcurrentActivities = 4

    /// 追踪所有活跃的提醒标识符（支持多个并发活动）
    private var activeIdentifiers: Set<String> = []

    /// 发布提醒到 Live Activity。
    ///
    /// PEN-85：长通知暂不实现——本方法不主动创建新的 Live Activity（避免提前数小时长驻、
    /// 打扰用户）。仅保留「更新既有活动」分支：更新历史遗留/已存在的活动，不再调用
    /// `Activity.request` 新增长驻活动；基础本地通知（UNNotificationRequest）不受影响。
    func publish(_ event: ReminderRealtimePushEvent) async {
        // 同一提醒标识符对应同一活动：存在且仍 active 则更新（不新建）
        guard let existing = Self.reminderActivities.first(where: {
            $0.attributes.reminderIdentifier == event.identifier && $0.activityState == .active
        }) else {
            Self.logger.debug("无既有 Live Activity 可更新 id=\(event.identifier)，跳过（PEN-85 不主动创建）")
            return
        }

        let state = MianyuWidgetAttributes.ContentState(
            title: event.title,
            primaryValue: event.primaryValue,
            detail: event.detail,
            tone: event.tone,
            symbolName: event.symbolName,
            supplementalSubtitle: "\(event.primaryValue) · \(event.title)",
            fireDate: event.fireDate,
            startDate: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: staleDate(for: event),
            relevanceScore: 0.85
        )

        await existing.update(content)
        Self.logger.debug("已更新现有 Live Activity id=\(event.identifier)")
    }

    func cancel(matching identifiers: [String]) async {
        let matchedIdentifiers = activeIdentifiers.intersection(identifiers)
        guard !matchedIdentifiers.isEmpty else { return }
        activeIdentifiers.subtract(matchedIdentifiers)

        // 只结束标识符匹配的活动，不影响其他并发提醒；无标识符的旧版活动一并清理
        for activity in Self.reminderActivities {
            guard activity.activityState == .active else { continue }
            let identifier = activity.attributes.reminderIdentifier
            guard identifier == nil || matchedIdentifiers.contains(identifier!) else { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        Self.logger.debug("已取消 Live Activity identifiers=\(matchedIdentifiers)")
    }

    /// 应用启动时清理上次残留的 Live Activity
    func cleanupStaleActivities() async {
        let activities = Activity<MianyuWidgetAttributes>.activities
        guard !activities.isEmpty else { return }

        let now = Date()
        for activity in activities {
            // 非 active 状态，或 staleDate 已过期的僵尸活动，一律立即结束
            let isStale = activity.content.staleDate.map { $0 < now } ?? false
            guard activity.activityState != .active || isStale else { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        // 以系统侧存活的活动为准，重建追踪状态
        activeIdentifiers = Set(
            Self.reminderActivities
                .filter { $0.activityState == .active }
                .compactMap { $0.attributes.reminderIdentifier }
        )
        Self.logger.debug("启动清理完成，当前活动数=\(Activity<MianyuWidgetAttributes>.activities.count)")
    }

    private static var reminderActivities: [Activity<MianyuWidgetAttributes>] {
        Activity<MianyuWidgetAttributes>.activities.filter { $0.attributes.name == "提醒" }
    }

    /// 并发活动达到上限时，结束触发时间最早的活动为新活动腾位
    private func trimActivitiesIfNeeded() async {
        let active = Self.reminderActivities.filter { $0.activityState == .active }
        guard active.count >= Self.maxConcurrentActivities else { return }

        let sorted = active.sorted {
            ($0.content.state.fireDate ?? .distantPast) < ($1.content.state.fireDate ?? .distantPast)
        }
        for activity in sorted.prefix(active.count - Self.maxConcurrentActivities + 1) {
            if let identifier = activity.attributes.reminderIdentifier {
                activeIdentifiers.remove(identifier)
            }
            await activity.end(nil, dismissalPolicy: .immediate)
            Self.logger.debug("并发达上限，已结束最早活动 id=\(activity.attributes.reminderIdentifier ?? "-")")
        }
    }

    private func staleDate(for event: ReminderRealtimePushEvent) -> Date? {
        let maxLiveDate = Date().addingTimeInterval(8 * 60 * 60)
        guard let fireDate = event.fireDate else { return maxLiveDate }
        return min(fireDate.addingTimeInterval(30 * 60), maxLiveDate)
    }
}
#endif
