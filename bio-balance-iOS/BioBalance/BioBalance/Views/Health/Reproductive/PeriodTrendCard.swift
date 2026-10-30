/// PeriodTrendCard 由健康首页周期入口调用，作为「周期趋势」内容卡片。
/// 负责展示生理周期月度趋势图与教育问答入口。

import SwiftUI
import Charts

/// 周期趋势卡片组件 作为健康模块里的内容展示卡片。
/// 负责解释具体指标含义，并展示对应的趋势、影响因素或分析结果。
struct PeriodTrendCard: View {
    @Bindable var viewModel: PeriodViewModel
    @State private var selectedDate: Date?
    @State private var selectedEducationQuestion: PeriodEducationQuestion?
    @State private var showEducationList = false

    var body: some View {
        PeriodTrendChartCard(
            summary: viewModel.summary,
            range: .month,
            selectedDate: $selectedDate,
            onSelectEducationQuestion: { question in
                selectedEducationQuestion = PeriodEducationQuestion(question: question)
            },
            onSelectEducationList: {
                showEducationList = true
            },
            visualStyle: .airy
        )
        .sheet(item: $selectedEducationQuestion) { item in
            NavigationStack {
                FAQDetailView(question: item.question)
            }
        }
        .sheet(isPresented: $showEducationList) {
            NavigationStack {
                FAQListView()
            }
        }
    }
}

/// 周期趋势卡片组件 作为健康模块里的内容展示卡片。
/// 负责健康指标详情展示。
struct PeriodTrendChartCard: View {
    enum VisualStyle {
        case standard
        case airy
    }

    let summary: PeriodSummary?
    let range: TrendsRange
    @Binding var selectedDate: Date?
    var onSelectEducationQuestion: ((String) -> Void)? = nil
    var onSelectEducationList: (() -> Void)? = nil
    var isStaticForExport: Bool = false
    var visualStyle: VisualStyle = .standard

    private let periodTint = Color(hex: "B86A63")
    private let predictedPeriodTint = Color(hex: "D8B9B3")
    private let fertileTint = Color(hex: "7A8FAE")
    private let ovulationTint = Color(hex: "4C7DFF")
    private let painTint = Color(hex: "24364D")
    private let moodTint = Color(hex: "8C6C7E")
    private let paperTint = Theme.Colors.secondarySurface
    private let borderTint = Theme.Colors.surfaceBorder
    private let inkTint = Theme.Colors.textPrimary
    private let mutedInkTint = Theme.Colors.textSecondary
    private let airyBorderTint = Theme.Colors.surfaceBorder

    private var isAiryStyle: Bool {
        visualStyle == .airy
    }

    private var cardBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: isAiryStyle ? [Theme.Colors.surface, Theme.Colors.surface] : [Theme.Colors.surface, paperTint],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorderColor: Color {
        isAiryStyle ? airyBorderTint : borderTint.opacity(0.72)
    }

    private var summaryItemBorderColor: Color {
        isAiryStyle ? airyBorderTint.opacity(0.92) : borderTint.opacity(0.45)
    }

    private var overlayRanges: [OverlayRangePoint] {
        (summary?.overlayRanges ?? []).compactMap { item in
            guard let startStr = item.startDate, let endStr = item.endDate else { return nil }
            guard let start = Self.dayFormatter.date(from: startStr), let end = Self.dayFormatter.date(from: endStr) else { return nil }
            return OverlayRangePoint(start: start, end: end, type: item.type ?? "UNKNOWN")
        }
        .sorted { $0.start < $1.start }
    }

    private var orderedLogs: [PeriodDayLog] {
        (summary?.dayLogs ?? []).sorted { ($0.date ?? "") < ($1.date ?? "") }
    }

    private var latestLog: PeriodDayLog? {
        orderedLogs.last
    }

    private var defaultSelectedDate: Date? {
        let calendar = Calendar.current
        if let selectedDate {
            let normalized = calendar.startOfDay(for: selectedDate)
            if isDateInsideChartDomain(normalized) {
                return normalized
            }
        }

        if range != .day {
            for log in orderedLogs.reversed() {
                guard let raw = log.date,
                      let date = Self.dayFormatter.date(from: raw),
                      isDateInsideChartDomain(date) else { continue }
                return date
            }
        }

        return calendar.startOfDay(for: Date())
    }

    private var normalizedSelectedDate: Date? {
        defaultSelectedDate.map { Calendar.current.startOfDay(for: $0) }
    }

    private var visibleLogs: [PeriodDayLog] {
        switch range {
        case .day:
            guard let anchor = normalizedSelectedDate else { return orderedLogs.suffix(1).map { $0 } }
            return orderedLogs.filter {
                guard let raw = $0.date, let date = Self.dayFormatter.date(from: raw) else { return false }
                return Calendar.current.isDate(date, inSameDayAs: anchor)
            }
        case .week:
            return logs(in: chartDomain)
        case .month:
            return logs(in: chartDomain)
        }
    }

    private var trackRows: [SymptomTrackRow] {
        SymptomMetricKey.allCases.map { key in
            SymptomTrackRow(
                key: key,
                events: visibleLogs.compactMap { log in
                    guard let rawDate = log.date,
                          let date = Self.dayFormatter.date(from: rawDate),
                          let value = key.value(from: log) else { return nil }
                    return SymptomEvent(date: date, value: value)
                }
            )
        }
    }

    private var chartDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        switch range {
        case .day:
            return today...end
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return start...end
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return start...end
        }
    }

    private func isDateInsideChartDomain(_ date: Date) -> Bool {
        date >= chartDomain.lowerBound && date < chartDomain.upperBound
    }

    private var visibleOverlayRanges: [OverlayRangePoint] {
        overlayRanges.filter { $0.end >= chartDomain.lowerBound && $0.start < chartDomain.upperBound }
    }

    private var visiblePhaseRanges: [OverlayRangePoint] {
        visibleOverlayRanges.filter { $0.type != "OVULATION" }
    }

    private var visibleOvulationRanges: [OverlayRangePoint] {
        visibleOverlayRanges.filter { $0.type == "OVULATION" }
    }

    private var selectedDateMarkers: [Date] {
        normalizedSelectedDate.map { [$0] } ?? []
    }

    private var summaryItems: [SummaryItem] {
        switch range {
        case .day:
            return [
                SummaryItem(
                    title: "当前阶段",
                    value: currentPhaseTitle,
                    detail: cycleDayText
                ),
                SummaryItem(
                    title: "下一关键时间",
                    value: formattedDate(summary?.predictions?.nextPeriodStart) ?? "--",
                    detail: predictionSourceText
                ),
                SummaryItem(
                    title: "当天状态",
                    value: dayStatusText,
                    detail: dayStatusDetail
                )
            ]
        case .week:
            return [
                SummaryItem(
                    title: "最近阶段",
                    value: currentPhaseTitle,
                    detail: cycleDayText
                ),
                SummaryItem(
                    title: "下一关键时间",
                    value: formattedDate(summary?.predictions?.nextPeriodStart) ?? "--",
                    detail: predictionSourceText
                ),
                SummaryItem(
                    title: "最近记录",
                    value: latestLogSummaryText,
                    detail: latestLogDetailText
                )
            ]
        case .month:
            return [
                SummaryItem(
                    title: "周期长度",
                    value: summary?.predictions?.cycleLength.map { "\($0)天" } ?? "--",
                    detail: currentPhaseTitle
                ),
                SummaryItem(
                    title: "下一关键时间",
                    value: formattedDate(summary?.predictions?.nextPeriodStart) ?? "--",
                    detail: predictionSourceText
                ),
                SummaryItem(
                    title: "最近周期",
                    value: latestCycleRangeText,
                    detail: latestLogDetailText
                )
            ]
        }
    }

    private var currentPhaseTitle: String {
        phaseText(summary?.current?.phase)
    }

    private var cycleDayText: String {
        summary?.current?.dayIndex.map { "周期第\($0)天" } ?? "等待同步"
    }

    private var dayStatusText: String {
        guard let log = selectedLog else { return "暂无记录" }
        return String(localized: "出血 \(metricValueText(log.flowLevel)) / 痛经 \(metricValueText(log.painLevel)) / 情绪 \(metricValueText(log.moodLevel))")
    }

    private var dayStatusDetail: String {
        selectedSummaryText ?? "当天还没有症状记录"
    }

    private var latestLogSummaryText: String {
        guard let log = latestLog else { return "--" }
        return String(localized: "出血 \(metricValueText(log.flowLevel))")
    }

    private var latestLogDetailText: String {
        guard let log = latestLog else { return "未记录" }
        return String(localized: "痛经 \(metricValueText(log.painLevel)) · 情绪 \(metricValueText(log.moodLevel))")
    }

    private var latestCycleRangeText: String {
        guard let range = latestPeriodRange else { return "等待更多记录" }
        return "\(Self.shortLabelFormatter.string(from: range.start)) - \(Self.shortLabelFormatter.string(from: range.end))"
    }

    private var latestPeriodRange: OverlayRangePoint? {
        visibleOverlayRanges.last(where: { $0.type == "PERIOD" || $0.type == "PREDICTED_PERIOD" })
    }

    private var selectedLog: PeriodDayLog? {
        guard let selectedDate = normalizedSelectedDate else { return nil }
        let key = Self.dayFormatter.string(from: selectedDate)
        return orderedLogs.last(where: { $0.date == key })
    }

    private var selectedSummaryText: String? {
        guard let selectedDate = normalizedSelectedDate else { return nil }
        let label = Self.shortLabelFormatter.string(from: selectedDate)
        guard let log = selectedLog else {
            return String(localized: "\(label) · 暂无症状记录")
        }
        return String(localized: "\(label) · 出血 \(metricScoreText(log.flowLevel)) · 痛经 \(metricScoreText(log.painLevel)) · 情绪 \(metricScoreText(log.moodLevel))")
    }

    private var selectedPhaseText: String {
        guard let selectedDate = normalizedSelectedDate else { return "周期观察" }
        if let range = visibleOverlayRanges.first(where: { selectedDate >= $0.start && selectedDate <= $0.end }) {
            switch range.type {
            case "PERIOD":
                return String(localized: "经期记录")
            case "PREDICTED_PERIOD":
                return String(localized: "预测经期")
            case "FERTILE_WINDOW":
                return String(localized: "易孕窗口")
            case "OVULATION":
                return String(localized: "排卵提示")
            default:
                return String(localized: "周期观察")
            }
        }
        return currentPhaseTitle
    }

    private var predictionSourceText: String {
        guard let source = summary?.predictions?.source else { return "健康 App 预测" }
        switch source.uppercased() {
        case "HEALTHKIT", PeriodStore.healthPredictionSource:
            return String(localized: "健康 App 预测")
        case "LOCAL", PeriodStore.localPredictionSource:
            return String(localized: "本地估算")
        default:
            return String(localized: "周期预测")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            summaryBar
            phaseContextBar

            Group {
                switch range {
                case .day:
                    daySnapshotCard
                case .week:
                    layeredTrendCard(isMonthView: false)
                case .month:
                    layeredTrendCard(isMonthView: true)
                }
            }

            PeriodEducationSection(
                onSelectQuestion: { question in
                    onSelectEducationQuestion?(question)
                },
                onSelectMore: {
                    onSelectEducationList?()
                }
            )
        }
        .padding(16)
        .background(
            cardBackgroundGradient,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .padding(.top, 2)
        .onAppear {
            selectedDate = defaultSelectedDate
        }
        .onChange(of: range.rawValue) { _, _ in
            selectedDate = defaultSelectedDate
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("周期趋势")
                .font(Theme.Typography.headline)
                .foregroundColor(inkTint)

            Spacer()

            Text(currentPhaseTitle)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(periodTint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(periodTint.opacity(isAiryStyle ? 0.06 : 0.10), in: Capsule())
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 10) {
            ForEach(summaryItems) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(item.value)
                        .font(.appSystem(size: 15, weight: .bold, design: .serif))
                        .foregroundColor(inkTint)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(item.detail)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(mutedInkTint)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Theme.Colors.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(summaryItemBorderColor, lineWidth: 1)
                )
            }
        }
    }

    private var phaseContextBar: some View {
        HStack(spacing: 8) {
            Text(selectedPhaseText)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(periodTint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(periodTint.opacity(isAiryStyle ? 0.06 : 0.10), in: Capsule())

            Text(contextHintText)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(mutedInkTint)
                .lineLimit(2)
        }
    }

    private var contextHintText: String {
        switch range {
        case .day:
            return selectedSummaryText ?? "先看当天状态，再结合当前阶段读这一天。"
        case .week:
            return selectedSummaryText ?? "先看最近 7 天的阶段过渡，再查看症状在哪些日期出现。"
        case .month:
            return selectedSummaryText ?? "先看整个月的窗口分布，再回头读症状集中出现在哪几段。"
        }
    }

    private var daySnapshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("当天判断")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(normalizedSelectedDate.map(Self.longLabelFormatter.string(from:)) ?? "今日")
                        .font(.appSystem(size: 22, weight: .black, design: .serif))
                        .foregroundColor(inkTint)
                    Text(selectedPhaseText)
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(mutedInkTint)
                }

                Spacer()

                dayHeroBadge(
                    title: "下一关键时间",
                    value: formattedDate(summary?.predictions?.nextPeriodStart) ?? "--"
                )
            }

            dayMiniTimeline

            HStack(spacing: 10) {
                dayMetricCard(title: "出血", value: selectedLog?.flowLevel, tint: periodTint)
                dayMetricCard(title: "痛经", value: selectedLog?.painLevel, tint: painTint)
                dayMetricCard(title: "情绪", value: selectedLog?.moodLevel, tint: moodTint)
            }

            Text(dayNarrativeText)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(mutedInkTint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), periodTint.opacity(isAiryStyle ? 0.03 : 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isAiryStyle ? airyBorderTint : Color.clear, lineWidth: 1)
        )
    }

    private var dayMiniTimeline: some View {
        HStack(spacing: 8) {
            timelineCapsule(title: "当前阶段", value: currentPhaseTitle, tint: periodTint)
            timelineCapsule(title: "周期日", value: cycleDayText, tint: fertileTint)
            timelineCapsule(title: "来源", value: predictionSourceText, tint: moodTint)
        }
    }

    private var dayNarrativeText: String {
        guard let date = normalizedSelectedDate else { return "继续补充当天状态后，这里会形成更完整的周期日报判断。" }
        if let log = selectedLog {
            if !hasRecordedSymptomValue(log) {
                return String(localized: "\(Self.longLabelFormatter.string(from: date)) 有一条周期记录，但出血量、痛经和情绪字段都未记录。补充后才能形成当天判断。")
            }
            return String(localized: "\(Self.longLabelFormatter.string(from: date)) 记录到 \(selectedPhaseText)，症状读数为 \(symptomScoreText(log))。这一天更适合作为当日判断，而不是拿来单独看长期趋势。")
        }
        return String(localized: "\(Self.longLabelFormatter.string(from: date)) 暂无症状记录。可以先结合当前阶段和下一关键时间理解这一天，再继续补录当天状态。")
    }

    private func layeredTrendCard(isMonthView: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            layeredLegend(isMonthView: isMonthView)
            phaseBandChart(isMonthView: isMonthView)
            symptomTrackPanel(isMonthView: isMonthView)

            if let selectedDate = normalizedSelectedDate {
                selectedDetailCard(for: selectedDate)
            }
        }
        .padding(14)
        .background(
            (isAiryStyle ? Color.white : Theme.Colors.secondaryBackground.opacity(0.48)),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isAiryStyle ? airyBorderTint : Color.clear, lineWidth: 1)
        )
    }

    private func layeredLegend(isMonthView: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isMonthView ? "月度节律分布" : "最近阶段变化")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            HStack(spacing: 12) {
                legendItem(title: "经期", color: periodTint)
                legendItem(title: "预测经期", color: predictedPeriodTint)
                legendItem(title: "易孕窗口", color: fertileTint)
                legendItem(title: "排卵提示", color: ovulationTint)
            }
        }
    }

    private func phaseBandChart(isMonthView: Bool) -> some View {
        Chart {
            ForEach(visiblePhaseRanges) { item in
                RectangleMark(
                    xStart: .value("开始", max(item.start, chartDomain.lowerBound)),
                    xEnd: .value("结束", min(calendarEnd(of: item.end), chartDomain.upperBound)),
                    yStart: .value("下限", 0),
                    yEnd: .value("上限", 1)
                )
                .foregroundStyle(rangeColor(for: item.type))
            }

            ForEach(visibleOvulationRanges) { item in
                RuleMark(x: .value("日期", midpoint(of: item)))
                    .foregroundStyle(ovulationTint.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }

            ForEach(selectedDateMarkers, id: \.self) { selectedDate in
                RuleMark(x: .value("选中", selectedDate))
                    .foregroundStyle(inkTint.opacity(0.3))
            }
        }
        .chartXScale(domain: chartDomain)
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: axisDates(for: chartDomain, range: range)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color.black.opacity(0.05))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.black.opacity(0.10))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(for: date))
                            .font(.appSystem(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .allowsHitTesting(!isStaticForExport)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateSelection(value: value.location, proxy: proxy, geometry: geo)
                            }
                    )
            }
        }
        .frame(height: isMonthView ? 76 : 68)
    }

    private func symptomTrackPanel(isMonthView: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            symptomTrackRowView(row: trackRow(for: .flow), isMonthView: isMonthView)
            symptomTrackRowView(row: trackRow(for: .pain), isMonthView: isMonthView)
            symptomTrackRowView(row: trackRow(for: .mood), isMonthView: isMonthView)

            if trackRows.allSatisfy(\.events.isEmpty) {
                Text("暂无症状记录，继续补充出血量、痛经和情绪后，这里会显示它们在周期中的出现位置。")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private func trackRow(for key: SymptomMetricKey) -> SymptomTrackRow {
        trackRows.first(where: { $0.key == key }) ?? SymptomTrackRow(key: key, events: [])
    }

    private func symptomTrackRowView(row: SymptomTrackRow, isMonthView: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.key.trackTitle)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text(trackSummaryText(for: row))
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(mutedInkTint)
            }

            Chart {
                ForEach(row.events, id: \.id) { event in
                    symptomBarMark(for: event, row: row, isMonthView: isMonthView)
                    symptomPointMark(for: event, row: row, isMonthView: isMonthView)
                }

                ForEach(selectedDateMarkers, id: \.self) { selectedDate in
                    RuleMark(x: .value("选中", selectedDate))
                        .foregroundStyle(inkTint.opacity(0.24))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: 0...maxTrackYValue(isMonthView: isMonthView))
            .chartYAxis(content: {
                symptomTrackYAxis(isMonthView: isMonthView)
            })
            .chartXAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .allowsHitTesting(!isStaticForExport)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(value: value.location, proxy: proxy, geometry: geo)
                                }
                        )
                }
            }
            .frame(height: isMonthView ? 44 : 48)
        }
    }

    private func selectedDetailCard(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(Self.shortLabelFormatter.string(from: date))
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(inkTint)
                Text(selectedPhaseText)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text(detailBadgeText(for: date))
                    .font(Theme.Typography.caption.weight(.bold))
                    .foregroundColor(periodTint)
            }

            Text(detailDescription(for: date))
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(mutedInkTint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: isAiryStyle ? [Color.white, periodTint.opacity(0.03)] : [periodTint.opacity(0.10), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isAiryStyle ? airyBorderTint : Color.clear, lineWidth: 1)
        )
    }

    private func updateSelection(value: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard !isStaticForExport else { return }
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let x = value.x - frame.origin.x
        if let date: Date = proxy.value(atX: x, as: Date.self) {
            let calendar = Calendar.current
            let normalized = calendar.startOfDay(for: date)
            let latestSelectableDate = calendar.date(byAdding: .day, value: -1, to: chartDomain.upperBound) ?? chartDomain.lowerBound
            selectedDate = min(max(normalized, chartDomain.lowerBound), latestSelectableDate)
        }
    }

    private func axisDates(for domain: ClosedRange<Date>, range: TrendsRange) -> [Date] {
        switch range {
        case .day:
            return [domain.lowerBound, midpoint(start: domain.lowerBound, end: domain.upperBound), domain.upperBound]
        case .week:
            return TrendsSelectionFormatter.axisDates(for: .week, dateDomain: domain)
        case .month:
            return TrendsSelectionFormatter.axisDates(for: .month, dateDomain: domain)
        }
    }

    private func axisLabel(for date: Date) -> String {
        switch range {
        case .day:
            return Self.hourLabelFormatter.string(from: date)
        case .week, .month:
            return TrendsSelectionFormatter.axisLabel(for: date, range: range)
        }
    }

    private func logs(in domain: ClosedRange<Date>) -> [PeriodDayLog] {
        orderedLogs.filter {
            guard let raw = $0.date, let date = Self.dayFormatter.date(from: raw) else { return false }
            return date >= domain.lowerBound && date < domain.upperBound
        }
    }

    private func midpoint(of range: OverlayRangePoint) -> Date {
        midpoint(start: range.start, end: range.end)
    }

    private func midpoint(start: Date, end: Date) -> Date {
        Date(timeIntervalSince1970: (start.timeIntervalSince1970 + end.timeIntervalSince1970) / 2)
    }

    private func calendarEnd(of date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
    }

    private func rangeColor(for type: String) -> Color {
        switch type {
        case "PERIOD":
            return periodTint.opacity(0.24)
        case "PREDICTED_PERIOD":
            return predictedPeriodTint.opacity(0.20)
        case "FERTILE_WINDOW":
            return fertileTint.opacity(0.18)
        default:
            return Theme.Colors.lightGray.opacity(0.10)
        }
    }

    private func phaseText(_ phase: String?) -> String {
        switch phase {
        case "MENSTRUATION":
            return "经期"
        case "FOLLICULAR":
            return "卵泡期"
        case "OVULATION":
            return "排卵期"
        case "LUTEAL":
            return "黄体期"
        default:
            return String(localized: "周期观察")
        }
    }

    private func formattedDate(_ rawDate: String?) -> String? {
        guard let rawDate, let date = Self.dayFormatter.date(from: rawDate) else { return nil }
        return Self.shortLabelFormatter.string(from: date)
    }

    private func trackSummaryText(for row: SymptomTrackRow) -> String {
        guard let latest = row.events.last else { return "暂无记录" }
        return String(localized: "最近 \(latest.value)/5")
    }

    @AxisContentBuilder
    private func symptomTrackYAxis(isMonthView: Bool) -> some AxisContent {
        AxisMarks(
            position: .leading,
            values: symptomTrackAxisValues(isMonthView: isMonthView)
        ) { value in
            AxisValueLabel {
                if let number = value.as(Double.self), number > 0 {
                    Text(isMonthView ? "高" : "强")
                        .font(.appSystem(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private func symptomTrackAxisValues(isMonthView: Bool) -> [Double] {
        [0.0, maxTrackAxisMark(isMonthView: isMonthView)]
    }

    @ChartContentBuilder
    private func symptomBarMark(for event: SymptomEvent, row: SymptomTrackRow, isMonthView: Bool) -> some ChartContent {
        let strength = trackEventStrength(for: event.value, isMonthView: isMonthView)
        let color = row.key.color(periodTint: periodTint, painTint: painTint, moodTint: moodTint)
        let opacity = isMonthView ? 0.68 : 0.84

        BarMark(
            x: .value("日期", event.date),
            yStart: .value("起点", 0.0),
            yEnd: .value("强度", strength)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .foregroundStyle(color.opacity(opacity))
    }

    @ChartContentBuilder
    private func symptomPointMark(for event: SymptomEvent, row: SymptomTrackRow, isMonthView: Bool) -> some ChartContent {
        let strength = trackEventStrength(for: event.value, isMonthView: isMonthView)
        let color = row.key.color(periodTint: periodTint, painTint: painTint, moodTint: moodTint)
        let size = isEventSelected(event.date) ? 62.0 : 28.0

        PointMark(
            x: .value("日期", event.date),
            y: .value("强度", strength)
        )
        .symbolSize(size)
        .foregroundStyle(color)
    }

    private func trackEventStrength(for value: Int, isMonthView: Bool) -> Double {
        let baseValue = isMonthView ? Double(value) * 0.52 : Double(value)
        return max(0.18, baseValue)
    }

    private func isEventSelected(_ date: Date) -> Bool {
        guard let selectedDate = normalizedSelectedDate else { return false }
        return Calendar.current.isDate(selectedDate, inSameDayAs: date)
    }

    private func maxTrackYValue(isMonthView: Bool) -> Double {
        isMonthView ? 3.0 : 5.0
    }

    private func maxTrackAxisMark(isMonthView: Bool) -> Double {
        isMonthView ? 3.0 : 5.0
    }

    private func detailBadgeText(for date: Date) -> String {
        guard let log = selectedLog else {
            return visibleOverlayRanges.contains(where: { date >= $0.start && date <= $0.end }) ? "区间提示" : "暂无记录"
        }
        return String(localized: "出血 \(metricValueText(log.flowLevel)) / 痛经 \(metricValueText(log.painLevel)) / 情绪 \(metricValueText(log.moodLevel))")
    }

    private func detailDescription(for date: Date) -> String {
        let dateText = Self.shortLabelFormatter.string(from: date)
        if let log = selectedLog {
            let flow = log.flowLevel
            let pain = log.painLevel
            let mood = log.moodLevel
            if !hasRecordedSymptomValue(log) {
                return String(localized: "\(dateText) 有一条周期记录，但出血量、痛经和情绪字段都未记录，暂时不能判断当天症状。")
            }
            if range == .month {
                return String(localized: "\(dateText) 在整个月的节律里记录到 \(selectedPhaseText)，症状读数为 \(symptomScoreText(log))。这个月更适合看它与前后窗口是否连续出现。")
            }
            if let flow, flow >= 4 {
                return String(localized: "\(dateText) 的出血量偏高，建议和痛经、睡眠与活动安排一起读，判断这几天是否需要更温和节奏。")
            }
            if let pain, pain >= 4 {
                return String(localized: "\(dateText) 的不适感更明显，更适合结合这周的阶段位置和恢复状态一起看。")
            }
            if let mood, mood >= 4 {
                return String(localized: "\(dateText) 的情绪波动更突出，可以留意它是否和当前周期窗口同步出现。")
            }
            return String(localized: "\(dateText) 已记录的项目整体比较平稳，更适合结合前后几天一起读，而不是只看单点。")
        }

        if let range = visibleOverlayRanges.first(where: { date >= $0.start && date <= $0.end }) {
            switch range.type {
            case "PREDICTED_PERIOD":
                return String(localized: "\(dateText) 落在预测经期窗口内，后续可结合真实记录继续校正周期节律。")
            case "FERTILE_WINDOW":
                return String(localized: "\(dateText) 处在易孕窗口，更适合连同体感和阶段信号一起看。")
            case "OVULATION":
                return String(localized: "\(dateText) 接近排卵提示日，通常更适合看前后几天的连续变化。")
            default:
                return String(localized: "\(dateText) 处在周期标记区间内，继续补充记录后这里会更完整。")
            }
        }

        return String(localized: "\(dateText) 还没有症状记录，继续补充后这里会更完整地显示周期节律。")
    }

    private func dayHeroBadge(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(inkTint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isAiryStyle ? airyBorderTint : Color.clear, lineWidth: 1)
        )
    }

    private func dayMetricCard(title: String, value: Int?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(metricScoreText(value))
                .font(.appSystem(size: 20, weight: .black, design: .serif))
                .foregroundColor(inkTint)
            Capsule()
                .fill(tint.opacity(0.18))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    if let value {
                        Capsule()
                            .fill(tint)
                            .frame(width: CGFloat(max(0, min(value, 5))) / 5 * 88, height: 8)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isAiryStyle ? airyBorderTint : Color.clear, lineWidth: 1)
        )
    }

    private func metricValueText(_ value: Int?) -> String {
        value.map(String.init) ?? "--"
    }

    private func metricScoreText(_ value: Int?) -> String {
        value.map { "\($0)/5" } ?? "--"
    }

    private func symptomScoreText(_ log: PeriodDayLog) -> String {
        "\(metricScoreText(log.flowLevel)) / \(metricScoreText(log.painLevel)) / \(metricScoreText(log.moodLevel))"
    }

    private func hasRecordedSymptomValue(_ log: PeriodDayLog) -> Bool {
        log.flowLevel != nil || log.painLevel != nil || log.moodLevel != nil
    }

    private func timelineCapsule(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(inkTint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), tint.opacity(isAiryStyle ? 0.03 : 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isAiryStyle ? airyBorderTint : Color.clear, lineWidth: 1)
        )
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(mutedInkTint)
        }
    }

    private struct OverlayRangePoint: Identifiable {
        var id: String { "\(type)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
        let start: Date
        let end: Date
        let type: String
    }

    private struct SummaryItem: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let detail: String
    }

    private struct SymptomEvent: Identifiable {
        var id: TimeInterval { date.timeIntervalSince1970 }
        let date: Date
        let value: Int
    }

    private struct SymptomTrackRow: Identifiable {
        let key: SymptomMetricKey
        let events: [SymptomEvent]

        var id: String { key.rawValue }
    }

    private enum SymptomMetricKey: String, CaseIterable, Identifiable {
        case flow
        case pain
        case mood

        var id: String { rawValue }

        var trackTitle: String {
            switch self {
            case .flow:
                return String(localized: "出血记录")
            case .pain:
                return String(localized: "痛经强度")
            case .mood:
                return "情绪波动"
            }
        }

        func value(from log: PeriodDayLog) -> Int? {
            switch self {
            case .flow:
                return log.flowLevel
            case .pain:
                return log.painLevel
            case .mood:
                return log.moodLevel
            }
        }

        func color(periodTint: Color, painTint: Color, moodTint: Color) -> Color {
            switch self {
            case .flow:
                return periodTint
            case .pain:
                return painTint
            case .mood:
                return moodTint
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let shortLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("Md")
        return f
    }()

    private static let longLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MEd")
        return f
    }()

    private static let hourLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.dateFormat = "H:mm"
        return f
    }()
}

private struct PeriodEducationQuestion: Identifiable {
    let question: String

    var id: String { question }
}

private struct PeriodEducationSection: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    let onSelectQuestion: (String) -> Void
    let onSelectMore: () -> Void

    private let items: [PeriodEducationItem] = [
        PeriodEducationItem(
            question: "月经周期是如何计算的？",
            title: "月经周期怎么计算？",
            subtitle: "通常从本次月经第一天算到下次月经前一天，长度因人而异。",
            tag: "周期",
            systemImage: "calendar",
            tint: Color(hex: "B86A63")
        ),
        PeriodEducationItem(
            question: "排卵期与易孕期有什么区别？",
            title: "排卵期和易孕期有什么区别？",
            subtitle: "排卵日是一个时间点，易孕期是一段窗口，前后几天都可能受孕。",
            tag: "排卵",
            systemImage: "sparkles",
            tint: Color(hex: "4C7DFF")
        ),
        PeriodEducationItem(
            question: "经期症状波动大正常吗？",
            title: "经期症状波动大正常吗？",
            subtitle: "出血、腹痛和情绪受睡眠、压力与作息影响，短期波动并不少见。",
            tag: "科普",
            systemImage: "heart.text.square.fill",
            tint: Color(hex: "8C6C7E")
        ),
        PeriodEducationItem(
            question: "经期推迟几天常见吗？",
            title: "经期推迟几天常见吗？",
            subtitle: "睡眠、压力、旅行和体重变化都可能让周期短期前后浮动几天。",
            tag: "延迟",
            systemImage: "clock.badge.exclamationmark.fill",
            tint: Color(hex: "C99690")
        ),
        PeriodEducationItem(
            question: "痛经什么时候该就医？",
            title: "痛经什么时候该就医？",
            subtitle: "如果疼痛持续加重、影响生活或伴随异常出血，建议尽快寻求专业评估。",
            tag: "就医",
            systemImage: "cross.case.fill",
            tint: Color(hex: "B28FA1")
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                    Text("周期科普")
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("了解周期变化与常见症状")
                        .font(Theme.Typography.supporting)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Spacer()

                Button {
                    onSelectMore()
                } label: {
                    HStack(spacing: 6) {
                        Text("查看更多")
                            .font(Theme.Typography.captionBold)
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 12, weight: .bold))
                    }
                    .foregroundColor(periodEducationAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(periodEducationAccent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.small) {
                    educationItems
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.top, 4)
    }

    private var periodEducationAccent: Color {
        Color(hex: "B86A63")
    }

    @ViewBuilder
    private var educationItems: some View {
        ForEach(items) { item in
            Button {
                onSelectQuestion(item.question)
            } label: {
                PeriodEducationTile(
                    title: item.title,
                    subtitle: item.subtitle,
                    tag: item.tag,
                    systemImage: item.systemImage,
                    tint: item.tint
                )
                .frame(width: adaptiveLayout.usesExpandedLayout ? 232 : 224)
                .frame(minHeight: adaptiveLayout.usesExpandedLayout ? 168 : nil)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PeriodEducationItem: Identifiable {
    let question: String
    let title: String
    let subtitle: String
    let tag: String
    let systemImage: String
    let tint: Color

    var id: String { question }
}

private struct PeriodEducationTile: View {
    let title: String
    let subtitle: String
    let tag: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(tint.opacity(0.10))
                    Image(systemName: systemImage)
                        .font(.appSystem(size: 20, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 46, height: 46)

                Spacer(minLength: 10)

                Text(tag)
                    .font(Theme.Typography.label)
                    .foregroundColor(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(tint.opacity(0.10), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(Theme.Typography.supporting)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("查看详情")
                    .font(Theme.Typography.captionBold)
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .bold))
            }
            .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .padding(Theme.Spacing.medium)
        .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: Theme.Stroke.subtleWidth)
        )
    }
}
