/// BodyProfileEditorView 由身体档案入口调用，作为「身体档案」编辑页。
/// 负责定义档案记录数据结构（BodyProfileRecord）并管理身高、体重、目标体重编辑。

import SwiftUI
import Charts

struct BodyProfileRecord: Sendable {
    let heightCm: Double
    let weightKg: Double
    let targetWeightKg: Double
    let date: Date
}

private enum BodyProfileTrendMetric: String, CaseIterable, Identifiable {
    case weight = "体重"
    case height = "身高"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .weight: return "kg"
        case .height: return "cm"
        }
    }

    var symbol: String {
        switch self {
        case .weight: return "scalemass.fill"
        case .height: return "ruler.fill"
        }
    }

    var accent: Color {
        switch self {
        case .weight: return Color(hex: "91C783")
        case .height: return Color(hex: "6FA7D8")
        }
    }
}

private enum BodyProfileTrendRange: String, CaseIterable, Identifiable {
    case week = "7天"
    case month = "30天"
    case quarter = "90天"
    case year = "一年"
    case all = "全部"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}

private enum BodyProfileInputField: Hashable {
    case height
    case currentWeight
    case targetWeight
}

struct BodyProfileRecordSheet: View {
    let initialHeightCm: Double
    let initialWeightKg: Double
    let initialTargetWeightKg: Double
    let onSave: (BodyProfileRecord) async -> Void

    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @FocusState private var focusedInput: BodyProfileInputField?
    @State private var heightCm: Double
    @State private var weightKg: Double
    @State private var targetWeightKg: Double
    @State private var recordDate = Date()
    @State private var isSaving = false
    @State private var selectedTrendMetric: BodyProfileTrendMetric = .weight
    @State private var selectedTrendRange: BodyProfileTrendRange = .week
    @State private var weightTrendPoints: [TimeSeriesPointDouble] = []
    @State private var heightTrendPoints: [TimeSeriesPointDouble] = []
    @State private var selectedTrendPointID: Int64?
    @State private var isTrendLoading = false
    @State private var trendLoadFailed = false

    init(
        initialHeightCm: Double,
        initialWeightKg: Double,
        initialTargetWeightKg: Double,
        onSave: @escaping (BodyProfileRecord) async -> Void
    ) {
        self.initialHeightCm = initialHeightCm
        self.initialWeightKg = initialWeightKg
        self.initialTargetWeightKg = initialTargetWeightKg
        self.onSave = onSave
        _heightCm = State(initialValue: min(max(initialHeightCm, 120), 220))
        _weightKg = State(initialValue: min(max(initialWeightKg, 30), 180))
        _targetWeightKg = State(initialValue: min(max(initialTargetWeightKg, 30), 180))
    }

    private var bmi: Double {
        let heightM = heightCm / 100.0
        return weightKg / (heightM * heightM)
    }

    private var bmiLevel: String {
        switch bmi {
        case ..<18.5: return "偏瘦"
        case ..<24: return "标准"
        case ..<28: return "偏胖"
        case ..<32: return "肥胖"
        default: return "重度肥胖"
        }
    }

    private var healthyWeightRange: ClosedRange<Double> {
        let heightM = heightCm / 100.0
        return (18.5 * heightM * heightM)...(23.9 * heightM * heightM)
    }

    private var targetDifference: Double {
        targetWeightKg - weightKg
    }

    private var targetSummary: String {
        if abs(targetDifference) < 0.05 { return "已达到目标体重" }
        return targetDifference > 0
            ? "距离目标还需增加 \(String(format: "%.1f", abs(targetDifference))) kg"
            : "距离目标还需减少 \(String(format: "%.1f", abs(targetDifference))) kg"
    }

    private var allTrendPoints: [TimeSeriesPointDouble] {
        let historicalPoints = selectedTrendMetric == .weight ? weightTrendPoints : heightTrendPoints
        let calendar = Calendar.current
        let draftDate = calendar.startOfDay(for: recordDate)
        let draftValue = selectedTrendMetric == .weight ? weightKg : heightCm

        // 当前表单值也是图表的一部分，让用户在保存前就能确认本次记录。
        // 同一天的 HealthKit 均值会被预览值替换，避免图表和统计重复计算一天。
        let pointsBeforeDraftDay = historicalPoints.filter {
            !calendar.isDate($0.date, inSameDayAs: draftDate)
        }
        let draftPoint = TimeSeriesPointDouble(
            timestamp: Int64(draftDate.timeIntervalSince1970),
            value: draftValue
        )
        return (pointsBeforeDraftDay + [draftPoint]).sorted { $0.date < $1.date }
    }

    private var visibleTrendPoints: [TimeSeriesPointDouble] {
        guard let days = selectedTrendRange.days else { return allTrendPoints }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return allTrendPoints.filter { $0.date >= start }
    }

    private var selectedTrendPoint: TimeSeriesPointDouble? {
        if let selectedTrendPointID,
           let point = visibleTrendPoints.first(where: { $0.id == selectedTrendPointID }) {
            return point
        }
        return visibleTrendPoints.last
    }

    private func isDraftTrendPoint(_ point: TimeSeriesPointDouble) -> Bool {
        Calendar.current.isDate(point.date, inSameDayAs: recordDate)
    }

    private var trendAverage: Double? {
        guard !visibleTrendPoints.isEmpty else { return nil }
        return visibleTrendPoints.map(\.value).reduce(0, +) / Double(visibleTrendPoints.count)
    }

    private var trendMaximum: TimeSeriesPointDouble? {
        visibleTrendPoints.max { $0.value < $1.value }
    }

    private var trendMinimum: TimeSeriesPointDouble? {
        visibleTrendPoints.min { $0.value < $1.value }
    }

    private var trendChange: Double? {
        guard let first = visibleTrendPoints.first?.value,
              let last = visibleTrendPoints.last?.value else { return nil }
        return last - first
    }

    private var trendYDomain: ClosedRange<Double> {
        let values = visibleTrendPoints.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let minimumPadding = selectedTrendMetric == .weight ? 0.8 : 0.4
        let padding = max((maximum - minimum) * 0.28, minimumPadding)
        return max(0, minimum - padding)...(maximum + padding)
    }

    private var trendXAxisDates: [Date] {
        guard let first = visibleTrendPoints.first?.date,
              let last = visibleTrendPoints.last?.date else { return [] }
        if visibleTrendPoints.count <= 2 { return visibleTrendPoints.map(\.date) }
        let middle = visibleTrendPoints[visibleTrendPoints.count / 2].date
        return [first, middle, last]
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: "EEF7FB"), Color(hex: "F8FBFA"), Color(hex: "FFF8F0")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            bodyProfileHeroBackdrop

            AdaptivePageScrollView(topPadding: 10, bottomPadding: 36) {
                VStack(alignment: .leading, spacing: 22) {
                    bodySummary

                    bodyTrendSection

                    bodyDataHeader

                    VStack(spacing: 16) {
                        BodyProfileRulerControl(
                            title: "身高",
                            value: $heightCm,
                            range: 120...220,
                            step: 1,
                            unit: "cm",
                            tint: Color(hex: "91C783"),
                            field: .height,
                            focusedField: $focusedInput
                        )

                        BodyProfileRulerControl(
                            title: "当前体重",
                            value: $weightKg,
                            range: 30...180,
                            step: 0.1,
                            unit: "kg",
                            tint: Color(hex: "FF9446"),
                            field: .currentWeight,
                            focusedField: $focusedInput
                        )

                        BodyProfileRulerControl(
                            title: "目标体重",
                            value: $targetWeightKg,
                            range: 30...180,
                            step: 0.1,
                            unit: "kg",
                            tint: Color(hex: "91C783"),
                            field: .targetWeight,
                            focusedField: $focusedInput
                        )
                    }

                    bmiPreview

                    Label("数据仅保存在您的设备与健康 App", systemImage: "lock.shield.fill")
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "7F8790"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)

                    saveButton
                }
            }
        }
        .appSecondaryNavigation(title: HealthPageName.bodyProfile)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedInput = nil
                }
            }
        }
        .task {
            await loadTrendPoints()
        }
        .onChange(of: selectedTrendMetric) { _, _ in
            selectedTrendPointID = nil
        }
        .onChange(of: selectedTrendRange) { _, _ in
            selectedTrendPointID = nil
        }
        .sensoryFeedback(.selection, trigger: selectedTrendMetric)
        .sensoryFeedback(.selection, trigger: selectedTrendRange)
    }

    private var bodyProfileHeroColor: Color {
        Color(hex: "E7F3E4")
    }

    private var bodyProfileHeroBackdrop: some View {
        VStack(spacing: 0) {
            bodyProfileHeroColor
                .frame(height: 180)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var bodyDataHeader: some View {
        HStack(spacing: 12) {
            sectionHeader("身体数据", symbol: "figure.stand")

            Spacer(minLength: 8)

            DatePicker(
                "记录日期",
                selection: $recordDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(Color(hex: "4A7CE8"))
            .accessibilityLabel("记录日期")
        }
    }

    private var bodyTrendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(selectedTrendMetric.rawValue)趋势")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "343A3E"))
                    Text(trendSourceDescription)
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "909492"))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                metricSelector
            }

            rangeSelector

            trendSummaryRow

            if !visibleTrendPoints.isEmpty {
                trendChart
                trendStatsGrid
            } else if isTrendLoading {
                ProgressView()
                    .tint(selectedTrendMetric.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 228)
            } else if trendLoadFailed {
                trendFailureState
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.appSystem(size: 28, weight: .semibold))
                        .foregroundColor(selectedTrendMetric.accent)
                    Text("当前范围暂无\(selectedTrendMetric.rawValue)记录")
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "5F666A"))
                    Text("请选择包含记录日期的范围，或等待健康 App 同步历史记录。")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "989D9F"))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 228)
            }
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        }
        .shadow(color: Color(hex: "84A7D9").opacity(0.10), radius: 18, x: 0, y: 10)
    }

    private var trendSourceDescription: String {
        if isTrendLoading {
            return String(localized: "当前填写预览 · 正在同步健康 App")
        }
        if trendLoadFailed {
            return String(localized: "当前填写预览 · 健康 App 暂不可读")
        }
        return String(localized: "健康 App 历史与当前填写预览")
    }

    private var trendFailureState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.appSystem(size: 30, weight: .semibold))
                .foregroundColor(selectedTrendMetric.accent)

            Text("趋势数据暂时没有加载成功")
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "5F666A"))

            Button {
                Task { await loadTrendPoints() }
            } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent)
                    .padding(.horizontal, 15)
                    .frame(height: 40)
                    .background(selectedTrendMetric.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 228)
    }

    private var metricSelector: some View {
        HStack(spacing: 2) {
            ForEach(BodyProfileTrendMetric.allCases) { metric in
                Button {
                    selectedTrendMetric = metric
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: metric.symbol)
                            .font(.appSystem(size: 10, weight: .black))
                        Text(metric.rawValue)
                            .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    }
                    .foregroundColor(selectedTrendMetric == metric ? metric.accent : Color(hex: "858B8E"))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        selectedTrendMetric == metric ? Color.white : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(metric.rawValue)趋势")
            }
        }
        .padding(3)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var rangeSelector: some View {
        HStack(spacing: 2) {
            ForEach(BodyProfileTrendRange.allCases) { range in
                Button {
                    selectedTrendRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(selectedTrendRange == range ? Color(hex: "484D50") : Color(hex: "929799"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            selectedTrendRange == range ? Color.white : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(hex: "EFF0EF"), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var trendSummaryRow: some View {
        HStack(spacing: 12) {
            trendSummaryMetric(
                title: selectedTrendMetric == .weight ? "距离目标" : "区间均值",
                value: primaryTrendSummary,
                color: Color(hex: "373B3D")
            )
            trendSummaryMetric(
                title: "\(selectedTrendMetric.rawValue)变化",
                value: trendChangeText,
                color: trendChangeColor
            )
        }
    }

    private func trendSummaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "929799"))
            Text(value)
                .font(.appSystem(size: 25, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryTrendSummary: String {
        if selectedTrendMetric == .weight {
            guard let current = visibleTrendPoints.last?.value else { return "--" }
            return String(format: "%.1f kg", abs(current - targetWeightKg))
        }
        return trendAverage.map { String(format: "%.0f cm", $0) } ?? "--"
    }

    private var trendChangeText: String {
        guard let trendChange else { return "--" }
        let prefix = trendChange > 0 ? "+" : ""
        let format = selectedTrendMetric == .weight ? "%.1f" : "%.0f"
        return "\(prefix)\(String(format: format, trendChange)) \(selectedTrendMetric.unit)"
    }

    private var trendChangeColor: Color {
        guard let trendChange else { return Color(hex: "929799") }
        if selectedTrendMetric == .weight {
            return trendChange <= 0 ? Color(hex: "91C783") : Color(hex: "F0A23A")
        }
        return trendChange >= 0 ? Color(hex: "6FA7D8") : Color(hex: "F0A23A")
    }

    private var trendChart: some View {
        let accent = selectedTrendMetric.accent

        return Chart {
            ForEach(visibleTrendPoints) { point in
                AreaMark(
                    x: .value("日期", point.date),
                    yStart: .value("基线", trendYDomain.lowerBound),
                    yEnd: .value(selectedTrendMetric.rawValue, point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.28), accent.opacity(0.015)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("日期", point.date),
                    y: .value(selectedTrendMetric.rawValue, point.value)
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)

                if point.id == selectedTrendPoint?.id {
                    RuleMark(x: .value("选中日期", point.date))
                        .foregroundStyle(accent.opacity(0.72))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value(selectedTrendMetric.rawValue, point.value)
                    )
                    .symbolSize(86)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .annotation(position: .overlay) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(accent, lineWidth: 3))
                    }
                    .annotation(
                        position: .top,
                        spacing: 10,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        trendTooltip(point)
                    }
                }
            }
        }
        .frame(height: 228)
        .chartLegend(.hidden)
        .chartYScale(domain: trendYDomain)
        .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 10))
        .chartXAxis {
            AxisMarks(values: trendXAxisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                AxisTick(stroke: StrokeStyle(lineWidth: 0))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(trendAxisDate(date))
                            .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "8C9294"))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
                    .foregroundStyle(Color.black.opacity(0.07))
                AxisTick(stroke: StrokeStyle(lineWidth: 0))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(trendAxisValue(number))
                            .font(.appSystem(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "919698"))
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.top, 22)
                .padding(.bottom, 6)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard frame.contains(value.location) else { return }
                                    let relativeX = value.location.x - frame.origin.x
                                    guard let date: Date = proxy.value(atX: relativeX) else { return }
                                    selectedTrendPointID = visibleTrendPoints.min {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }?.id
                                }
                        )
                }
            }
        }
        .accessibilityLabel("\(selectedTrendMetric.rawValue)趋势图")
    }

    private func trendTooltip(_ point: TimeSeriesPointDouble) -> some View {
        VStack(spacing: 3) {
            Text(trendValue(point.value))
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "3E4244"))
            Text(isDraftTrendPoint(point) ? "当前填写 · \(trendFullDate(point.date))" : trendFullDate(point.date))
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "A0A4A5"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private var trendStatsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            trendStat(title: "数据天数", value: "\(visibleTrendPoints.count) 天", symbol: "calendar", tint: Color(hex: "F0C936"))
            trendStat(title: "平均\(selectedTrendMetric.rawValue)", value: trendAverage.map { trendValue($0) } ?? "--", symbol: "chart.line.uptrend.xyaxis", tint: Color(hex: "9B8CE4"))
            trendStat(title: selectedTrendMetric == .weight ? "最重" : "最高记录", value: trendMaximum.map { trendValue($0.value) } ?? "--", symbol: "arrow.up", tint: Color(hex: "F0A23A"))
            trendStat(title: selectedTrendMetric == .weight ? "最轻" : "最低记录", value: trendMinimum.map { trendValue($0.value) } ?? "--", symbol: "arrow.down", tint: selectedTrendMetric.accent)
        }
    }

    private func trendStat(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "878D8F"))
                Spacer(minLength: 4)
                Image(systemName: symbol)
                    .font(.appSystem(size: 9, weight: .black))
                    .foregroundColor(tint)
            }
            Text(value)
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "3D4244"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func trendValue(_ value: Double) -> String {
        let format = selectedTrendMetric == .weight ? "%.1f" : "%.0f"
        return "\(String(format: format, value)) \(selectedTrendMetric.unit)"
    }

    private func trendAxisValue(_ value: Double) -> String {
        let format = selectedTrendMetric == .weight ? "%.0f" : "%.0f"
        return "\(String(format: format, value))\(selectedTrendMetric.unit)"
    }

    private func trendAxisDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month).\(day)"
    }

    private func trendFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    @MainActor
    private func loadTrendPoints() async {
        guard !isTrendLoading else { return }
        isTrendLoading = true
        trendLoadFailed = false

        async let weightResult = try? HealthKitManager.shared.fetchDailyBodyMassAverages(days: 3650)
        async let heightResult = try? HealthKitManager.shared.fetchDailyHeightAverages(days: 3650)
        let (weights, heights) = await (weightResult, heightResult)

        if let weights {
            weightTrendPoints = weights.sorted { $0.date < $1.date }
        }
        if let heights {
            heightTrendPoints = heights.sorted { $0.date < $1.date }
        }
        trendLoadFailed = weights == nil && heights == nil
        selectedTrendPointID = visibleTrendPoints.last?.id
        isTrendLoading = false
    }

    private var bodySummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "figure.stand")
                    .font(.appSystem(size: 24, weight: .black))
                    .foregroundColor(Color(hex: "518A52"))
                    .frame(width: 54, height: 54)
                    .background(Theme.Colors.surface.opacity(0.66), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("身体概览")
                        .font(.appSystem(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "263A2A"))
                    Text("记录身高与体重，持续观察身体变化。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "667769"))
                }

                Spacer(minLength: 8)

                Text(bmiLevel)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "3F7648"))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Theme.Colors.surface.opacity(0.72), in: Capsule())
            }

            HStack(spacing: 0) {
                summaryMetric(title: "当前体重", value: String(format: "%.1f", weightKg), unit: "kg")
                Divider().frame(height: 42)
                summaryMetric(title: "目标体重", value: String(format: "%.1f", targetWeightKg), unit: "kg")
                Divider().frame(height: 42)
                summaryMetric(title: "BMI", value: String(format: "%.1f", bmi), unit: bmiLevel)
            }
            .padding(.vertical, 17)
            .background(Theme.Colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .background(
            bodyProfileHeroColor,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .padding(.horizontal, -adaptiveLayout.outerPadding)
        .padding(.top, -10)
    }

    private func summaryMetric(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "929292"))
            Text(value)
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(unit)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "91A08E"))
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.appSystem(size: 14, weight: .black))
                .foregroundColor(Color(hex: "4A7CE8"))
            Text(title)
                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, 6)
    }

    private var bmiPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("身体质量指数")
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "646867"))
                    Text("BMI \(String(format: "%.1f", bmi))")
                        .font(.appSystem(size: 25, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Spacer()

                Text(bmiLevel)
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "4A8B61"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(hex: "DFF3E4"), in: Capsule())
            }

            BodyProfileBMIScale(value: bmi)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(targetSummary)
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "555A58"))
                    Text("按当前身高，BMI 18.5–23.9 对应约 \(String(format: "%.1f", healthyWeightRange.lowerBound))–\(String(format: "%.1f", healthyWeightRange.upperBound)) kg。")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "909492"))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                targetWeightMenu
            }
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        }
        .shadow(color: Color(hex: "84A7D9").opacity(0.10), radius: 18, x: 0, y: 10)
    }

    private var targetWeightMenu: some View {
        Menu {
            Button("设为当前体重") {
                setTargetWeight(weightKg)
            }
            Button("设为健康区间中值") {
                setTargetWeight((healthyWeightRange.lowerBound + healthyWeightRange.upperBound) / 2)
            }
            Button("设为健康区间下限") {
                setTargetWeight(healthyWeightRange.lowerBound)
            }
            Button("设为健康区间上限") {
                setTargetWeight(healthyWeightRange.upperBound)
            }
        } label: {
            Image(systemName: "scope")
                .font(.appSystem(size: 15, weight: .black))
                .foregroundColor(Color(hex: "4A8B61"))
                .frame(width: 42, height: 42)
                .background(Color(hex: "DFF3E4"), in: Circle())
        }
        .accessibilityLabel("快速设置目标体重")
    }

    private func setTargetWeight(_ value: Double) {
        targetWeightKg = min(max((value * 10).rounded() / 10, 30), 180)
    }

    private var saveButton: some View {
        Button {
            guard !isSaving else { return }
            isSaving = true
            Task {
                await onSave(
                    BodyProfileRecord(
                        heightCm: heightCm,
                        weightKg: weightKg,
                        targetWeightKg: targetWeightKg,
                        date: recordDate
                    )
                )
                isSaving = false
            }
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView()
                        .tint(Theme.Colors.onAccent)
                } else {
                    Image(systemName: "checkmark")
                        .font(.appSystem(size: 17, weight: .black))
                }
                Text(isSaving ? "正在保存" : saveButtonTitle)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
            }
            .foregroundColor(Theme.Colors.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color(hex: "4A7CE8"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private var saveButtonTitle: String {
        if Calendar.current.isDateInToday(recordDate) {
            return String(localized: "保存身体档案")
        }
        return "保存 \(recordDate.formatted(.dateTime.locale(Locale.autoupdatingCurrent).month().day())) 记录"
    }
}

private struct BodyProfileBMIScale: View {
    let value: Double

    private var progress: Double {
        min(max((value - 15) / 20, 0), 1)
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        Color(hex: "8EBEE8")
                        Color(hex: "79C58E")
                        Color(hex: "E8BE69")
                        Color(hex: "E78B78")
                    }
                    .clipShape(Capsule())

                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color(hex: "333638"), lineWidth: 3))
                        .offset(x: max(0, min(proxy.size.width - 16, proxy.size.width * progress - 8)))
                }
            }
            .frame(height: 10)

            HStack {
                Text("偏瘦")
                Spacer()
                Text("标准")
                Spacer()
                Text("偏胖")
                Spacer()
                Text("肥胖")
            }
            .font(.appSystem(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "969A98"))
        }
    }
}

private struct BodyProfileRulerControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let tint: Color
    let field: BodyProfileInputField
    let focusedField: FocusState<BodyProfileInputField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                Spacer()

                Text(rangeText)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "969C99"))
            }

            HStack(spacing: 12) {
                adjustmentButton(symbol: "minus", delta: -step, isDisabled: value <= range.lowerBound)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    TextField("数值", value: $value, format: valueFormat)
                        .font(.appSystem(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused(focusedField, equals: field)
                        .frame(maxWidth: 128)
                        .onChange(of: value) { _, newValue in
                            let boundedValue = min(max(newValue, range.lowerBound), range.upperBound)
                            if boundedValue != newValue {
                                value = boundedValue
                            }
                        }

                    Text(unit)
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)

                adjustmentButton(symbol: "plus", delta: step, isDisabled: value >= range.upperBound)
            }

            ZStack(alignment: .top) {
                rulerTicks
                    .frame(height: 38)
                    .padding(.top, 12)

                Image(systemName: "triangle.fill")
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundColor(tint)
                    .rotationEffect(.degrees(180))
                    .offset(y: -2)
            }

            Slider(value: $value, in: range, step: step)
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue("\(valueText) \(unit)")
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        }
        .shadow(color: Color(hex: "84A7D9").opacity(0.08), radius: 12, x: 0, y: 7)
    }

    private var valueText: String {
        step >= 1 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private var valueFormat: FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(step >= 1 ? 0 : 1))
    }

    private var rangeText: String {
        "\(formatted(range.lowerBound))–\(formatted(range.upperBound)) \(unit)"
    }

    private func formatted(_ value: Double) -> String {
        step >= 1 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func adjustmentButton(symbol: String, delta: Double, isDisabled: Bool) -> some View {
        Button {
            let adjusted = min(max(value + delta, range.lowerBound), range.upperBound)
            value = step >= 1 ? adjusted.rounded() : (adjusted * 10).rounded() / 10
        } label: {
            Image(systemName: symbol)
                .font(.appSystem(size: 15, weight: .black))
                .foregroundColor(isDisabled ? Color(hex: "B8BEBA") : tint)
                .frame(width: 44, height: 44)
                .background((isDisabled ? Color(hex: "EEF0EF") : tint.opacity(0.12)), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(symbol == "plus" ? "增加\(title)" : "减少\(title)")
    }

    private var rulerTicks: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<31, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index == 15 ? tint : Color(hex: "D7D7D7"))
                    .frame(width: index == 15 ? 4 : 3, height: index % 10 == 0 ? 28 : (index % 5 == 0 ? 22 : 14))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
