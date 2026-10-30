/// Activity Widget 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
import WidgetKit
import SwiftUI

/// Activity数据模型 作为小组件扩展里的数据载体。
/// 负责Widget 展示与配置。
struct ActivityEntry: TimelineEntry {
    let date: Date
    let steps: Int?
    let activeEnergy: Int?
    let exerciseMinutes: Int?
    let standHours: Int?
    let completionRate: Double?
    let metricCompletionRates: [Double]
    let lastSyncTime: Date?
    /// 活动域的过期窗口，来自 V2 快照分域新鲜度
    let staleAfter: TimeInterval
}

/// Activity结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct ActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry {
        ActivityEntry(date: Date(), steps: nil, activeEnergy: nil, exerciseMinutes: nil, standHours: nil, completionRate: nil, metricCompletionRates: [], lastSyncTime: nil, staleAfter: AppGroupSchema.Freshness.activityStaleAfter)
    }

    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> ()) {
        completion(loadEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> ()) {
        let currentDate = Date()
        let base = loadEntry(date: currentDate)
        // 多 entry 让相对时间文案与新鲜度状态在两次刷新之间也能持续推进
        let entries = (0..<8).map { offset in
            ActivityEntry(
                date: currentDate.addingTimeInterval(TimeInterval(offset) * 15 * 60),
                steps: base.steps,
                activeEnergy: base.activeEnergy,
                exerciseMinutes: base.exerciseMinutes,
                standHours: base.standHours,
                completionRate: base.completionRate,
                metricCompletionRates: base.metricCompletionRates,
                lastSyncTime: base.lastSyncTime,
                staleAfter: base.staleAfter
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func loadEntry(date: Date) -> ActivityEntry {
        // 改读 V2 快照：使用活动域的 updatedAt 与过期窗口，取代全局 lastSyncTime
        let snapshot = WidgetSharedStore.loadSnapshot(now: date)
        return ActivityEntry(
            date: date,
            steps: snapshot.steps,
            activeEnergy: snapshot.activeEnergy,
            exerciseMinutes: snapshot.exerciseMinutes,
            standHours: snapshot.standHours,
            completionRate: snapshot.activityCompletionRate,
            metricCompletionRates: [
                snapshot.stepsCompletionRate,
                snapshot.activeEnergyCompletionRate,
                snapshot.exerciseMinutesCompletionRate,
                snapshot.standHoursCompletionRate
            ].compactMap { $0 },
            lastSyncTime: snapshot.activity.freshness.updatedAt,
            staleAfter: snapshot.activity.freshness.staleAfter
        )
    }
}

/// Activity小组件条目视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct ActivityWidgetEntryView: View {
    var entry: ActivityEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let isFresh = widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .fresh
        let model = ActivityCardModel(
            title: String(localized: "今日活动"),
            subtitle: activitySubtitle,
            icon: "figure.walk",
            valueTitle: String(localized: "完成度"),
            valueText: isFresh ? entry.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "--" : "--",
            primaryMetricTitle: String(localized: "步数"),
            primaryMetricValue: isFreshAndValid(entry.steps) ? entry.steps.map { "\($0)" } ?? "--" : "--",
            secondaryMetricTitle: String(localized: "活跃能量"),
            secondaryMetricValue: isFreshAndValid(entry.activeEnergy) ? entry.activeEnergy.map { "\($0) kcal" } ?? "--" : "--",
            tertiaryMetricTitle: String(localized: "锻炼分钟"),
            tertiaryMetricValue: isFreshAndValid(entry.exerciseMinutes) ? entry.exerciseMinutes.map { "\($0)" } ?? "--" : "--",
            quaternaryMetricTitle: String(localized: "站立"),
            quaternaryMetricValue: isFreshAndValid(entry.standHours) ? entry.standHours.map { String(localized: "\($0) 小时") } ?? "--" : "--",
            syncTime: entry.lastSyncTime,
            staleAfter: entry.staleAfter,
            referenceDate: entry.date,
            tone: activityTone,
            progress: isFresh ? entry.completionRate ?? 0.16 : 0.16
        )

        Group {
            switch family {
            case .systemSmall:
                ActivitySystemSmallCard(
                    model: model,
                    chartValues: isFresh ? entry.metricCompletionRates : []
                )
            case .systemMedium:
                ActivitySystemMediumCard(model: model)
            case .systemLarge:
                ActivitySystemLargeCard(model: model)
            case .accessoryCircular:
                ActivityAccessoryCircularView(entry: entry, tone: activityTone)
            case .accessoryRectangular:
                WidgetAccessorySummaryView(
                    label: String(localized: "活动"),
                    title: activitySubtitle,
                    detail: isFreshAndValid(entry.steps) ? entry.steps.map { String(localized: "步数 \($0)") } ?? String(localized: "等待今日同步") : String(localized: "等待今日同步"),
                    tint: activityTone.accent
                )
            case .accessoryInline:
                Text(isFreshAndValid(entry.steps) ? entry.steps.map { String(localized: "步数 \($0)") } ?? String(localized: "活动 待同步") : String(localized: "活动 待同步"))
            default:
                ActivitySystemMediumCard(model: model)
            }
        }
        .widgetURL(MianyuWidgetDeepLink.activity)
    }

    private func isFreshAndValid(_ value: Int?) -> Bool {
        widgetIsFreshAndValid(value, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date)
    }

    private var activityTone: WidgetVisualTone {
        if widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .stale { return .caution }
        guard let rate = entry.completionRate else { return .waiting }
        switch rate {
        case 0.85...: return .relaxed
        case 0.65..<0.85: return .steady
        case 0.35..<0.65: return .mild
        default: return .caution
        }
    }

    private var activitySubtitle: String {
        if widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .stale { return String(localized: "数据较旧") }
        guard let rate = entry.completionRate else { return String(localized: "等待同步") }
        switch rate {
        case 0.85...: return String(localized: "节奏很稳")
        case 0.65..<0.85: return String(localized: "持续保持")
        case 0.35..<0.65: return String(localized: "再动一动")
        default: return String(localized: "先起身活动")
        }
    }
}

/// Activity数据模型 作为小组件扩展里的数据载体。
/// 负责Widget 展示与配置。
struct ActivityCardModel: Sendable {
    let title: String
    let subtitle: String
    let icon: String
    let valueTitle: String
    let valueText: String
    let primaryMetricTitle: String
    let primaryMetricValue: String
    let secondaryMetricTitle: String
    let secondaryMetricValue: String
    let tertiaryMetricTitle: String
    let tertiaryMetricValue: String
    let quaternaryMetricTitle: String
    let quaternaryMetricValue: String
    let syncTime: Date?
    /// 域级过期窗口与 entry 参考时间，供卡片内时间/新鲜度文案使用
    let staleAfter: TimeInterval
    let referenceDate: Date
    let tone: WidgetVisualTone
    let progress: Double
}

private struct ActivitySystemSmallCard: View {
    let model: ActivityCardModel
    let chartValues: [Double]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetGlassMetrics.outerRadiusSmall, style: .continuous)
        ZStack {
            WidgetReferenceCardBackground(tint: model.tone.accent, cornerRadius: WidgetGlassMetrics.outerRadiusSmall)
            VStack(alignment: .leading, spacing: 5) {
                WidgetReferenceHeader(icon: model.icon, title: String(localized: "活动"), status: model.subtitle, tint: model.tone.accent)
                WidgetReferenceMetric(value: model.primaryMetricValue, unit: String(localized: "步数"))
                WidgetReferenceBars(
                    values: chartValues.isEmpty ? [0, 0, 0, 0] : chartValues.map { min(1, max(0, $0)) },
                    tint: model.tone.accent,
                    secondaryTint: model.tone.secondaryAccent
                )
                .frame(height: 34)
                WidgetReferenceFooter(stats: [
                    WidgetReferenceStat(value: model.secondaryMetricValue, label: model.secondaryMetricTitle, tint: WidgetPalette.accentRed),
                    WidgetReferenceStat(value: model.tertiaryMetricValue, label: model.tertiaryMetricTitle, tint: WidgetPalette.brandGreen),
                    WidgetReferenceStat(value: model.quaternaryMetricValue, label: model.quaternaryMetricTitle, tint: WidgetPalette.brandCyan)
                ])
            }
            .padding(12)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// Activity系统中号卡片组件 作为小组件扩展里的内容展示卡片。
/// 负责Widget 展示与配置。
struct ActivitySystemMediumCard: View {
    let model: ActivityCardModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack(alignment: .trailing) {
            WidgetCardBackground(tone: model.tone, cornerRadius: 28)
            WidgetRingView(progress: model.progress, tint: model.tone.accent, lineWidth: 16)
                .frame(width: WidgetGlassMetrics.mediumOrbSize, height: WidgetGlassMetrics.mediumOrbSize)
                .overlay {
                    VStack(spacing: 2) {
                        Text(model.valueText)
                            .font(.widgetAppSystem(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(model.tone.accent)
                        Text(model.valueTitle)
                            .font(.widgetAppSystem(size: 11, weight: .semibold))
                            .foregroundStyle(WidgetPalette.textTertiary)
                    }
                }
                .padding(.trailing, WidgetGlassMetrics.mediumOrbTrailingInset)
        }
        .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    WidgetAccentChip(icon: model.icon, text: model.title, tint: model.tone.accent)
                    Spacer(minLength: 0)
                    WidgetAccentChip(icon: "clock", text: widgetRelativeSyncText(for: model.syncTime, staleAfter: model.staleAfter, now: model.referenceDate), tint: model.tone.accent)
                }
                Text(model.subtitle)
                    .font(.widgetAppSystem(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(model.tone.accent)
                HStack(spacing: 8) {
                    WidgetMetricCard(title: model.primaryMetricTitle, value: model.primaryMetricValue, tint: model.tone.accent)
                    WidgetMetricCard(title: model.secondaryMetricTitle, value: model.secondaryMetricValue, tint: model.tone.secondaryAccent)
                }
                Spacer(minLength: 0)
            }
            .padding(WidgetGlassMetrics.outerPadding)
            .padding(.trailing, WidgetGlassMetrics.mediumContentTrailingReserve)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// Activity系统大号卡片组件 作为小组件扩展里的内容展示卡片。
/// 负责Widget 展示与配置。
struct ActivitySystemLargeCard: View {
    let model: ActivityCardModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        ZStack {
            WidgetCardBackground(tone: model.tone, cornerRadius: 32)
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    WidgetAccentChip(icon: model.icon, text: model.title, tint: model.tone.accent)
                    Spacer(minLength: 0)
                    WidgetAccentChip(icon: "clock", text: widgetRelativeSyncText(for: model.syncTime, staleAfter: model.staleAfter, now: model.referenceDate), tint: model.tone.accent)
                }
            
                HStack(alignment: .top, spacing: 12) {
                    WidgetRingView(progress: model.progress, tint: model.tone.accent, lineWidth: 17)
                        .frame(width: 112, height: 112)
                        .overlay {
                            VStack(spacing: 2) {
                                Text(model.valueText)
                                    .font(.widgetAppSystem(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(model.tone.accent)
                                Text(model.valueTitle)
                                    .font(.widgetAppSystem(size: 11, weight: .semibold))
                                    .foregroundStyle(WidgetPalette.textTertiary)
                            }
                        }
                    VStack(spacing: 8) {
                        ActivityCompactMetricRow(title: model.primaryMetricTitle, value: model.primaryMetricValue, tint: model.tone.accent)
                        ActivityCompactMetricRow(title: model.secondaryMetricTitle, value: model.secondaryMetricValue, tint: model.tone.secondaryAccent)
                        ActivityCompactMetricRow(title: model.tertiaryMetricTitle, value: model.tertiaryMetricValue, tint: model.tone.accent)
                        ActivityCompactMetricRow(title: model.quaternaryMetricTitle, value: model.quaternaryMetricValue, tint: model.tone.secondaryAccent)
                    }
                }
                WidgetProgressStrip(title: String(localized: "今日完成度"), value: model.valueText, progress: model.progress, tint: model.tone.accent)
                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }
}

private struct ActivityCompactMetricRow: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.widgetAppSystem(size: 11, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                .frame(width: 54, alignment: .leading)

            Text(value)
                .font(.widgetAppSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? WidgetPalette.textPrimaryDark : WidgetPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 0.8)
        )
    }
}

/// Activity配件圆形视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct ActivityAccessoryCircularView: View {
    let entry: ActivityEntry
    let tone: WidgetVisualTone

    var body: some View {
        if widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .fresh, let rate = entry.completionRate {
            Gauge(value: rate, in: 0...1) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text("\(Int((rate * 100).rounded()))%")
            }
            .tint(tone.accent)
            .gaugeStyle(.accessoryCircular)
            // 锁屏着色模式下让系统统一渲染重点内容
            .widgetAccentable()
        } else {
            Image(systemName: "figure.walk")
        }
    }
}

/// Activity小组件结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct ActivityWidget: Widget {
    let kind: String = "ActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActivityProvider()) { entry in
            ActivityWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("活动")
        .description("查看今日步数与活动完成度。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

/// Activity小组件预览提供器 作为小组件扩展里的预览辅助类型。
/// 负责Widget 展示与配置。
struct ActivityWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ActivityWidgetEntryView(entry: ActivityEntry(date: .now, steps: 7560, activeEnergy: 420, exerciseMinutes: 18, standHours: 9, completionRate: 0.62, metricCompletionRates: [0.75, 0.84, 0.60, 0.75], lastSyncTime: .now, staleAfter: AppGroupSchema.Freshness.activityStaleAfter))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            ActivityWidgetEntryView(entry: ActivityEntry(date: .now, steps: 7560, activeEnergy: 420, exerciseMinutes: 18, standHours: 9, completionRate: 0.62, metricCompletionRates: [0.75, 0.84, 0.60, 0.75], lastSyncTime: .now, staleAfter: AppGroupSchema.Freshness.activityStaleAfter))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            ActivityWidgetEntryView(entry: ActivityEntry(date: .now, steps: 10020, activeEnergy: 610, exerciseMinutes: 34, standHours: 11, completionRate: 0.92, metricCompletionRates: [1, 1, 1, 0.92], lastSyncTime: .now, staleAfter: AppGroupSchema.Freshness.activityStaleAfter))
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
