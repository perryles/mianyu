import Foundation

enum UnifiedReminderSource: String, Codable, CaseIterable, Sendable {
    case personalized
    case recoveryChallenge
    case dailyGoal
}

enum UnifiedReminderCadence: Codable, Equatable, Sendable {
    case daily(hour: Int, minute: Int)
    case once(Date)
}

struct UnifiedReminderCandidate: Codable, Equatable, Sendable {
    let identifier: String
    let source: UnifiedReminderSource
    let cadence: UnifiedReminderCadence
    let priority: Int
    let title: String
    let body: String
    let categoryIdentifier: String?
    let updatedAt: Date
}

enum UnifiedReminderWindowArbitrator {
    static let defaultWindowMinutes = 60

    static func winningIdentifiers(
        from candidates: [UnifiedReminderCandidate],
        calendar: Calendar = .current,
        windowMinutes: Int = defaultWindowMinutes
    ) -> Set<String> {
        let resolvedWindow = max(1, windowMinutes)
        let ranked = candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.identifier < rhs.identifier
        }

        var winners: [UnifiedReminderCandidate] = []
        for candidate in ranked where !winners.contains(where: {
            conflicts(candidate, $0, calendar: calendar, windowMinutes: resolvedWindow)
        }) {
            winners.append(candidate)
        }
        return Set(winners.map(\.identifier))
    }

    static func conflicts(
        _ lhs: UnifiedReminderCandidate,
        _ rhs: UnifiedReminderCandidate,
        calendar: Calendar = .current,
        windowMinutes: Int = defaultWindowMinutes
    ) -> Bool {
        switch (lhs.cadence, rhs.cadence) {
        case let (.daily(lhsHour, lhsMinute), .daily(rhsHour, rhsMinute)):
            return circularMinuteDistance(
                lhsHour * 60 + lhsMinute,
                rhsHour * 60 + rhsMinute
            ) < max(1, windowMinutes)

        case let (.once(lhsDate), .once(rhsDate)):
            return abs(lhsDate.timeIntervalSince(rhsDate)) < Double(max(1, windowMinutes) * 60)

        case let (.daily(hour, minute), .once(date)),
             let (.once(date), .daily(hour, minute)):
            let components = calendar.dateComponents([.hour, .minute], from: date)
            let onceMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            return circularMinuteDistance(hour * 60 + minute, onceMinute) < max(1, windowMinutes)
        }
    }

    private static func circularMinuteDistance(_ lhs: Int, _ rhs: Int) -> Int {
        let minutesPerDay = 24 * 60
        let direct = abs(normalizedMinute(lhs) - normalizedMinute(rhs))
        return min(direct, minutesPerDay - direct)
    }

    private static func normalizedMinute(_ value: Int) -> Int {
        let minutesPerDay = 24 * 60
        return ((value % minutesPerDay) + minutesPerDay) % minutesPerDay
    }
}

protocol UnifiedReminderScheduling: Sendable {
    func scheduleDaily(
        identifier: String,
        hour: Int,
        minute: Int,
        title: String,
        body: String,
        source: UnifiedReminderSource,
        priority: Int
    )

    func scheduleOnce(
        identifier: String,
        date: Date,
        title: String,
        body: String,
        categoryIdentifier: String?,
        source: UnifiedReminderSource,
        priority: Int
    )

    func cancel(identifiers: [String])
}

protocol UnifiedReminderDelivering: Sendable {
    func scheduleDaily(identifier: String, hour: Int, minute: Int, title: String, body: String)
    func scheduleOnce(identifier: String, date: Date, title: String, body: String, categoryIdentifier: String?)
    func cancel(identifiers: [String])
}

struct SystemUnifiedReminderDelivery: UnifiedReminderDelivering {
    func scheduleDaily(identifier: String, hour: Int, minute: Int, title: String, body: String) {
        LocalNotificationScheduler.scheduleDaily(
            identifier: identifier,
            hour: hour,
            minute: minute,
            title: title,
            body: body
        )
    }

    func scheduleOnce(
        identifier: String,
        date: Date,
        title: String,
        body: String,
        categoryIdentifier: String?
    ) {
        LocalNotificationScheduler.scheduleOnce(
            identifier: identifier,
            date: date,
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            overwrite: true
        )
    }

    func cancel(identifiers: [String]) {
        LocalNotificationScheduler.cancel(identifiers: identifiers)
    }
}

final class UnifiedReminderWindowCoordinator: UnifiedReminderScheduling, @unchecked Sendable {
    static let shared = UnifiedReminderWindowCoordinator()

    private let defaults: UserDefaults
    private let delivery: UnifiedReminderDelivering
    private let calendar: Calendar
    private let nowProvider: @Sendable () -> Date
    private let windowMinutes: Int
    private let lock = NSRecursiveLock()
    private let storageKey = "notificationManagement.unifiedReminderCandidates.v1"

    init(
        defaults: UserDefaults = .standard,
        delivery: UnifiedReminderDelivering = SystemUnifiedReminderDelivery(),
        calendar: Calendar = .autoupdatingCurrent,
        windowMinutes: Int = UnifiedReminderWindowArbitrator.defaultWindowMinutes,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.delivery = delivery
        self.calendar = calendar
        self.windowMinutes = max(1, windowMinutes)
        self.nowProvider = nowProvider
    }

    func scheduleDaily(
        identifier: String,
        hour: Int,
        minute: Int,
        title: String,
        body: String,
        source: UnifiedReminderSource,
        priority: Int
    ) {
        let candidate = UnifiedReminderCandidate(
            identifier: identifier,
            source: source,
            cadence: .daily(hour: clampedHour(hour), minute: clampedMinute(minute)),
            priority: priority,
            title: title,
            body: body,
            categoryIdentifier: nil,
            updatedAt: nowProvider()
        )
        upsert(candidate)
    }

    func scheduleOnce(
        identifier: String,
        date: Date,
        title: String,
        body: String,
        categoryIdentifier: String?,
        source: UnifiedReminderSource,
        priority: Int
    ) {
        let candidate = UnifiedReminderCandidate(
            identifier: identifier,
            source: source,
            cadence: .once(date),
            priority: priority,
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            updatedAt: nowProvider()
        )
        upsert(candidate)
    }

    func cancel(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let removed = Set(identifiers)
        var candidates = pruned(loadCandidates())
        candidates.removeAll { removed.contains($0.identifier) }
        saveCandidates(candidates)
        delivery.cancel(identifiers: identifiers)
        reconcile(candidates)
    }

    func winningIdentifiers() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return UnifiedReminderWindowArbitrator.winningIdentifiers(
            from: pruned(loadCandidates()),
            calendar: calendar,
            windowMinutes: windowMinutes
        )
    }

    private func upsert(_ candidate: UnifiedReminderCandidate) {
        lock.lock()
        defer { lock.unlock() }

        var candidates = pruned(loadCandidates())
        candidates.removeAll { $0.identifier == candidate.identifier }
        candidates.append(candidate)
        saveCandidates(candidates)
        reconcile(candidates)
    }

    private func reconcile(_ candidates: [UnifiedReminderCandidate]) {
        let winners = UnifiedReminderWindowArbitrator.winningIdentifiers(
            from: candidates,
            calendar: calendar,
            windowMinutes: windowMinutes
        )

        for candidate in candidates {
            guard winners.contains(candidate.identifier) else {
                delivery.cancel(identifiers: [candidate.identifier])
                continue
            }

            switch candidate.cadence {
            case let .daily(hour, minute):
                delivery.scheduleDaily(
                    identifier: candidate.identifier,
                    hour: hour,
                    minute: minute,
                    title: candidate.title,
                    body: candidate.body
                )
            case let .once(date):
                delivery.scheduleOnce(
                    identifier: candidate.identifier,
                    date: date,
                    title: candidate.title,
                    body: candidate.body,
                    categoryIdentifier: candidate.categoryIdentifier
                )
            }
        }
    }

    private func pruned(_ candidates: [UnifiedReminderCandidate]) -> [UnifiedReminderCandidate] {
        let now = nowProvider()
        return candidates.filter { candidate in
            switch candidate.cadence {
            case .daily:
                return true
            case let .once(date):
                return date > now
            }
        }
    }

    private func loadCandidates() -> [UnifiedReminderCandidate] {
        guard let data = defaults.data(forKey: storageKey),
              let candidates = try? JSONDecoder().decode([UnifiedReminderCandidate].self, from: data) else {
            return []
        }
        return candidates
    }

    private func saveCandidates(_ candidates: [UnifiedReminderCandidate]) {
        guard let data = try? JSONEncoder().encode(candidates) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func clampedHour(_ hour: Int) -> Int {
        min(23, max(0, hour))
    }

    private func clampedMinute(_ minute: Int) -> Int {
        min(59, max(0, minute))
    }
}
