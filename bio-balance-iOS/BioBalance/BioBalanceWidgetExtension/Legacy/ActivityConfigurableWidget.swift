/// Activity Configurable Widget 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
import WidgetKit
import SwiftUI
import AppIntents

/// Activity小组件Primary指标枚举 作为小组件扩展里的能力或分类定义。
/// 负责描述Widget 展示与配置过程中会用到的状态、分类或分支。
enum ActivityWidgetPrimaryMetric: String, AppEnum {
    case steps
    case activeEnergy
    case exerciseMinutes
    case standHours

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "主指标")
    }

    static var caseDisplayRepresentations: [ActivityWidgetPrimaryMetric: DisplayRepresentation] {
        [
            .steps: DisplayRepresentation(title: "步数"),
            .activeEnergy: DisplayRepresentation(title: "活跃能量"),
            .exerciseMinutes: DisplayRepresentation(title: "锻炼分钟"),
            .standHours: DisplayRepresentation(title: "站立")
        ]
    }
}

/// Activity小组件Layout枚举 作为小组件扩展里的状态与分类定义。
/// 负责描述Widget 展示与配置过程中会用到的状态、分类或分支。
enum ActivityWidgetLayoutStyle: String, AppEnum {
    case focus
    case grid

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "布局")
    }

    static var caseDisplayRepresentations: [ActivityWidgetLayoutStyle: DisplayRepresentation] {
        [
            .focus: DisplayRepresentation(title: "聚焦"),
            .grid: DisplayRepresentation(title: "网格")
        ]
    }
}

/// Activity小组件ConfigurationIntent结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct ActivityWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "活动小组件"
    static let description = IntentDescription("选择主指标与布局样式。")

    @Parameter(title: "主指标", default: .steps)
    var primaryMetric: ActivityWidgetPrimaryMetric

    @Parameter(title: "布局", default: .focus)
    var layout: ActivityWidgetLayoutStyle
}

/// ActivityConfigurable数据模型 作为小组件扩展里的数据载体。
/// 负责Widget 展示与配置。
struct ActivityConfigurableEntry: TimelineEntry {
    let date: Date
    let configuration: ActivityWidgetConfigurationIntent
    let steps: Int?
    let activeEnergy: Int?
    let exerciseMinutes: Int?
    let standHours: Int?
    let completionRate: Double?
    let lastSyncTime: Date?
    /// 活动域的过期窗口，来自 V2 快照分域新鲜度
    let staleAfter: TimeInterval
}

/// ActivityConfigurable结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct ActivityConfigurableProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ActivityConfigurableEntry {
        ActivityConfigurableEntry(
            date: Date(),
            configuration: ActivityWidgetConfigurationIntent(),
            steps: nil,
            activeEnergy: nil,
            exerciseMinutes: nil,
            standHours: nil,
            completionRate: nil,
            lastSyncTime: nil,
            staleAfter: AppGroupSchema.Freshness.activityStaleAfter
        )
    }

    func snapshot(for configuration: ActivityWidgetConfigurationIntent, in context: Context) async -> ActivityConfigurableEntry {
        loadEntry(date: Date(), configuration: configuration)
    }

    func timeline(for configuration: ActivityWidgetConfigurationIntent, in context: Context) async -> Timeline<ActivityConfigurableEntry> {
        let currentDate = Date()
        let base = loadEntry(date: currentDate, configuration: configuration)
        // 多 entry 让相对时间文案与新鲜度状态在两次刷新之间也能持续推进
        let entries = (0..<8).map { offset in
            ActivityConfigurableEntry(
                date: currentDate.addingTimeInterval(TimeInterval(offset) * 15 * 60),
                configuration: base.configuration,
                steps: base.steps,
                activeEnergy: base.activeEnergy,
                exerciseMinutes: base.exerciseMinutes,
                standHours: base.standHours,
                completionRate: base.completionRate,
                lastSyncTime: base.lastSyncTime,
                staleAfter: base.staleAfter
            )
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func loadEntry(date: Date, configuration: ActivityWidgetConfigurationIntent) -> ActivityConfigurableEntry {
        // 改读 V2 快照：使用活动域的 updatedAt 与过期窗口，取代全局 lastSyncTime
        let snapshot = WidgetSharedStore.loadSnapshot(now: date)
        let completionRate = snapshot.activityCompletionRate
        let lastSyncTime = snapshot.activity.freshness.updatedAt
        let staleAfter = snapshot.activity.freshness.staleAfter

        switch configuration.layout {
        case .grid:
            return ActivityConfigurableEntry(
                date: date,
                configuration: configuration,
                steps: snapshot.steps,
                activeEnergy: snapshot.activeEnergy,
                exerciseMinutes: snapshot.exerciseMinutes,
                standHours: snapshot.standHours,
                completionRate: completionRate,
                lastSyncTime: lastSyncTime,
                staleAfter: staleAfter
            )
        case .focus:
            return ActivityConfigurableEntry(
                date: date,
                configuration: configuration,
                steps: configuration.primaryMetric == .steps ? snapshot.steps : nil,
                activeEnergy: configuration.primaryMetric == .activeEnergy ? snapshot.activeEnergy : nil,
                exerciseMinutes: configuration.primaryMetric == .exerciseMinutes ? snapshot.exerciseMinutes : nil,
                standHours: configuration.primaryMetric == .standHours ? snapshot.standHours : nil,
                completionRate: completionRate,
                lastSyncTime: lastSyncTime,
                staleAfter: staleAfter
            )
        }
    }
}

/// ActivityConfigurable小组件条目视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct ActivityConfigurableWidgetEntryView: View {
    var entry: ActivityConfigurableEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let tone = activityTone
        Group {
            switch family {
            case .systemMedium:
                ActivityConfigurableMediumView(entry: entry, tone: tone)
            case .systemLarge:
                ActivityConfigurableLargeView(entry: entry, tone: tone)
            case .accessoryCircular:
                ActivityConfigurableAccessoryCircularView(entry: entry, tone: tone)
            case .accessoryRectangular:
                WidgetAccessorySummaryView(
                    label: String(localized: "活动"),
                    title: layoutTitle,
                    detail: focusDescriptor.valueText,
                    tint: tone.accent
                )
            case .accessoryInline:
                Text("\(focusDescriptor.title) \(focusDescriptor.valueText)")
            default:
                ActivityConfigurableMediumView(entry: entry, tone: tone)
            }
        }
        .widgetURL(MianyuWidgetDeepLink.activity)
    }

    private var activityTone: WidgetVisualTone {
        // 数据过期时降级为提醒色，避免拿旧数据当作当前完成度
        if widgetDataState(for: entry.lastSyncTime, staleAfter: entry.staleAfter, now: entry.date) == .stale { return .caution }
        guard let rate = entry.completionRate else { return .waiting }
        switch rate {
        case 0.85...: return .relaxed
        case 0.65..<0.85: return .steady
        case 0.35..<0.65: return .mild
        default: return .caution
        }
    }

    private var layoutTitle: String {
        entry.configuration.layout == .grid ? String(localized: "活动网格") : String(localized: "活动聚焦")
    }

    private var focusDescriptor: ActivityMetricDescriptor {
        activityPrimaryMetricDescriptor(for: entry)
    }
}

private struct ActivityMetricDescriptor: Equatable, Sendable {
    let icon: String
    let title: String
    let valueText: String
}

private func nonZeroValue(_ value: Int?) -> Int? {
    value.flatMap { $0 > 0 ? $0 : nil }
}

private func activityPrimaryMetricDescriptor(for entry: ActivityConfigurableEntry) -> ActivityMetricDescriptor {
    switch entry.configuration.primaryMetric {
    case .steps:
        return ActivityMetricDescriptor(icon: "figure.walk", title: String(localized: "步数"), valueText: nonZeroValue(entry.steps).map { "\($0)" } ?? "--")
    case .activeEnergy:
        return ActivityMetricDescriptor(icon: "flame.fill", title: String(localized: "活跃能量"), valueText: nonZeroValue(entry.activeEnergy).map { "\($0) kcal" } ?? "--")
    case .exerciseMinutes:
        return ActivityMetricDescriptor(icon: "figure.run", title: String(localized: "锻炼分钟"), valueText: nonZeroValue(entry.exerciseMinutes).map { "\($0)" } ?? "--")
    case .standHours:
        return ActivityMetricDescriptor(icon: "figure.stand", title: String(localized: "站立"), valueText: nonZeroValue(entry.standHours).map { String(localized: "\($0) 小时") } ?? "--")
    }
}

private struct ActivityConfigurableMediumView: View {
    let entry: ActivityConfigurableEntry
    let tone: WidgetVisualTone

    var body: some View {
        switch entry.configuration.layout {
        case .grid:
            ActivitySystemMediumCard(model: gridModel)
        case .focus:
            ActivityConfigurableFocusMediumCard(model: focusModel)
        }
    }

    private var focusModel: ActivityFocusModel {
        let descriptor = activityPrimaryMetricDescriptor(for: entry)
        return ActivityFocusModel(
            title: descriptor.title,
            subtitle: widgetProgressNarrative(progress: entry.completionRate, low: String(localized: "先完成今天的第一段活动"), medium: String(localized: "主指标已经动起来了，继续保持"), high: String(localized: "今天这项指标很稳，继续轻松维持")),
            icon: descriptor.icon,
            value: descriptor.valueText,
            syncTime: entry.lastSyncTime,
            staleAfter: entry.staleAfter,
            referenceDate: entry.date,
            tone: tone,
            progress: entry.completionRate ?? 0.16
        )
    }

    private var gridModel: ActivityCardModel {
        ActivityCardModel(
            title: String(localized: "活动网格"),
            subtitle: activitySubtitle,
            icon: "square.grid.2x2.fill",
            valueTitle: String(localized: "完成度"),
            valueText: entry.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "--",
            primaryMetricTitle: String(localized: "步数"),
            primaryMetricValue: entry.steps.map { "\($0)" } ?? "--",
            secondaryMetricTitle: String(localized: "活跃能量"),
            secondaryMetricValue: entry.activeEnergy.map { "\($0) kcal" } ?? "--",
            tertiaryMetricTitle: String(localized: "锻炼分钟"),
            tertiaryMetricValue: entry.exerciseMinutes.map { "\($0)" } ?? "--",
            quaternaryMetricTitle: String(localized: "站立"),
            quaternaryMetricValue: entry.standHours.map { String(localized: "\($0) 小时") } ?? "--",
            syncTime: entry.lastSyncTime,
            staleAfter: entry.staleAfter,
            referenceDate: entry.date,
            tone: tone,
            progress: entry.completionRate ?? 0.16
        )
    }

    private var activitySubtitle: String {
        guard let rate = entry.completionRate else { return String(localized: "等待同步") }
        switch rate {
        case 0.85...: return String(localized: "节奏很稳")
        case 0.65..<0.85: return String(localized: "持续保持")
        case 0.35..<0.65: return String(localized: "再动一动")
        default: return String(localized: "先起身活动")
        }
    }
}

private struct ActivityConfigurableLargeView: View {
    let entry: ActivityConfigurableEntry
    let tone: WidgetVisualTone

    var body: some View {
        switch entry.configuration.layout {
        case .grid:
            ActivitySystemLargeCard(model: gridModel)
        case .focus:
            ActivityConfigurableFocusLargeCard(model: focusModel)
        }
    }

    private var focusModel: ActivityFocusModel {
        let descriptor = activityPrimaryMetricDescriptor(for: entry)
        return ActivityFocusModel(
            title: descriptor.title,
            subtitle: String(localized: "主指标聚焦"),
            icon: descriptor.icon,
            value: descriptor.valueText,
            syncTime: entry.lastSyncTime,
            staleAfter: entry.staleAfter,
            referenceDate: entry.date,
            tone: tone,
            progress: entry.completionRate ?? 0.16
        )
    }

    private var gridModel: ActivityCardModel {
        ActivityCardModel(
            title: String(localized: "活动网格"),
            subtitle: String(localized: "把四项活动放在一张卡里"),
            icon: "square.grid.2x2.fill",
            valueTitle: String(localized: "完成度"),
            valueText: entry.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "--",
            primaryMetricTitle: String(localized: "步数"),
            primaryMetricValue: entry.steps.map { "\($0)" } ?? "--",
            secondaryMetricTitle: String(localized: "活跃能量"),
            secondaryMetricValue: entry.activeEnergy.map { "\($0) kcal" } ?? "--",
            tertiaryMetricTitle: String(localized: "锻炼分钟"),
            tertiaryMetricValue: entry.exerciseMinutes.map { "\($0)" } ?? "--",
            quaternaryMetricTitle: String(localized: "站立"),
            quaternaryMetricValue: entry.standHours.map { String(localized: "\($0) 小时") } ?? "--",
            syncTime: entry.lastSyncTime,
            staleAfter: entry.staleAfter,
            referenceDate: entry.date,
            tone: tone,
            progress: entry.completionRate ?? 0.16
        )
    }
}

private struct ActivityFocusModel: Sendable {
    let title: String
    let subtitle: String
    let icon: String
    let value: String
    let syncTime: Date?
    /// 域级过期窗口与 entry 参考时间，供卡片内时间/新鲜度文案使用
    let staleAfter: TimeInterval
    let referenceDate: Date
    let tone: WidgetVisualTone
    let progress: Double
}

private struct ActivityConfigurableFocusMediumCard: View {
    let model: ActivityFocusModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack(alignment: .trailing) {
            WidgetCardBackground(tone: model.tone, cornerRadius: 28)
            WidgetRingView(progress: model.progress, tint: model.tone.accent, lineWidth: 16)
                .frame(width: 118, height: 118)
                .overlay {
                    Image(systemName: model.icon)
                        .font(.widgetAppSystem(size: 28, weight: .bold))
                        .foregroundStyle(model.tone.accent)
                }
                .padding(.trailing, 20)
        }
        .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    WidgetAccentChip(icon: model.icon, text: String(localized: "活动聚焦"), tint: model.tone.accent)
                    Spacer(minLength: 0)
                    WidgetAccentChip(icon: "clock", text: widgetRelativeSyncText(for: model.syncTime, staleAfter: model.staleAfter, now: model.referenceDate), tint: model.tone.accent)
                }
                Text(model.title)
                    .font(.widgetAppSystem(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(model.tone.accent)
                Text(model.value)
                    .font(.widgetAppSystem(size: 20, weight: .bold))
                    .foregroundStyle(WidgetPalette.textPrimary)
                Text(model.subtitle)
                    .font(.widgetAppSystem(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetPalette.textSecondary)
                if model.value == "--" {
                    WidgetEmptyStateBanner(title: String(localized: "等待活动同步"), detail: String(localized: "同步后会聚焦展示你当前选择的主指标"), tint: model.tone.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .padding(.trailing, 122)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }
}

private struct ActivityConfigurableFocusLargeCard: View {
    let model: ActivityFocusModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        ZStack {
            WidgetCardBackground(tone: model.tone, cornerRadius: 32)
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    WidgetAccentChip(icon: model.icon, text: String(localized: "活动聚焦"), tint: model.tone.accent)
                    Spacer(minLength: 0)
                    WidgetAccentChip(icon: "clock", text: widgetRelativeSyncText(for: model.syncTime, staleAfter: model.staleAfter, now: model.referenceDate), tint: model.tone.accent)
                }
                Text(model.title)
                    .font(.widgetAppSystem(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(model.tone.accent)
                HStack(spacing: 14) {
                    WidgetRingView(progress: model.progress, tint: model.tone.accent, lineWidth: 17)
                        .frame(width: 112, height: 112)
                        .overlay {
                            Image(systemName: model.icon)
                                .font(.widgetAppSystem(size: 30, weight: .bold))
                                .foregroundStyle(model.tone.accent)
                        }
                    VStack(alignment: .leading, spacing: 10) {
                        WidgetMetricCard(title: model.title, value: model.value, tint: model.tone.accent)
                        if model.value == "--" {
                            WidgetEmptyStateBanner(title: String(localized: "等待活动同步"), detail: String(localized: "同步后会显示主指标数值和完成度趋势"), tint: model.tone.accent)
                        } else {
                            WidgetInsightBanner(title: String(localized: "今日建议"), value: model.subtitle, tint: model.tone.accent)
                        }
                    }
                }
                WidgetProgressStrip(title: String(localized: "活动完成度"), value: "\(Int((model.progress * 100).rounded()))%", progress: model.progress, tint: model.tone.accent)
                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .clipShape(shape)
        .containerBackground(for: .widget) { Color.clear }
    }
}

private struct ActivityConfigurableAccessoryCircularView: View {
    let entry: ActivityConfigurableEntry
    let tone: WidgetVisualTone

    var body: some View {
        if let rate = entry.completionRate {
            Gauge(value: rate, in: 0...1) {
                Image(systemName: activityPrimaryMetricDescriptor(for: entry).icon)
            } currentValueLabel: {
                Text("\(Int((rate * 100).rounded()))%")
            }
            .tint(tone.accent)
            .gaugeStyle(.accessoryCircular)
            // 锁屏着色模式下让系统统一渲染重点内容
            .widgetAccentable()
        } else {
            Image(systemName: activityPrimaryMetricDescriptor(for: entry).icon)
        }
    }
}

/// ActivityConfigurable小组件结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct ActivityConfigurableWidget: Widget {
    let kind: String = "ActivityWidgetConfigurable"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ActivityWidgetConfigurationIntent.self,
            provider: ActivityConfigurableProvider()
        ) { entry in
            ActivityConfigurableWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("活动（可配置）")
        .description("选择主指标与布局样式。")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

/// ActivityConfigurable小组件预览提供器 作为小组件扩展里的预览辅助类型。
/// 负责Widget 展示与配置。
struct ActivityConfigurableWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ActivityConfigurableWidgetEntryView(
                entry: ActivityConfigurableEntry(
                    date: .now,
                    configuration: {
                        let intent = ActivityWidgetConfigurationIntent()
                        intent.primaryMetric = .steps
                        intent.layout = .focus
                        return intent
                    }(),
                    steps: 7560,
                    activeEnergy: nil,
                    exerciseMinutes: nil,
                    standHours: nil,
                    completionRate: 0.62,
                    lastSyncTime: .now,
                    staleAfter: AppGroupSchema.Freshness.activityStaleAfter
                )
            )
            .previewContext(WidgetPreviewContext(family: .systemMedium))

            ActivityConfigurableWidgetEntryView(
                entry: ActivityConfigurableEntry(
                    date: .now,
                    configuration: {
                        let intent = ActivityWidgetConfigurationIntent()
                        intent.primaryMetric = .activeEnergy
                        intent.layout = .grid
                        return intent
                    }(),
                    steps: 10230,
                    activeEnergy: 610,
                    exerciseMinutes: 34,
                    standHours: 11,
                    completionRate: 0.91,
                    lastSyncTime: .now,
                    staleAfter: AppGroupSchema.Freshness.activityStaleAfter
                )
            )
            .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}