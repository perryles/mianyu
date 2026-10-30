/// Vitals Widget 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
import WidgetKit
import SwiftUI

/// 生命体征数据模型 作为小组件扩展里的数据载体。
/// 负责Widget 展示与配置。
struct VitalsEntry: TimelineEntry {
    let date: Date
    let heartRate: Double?
    let hrv: Double?
    let lastSyncTime: Date?
    /// 生命体征域的过期窗口，来自 V2 快照分域新鲜度
    let staleAfter: TimeInterval
}

/// 生命体征结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct VitalsProvider: TimelineProvider {
    func placeholder(in context: Context) -> VitalsEntry {
        VitalsEntry(date: Date(), heartRate: nil, hrv: nil, lastSyncTime: nil, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter)
    }

    func getSnapshot(in context: Context, completion: @escaping (VitalsEntry) -> ()) {
        completion(loadEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VitalsEntry>) -> ()) {
        let currentDate = Date()
        let base = loadEntry(date: currentDate)
        // 多 entry 让相对时间文案与新鲜度状态在两次刷新之间也能持续推进
        let entries = (0..<8).map { offset in
            VitalsEntry(
                date: currentDate.addingTimeInterval(TimeInterval(offset) * 15 * 60),
                heartRate: base.heartRate,
                hrv: base.hrv,
                lastSyncTime: base.lastSyncTime,
                staleAfter: base.staleAfter
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func loadEntry(date: Date) -> VitalsEntry {
        // 改读 V2 快照：使用生命体征域的 updatedAt 与过期窗口，取代全局 lastSyncTime
        let snapshot = WidgetSharedStore.loadSnapshot(now: date)
        return VitalsEntry(
            date: date,
            heartRate: snapshot.heartRate,
            hrv: snapshot.hrv,
            lastSyncTime: snapshot.vitals.freshness.updatedAt,
            staleAfter: snapshot.vitals.freshness.staleAfter
        )
    }
}

/// 生命体征小组件条目视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct VitalsWidgetEntryView: View {
    var entry: VitalsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let tone = vitalsTone
        let title = vitalsTitle

        Group {
            switch family {
            case .systemSmall:
                VitalsSystemSmallView(entry: entry, tone: tone, title: title)
            case .systemMedium:
                VitalsSystemMediumView(entry: entry, tone: tone, title: title)
            case .accessoryCircular:
                VitalsAccessoryCircularView(entry: entry, tone: tone)
            case .accessoryRectangular:
                WidgetAccessorySummaryView(
                    label: String(localized: "恢复"),
                    title: title,
                    detail: entry.hrv.map { "HRV \(Int($0.rounded()))ms" } ?? String(localized: "等待今日同步"),
                    tint: tone.accent
                )
            case .accessoryInline:
                Text(widgetIsFreshAndValid(entry.heartRate, lastSyncTime: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) ? entry.heartRate.map { String(localized: "HR \(Int($0.rounded()))") } ?? String(localized: "恢复 待同步") : String(localized: "恢复 待同步"))
            default:
                VitalsSystemSmallView(entry: entry, tone: tone, title: title)
            }
        }
        .widgetURL(MianyuWidgetDeepLink.vitals)
    }

    private var vitalsTone: WidgetVisualTone {
        // 数据过期时降级为提醒色，避免拿旧数据当作当前恢复状态
        if widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .stale { return .caution }
        guard let hrv = entry.hrv, hrv > 0 else { return .waiting }
        let hr = entry.heartRate ?? 0
        if hrv >= 55 && (hr == 0 || hr <= 72) { return .relaxed }
        if hrv >= 40 && (hr == 0 || hr <= 82) { return .steady }
        if hrv >= 28 { return .mild }
        return .caution
    }

    private var vitalsTitle: String {
        if widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .stale { return String(localized: "数据较旧") }
        guard let hrv = entry.hrv, hrv > 0 else { return String(localized: "待同步") }
        let hr = entry.heartRate ?? 0
        if hrv >= 55 && (hr == 0 || hr <= 72) { return String(localized: "恢复在线") }
        if hrv >= 40 && (hr == 0 || hr <= 82) { return String(localized: "恢复平稳") }
        if hrv >= 28 { return String(localized: "恢复偏弱") }
        return String(localized: "优先恢复")
    }
}

private struct VitalsSystemSmallView: View {
    let entry: VitalsEntry
    let tone: WidgetVisualTone
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack {
            WidgetReferenceCardBackground(tint: tone.accent, cornerRadius: 24)
            VStack(alignment: .leading, spacing: 5) {
                WidgetReferenceHeader(icon: "waveform.path.ecg", title: String(localized: "生命体征"), status: title, tint: tone.accent)
                WidgetReferenceMetric(value: hrvText, unit: "HRV ms")
                WidgetReferenceBars(values: chartValues, tint: tone.accent, secondaryTint: WidgetPalette.accentRed)
                    .frame(height: 34)
                WidgetReferenceFooter(stats: [
                    WidgetReferenceStat(value: hrvText, label: "HRV", tint: tone.accent),
                    WidgetReferenceStat(value: heartRateText, label: String(localized: "心率"), tint: WidgetPalette.accentRed),
                    WidgetReferenceStat(value: widgetClockText(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date), label: String(localized: "同步"), tint: Color.white.opacity(0.72))
                ])
            }
            .padding(12)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var hrvText: String {
        entry.hrv.map { "\(Int($0.rounded()))" } ?? "--"
    }

    private var heartRateText: String {
        entry.heartRate.map { "\(Int($0.rounded()))" } ?? "--"
    }

    private var chartValues: [Double] {
        let hrv = entry.hrv ?? 0
        let heartRatePercent = min(100, max(0, (entry.heartRate ?? 0) / 120 * 100))
        return WidgetMetricSeries.normalized([hrv, heartRatePercent, (hrv + heartRatePercent) / 2])
    }
}

private struct VitalsSystemMediumView: View {
    let entry: VitalsEntry
    let tone: WidgetVisualTone
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack(alignment: .trailing) {
            WidgetCardBackground(tone: tone, cornerRadius: 28)
            WidgetRingView(progress: ringProgress, tint: tone.accent, lineWidth: 16)
                .frame(width: 118, height: 118)
                .overlay {
                    VStack(spacing: 2) {
                        Text(entry.hrv.map { "\(Int($0.rounded()))" } ?? "--")
                            .font(.widgetAppSystem(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(tone.accent)
                        Text("HRV")
                            .font(.widgetAppSystem(size: 11, weight: .semibold))
                            .foregroundStyle(WidgetPalette.textTertiary)
                    }
                }
                .padding(.trailing, 20)
        }
        .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    WidgetAccentChip(icon: "waveform.path.ecg", text: String(localized: "恢复状态"), tint: tone.accent)
                    Spacer(minLength: 0)
                    WidgetAccentChip(icon: "clock", text: widgetRelativeSyncText(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date), tint: tone.accent)
                }
                Text(title)
                    .font(.widgetAppSystem(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(tone.accent)
                Text(widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .stale ? String(localized: "恢复数据较旧") : widgetRelativeSyncText(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date))
                    .font(.widgetAppSystem(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetPalette.textSecondary)
                HStack(spacing: 8) {
                    WidgetMetricCard(title: "HRV", value: entry.hrv.map { "\(Int($0.rounded()))ms" } ?? "--", tint: tone.accent)
                    WidgetMetricCard(title: String(localized: "心率"), value: entry.heartRate.map { "\(Int($0.rounded()))" } ?? "--", tint: WidgetPalette.accentRed)
                }
                if entry.hrv == nil && entry.heartRate == nil {
                    WidgetEmptyStateBanner(title: String(localized: "等待恢复同步"), detail: String(localized: "同步完成后显示 HR 和 HRV"), tint: tone.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .padding(.trailing, 122)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var ringProgress: Double {
        guard let hrv = entry.hrv else { return 0.16 }
        return max(0.08, min(1, hrv / 100))
    }
}

private struct VitalsAccessoryCircularView: View {
    let entry: VitalsEntry
    let tone: WidgetVisualTone

    var body: some View {
        if let hrv = entry.hrv {
            Gauge(value: hrv, in: 0...100) {
                Image(systemName: "waveform.path.ecg")
            } currentValueLabel: {
                Text("\(Int(hrv.rounded()))")
            }
            .tint(tone.accent)
            .gaugeStyle(.accessoryCircular)
            // 锁屏着色模式下让系统统一渲染重点内容
            .widgetAccentable()
        } else {
            Image(systemName: "waveform.path.ecg")
        }
    }
}

/// 生命体征小组件结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct VitalsWidget: Widget {
    let kind: String = "VitalsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VitalsProvider()) { entry in
            VitalsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("生命体征")
        .description("查看心率与 HRV。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

/// 生命体征小组件预览提供器 作为小组件扩展里的预览辅助类型。
/// 负责Widget 展示与配置。
struct VitalsWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VitalsWidgetEntryView(entry: VitalsEntry(date: .now, heartRate: 68, hrv: 60, lastSyncTime: .now, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            VitalsWidgetEntryView(entry: VitalsEntry(date: .now, heartRate: 78, hrv: 38, lastSyncTime: .now, staleAfter: AppGroupSchema.Freshness.vitalsStaleAfter))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
