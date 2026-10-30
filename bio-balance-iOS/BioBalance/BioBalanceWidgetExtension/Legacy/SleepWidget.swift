/// Sleep Widget 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
import WidgetKit
import SwiftUI

/// 睡眠数据模型 作为小组件扩展里的数据载体。
/// 负责Widget 展示与配置。
struct SleepEntry: TimelineEntry {
    let date: Date
    let durationMinutes: Int?
    let score: Int?
    let completionRate: Double?
    let lastSyncTime: Date?
    /// 睡眠域的过期窗口，来自 V2 快照分域新鲜度
    let staleAfter: TimeInterval
}

/// 睡眠结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct SleepProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepEntry {
        SleepEntry(date: Date(), durationMinutes: nil, score: nil, completionRate: nil, lastSyncTime: nil, staleAfter: AppGroupSchema.Freshness.sleepStaleAfter)
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepEntry) -> ()) {
        completion(loadEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepEntry>) -> ()) {
        let currentDate = Date()
        let base = loadEntry(date: currentDate)
        // 多 entry 让相对时间文案与新鲜度状态在两次刷新之间也能持续推进
        let entries = (0..<8).map { offset in
            SleepEntry(
                date: currentDate.addingTimeInterval(TimeInterval(offset) * 15 * 60),
                durationMinutes: base.durationMinutes,
                score: base.score,
                completionRate: base.completionRate,
                lastSyncTime: base.lastSyncTime,
                staleAfter: base.staleAfter
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func loadEntry(date: Date) -> SleepEntry {
        // 改读 V2 快照：睡眠域使用自身的 updatedAt 与 18h 过期窗口，避免被全局 6h 窗口误判为“数据较旧”
        let snapshot = WidgetSharedStore.loadSnapshot(now: date)
        return SleepEntry(
            date: date,
            durationMinutes: snapshot.sleepDurationMinutes,
            score: snapshot.sleepScore,
            completionRate: snapshot.sleepDurationCompletionRate,
            lastSyncTime: snapshot.sleep.freshness.updatedAt,
            staleAfter: snapshot.sleep.freshness.staleAfter
        )
    }
}

/// 睡眠小组件条目视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct SleepWidgetEntryView: View {
    var entry: SleepEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let tone = sleepTone
        let title = sleepTitle

        Group {
            switch family {
            case .systemSmall:
                SleepSystemSmallView(entry: entry, tone: tone, title: title)
            case .systemMedium:
                SleepSystemMediumView(entry: entry, tone: tone, title: title)
            case .accessoryCircular:
                SleepAccessoryCircularView(entry: entry, tone: tone)
            case .accessoryRectangular:
                WidgetAccessorySummaryView(
                    label: String(localized: "睡眠"),
                    title: title,
                    detail: widgetDurationText(minutes: entry.durationMinutes),
                    tint: tone.accent
                )
            case .accessoryInline:
                Text(entry.durationMinutes.map { String(localized: "睡眠 \(widgetDurationText(minutes: $0))") } ?? String(localized: "睡眠 待同步"))
            default:
                SleepSystemSmallView(entry: entry, tone: tone, title: title)
            }
        }
        .widgetURL(MianyuWidgetDeepLink.sleep)
    }

    private var sleepTone: WidgetVisualTone {
        if widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .stale { return .caution }
        guard let score = entry.score, score > 0 else { return .waiting }
        if score >= 85 { return .relaxed }
        if score >= 70 { return .steady }
        if score >= 55 { return .mild }
        return .caution
    }

    private var sleepTitle: String {
        if widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .stale { return String(localized: "数据较旧") }
        guard let score = entry.score, score > 0 else { return String(localized: "待同步") }
        if score >= 85 { return String(localized: "恢复在线") }
        if score >= 70 { return String(localized: "睡得不错") }
        if score >= 55 { return String(localized: "稍晚一点休息") }
        return String(localized: "优先补觉")
    }
}

private struct SleepSystemSmallView: View {
    let entry: SleepEntry
    let tone: WidgetVisualTone
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack {
            WidgetReferenceCardBackground(tint: tone.accent, cornerRadius: 24)
            VStack(alignment: .leading, spacing: 5) {
                WidgetReferenceHeader(icon: "bed.double.fill", title: String(localized: "昨夜睡眠"), status: title, tint: tone.accent)
                WidgetReferenceMetric(value: compactDurationText, unit: String(localized: "时长"))
                WidgetReferenceBars(values: chartValues, tint: tone.accent, secondaryTint: tone.secondaryAccent)
                    .frame(height: 34)
                WidgetReferenceFooter(stats: [
                    WidgetReferenceStat(value: scoreText, label: String(localized: "评分"), tint: tone.secondaryAccent),
                    WidgetReferenceStat(value: completionText, label: String(localized: "完成度"), tint: tone.accent),
                    WidgetReferenceStat(value: widgetClockText(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date), label: String(localized: "同步"), tint: Color.white.opacity(0.72))
                ])
            }
            .padding(12)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var hasFreshDuration: Bool {
        widgetIsFreshAndValid(entry.durationMinutes, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date)
    }

    private var hasFreshScore: Bool {
        widgetIsFreshAndValid(entry.score, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date)
    }

    private var compactDurationText: String {
        guard hasFreshDuration, let minutes = entry.durationMinutes else { return "--" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private var scoreText: String {
        hasFreshScore ? entry.score.map(String.init) ?? "--" : "--"
    }

    private var completionText: String {
        guard hasFreshDuration, let rate = entry.completionRate else { return "--" }
        return "\(Int((min(1, max(0, rate)) * 100).rounded()))%"
    }

    private var chartValues: [Double] {
        let completion = hasFreshDuration ? (entry.completionRate ?? 0) * 100 : 0
        let score = hasFreshScore ? Double(entry.score ?? 0) : 0
        return WidgetMetricSeries.normalized([completion, score, (completion + score) / 2])
    }
}

private struct SleepSystemMediumView: View {
    let entry: SleepEntry
    let tone: WidgetVisualTone
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack(alignment: .trailing) {
            WidgetCardBackground(tone: tone, cornerRadius: 28)
            WidgetRingView(progress: completionRate, tint: tone.accent, lineWidth: 16)
                .frame(width: 118, height: 118)
                .overlay {
                    VStack(spacing: 2) {
                        Text(widgetIsFreshAndValid(entry.score, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) ? entry.score.map { "\($0)" } ?? "--" : "--")
                            .font(.widgetAppSystem(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(tone.accent)
                        Text("评分")
                            .font(.widgetAppSystem(size: 11, weight: .semibold))
                            .foregroundStyle(WidgetPalette.textTertiary)
                    }
                }
                .padding(.trailing, 20)
        }
        .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    WidgetAccentChip(icon: "bed.double.fill", text: String(localized: "昨夜恢复卡"), tint: tone.accent)
                    Spacer(minLength: 0)
                    WidgetAccentChip(icon: "clock", text: widgetRelativeSyncText(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date), tint: tone.accent)
                }
                Text(title)
                    .font(.widgetAppSystem(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(tone.accent)
                Text(widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .stale ? String(localized: "昨夜睡眠数据较旧") : widgetRelativeSyncText(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date))
                    .font(.widgetAppSystem(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetPalette.textSecondary)
                HStack(spacing: 8) {
                    WidgetMetricCard(title: String(localized: "时长"), value: widgetIsFreshAndValid(entry.durationMinutes, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) ? widgetDurationText(minutes: entry.durationMinutes) : "--", tint: tone.accent)
                    WidgetMetricCard(title: String(localized: "评分"), value: widgetIsFreshAndValid(entry.score, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) ? entry.score.map { String(localized: "\($0)分") } ?? "--" : "--", tint: tone.secondaryAccent)
                }
                if !widgetIsFreshAndValid(entry.durationMinutes, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) {
                    WidgetEmptyStateBanner(title: String(localized: "等待昨夜数据"), detail: String(localized: "同步完成后显示时长和评分"), tint: tone.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .padding(.trailing, 122)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var completionRate: Double {
        max(0.08, widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .fresh ? entry.completionRate ?? 0.16 : 0.16)
    }
}

private struct SleepAccessoryCircularView: View {
    let entry: SleepEntry
    let tone: WidgetVisualTone

    var body: some View {
        if widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .fresh, let rate = entry.completionRate {
            Gauge(value: rate, in: 0...1) {
                Image(systemName: "bed.double.fill")
            } currentValueLabel: {
                Text("\(Int((rate * 100).rounded()))%")
            }
            .tint(tone.accent)
            .gaugeStyle(.accessoryCircular)
            // 锁屏着色模式下让系统统一渲染重点内容
            .widgetAccentable()
        } else {
            Image(systemName: "bed.double.fill")
        }
    }
}

/// 睡眠小组件结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct SleepWidget: Widget {
    let kind: String = "SleepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepProvider()) { entry in
            SleepWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("睡眠")
        .description("查看睡眠时长与评分。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

/// 睡眠小组件预览提供器 作为小组件扩展里的预览辅助类型。
/// 负责Widget 展示与配置。
struct SleepWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SleepWidgetEntryView(entry: SleepEntry(date: .now, durationMinutes: 470, score: 87, completionRate: 0.92, lastSyncTime: .now, staleAfter: AppGroupSchema.Freshness.sleepStaleAfter))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SleepWidgetEntryView(entry: SleepEntry(date: .now, durationMinutes: 390, score: 62, completionRate: 0.75, lastSyncTime: .now, staleAfter: AppGroupSchema.Freshness.sleepStaleAfter))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
