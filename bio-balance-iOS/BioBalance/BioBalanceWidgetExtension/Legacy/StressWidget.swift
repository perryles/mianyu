/// Stress Widget 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
import WidgetKit
import SwiftUI

/// 压力数据模型 作为小组件扩展里的数据载体。
/// 负责Widget 展示与配置。
struct StressEntry: TimelineEntry {
    let date: Date
    let stress: Double?
    let trend: String?
    let history: [WidgetStressHistoryPoint]
    let lastSyncTime: Date?
    /// 生命体征域的过期窗口，来自 V2 快照分域新鲜度
    let staleAfter: TimeInterval
}

/// 压力结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct StressProvider: TimelineProvider {
    func placeholder(in context: Context) -> StressEntry {
        StressEntry(date: Date(), stress: nil, trend: nil, history: [], lastSyncTime: nil, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter)
    }

    func getSnapshot(in context: Context, completion: @escaping (StressEntry) -> ()) {
        completion(loadEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StressEntry>) -> ()) {
        let currentDate = Date()
        let base = loadEntry(date: currentDate)
        // 多 entry 让相对时间文案与新鲜度状态在两次刷新之间也能持续推进
        let entries = (0..<8).map { offset in
            StressEntry(
                date: currentDate.addingTimeInterval(TimeInterval(offset) * 15 * 60),
                stress: base.stress,
                trend: base.trend,
                history: base.history,
                lastSyncTime: base.lastSyncTime,
                staleAfter: base.staleAfter
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func loadEntry(date: Date) -> StressEntry {
        // 改读 V2 快照：压力属于生命体征域，使用域级 updatedAt 与过期窗口
        let snapshot = WidgetSharedStore.loadSnapshot(now: date)
        return StressEntry(
            date: date,
            stress: snapshot.stress,
            trend: snapshot.stressTrend,
            history: snapshot.stressHistory,
            lastSyncTime: snapshot.vitals.freshness.updatedAt,
            staleAfter: snapshot.vitals.freshness.staleAfter
        )
    }
}

/// 压力小组件条目视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct StressWidgetEntryView: View {
    var entry: StressEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let tone = stressTone
        let title = stressTitle

        Group {
            switch family {
            case .systemSmall:
                StressSystemSmallView(entry: entry, tone: tone, title: title)
            case .systemMedium:
                StressSystemMediumView(entry: entry, tone: tone, title: title)
            case .accessoryCircular:
                StressAccessoryCircularView(entry: entry, tone: tone)
            case .accessoryRectangular:
                WidgetAccessorySummaryView(
                    label: String(localized: "压力"),
                    title: title,
                    detail: entry.stress.map { String(localized: "压力 \(Int($0.rounded())) · \(widgetRelativeSyncText(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date))") } ?? String(localized: "等待今日同步"),
                    tint: tone.accent
                )
            case .accessoryInline:
                Text(entry.stress.map { String(localized: "压力 \(Int($0.rounded()))") } ?? String(localized: "压力 待同步"))
            default:
                StressSystemSmallView(entry: entry, tone: tone, title: title)
            }
        }
        .widgetURL(MianyuWidgetDeepLink.stress)
    }

    private var dataState: WidgetDataState {
        widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date)
    }

    private var hasFreshStress: Bool {
        widgetIsFreshStress(entry.stress, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date)
    }

    private var stressTone: WidgetVisualTone {
        switch dataState {
        case .missing:
            return .waiting
        case .stale:
            return .caution
        case .fresh:
            return widgetToneForStress(entry.stress)
        }
    }

    private var stressTitle: String {
        switch dataState {
        case .missing:
            return String(localized: "压力监测")
        case .stale:
            return String(localized: "数据较旧")
        case .fresh:
            return widgetStressLabel(entry.stress)
        }
    }
}

private struct StressSystemSmallView: View {
    let entry: StressEntry
    let tone: WidgetVisualTone
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetGlassMetrics.outerRadiusSmall, style: .continuous)
        ZStack {
            WidgetReferenceCardBackground(tint: tone.accent, cornerRadius: WidgetGlassMetrics.outerRadiusSmall)
            VStack(alignment: .leading, spacing: 5) {
                WidgetReferenceHeader(icon: "wind", title: String(localized: "压力"), status: title, tint: tone.accent)
                WidgetReferenceMetric(value: stressText, unit: String(localized: "压力"))
                WidgetReferenceSparkline(values: chartValues, tint: tone.accent)
                    .frame(height: 34)
                WidgetReferenceFooter(stats: [
                    WidgetReferenceStat(value: stressText, label: String(localized: "压力"), tint: tone.accent),
                    WidgetReferenceStat(value: trendText, label: String(localized: "趋势"), tint: tone.secondaryAccent),
                    WidgetReferenceStat(value: widgetClockText(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date), label: String(localized: "同步"), tint: Color.white.opacity(0.72))
                ])
            }
            .padding(12)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var hasFreshStress: Bool {
        widgetIsFreshStress(entry.stress, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date)
    }

    private var stressText: String {
        hasFreshStress ? entry.stress.map { "\(Int($0.rounded()))" } ?? "--" : "--"
    }

    private var trendText: String {
        hasFreshStress ? (entry.trend ?? String(localized: "稳定")) : String(localized: "待同步")
    }

    private var chartValues: [Double] {
        WidgetMetricSeries.recentNormalized(
            entry.history.map { Double($0.value) },
            limit: 9,
            fallback: entry.stress.map { WidgetMetricSeries.normalized([$0]) } ?? [0]
        )
    }
}

private struct StressSystemMediumView: View {
    let entry: StressEntry
    let tone: WidgetVisualTone
    let title: String

    private var hasFreshStress: Bool {
        widgetIsFreshStress(entry.stress, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack(alignment: .trailing) {
            WidgetCardBackground(tone: tone, cornerRadius: 28)
            WidgetRingView(progress: ringProgress, tint: tone.accent, lineWidth: 16)
                .frame(width: WidgetGlassMetrics.mediumOrbSize, height: WidgetGlassMetrics.mediumOrbSize)
                .overlay {
                    VStack(spacing: 2) {
                        Text(hasFreshStress ? entry.stress.map { "\(Int($0.rounded()))" } ?? "--" : "--")
                            .font(.widgetAppSystem(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(tone.accent)
                        Text("压力")
                            .font(.widgetAppSystem(size: 11, weight: .semibold))
                            .foregroundStyle(WidgetPalette.textTertiary)
                    }
                }
                .padding(.trailing, WidgetGlassMetrics.mediumOrbTrailingInset)
        }
        .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    WidgetAccentChip(icon: "wind", text: String(localized: "压力监测"), tint: tone.accent)
                    Spacer(minLength: 0)
                    WidgetAccentChip(icon: "clock", text: widgetRelativeSyncText(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date), tint: tone.accent)
                }
                Text(title)
                    .font(.widgetAppSystem(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(tone.accent)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    WidgetMetricCard(title: String(localized: "压力"), value: hasFreshStress ? entry.stress.map { "\(Int($0.rounded()))" } ?? "--" : "--", tint: tone.accent)
                    WidgetMetricCard(title: String(localized: "趋势"), value: hasFreshStress ? entry.trend ?? String(localized: "稳定") : String(localized: "等待同步"), tint: tone.secondaryAccent)
                }
                Spacer(minLength: 0)
            }
            .padding(WidgetGlassMetrics.outerPadding)
            .padding(.trailing, WidgetGlassMetrics.mediumContentTrailingReserve)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var ringProgress: Double {
        guard hasFreshStress, let value = entry.stress else { return 0.18 }
        return max(0.08, min(1, value / 100))
    }
}

private struct StressAccessoryCircularView: View {
    let entry: StressEntry
    let tone: WidgetVisualTone

    var body: some View {
        if widgetIsFreshStress(entry.stress, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date), let stress = entry.stress {
            Gauge(value: stress, in: 0...100) {
                Image(systemName: "wind")
            } currentValueLabel: {
                Text("\(Int(stress.rounded()))")
            }
            .tint(tone.accent)
            .gaugeStyle(.accessoryCircular)
            // 锁屏着色模式下让系统统一渲染重点内容
            .widgetAccentable()
        } else {
            Image(systemName: "wind")
        }
    }
}

/// 压力小组件结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct StressWidget: Widget {
    let kind: String = "StressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StressProvider()) { entry in
            StressWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("压力")
        .description("查看压力水平与趋势。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

/// 压力小组件预览提供器 作为小组件扩展里的预览辅助类型。
/// 负责Widget 展示与配置。
struct StressWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StressWidgetEntryView(entry: StressEntry(date: .now, stress: 28, trend: "下降", history: [], lastSyncTime: .now, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            StressWidgetEntryView(entry: StressEntry(date: .now, stress: 66, trend: "升高", history: [], lastSyncTime: .now, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
