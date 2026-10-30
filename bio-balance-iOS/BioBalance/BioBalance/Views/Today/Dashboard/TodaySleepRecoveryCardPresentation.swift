import Foundation

enum TodaySleepRecoveryCardState: Equatable, Sendable {
    case loading
    case empty
    case content
}

struct TodaySleepRecoveryMetric: Equatable, Sendable {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
}

struct TodaySleepRecoveryCardPresentation: Equatable, Sendable {
    let state: TodaySleepRecoveryCardState
    let durationMinutes: Int
    let sleepScore: Int
    let sourceDate: Date?
    let timeRangeText: String
    let badgeText: String
    let headline: String
    let context: String
    let tone: SleepPageFocusTone
    let metrics: [TodaySleepRecoveryMetric]
}

enum TodaySleepRecoveryCardPresentationBuilder {
    static func make(
        primaryData: SleepData?,
        fallbackSummary: SleepSessionSummary?,
        primaryInterval: SleepInterval?,
        goalMinutes: Int,
        nightlyHrv: Double?,
        nightlyRespirationRate: Double?,
        recentNights: [SleepTrendNightSummary],
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> TodaySleepRecoveryCardPresentation {
        guard let resolved = resolve(
            primaryData: primaryData,
            fallbackSummary: fallbackSummary,
            primaryInterval: primaryInterval
        ) else {
            return TodaySleepRecoveryCardPresentation(
                state: primaryData == nil ? .loading : .empty,
                durationMinutes: 0,
                sleepScore: 0,
                sourceDate: nil,
                timeRangeText: "",
                badgeText: String(localized: "建立中"),
                headline: String(localized: "等待昨夜睡眠记录"),
                context: String(localized: "完成一次可用睡眠后，这里会归纳夜间恢复。"),
                tone: .building,
                metrics: []
            )
        }

        let focus = SleepPageFocusBuilder.make(
            data: resolved.data,
            latestSummary: resolved.summary,
            goalMinutes: goalMinutes,
            recentNights: recentNights
        )
        let intervalText = resolved.interval.map {
            timeRangeText(start: $0.start, end: $0.end, locale: locale, calendar: calendar)
        } ?? ""
        let sourceDate = resolved.interval.map { calendar.startOfDay(for: $0.end) }

        return TodaySleepRecoveryCardPresentation(
            state: .content,
            durationMinutes: resolved.data.duration_minutes,
            sleepScore: resolved.data.sleep_score,
            sourceDate: sourceDate,
            timeRangeText: intervalText,
            badgeText: focus.badgeText,
            headline: focus.title,
            context: focus.context,
            tone: focus.tone,
            metrics: metrics(
                data: resolved.data,
                nightlyHrv: resolved.usesFallback ? nil : nightlyHrv,
                nightlyRespirationRate: resolved.usesFallback ? nil : nightlyRespirationRate
            )
        )
    }

    private struct ResolvedSleep {
        let data: SleepData
        let summary: SleepSessionSummary?
        let interval: SleepInterval?
        let usesFallback: Bool
    }

    private static func resolve(
        primaryData: SleepData?,
        fallbackSummary: SleepSessionSummary?,
        primaryInterval: SleepInterval?
    ) -> ResolvedSleep? {
        if let primaryData, primaryData.duration_minutes > 0 {
            let encodedInterval = dateInterval(from: primaryData)
            let interval = primaryInterval ?? encodedInterval
            let normalizedData = dataByAddingInterval(primaryData, interval: interval)
            return ResolvedSleep(data: normalizedData, summary: fallbackSummary, interval: interval, usesFallback: false)
        }

        guard let summary = fallbackSummary, summary.sleepDurationMinutes > 0 else {
            return nil
        }
        let interval = SleepInterval(start: summary.startTime, end: summary.endTime)
        return ResolvedSleep(
            data: SleepData(
                sleep_score: summary.sleepScore,
                duration_minutes: summary.sleepDurationMinutes,
                stages: [],
                avg_heart_rate: nil,
                avg_respiration_rate: nil,
                awake_count: nil,
                start_time: Int(summary.startTime.timeIntervalSince1970),
                end_time: Int(summary.endTime.timeIntervalSince1970)
            ),
            summary: summary,
            interval: interval,
            usesFallback: true
        )
    }

    private static func dataByAddingInterval(_ data: SleepData, interval: SleepInterval?) -> SleepData {
        guard let interval else { return data }
        return SleepData(
            sleep_score: data.sleep_score,
            duration_minutes: data.duration_minutes,
            stages: data.stages,
            avg_heart_rate: data.avg_heart_rate,
            avg_respiration_rate: data.avg_respiration_rate,
            awake_count: data.awake_count,
            start_time: data.start_time ?? Int(interval.start.timeIntervalSince1970),
            end_time: data.end_time ?? Int(interval.end.timeIntervalSince1970)
        )
    }

    private static func dateInterval(from data: SleepData) -> SleepInterval? {
        guard let rawStart = data.start_time,
              let rawEnd = data.end_time,
              rawStart > 0,
              rawEnd > rawStart else { return nil }
        return SleepInterval(start: date(from: rawStart), end: date(from: rawEnd))
    }

    private static func date(from timestamp: Int) -> Date {
        let seconds = timestamp > 10_000_000_000
            ? TimeInterval(timestamp) / 1_000
            : TimeInterval(timestamp)
        return Date(timeIntervalSince1970: seconds)
    }

    private static func metrics(
        data: SleepData,
        nightlyHrv: Double?,
        nightlyRespirationRate: Double?
    ) -> [TodaySleepRecoveryMetric] {
        var result: [TodaySleepRecoveryMetric] = []
        if let nightlyHrv, nightlyHrv > 0 {
            result.append(TodaySleepRecoveryMetric(
                title: String(localized: "夜间 HRV"),
                value: "\(Int(nightlyHrv.rounded()))",
                unit: "ms",
                systemImage: "waveform.path.ecg"
            ))
        } else if let nightlyRespirationRate, nightlyRespirationRate > 0 {
            result.append(TodaySleepRecoveryMetric(
                title: String(localized: "呼吸频率"),
                value: String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), nightlyRespirationRate),
                unit: String(localized: "次/分"),
                systemImage: "lungs.fill"
            ))
        } else if let deepMinutes = deepSleepMinutes(in: data.stages), deepMinutes > 0 {
            result.append(TodaySleepRecoveryMetric(
                title: String(localized: "深睡"),
                value: "\(deepMinutes)",
                unit: String(localized: "分"),
                systemImage: "moon.zzz.fill"
            ))
        }
        return Array(result.prefix(3))
    }

    private static func deepSleepMinutes(in stages: [SleepStage]) -> Int? {
        let value = stages
            .filter { $0.stage.localizedCaseInsensitiveContains("deep") || $0.stage.contains("深") }
            .reduce(0) { $0 + max(0, $1.duration) }
        return value > 0 ? value : nil
    }

    private static func timeRangeText(
        start: Date,
        end: Date,
        locale: Locale,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }
}
