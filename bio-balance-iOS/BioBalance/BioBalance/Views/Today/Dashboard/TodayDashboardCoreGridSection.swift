/// TodayDashboardCoreGridSection 由 DashboardView 调用，作为「今日核心网格」区块组件。
/// 负责排列身体电量、专注力、压力、最大摄氧量等混合卡片并处理点击跳转。

import SwiftUI
import OSLog

/// 今日仪表盘CoreGrid区块组件 作为今日页里的布局区块组件。
/// 负责展示今天页顶部混合网格卡片。
struct TodayDashboardCoreGridSection: View {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "TodaySignals")
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Bindable var dashboardViewModel: DashboardViewModel
    let bodyBatteryValue: Int?
    let focusCapacityValue: Int?
    let bodyBatteryTrendPoints: [TimeSeriesPoint]
    let focusCapacityTrendPoints: [TimeSeriesPoint]
    let vo2MaxText: String
    let pressureSignalHintText: String
    let vo2MaxSignalHintText: String
    let onTapPressure: () -> Void
    let onTapBodyBattery: () -> Void
    let onTapFocusCapacity: () -> Void
    let onTapVO2Max: () -> Void

    private var gridColumns: [GridItem] {
        let columnCount = adaptiveLayout.usesExpandedLayout ? max(1, adaptiveLayout.rootGridColumnCount) : 2
        return Array(
            repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
            count: columnCount
        )
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            Button(action: onTapPressure) {
                pressureReferenceCard
            }
            .todayCardButtonStyle()

            Button(action: onTapBodyBattery) {
                bodyBatteryReferenceCard
            }
            .todayCardButtonStyle()

            Button(action: onTapFocusCapacity) {
                focusCapacityReferenceCard
            }
            .todayCardButtonStyle()

            Button(action: onTapVO2Max) {
                vo2MaxReferenceCard
            }
            .todayCardButtonStyle()
        }
        .onAppear {
            logSignalAvailability(operation: "pageEnter")
        }
        .onChange(of: signalAvailabilityKey) { _, _ in
            logSignalAvailability(operation: "stateChange")
        }
    }
}

private extension TodayDashboardCoreGridSection {
    var signalAvailabilityKey: String {
        [
            bodyBatteryValue == nil ? "bodyBattery:unavailable" : "bodyBattery:available",
            focusCapacityValue == nil ? "focusCapacity:unavailable" : "focusCapacity:available",
            dashboardViewModel.vo2MaxAssessment == nil ? "vo2Max:unavailable" : "vo2Max:available",
            dashboardViewModel.cardStressAssessment.unavailableReason?.rawValue ?? "stress:available",
            dashboardViewModel.cardStressSource,
            "bodyBatteryPoints:\(bodyBatteryTrendPoints.count)",
            "focusCapacityPoints:\(focusCapacityTrendPoints.count)"
        ].joined(separator: "|")
    }

    func logSignalAvailability(operation: String) {
        let stressReason = dashboardViewModel.cardStressAssessment.unavailableReason?.rawValue ?? "none"
        let stressSource = dashboardViewModel.cardStressSource
        let stressAvailable = dashboardViewModel.cardStressAssessment.hasData
        let bodyBatteryAvailable = bodyBatteryValue != nil
        let bodyBatteryPointCount = bodyBatteryTrendPoints.count
        let focusCapacityAvailable = focusCapacityValue != nil
        let focusCapacityPointCount = focusCapacityTrendPoints.count
        let vo2MaxAvailable = dashboardViewModel.vo2MaxAssessment != nil
        Self.logger.info(
            "[Today][BodySignals] operation=\(operation, privacy: .public) stressSource=\(stressSource, privacy: .public) stressAvailable=\(stressAvailable, privacy: .public) stressReason=\(stressReason, privacy: .public) bodyBatteryAvailable=\(bodyBatteryAvailable, privacy: .public) bodyBatteryPointCount=\(bodyBatteryPointCount, privacy: .public) focusCapacityAvailable=\(focusCapacityAvailable, privacy: .public) focusCapacityPointCount=\(focusCapacityPointCount, privacy: .public) vo2MaxAvailable=\(vo2MaxAvailable, privacy: .public)"
        )
    }

    var pressureReferenceCard: some View {
        let style = StressVisualStyle.style(for: dashboardViewModel.cardStressAssessment.band)

        return GeometryReader { proxy in
            let scale = cardScale(for: proxy.size.width)

            VStack(alignment: .leading, spacing: scaled(12, by: scale)) {
                headerRow(
                    title: "综合压力",
                    tint: style.accentColor,
                    symbol: "gauge.with.dots.needle.50percent",
                    scale: scale
                )

                Text(normalizedPressureValueText)
                    .font(.appSystem(size: scaled(34, by: scale), weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                pressurePulsePreview(scale: scale)
                    .frame(height: scaled(30, by: scale))
            }
            .padding(.horizontal, scaled(14, by: scale))
            .padding(.vertical, scaled(12, by: scale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .aspectRatio(1.12, contentMode: .fit)
        .todayCardSurface(tint: style.accentColor)
    }

    var bodyBatteryReferenceCard: some View {
        let cardTint = bodyBatteryTint
        return GeometryReader { proxy in
            let scale = cardScale(for: proxy.size.width)

            VStack(alignment: .leading, spacing: scaled(12, by: scale)) {
                headerRow(
                    title: "身体电量",
                    tint: cardTint,
                    symbol: bodyBatterySymbol,
                    scale: scale
                )

                if let bodyBatteryValue = Int(normalizedBodyBatteryText) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(bodyBatteryValue)")
                            .font(.appSystem(size: scaled(34, by: scale), weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(localizedPercentSymbol)
                            .font(.appSystem(size: scaled(34, by: scale), weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                } else {
                    Text("--")
                        .font(.appSystem(size: scaled(34, by: scale), weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                bodyBatteryTrendPreview(tint: cardTint, scale: scale)
                    .frame(height: scaled(30, by: scale))
            }
            .padding(.horizontal, scaled(14, by: scale))
            .padding(.vertical, scaled(12, by: scale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .aspectRatio(1.12, contentMode: .fit)
        .todayCardSurface(tint: cardTint)
    }

    var focusCapacityReferenceCard: some View {
        let cardTint = focusCapacityTint
        return GeometryReader { proxy in
            let scale = cardScale(for: proxy.size.width)

            VStack(alignment: .leading, spacing: scaled(12, by: scale)) {
                headerRow(
                    title: "专注能力",
                    tint: cardTint,
                    symbol: "scope",
                    scale: scale
                )

                if let focusCapacityValue = Int(normalizedFocusCapacityText) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(focusCapacityValue)")
                            .font(.appSystem(size: scaled(34, by: scale), weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(localizedPercentSymbol)
                            .font(.appSystem(size: scaled(34, by: scale), weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                } else {
                    Text("--")
                        .font(.appSystem(size: scaled(34, by: scale), weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                focusCapacityTrendPreview(tint: cardTint, scale: scale)
                    .frame(height: scaled(30, by: scale))
            }
            .padding(.horizontal, scaled(14, by: scale))
            .padding(.vertical, scaled(12, by: scale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .aspectRatio(1.12, contentMode: .fit)
        .todayCardSurface(tint: cardTint)
    }

    var vo2MaxReferenceCard: some View {
        let cardTint = vo2MaxTint
        return GeometryReader { proxy in
            let scale = cardScale(for: proxy.size.width)

            VStack(alignment: .leading, spacing: scaled(12, by: scale)) {
                headerRow(
                    title: "心肺能力",
                    tint: cardTint,
                    symbol: "lungs.fill",
                    scale: scale
                )

                HStack(alignment: .firstTextBaseline, spacing: scaled(3, by: scale)) {
                    Text(normalizedVO2MaxText)
                        .font(.appSystem(size: scaled(34, by: scale), weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if normalizedVO2MaxText != "--" {
                        Text("ml/kg/min")
                            .font(.appSystem(size: scaled(12, by: scale), weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }

                vo2MaxTrendPreview(tint: cardTint, scale: scale)
                    .frame(height: scaled(30, by: scale))
            }
            .padding(.horizontal, scaled(14, by: scale))
            .padding(.vertical, scaled(12, by: scale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .aspectRatio(1.12, contentMode: .fit)
        .todayCardSurface(tint: vo2MaxTint)
    }

    func headerRow(title: String, tint: Color, symbol: String, scale: CGFloat) -> some View {
        HStack(alignment: .center, spacing: scaled(10, by: scale)) {
            HStack(spacing: scaled(6, by: scale)) {
                Image(systemName: symbol)
                    .font(.appSystem(size: scaled(12, by: scale), weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: scaled(26, by: scale), height: scaled(26, by: scale))
                    .bbTintedChip(
                        tint: tint,
                        in: RoundedRectangle(cornerRadius: scaled(9, by: scale), style: .continuous),
                        tintOpacity: 0.10
                    )

                Text(title)
                    .font(.appSystem(size: scaled(15, by: scale), weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            chevronBadge(scale: scale)
        }
    }

    func chevronBadge(scale: CGFloat) -> some View {
        Image(systemName: Theme.Icons.chevronRight)
            .font(.appSystem(size: scaled(11, by: scale), weight: .bold))
            .foregroundColor(Color(hex: "9FAAB9"))
            .frame(width: scaled(22, by: scale), height: scaled(22, by: scale))
    }

    var normalizedPressureValueText: String {
        let value = dashboardViewModel.cardStressAssessment.valueText
        return value == "—" ? "--" : value
    }

    var normalizedVO2MaxText: String {
        vo2MaxText == "—" ? "--" : vo2MaxText
    }

    var normalizedBodyBatteryText: String {
        guard let value = bodyBatteryValue else { return "--" }
        return "\(value)"
    }

    var normalizedFocusCapacityText: String {
        guard let value = focusCapacityValue else { return "--" }
        return "\(value)"
    }

    /// 从本地化百分比字符串中剥离数字，仅保留百分号符号（保持 locale 一致）。
    var localizedPercentSymbol: String {
        localizedPercent(0).replacingOccurrences(of: "0", with: "")
    }

    var bodyBatterySymbol: String {
        guard let value = bodyBatteryValue else { return "battery.0percent" }
        switch value {
        case 80...:
            return "battery.100percent"
        case 55..<80:
            return "battery.75percent"
        case 30..<55:
            return "battery.50percent"
        case 12..<30:
            return "battery.25percent"
        default:
            return "battery.0percent"
        }
    }

    var bodyBatteryTint: Color {
        guard let value = bodyBatteryValue else { return Color(hex: "9FAAB9") }
        switch value {
        case 55...:
            return Color(hex: "2FBF8F")
        case 30..<55:
            return Color(hex: "A56A24")
        default:
            return Color(hex: "E36A5C")
        }
    }

    var focusCapacityTint: Color {
        guard let value = focusCapacityValue else { return Color(hex: "9FAAB9") }
        switch StressFocusCapacityEngine.band(for: value) {
        case .strong:
            return Color(hex: "6B83E8")
        case .available:
            return Color(hex: "2FBF8F")
        case .limited:
            return Color(hex: "A56A24")
        case .depleted:
            return Color(hex: "E36A5C")
        case .unavailable:
            return Color(hex: "9FAAB9")
        }
    }

    var vo2MaxTint: Color {
        guard let level = dashboardViewModel.vo2MaxAssessment?.fitnessLevel else {
            return Color(hex: "9FAAB9")
        }
        switch level {
        case .excellent, .good:
            return Color(hex: "2FBF8F")
        case .average:
            return Color(hex: "A56A24")
        case .belowAverage, .poor:
            return Color(hex: "E36A5C")
        }
    }

    @ViewBuilder
    func pressurePulsePreview(scale: CGFloat) -> some View {
        let values = pressureTrendValues
        AnimatedSignalBars(
            values: values,
            colors: values.map(pressurePreviewColor),
            signature: previewSignature(values: values.map(Double.init)),
            spacing: scaled(2.5, by: scale),
            minimumHeight: scaled(3, by: scale)
        )
    }

    var pressureTrendValues: [CGFloat] {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: dashboardViewModel.selectedDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay.addingTimeInterval(86_400)
        let daySamples = (dashboardViewModel.history?.stressPoints ?? []).filter {
            $0.value > 0 && $0.date >= selectedDay && $0.date < dayEnd
        }
        let grouped = Dictionary(grouping: daySamples) { $0.timestamp / 1_800 }
        var values = grouped.keys.sorted().compactMap { bucket -> Int? in
            guard let samples = grouped[bucket], !samples.isEmpty else { return nil }
            return Int((Double(samples.map(\.value).reduce(0, +)) / Double(samples.count)).rounded())
        }

        if let selectedScore = dashboardViewModel.cardStressAssessment.score,
           selectedScore > 0,
           values.isEmpty {
            values.append(selectedScore)
        }

        return values.suffix(18).map { CGFloat(max(0, min(100, $0))) }
    }

    func pressurePreviewColor(for value: CGFloat) -> Color {
        // 与 StressBand 色调体系对齐
        switch value {
        case ..<30:
            return Color(hex: "34C759") // relaxed: 绿色
        case 30..<50:
            return Color(hex: "007F79") // steady: 青色
        case 50..<70:
            return Color(hex: "FF9F0A") // mild: 橙色
        case 70..<85:
            return Color(hex: "FF7A00") // caution: 深橙
        default:
            return Color(hex: "D70015") // high: 红色
        }
    }

    @ViewBuilder
    func bodyBatteryTrendPreview(tint: Color, scale: CGFloat) -> some View {
        let source = Array(bodyBatteryTrendPoints.suffix(18))
        AnimatedSignalLine(
            points: previewPoints(values: source.map { Double($0.value) }),
            signature: previewSignature(values: source.map { Double($0.value) }),
            tint: tint,
            lineWidth: scaled(2.1, by: scale),
            pointDiameter: scaled(6, by: scale),
            endpointDiameter: scaled(8, by: scale)
        )
    }

    @ViewBuilder
    func focusCapacityTrendPreview(tint: Color, scale: CGFloat) -> some View {
        let source = Array(focusCapacityTrendPoints.suffix(18))
        AnimatedSignalLine(
            points: previewPoints(values: source.map { Double($0.value) }),
            signature: previewSignature(values: source.map { Double($0.value) }),
            tint: tint,
            lineWidth: scaled(2.1, by: scale),
            pointDiameter: scaled(6, by: scale),
            endpointDiameter: scaled(8, by: scale)
        )
    }

    @ViewBuilder
    func vo2MaxTrendPreview(tint: Color, scale: CGFloat) -> some View {
        let source = VO2MaxRules.assessmentsInDashboardRollingWeek(
            onOrBefore: dashboardViewModel.selectedDate,
            in: dashboardViewModel.vo2MaxHistory
        )
        AnimatedSignalLine(
            points: previewPoints(values: source.map(\.value)),
            signature: previewSignature(values: source.map(\.value)),
            tint: tint,
            lineWidth: scaled(2.1, by: scale),
            pointDiameter: scaled(6, by: scale),
            endpointDiameter: scaled(8, by: scale)
        )
    }

    func previewPoints(values: [Double]) -> [CGPoint] {
        guard let minimum = values.min(), let maximum = values.max() else { return [] }
        let range = maximum - minimum
        return values.enumerated().map { index, value in
            let x = values.count > 1 ? 0.04 + 0.92 * CGFloat(index) / CGFloat(values.count - 1) : 0.5
            let normalized = range > 0.01 ? CGFloat((value - minimum) / range) : 0.5
            let y = 0.72 - normalized * 0.48
            return CGPoint(x: x, y: y)
        }
    }

    func previewSignature(values: [Double]) -> String {
        values.map { String(format: "%.3f", $0) }.joined(separator: "|")
    }

    func cardScale(for width: CGFloat) -> CGFloat {
        let raw = width / 180
        return min(max(raw, 0.84), 1.08)
    }

    func scaled(_ value: CGFloat, by scale: CGFloat) -> CGFloat {
        value * scale
    }

    func signalCard(
        title: String,
        value: String,
        subtitle: String,
        tint: Color,
        symbol: String
    ) -> some View {
        cardShell(tint: tint) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 30, height: 30)
                    .bbTintedChip(tint: tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous), tintOpacity: 0.09)

                Spacer(minLength: 0)

                chevronBadge
            }

            Text(title)
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            Text(value)
                .font(.appSystem(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func summaryCard(
        title: String,
        value: String,
        subtitle: String,
        tint: Color,
        symbol: String,
        badge: String,
        tags: [String]
    ) -> some View {
        cardShell(tint: tint) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 34, height: 34)
                    .bbTintedChip(tint: tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous), tintOpacity: 0.09)

                Spacer(minLength: 0)

                Text(badge)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .bbTintedChip(tint: tint, in: Capsule(), tintOpacity: 0.06)
            }

            Text(title)
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            Text(value)
                .font(.appSystem(size: adaptiveLayout.usesExpandedLayout ? 24 : 22, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(Array(tags.filter { !$0.isEmpty }.prefix(2).enumerated()), id: \.offset) { _, tag in
                    Text(tag)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .bbTintedChip(tint: tint, in: Capsule(), tintOpacity: 0.05)
                }

                Spacer(minLength: 0)

                chevronBadge
            }
        }
    }

    func cardShell<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: adaptiveLayout.usesExpandedLayout ? 156 : 146, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.72), tint.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .bbTintedSurface(tint: tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous), tintStrength: 0.06)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    var chevronBadge: some View {
        Image(systemName: Theme.Icons.chevronRight)
            .font(.appSystem(size: 12, weight: .bold))
            .foregroundColor(Theme.Colors.textTertiary)
            .frame(width: 24, height: 24)
    }
}

/// Owns its drawing progress so asynchronous updates to one card do not reset
/// or skip the other cards' animations.
private struct SignalPreviewEmptyState: View {
    var body: some View {
        Text("等待样本")
            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct AnimatedSignalLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var hasAnimated = false

    let points: [CGPoint]
    let signature: String
    let tint: Color
    let lineWidth: CGFloat
    let pointDiameter: CGFloat
    let endpointDiameter: CGFloat

    private var displayedProgress: CGFloat { reduceMotion ? 1 : progress }
    private var animationID: String { "\(reduceMotion)|\(signature)" }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            if points.isEmpty {
                SignalPreviewEmptyState()
            } else if let point = points.first, points.count == 1 {
                Circle()
                    .fill(tint.opacity(0.72))
                    .frame(width: endpointDiameter, height: endpointDiameter)
                    .position(x: point.x * size.width, y: point.y * size.height)
                    .scaleEffect(displayedProgress)
                    .opacity(displayedProgress)
            } else {
                ZStack {
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                        for point in points.dropFirst() {
                            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                        }
                    }
                    .trim(from: 0, to: displayedProgress)
                    .stroke(
                        tint.opacity(0.68),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )

                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        let isEndpoint = index == points.count - 1
                        Circle()
                            .fill(isEndpoint ? tint : Theme.Colors.surface)
                            .frame(
                                width: isEndpoint ? endpointDiameter : pointDiameter,
                                height: isEndpoint ? endpointDiameter : pointDiameter
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        tint.opacity(isEndpoint ? 0 : 0.7),
                                        lineWidth: max(1, lineWidth * 0.75)
                                    )
                            )
                            .position(x: point.x * size.width, y: point.y * size.height)
                            .opacity(displayedProgress)
                    }
                }
            }
        }
        .task(id: animationID) {
            await restartAnimation(hasData: !points.isEmpty)
        }
    }

    @MainActor
    private func restartAnimation(hasData: Bool) async {
        guard hasData else {
            progress = 1
            return
        }
        guard !reduceMotion else {
            progress = 1
            hasAnimated = true
            return
        }
        guard !hasAnimated else {
            progress = 1
            return
        }
        hasAnimated = true
        progress = 0
        try? await Task.sleep(for: MotionTokens.chartDrawDelay)
        guard !Task.isCancelled else { return }
        withAnimation(MotionTokens.chartDrawAnimation) {
            progress = 1
        }
    }
}

private struct AnimatedSignalBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var hasAnimated = false

    let values: [CGFloat]
    let colors: [Color]
    let signature: String
    let spacing: CGFloat
    let minimumHeight: CGFloat

    private var displayedProgress: CGFloat { reduceMotion ? 1 : progress }
    private var animationID: String { "\(reduceMotion)|\(signature)" }

    var body: some View {
        GeometryReader { geometry in
            if values.isEmpty {
                SignalPreviewEmptyState()
            } else {
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        Capsule()
                            .fill(colors.indices.contains(index) ? colors[index] : Theme.Colors.textTertiary)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: minimumHeight,
                                maxHeight: max(minimumHeight, geometry.size.height * value / 100)
                            )
                            .opacity(index == values.count - 1 ? 1 : 0.82)
                            .scaleEffect(y: displayedProgress, anchor: .bottom)
                    }
                }
            }
        }
        .task(id: animationID) {
            await restartAnimation(hasData: !values.isEmpty)
        }
    }

    @MainActor
    private func restartAnimation(hasData: Bool) async {
        guard hasData else {
            progress = 1
            return
        }
        guard !reduceMotion else {
            progress = 1
            hasAnimated = true
            return
        }
        guard !hasAnimated else {
            progress = 1
            return
        }
        hasAnimated = true
        progress = 0
        try? await Task.sleep(for: MotionTokens.chartDrawDelay)
        guard !Task.isCancelled else { return }
        withAnimation(MotionTokens.chartDrawAnimation) {
            progress = 1
        }
    }
}
