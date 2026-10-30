/// WorkoutAnalysisSection 为单次训练渲染深度分析：海拔爬升曲线、最高/累计爬升指标，
/// 以及分段表（按公里或 5 分钟，含配速、段内爬升与平均心率）。
///
/// 数据全部来自 HealthKit 原始样本的本机计算；样本不足时各区块独立降级为说明文案，
/// 不使用估算值补位。

import SwiftUI
import Charts

struct WorkoutAnalysisSection: View {
    let report: WorkoutAnalysisReport
    let accent: Color

    @State private var selectedElevation: WorkoutElevationSample?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if report.hasElevation {
                elevationCard
            }
            if report.hasSplits {
                splitsCard
            }
        }
    }

    // MARK: 海拔

    private var elevationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label(String(localized: "爬升高度"), systemImage: "mountain.2.fill")
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                if let peak = selectedElevation ?? report.elevationProfile.max(by: { $0.elevationMeters < $1.elevationMeters }) {
                    Text(elevationReadout(peak))
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.10), in: Capsule())
                }
            }

            Chart(report.elevationProfile) { sample in
                AreaMark(
                    x: .value("时间", sample.offset),
                    y: .value("海拔", sample.elevationMeters)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.32), accent.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("时间", sample.offset),
                    y: .value("海拔", sample.elevationMeters)
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.catmullRom)

                if let selectedElevation {
                    RuleMark(x: .value("时间", selectedElevation.offset))
                        .foregroundStyle(accent.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(
                        x: .value("时间", selectedElevation.offset),
                        y: .value("海拔", selectedElevation.elevationMeters)
                    )
                    .foregroundStyle(accent)
                    .symbolSize(26)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(BBChartStyle.grid)
                    AxisValueLabel {
                        if let offset = value.as(TimeInterval.self) {
                            Text(Self.clockText(offset))
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(BBChartStyle.grid)
                    AxisValueLabel {
                        if let meters = value.as(Double.self) {
                            Text(Self.meterText(meters))
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectedElevation = nearestSample(at: value.location, proxy: proxy, in: geometry)
                                }
                                .onEnded { _ in
                                    selectedElevation = nil
                                }
                        )
                }
            }
            .frame(height: 148)
            .accessibilityLabel(String(localized: "训练海拔曲线"))

            if let maxElevation = report.maxElevationMeters {
                elevationStatRow(
                    String(localized: "最高海拔"),
                    value: Self.meterText(maxElevation)
                )
            }
            if let ascent = report.totalAscentMeters, ascent > 0 {
                elevationStatRow(
                    String(localized: "累计爬升"),
                    value: Self.meterText(ascent)
                )
            }
        }
        .modifier(LiquidGlassCardModifier(accent: accent))
    }

    private func elevationReadout(_ sample: WorkoutElevationSample) -> String {
        let relative = max(0, sample.elevationMeters)
        return String(localized: "\(Self.clockText(sample.offset)) · \(Self.meterText(relative))")
    }

    private func elevationStatRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: "arrow.up.right")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }

    private func nearestSample(
        at point: CGPoint,
        proxy: ChartProxy,
        in geometry: GeometryProxy
    ) -> WorkoutElevationSample? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let originX = geometry[plotFrame].origin.x
        let width = geometry[plotFrame].width
        guard width > 0, let first = report.elevationProfile.first, let last = report.elevationProfile.last else {
            return nil
        }
        let fraction = min(max((point.x - originX) / width, 0), 1)
        let targetOffset = first.offset + (last.offset - first.offset) * fraction
        return report.elevationProfile.min { abs($0.offset - targetOffset) < abs($1.offset - targetOffset) }
    }

    // MARK: 分段

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label(String(localized: "分段"), systemImage: "list.number")
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(splitScopeText)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            // 表头
            HStack(spacing: 12) {
                Text(splitIndexHeader)
                    .frame(width: 34, alignment: .leading)
                Text(String(localized: "配速"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(localized: "爬升"))
                    .frame(width: 62, alignment: .trailing)
                Text(String(localized: "BPM"))
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)

            ForEach(Array(report.splits.enumerated()), id: \.element.id) { index, split in
                splitRow(split)
                if index < report.splits.count - 1 {
                    Divider()
                        .foregroundStyle(FitnessVisualStyle.divider.opacity(0.7))
                }
            }

            Text(splitFootnote)
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(LiquidGlassCardModifier(accent: accent))
    }

    private var splitScopeText: String {
        switch report.splitKind {
        case .distance: return String(localized: "每公里")
        case .time: return String(localized: "每 5 分钟")
        }
    }

    private var splitIndexHeader: String {
        report.splitKind == .distance ? String(localized: "公里") : String(localized: "时段")
    }

    private var splitFootnote: String {
        let hasMissingPace = report.splits.contains { $0.paceSecondsPerKilometer == nil }
        if hasMissingPace {
            return String(localized: "分段距离由轨迹推算，缺失样本的配速保持为空，不做估算。")
        }
        return String(localized: "分段由设备记录的轨迹与心率样本计算，缺失指标保持为空。")
    }

    private func splitRow(_ split: WorkoutSplitSummary) -> some View {
        HStack(spacing: 12) {
            Text(splitLabel(split))
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(width: 34, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                Text(paceText(split))
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(paceColor(split))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if split.paceSecondsPerKilometer != nil {
                    Capsule()
                        .fill(paceColor(split))
                        .frame(width: paceBarWidth(split), height: 5)
                        .background(
                            Capsule().fill(paceColor(split).opacity(0.14))
                        )
                } else {
                    Text(String(localized: "缺样本"))
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(split.elevationGainMeters.map { Self.meterText($0) } ?? "--")
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(split.elevationGainMeters.flatMap { $0 > 0 ? Color(hex: "708D55") : nil } ?? Theme.Colors.textTertiary)
                .frame(width: 62, alignment: .trailing)

            Text(split.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "--")
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(split.averageHeartRate != nil ? Color(hex: "B64A59") : Theme.Colors.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func splitLabel(_ split: WorkoutSplitSummary) -> String {
        report.splitKind == .distance ? "\(split.index)" : Self.clockText(split.duration * Double(split.index - 1))
    }

    private func paceText(_ split: WorkoutSplitSummary) -> String {
        guard let pace = split.paceSecondsPerKilometer else { return "--" }
        return Self.clockText(pace)
    }

    /// 配速条形指示：越快的段填充越满、颜色越暖。以 10:00/km 为最慢、3:00/km 为最快。
    private func paceBarFillRatio(_ pace: TimeInterval) -> Double {
        let clamped = min(max(pace, 180), 600)
        return (600 - clamped) / 420
    }

    private func paceBarWidth(_ split: WorkoutSplitSummary) -> CGFloat {
        guard let pace = split.paceSecondsPerKilometer else { return 0 }
        return CGFloat(28 + paceBarFillRatio(pace) * 18)
    }

    private func paceColor(_ split: WorkoutSplitSummary) -> Color {
        guard let pace = split.paceSecondsPerKilometer else { return Theme.Colors.textTertiary }
        switch pace {
        case ..<300: return Color(hex: "EF6B4D")
        case ..<420: return Color(hex: "4C79D8")
        default: return Color(hex: "526F82")
        }
    }

    // MARK: 格式化

    private static func clockText(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }

    private static func meterText(_ meters: Double) -> String {
        String(localized: "\(Int(meters.rounded())) 米")
    }
}

/// 分析卡容器：iOS 26+ 用 Liquid Glass 玻璃卡承载，旧系统退化为半透明白卡 + 细描边。
/// 与 WorkoutActivityReportView 的 activityReportCardStyle 保持同一padding/圆角量级。
private struct LiquidGlassCardModifier: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .bbLiquidGlassSurface(
                    tint: accent,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                    tintStrength: 0.08
                )
        } else {
            content
                .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(accent.opacity(0.12), lineWidth: 1)
                }
        }
    }
}
