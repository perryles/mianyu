/// AlertHistoryView 由设置页告警历史入口调用，作为「告警历史」列表页。
/// 负责按分类（全部/心率/压力/睡眠）筛选并展示历史提醒记录。

import SwiftUI
import Charts

/// AlertHistoryView 负责按分类筛选并展示心率、压力和睡眠相关提醒历史。
struct AlertHistoryView: View {
    /// Filter 用于在告警历史页内切换不同类型的提醒记录。
    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case heartRate = "心率"
        case stress = "压力"
        case sleep = "睡眠"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: return String(localized: "全部")
            case .heartRate: return String(localized: "心率")
            case .stress: return String(localized: "压力")
            case .sleep: return String(localized: "睡眠")
            }
        }

        var tint: Color {
            switch self {
            case .all: return Theme.Colors.mintGreen
            case .heartRate: return Color(hex: "FF5A5F")
            case .stress: return Color(hex: "F3A53B")
            case .sleep: return Color(hex: "5B8CFF")
            }
        }

        var systemImage: String {
            switch self {
            case .all: return "bell.badge.fill"
            case .heartRate: return AlertHistoryItem.Kind.heartRate.icon
            case .stress: return AlertHistoryItem.Kind.stress.icon
            case .sleep: return AlertHistoryItem.Kind.sleep.icon
            }
        }
    }

    let focusDate: Date?
    @State private var filter: Filter = .all

    // 告警历史尚未接入真实数据源。为避免把示例数据当作真实健康告警展示，
    // 在数据源就绪前以空数据呈现（空态文案见「告警记录」列表）。
    private let items: [AlertHistoryItem] = []

    init(focusDate: Date? = nil) {
        self.focusDate = focusDate
    }

    private var filteredItems: [AlertHistoryItem] {
        switch filter {
        case .all:
            return items
        case .heartRate:
            return items.filter { $0.kind == .heartRate }
        case .stress:
            return items.filter { $0.kind == .stress }
        case .sleep:
            return items.filter { $0.kind == .sleep }
        }
    }

    private var focusDayItems: [AlertHistoryItem] {
        guard let focusDate else { return [] }
        return items.filter { Calendar.current.isDate($0.date, inSameDayAs: focusDate) }
    }

    private var highRiskCount: Int {
        filteredItems.filter { $0.alertSeverity == .high }.count
    }

    private var recent24hCount: Int {
        let since = Date().addingTimeInterval(-24 * 3600)
        return filteredItems.filter { $0.date >= since }.count
    }

    var body: some View {
        ZStack {
            ReportsSoftBackground()

            AdaptivePageScrollView(style: .reading, topPadding: 18, bottomPadding: 96) {
                VStack(alignment: .leading, spacing: 16) {
                    AlertHistoryHeroCard(
                        totalCount: filteredItems.count,
                        highRiskCount: highRiskCount,
                        recent24hCount: recent24hCount,
                        focusDate: focusDate,
                        focusCount: focusDayItems.count,
                        tint: filter.tint
                    )

                    AlertHistoryFilterCard(filter: $filter, items: items)

                    AlertHistoryOverviewCard(
                        items: filteredItems,
                        focusDate: focusDate
                    )

                    AlertHistoryTrendCard(items: filteredItems)

                    ReportsContentCard(spacing: 14) {
                        ReportsSectionHeader("告警记录", subtitle: recordSubtitle)

                        if filteredItems.isEmpty {
                            ReportsInlineEmptyState(text: "当前筛选下暂无告警记录")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(filteredItems) { item in
                                    AlertHistoryRow(item: item, isFocusDay: isFocusDay(item))
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("告警记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var recordSubtitle: String {
        if let focusDate {
            return String(localized: "已高亮 \(focusDate.reportsShortDateString()) 同日告警，方便和报告详情一起回看。")
        }
        return String(localized: "按时间回看心率、压力和睡眠提醒，并查看对应处理建议。")
    }

    private func isFocusDay(_ item: AlertHistoryItem) -> Bool {
        guard let focusDate else { return false }
        return Calendar.current.isDate(item.date, inSameDayAs: focusDate)
    }
}

private struct AlertHistoryHeroCard: View {
    let totalCount: Int
    let highRiskCount: Int
    let recent24hCount: Int
    let focusDate: Date?
    let focusCount: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("告警记录")
                    .font(.appSystem(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "0F2C57"))

                Text("把异常提醒、风险层级和处理建议整理成可复盘的报告视图。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "50627E"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(heroBadge)
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: Capsule())

                        Text(heroHeadline)
                            .font(.appSystem(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "0F2347"))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(heroDetail)
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 6) {
                        Text("\(totalCount)")
                            .font(.appSystem(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("记录")
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "62738D"))
                    }
                    .frame(width: 96, height: 112)
                    .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
                    )
                }

                HStack(spacing: 10) {
                    ReportsHeroMetricPill(title: "高风险", value: "\(highRiskCount)", tint: Color(hex: "F46B5A"))
                    ReportsHeroMetricPill(title: "近24小时", value: "\(recent24hCount)", tint: Color(hex: "F3A53B"))
                    ReportsHeroMetricPill(title: "报告同日", value: focusDate == nil ? "--" : "\(focusCount)", tint: Theme.Colors.mintGreen)
                }
            }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var heroBadge: String {
        focusDate == nil ? "最近告警" : "报告同日复盘"
    }

    private var heroHeadline: String {
        if totalCount == 0 {
            return String(localized: "当前没有需要回看的告警。")
        }
        if highRiskCount > 0 {
            return String(localized: "有 \(highRiskCount) 条高风险提醒值得优先复盘。")
        }
        return String(localized: "告警以中低风险提醒为主。")
    }

    private var heroDetail: String {
        if let focusDate {
            return String(localized: "\(focusDate.reportsShortDateString()) 同日有 \(focusCount) 条提醒，可结合报告里的睡眠、压力和活动变化一起看。")
        }
        return String(localized: "这里会把提醒按类型和时间整理，帮助你判断异常是偶发，还是集中出现在某个恢复窗口。")
    }
}

private struct AlertHistoryFilterCard: View {
    @Binding var filter: AlertHistoryView.Filter
    let items: [AlertHistoryItem]

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("筛选", subtitle: "按类型查看告警，数量会随筛选即时更新。")

            HStack(spacing: 8) {
                ForEach(AlertHistoryView.Filter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        filterButton(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filterButton(_ item: AlertHistoryView.Filter) -> some View {
        let isSelected = filter == item
        let count = countForFilter(item)
        return VStack(spacing: 6) {
            Image(systemName: item.systemImage)
                .font(.appSystem(size: 14, weight: .black))
                .foregroundColor(isSelected ? .white : item.tint)

            Text(item.displayName)
                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? .white : Color(hex: "102C57"))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("\(count)")
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .white.opacity(0.86) : Color(hex: "7A8AA0"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? item.tint : Color.white.opacity(0.70))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.tint.opacity(isSelected ? 0 : 0.12), lineWidth: 1)
        )
    }

    private func countForFilter(_ filter: AlertHistoryView.Filter) -> Int {
        switch filter {
        case .all:
            return items.count
        case .heartRate:
            return items.filter { $0.kind == .heartRate }.count
        case .stress:
            return items.filter { $0.kind == .stress }.count
        case .sleep:
            return items.filter { $0.kind == .sleep }.count
        }
    }
}

private struct AlertHistoryOverviewCard: View {
    let items: [AlertHistoryItem]
    let focusDate: Date?

    private var primaryKind: AlertHistoryItem.Kind? {
        let counts = Dictionary(grouping: items, by: { $0.kind }).mapValues(\.count)
        return counts.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue > rhs.key.rawValue
            }
            return lhs.value < rhs.value
        }?.key
    }

    private var latestItem: AlertHistoryItem? {
        items.max { $0.date < $1.date }
    }

    private var focusCount: Int {
        guard let focusDate else { return 0 }
        return items.filter { Calendar.current.isDate($0.date, inSameDayAs: focusDate) }.count
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("告警概览", subtitle: "先看集中类型、最近提醒和处理优先级。")

            HStack(spacing: 8) {
                ReportsCompactMetricPill(title: "集中类型", value: primaryKind?.rawValue ?? "--", tint: primaryKind?.alertTint ?? Color(hex: "8AA0B8"))
                ReportsCompactMetricPill(title: "最近提醒", value: latestItem?.shortTimeText ?? "--", tint: Color(hex: "5B8CFF"))
                ReportsCompactMetricPill(title: "报告同日", value: focusDate == nil ? "--" : "\(focusCount)", tint: Theme.Colors.mintGreen)
            }

            VStack(spacing: 10) {
                overviewRow(
                    title: priorityTitle,
                    detail: priorityDetail,
                    systemImage: "exclamationmark.shield.fill",
                    tint: priorityTint
                )
                overviewRow(
                    title: "建议回看",
                    detail: reviewDetail,
                    systemImage: "doc.text.magnifyingglass",
                    tint: Color(hex: "5B8CFF")
                )
            }
        }
    }

    private var priorityTitle: String {
        if items.contains(where: { $0.alertSeverity == .high }) {
            return String(localized: "优先处理高风险提醒")
        }
        if items.isEmpty {
            return String(localized: "暂无处理优先级")
        }
        return String(localized: "以观察和复盘为主")
    }

    private var priorityDetail: String {
        if let latestItem {
            return "\(latestItem.title)：\(latestItem.suggestion)"
        }
        return String(localized: "当前没有告警记录，可以继续保持现有监测设置。")
    }

    private var priorityTint: Color {
        items.contains(where: { $0.alertSeverity == .high }) ? Color(hex: "F46B5A") : Theme.Colors.mintGreen
    }

    private var reviewDetail: String {
        if let primaryKind {
            return String(localized: "\(primaryKind.rawValue)提醒出现较多，建议结合报告里的\(primaryKind.reviewMetricName)一起复盘。")
        }
        return String(localized: "暂无集中类型，继续观察后会自动形成更清晰的提醒分布。")
    }

    private func overviewRow(title: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.13))
                Image(systemName: systemImage)
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AlertHistoryTrendCard: View {
    let items: [AlertHistoryItem]

    private var points: [AlertTrendPoint] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -6 + offset, to: start) else { return nil }
            let count = items.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
            return AlertTrendPoint(date: day, count: count)
        }
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("近 7 天告警趋势", subtitle: "看提醒是否集中在某几天，辅助判断是否和睡眠或压力波动重合。")

            if points.allSatisfy({ $0.count == 0 }) {
                ReportsInlineEmptyState(text: "近 7 天暂无当前筛选类型的告警")
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("日期", point.date),
                        y: .value("次数", point.count)
                    )
                    .foregroundStyle(Theme.Colors.mintGreen.gradient)
                    .cornerRadius(5)
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(ReportsChartStyle.plotBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

private struct AlertTrendPoint: Identifiable {
    let date: Date
    let count: Int

    var id: Int64 {
        Int64(date.timeIntervalSince1970)
    }
}

/// AlertHistoryRow 由 AlertHistoryView 调用，用来渲染单条告警历史记录。
private struct AlertHistoryRow: View {
    let item: AlertHistoryItem
    let isFocusDay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(item.kind.alertTint.opacity(0.13))
                    Image(systemName: item.kind.icon)
                        .font(.appSystem(size: 18, weight: .black))
                        .foregroundColor(item.kind.alertTint)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if isFocusDay {
                            Text("报告同日")
                                .font(.appSystem(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.mintGreen)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.mintGreen.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(item.detail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(item.kind.rawValue)
                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(item.kind.alertTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(item.kind.alertTint.opacity(0.10), in: Capsule())

                    Text(item.shortTimeText)
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "7A8AA0"))
                }
            }

            HStack(spacing: 8) {
                ReportsCompactMetricPill(title: "风险", value: item.alertSeverity.title, tint: item.alertSeverity.tint)
                ReportsCompactMetricPill(title: "处理", value: item.actionLevel, tint: item.kind.alertTint)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.appSystem(size: 13, weight: .black))
                    .foregroundColor(Theme.Colors.mintGreen)
                    .padding(.top, 1)
                Text(item.suggestion)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "35506F"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Theme.Colors.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.92), item.kind.alertTint.opacity(isFocusDay ? 0.12 : 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isFocusDay ? Theme.Colors.mintGreen.opacity(0.32) : Color.white.opacity(0.72), lineWidth: 1)
        )
    }
}

private enum AlertSeverity: Equatable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: return String(localized: "高")
        case .medium: return String(localized: "中")
        case .low: return String(localized: "低")
        }
    }

    var tint: Color {
        switch self {
        case .high: return Color(hex: "F46B5A")
        case .medium: return Color(hex: "F3A53B")
        case .low: return Theme.Colors.mintGreen
        }
    }
}

private extension AlertHistoryItem {
    var alertSeverity: AlertSeverity {
        switch kind {
        case .heartRate: return .high
        case .stress: return .medium
        case .sleep: return .low
        }
    }

    var actionLevel: String {
        switch kind {
        case .heartRate: return String(localized: "先休息")
        case .stress: return String(localized: "降负荷")
        case .sleep: return String(localized: "调节律")
        }
    }

    var suggestion: String {
        switch kind {
        case .heartRate:
            return String(localized: "先停止高强度活动，坐下休息 3-5 分钟；若伴随胸闷、头晕或持续不适，请及时就医。")
        case .stress:
            return String(localized: "安排一次 2-3 分钟慢呼吸或短步行，先把后续任务强度降半档。")
        case .sleep:
            return String(localized: "优先固定今晚入睡窗口，减少临睡前刺激，并观察是否连续多晚中断。")
        }
    }

    var shortTimeText: String {
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

private extension AlertHistoryItem.Kind {
    var alertTint: Color {
        switch self {
        case .heartRate: return Color(hex: "FF5A5F")
        case .stress: return Color(hex: "F3A53B")
        case .sleep: return Color(hex: "5B8CFF")
        }
    }

    var reviewMetricName: String {
        switch self {
        case .heartRate: return String(localized: "心率和活动负荷")
        case .stress: return String(localized: "压力曲线和恢复建议")
        case .sleep: return String(localized: "睡眠结构和夜间中断")
        }
    }
}

#Preview {
    NavigationStack {
        AlertHistoryView(focusDate: Date())
    }
}
