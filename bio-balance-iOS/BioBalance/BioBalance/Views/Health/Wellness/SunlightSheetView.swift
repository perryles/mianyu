/// SunlightSheetView 由每日打卡日照入口调用，作为「日照记录」弹层。
/// 负责按天/周/月展示日照时长趋势，并关联天气与位置信息。

import SwiftUI
import Charts
import CoreLocation
import WeatherKit
import UIKit

/// 日照视图 由上级页面或路由调用，作为习惯模块里的界面或内容组件。
/// 负责展示行为打卡、日常记录与习惯分析内容。
struct SunlightSheetView: View {
    /// Range 枚举，作为内部辅助类型，用于细分外层习惯记录与分析中的状态或分支。
    enum Range: String, CaseIterable, Identifiable {
        case day = "天"
        case week = "周"
        case month = "月"

        var id: String { rawValue }

        /// 本地化标题：rawValue 仅作标识，UI 展示走 String Catalog。
        var displayName: String {
            switch self {
            case .day: return String(localized: "天")
            case .week: return String(localized: "周")
            case .month: return String(localized: "月")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var viewModel = SunlightSheetViewModel()
    @State private var selectedRange: Range = .day
    @State private var selectedDate: Date
    @State private var selectedBarTime: Date?
    @State private var showingReminderSettings = false
    let showsDismissButton: Bool

    private let topAnchorID = "sunlight-sheet-top"
    private static let tint = Color(hex: "F4A259")
    private static let accent = Color(hex: "FFD36F")

    init(initialDate: Date = Date(), showsDismissButton: Bool = false) {
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
        self.showsDismissButton = showsDismissButton
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.secondaryBackground
                    .ignoresSafeArea()
                ambientBackground

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            Color.clear
                                .frame(height: 0)
                                .id(topAnchorID)
                            headerCard
                            outdoorAdviceCard
                            rhythmCard
                            trendCard
                            guidanceCard
                            noteCard
                            weatherAttributionCard
                            metricDisclaimerCard
                        }
                        .padding(Theme.Layout.padding)
                        .padding(.bottom, 24)
                    }
                    .onAppear {
                        proxy.scrollTo(topAnchorID, anchor: .top)
                    }
                }
            }
            .navigationTitle("晒太阳")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await reloadData()
            }
            .onChange(of: selectedRange) { _, _ in
                selectedBarTime = nil
                Task { await reloadData() }
            }
            .onChange(of: selectedDate) { _, _ in
                selectedBarTime = nil
                Task { await reloadData() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showsDismissButton {
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
                    MetricReminderSettingsView(metricKey: "sunlight", metricTitle: "日照")
                }
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
            }
        }
    }

    /// WeatherKit 归因卡片（满足 App Store 审核指南 5.2.5 对 Apple Weather 数据来源标注的要求）。
    private var weatherAttributionCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "cloud.sun")
                .font(.appSystem(size: 18, weight: .bold))
                .foregroundColor(Theme.Colors.textTertiary)

            VStack(alignment: .leading, spacing: 3) {
                Text("Apple Weather")
                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Button {
                    openURL(URL(string: "https://apple.com/legal/weather/data/")!)
                } label: {
                    Text("天气数据由 Apple Weather 提供")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .underline()
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Colors.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 0.5)
        )
    }

    private var metricDisclaimerCard: some View {
        HealthDisclaimerCard(
            message: "本页自然光暴露数据、趋势和建议仅供日常自我管理参考，不构成医疗诊断或治疗建议。若身体不适或需要做出重要健康决定，请咨询专业医生。",
            strokeColor: Self.tint.opacity(0.14)
        )
    }

    private var ambientBackground: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Self.tint.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .blur(radius: 28)
                    .offset(x: -42, y: -38)
                Spacer()
                Circle()
                    .fill(Self.accent.opacity(0.22))
                    .frame(width: 150, height: 150)
                    .blur(radius: 28)
                    .offset(x: 30, y: -20)
            }
            Spacer()
        }
        .ignoresSafeArea()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("自然光暴露")
                        .font(.appSystem(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(rangeDescription)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Self.tint)
                } else {
                    Text(statusText)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(statusTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(statusTint.opacity(0.12), in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(summary.displayMinutes.rounded()))")
                    .font(.appSystem(size: 52, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("分钟")
                    .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            HStack(spacing: 10) {
                metricPill(title: "目标", value: "\(Int(completionRate * 100))", unit: "%")
                metricPill(title: "晨间", value: "\(Int(summary.morningMinutes.rounded()))", unit: "分钟")
                metricPill(title: "午后", value: "\(Int(summary.afternoonMinutes.rounded()))", unit: "分钟")
            }

            Picker("", selection: $selectedRange) {
                ForEach(Range.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    shiftDate(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.surface.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("前一天")

                Spacer()

                Text(dateTitle)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button {
                    shiftDate(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(canMoveForward ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.surface.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
                .accessibilityLabel("后一天")
            }
        }
        .glassCard()
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("光照节律")
                        .font(.appSystem(size: 20, weight: .bold, design: .serif))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(viewModel.errorMessage ?? "这里会直接读取健康 App 的自然光暴露记录。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(remainingText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Self.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Self.tint.opacity(0.10), in: Capsule())
            }

            HStack(alignment: .center, spacing: 14) {
                progressRing

                VStack(alignment: .leading, spacing: 8) {
                    Text(insightText)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        infoTag(title: "主要时段", value: bestWindowText)
                        infoTag(title: "趋势对比", value: totalChangeText)
                    }
                }
            }

            HStack(spacing: 8) {
                infoTag(title: highlightPrimaryTitle, value: highlightPrimaryText)
                infoTag(title: highlightSecondaryTitle, value: highlightSecondaryText)
            }
        }
        .glassCard()
    }

    private var outdoorAdviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("外出建议")
                        .font(.appSystem(size: 20, weight: .bold, design: .serif))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(outdoorAdviceIntroText)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(outdoorAdviceBadgeText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(outdoorAdviceBadgeTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(outdoorAdviceBadgeTint.opacity(0.12), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "location")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(viewModel.outdoorContext.locationName)
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                outdoorGaugeCard

                HStack(spacing: 12) {
                    outdoorMetricBlock(title: "最高", value: outdoorPeakUVText)
                    Spacer()
                    outdoorMetricBlock(title: "黄金时段", value: viewModel.outdoorContext.bestExposureWindowText, alignment: .trailing)
                }
                .padding(.horizontal, 6)

                if viewModel.outdoorContext.showsSettingsAction {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                            Text("去设置开启定位")
                        }
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Self.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 10) {
                adviceRow(
                    icon: "sun.max.fill",
                    tint: Self.tint,
                    title: "优先安排",
                    detail: outdoorAdvicePrimaryRow
                )
                adviceRow(
                    icon: "timer",
                    tint: Color(hex: "E98B4A"),
                    title: "建议时长",
                    detail: outdoorAdviceDurationRow
                )
                adviceRow(
                    icon: "checkmark.shield",
                    tint: Theme.Colors.mintGreen,
                    title: "节律提醒",
                    detail: outdoorAdviceCautionRow
                )
            }
        }
        .glassCard()
    }

    private var outdoorGaugeCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.86),
                            Color(hex: "FFF8EE").opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                ZStack {
                    outdoorGaugeArc
                        .frame(height: 138)

                    VStack(spacing: 4) {
                        Text("当前")
                            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text(outdoorCurrentUVText)
                            .font(.appSystem(size: 44, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.outdoorContext.weatherSymbolName)
                                .font(.appSystem(size: 15, weight: .semibold))
                            Text("\(viewModel.outdoorContext.currentConditionDescription) / \(viewModel.outdoorContext.currentTemperatureText)")
                                .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .offset(y: 18)
                }

                HStack {
                    Label(viewModel.outdoorContext.sunriseText, systemImage: "sunrise.fill")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer()
                    Text(viewModel.outdoorContext.statusLabel)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(outdoorStatusTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(outdoorStatusTint.opacity(0.12), in: Capsule())
                    Spacer()
                    Label(viewModel.outdoorContext.sunsetText, systemImage: "sunset.fill")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, 2)
            }
            .padding(18)
        }
    }

    private var outdoorGaugeArc: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let radius = min(width / 2.1, height * 1.28)
            let center = CGPoint(x: width / 2, y: height)
            let progress = viewModel.outdoorContext.gaugeProgress
            let endAngle = Angle(degrees: 180 - (180 * progress))

            ZStack {
                SunlightGaugeArc(startAngle: .degrees(180), endAngle: .degrees(0))
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "6AA7E8"),
                                Color(hex: "EAB55B"),
                                Color(hex: "7FB0E7")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .opacity(0.32)

                SunlightGaugeArc(startAngle: .degrees(180), endAngle: endAngle)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "6AA7E8"),
                                Color(hex: "F1B64D")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )

                ForEach(0..<20, id: \.self) { index in
                    let dotAngle = Double(index) / 19.0 * 180.0
                    Circle()
                        .fill(Color.white.opacity(0.68))
                        .frame(width: 4, height: 4)
                        .position(
                            x: center.x + cos((180 - dotAngle) * .pi / 180) * (radius - 1),
                            y: center.y - sin((180 - dotAngle) * .pi / 180) * (radius - 1)
                        )
                }

                if progress > 0.001 {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 38, height: 38)
                        .overlay {
                            Circle()
                                .stroke(Color(hex: "F0BE64"), lineWidth: 4)
                            Text(viewModel.outdoorContext.currentUVIndex.map(String.init) ?? "--")
                                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(hex: "D3862F"))
                        }
                        .position(
                            x: center.x + cos(endAngle.radians) * radius,
                            y: center.y + sin(endAngle.radians) * radius
                        )
                }
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Self.tint.opacity(0.14), lineWidth: 12)
            Circle()
                .trim(from: 0, to: completionRate)
                .stroke(
                    LinearGradient(
                        colors: [Self.tint, Self.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 106, height: 106)
        .overlay {
            VStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(Self.tint)
                Text(localizedPercentRatio(completionRate))
                    .font(.appSystem(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("完成度")
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trendTitle)
                    .font(.appSystem(.headline, design: .default))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(trendSubtitle)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            if chartBars.isEmpty {
                emptyTrendChart
            } else {
                HStack(spacing: 8) {
                    metricPill(title: summaryMetricTitle, value: "\(Int(summary.displayMinutes.rounded()))", unit: "分钟")
                    metricPill(title: peakMetricTitle, value: "\(Int(summary.peakValue.rounded()))", unit: "分钟")
                    metricPill(title: activeMetricTitle, value: "\(summary.activeBucketCount)", unit: activeMetricUnit)
                }

                Chart(chartBars) { item in
                    BarMark(
                        x: .value("时间", item.time),
                        y: .value("分钟", item.value)
                    )
                    .foregroundStyle(sunlightBarGradient(for: item))
                    .opacity(selectedBar == nil || selectedBar?.id == item.id ? 1 : 0.42)
                    .cornerRadius(5)

                    if let target = targetBarReferenceValue {
                        RuleMark(y: .value("参考", target))
                            .foregroundStyle(Self.tint.opacity(0.30))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text(targetReferenceText)
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Self.tint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                            }
                    }

                    if item.id == summary.peakBar.id, item.value > 0 {
                        PointMark(
                            x: .value("时间", item.time),
                            y: .value("分钟", item.value)
                        )
                        .symbolSize(64)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .annotation(position: .top) {
                            Text("峰值 \(Int(item.value.rounded()))")
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                        }
                    }
                }
                .frame(height: 210)
                .chartLegend(.hidden)
                .chartXScale(domain: xAxisDomain)
                .chartYScale(domain: 0...yAxisUpperBound)
                .chartPlotStyle { plotArea in
                    plotArea.padding(.bottom, 8)
                }
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
                                                let location = drag.location
                                                guard frame.contains(location) else { return }
                                                let xPosition = location.x - frame.origin.x
                                                guard let date: Date = proxy.value(atX: xPosition) else { return }
                                                selectedBarTime = nearestBar(to: date)?.time
                                            default:
                                                break
                                            }
                                        }
                                        .onEnded { value in
                                            switch value {
                                            case .second(true, let drag):
                                                if let drag {
                                                    let location = drag.location
                                                    guard frame.contains(location) else {
                                                        selectedBarTime = nil
                                                        return
                                                    }
                                                    let xPosition = location.x - frame.origin.x
                                                    guard let date: Date = proxy.value(atX: xPosition) else { return }
                                                    selectedBarTime = nearestBar(to: date)?.time
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
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisMarks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text("\(Int(amount.rounded()))")
                            }
                        }
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xAxisMarks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                            }
                        }
                        .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                Text(chartInsightText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let selectedBar {
                    selectedBarDetailCard(for: selectedBar)
                }
            }
        }
        .glassCard()
    }

    private var emptyTrendChart: some View {
        ZStack {
            Chart(chartBars) { item in
                BarMark(
                    x: .value("时间", item.time),
                    y: .value("分钟", item.value)
                )
            }
            .frame(height: 210)
            .chartLegend(.hidden)
            .chartXScale(domain: xAxisDomain)
            .chartYScale(domain: 0...yAxisUpperBound)
            .chartYAxis {
                AxisMarks(position: .leading, values: yAxisMarks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text("\(Int(amount.rounded()))")
                        }
                    }
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisMarks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date))
                        }
                    }
                    .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            VStack(spacing: 10) {
                Text(viewModel.errorMessage ?? "暂无自然光记录")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                Button {
                    Task { await reloadData() }
                } label: {
                    Text("重新读取")
                        .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.textPrimary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Theme.Colors.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("建议")
                .font(.appSystem(.headline, design: .default))
                .foregroundColor(Theme.Colors.textPrimary)

            summaryRow(title: "当前状态", value: statusText)
            summaryRow(title: "推荐安排", value: bestWindowDescription)
            summaryRow(title: "节律提示", value: rhythmHintText)
        }
        .glassCard()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(.appSystem(.headline, design: .default))
                .foregroundColor(Theme.Colors.textPrimary)
            Text("这里展示的是健康 App 的自然光暴露（Time in Daylight）数据，不再使用模拟样本。")
            Text("如果当前设备系统版本、权限或健康记录不支持这项数据，页面会显示为空。")
        }
        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
        .foregroundColor(Theme.Colors.textSecondary)
        .glassCard()
    }

    private func metricPill(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(unit)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Self.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func adviceTag(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.appSystem(size: 11, weight: .bold))
            Text(text)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(Theme.Colors.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface.opacity(0.72), in: Capsule())
    }

    private func outdoorMetricBlock(title: String, value: String, alignment: Alignment = .leading) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(value)
                .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func adviceRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.appSystem(size: 14, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.appSystem(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var summary: SunlightSummary {
        SunlightSummary.make(
            range: selectedRange,
            anchorDate: selectedDate,
            currentPoints: viewModel.currentPoints,
            previousPoints: viewModel.previousPoints
        )
    }

    private var chartBars: [SunlightBarPoint] {
        summary.barPoints
    }

    private var selectedBar: SunlightBarPoint? {
        if let selectedBarTime,
           let exact = chartBars.first(where: { abs($0.time.timeIntervalSince(selectedBarTime)) < 1 }) {
            return exact
        }
        return nil
    }

    private var trendSubtitle: String {
        switch selectedRange {
        case .day:
            return String(localized: "按小时查看当天真实自然光暴露分钟数，观察光照是否更多落在上午。")
        case .week:
            return String(localized: "按天查看本周真实自然光暴露分钟数，并和日目标参考线对照。")
        case .month:
            return String(localized: "按天查看本月真实自然光暴露分钟数，观察哪些日期更稳定接近日目标。")
        }
    }

    private var completionRate: Double {
        min(1, summary.displayMinutes / targetMinutes)
    }

    private var targetMinutes: Double {
        switch selectedRange {
        case .day:
            return 20
        case .week:
            return 20 * 7
        case .month:
            let month = Calendar.current.dateInterval(of: .month, for: selectedDate)
            let days = month.map { Calendar.current.dateComponents([.day], from: $0.start, to: $0.end).day ?? 30 } ?? 30
            return 20 * Double(max(1, days))
        }
    }

    private var completionRatio: Double {
        guard targetMinutes > 0 else { return 0 }
        return summary.displayMinutes / targetMinutes
    }

    private var statusText: String {
        switch completionRatio {
        case 1...:
            return String(localized: "已达标")
        case 0.6..<1:
            return String(localized: "补充中")
        case ...0:
            return String(localized: "暂无记录")
        default:
            return String(localized: "待补足")
        }
    }

    private var statusTint: Color {
        completionRatio >= 1 ? Theme.Colors.mintGreen : Self.tint
    }

    private var remainingText: String {
        let remaining = max(0, Int(ceil(targetMinutes - summary.displayMinutes)))
        switch selectedRange {
        case .day:
            return remaining == 0 ? "今日目标完成" : "还差 \(remaining) 分钟"
        case .week:
            return remaining == 0 ? "本周目标完成" : "本周还差 \(remaining) 分钟"
        case .month:
            return remaining == 0 ? "本月目标完成" : "本月还差 \(remaining) 分钟"
        }
    }

    private var bestWindowText: String {
        summary.morningMinutes >= summary.afternoonMinutes ? "上午更集中" : "午后更多"
    }

    private var highlightPrimaryTitle: String {
        switch selectedRange {
        case .day:
            return String(localized: "峰值时段")
        case .week:
            return String(localized: "最佳暴露日")
        case .month:
            return String(localized: "最佳暴露日")
        }
    }

    private var highlightPrimaryText: String {
        switch selectedRange {
        case .day:
            return String(localized: "\(axisLabel(for: summary.peakBar.time)) · \(Int(summary.peakValue.rounded())) 分钟")
        case .week, .month:
            return String(localized: "\(axisLabel(for: summary.peakBar.time)) · \(Int(summary.peakValue.rounded())) 分钟")
        }
    }

    private var highlightSecondaryTitle: String {
        switch selectedRange {
        case .day:
            return String(localized: "节律重心")
        case .week:
            return String(localized: "稳定程度")
        case .month:
            return String(localized: "稳定程度")
        }
    }

    private var highlightSecondaryText: String {
        switch selectedRange {
        case .day:
            return summary.morningMinutes >= summary.afternoonMinutes ? String(localized: "偏上午") : String(localized: "偏午后")
        case .week, .month:
            return stabilityText
        }
    }

    private var stabilityText: String {
        let active = summary.activeBucketCount
        switch selectedRange {
        case .day:
            return "--"
        case .week:
            if active >= 5 { return String(localized: "较稳定") }
            if active >= 3 { return String(localized: "有起伏") }
            return String(localized: "偏零散")
        case .month:
            if active >= 18 { return String(localized: "较稳定") }
            if active >= 10 { return String(localized: "有起伏") }
            return String(localized: "偏零散")
        }
    }

    private var summaryMetricTitle: String {
        switch selectedRange {
        case .day: return String(localized: "累计")
        case .week: return String(localized: "本周累计")
        case .month: return String(localized: "本月累计")
        }
    }

    private var peakMetricTitle: String {
        switch selectedRange {
        case .day: return String(localized: "峰值小时")
        case .week: return String(localized: "单日峰值")
        case .month: return String(localized: "单日峰值")
        }
    }

    private var activeMetricTitle: String {
        switch selectedRange {
        case .day: return String(localized: "有效时段")
        case .week: return String(localized: "活跃天数")
        case .month: return String(localized: "活跃天数")
        }
    }

    private var activeMetricUnit: String {
        selectedRange == .day ? "个" : "天"
    }

    private var targetBarReferenceValue: Double? {
        switch selectedRange {
        case .day:
            return nil
        case .week, .month:
            return 20
        }
    }

    private var targetReferenceText: String {
        selectedRange == .week ? "日目标 20 分钟" : "参考 20 分钟"
    }

    private var totalChangeText: String {
        guard let comparison = summary.previousComparableMinutes, comparison > 0 else {
            return String(localized: "暂无对比")
        }
        let delta = ((summary.displayMinutes - comparison) / comparison) * 100
        let prefix = delta >= 0 ? "+" : ""
        return "\(prefix)\(Int(delta.rounded()))%"
    }

    private var insightText: String {
        if completionRatio >= 1 {
            return String(localized: "当前范围内的自然光暴露已经达到建议值，继续保持白天规律暴露就很好。")
        }
        if summary.displayMinutes == 0 {
            return String(localized: "当前范围内还没有读到有效自然光记录，先确认健康数据已经同步。")
        }
        return String(localized: "当前自然光暴露还可以再补一点，优先放在上午通常会更有利于白天清醒。")
    }

    private var bestWindowDescription: String {
        switch selectedRange {
        case .day:
            return summary.morningMinutes >= summary.afternoonMinutes
                ? "当前自然光更多落在上午，节律方向是对的。"
                : "可以把一部分自然光暴露前移到上午，会更接近理想节律。"
        case .week, .month:
            return String(localized: "\(highlightPrimaryText) 是当前范围内暴露最多的一段记录，可参考那天的外出节奏继续复用。")
        }
    }

    private var rhythmHintText: String {
        if summary.displayMinutes == 0 {
            return String(localized: "没有有效记录时，趋势判断会先暂停。")
        }
        return summary.morningMinutes >= summary.afternoonMinutes
            ? "晨间暴露占比更高，这通常对稳定生物钟更友好。"
            : "午后暴露偏多，可以尝试把一部分时长前移到上午。"
    }

    private var outdoorAdviceIntroText: String {
        switch selectedRange {
        case .day:
            return isSelectedDateToday
                ? "结合今天已经读到的自然光暴露，给你一个更容易执行的外出安排。"
                : "基于这一天的自然光记录，回看什么样的外出节奏会更合适。"
        case .week:
            return String(localized: "按本周的日照节律，帮你找一个更容易延续的外出策略。")
        case .month:
            return String(localized: "按本月的日照习惯，给出更稳妥的外出补光方向。")
        }
    }

    private var outdoorAdviceBadgeText: String {
        switch selectedRange {
        case .day:
            if summary.displayMinutes <= 0 { return String(localized: "等待开始") }
            if completionRatio >= 1 { return String(localized: "今天已够") }
            return String(localized: "还能补一点")
        case .week:
            return summary.activeBucketCount >= 5 ? String(localized: "节奏不错") : String(localized: "建议加频次")
        case .month:
            return summary.activeBucketCount >= 18 ? String(localized: "习惯成形") : String(localized: "继续稳定")
        }
    }

    private var outdoorAdviceBadgeTint: Color {
        switch outdoorAdviceBadgeText {
        case "今天已够", "节奏不错", "习惯成形":
            return Theme.Colors.mintGreen
        default:
            return Self.tint
        }
    }

    private var outdoorAdviceHeadline: String {
        switch selectedRange {
        case .day:
            if completionRatio >= 1 {
                return isSelectedDateToday
                    ? "今天日照已经达标，保持白天正常出门就可以。"
                    : "这一天的日照已经达标，节奏可以继续复用。"
            }
            if summary.displayMinutes == 0 {
                return isSelectedDateToday
                    ? "今天还没读到有效日照，建议尽快安排一次短外出。"
                    : "这一天没有读到有效日照，适合补一段上午外出。"
            }
            if selectedDateHour < 11 {
                return String(localized: "现在更适合把外出放在上午，先补一段自然光。")
            }
            if selectedDateHour < 16 {
                return String(localized: "中午到午后可以补足缺口，安排一次短走动最合适。")
            }
            return String(localized: "今天剩余窗口不多了，补一点也比完全错过更好。")
        case .week:
            if summary.activeBucketCount >= 5 {
                return String(localized: "本周外出节律已经比较稳，重点是把好习惯固定在工作日。")
            }
            return String(localized: "本周日照分布还偏零散，优先增加固定的白天外出频次。")
        case .month:
            if summary.activeBucketCount >= 18 {
                return String(localized: "本月已经形成一定规律，继续保持上午优先会更稳。")
            }
            return String(localized: "本月外出补光还不够稳定，先把可重复的小窗口固定下来。")
        }
    }

    private var outdoorAdviceSupportingText: String {
        viewModel.outdoorContext.recommendationDetail
    }

    private var outdoorAdviceWindowTag: String {
        switch selectedRange {
        case .day:
            return viewModel.outdoorContext.bestExposureWindowText
        case .week:
            return summary.morningMinutes >= summary.afternoonMinutes ? String(localized: "继续保留上午时段") : String(localized: "优先把外出前移")
        case .month:
            return summary.morningMinutes >= summary.afternoonMinutes ? String(localized: "维持晨间见光") : String(localized: "增加上午见光")
        }
    }

    private var outdoorAdviceActionTag: String {
        switch selectedRange {
        case .day:
            return viewModel.outdoorContext.statusLabel
        case .week:
            return String(localized: "先保频次再拉时长")
        case .month:
            return String(localized: "建立固定外出点")
        }
    }

    private var outdoorAdvicePrimaryRow: String {
        switch selectedRange {
        case .day:
            return viewModel.outdoorContext.recommendationHeadline
        case .week:
            return String(localized: "参考 \(highlightPrimaryText) 这天的节奏，优先在工作日固定一个白天出门时间。")
        case .month:
            return String(localized: "把外出安排绑定到稳定场景里，比如早餐后、午饭后或通勤中多走一段。")
        }
    }

    private var outdoorAdviceDurationRow: String {
        switch selectedRange {
        case .day:
            if completionRatio >= 1 {
                return String(localized: "今天以维持节律为主，不需要刻意追求更久时长。")
            }
            return String(localized: "建议再补 \(remainingSunlightMinutesText)，也可以拆成 10 分钟到 15 分钟的小段来完成。")
        case .week:
            return String(localized: "本周先争取把更多天拉到 15 到 20 分钟，再考虑继续增加时长。")
        case .month:
            return String(localized: "本月先追求多数天都有暴露，再把单日时长逐步稳定到 20 分钟附近。")
        }
    }

    private var outdoorAdviceCautionRow: String {
        switch selectedRange {
        case .day:
            return viewModel.outdoorContext.cautionText
        case .week:
            return String(localized: "连续几天都有白天见光，通常比周末一次性补很多更容易长期坚持。")
        case .month:
            return String(localized: "想让节律更稳，关键是减少长时间完全不见自然光的日子。")
        }
    }

    private var outdoorCurrentUVText: String {
        if let value = viewModel.outdoorContext.currentUVIndex {
            return "UV \(value)"
        }
        return "UV --"
    }

    private var outdoorPeakUVText: String {
        if let value = viewModel.outdoorContext.peakUVIndex {
            return "UV \(value)"
        }
        return "--"
    }

    private var outdoorStatusTint: Color {
        switch viewModel.outdoorContext.statusLabel {
        case "温和", "适中":
            return Theme.Colors.mintGreen
        case "偏强", "很强":
            return Color(hex: "E98B4A")
        default:
            return Theme.Colors.textSecondary
        }
    }

    private var outdoorAdviceWindowText: String {
        switch selectedRange {
        case .day:
            if completionRatio >= 1 {
                return String(localized: "白天正常出门时段")
            }
            if selectedDateHour < 10 {
                return String(localized: "现在到 10:30")
            }
            if selectedDateHour < 14 {
                return String(localized: "接下来 2 小时内")
            }
            if selectedDateHour < 17 {
                return String(localized: "傍晚前")
            }
            return String(localized: "明天上午优先")
        case .week:
            return String(localized: "工作日上午更优先")
        case .month:
            return String(localized: "固定在上午更稳")
        }
    }

    private var remainingSunlightMinutesText: String {
        let remaining = max(0, Int(ceil(20 - summary.displayMinutes)))
        if remaining <= 0 { return "0 分钟" }
        if remaining <= 10 { return "\(remaining) 分钟" }
        return "\(remaining) 分钟"
    }

    private var isSelectedDateToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var canMoveForward: Bool {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch selectedRange {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        let next = calendar.date(byAdding: component, value: 1, to: selectedDate) ?? selectedDate
        let nextStart: Date
        switch selectedRange {
        case .day:
            nextStart = calendar.startOfDay(for: next)
        case .week:
            nextStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: next)) ?? next
        case .month:
            nextStart = calendar.dateInterval(of: .month, for: next)?.start ?? next
        }
        return nextStart <= calendar.startOfDay(for: Date())
    }

    private var selectedDateHour: Int {
        let referenceDate = isSelectedDateToday ? Date() : selectedDate.addingTimeInterval(12 * 60 * 60)
        return Calendar.current.component(.hour, from: referenceDate)
    }

    private var rangeDescription: String {
        switch selectedRange {
        case .day:
            return String(localized: "查看当天自然光暴露变化")
        case .week:
            return String(localized: "查看本周每日暴露与累计进度")
        case .month:
            return String(localized: "查看本月每日暴露与累计进度")
        }
    }

    private var xAxisDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedDate)
        switch selectedRange {
        case .day:
            return selectedDay...(calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: selectedDay) ?? selectedDay
            let end = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
            return start...end
        case .month:
            let interval = calendar.dateInterval(of: .month, for: selectedDate)
                ?? DateInterval(start: selectedDay, duration: 31 * 86_400)
            return interval.start...interval.end
        }
    }

    private var xAxisMarks: [Date] {
        let calendar = Calendar.current
        switch selectedRange {
        case .day:
            let start = calendar.startOfDay(for: selectedDate)
            return [6, 12, 18].compactMap { calendar.date(byAdding: .hour, value: $0, to: start) }
        case .week:
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: xAxisDomain.lowerBound) }
        case .month:
            let days = max(1, calendar.dateComponents([.day], from: xAxisDomain.lowerBound, to: xAxisDomain.upperBound).day ?? 30)
            return [0, 7, 14, 21, days - 1].compactMap { calendar.date(byAdding: .day, value: $0, to: xAxisDomain.lowerBound) }
        }
    }

    private var yAxisUpperBound: Double {
        let maxValue = max(chartBars.map(\.value).max() ?? 0, 20)
        let step = max(5, ceil((maxValue / 4) / 5) * 5)
        return step * 4
    }

    private var yAxisMarks: [Double] {
        let step = yAxisUpperBound / 4
        return (0...4).map { Double($0) * step }
    }

    private var dateTitle: String {
        switch selectedRange {
        case .day:
            return selectedDate.formatted(.dateTime.year().month(.wide).day())
        case .week:
            let end = Calendar.current.startOfDay(for: selectedDate)
            let start = Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end
            return "\(start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return selectedDate.formatted(.dateTime.year().month(.wide))
        }
    }

    private var trendTitle: String {
        switch selectedRange {
        case .day:
            return String(localized: "当日趋势")
        case .week:
            return String(localized: "本周趋势")
        case .month:
            return String(localized: "当月趋势")
        }
    }

    private var chartInsightText: String {
        if summary.displayMinutes == 0 {
            return String(localized: "当前范围内没有可用自然光记录。")
        }
        if selectedBar != nil {
            return String(localized: "已切换到单个时段/日期视角，可以直接比较这一根柱子和整体节律的位置。")
        }
        switch selectedRange {
        case .day:
            return summary.morningMinutes >= summary.afternoonMinutes
                ? "今天的自然光更多落在上午，这通常更有利于白天清醒和夜间节律稳定。"
                : "今天的自然光主要集中在午后，如果想更稳地拉回节律，可以把一部分暴露前移到上午。"
        case .week:
            return String(localized: "这张图按天展示本周真实暴露分钟数，先看有没有连续几天稳定接近 20 分钟。")
        case .month:
            return String(localized: "这张图按天展示本月真实暴露分钟数，重点看是否形成连续稳定的日照习惯。")
        }
    }

    private func sunlightBarGradient(for item: SunlightBarPoint) -> LinearGradient {
        if selectedRange == .day {
            let hour = Calendar.current.component(.hour, from: item.time)
            if hour < 12 {
                return LinearGradient(
                    colors: [Color(hex: "FFE08A"), Color(hex: "F4A259")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            return LinearGradient(
                colors: [Color(hex: "FFD36F"), Color(hex: "E98B4A")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        let isPeak = item.id == summary.peakBar.id && item.value > 0
        return LinearGradient(
            colors: isPeak ? [Color(hex: "FFD36F"), Color(hex: "E98B4A")] : [Self.accent, Self.tint],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func nearestBar(to date: Date) -> SunlightBarPoint? {
        chartBars.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) })
    }

    private func selectedBarDetailCard(for bar: SunlightBarPoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(selectedBarLabel(for: bar))
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("\(Int(bar.value.rounded())) 分钟")
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Self.tint)
            }

            Text(selectedBarDescription(for: bar))
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func selectedBarLabel(for bar: SunlightBarPoint) -> String {
        switch selectedRange {
        case .day:
            return "\(axisLabel(for: bar.time))"
        case .week, .month:
            return "\(axisLabel(for: bar.time))"
        }
    }

    private func selectedBarDescription(for bar: SunlightBarPoint) -> String {
        switch selectedRange {
        case .day:
            if bar.value == 0 {
                return String(localized: "这个小时没有读取到自然光暴露记录。")
            }
            let hour = Calendar.current.component(.hour, from: bar.time)
            if hour < 12 {
                return String(localized: "这一小时的自然光暴露发生在上午，更有利于帮助身体建立清醒信号。")
            }
            return String(localized: "这一小时的自然光暴露发生在午后，若能有一部分前移到上午，节律会更理想。")
        case .week:
            if bar.value == 0 {
                return String(localized: "这一天没有读取到自然光暴露记录。")
            }
            if bar.value >= 20 {
                return String(localized: "这一天已经达到建议暴露量，是本周值得复用的外出节奏。")
            }
            return String(localized: "这一天有自然光暴露，但距离建议目标还有空间。")
        case .month:
            if bar.value == 0 {
                return String(localized: "这一天没有读取到自然光暴露记录。")
            }
            if bar.value >= 20 {
                return String(localized: "这一天已经达到建议暴露量，说明当日的作息更贴近日照目标。")
            }
            return String(localized: "这一天有自然光暴露记录，但还没有达到理想目标。")
        }
    }

    private func shiftDate(by value: Int) {
        if value > 0, !canMoveForward { return }
        let calendar = Calendar.current
        let component: Calendar.Component
        switch selectedRange {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }
        let candidate = calendar.date(byAdding: component, value: value, to: selectedDate) ?? selectedDate
        selectedDate = value > 0 ? min(candidate, calendar.startOfDay(for: Date())) : candidate
    }

    private func axisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        switch selectedRange {
        case .day:
            formatter.dateFormat = "HH:mm"
        case .week:
            formatter.dateFormat = "E"
        case .month:
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: date)
    }

    private func reloadData() async {
        await viewModel.reload(range: selectedRange, selectedDate: selectedDate)
    }
}

private struct SunlightBarPoint: Identifiable {
    let time: Date
    let value: Double

    var id: TimeInterval { time.timeIntervalSince1970 }
}

nonisolated private struct SunlightGaugeArc: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        return path
    }
}

private struct SunlightSummary {
    let displayMinutes: Double
    let morningMinutes: Double
    let afternoonMinutes: Double
    let previousComparableMinutes: Double?
    let barPoints: [SunlightBarPoint]
    let peakBar: SunlightBarPoint
    let peakValue: Double
    let activeBucketCount: Int

    static func make(
        range: SunlightSheetView.Range,
        anchorDate: Date,
        currentPoints: [TimeSeriesPointDouble],
        previousPoints: [TimeSeriesPointDouble]
    ) -> SunlightSummary {
        let calendar = Calendar.current
        let morning = currentPoints
            .filter { calendar.component(.hour, from: $0.date) < 12 }
            .reduce(0) { $0 + $1.value }
        let afternoon = currentPoints
            .filter { calendar.component(.hour, from: $0.date) >= 12 }
            .reduce(0) { $0 + $1.value }

        switch range {
        case .day:
            let start = calendar.startOfDay(for: anchorDate)
            let bars = (0..<24).compactMap { hour -> SunlightBarPoint? in
                guard let time = calendar.date(byAdding: .hour, value: hour, to: start) else { return nil }
                let value = currentPoints.first(where: { calendar.component(.hour, from: $0.date) == hour })?.value ?? 0
                return SunlightBarPoint(time: time, value: value)
            }
            let currentTotal = bars.reduce(0) { $0 + $1.value }
            let previousTotal = previousPoints.reduce(0) { $0 + $1.value }
            let peakBar = bars.max(by: { $0.value < $1.value }) ?? SunlightBarPoint(time: start, value: 0)
            return SunlightSummary(
                displayMinutes: currentTotal,
                morningMinutes: morning,
                afternoonMinutes: afternoon,
                previousComparableMinutes: previousTotal > 0 ? previousTotal : nil,
                barPoints: bars,
                peakBar: peakBar,
                peakValue: peakBar.value,
                activeBucketCount: bars.filter { $0.value > 0 }.count
            )

        case .week:
            let start = calendar.startOfDay(for: anchorDate)
            let grouped = Dictionary(grouping: currentPoints) { calendar.startOfDay(for: $0.date) }
            let bars = (0..<7).compactMap { offset -> SunlightBarPoint? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                let key = calendar.startOfDay(for: day)
                let total = grouped[key]?.reduce(0) { $0 + $1.value } ?? 0
                return SunlightBarPoint(time: key, value: total)
            }
            let total = bars.reduce(0) { $0 + $1.value }
            let previousTotal = previousPoints.reduce(0) { $0 + $1.value }
            let peakBar = bars.max(by: { $0.value < $1.value }) ?? SunlightBarPoint(time: start, value: 0)
            return SunlightSummary(
                displayMinutes: total,
                morningMinutes: morning,
                afternoonMinutes: afternoon,
                previousComparableMinutes: previousTotal > 0 ? previousTotal : nil,
                barPoints: bars,
                peakBar: peakBar,
                peakValue: peakBar.value,
                activeBucketCount: bars.filter { $0.value > 0 }.count
            )

        case .month:
            let month = calendar.dateInterval(of: .month, for: anchorDate)
            let start = month?.start ?? calendar.startOfDay(for: anchorDate)
            let days = month.map { calendar.dateComponents([.day], from: $0.start, to: $0.end).day ?? 30 } ?? 30
            let grouped = Dictionary(grouping: currentPoints) { calendar.startOfDay(for: $0.date) }
            let bars = (0..<days).compactMap { offset -> SunlightBarPoint? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                let key = calendar.startOfDay(for: day)
                let total = grouped[key]?.reduce(0) { $0 + $1.value } ?? 0
                return SunlightBarPoint(time: key, value: total)
            }
            let total = bars.reduce(0) { $0 + $1.value }
            let previousTotal = previousPoints.reduce(0) { $0 + $1.value }
            let peakBar = bars.max(by: { $0.value < $1.value }) ?? SunlightBarPoint(time: start, value: 0)
            return SunlightSummary(
                displayMinutes: total,
                morningMinutes: morning,
                afternoonMinutes: afternoon,
                previousComparableMinutes: previousTotal > 0 ? previousTotal : nil,
                barPoints: bars,
                peakBar: peakBar,
                peakValue: peakBar.value,
                activeBucketCount: bars.filter { $0.value > 0 }.count
            )
        }
    }
}

@MainActor
@Observable
final class SunlightSheetViewModel {
    var currentPoints: [TimeSeriesPointDouble] = []
    var previousPoints: [TimeSeriesPointDouble] = []
    var isLoading = false
    var errorMessage: String?
    var outdoorContext = SunlightOutdoorContext.placeholder

    private let locationService = LocationSharingService.shared
    private let weatherService = WeatherService.shared
    private let geocoder = CLGeocoder()
    private var loadRequestID = UUID()

    func reload(range: SunlightSheetView.Range, selectedDate: Date) async {
        let requestID = UUID()
        loadRequestID = requestID
        isLoading = true
        errorMessage = nil

        let currentBounds = Self.bounds(for: range, anchorDate: selectedDate)
        let previousBounds = Self.previousBounds(for: currentBounds)

        async let currentSeriesTask = HealthKitManager.shared.fetchTimeInDaylightSeries(
            start: currentBounds.start,
            end: currentBounds.end,
            interval: DateComponents(hour: 1)
        )
        async let previousSeriesTask = HealthKitManager.shared.fetchTimeInDaylightSeries(
            start: previousBounds.start,
            end: previousBounds.end,
            interval: DateComponents(hour: 1)
        )
        async let outdoorContextTask = loadOutdoorContext(for: selectedDate)

        do {
            let loadedCurrentPoints = try await currentSeriesTask
            let loadedPreviousPoints = try await previousSeriesTask
            guard loadRequestID == requestID else { return }
            currentPoints = loadedCurrentPoints
            previousPoints = loadedPreviousPoints
            if currentPoints.isEmpty {
                errorMessage = String(localized: "当前范围内还没有自然光暴露记录。")
            }
        } catch {
            guard loadRequestID == requestID else { return }
            currentPoints = []
            previousPoints = []
            errorMessage = String(localized: "读取自然光数据失败，请检查健康权限与系统支持情况。")
        }

        let loadedOutdoorContext = await outdoorContextTask
        guard loadRequestID == requestID else { return }
        outdoorContext = loadedOutdoorContext

        isLoading = false
    }

    func loadOutdoorContext(for selectedDate: Date) async -> SunlightOutdoorContext {
        guard Calendar.current.isDateInToday(selectedDate) else {
            return .historical(for: selectedDate)
        }

        let authorization = await locationService.requestAuthorizationIfNeeded()
        guard authorization == .authorized else {
            return .locationPermissionRequired
        }

        guard let location = await locationService.fetchCurrentLocationIfAuthorized() else {
            return .locationPermissionRequired
        }

        async let placemarkTask = reverseGeocode(location: location)
        async let weatherTask = fetchWeather(location: location)

        let locationName = await placemarkTask ?? "当前位置"
        let weather = await weatherTask

        guard let weather else {
            return SunlightOutdoorContext(
                locationName: locationName,
                currentUVIndex: nil,
                currentConditionDescription: "天气暂时不可用",
                currentTemperatureText: "--",
                sunriseText: "--:--",
                sunsetText: "--:--",
                peakUVIndex: nil,
                bestExposureWindowText: "优先白天外出",
                recommendationHeadline: "定位已获取，但天气数据暂时不可用。",
                recommendationDetail: "你仍然可以参考今天的自然光完成度安排短时外出。",
                weatherSymbolName: "cloud.sun",
                gaugeProgress: 0,
                statusLabel: "等待天气",
                cautionText: "如果持续无法获取天气，请确认真机已开启 WeatherKit 服务与网络连接。",
                showsSettingsAction: false
            )
        }

        let uv = weather.currentWeather.uvIndex.value
        let hourly = weather.hourlyForecast.forecast
        let peakUV = hourly.map { $0.uvIndex.value }.max() ?? uv
        let bestWindow = Self.bestExposureWindowText(from: hourly)

        return SunlightOutdoorContext(
            locationName: locationName,
            currentUVIndex: uv,
            currentConditionDescription: Self.conditionDescription(for: weather.currentWeather.condition),
            currentTemperatureText: Self.temperatureText(for: weather.currentWeather.temperature),
            sunriseText: Self.timeText(for: weather.dailyForecast.forecast.first?.sun.sunrise),
            sunsetText: Self.timeText(for: weather.dailyForecast.forecast.first?.sun.sunset),
            peakUVIndex: peakUV,
            bestExposureWindowText: bestWindow,
            recommendationHeadline: Self.recommendationHeadline(for: uv),
            recommendationDetail: Self.recommendationDetail(for: uv, bestWindow: bestWindow),
            weatherSymbolName: weather.currentWeather.symbolName,
            gaugeProgress: min(max(Double(uv) / 11.0, 0), 1),
            statusLabel: Self.uvStatusLabel(for: uv),
            cautionText: Self.cautionText(for: uv),
            showsSettingsAction: false
        )
    }

    private func reverseGeocode(location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            let candidates = [
                placemark.locality,
                placemark.subAdministrativeArea,
                placemark.administrativeArea
            ]
            return candidates.compactMap { $0 }.first.map { "\($0)" }
        } catch {
            return nil
        }
    }

    private func fetchWeather(location: CLLocation) async -> Weather? {
        do {
            return try await weatherService.weather(for: location)
        } catch {
            return nil
        }
    }

    private static func temperatureText(for temperature: Measurement<UnitTemperature>) -> String {
        let value = Int(temperature.converted(to: .celsius).value.rounded())
        return "\(value)°C"
    }

    private static func timeText(for date: Date?) -> String {
        guard let date else { return "--:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func bestExposureWindowText(from hourly: [HourWeather]) -> String {
        let filtered = hourly.filter { item in
            let hour = Calendar.current.component(.hour, from: item.date)
            return hour >= 9 && hour <= 16
        }

        guard !filtered.isEmpty else { return "09:00 - 16:00" }

        let suitable = filtered.filter { item in
            let value = item.uvIndex.value
            return value >= 2 && value <= 6
        }

        guard let first = suitable.first, let last = suitable.last else {
            return "10:00 - 15:00"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: first.date)) - \(formatter.string(from: last.date))"
    }

    private static func uvStatusLabel(for uv: Int) -> String {
        switch uv {
        case ..<2: return String(localized: "偏弱")
        case ..<5: return String(localized: "温和")
        case ..<7: return String(localized: "适中")
        case ..<9: return String(localized: "偏强")
        default: return String(localized: "很强")
        }
    }

    private static func recommendationHeadline(for uv: Int) -> String {
        switch uv {
        case ..<2:
            return String(localized: "现在紫外线偏弱，适合轻松出门走一走。")
        case ..<5:
            return String(localized: "现在是比较舒服的外出时段，适合顺手补自然光。")
        case ..<7:
            return String(localized: "当前紫外线适中，安排短时外出效率不错。")
        case ..<9:
            return String(localized: "紫外线已经偏强，建议缩短暴露时间并注意遮挡。")
        default:
            return String(localized: "现在紫外线很强，更适合避开直晒或改到稍晚一些。")
        }
    }

    private static func recommendationDetail(for uv: Int, bestWindow: String) -> String {
        switch uv {
        case ..<2:
            return String(localized: "如果今天还没晒到太阳，可以直接利用现在的窗口补一点；更高效时段预计在 \(bestWindow)。")
        case ..<5:
            return String(localized: "当前体感和效率通常比较平衡，适合散步、通勤多走一段，或在室外停留 10 到 20 分钟。")
        case ..<7:
            return String(localized: "如果只是想补自然光，优先控制在 10 到 15 分钟，并尽量选择 \(bestWindow) 这样的稳定窗口。")
        case ..<9:
            return String(localized: "想继续外出的话，建议缩短单次时长，优先选择有遮阴路线，并避免长时间直晒。")
        default:
            return String(localized: "更建议把外出改到 \(bestWindow) 这样的时段，既能补光，也更容易兼顾舒适度和防晒。")
        }
    }

    private static func cautionText(for uv: Int) -> String {
        switch uv {
        case ..<5:
            return String(localized: "以补光和建立白天清醒信号为主，保持规律比单次很久更重要。")
        case ..<7:
            return String(localized: "效率不错，但不需要为了日照刻意停留过久。")
        default:
            return String(localized: "紫外线偏强时，以短时见光、及时补水和避免长时间暴露为主。")
        }
    }

    private static func conditionDescription(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear:
            return String(localized: "晴")
        case .mostlyClear, .partlyCloudy:
            return String(localized: "多云")
        case .cloudy, .mostlyCloudy:
            return String(localized: "阴")
        case .drizzle, .rain, .heavyRain, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .sunShowers:
            return String(localized: "雨")
        case .snow, .flurries, .sleet, .hail, .blizzard, .blowingSnow:
            return String(localized: "雪")
        case .foggy, .haze, .smoky:
            return String(localized: "雾")
        default:
            return String(localized: "天气")
        }
    }

    private static func bounds(for range: SunlightSheetView.Range, anchorDate: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            return (start, end)
        case .week:
            let anchorStart = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: anchorStart) ?? anchorStart
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? anchorStart
            return (start, end)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: anchorDate)
            let start = interval?.start ?? calendar.startOfDay(for: anchorDate)
            let end = interval?.end ?? calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(2_592_000)
            return (start, end)
        }
    }

    private static func previousBounds(for bounds: (start: Date, end: Date)) -> (start: Date, end: Date) {
        let duration = bounds.end.timeIntervalSince(bounds.start)
        let previousEnd = bounds.start
        let previousStart = previousEnd.addingTimeInterval(-duration)
        return (previousStart, previousEnd)
    }
}

struct SunlightOutdoorContext {
    let locationName: String
    let currentUVIndex: Int?
    let currentConditionDescription: String
    let currentTemperatureText: String
    let sunriseText: String
    let sunsetText: String
    let peakUVIndex: Int?
    let bestExposureWindowText: String
    let recommendationHeadline: String
    let recommendationDetail: String
    let weatherSymbolName: String
    let gaugeProgress: Double
    let statusLabel: String
    let cautionText: String
    let showsSettingsAction: Bool

    static let placeholder = SunlightOutdoorContext(
        locationName: "定位中",
        currentUVIndex: nil,
        currentConditionDescription: "正在读取天气",
        currentTemperatureText: "--",
        sunriseText: "--:--",
        sunsetText: "--:--",
        peakUVIndex: nil,
        bestExposureWindowText: "--",
        recommendationHeadline: "正在准备外出建议",
        recommendationDetail: "需要定位和天气数据来生成更贴近当天情况的建议。",
        weatherSymbolName: "cloud.sun",
        gaugeProgress: 0,
        statusLabel: "读取中",
        cautionText: "请稍等片刻。",
        showsSettingsAction: false
    )

    static let locationPermissionRequired = SunlightOutdoorContext(
        locationName: "未开启定位",
        currentUVIndex: nil,
        currentConditionDescription: "天气不可用",
        currentTemperatureText: "--",
        sunriseText: "--:--",
        sunsetText: "--:--",
        peakUVIndex: nil,
        bestExposureWindowText: "开启定位后可用",
        recommendationHeadline: "需要定位权限，才能结合本地天气给出外出建议。",
        recommendationDetail: "如果这次没有看到系统弹窗，通常是之前已经拒绝过，需要到系统设置里手动打开定位权限。",
        weatherSymbolName: "location.slash",
        gaugeProgress: 0,
        statusLabel: "未连接",
        cautionText: "定位开好后，如果仍没有天气数据，再检查 App ID 是否已启用 WeatherKit。",
        showsSettingsAction: true
    )

    static func historical(for selectedDate: Date) -> SunlightOutdoorContext {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        let dateText = formatter.string(from: selectedDate)
        return SunlightOutdoorContext(
            locationName: dateText,
            currentUVIndex: nil,
            currentConditionDescription: "历史记录",
            currentTemperatureText: "--",
            sunriseText: "--:--",
            sunsetText: "--:--",
            peakUVIndex: nil,
            bestExposureWindowText: "仅今天支持实时天气",
            recommendationHeadline: "历史日期不显示实时天气，主要用来回看当时的日照节律。",
            recommendationDetail: "如果想看当前位置的外出建议，请切回今天。",
        weatherSymbolName: "clock.arrow.circlepath",
        gaugeProgress: 0,
        statusLabel: "历史",
        cautionText: "实时 UV 和天气只在今天页展示。",
        showsSettingsAction: false
    )
}
}

#Preview {
    SunlightSheetView()
}
