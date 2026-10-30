/// WorkoutRecordDetailPresentation 作为趋势模块的支撑类型，负责定义健身记录展示模型。
/// 负责描述日柱、日历、会话详情等组合图表的数据结构。

import SwiftUI
import Charts

/// 健身Record详情展示结构体 作为趋势模块里的辅助类型。
/// 负责强化健身记录模块的组合图表与阅读方式。
struct WorkoutRecordDetailPresentation: Sendable, Hashable {
    struct DailyBar: Identifiable, Sendable, Hashable {
        let date: Date
        let energyKilocalories: Int?
        let totalMinutes: Int
        let workoutCount: Int
        let dominantWorkoutTitle: String?

        var id: TimeInterval { date.timeIntervalSince1970 }
        var hasWorkout: Bool { workoutCount > 0 }
    }

    struct CalendarDay: Identifiable, Sendable, Hashable {
        let date: Date
        let weekdayLabel: String
        let dayNumber: String
        let hasWorkout: Bool

        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    struct SecondaryMetric: Identifiable, Sendable, Hashable {
        let id = UUID()
        let title: String
        let unit: String
        let accentHex: String
        let status: TrendCategoryStatus
        let summary: String
        let emptyMessage: String
        let points: [TimeSeriesPointDouble]
    }

    let displayStartDate: Date
    let displayEndDate: Date
    let totalEnergyKilocalories: Int?
    let totalMinutes: Int
    let totalWorkoutCount: Int
    let activeWorkoutDays: Int
    let inactiveDays: Int
    let latestWorkoutDate: Date?
    let latestWorkoutTitle: String?
    let dailyBars: [DailyBar]
    let calendarDays: [CalendarDay]
    let secondaryMetrics: [SecondaryMetric]
    let sessions: [WorkoutSessionSummary]
    let recentWorkoutContext: WorkoutSessionSummary?
}


struct WorkoutRecordDetailContent: View {
    let presentation: WorkoutRecordDetailPresentation
    let requestedRange: TrendsRange
    var isStaticForExport: Bool = false
    var isLoading: Bool = false

    @State private var selectedSessionDate: Date?
    @State private var selectedDayDate: Date?

    private let highlightColor = Color(hex: "D85B73")
    private let accentColor = Color(hex: "7CD992")
    private let mutedCapsule = Color(hex: "D7DDD8")

    private var dateRangeTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return "\(formatter.string(from: presentation.displayStartDate)) - \(formatter.string(from: presentation.displayEndDate))"
    }

    private var totalEnergyText: String {
        presentation.totalEnergyKilocalories.map {
            metricValueText(for: Double($0), unit: "kcal")
        } ?? "--"
    }

    private var usesEnergyChart: Bool {
        guard presentation.totalEnergyKilocalories != nil else { return false }
        let workoutDays = presentation.dailyBars.filter(\.hasWorkout)
        return !workoutDays.isEmpty && workoutDays.allSatisfy { $0.energyKilocalories != nil }
    }

    private var primaryChartTitle: String {
        usesEnergyChart ? "运动消耗" : "训练总时长"
    }

    private var primaryChartUnit: String {
        usesEnergyChart ? "kcal" : "分钟"
    }

    private var primaryChartTotalText: String {
        if usesEnergyChart {
            return totalEnergyText
        }
        return metricValueText(for: Double(presentation.totalMinutes), unit: "分钟")
    }

    private func primaryChartValue(for bar: WorkoutRecordDetailPresentation.DailyBar) -> Double {
        guard usesEnergyChart else { return Double(bar.totalMinutes) }
        guard bar.hasWorkout else { return 0 }
        guard let energyKilocalories = bar.energyKilocalories else {
            return Double(bar.totalMinutes)
        }
        return Double(energyKilocalories)
    }

    private var averageChartValue: Double {
        guard !presentation.dailyBars.isEmpty else { return 0 }
        return presentation.dailyBars.reduce(0) { $0 + primaryChartValue(for: $1) }
            / Double(presentation.dailyBars.count)
    }

    private var yDomain: ClosedRange<Double> {
        let values = presentation.dailyBars.map { primaryChartValue(for: $0) }
        return chartDomain(for: values.isEmpty ? [0, 100] : values)
    }

    private var yAxisValues: [Double] {
        chartAxisValues(for: yDomain)
    }

    var body: some View {
        Group {
            if isLoading {
                workoutLoadingState
            } else {
                VStack(spacing: 18) {
                    if requestedRange == .day {
                        dayWorkoutChartCard

                        if !presentation.sessions.isEmpty {
                            daySessionTimelineCard
                        } else if let recentWorkout = presentation.recentWorkoutContext {
                            recentWorkoutContextCard(recentWorkout)
                        }
                    } else {
                        heroChartCard
                        workoutCalendarCard
                        workoutStatsCard

                        if !presentation.secondaryMetrics.isEmpty {
                            secondaryMetricSection
                        }
                    }
                }
            }
        }
    }

    private var workoutLoadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(highlightColor)
            Text("正在同步训练记录…")
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .accessibilityElement(children: .combine)
    }

    private var dayWorkoutChartCard: some View {
        BBChartCard(
            title: "今日训练节奏",
            subtitle: dayChartSubtitle,
            isEmpty: presentation.sessions.isEmpty,
            emptyTitle: "今天还没有训练记录",
            emptySystemImage: "figure.cooldown",
            systemImage: "figure.run.circle.fill",
            tint: accentColor
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    BBChartMetricPill(
                        title: "训练次数",
                        value: "\(presentation.sessions.count) 次",
                        tint: highlightColor
                    )
                    BBChartMetricPill(
                        title: "训练时长",
                        value: "\(presentation.totalMinutes) 分钟",
                        tint: accentColor
                    )
                    BBChartMetricPill(
                        title: "运动消耗",
                        value: totalEnergyText,
                        tint: Color(hex: "E38B48")
                    )
                }

                interactiveDaySessionChart

                if let session = activeSession {
                    BBChartSelectionReadout(
                        title: session.activityTitle,
                        value: metricValueText(for: session.durationMinutes, unit: "分钟"),
                        detail: "\(sessionTimeRange(session)) · \(sessionMeasurementText(session))",
                        tint: workoutTint(for: session.activityTitle),
                        systemImage: workoutSymbol(for: session.activityTitle)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var interactiveDaySessionChart: some View {
        if isStaticForExport {
            daySessionChart
        } else {
            daySessionChart
                .chartXSelection(value: $selectedSessionDate)
        }
    }

    private var daySessionChart: some View {
        Chart {
            ForEach(presentation.sessions) { session in
                BarMark(
                    x: .value("开始时间", session.startDate, unit: .minute),
                    y: .value("训练时长", session.durationMinutes),
                    width: .fixed(18)
                )
                .foregroundStyle(workoutTint(for: session.activityTitle).gradient)
                .cornerRadius(5)
            }

            if averageSessionMinutes > 0 {
                RuleMark(y: .value("单次平均", averageSessionMinutes))
                    .foregroundStyle(BBChartStyle.baseline.opacity(0.68))
                    .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
            }

            if let selectedSessionDate {
                RuleMark(x: .value("选中时间", selectedSessionDate))
                    .foregroundStyle(BBChartStyle.selection.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: dayDateDomain)
        .chartYScale(domain: 0...dayChartUpperBound)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine().foregroundStyle(BBChartStyle.grid.opacity(0.58))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                    }
                }
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(BBChartStyle.grid.opacity(0.62))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text("\(Int(minutes.rounded()))")
                    }
                }
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(BBChartStyle.plotGradient(tint: accentColor))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(height: 210)
        .accessibilityLabel("今日逐次训练时长")
    }

    private var daySessionTimelineCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            BBChartHeader(
                title: "今日训练时间线",
                subtitle: "按每次训练的实际开始与结束时间排列",
                systemImage: "clock.fill",
                tint: highlightColor
            )

            ForEach(presentation.sessions) { session in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: workoutSymbol(for: session.activityTitle))
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundStyle(workoutTint(for: session.activityTitle))
                        .frame(width: 38, height: 38)
                        .background(
                            workoutTint(for: session.activityTitle).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.activityTitle)
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(sessionTimeRange(session))
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(sessionMeasurementText(session))
                            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)

                        ForEach(session.zoneSummaries) { zoneSummary in
                            workoutZoneStrip(zoneSummary)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(metricValueText(for: session.durationMinutes, unit: "分钟"))
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(workoutTint(for: session.activityTitle))
                        .monospacedDigit()
                }

                if session.id != presentation.sessions.last?.id {
                    Divider().overlay(BBChartStyle.grid.opacity(0.72))
                }
            }
        }
        .padding(16)
        .bbChartSurface(tint: highlightColor, cornerRadius: 26)
    }

    private func recentWorkoutContextCard(_ session: WorkoutSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            BBChartHeader(
                title: "近期训练参考",
                subtitle: "以下记录不计入今天的统计和图表",
                systemImage: "clock.arrow.circlepath",
                tint: Color(hex: "6E7B86")
            )

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: workoutSymbol(for: session.activityTitle))
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundStyle(workoutTint(for: session.activityTitle))
                    .frame(width: 42, height: 42)
                    .background(
                        workoutTint(for: session.activityTitle).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.activityTitle)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(workoutDateText(session.startDate)) · \(sessionTimeRange(session))")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("\(metricValueText(for: session.durationMinutes, unit: "分钟")) · \(sessionMeasurementText(session))")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .bbChartPlotSurface(tint: Color(hex: "6E7B86"), cornerRadius: 16)
        }
        .padding(16)
        .bbChartSurface(tint: Color(hex: "6E7B86"), cornerRadius: 26)
    }

    private var heroChartCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(dateRangeTitle)
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "B14C63"))

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(primaryChartTotalText)
                            .font(.appSystem(size: 42, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(primaryChartTitle)
                            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Text(heroHeadline)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "B14C63"))

                    Text(displayRangeTag)
                        .font(.appSystem(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "B14C63"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: "F9E7EB"), in: Capsule())
                }
            }

            HStack(spacing: 18) {
                legendPill(label: "窗口日均", color: highlightColor)
            }

            Chart {
                ForEach(presentation.dailyBars) { bar in
                    BarMark(
                        x: .value("日期", bar.date),
                        y: .value(primaryChartTitle, primaryChartValue(for: bar))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                highlightColor.opacity(bar.hasWorkout ? 0.92 : 0.25),
                                highlightColor.opacity(bar.hasWorkout ? 0.72 : 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if averageChartValue > 0 {
                    RuleMark(y: .value("窗口日均", averageChartValue))
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                        .foregroundStyle(highlightColor.opacity(0.65))
                }

                if let selectedDayDate {
                    RuleMark(x: .value("选中日期", selectedDayDate))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(BBChartStyle.selection.opacity(0.28))
                }
            }
            .chartXAxis {
                AxisMarks(values: periodAxisDates) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date))
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: yAxisValues) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.18))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number.rounded()))")
                        }
                    }
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .chartXScale(domain: periodDateDomain)
            .chartYScale(domain: yDomain)
            .chartPlotStyle { plotArea in
                plotArea
                    .background(BBChartStyle.plotGradient(tint: highlightColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .chartXSelection(value: $selectedDayDate)
            .frame(height: 260)

            if let day = activeDailyBar {
                BBChartSelectionReadout(
                    title: workoutDateText(day.date),
                    value: metricValueText(for: primaryChartValue(for: day), unit: primaryChartUnit),
                    detail: "\(day.workoutCount) 次 · \(day.totalMinutes) 分钟 · \(day.dominantWorkoutTitle ?? "无训练")",
                    tint: day.hasWorkout ? highlightColor : Color(hex: "7B8794"),
                    systemImage: day.hasWorkout ? "figure.run" : "figure.cooldown"
                )
            }

            HStack(spacing: 8) {
                BBChartMetricPill(
                    title: "训练次数",
                    value: "\(presentation.totalWorkoutCount) 次",
                    tint: highlightColor
                )
                BBChartMetricPill(
                    title: "训练总时长",
                    value: metricValueText(for: Double(presentation.totalMinutes), unit: "分钟"),
                    tint: accentColor
                )
                BBChartMetricPill(
                    title: "窗口日均",
                    value: metricValueText(for: averageChartValue, unit: primaryChartUnit),
                    tint: Color(hex: "E38B48")
                )
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 8)
    }

    private var workoutCalendarCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            BBChartHeader(
                title: "运动日历",
                subtitle: "按天查看当前窗口内的训练分布",
                systemImage: "calendar",
                tint: accentColor
            )

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7),
                spacing: 14
            ) {
                ForEach(presentation.calendarDays) { day in
                    workoutDayCell(day)
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 12, x: 0, y: 6)
    }

    private var workoutStatsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                statsPanel(
                    title: "无运动",
                    value: "\(presentation.inactiveDays)天",
                    tint: mutedCapsule,
                    textColor: Theme.Colors.textSecondary
                )
                statsPanel(
                    title: "有运动",
                    value: "\(presentation.activeWorkoutDays)天",
                    tint: Color(hex: "F7D7DE"),
                    textColor: highlightColor
                )
            }

            if let latestWorkoutDate = presentation.latestWorkoutDate {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(highlightColor.opacity(0.92))
                        .frame(width: 10, height: 10)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近一次记录")
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text("\(workoutDateText(latestWorkoutDate)) · \(presentation.latestWorkoutTitle ?? "综合运动")")
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        )
    }

    private var secondaryMetricSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("次级趋势")
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: 14) {
                ForEach(presentation.secondaryMetrics) { metric in
                    WorkoutSecondaryMetricCard(
                        metric: metric,
                        range: requestedRange
                    )
                }
            }
        }
    }

    private func workoutDayCell(_ day: WorkoutRecordDetailPresentation.CalendarDay) -> some View {
        VStack(spacing: 8) {
            Text(day.weekdayLabel)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(day.hasWorkout ? Color(hex: "D6DED7") : Color(hex: "E7ECE8"))
                .frame(height: 72)
                .overlay {
                    Image(systemName: day.hasWorkout ? "figure.run" : "figure.cooldown")
                        .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(day.hasWorkout ? Color.white.opacity(0.92) : Color.white.opacity(0.78))
                }

            Text(day.dayNumber)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private func statsPanel(title: String, value: String, tint: Color, textColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 34, weight: .black, design: .rounded))
                .foregroundColor(textColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(tint, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func legendPill(label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 18, height: 8)
            Text(label)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    private var dayChartSubtitle: String {
        guard let first = presentation.sessions.first, let last = presentation.sessions.last else {
            return String(localized: "今日数据保持独立，近期训练不会计入今天")
        }
        return String(localized: "\(presentation.sessions.count) 次训练 · \(timeText(first.startDate)) 至 \(timeText(last.endDate))")
    }

    private var dayDateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: presentation.displayStartDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? presentation.displayEndDate
        return start...max(end, start.addingTimeInterval(1))
    }

    private var averageSessionMinutes: Double {
        guard !presentation.sessions.isEmpty else { return 0 }
        return presentation.sessions.reduce(0) { $0 + $1.durationMinutes } / Double(presentation.sessions.count)
    }

    private var dayChartUpperBound: Double {
        let peak = presentation.sessions.map(\.durationMinutes).max() ?? 0
        return max(15, ceil(peak * 1.2 / 5) * 5)
    }

    private var activeSession: WorkoutSessionSummary? {
        guard let selectedSessionDate else { return presentation.sessions.last }
        return presentation.sessions.min {
            abs($0.startDate.timeIntervalSince(selectedSessionDate))
                < abs($1.startDate.timeIntervalSince(selectedSessionDate))
        }
    }

    private var activeDailyBar: WorkoutRecordDetailPresentation.DailyBar? {
        guard let selectedDayDate else {
            return presentation.dailyBars.last(where: \.hasWorkout) ?? presentation.dailyBars.last
        }
        return presentation.dailyBars.min {
            abs($0.date.timeIntervalSince(selectedDayDate))
                < abs($1.date.timeIntervalSince(selectedDayDate))
        }
    }

    private var periodDateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: presentation.displayStartDate)
        let endDay = calendar.startOfDay(for: presentation.displayEndDate)
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? presentation.displayEndDate
        return start...max(end, start.addingTimeInterval(1))
    }

    private var periodAxisDates: [Date] {
        TrendsSelectionFormatter.axisDates(for: requestedRange, dateDomain: periodDateDomain)
    }

    private func sessionTimeRange(_ session: WorkoutSessionSummary) -> String {
        "\(timeText(session.startDate))-\(timeText(session.endDate))"
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func sessionMeasurementText(_ session: WorkoutSessionSummary) -> String {
        var values: [String] = []
        if let energy = session.activeEnergyKilocalories, energy.isFinite, energy >= 0 {
            values.append(metricValueText(for: energy, unit: "kcal"))
        }
        if let distance = session.distanceKilometers, distance.isFinite, distance >= 0 {
            values.append(metricValueText(for: distance, unit: "km"))
        }
        return values.isEmpty ? "未记录能量或距离" : values.joined(separator: " · ")
    }

    private func workoutZoneStrip(_ summary: WorkoutZoneSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: summary.metric == .heartRate ? "heart.fill" : "bolt.fill")
                    .foregroundStyle(summary.metric == .heartRate ? Color(hex: "D85B73") : Color(hex: "357ABD"))
                Text(summary.metric == .heartRate ? "心率区间" : "骑行功率区间")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 4)
                if let dominant = summary.dominantZone {
                    Text("主要 Zone \(dominant.index)")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            GeometryReader { proxy in
                let spacing = CGFloat(max(0, summary.zones.count - 1)) * 2
                let availableWidth = max(0, proxy.size.width - spacing)
                HStack(spacing: 2) {
                    ForEach(summary.zones) { zone in
                        let fraction = summary.totalDuration > 0 ? zone.duration / summary.totalDuration : 0
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(workoutZoneColor(index: zone.index))
                            .frame(width: max(3, availableWidth * fraction))
                            .accessibilityLabel("Zone \(zone.index)，\(Int(zone.duration / 60)) 分钟")
                    }
                }
            }
            .frame(height: 7)

            Text(workoutZoneDetailText(summary))
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(workoutZoneSourceText(summary.source))
                .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.82))
        }
        .padding(.top, 3)
    }

    private func workoutZoneDetailText(_ summary: WorkoutZoneSummary) -> String {
        summary.zones
            .filter { $0.duration > 0 }
            .map { zone in
                let seconds = Int(zone.duration.rounded())
                let durationText = seconds >= 60 ? "\(seconds / 60) 分" : "\(seconds) 秒"
                return "Z\(zone.index) \(durationText) · \(workoutZoneBoundaryText(zone, metric: summary.metric))"
            }
            .joined(separator: "　")
    }

    private func workoutZoneBoundaryText(_ zone: WorkoutZone, metric: WorkoutZoneMetric) -> String {
        let unit = metric == .heartRate ? "bpm" : "W"
        switch (zone.minimumValue, zone.maximumValue) {
        case let (minimum?, maximum?): return "\(Int(minimum.rounded()))–\(Int(maximum.rounded())) \(unit)"
        case let (minimum?, nil): return "≥\(Int(minimum.rounded())) \(unit)"
        case let (nil, maximum?): return "<\(Int(maximum.rounded())) \(unit)"
        case (nil, nil): return "范围由 HealthKit 管理"
        }
    }

    private func workoutZoneSourceText(_ source: WorkoutZoneConfigurationSource) -> String {
        switch source {
        case .system: return "区间来源：HealthKit 自动计算"
        case .user: return "区间来源：用户在健康 App 中设置"
        case .app: return "区间来源：训练 App 自定义"
        }
    }

    private func workoutZoneColor(index: Int) -> Color {
        switch index {
        case ...1: return Color(hex: "71B7E6")
        case 2: return Color(hex: "58B88B")
        case 3: return Color(hex: "E6B84D")
        case 4: return Color(hex: "E88749")
        default: return Color(hex: "D85B73")
        }
    }

    private func workoutTint(for title: String) -> Color {
        if title.contains("跑") || title.contains("间歇") { return Color(hex: "D85B73") }
        if title.contains("步行") || title.contains("徒步") { return Color(hex: "287A58") }
        if title.contains("骑行") || title.contains("划船") { return Color(hex: "357ABD") }
        if title.contains("力量") || title.contains("核心") { return Color(hex: "8A62C7") }
        if title.contains("瑜伽") || title.contains("舞蹈") { return Color(hex: "D17A36") }
        if title.contains("游泳") { return Color(hex: "148FA8") }
        return Color(hex: "5F7468")
    }

    private func workoutSymbol(for title: String) -> String {
        if title.contains("跑") || title.contains("间歇") { return "figure.run" }
        if title.contains("步行") || title.contains("徒步") { return "figure.walk" }
        if title.contains("骑行") { return "figure.outdoor.cycle" }
        if title.contains("游泳") { return "figure.pool.swim" }
        if title.contains("瑜伽") { return "figure.yoga" }
        if title.contains("划船") { return "figure.rower" }
        if title.contains("力量") || title.contains("核心") { return "dumbbell.fill" }
        return "figure.mixed.cardio"
    }

    private var heroHeadline: String {
        if let latestWorkoutDate = presentation.latestWorkoutDate {
            return String(localized: "最近一次训练在 \(workoutDateText(latestWorkoutDate))，\(presentation.latestWorkoutTitle ?? String(localized: "综合运动")) 作为主要训练类型被记录。")
        }
        return String(localized: "当前窗口内没有新的训练记录，继续在健康 App 中记录训练后，这里会自动形成可读趋势。")
    }

    private var displayRangeTag: String {
        requestedRange == .week ? String(localized: "最近7天") : String(localized: "最近30天")
    }

    private func workoutDateText(_ date: Date) -> String {
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func axisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func metricValueText(for value: Double, unit: String) -> String {
        let digits: Int
        switch unit {
        case "kcal", "分钟", "次":
            digits = 0
        default:
            digits = abs(value) >= 100 || value == value.rounded() ? 0 : 1
        }
        let valueText = String(format: "%.\(digits)f", value)
        return unit.isEmpty ? valueText : "\(valueText)\(unit)"
    }

    private func chartDomain(for values: [Double]) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...100
        }
        if abs(maxValue - minValue) < 0.1 {
            let padding = max(20, abs(maxValue) * 0.18)
            return max(0, minValue - padding)...(maxValue + padding)
        }
        let span = maxValue - minValue
        let padding = max(18, span * 0.24)
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private func chartAxisValues(for domain: ClosedRange<Double>) -> [Double] {
        let lower = domain.lowerBound
        let upper = domain.upperBound
        let span = max(upper - lower, 1)
        let step = max(10, ceil((span / 3) / 10) * 10)
        let start = floor(lower / step) * step
        let end = ceil(upper / step) * step
        var values: [Double] = []
        var current = start
        while current <= end + 0.1 {
            values.append(current)
            current += step
        }
        return values
    }
}

private struct WorkoutSecondaryMetricCard: View {
    let metric: WorkoutRecordDetailPresentation.SecondaryMetric
    let range: TrendsRange

    private var accentColor: Color {
        Color(hex: metric.accentHex)
    }

    private var currentPoint: TimeSeriesPointDouble? {
        metric.points.last
    }

    private var averageValue: Double {
        guard !metric.points.isEmpty else { return 0 }
        return metric.points.map(\.value).reduce(0, +) / Double(metric.points.count)
    }

    private var usesDiscreteCountStyle: Bool {
        metric.unit == "次"
    }

    private var yDomain: ClosedRange<Double> {
        let domain = TrendYAxisDesigner.domain(for: metric.points.map(\.value), range: range)
        if usesDiscreteCountStyle || metric.unit == "分钟" {
            return 0...max(domain.upperBound, 1)
        }
        return domain
    }

    private var yAxisValues: [Double] {
        let values = TrendYAxisDesigner.axisValues(for: yDomain, range: range)
        if usesDiscreteCountStyle {
            let filtered = values.map { max(0, round($0)) }.removingConsecutiveDuplicates()
            if filtered.first != 0 {
                return [0] + filtered
            }
            return filtered
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.title)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(metric.summary)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Text(metric.status.title)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentColor.opacity(0.10), in: Capsule())
            }

            if metric.points.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(metric.emptyMessage)
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("当前还没有可展示的记录点，继续在健康 App 中记录训练后这里会自动补齐。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                .padding(16)
                .background(accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                HStack(spacing: 12) {
                    metricValueBlock(title: "当前", value: metricValueText(currentPoint?.value ?? 0, unit: metric.unit))
                    metricValueBlock(title: "均值", value: metricValueText(averageValue, unit: metric.unit))
                }

                metricChart
            }
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.82), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var metricChart: some View {
        if usesDiscreteCountStyle {
            discreteMetricChart
        } else {
            continuousMetricChart
        }
    }

    private var discreteMetricChart: some View {
        Chart {
            ForEach(metric.points) { point in
                PointMark(
                    x: .value("日期", point.date),
                    y: .value("值", point.value)
                )
                .symbol(.square)
                .symbolSize(90)
                .foregroundStyle(accentColor)
            }
        }
        .chartXAxis {
            metricXAxis
        }
        .chartYAxis {
            metricYAxis
        }
        .chartYScale(domain: yDomain)
        .frame(height: 180)
    }

    private var continuousMetricChart: some View {
        Chart {
            ForEach(metric.points) { point in
                RuleMark(
                    x: .value("日期", point.date),
                    yStart: .value("起点", 0),
                    yEnd: .value("值", point.value)
                )
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .foregroundStyle(accentColor.opacity(0.36))

                PointMark(
                    x: .value("日期", point.date),
                    y: .value("值", point.value)
                )
                .symbolSize(80)
                .foregroundStyle(accentColor)
            }
        }
        .chartXAxis {
            metricXAxis
        }
        .chartYAxis {
            metricYAxis
        }
        .chartYScale(domain: yDomain)
        .frame(height: 180)
    }

    private var metricXAxis: some AxisContent {
        AxisMarks(values: axisDates) { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(axisLabel(for: date))
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private var metricYAxis: some AxisContent {
        AxisMarks(position: .leading, values: yAxisValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.18))
            AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.28))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(axisValueText(number))
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func metricValueBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metricValueText(_ value: Double, unit: String) -> String {
        let digits: Int
        switch unit {
        case "分钟", "次":
            digits = 0
        default:
            digits = abs(value) >= 100 || value == value.rounded() ? 0 : 1
        }
        let valueText = String(format: "%.\(digits)f", value)
        return unit.isEmpty ? valueText : "\(valueText)\(unit)"
    }

    private var axisDates: [Date] {
        let domain = metric.points.compactMap(\.date)
        guard let first = domain.min(), let last = domain.max() else { return metric.points.map(\.date) }
        return TrendsSelectionFormatter.axisDates(for: range, dateDomain: first...last)
    }

    private func axisValueText(_ value: Double) -> String {
        let text = metricValueText(value, unit: metric.unit)
        if metric.unit.isEmpty {
            return text
        }
        if text.hasSuffix(metric.unit) {
            return String(text.dropLast(metric.unit.count))
        }
        return text
    }

    private func axisLabel(for date: Date) -> String {
        TrendsSelectionFormatter.axisLabel(for: date, range: range)
    }
}

private extension Array where Element == Double {
    func removingConsecutiveDuplicates() -> [Double] {
        var result: [Double] = []
        for value in self where result.last != value {
            result.append(value)
        }
        return result
    }
}
