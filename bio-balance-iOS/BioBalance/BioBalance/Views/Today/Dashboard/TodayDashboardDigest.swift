import Foundation

enum TodayDashboardPatternTone: Equatable, Sendable {
    case positive
    case attention
    case neutral
    case muted
}

struct TodayDashboardPattern: Equatable, Sendable {
    let title: String
    let systemImage: String
    let tone: TodayDashboardPatternTone
}

struct TodayDashboardDigest {
    let patterns: [TodayDashboardPattern]
    let previousWeekReview: WeeklyHealthReview
    let previousWeekRangeText: String
}

struct TodayPreviousWeekCardPresentation: Equatable {
    let primaryValue: String
    let primaryLabel: String
    let comparisonText: String
    let coverageText: String
    let supportKind: ReportMetricKind?
    let attentionKind: ReportMetricKind?
}

enum TodayPreviousWeekCardPresentationBuilder {
    static func make(review: WeeklyHealthReview) -> TodayPreviousWeekCardPresentation {
        let comparisonText: String
        if let delta = review.scoreDelta {
            if delta > 0 {
                comparisonText = String(localized: "较前周 +\(delta)")
            } else if delta < 0 {
                comparisonText = String(localized: "较前周 \(delta)")
            } else {
                comparisonText = String(localized: "与前周持平")
            }
        } else {
            comparisonText = String(localized: "等待可比样本")
        }

        return TodayPreviousWeekCardPresentation(
            primaryValue: review.averageScore.map(String.init) ?? "--",
            primaryLabel: String(localized: "上周均分"),
            comparisonText: comparisonText,
            coverageText: String(localized: "\(review.scoredDays)/\(review.expectedDays) 天评分 · 指标覆盖 \(review.overallCoveragePercent)%"),
            supportKind: review.supportKind,
            attentionKind: review.attentionKind
        )
    }
}

enum TodayDashboardDigestBuilder {
    static func make(
        summaries: [ReportDaySummary],
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> TodayDashboardDigest {
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
            ?? calendar.startOfDay(for: referenceDate)
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: currentWeekStart)
            ?? currentWeekStart
        let comparisonWeekStart = calendar.date(byAdding: .day, value: -7, to: previousWeekStart)
            ?? previousWeekStart
        let previousWeekInterval = DateInterval(start: previousWeekStart, end: currentWeekStart)
        let comparisonWeekInterval = DateInterval(start: comparisonWeekStart, end: previousWeekStart)
        let previousWeek = summaries.filter {
            $0.date >= previousWeekInterval.start && $0.date < previousWeekInterval.end
        }
        let comparisonWeek = summaries.filter {
            $0.date >= comparisonWeekInterval.start && $0.date < comparisonWeekInterval.end
        }
        let review = WeeklyHealthReviewEngine.make(
            current: previousWeek,
            previous: comparisonWeek,
            expectedDays: 7,
            scope: String(localized: "上周")
        )

        return TodayDashboardDigest(
            patterns: makePatterns(
                summaries: summaries,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            previousWeekReview: review,
            previousWeekRangeText: rangeText(
                start: previousWeekStart,
                end: calendar.date(byAdding: .day, value: -1, to: currentWeekStart) ?? currentWeekStart,
                calendar: calendar
            )
        )
    }

    private static func makePatterns(
        summaries: [ReportDaySummary],
        referenceDate: Date,
        calendar: Calendar
    ) -> [TodayDashboardPattern] {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate))
            ?? referenceDate
        let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        let recent = summaries
            .filter { DateInterval(start: start, end: end).contains($0.date) && $0.hasData }
            .sorted { $0.date < $1.date }

        guard !recent.isEmpty else {
            return [TodayDashboardPattern(title: String(localized: "等待规律样本"), systemImage: "clock", tone: .muted)]
        }

        var patterns: [TodayDashboardPattern] = []
        if let attention = mostFrequent(
            recent.compactMap { $0.scoreBreakdown?.leadingNegative?.tone == .caution
                ? $0.scoreBreakdown?.leadingNegativeKind
                : nil
            }
        ) {
            patterns.append(attentionPattern(for: attention))
        }
        if let support = mostFrequent(
            recent.compactMap { $0.scoreBreakdown?.leadingPositive?.tone == .positive
                ? $0.scoreBreakdown?.leadingPositiveKind
                : nil
            }
        ) {
            patterns.append(supportPattern(for: support))
        }
        if let trend = scoreTrendPattern(from: recent) {
            patterns.append(trend)
        }

        if patterns.isEmpty {
            patterns.append(TodayDashboardPattern(
                title: String(localized: "近期规律较平稳"),
                systemImage: "equal.circle.fill",
                tone: .neutral
            ))
        }
        return Array(patterns.prefix(3))
    }

    private static func mostFrequent(_ kinds: [ReportMetricKind]) -> ReportMetricKind? {
        let counts = Dictionary(grouping: kinds, by: { $0 }).mapValues(\.count)
        return counts.keys.sorted { lhs, rhs in
            let left = counts[lhs, default: 0]
            let right = counts[rhs, default: 0]
            return left == right ? lhs.rawValue < rhs.rawValue : left > right
        }.first
    }

    private static func attentionPattern(for kind: ReportMetricKind) -> TodayDashboardPattern {
        switch kind {
        case .sleep:
            return TodayDashboardPattern(title: String(localized: "睡眠节律待稳"), systemImage: "moon.zzz.fill", tone: .attention)
        case .stress:
            return TodayDashboardPattern(title: String(localized: "压力波动偏多"), systemImage: "brain.head.profile", tone: .attention)
        case .hrv:
            return TodayDashboardPattern(title: String(localized: "恢复弹性偏弱"), systemImage: "waveform.path.ecg", tone: .attention)
        case .activity:
            return TodayDashboardPattern(title: String(localized: "活动量偏少"), systemImage: "figure.walk", tone: .attention)
        }
    }

    private static func supportPattern(for kind: ReportMetricKind) -> TodayDashboardPattern {
        switch kind {
        case .sleep:
            return TodayDashboardPattern(title: String(localized: "睡眠在托住恢复"), systemImage: "bed.double.fill", tone: .positive)
        case .stress:
            return TodayDashboardPattern(title: String(localized: "压力管理较稳"), systemImage: "leaf.fill", tone: .positive)
        case .hrv:
            return TodayDashboardPattern(title: String(localized: "恢复弹性较好"), systemImage: "waveform.path.ecg", tone: .positive)
        case .activity:
            return TodayDashboardPattern(title: String(localized: "活动保持较好"), systemImage: "figure.walk.motion", tone: .positive)
        }
    }

    private static func scoreTrendPattern(from summaries: [ReportDaySummary]) -> TodayDashboardPattern? {
        let scores = summaries.compactMap(\.score)
        guard scores.count >= 6 else { return nil }
        let window = min(7, scores.count / 2)
        let earlier = Array(scores.prefix(window))
        let later = Array(scores.suffix(window))
        let earlierAverage = Double(earlier.reduce(0, +)) / Double(earlier.count)
        let laterAverage = Double(later.reduce(0, +)) / Double(later.count)
        let delta = laterAverage - earlierAverage
        if delta >= 4 {
            return TodayDashboardPattern(title: String(localized: "近期状态回升"), systemImage: "arrow.up.right", tone: .positive)
        }
        if delta <= -4 {
            return TodayDashboardPattern(title: String(localized: "近期状态走弱"), systemImage: "arrow.down.right", tone: .attention)
        }
        return TodayDashboardPattern(title: String(localized: "近期状态平稳"), systemImage: "equal", tone: .neutral)
    }

    private static func rangeText(start: Date, end: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }
}
