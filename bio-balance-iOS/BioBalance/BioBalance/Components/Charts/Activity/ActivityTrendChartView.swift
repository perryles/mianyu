import SwiftUI
import Charts

extension ActivityTrendMetric {
    var tint: Color {
        switch self {
        case .steps: return Theme.Colors.mintGreen
        case .exercise: return Color(hex: "5E5CE6")
        case .energy: return Color(hex: "FF9F0A")
        case .stand: return Color(hex: "73C8E8")
        case .speed: return Color(hex: "007F79")
        }
    }
}

/// Activity视图 由上级页面或路由调用，作为活动模块里的界面或内容组件。
/// 负责活动数据展示与分析。
struct ActivityTrendChartView: View {
    let steps: [TimeSeriesPointDouble]
    let activeEnergy: [TimeSeriesPointDouble]
    let exerciseMinutes: [TimeSeriesPointDouble]
    let standHours: [TimeSeriesPointDouble]
    let walkingSpeed: [TimeSeriesPointDouble]

    @State private var selectedMetric: ActivityTrendMetric = .steps
    @State private var selectedRange: Int = 7
    @State private var selectedDate: Date?

    private var displayedPoints: [ActivityTrendReading] {
        let source: [TimeSeriesPointDouble]
        switch selectedMetric {
        case .steps:
            source = steps
        case .exercise:
            source = exerciseMinutes
        case .energy:
            source = activeEnergy
        case .stand:
            source = standHours
        case .speed:
            source = walkingSpeed
        }
        let domain = dateDomain
        return ActivityTrendData.prepare(
            source.map { ActivityTrendReading(timestamp: $0.timestamp, value: $0.value) },
            metric: selectedMetric, domain: domain
        )
    }

    private var dateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = Date()
        let todayStart = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -(selectedRange - 1), to: todayStart) ?? todayStart
        return start...end
    }

    private var averageValue: Double? {
        guard !displayedPoints.isEmpty else { return nil }
        return displayedPoints.map(\.value).reduce(0, +) / Double(displayedPoints.count)
    }

    private var peakValue: Double? {
        displayedPoints.map(\.value).max()
    }

    private var selectedPoint: ActivityTrendReading? {
        guard let selectedDate else { return displayedPoints.last }
        return ActivityTrendData.selected(on: selectedDate, in: displayedPoints)
    }

    private var yDomain: ClosedRange<Double> {
        ActivityTrendData.yDomain(displayedPoints, metric: selectedMetric)
    }

    private var plotDateDomain: ClosedRange<Date> {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dateDomain.upperBound)) ?? dateDomain.upperBound
        return dateDomain.lowerBound...end
    }

    private var shortSelectedSummary: String {
        if let selectedDate, selectedPoint == nil {
            return String(localized: "\(selectedDateText(for: selectedDate)) · 该日暂无数据")
        }
        guard let selectedPoint else { return "长按 0.25 秒后拖动图表，可查看某一天的具体数据" }
        return "\(selectedDateText(for: selectedPoint.date)) · \(formatted(selectedPoint.value)) \(selectedMetric.unit)"
    }

    private var chartSummaryText: String {
        if selectedDate != nil, selectedPoint == nil {
            return String(localized: "所选日期没有记录；不会使用邻近日期代替，也不会将缺失值计为零。")
        }
        guard let selectedPoint else {
            switch selectedMetric {
            case .steps:
                return String(localized: "步数更适合看连续几天的节奏，而不是只看某一天高一点还是低一点。")
            case .exercise:
                return String(localized: "锻炼分钟数更适合配合恢复状态一起看，判断负荷是否稳定。")
            case .energy:
                return String(localized: "活动能量可以帮助理解你最近几天的总体消耗强度。")
            case .stand:
                return String(localized: "站立小时更适合判断久坐有没有被打断，连续性通常比单天峰值更重要。")
            case .speed:
                return String(localized: "步速更接近日常状态，适合结合步数和锻炼时间一起读。")
            }
        }
        return selectedDescription(for: selectedPoint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("活动趋势")
                            .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        ActivityProBadge()
                    }
                    Text("来自健康 App 的近期记录")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Picker("", selection: $selectedRange) {
                    Text("7天").tag(7)
                    Text("30天").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            metricPicker

            HStack(spacing: 10) {
                statChip(title: "均值", value: formatted(averageValue), unit: selectedMetric.unit)
                statChip(title: "峰值", value: formatted(peakValue), unit: selectedMetric.unit)
            }

            Text(String(localized: "均值仅基于 \(displayedPoints.count) 条记录，缺失日期不补零。"))
                .font(.appSystem(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            selectionSummaryRow

            if displayedPoints.isEmpty {
                emptyChart
            } else {
                activityChart

                if let selectedPoint {
                    selectedDetailCard(for: selectedPoint)
                }
            }

            Text(chartSummaryText)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(selectedMetric.tint.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 16, x: 0, y: 8)
        .onChange(of: selectedMetric) { _, _ in selectedDate = nil }
        .onChange(of: selectedRange) { _, _ in selectedDate = nil }
    }

    private var selectionSummaryRow: some View {
        HStack(spacing: 8) {
            Text(selectedDate == nil ? String(localized: "最新记录") : String(localized: "已选中"))
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(selectedMetric.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selectedMetric.tint.opacity(0.12), in: Capsule())

            Text(shortSelectedSummary)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activityChart: some View {
        ActivityTrendPlot(
            displayedPoints: displayedPoints, selectedMetric: selectedMetric,
            selectedRange: selectedRange, plotDateDomain: plotDateDomain,
            yDomain: yDomain, selectedDate: $selectedDate
        )
    }

    private var metricPicker: some View {
        HStack(spacing: 8) {
            ForEach(ActivityTrendMetric.allCases) { metric in
                Button {
                    selectedMetric = metric
                } label: {
                    Text(LocalizedStringKey(metric.rawValue))
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(selectedMetric == metric ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            selectedMetric == metric ? metric.tint.opacity(0.18) : Color.black.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedMetric == metric ? .isSelected : [])
            }
        }
    }

    private func statChip(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(unit)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(selectedMetric.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var emptyChart: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.appSystem(size: 28, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("当前区间暂无\(selectedMetric.rawValue)记录")
                .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }



    private func selectedDetailCard(for point: ActivityTrendReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(selectedDateText(for: point.date))
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("活动记录")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text("\(formatted(point.value)) \(selectedMetric.unit)")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(selectedMetric.tint)
            }

            Text(selectedDescription(for: point))
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [selectedMetric.tint.opacity(0.12), Theme.Colors.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func selectedDescription(for point: ActivityTrendReading) -> String {
        let dateText = selectedDateText(for: point.date)
        let valueText = "\(formatted(point.value)) \(selectedMetric.unit)"
        switch selectedMetric {
        case .steps:
            if point.value >= 10000 {
                return String(localized: "\(dateText) 一共走了 \(valueText)，这一天的活动量已经很完整，更适合作为本周活跃高点来读。")
            }
            return String(localized: "\(dateText) 一共走了 \(valueText)，步数更适合结合前后几天一起看，判断最近整体活动节奏。")
        case .exercise:
            if point.value >= 30 {
                return String(localized: "\(dateText) 记录了 \(valueText) 锻炼，这种训练日更适合结合恢复和睡眠一起判断负荷。")
            }
            return String(localized: "\(dateText) 记录了 \(valueText) 锻炼，更像是轻量活动日，适合继续补足连续性。")
        case .energy:
            return String(localized: "\(dateText) 活动消耗约 \(valueText)，它能帮助理解这一天整体身体负荷大概落在什么区间。")
        case .stand:
            return String(localized: "\(dateText) 的站立记录为 \(valueText)；它统计有站立活动的小时数，并非累计站立时长。")
        case .speed:
            return String(localized: "\(dateText) 平均步速约 \(valueText)，步速更适合和步数、锻炼时间一起判断这天的活动质量。")
        }
    }

    private func selectedDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }



    private func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        switch selectedMetric {
        case .steps, .exercise, .energy, .stand:
            return String(format: "%.0f", value)
        case .speed:
            return String(format: "%.1f", value)
        }
    }
}

#Preview {
    let now = Date()
    let points = (0..<30).map { index in
        TimeSeriesPointDouble(timestamp: Int64((Calendar.current.date(byAdding: .day, value: -29 + index, to: now) ?? now).timeIntervalSince1970), value: Double(3000 + index * 160))
    }
    ActivityTrendChartView(steps: points, activeEnergy: points.map { TimeSeriesPointDouble(timestamp: $0.timestamp, value: $0.value / 18) }, exerciseMinutes: points.map { TimeSeriesPointDouble(timestamp: $0.timestamp, value: $0.value / 240) }, standHours: points.map { TimeSeriesPointDouble(timestamp: $0.timestamp, value: Double(6 + (Int($0.value) / 800) % 7)) }, walkingSpeed: points.map { TimeSeriesPointDouble(timestamp: $0.timestamp, value: 1.1) })
        .padding()
}
