/// Local Notification Scheduler 负责通知相关能力，管理本地提醒、通知调度和习惯提醒触发逻辑。
///
/// PEN-85：长通知暂不实现——本模块调度基础本地通知（UNNotificationRequest）；
/// 与之联动的实时推送（ReminderRealtimePushCenter）不再主动创建 Live Activity（长驻通知），
/// 仅保留既有活动更新与清理能力。
import Foundation
import UserNotifications

/// 本地通知Scheduler枚举 作为通知能力层里的能力或分类定义。
/// 负责描述本地通知与提醒调度过程中会用到的状态、分类或分支。
enum LocalNotificationScheduler {
    static let personalizedCategoryIdentifier = "personalized.recovery.reminder"

    private enum SuspendedNotificationKind: String, Codable {
        case daily
        case once
    }

    private struct SuspendedNotificationRequest: Codable, Equatable {
        let identifier: String
        let kind: SuspendedNotificationKind
        let hour: Int?
        let minute: Int?
        let date: Date?
        let title: String
        let body: String
        let categoryIdentifier: String?
        let bypassesQuietHours: Bool
    }

    private static let suspendedRequestsKey = "notificationManagement.suspendedQuietHoursRequests.v1"

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func scheduleDaily(
        identifier: String,
        hour: Int,
        minute: Int,
        title: String,
        body: String,
        bypassesQuietHours: Bool = false
    ) {
        let preferences = NotificationManagementPreferencesStore.shared.load()
        guard !isSuppressedByQuietHours(hour: hour, minute: minute, preferences: preferences, bypassesQuietHours: bypassesQuietHours) else {
            suspend(
                SuspendedNotificationRequest(
                    identifier: identifier,
                    kind: .daily,
                    hour: hour,
                    minute: minute,
                    date: nil,
                    title: title,
                    body: body,
                    categoryIdentifier: nil,
                    bypassesQuietHours: bypassesQuietHours
                )
            )
            removeActiveRequests(identifiers: [identifier])
            return
        }

        removeSuspended(identifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = notificationSound(preferences: preferences)
        content.userInfo = notificationUserInfo(bypassesQuietHours: bypassesQuietHours)

        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[通知] scheduleDaily 调度失败 id=\(identifier): \(error.localizedDescription)")
            }
        }
        ReminderRealtimePushCenter.publishDaily(
            identifier: identifier,
            hour: hour,
            minute: minute,
            title: title,
            body: body
        )
    }

    static func scheduleOnce(
        identifier: String,
        date: Date,
        title: String,
        body: String,
        categoryIdentifier: String? = nil,
        overwrite: Bool = true,
        bypassesQuietHours: Bool = false
    ) {
        if overwrite {
            cancel(identifiers: [identifier])
        }

        let preferences = NotificationManagementPreferencesStore.shared.load()
        guard !isSuppressedByQuietHours(date: date, preferences: preferences, bypassesQuietHours: bypassesQuietHours) else {
            suspend(
                SuspendedNotificationRequest(
                    identifier: identifier,
                    kind: .once,
                    hour: nil,
                    minute: nil,
                    date: date,
                    title: title,
                    body: body,
                    categoryIdentifier: categoryIdentifier,
                    bypassesQuietHours: bypassesQuietHours
                )
            )
            return
        }

        removeSuspended(identifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = notificationSound(preferences: preferences)
        content.userInfo = notificationUserInfo(bypassesQuietHours: bypassesQuietHours)
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }

        let request: UNNotificationRequest
        let interval = date.timeIntervalSinceNow
        if interval <= 60 {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
            request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        } else {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[通知] scheduleOnce 调度失败 id=\(identifier): \(error.localizedDescription)")
            }
        }
        ReminderRealtimePushCenter.publishOnce(identifier: identifier, date: date, title: title, body: body)
    }

    static func scheduleAfter(
        identifier: String,
        seconds: TimeInterval,
        title: String,
        body: String,
        bypassesQuietHours: Bool = false
    ) {
        let preferences = NotificationManagementPreferencesStore.shared.load()
        let fireDate = Date().addingTimeInterval(max(1, seconds))
        guard !isSuppressedByQuietHours(date: fireDate, preferences: preferences, bypassesQuietHours: bypassesQuietHours) else {
            suspend(
                SuspendedNotificationRequest(
                    identifier: identifier,
                    kind: .once,
                    hour: nil,
                    minute: nil,
                    date: fireDate,
                    title: title,
                    body: body,
                    categoryIdentifier: nil,
                    bypassesQuietHours: bypassesQuietHours
                )
            )
            removeActiveRequests(identifiers: [identifier])
            return
        }

        removeSuspended(identifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = notificationSound(preferences: preferences)
        content.userInfo = notificationUserInfo(bypassesQuietHours: bypassesQuietHours)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[通知] scheduleAfter 调度失败 id=\(identifier): \(error.localizedDescription)")
            }
        }
        ReminderRealtimePushCenter.publishAfter(identifier: identifier, seconds: seconds, title: title, body: body)
    }

    static func cancel(identifiers: [String]) {
        removeActiveRequests(identifiers: identifiers)
        removeSuspended(identifiers: identifiers)
    }

    static func pendingRequestIdentifiers(matching prefix: String? = nil) async -> [String] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = requests.map(\.identifier)
        guard let prefix, !prefix.isEmpty else {
            return identifiers
        }
        return identifiers.filter { $0.hasPrefix(prefix) }
    }

    static func reconcilePendingRequestsForQuietHours() async {
        let preferences = NotificationManagementPreferencesStore.shared.load()
        await restoreSuspendedRequestsIfNeeded(preferences: preferences)
        guard preferences.quietHoursEnabled else { return }

        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let quietIdentifiers = requests.compactMap { request -> String? in
            if request.content.userInfo["bypassesQuietHours"] as? Bool == true,
               preferences.criticalAlertsBypassQuietHours {
                return nil
            }

            if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger,
               let hour = calendarTrigger.dateComponents.hour {
                let minute = calendarTrigger.dateComponents.minute ?? 0
                return isWithinQuietHours(hour: hour, minute: minute, preferences: preferences) ? request.identifier : nil
            }

            if let nextDate = nextFireDate(from: request.trigger) {
                return isWithinQuietHours(date: nextDate, preferences: preferences) ? request.identifier : nil
            }

            return nil
        }

        guard !quietIdentifiers.isEmpty else { return }
        let suspended = requests
            .filter { quietIdentifiers.contains($0.identifier) }
            .compactMap(suspendedRequest(from:))
        suspended.forEach(suspend)
        removeActiveRequests(identifiers: quietIdentifiers)
    }

    static func isWithinQuietHours(date: Date = Date(), preferences: NotificationManagementPreferences = NotificationManagementPreferencesStore.shared.load()) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return isWithinQuietHours(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            preferences: preferences
        )
    }

    static func isWithinQuietHours(hour: Int, minute: Int, preferences: NotificationManagementPreferences = NotificationManagementPreferencesStore.shared.load()) -> Bool {
        guard preferences.quietHoursEnabled else { return false }

        let current = max(0, min(23, hour)) * 60 + max(0, min(59, minute))
        let start = preferences.quietStartTotalMinutes
        let end = preferences.quietEndTotalMinutes

        if start == end {
            return true
        }

        if start < end {
            return current >= start && current < end
        }

        return current >= start || current < end
    }

    private static func isSuppressedByQuietHours(
        date: Date,
        preferences: NotificationManagementPreferences,
        bypassesQuietHours: Bool
    ) -> Bool {
        if bypassesQuietHours && preferences.criticalAlertsBypassQuietHours {
            return false
        }
        return isWithinQuietHours(date: date, preferences: preferences)
    }

    private static func isSuppressedByQuietHours(
        hour: Int,
        minute: Int,
        preferences: NotificationManagementPreferences,
        bypassesQuietHours: Bool
    ) -> Bool {
        if bypassesQuietHours && preferences.criticalAlertsBypassQuietHours {
            return false
        }
        return isWithinQuietHours(hour: hour, minute: minute, preferences: preferences)
    }

    private static func notificationSound(preferences: NotificationManagementPreferences) -> UNNotificationSound? {
        return preferences.deliveryStyle == .quiet ? nil : .default
    }

    private static func notificationUserInfo(bypassesQuietHours: Bool) -> [AnyHashable: Any] {
        guard bypassesQuietHours else { return [:] }
        return ["bypassesQuietHours": true]
    }

    private static func removeActiveRequests(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        ReminderRealtimePushCenter.cancel(identifiers: identifiers)
    }

    private static func suspend(_ request: SuspendedNotificationRequest) {
        var requests = loadSuspendedRequests()
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
        saveSuspendedRequests(requests)
    }

    private static func removeSuspended(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        var requests = loadSuspendedRequests()
        let originalCount = requests.count
        requests.removeAll { identifiers.contains($0.identifier) }
        guard requests.count != originalCount else { return }
        saveSuspendedRequests(requests)
    }

    private static func loadSuspendedRequests() -> [SuspendedNotificationRequest] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: suspendedRequestsKey),
              let requests = try? JSONDecoder().decode([SuspendedNotificationRequest].self, from: data) else {
            return []
        }
        return requests
    }

    private static func saveSuspendedRequests(_ requests: [SuspendedNotificationRequest]) {
        let defaults = UserDefaults.standard
        guard let data = try? JSONEncoder().encode(requests) else { return }
        defaults.set(data, forKey: suspendedRequestsKey)
    }

    private static func restoreSuspendedRequestsIfNeeded(preferences: NotificationManagementPreferences) async {
        let now = Date()
        let requests = loadSuspendedRequests()
        guard !requests.isEmpty else { return }

        var remaining: [SuspendedNotificationRequest] = []
        for request in requests {
            if shouldKeepSuspended(request, preferences: preferences, now: now) {
                remaining.append(request)
                continue
            }

            switch request.kind {
            case .daily:
                scheduleDaily(
                    identifier: request.identifier,
                    hour: request.hour ?? 0,
                    minute: request.minute ?? 0,
                    title: request.title,
                    body: request.body,
                    bypassesQuietHours: request.bypassesQuietHours
                )
            case .once:
                guard let date = request.date, date > now else { continue }
                scheduleOnce(
                    identifier: request.identifier,
                    date: date,
                    title: request.title,
                    body: request.body,
                    categoryIdentifier: request.categoryIdentifier,
                    bypassesQuietHours: request.bypassesQuietHours
                )
            }
        }

        let refreshed = loadSuspendedRequests()
        let restoredIdentifiers = Set(requests.map(\.identifier)).subtracting(remaining.map(\.identifier))
        let merged = refreshed.filter { !restoredIdentifiers.contains($0.identifier) } + remaining
        saveSuspendedRequests(uniqueSuspendedRequests(merged))
    }

    private static func shouldKeepSuspended(
        _ request: SuspendedNotificationRequest,
        preferences: NotificationManagementPreferences,
        now: Date
    ) -> Bool {
        switch request.kind {
        case .daily:
            return isSuppressedByQuietHours(
                hour: request.hour ?? 0,
                minute: request.minute ?? 0,
                preferences: preferences,
                bypassesQuietHours: request.bypassesQuietHours
            )
        case .once:
            guard let date = request.date, date > now else { return false }
            return isSuppressedByQuietHours(
                date: date,
                preferences: preferences,
                bypassesQuietHours: request.bypassesQuietHours
            )
        }
    }

    private static func suspendedRequest(from request: UNNotificationRequest) -> SuspendedNotificationRequest? {
        let bypassesQuietHours = request.content.userInfo["bypassesQuietHours"] as? Bool == true

        if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger,
           let hour = calendarTrigger.dateComponents.hour {
            let minute = calendarTrigger.dateComponents.minute ?? 0
            if calendarTrigger.repeats {
                return SuspendedNotificationRequest(
                    identifier: request.identifier,
                    kind: .daily,
                    hour: hour,
                    minute: minute,
                    date: nil,
                    title: request.content.title,
                    body: request.content.body,
                    categoryIdentifier: request.content.categoryIdentifier.isEmpty ? nil : request.content.categoryIdentifier,
                    bypassesQuietHours: bypassesQuietHours
                )
            }

            return SuspendedNotificationRequest(
                identifier: request.identifier,
                kind: .once,
                hour: nil,
                minute: nil,
                date: Calendar.current.date(from: calendarTrigger.dateComponents),
                title: request.content.title,
                body: request.content.body,
                categoryIdentifier: request.content.categoryIdentifier.isEmpty ? nil : request.content.categoryIdentifier,
                bypassesQuietHours: bypassesQuietHours
            )
        }

        if let nextDate = nextFireDate(from: request.trigger) {
            return SuspendedNotificationRequest(
                identifier: request.identifier,
                kind: .once,
                hour: nil,
                minute: nil,
                date: nextDate,
                title: request.content.title,
                body: request.content.body,
                categoryIdentifier: request.content.categoryIdentifier.isEmpty ? nil : request.content.categoryIdentifier,
                bypassesQuietHours: bypassesQuietHours
            )
        }

        return nil
    }

    private static func nextFireDate(from trigger: UNNotificationTrigger?) -> Date? {
        if let calendarTrigger = trigger as? UNCalendarNotificationTrigger {
            return calendarTrigger.nextTriggerDate()
        }

        if let timeIntervalTrigger = trigger as? UNTimeIntervalNotificationTrigger {
            return Date().addingTimeInterval(timeIntervalTrigger.timeInterval)
        }

        return nil
    }

    private static func uniqueSuspendedRequests(_ requests: [SuspendedNotificationRequest]) -> [SuspendedNotificationRequest] {
        var seen: Set<String> = []
        var unique: [SuspendedNotificationRequest] = []
        for request in requests.reversed() where !seen.contains(request.identifier) {
            seen.insert(request.identifier)
            unique.append(request)
        }
        return Array(unique.reversed())
    }
}
