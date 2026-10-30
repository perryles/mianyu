import Foundation

protocol RecoveryChallengeDataProviding {
    func fetchSleepSummary(endingOn date: Date) async -> SleepTrendNightSummary?
    func fetchCaffeineIntake(on date: Date) async -> Int?
    func fetchSunlightMinutes(on date: Date) async -> Int?
    func localActionRecord(on date: Date) -> LocalActionDayRecord
    func localCaffeineDoseTotal(on date: Date) -> Int
}

struct RecoveryChallengeEvaluationContext {
    let now: Date
    let calendar: Calendar
    let dataProvider: RecoveryChallengeDataProviding
}

struct RecoveryChallengeEvaluator {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func evaluate(
        kind: RecoveryChallengeKind,
        date: Date,
        context: RecoveryChallengeEvaluationContext
    ) async -> RecoveryChallengeDayProgress {
        switch kind {
        case .sleepEarly:
            return await evaluateSleepEarly(on: date, context: context)
        case .lowCaffeine:
            return await evaluateLowCaffeine(on: date, context: context)
        case .sunlight:
            return await evaluateSunlight(on: date, context: context)
        }
    }

    func evaluateAndRefresh(
        record: RecoveryChallengeRecord,
        on date: Date,
        context: RecoveryChallengeEvaluationContext
    ) async -> RecoveryChallengeRecord {
        guard record.status == .active else { return record }

        let today = context.calendar.startOfDay(for: date)
        let target = max(1, record.targetDays)
        var updated = record
        var progresses = normalizedProgresses(record, calendar: context.calendar)
        var streak = 0

        for index in 0..<target {
            let targetDate = context.calendar.date(byAdding: .day, value: index, to: updated.startDate) ?? updated.startDate
            guard let progressIndex = progresses.firstIndex(where: { context.calendar.isDate($0.date, inSameDayAs: targetDate) }) else {
                continue
            }

            if updated.status != .active {
                break
            }

            let evaluated = await evaluate(kind: updated.kind, date: targetDate, context: context)
            let resolved = finalizePendingIfNeeded(evaluated, targetDate: targetDate, today: today, kind: updated.kind)
            progresses[progressIndex] = resolved

            switch resolved.status {
            case .completed:
                streak += 1
                if streak >= target {
                    updated.status = .completed
                    updated.completedAt = context.now
                    updated.reminderEnabled = false
                }
            case .failed:
                updated.status = .failed
                updated.failedAt = context.now
                updated.reminderEnabled = false
            case .pending:
                break
            }
        }

        updated.currentStreak = streak
        updated.dayProgresses = progresses.sorted { $0.date < $1.date }
        return updated
    }

    private func normalizedProgresses(_ record: RecoveryChallengeRecord, calendar: Calendar) -> [RecoveryChallengeDayProgress] {
        let target = max(1, record.targetDays)
        return (0..<target).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: record.startDate) ?? record.startDate
            if let existing = record.dayProgresses.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                return existing
            }
            return RecoveryChallengeDayProgress.placeholder(for: day, targetText: targetText(for: record.kind))
        }
    }

    private func finalizePendingIfNeeded(
        _ progress: RecoveryChallengeDayProgress,
        targetDate: Date,
        today: Date,
        kind: RecoveryChallengeKind
    ) -> RecoveryChallengeDayProgress {
        guard progress.status == .pending, targetDate < today else { return progress }
        var failed = progress
        failed.status = .failed
        failed.isFinal = true
        failed.failureReason = progress.failureReason ?? missingDataFailureText(for: kind)
        failed.badgeText = "已失手"
        failed.detailText = progress.failureReason ?? missingDataFailureText(for: kind)
        return failed
    }

    private func evaluateSleepEarly(
        on date: Date,
        context: RecoveryChallengeEvaluationContext
    ) async -> RecoveryChallengeDayProgress {
        let targetText = "不晚于 00:30"
        guard let summary = await context.dataProvider.fetchSleepSummary(endingOn: date) else {
            return RecoveryChallengeDayProgress(
                date: date,
                status: .pending,
                isFinal: false,
                rawValue: nil,
                rawValueText: "等待主睡眠",
                targetText: targetText,
                detailText: "这一天还没有读取到有效主睡眠样本。",
                failureReason: "未读取到有效主睡眠样本",
                badgeText: "等待样本",
                updatedAt: context.now
            )
        }

        let bedtimeText = shortTimeString(summary.startTime)
        let startOfDay = context.calendar.startOfDay(for: date)
        let startedBeforeTargetDay = summary.startTime < startOfDay
        let timePassed = context.calendar.dateComponents([.hour, .minute], from: summary.startTime)
        let hour = timePassed.hour ?? 0
        let minute = timePassed.minute ?? 0
        let passed = startedBeforeTargetDay || hour < 0 || (hour == 0 && minute <= 30)

        return RecoveryChallengeDayProgress(
            date: date,
            status: passed ? .completed : .failed,
            isFinal: true,
            rawValue: Double(hour * 60 + minute),
            rawValueText: bedtimeText,
            targetText: targetText,
            detailText: passed ? "昨晚入睡时间守住了目标窗口。" : "昨晚入睡时间已经晚于本次挑战目标。",
            failureReason: passed ? nil : "入睡时间晚于 00:30",
            badgeText: passed ? "已达标" : "晚睡失手",
            updatedAt: context.now
        )
    }

    private func evaluateLowCaffeine(
        on date: Date,
        context: RecoveryChallengeEvaluationContext
    ) async -> RecoveryChallengeDayProgress {
        let targetText = "<= 200 mg"
        let healthKit = await context.dataProvider.fetchCaffeineIntake(on: date) ?? 0
        let localRecord = context.dataProvider.localActionRecord(on: date)
        let localEvents = context.dataProvider.localCaffeineDoseTotal(on: date)
        let merged = max(healthKit, localRecord.caffeineMg, localEvents)
        let today = context.calendar.startOfDay(for: context.now)
        let isPast = date < today

        if merged > 200 {
            return RecoveryChallengeDayProgress(
                date: date,
                status: .failed,
                isFinal: true,
                rawValue: Double(merged),
                rawValueText: "\(merged) mg",
                targetText: targetText,
                detailText: "今天的咖啡因已经超过挑战目标，当前这一天无法再挽回。",
                failureReason: "咖啡因总量超过 200 mg",
                badgeText: "已超量",
                updatedAt: context.now
            )
        }

        if isPast {
            return RecoveryChallengeDayProgress(
                date: date,
                status: .completed,
                isFinal: true,
                rawValue: Double(merged),
                rawValueText: "\(merged) mg",
                targetText: targetText,
                detailText: "这一天的总量控制在恢复友好区间内。",
                failureReason: nil,
                badgeText: "已守住",
                updatedAt: context.now
            )
        }

        return RecoveryChallengeDayProgress(
            date: date,
            status: .pending,
            isFinal: false,
            rawValue: Double(merged),
            rawValueText: "\(merged) mg",
            targetText: targetText,
            detailText: merged == 0
                ? "今天还没有摄入咖啡因，继续守住就好。"
                : "当前还在目标范围内，今天后半段继续别追加太多。",
            failureReason: nil,
            badgeText: "保持中",
            updatedAt: context.now
        )
    }

    private func evaluateSunlight(
        on date: Date,
        context: RecoveryChallengeEvaluationContext
    ) async -> RecoveryChallengeDayProgress {
        let targetText = ">= 20 分钟"
        let healthKitMinutes = await context.dataProvider.fetchSunlightMinutes(on: date) ?? 0
        let localMinutes = context.dataProvider.localActionRecord(on: date).sunlightMinutes
        let minutes = max(healthKitMinutes, localMinutes)
        let today = context.calendar.startOfDay(for: context.now)
        let isPast = date < today

        if minutes >= 20 {
            return RecoveryChallengeDayProgress(
                date: date,
                status: .completed,
                isFinal: true,
                rawValue: Double(minutes),
                rawValueText: "\(minutes) 分钟",
                targetText: targetText,
                detailText: "这一天的自然光暴露已经达到挑战目标。",
                failureReason: nil,
                badgeText: "已达标",
                updatedAt: context.now
            )
        }

        if isPast {
            return RecoveryChallengeDayProgress(
                date: date,
                status: .failed,
                isFinal: true,
                rawValue: Double(minutes),
                rawValueText: "\(minutes) 分钟",
                targetText: targetText,
                detailText: "这一天的日照时长还没有拉到目标区间。",
                failureReason: "日照时长不足 20 分钟",
                badgeText: "未达标",
                updatedAt: context.now
            )
        }

        return RecoveryChallengeDayProgress(
            date: date,
            status: .pending,
            isFinal: false,
            rawValue: Double(minutes),
            rawValueText: "\(minutes) 分钟",
            targetText: targetText,
            detailText: minutes == 0
                ? "今天还没有形成自然光暴露样本。"
                : "已经开始累积，再补一点更容易把今天守住。",
            failureReason: nil,
            badgeText: "继续补光",
            updatedAt: context.now
        )
    }

    private func targetText(for kind: RecoveryChallengeKind) -> String {
        switch kind {
        case .sleepEarly:
            return String(localized: "不晚于 00:30")
        case .lowCaffeine:
            return "<= 200 mg"
        case .sunlight:
            return ">= 20 分钟"
        }
    }

    private func missingDataFailureText(for kind: RecoveryChallengeKind) -> String {
        switch kind {
        case .sleepEarly:
            return String(localized: "这一天没有形成可判定的主睡眠样本。")
        case .lowCaffeine:
            return String(localized: "这一天没有守住低咖啡因目标。")
        case .sunlight:
            return String(localized: "这一天的日照时长没有补到目标区间。")
        }
    }

    private func shortTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct RecoveryChallengeLiveDataProvider: RecoveryChallengeDataProviding {
    let healthKitManager: HealthKitManager
    let actionRecordStore: ActionRecordStore
    let calendar: Calendar

    init(
        healthKitManager: HealthKitManager = .shared,
        actionRecordStore: ActionRecordStore = .shared,
        calendar: Calendar = .current
    ) {
        self.healthKitManager = healthKitManager
        self.actionRecordStore = actionRecordStore
        self.calendar = calendar
    }

    func fetchSleepSummary(endingOn date: Date) async -> SleepTrendNightSummary? {
        let endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let summaries = try? await healthKitManager.fetchSleepNightSummaries(days: 2, endDate: endDate)
        return summaries?.last(where: { calendar.isDate($0.day, inSameDayAs: date) })
    }

    func fetchCaffeineIntake(on date: Date) async -> Int? {
        try? await healthKitManager.fetchDietaryCaffeine(on: date)
    }

    func fetchSunlightMinutes(on date: Date) async -> Int? {
        try? await healthKitManager.fetchTimeInDaylightMinutes(on: date)
    }

    func localActionRecord(on date: Date) -> LocalActionDayRecord {
        actionRecordStore.record(for: date)
    }

    func localCaffeineDoseTotal(on date: Date) -> Int {
        actionRecordStore.caffeineDoseEvents(on: date).reduce(0) { $0 + $1.amountMg }
    }
}
