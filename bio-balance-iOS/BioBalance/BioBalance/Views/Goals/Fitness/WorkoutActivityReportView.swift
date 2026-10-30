/// WorkoutActivityReportView 为 HealthKit 已识别的非游泳训练生成运动类型专属报告。
/// 各类型共享眠屿报告结构，但使用对应名称、图标、色彩与训练关注点。

import SwiftUI
import Charts

struct WorkoutActivityReportView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: ActionDayDetailModel
    let kind: WorkoutReportKind

    private var accent: Color { Color(hex: kind.accentHex) }
    private var reportTitle: String {
        kind == .other ? String(localized: "\(model.workoutTitle)报告") : kind.reportTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroCard
            metricsCard
            performanceCard
            trendCard
            sourceNote
        }
    }

    private var heroCard: some View {
        ModernReportHero(
            eyebrow: String(localized: "训练识别报告"),
            title: reportTitle,
            value: heroPrimaryValue,
            unit: heroPrimaryUnit,
            captions: heroCaptions,
            badge: ModernReportBadge(
                symbol: "trophy.fill",
                text: intensityLabel,
                tint: accent
            ),
            accent: accent,
            symbol: kind.symbol
        )
    }

    private var heroCaptions: [ModernReportCaption] {
        var captions = [
            ModernReportCaption(symbol: "calendar", text: model.title),
            ModernReportCaption(symbol: "checkmark.seal.fill", text: model.workoutTitle)
        ]

        if let count = model.workoutCount, count > 1 {
            captions.append(
                ModernReportCaption(
                    symbol: "square.stack.3d.up.fill",
                    text: String(localized: "当日 \(count) 次")
                )
            )
        }
        return captions
    }


    private var metricsCard: some View {
        ModernReportMetricsPanel(
            title: String(localized: "训练数据"),
            metrics: [
                ModernReportMetric(title: String(localized: "运动时间"), value: trainingText, tint: accent),
                ModernReportMetric(title: String(localized: "动态消耗"), value: energyText, tint: Color(hex: "E46E57")),
                showsDistanceMetrics
                    ? ModernReportMetric(title: String(localized: "距离"), value: distanceText, tint: Color(hex: "3A90B7"))
                    : ModernReportMetric(title: String(localized: "训练负荷"), value: loadText, tint: Color(hex: "C45F76")),
                showsDistanceMetrics
                    ? ModernReportMetric(title: performanceMetricTitle, value: performanceMetricText, tint: Color(hex: "5977C9"))
                    : ModernReportMetric(title: String(localized: "恢复状态"), value: recoveryText, tint: Color(hex: "4A9B72")),
                ModernReportMetric(title: String(localized: "当日 HRV"), value: hrvText, tint: Color(hex: "A85C9A")),
                ModernReportMetric(
                    title: String(localized: "当日训练"),
                    value: model.workoutCount.map { String(localized: "\($0) 次") } ?? String(localized: "暂无"),
                    tint: accent
                )
            ]
        )
    }


    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle(focusTitle, symbol: focusSymbol)
                Spacer()
                Text(intensityLabel)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accent.opacity(0.10), in: Capsule())
            }

            Text(focusHeadline)
                .font(.appSystem(size: 23, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(focusDetail)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                scoreTile("训练负荷", value: loadText)
                scoreTile("恢复状态", value: recoveryText)
                scoreTile("完成情况", value: model.distanceKilometers == nil ? trainingText : distanceText)
            }
        }
        .activityReportCardStyle(accent: accent)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("近期节奏", symbol: "chart.xyaxis.line")
                Spacer()
                Text("近 7 天 · 分钟")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if model.trendPoints.isEmpty {
                Text("继续记录训练后，这里会显示本周节奏。")
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                Chart(model.trendPoints) { point in
                    BarMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("分钟", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.52)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(5)
                }
                .frame(height: 170)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(model.trendPoints.count, 5))) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) { Text("\(Int(minutes))") }
                        }
                    }
                }
                .accessibilityLabel("近七天训练时长")
                .accessibilityValue(trendAccessibilityText)
            }
        }
        .activityReportCardStyle(accent: accent)
    }

    private var sourceNote: some View {
        Label(
            sourceNoteText,
            systemImage: "heart.text.square.fill"
        )
        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
        .foregroundColor(Theme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.appSystem(size: 18, weight: .black, design: .rounded))
            .foregroundColor(Theme.Colors.textPrimary)
    }

    private func metric(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.appSystem(size: 15, weight: .black))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(title)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func scoreTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var showsDistanceMetrics: Bool {
        switch kind {
        case .running, .walking, .hiking, .cycling, .rowing, .elliptical: return true
        default: return model.distanceKilometers != nil
        }
    }

    private var metricColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    @ViewBuilder
    private var reportContextLabels: some View {
        Label(model.title, systemImage: "calendar")
        Label(model.workoutTitle, systemImage: "checkmark.seal.fill")
        if let count = model.workoutCount, count > 1 {
            Label("当日 \(count) 次", systemImage: "square.stack.3d.up.fill")
        }
    }

    private var focusTitle: String {
        switch kind {
        case .running, .walking, .hiking: return String(localized: "配速与耐力")
        case .cycling, .rowing, .elliptical: return String(localized: "节奏与输出")
        case .strength, .core: return String(localized: "力量与恢复")
        case .highIntensity: return String(localized: "强度与恢复")
        case .yoga: return String(localized: "练习与恢复")
        case .dance: return String(localized: "节奏与活力")
        case .swimming: return String(localized: "泳姿与效率")
        case .other: return String(localized: "表现与恢复")
        }
    }

    private var focusSymbol: String {
        showsDistanceMetrics ? "speedometer" : "bolt.heart.fill"
    }

    private var focusHeadline: String {
        if showsDistanceMetrics, let distance = model.distanceKilometers {
            return String(localized: "完成 \(String(format: "%.2f", distance)) 公里")
        }
        if let load = model.trainingLoadScore {
            return String(localized: "本次训练负荷 \(load) 分")
        }
        return String(localized: "本次训练已完整记录")
    }

    private var focusDetail: String {
        switch kind {
        case .running, .walking, .hiking:
            return String(localized: "结合距离、配速与近期训练量，观察耐力节奏是否稳定；设备没有写入的指标会保持为空。")
        case .cycling, .rowing, .elliptical:
            return String(localized: "用训练时长、距离和负荷观察输出节奏，并结合恢复分安排下一次训练。")
        case .strength, .core, .highIntensity:
            return String(localized: "力量类训练优先关注训练负荷与恢复状态，距离和配速不作为核心表现指标。")
        case .yoga:
            return String(localized: "瑜伽训练优先关注持续时间与恢复状态，保持稳定练习比追求距离更有意义。")
        case .dance:
            return String(localized: "结合训练时长、动态消耗与恢复状态，观察本次节奏是否适合当前身体状态。")
        case .swimming, .other:
            return model.insightText
        }
    }

    private var intensityLabel: String {
        guard let score = model.trainingLoadScore else { return String(localized: "等待负荷") }
        switch score {
        case 76...: return String(localized: "高负荷")
        case 51...: return String(localized: "中等负荷")
        case 26...: return String(localized: "轻负荷")
        default: return String(localized: "恢复负荷")
        }
    }

    private var durationPrimaryValue: String {
        let value = model.statItems.first(where: { $0.title == "训练" })?.valueText ?? "--"
        return value.split(separator: " ").first.map(String.init) ?? "--"
    }

    private var heroPrimaryValue: String {
        guard showsDistanceMetrics, let distance = model.distanceKilometers else {
            return durationPrimaryValue
        }
        return String(format: distance >= 10 ? "%.1f" : "%.2f", distance)
    }

    private var heroPrimaryUnit: String {
        showsDistanceMetrics && model.distanceKilometers != nil ? String(localized: "公里") : String(localized: "分钟")
    }

    private var performanceMetricTitle: String {
        switch kind {
        case .cycling: return String(localized: "平均速度")
        case .rowing: return String(localized: "500 米配速")
        default: return String(localized: "平均配速")
        }
    }

    private var performanceMetricText: String {
        guard let distance = model.distanceKilometers,
              let minutes = trainingMinutes,
              distance > 0,
              minutes > 0 else { return String(localized: "暂无") }
        switch kind {
        case .cycling:
            return String(format: "%.1f km/h", distance / (minutes / 60))
        case .rowing:
            let secondsPer500Meters = minutes * 60 / (distance * 2)
            return "\(clockText(secondsPer500Meters))/500m"
        default:
            return paceText
        }
    }

    private var trainingMinutes: Double? {
        guard let text = model.statItems.first(where: { $0.title == "训练" })?.valueText,
              let number = text.split(separator: " ").first,
              let value = Double(number) else { return nil }
        return value
    }

    private var sourceNoteText: String {
        if let count = model.workoutCount, count > 1 {
            return String(localized: "报告按当日 \(count) 次训练汇总，运动类型取主要训练；缺失指标不会使用估算值补位。")
        }
        return String(localized: "运动类型与训练数据来自健康 App；缺失指标不会使用估算值补位。")
    }

    private var trendAccessibilityText: String {
        guard let latest = model.trendPoints.last else { return String(localized: "暂无数据") }
        return String(localized: "最近一天 \(Int(latest.value.rounded())) 分钟，共 \(model.trendPoints.count) 天有训练记录")
    }

    private func clockText(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }

    private var trainingText: String { model.statItems.first(where: { $0.title == "训练" })?.valueText ?? "暂无" }
    private var energyText: String { model.statItems.first(where: { $0.title == "消耗" })?.valueText ?? "暂无" }
    private var hrvText: String { model.statItems.first(where: { $0.title == "HRV" })?.valueText ?? "暂无" }
    private var distanceText: String { model.distanceKilometers.map { String(format: "%.2f km", $0) } ?? "暂无" }
    private var paceText: String { model.averagePaceText.map { "\($0)/km" } ?? "暂无" }
    private var loadText: String { model.trainingLoadScore.map { "\($0) 分" } ?? "暂无" }
    private var recoveryText: String { model.recoveryScore.map { "\($0) 分" } ?? "暂无" }
}

private extension View {
    /// iOS 26+ 使用轻玻璃承载新版报告；旧系统保持白卡和彩色细描边。
    @ViewBuilder
    func activityReportCardStyle(accent: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .bbLiquidGlassSurface(
                    tint: accent,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                    tintStrength: 0.08,
                    shadow: false
                )
        } else {
            self
                .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(accent.opacity(0.12), lineWidth: 1)
                }
        }
    }
}
