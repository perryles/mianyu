/// HRVDetailView 由健康首页与今日页调用，作为「心率变异性(HRV)」详情页。
/// 负责展示 HRV 趋势、区间带、测量入口与影响因素解读，并支持手动测量。

import SwiftUI
import Charts
import WidgetKit

/// HRVBand结构体 作为健康模块里的辅助类型。
/// 负责解释具体指标含义，并展示对应的趋势、影响因素或分析结果。
private struct HRVBand: Identifiable {
    let id: String
    let lowerBound: Double
    let upperBound: Double
    let color: Color
}

private struct HRVSmoothedPoint: Identifiable {
    let id: Date
    let date: Date
    let value: Double
}

/// HRVMeasurement视图模型 作为健康模块里的界面状态管理入口。
/// 负责健康指标详情展示。
@MainActor
@Observable
final class HRVMeasurementViewModel {
    /// Measurement State 枚举，作为内部辅助类型，用于细分外层健康指标详情展示中的状态或分支。
    enum MeasurementState {
        case idle
        case measuring
        case completed
        case failed(String)
    }

    var state: MeasurementState = .idle
    var latestHRV: Double?
    var todayHRVPoints: [TimeSeriesPointDouble] = []
    var sessionHeartRatePoints: [TimeSeriesPoint] = []
    var remainingSeconds: Int = 120
    var measuredAt: Date?

    private var measurementTask: Task<Void, Never>?
    private var sessionStart: Date?

    var progress: Double {
        1.0 - Double(remainingSeconds) / 120.0
    }

    var isMeasuring: Bool {
        if case .measuring = state { return true }
        return false
    }

    func load(initial: RealtimeHealth?) {
        latestHRV = initial?.hrv.nonZero
        measuredAt = initial.map { Date(timeIntervalSince1970: TimeInterval($0.timestamp)) }
        refreshFromHealthKit()
    }

    func startMeasurement() {
        guard !isMeasuring else { return }

        measurementTask?.cancel()
        remainingSeconds = 120
        sessionHeartRatePoints = []
        sessionStart = Date()
        state = .measuring

        measurementTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self, self.remainingSeconds > 0 else { return }
                    self.remainingSeconds -= 1
                }

                let shouldFinish = await MainActor.run { self?.remainingSeconds == 0 }
                if shouldFinish == true {
                    await self?.finishMeasurement()
                    return
                }
            }
        }
    }

    func cancelMeasurement() {
        measurementTask?.cancel()
        measurementTask = nil
        remainingSeconds = 120
        state = .idle
    }

    func refreshFromHealthKit() {
        Task {
            do {
                async let latest = HealthKitManager.shared.fetchLatestHRV()
                async let today = HealthKitManager.shared.fetchTodayHRVSamples()
                let latestValue = try? await latest
                let todayPoints = (try? await today) ?? []

                latestHRV = latestValue?.nonZero ?? todayPoints.last?.value.nonZero ?? latestHRV
                todayHRVPoints = todayPoints
                if let latestHRV {
                    measuredAt = todayPoints.last?.date ?? Date()
                    pushRealtimeSnapshot(hrv: latestHRV)
                }
            }
        }
    }

    private func finishMeasurement() async {
        measurementTask?.cancel()
        measurementTask = nil

        let end = Date()
        let start = sessionStart ?? end.addingTimeInterval(-120)

        do {
            try await HealthKitManager.shared.saveMindfulSession(start: start, end: end)
            let latest = try? await HealthKitManager.shared.fetchLatestHRV()
            let today = (try? await HealthKitManager.shared.fetchTodayHRVSamples()) ?? []
            let heartRates = (try? await HealthKitManager.shared.fetchHeartRateSeries(start: start, end: end, maxPoints: 80)) ?? []

            latestHRV = latest?.nonZero ?? today.last?.value.nonZero ?? latestHRV
            todayHRVPoints = today
            sessionHeartRatePoints = heartRates
            measuredAt = Date()

            if let latestHRV {
                pushRealtimeSnapshot(hrv: latestHRV, heartRate: heartRates.last?.value)
            }
            state = .completed
        } catch {
            state = .failed("未能写入正念记录，请检查健康权限。")
        }
    }

    private func pushRealtimeSnapshot(hrv: Double, heartRate: Int? = nil) {
        let bpm = heartRate ?? Int(AppGroupManager.shared.getLatestHeartRate() ?? 0)
        let vitals = RealtimeHealth(
            bpm: bpm,
            hrv_sdnn: hrv,
            timestamp: Int64(Date().timeIntervalSince1970)
        )

        HealthDataManager.shared.pushRealtimeToWatch(vitals)
    }
}

/// HRV视图 由上级页面或路由调用，作为健康模块里的界面或内容组件。
/// 负责健康指标详情展示。
struct HRVDetailView: View {
    let realtimeHealth: RealtimeHealth?
    var showsDismissButton: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = HRVMeasurementViewModel()
    @AppStorage("app_font_scale_level") private var appFontScaleLevelRaw: Int = 2
    @State private var selectedHRVTimestamp: Date?
    @State private var selectedRange: MetricDetailRange = .day
    @State private var selectedDate: Date
    @State private var aggregatedHRVPoints: [TimeSeriesPointDouble] = []
    @State private var isTrendLoading = false
    @State private var showingReminderSettings = false
    @State private var loadRequestID = UUID()

    private static let tint = Theme.Colors.mintGreen
    private static let accent = Color(hex: "EAF6FF")

    private var appFontScaleLevel: AppFontScaleLevel {
        AppFontScaleLevel(rawValue: appFontScaleLevelRaw) ?? .two
    }

    init(realtimeHealth: RealtimeHealth?, initialDate: Date = Date(), showsDismissButton: Bool = false) {
        self.realtimeHealth = realtimeHealth
        self.showsDismissButton = showsDismissButton
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
    }

    private var canMoveForward: Bool {
        selectedRange.canShiftForward(from: selectedDate)
    }

    var body: some View {
        ZStack {
            HealthDetailPageBackground()
            ambientBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    heroCard
                    overviewCard
                    recoveryContextCard
                    recoverySnapshotCard
                    trendCard
                    guideCard
                    noteCard
                    metricDisclaimerCard
                }
                .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                .padding(.bottom, HealthDetailDesignSystem.pageBottomPadding)
            }
        }
        .healthDetailNavigation(title: HealthPageName.hrv)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    HealthNavigationDismissButton {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("设置") { showingReminderSettings = true }
            }
        }
        .sheet(isPresented: $showingReminderSettings) {
            NavigationStack {
                MetricReminderSettingsView(metricKey: "hrv", metricTitle: "HRV")
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .onAppear {
            if Calendar.current.isDateInToday(selectedDate) {
                viewModel.load(initial: realtimeHealth)
            }
        }
        .task {
            await reloadRangeData()
        }
        .onChange(of: selectedRange) { _, _ in
            Task { await reloadRangeData() }
        }
        .onChange(of: selectedDate) { _, _ in
            Task { await reloadRangeData() }
        }
    }

    private var metricDisclaimerCard: some View {
        HealthDisclaimerCard(
            message: "本页心率变异性数据、趋势和解读仅供日常自我管理参考，不构成医疗诊断或治疗建议。若身体不适或需要做出重要健康决定，请咨询专业医生。"
        )
    }

    private var ambientBackground: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Self.tint.opacity(0.16))
                    .frame(width: 190, height: 190)
                    .blur(radius: 30)
                    .offset(x: -42, y: -38)
                Spacer()
                Circle()
                    .fill(Color(hex: "A8D8FF").opacity(0.18))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)
                    .offset(x: 30, y: -22)
            }
            Spacer()
        }
        .ignoresSafeArea()
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前心率变异性")
                        .font(Theme.Typography.scaled(size: 17, weight: .bold, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(currentValueText)
                            .font(Theme.Typography.scaled(size: 50, weight: .heavy, design: .rounded, level: appFontScaleLevel))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("ms")
                            .font(Theme.Typography.scaled(size: 16, weight: .bold, design: .rounded, level: appFontScaleLevel))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                sectionBadge(statusBadgeText, tint: Self.tint)
            }

            Picker("", selection: $selectedRange) {
                ForEach(MetricDetailRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    selectedDate = selectedRange.shiftClampedToToday(selectedDate, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.surface.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(selectedRange.title(for: selectedDate))
                    .font(Theme.Typography.scaled(size: 16, weight: .bold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button {
                    selectedDate = selectedRange.shiftClampedToToday(selectedDate, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(canMoveForward ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.surface.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
            }

            Text(statusText)
                .font(Theme.Typography.scaled(size: 14, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                contextTag(title: "建议动作", value: suggestedActionText)
                contextTag(title: "采样窗口", value: samplingWindowText)
            }

            if let measuredAt = viewModel.measuredAt {
                Text("更新于 \(measuredAt.formatted(.dateTime.hour().minute()))")
                    .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .healthDetailSurface()
    }

    private var overviewCard: some View {
        HStack(spacing: 10) {
            overviewPill(title: selectedRange == .day ? "本次" : "当前", value: currentValueText == "—" ? "暂无" : "\(currentValueText) ms", tint: Self.tint)
            overviewPill(title: "样本", value: "\(activeHRVPoints.count) 个", tint: Color(hex: "7D8BFF"))
            overviewPill(title: "状态", value: statusBadgeText, tint: Color(hex: "FFB340"))
        }
    }

    private var recoveryContextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("恢复节律")
                        .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("先判断当前恢复松紧，再决定今天适合维持、观察还是放慢。")
                        .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                sectionBadge(statusBadgeText, tint: Self.tint)
            }

            HStack(spacing: 10) {
                contextTag(title: "当前状态", value: statusBadgeText)
                contextTag(title: "恢复方向", value: recoveryDirectionText)
            }

            Text(hrvInsightText)
                .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .detailCardSurface(tint: Self.accent)
    }

    private var recoverySnapshotCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("恢复摘要")
                        .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(selectedRange == .day ? "用当天的真实样本，快速看恢复高点、低点和整体节律。" : "用这段时间的真实记录，快速看恢复高点、低点和整体节律。")
                        .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                sectionBadge(snapshotBadgeText, tint: Color(hex: "7D8BFF"))
            }

            HStack(spacing: 10) {
                contextTag(title: selectedRange == .day ? "日内均值" : "范围均值", value: averageHRVValue.map { "\(Int($0.rounded())) ms" } ?? "暂无")
                contextTag(title: "高点时段", value: peakHRVTimeText)
                contextTag(title: "低点时段", value: lowestHRVTimeText)
            }

            HStack(spacing: 10) {
                contextTag(title: "波动等级", value: variabilityLevelText)
                contextTag(title: "最新偏移", value: latestDeltaText)
            }

            Text(recoverySummaryText)
                .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .detailCardSurface(tint: Color(hex: "EEF3FF"))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedRange == .day ? "今日心率变异性" : (selectedRange == .week ? "本周心率变异性" : "本月心率变异性"))
                        .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(trendSummaryText)
                        .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                sectionBadge(activeHRVPoints.isEmpty ? "暂无数据" : "\(activeHRVPoints.count) 个样本", tint: Self.tint)
            }

            if !activeHRVPoints.isEmpty {
                HStack(spacing: 8) {
                    chartMetricChip(title: selectedRange == .day ? "本次" : "当前", value: currentValueText == "—" ? "暂无" : currentValueText)
                    chartMetricChip(title: "均值", value: averageHRVText)
                    chartMetricChip(title: "波动", value: hrvSpreadText)
                }
            }

            if isTrendLoading {
                ProgressView()
                    .frame(height: 168)
                    .frame(maxWidth: .infinity)
            } else if activeHRVPoints.isEmpty {
                emptyTrendChart(selectedRange == .day ? "健康 App 暂无心率变异性样本" : "健康 App 暂无这段时间的 HRV 趋势")
            } else if selectedRange == .day {
                Chart {
                    ForEach(hrvBands) { band in
                        RectangleMark(
                            xStart: .value("开始", chartDomain.lowerBound),
                            xEnd: .value("结束", chartDomain.upperBound),
                            yStart: .value("下界", band.lowerBound),
                            yEnd: .value("上界", band.upperBound)
                        )
                        .foregroundStyle(band.color.opacity(0.08))
                    }

                    if let lowerThreshold = lowerRecoveryThreshold {
                        RuleMark(y: .value("偏紧阈值", lowerThreshold))
                            .foregroundStyle(Color(hex: "6D7EF7").opacity(0.16))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }

                    if let upperThreshold = upperRecoveryThreshold {
                        RuleMark(y: .value("放松阈值", upperThreshold))
                            .foregroundStyle(Color(hex: "33B58F").opacity(0.16))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }

                    ForEach(activeHRVPoints) { item in
                        AreaMark(
                            x: .value("时间", item.date),
                            yStart: .value("基线", yAxisDomain.lowerBound),
                            yEnd: .value("HRV", item.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Self.tint.opacity(selectedHRVPoint == nil || selectedHRVPoint?.id == item.id ? 0.22 : 0.10), Self.tint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(smoothedHRVPoints) { item in
                        LineMark(
                            x: .value("时间", item.date),
                            y: .value("节律线", item.value)
                        )
                        .foregroundStyle(Color(hex: "11233F").opacity(0.28))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [5, 4]))
                    }

                    ForEach(activeHRVPoints) { item in

                        LineMark(
                            x: .value("时间", item.date),
                            y: .value("HRV", item.value)
                        )
                        .foregroundStyle(hrvGlowColor.opacity(0.28))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

                        LineMark(
                            x: .value("时间", item.date),
                            y: .value("HRV", item.value)
                        )
                        .foregroundStyle(hrvLineGradient)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("时间", item.date),
                            y: .value("HRV", item.value)
                        )
                            .symbolSize(item.id == activeHRVPoints.last?.id ? 84 : 34)
                            .foregroundStyle(Theme.Colors.onAccent)
                            .opacity(selectedHRVPoint == nil || selectedHRVPoint?.id == item.id ? 1 : 0.42)
                            .annotation(position: .overlay, alignment: .center) {
                                Circle()
                                    .fill(hrvLineColor(for: item.value))
                                    .frame(width: item.id == activeHRVPoints.last?.id ? 12 : 9, height: item.id == activeHRVPoints.last?.id ? 12 : 9)
                            }
                    }

                    if let average = averageHRVValue {
                        RuleMark(y: .value("日内均值", average))
                            .foregroundStyle(Color(hex: "1F7A6B").opacity(0.30))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("日内均值 \(Int(average.rounded()))")
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "1F7A6B"))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                            }
                    }

                    if let latestPoint = latestHRVPoint {
                        PointMark(
                            x: .value("时间", latestPoint.date),
                            y: .value("最新", latestPoint.value)
                        )
                        .symbolSize(104)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .annotation(position: .topTrailing, spacing: 10) {
                            chartCalloutBadge(
                                title: "最新",
                                value: "\(Int(latestPoint.value.rounded())) ms",
                                tint: hrvLineColor(for: latestPoint.value)
                            )
                        }
                    }

                    if let peakPoint = peakHRVPoint {
                        PointMark(
                            x: .value("时间", peakPoint.date),
                            y: .value("HRV", peakPoint.value)
                        )
                        .symbolSize(72)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .annotation(position: .top) {
                            chartCalloutBadge(
                                title: "高点",
                                value: "\(Int(peakPoint.value.rounded())) ms",
                                tint: Color(hex: "33B58F")
                            )
                        }
                    }

                    if let lowestPoint = lowestHRVPoint {
                        PointMark(
                            x: .value("时间", lowestPoint.date),
                            y: .value("HRV", lowestPoint.value)
                        )
                        .symbolSize(64)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .annotation(position: .bottom) {
                            chartCalloutBadge(
                                title: "低点",
                                value: "\(Int(lowestPoint.value.rounded())) ms",
                                tint: Color(hex: "5C6DFF")
                            )
                        }
                    }

                    if let selectedHRVPoint {
                        RuleMark(x: .value("选中", selectedHRVPoint.date))
                            .foregroundStyle(Self.tint.opacity(0.24))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        PointMark(
                            x: .value("时间", selectedHRVPoint.date),
                            y: .value("HRV", selectedHRVPoint.value)
                        )
                        .symbolSize(88)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .annotation(position: .overlay, alignment: .center) {
                            Circle()
                                .fill(hrvLineColor(for: selectedHRVPoint.value))
                                .frame(width: 13, height: 13)
                        }
                    }
                }
                .chartXScale(domain: chartDomain)
                .chartYScale(domain: yAxisDomain)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.25)
                                        .sequenced(before: DragGesture(minimumDistance: 0))
                                        .onChanged { value in
                                            switch value {
                                            case .first:
                                                break
                                            case .second(true, let drag):
                                                guard let drag else { return }
                                                updateHRVSelection(at: drag.location, frame: frame, proxy: proxy)
                                            default:
                                                break
                                            }
                                        }
                                        .onEnded { value in
                                            switch value {
                                            case .second(true, let drag):
                                                if let drag {
                                                    updateHRVSelection(at: drag.location, frame: frame, proxy: proxy)
                                                }
                                            default:
                                                break
                                            }
                                        }
                                )
                        } else {
                            Color.clear
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisMarks) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .clipped()
                        .padding(.leading, 4)
                        .padding(.trailing, 8)
                }
                .frame(height: 208)

                hrvChartLegendRow

                if let selectedHRVPoint {
                    selectedHRVDetailCard(for: selectedHRVPoint)
                }

                Text(hrvInsightText)
                    .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart(activeHRVPoints) { item in
                    AreaMark(
                        x: .value("日期", item.date),
                        yStart: .value("基线", yAxisDomain.lowerBound),
                        yEnd: .value("HRV", item.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Self.tint.opacity(0.20), Self.tint.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", item.date),
                        y: .value("HRV", item.value)
                    )
                    .foregroundStyle(hrvLineGradient)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("日期", item.date),
                        y: .value("HRV", item.value)
                    )
                    .foregroundStyle(Theme.Colors.onAccent)
                    .symbolSize(item.id == selectedHRVPoint?.id ? 74 : 34)
                    .annotation(position: .overlay, alignment: .center) {
                        Circle()
                            .fill(hrvLineColor(for: item.value))
                            .frame(width: item.id == selectedHRVPoint?.id ? 12 : 9, height: item.id == selectedHRVPoint?.id ? 12 : 9)
                    }

                    if let average = averageHRVValue {
                        RuleMark(y: .value("均值", average))
                            .foregroundStyle(Color(hex: "1F7A6B").opacity(0.30))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    if let selectedHRVPoint {
                        RuleMark(x: .value("选中", selectedHRVPoint.date))
                            .foregroundStyle(Self.tint.opacity(0.24))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXScale(domain: chartDomain)
                .chartYScale(domain: yAxisDomain)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.25)
                                        .sequenced(before: DragGesture(minimumDistance: 0))
                                        .onChanged { value in
                                            switch value {
                                            case .first:
                                                break
                                            case .second(true, let drag):
                                                guard let drag else { return }
                                                updateHRVSelection(at: drag.location, frame: frame, proxy: proxy)
                                            default:
                                                break
                                            }
                                        }
                                )
                        } else {
                            Color.clear
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisMarks) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .frame(height: 208)

                if let selectedHRVPoint {
                    selectedHRVDetailCard(for: selectedHRVPoint)
                }

                Text(hrvInsightText)
                    .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .detailCardSurface(tint: Self.tint)
    }


    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("建议")
                    .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                sectionBadge("恢复提示", tint: Color(hex: "7D8BFF"))
            }

            summaryRow(title: "当前状态", value: hrvInsightText)
            summaryRow(title: "波动解读", value: recoverySummaryText)
            summaryRow(title: "趋势判断", value: recoveryDirectionSummaryText)
            summaryRow(title: "建议安排", value: guideSummaryText)

            Divider()
                .overlay(Theme.Colors.surfaceBorder)

            NavigationLink {
                HRVBaselineNightAnalysisView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.appSystem(size: 15, weight: .bold))
                        .foregroundColor(Self.tint)
                        .frame(width: 38, height: 38)
                        .background(Self.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("查看夜间 HRV 基线")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("对比 7 / 14 / 30 天夜间样本")
                            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 11, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .detailCardSurface(tint: Color(hex: "7D8BFF"))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说明")
                .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(selectedRange == .day ? "这里直接读取健康 App 的 HRV 样本，并按真实采样时间绘制当天变化。" : "这里直接读取健康 App 的 HRV 记录，并按真实有效日绘制所选范围的趋势。")
            Text(selectedRange == .day ? "心率变异性更适合放到睡眠、压力和连续几天的基线里一起看，单一时刻的高低不代表当天恢复全貌。" : "周/月范围下更适合看连续几天的基线有没有整体上移或走低，而不是只盯单日波动。")
            Text(selectedRange == .day ? "页面里的高点、低点、均值和方向判断都基于当天已同步的真实样本计算，不使用虚构占位数据。" : "页面里的均值、波动和方向判断都基于所选范围内已同步的真实记录计算，不使用虚构占位数据。")
            Text(selectedRange == .day ? "如果当天还没有样本，等待 Apple Watch 后台同步后会自动更新。" : "如果这段时间内样本较少，先继续佩戴并等待健康 App 完成同步。")
        }
        .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: appFontScaleLevel))
        .foregroundColor(Theme.Colors.textSecondary)
        .detailCardSurface()
    }

    private func emptyChart(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.appSystem(size: 24, weight: .bold))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(text)
                .font(Theme.Typography.scaled(size: 15, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.secondaryBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func emptyTrendChart(_ text: String) -> some View {
        ZStack {
            Chart(activeHRVPoints) { item in
                PointMark(x: .value("时间", item.date), y: .value("HRV", item.value))
            }
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: yAxisDomain)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                        .foregroundStyle(Color.black.opacity(0.08))
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date))
                                .font(.appSystem(size: 10, weight: .medium))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yAxisMarks) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                        .foregroundStyle(Color.black.opacity(0.08))
                    AxisValueLabel()
                        .font(.appSystem(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(height: 168)

            emptyChart(text)
                .padding(.horizontal, 24)
                .frame(height: 104)
        }
    }

    private var currentValueText: String {
        guard let value = currentHRVValue, value > 0 else { return "—" }
        return String(format: "%.0f", value)
    }

    private var statusText: String {
        guard let value = currentHRVValue, value > 0 else {
            return selectedRange == .day ? "健康 App 同步到新的心率变异性样本后，这里会显示当前结果。" : "健康 App 同步到新的 HRV 记录后，这里会显示这段时间的结果。"
        }
        if value >= 55 { return "恢复状态不错，副交感神经活跃度较好。" }
        if value >= 35 { return "处于常见范围，建议结合你的长期基线看变化。" }
        return String(localized: "近期恢复压力偏高，建议放慢节奏并保证睡眠。")
    }

    private var statusBadgeText: String {
        guard let value = currentHRVValue, value > 0 else { return "等待数据" }
        if value >= 55 { return "恢复不错" }
        if value >= 35 { return "常见范围" }
        return "恢复偏紧"
    }

    private var trendSummaryText: String {
        guard !activeHRVPoints.isEmpty else { return selectedRange == .day ? "等待健康 App 同步今天的心率变异性样本。" : "等待健康 App 同步这段时间的 HRV 趋势。" }
        return selectedRange == .day
            ? "把今天的心率变异性拉成日内曲线，更容易判断什么时候恢复更稳、什么时候负荷更高。"
            : "把这段时间的 HRV 拉成日级趋势，更容易判断恢复基线是在回升、持平还是持续走低。"
    }

    private var samplingWindowText: String {
        guard let first = viewModel.todayHRVPoints.first?.date,
              let last = viewModel.todayHRVPoints.last?.date else {
            return String(localized: "等待同步")
        }
        return "\(axisLabel(for: first)) - \(axisLabel(for: last))"
    }

    private var hrvInsightText: String {
        if let selectedHRVPoint {
            return selectedHRVDescription(for: selectedHRVPoint)
        }
        guard let latest = currentHRVValue, latest > 0 else {
            return String(localized: "没有样本时先不用着急，等待 Apple Watch 后台同步即可。")
        }
        if latest >= 55 {
            return String(localized: "当前心率变异性处在相对更放松的状态，恢复节奏看起来比较稳定。")
        }
        if latest >= 35 {
            return String(localized: "当前结果在常见区间内，更适合和你最近几天的基线一起看变化。")
        }
        return String(localized: "当前心率变异性偏低，通常意味着疲劳、睡眠不足或近期压力负荷更高。")
    }

    private var suggestedActionText: String {
        guard let value = currentHRVValue, value > 0 else {
            return String(localized: "先等待样本同步")
        }
        if value >= 55 { return "维持当前节奏" }
        if value >= 35 { return "继续观察趋势" }
        return "今晚优先恢复"
    }

    private var dayStart: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }

    private var dayEnd: Date {
        if selectedRange == .day {
            return Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        }
        return activeHRVPoints.last?.date ?? (Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60))
    }

    private var chartDomain: ClosedRange<Date> {
        if selectedRange == .day {
            return dayStart...dayEnd
        }
        let interval = selectedRange.visibleDateInterval(anchorDate: selectedDate)
        return interval.start...interval.end
    }

    private var averageHRVValue: Double? {
        let values = activeHRVPoints.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var averageHRVText: String {
        guard let averageHRVValue else { return "暂无" }
        return String(format: "%.0f", averageHRVValue)
    }

    private var yAxisDomain: ClosedRange<Double> {
        let values = activeHRVPoints.map(\.value) + [averageHRVValue].compactMap { $0 }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 20...80
        }
        if abs(maxValue - minValue) < 1 {
            let padding = max(6, maxValue * 0.12)
            return max(0, minValue - padding)...(maxValue + padding)
        }
        let padding = max(6, (maxValue - minValue) * 0.22)
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private var yAxisMarks: [Double] {
        let lower = yAxisDomain.lowerBound
        let upper = yAxisDomain.upperBound
        let step = (upper - lower) / 3
        return [floor(lower), floor(lower + step), floor(lower + step * 2), ceil(upper)]
    }

    private var axisDates: [Date] {
        if selectedRange == .day {
            return [0, 6, 12, 18, 24].compactMap { hour in
                Calendar.current.date(byAdding: .hour, value: hour, to: dayStart)
            }
        }
        let calendar = Calendar.current
        let interval = selectedRange.visibleDateInterval(anchorDate: selectedDate)
        if selectedRange == .week {
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        }
        let days = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30)
        return [0, 7, 14, 21, days - 1].compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func axisLabel(for date: Date) -> String {
        if selectedRange != .day {
            return selectedRange == .week ? ChineseDateText.compactMonthDay(date) : ChineseDateText.compactDay(date)
        }
        if abs(date.timeIntervalSince(dayEnd)) < 1 {
            return "24:00"
        }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var hrvSpreadText: String {
        let values = activeHRVPoints.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return "暂无" }
        return String(format: "%.0f", maxValue - minValue)
    }

    private var latestHRVPoint: TimeSeriesPointDouble? {
        activeHRVPoints.last
    }

    private var peakHRVPoint: TimeSeriesPointDouble? {
        activeHRVPoints.max(by: { $0.value < $1.value })
    }

    private var lowestHRVPoint: TimeSeriesPointDouble? {
        activeHRVPoints.min(by: { $0.value < $1.value })
    }

    private var peakHRVTimeText: String {
        guard let peakHRVPoint else { return "等待样本" }
        return axisLabel(for: peakHRVPoint.date)
    }

    private var lowestHRVTimeText: String {
        guard let lowestHRVPoint else { return "等待样本" }
        return axisLabel(for: lowestHRVPoint.date)
    }

    private var snapshotBadgeText: String {
        if activeHRVPoints.isEmpty { return "等待样本" }
        if let average = averageHRVValue, let latest = currentHRVValue {
            if latest - average >= 6 { return "恢复回升" }
            if average - latest >= 6 { return "恢复偏紧" }
        }
        return String(localized: "节律观察")
    }

    private var latestDeltaText: String {
        guard let average = averageHRVValue,
              let latest = currentHRVValue else {
            return String(localized: "等待样本")
        }
        let delta = Int(abs(latest - average).rounded())
        if latest >= average + 1 {
            return "+\(delta) ms"
        }
        if latest <= average - 1 {
            return "-\(delta) ms"
        }
        return String(localized: "接近均值")
    }

    private var variabilityLevelText: String {
        guard let peak = peakHRVPoint?.value,
              let low = lowestHRVPoint?.value else {
            return String(localized: "等待样本")
        }
        let spread = peak - low
        if spread >= 20 { return "高波动" }
        if spread >= 10 { return "中等波动" }
        return String(localized: "平稳波动")
    }

    private var recoveryDirectionText: String {
        guard activeHRVPoints.count >= 4 else { return "继续观察" }
        let values = activeHRVPoints.map(\.value)
        let splitIndex = values.count / 2
        let firstHalf = Array(values.prefix(splitIndex))
        let secondHalf = Array(values.suffix(values.count - splitIndex))
        guard !firstHalf.isEmpty, !secondHalf.isEmpty else { return "继续观察" }
        let firstAverage = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAverage = secondHalf.reduce(0, +) / Double(secondHalf.count)
        let delta = secondAverage - firstAverage
        if delta >= 5 { return "逐步回升" }
        if delta <= -5 { return "逐步走低" }
        return "整体平稳"
    }

    private var recoveryDirectionSummaryText: String {
        switch recoveryDirectionText {
        case "逐步回升":
            return String(localized: "后半段样本高于前半段，今天后程恢复有回升迹象。")
        case "逐步走低":
            return String(localized: "后半段样本低于前半段，说明今天后程恢复压力在增加。")
        case "整体平稳":
            return String(localized: "前后半段差异不大，今天更像是围绕个人常见区间波动。")
        default:
            return String(localized: "今天样本还不够密集，先继续积累数据再判断方向。")
        }
    }

    private var recoverySummaryText: String {
        guard !activeHRVPoints.isEmpty else {
            return selectedRange == .day ? "今天还没有同步到心率变异性样本，等手表完成后台同步后，这里会开始形成恢复轮廓。" : "这段时间还没有同步到足够的 HRV 记录，等手表完成后台同步后，这里会开始形成恢复轮廓。"
        }
        guard let average = averageHRVValue,
              let peakHRVPoint,
              let lowestHRVPoint else {
            return String(localized: "今天已有样本，但还需要更多数据点，才能更稳定地判断恢复节律。")
        }

        let peakText = axisLabel(for: peakHRVPoint.date)
        let lowText = axisLabel(for: lowestHRVPoint.date)
        let spread = Int((peakHRVPoint.value - lowestHRVPoint.value).rounded())

        if spread >= 18 {
            return String(localized: "今天的波动幅度约 \(spread) ms，\(peakText) 附近更放松，\(lowText) 附近更偏紧，说明恢复状态在日内拉开了明显差距，建议结合那一段的活动、压力或进食情况一起看。")
        }

        if let latest = currentHRVValue, latest >= average + 6 {
            return String(localized: "最新样本高于日内均值，说明恢复状态有回升迹象；如果晚间还能维持，通常是不错的节律信号。")
        }

        if let latest = currentHRVValue, latest <= average - 6 {
            return String(localized: "最新样本低于日内均值，说明此刻恢复偏紧；今晚更适合把睡眠、放松和负荷控制放在前面。")
        }

        return String(localized: "今天的心率变异性围绕日内均值附近波动，峰谷差约 \(spread) ms，整体节律相对平稳。")
    }

    private var guideSummaryText: String {
        guard let latest = currentHRVValue, latest > 0 else {
            return String(localized: "先等待样本同步，再把今天的变化和睡眠、压力页面放在一起看。")
        }
        if recoveryDirectionText == "逐步走低" {
            return String(localized: "今天后半段恢复在走低，晚间更适合降低刺激、减少额外训练负荷，并优先保证入睡质量。")
        }
        if recoveryDirectionText == "逐步回升" {
            return String(localized: "今天后半段恢复在回升，适合维持节奏，但仍建议避免把晚间状态继续透支掉。")
        }
        if latest >= 55 {
            return String(localized: "恢复状态相对不错，今天更适合维持现有节奏，避免不必要的熬夜和额外透支。")
        }
        if latest >= 35 {
            return String(localized: "当前处在常见区间，建议继续观察晚间变化，再结合睡眠和压力一起判断。")
        }
        return String(localized: "恢复偏紧时优先保证睡眠、减少刺激和高负荷安排，让身体先把节律拉回稳定区间。")
    }

    private var selectedHRVPoint: TimeSeriesPointDouble? {
        guard let selectedHRVTimestamp else { return nil }
        return activeHRVPoints.first(where: { abs($0.date.timeIntervalSince(selectedHRVTimestamp)) < 1 })
    }

    private var hrvGlowColor: Color {
        if let latest = viewModel.latestHRV {
            return hrvLineColor(for: latest)
        }
        return Self.tint
    }

    private var hrvLineGradient: LinearGradient {
        LinearGradient(colors: hrvGradientStops, startPoint: .leading, endPoint: .trailing)
    }

    private var hrvGradientStops: [Color] {
        let values = activeHRVPoints.map(\.value)
        guard !values.isEmpty else {
            return [Color(hex: "3AAE9B"), Color(hex: "6D7EF7")]
        }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        if abs(maxValue - minValue) < 1 {
            let color = hrvLineColor(for: maxValue)
            return [color.opacity(0.88), color]
        }

        let midValue = values.reduce(0, +) / Double(values.count)
        return [hrvLineColor(for: minValue), hrvLineColor(for: midValue), hrvLineColor(for: maxValue)]
    }

    private var hrvBands: [HRVBand] {
        let lower = yAxisDomain.lowerBound
        let upper = yAxisDomain.upperBound
        let mid = averageHRVValue ?? ((lower + upper) / 2)
        let lowerBand = max(lower, mid - 8)
        let upperBand = min(upper, mid + 8)
        return [
            HRVBand(id: "lower", lowerBound: lower, upperBound: lowerBand, color: Color(hex: "DCE6FF")),
            HRVBand(id: "middle", lowerBound: lowerBand, upperBound: upperBand, color: Color(hex: "DDF5EC")),
            HRVBand(id: "upper", lowerBound: upperBand, upperBound: upper, color: Color(hex: "EAF8F2"))
        ]
    }

    private var lowerRecoveryThreshold: Double? {
        guard let averageHRVValue else { return nil }
        return max(yAxisDomain.lowerBound, averageHRVValue - 8)
    }

    private var upperRecoveryThreshold: Double? {
        guard let averageHRVValue else { return nil }
        return min(yAxisDomain.upperBound, averageHRVValue + 8)
    }

    private var smoothedHRVPoints: [HRVSmoothedPoint] {
        let points = activeHRVPoints
        guard points.count >= 3 else {
            return points.map { HRVSmoothedPoint(id: $0.date, date: $0.date, value: $0.value) }
        }

        return points.enumerated().map { index, point in
            let start = max(0, index - 1)
            let end = min(points.count - 1, index + 1)
            let window = points[start...end].map(\.value)
            let average = window.reduce(0, +) / Double(window.count)
            return HRVSmoothedPoint(id: point.date, date: point.date, value: average)
        }
    }

    private func updateHRVSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else {
            selectedHRVTimestamp = nil
            return
        }
        let xPosition = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        selectedHRVTimestamp = nearestHRVPoint(to: date)?.date
    }

    private func nearestHRVPoint(to date: Date) -> TimeSeriesPointDouble? {
        activeHRVPoints.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    private func selectedHRVDetailCard(for point: TimeSeriesPointDouble) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(axisLabel(for: point.date))
                    .font(Theme.Typography.scaled(size: 13, weight: .bold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("\(Int(point.value.rounded())) ms")
                    .font(Theme.Typography.scaled(size: 18, weight: .heavy, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(hrvLineColor(for: point.value))
            }

            if let average = averageHRVValue {
                Text(deltaDescription(for: point.value - average))
                    .font(Theme.Typography.scaled(size: 11, weight: .bold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(hrvLineColor(for: point.value))
            }

            HStack(spacing: 10) {
                selectionStatPill(title: "区间", value: recoveryBandTitle(for: point.value))
                selectionStatPill(title: "位置", value: rankingDescription(for: point))
            }

            Text(selectedHRVDescription(for: point))
                .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func selectedHRVDescription(for point: TimeSeriesPointDouble) -> String {
        let timeText = axisLabel(for: point.date)
        if let average = averageHRVValue {
            let delta = point.value - average
            if delta >= 6 {
                return String(localized: "\(timeText) 这一笔心率变异性高于日内均值，通常说明这段恢复状态更放松。")
            }
            if delta <= -6 {
                return String(localized: "\(timeText) 这一笔心率变异性低于日内均值，可能更接近疲劳、压力或恢复偏紧的时段。")
            }
        }
        return String(localized: "\(timeText) 这一笔心率变异性接近日内常见水平，整体节律相对平稳。")
    }

    private func deltaDescription(for delta: Double) -> String {
        let rounded = Int(abs(delta).rounded())
        if delta >= 1 {
            return String(localized: "较日内均值高 \(rounded) ms")
        }
        if delta <= -1 {
            return String(localized: "较日内均值低 \(rounded) ms")
        }
        return String(localized: "与日内均值基本持平")
    }

    private func hrvLineColor(for value: Double) -> Color {
        if let average = averageHRVValue {
            let delta = value - average
            if delta >= 6 { return Color(hex: "33B58F") }
            if delta <= -6 { return Color(hex: "6D7EF7") }
            return Color(hex: "57B8B0")
        }
        if value >= 55 { return Color(hex: "33B58F") }
        if value >= 35 { return Color(hex: "57B8B0") }
        return Color(hex: "6D7EF7")
    }

    private func recoveryBandTitle(for value: Double) -> String {
        if let upperRecoveryThreshold, value >= upperRecoveryThreshold { return "恢复较好" }
        if let lowerRecoveryThreshold, value <= lowerRecoveryThreshold { return "恢复偏紧" }
        return String(localized: "常见区间")
    }

    private func rankingDescription(for point: TimeSeriesPointDouble) -> String {
        let sorted = activeHRVPoints.sorted(by: { $0.value > $1.value })
        guard let index = sorted.firstIndex(where: { $0.id == point.id }) else { return "等待排序" }
        return String(localized: "第 \(index + 1) / \(sorted.count) 位")
    }

    private var activeHRVPoints: [TimeSeriesPointDouble] {
        selectedRange == .day ? viewModel.todayHRVPoints : aggregatedHRVPoints
    }

    private var currentHRVValue: Double? {
        if selectedRange == .day {
            return viewModel.latestHRV
        }
        return activeHRVPoints.last?.value
    }

    @MainActor
    private func reloadRangeData() async {
        let requestID = UUID()
        loadRequestID = requestID
        isTrendLoading = true
        defer {
            if loadRequestID == requestID {
                isTrendLoading = false
            }
        }
        guard selectedRange != .day else {
            let points: [TimeSeriesPointDouble]
            if Calendar.current.isDateInToday(selectedDate) {
                points = (try? await HealthKitManager.shared.fetchTodayHRVSamples()) ?? []
            } else {
                points = (try? await HealthKitManager.shared.fetchHRVSamples(on: selectedDate)) ?? []
            }
            guard loadRequestID == requestID else { return }
            viewModel.todayHRVPoints = points
            viewModel.latestHRV = points.last?.value
            viewModel.measuredAt = points.last?.date
            selectedHRVTimestamp = activeHRVPoints.last?.date
            return
        }
        let days = selectedRange == .week ? 7 : 31
        let queryEnd = selectedRange.queryEndDate(anchorDate: selectedDate)
        let loaded = (try? await HealthKitManager.shared.fetchDailyHRVAverages(days: days, endDate: queryEnd)) ?? []
        guard loadRequestID == requestID else { return }
        aggregatedHRVPoints = loaded
            .filter { selectedRange.contains($0.date, anchorDate: selectedDate) }
            .sorted { $0.timestamp < $1.timestamp }
        selectedHRVTimestamp = activeHRVPoints.last?.date
    }

    private var hrvChartLegendRow: some View {
        HStack(spacing: 10) {
            chartLegendPill(color: hrvLineColor(for: averageHRVValue ?? (latestHRVPoint?.value ?? 45)), label: "实时 HRV 曲线")
            chartLegendPill(stroke: Color(hex: "11233F").opacity(0.38), label: "平滑节律线")
            chartLegendPill(stroke: Color(hex: "1F7A6B").opacity(0.38), label: "日内均值")
        }
    }

    private func chartLegendPill(color: Color? = nil, stroke: Color = .clear, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color ?? .clear)
                .overlay {
                    if color == nil {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(stroke, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }
                }
                .frame(width: 18, height: 8)

            Text(label)
                .font(Theme.Typography.scaled(size: 10, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.Colors.surface.opacity(0.74), in: Capsule())
    }

    private func chartCalloutBadge(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(tint)
            Text(value)
                .font(.appSystem(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
    }

    private func selectionStatPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Typography.scaled(size: 10, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 12, weight: .heavy, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func overviewPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Typography.scaled(size: 11, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 14, weight: .black, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chartMetricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.Typography.scaled(size: 10, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 15, weight: .black, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.scaled(size: 13, weight: .semibold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func sectionBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.Typography.scaled(size: 10, weight: .heavy, design: .rounded, level: appFontScaleLevel))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func contextTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.Typography.scaled(size: 11, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 14, weight: .black, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    func detailCardSurface(tint: Color? = nil) -> some View {
        self
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.96), tint?.opacity(0.05) ?? Color.white.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
    }
}

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}
