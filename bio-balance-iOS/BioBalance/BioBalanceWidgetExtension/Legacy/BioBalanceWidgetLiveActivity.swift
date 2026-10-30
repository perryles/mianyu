/// Bio Balance Widget Live Activity 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
import ActivityKit
import WidgetKit
import SwiftUI

/// 应用小组件LiveActivity结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct MianyuWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MianyuWidgetAttributes.self) { context in
            ReminderLiveActivityLockScreenView(context: context)
                .widgetURL(Self.deepLink(for: context.attributes))
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(Color(.label))
        } dynamicIsland: { context in
            let tone = WidgetVisualTone(rawValue: context.state.tone) ?? .steady
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("眠屿", systemImage: context.state.symbolName)
                        .font(.headline)
                        .foregroundStyle(tone.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ReminderCountdownText(state: context.state, style: .expanded)
                        .foregroundStyle(tone.accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: context.state.symbolName)
                                .font(.body)
                                .foregroundStyle(tone.accent)
                            Text(context.state.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        ReminderCountdownBar(state: context.state, tint: tone.accent)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tone.accent)
            } compactTrailing: {
                ReminderCountdownText(state: context.state, style: .compact)
                    .foregroundStyle(tone.accent)
            } minimal: {
                ReminderCountdownRing(state: context.state, tint: tone.accent)
            }
            .widgetURL(Self.deepLink(for: context.attributes))
            .keylineTint(tone.accent)
        }
        // iOS 18+: 支持 Apple Watch 智能叠放、CarPlay 和 macOS 菜单栏展示
        .supplementalActivityFamilies([.small, .medium])
    }

    // MARK: - 深层链接

    /// 优先携带提醒标识符供应用侧精确路由；无标识符的旧版活动回退为名称
    fileprivate static func deepLink(for attributes: MianyuWidgetAttributes) -> URL {
        let target = attributes.reminderIdentifier ?? attributes.name
        let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
        return URL(string: "biobalance://reminder/\(encoded)")!
    }
}

// MARK: - 锁屏与补充家族布局

/// 锁屏横幅视图，按 activityFamily 区分完整布局与紧凑布局（智能叠放/CarPlay/macOS 菜单栏）。
private struct ReminderLiveActivityLockScreenView: View {
    let context: ActivityViewContext<MianyuWidgetAttributes>
    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.colorScheme) private var colorScheme

    private var tone: WidgetVisualTone {
        WidgetVisualTone(rawValue: context.state.tone) ?? .steady
    }

    var body: some View {
        switch activityFamily {
        case .small:
            smallFamilyBody
        default:
            fullBody
        }
    }

    /// 紧凑布局：单行图标 + 标题 + 副标题 + 倒计时
    private var smallFamilyBody: some View {
        HStack(spacing: 8) {
            Image(systemName: context.state.symbolName)
                .font(.body.weight(.bold))
                .foregroundStyle(tone.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(context.state.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(context.state.supplementalSubtitle ?? context.state.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            ReminderCountdownText(state: context.state, style: .compact)
                .foregroundStyle(tone.accent)
        }
        .padding(10)
    }

    /// 完整锁屏布局：卡片背景 + 标题 + 指标/建议双卡
    private var fullBody: some View {
        ZStack {
            WidgetCardBackground(tone: tone, cornerRadius: 24)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    WidgetAccentChip(icon: context.state.symbolName, text: String(localized: "眠屿 Live"), tint: tone.accent)
                    Spacer(minLength: 0)
                    if let fireDate = context.state.fireDate, fireDate > Date() {
                        Text(timerInterval: Date.now...fireDate, countsDown: true)
                            .font(.widgetAppSystem(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 72)
                            .foregroundStyle(tone.accent)
                    } else {
                        Text(context.attributes.name)
                            .font(.widgetAppSystem(size: 12, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                    }
                }
                Text(context.state.title)
                    .font(.widgetAppSystem(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(tone.accent)
                HStack(spacing: 10) {
                    WidgetMetricCard(title: String(localized: "当前指标"), value: context.state.primaryValue, tint: tone.accent)
                    WidgetInsightBanner(title: String(localized: "建议"), value: context.state.detail, tint: tone.accent)
                }
                ReminderCountdownBar(state: context.state, tint: tone.accent)
            }
        }
        .padding(16)
    }
}

/// 倒计时文本：fireDate 在未来时显示系统自动更新的计时器，否则回退为静态主指标文案。
private struct ReminderCountdownText: View {
    enum Style {
        case compact
        case expanded
    }

    let state: MianyuWidgetAttributes.ContentState
    let style: Style

    var body: some View {
        Group {
            if let fireDate = state.fireDate, fireDate > Date() {
                Text(timerInterval: Date.now...fireDate, countsDown: true)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: style == .compact ? 46 : 72)
            } else {
                Text(state.primaryValue)
                    .lineLimit(1)
            }
        }
        .font(font)
        .monospacedDigit()
        .contentTransition(.numericText())
    }

    private var font: Font {
        switch style {
        case .compact: return .caption2.weight(.semibold)
        case .expanded: return .title3.weight(.bold)
        }
    }
}

/// 倒计时进度条：系统自动驱动消耗，仅在具备完整起止时间且尚未到期时展示。
private struct ReminderCountdownBar: View {
    let state: MianyuWidgetAttributes.ContentState
    let tint: Color

    var body: some View {
        if let startDate = state.startDate, let fireDate = state.fireDate,
           startDate < fireDate, fireDate > Date() {
            ProgressView(timerInterval: startDate...fireDate, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(tint)
        }
    }
}

/// 灵动岛 minimal 态：环形倒计时包裹提醒图标，无倒计时时回退为纯图标。
private struct ReminderCountdownRing: View {
    let state: MianyuWidgetAttributes.ContentState
    let tint: Color

    var body: some View {
        if let startDate = state.startDate, let fireDate = state.fireDate,
           startDate < fireDate, fireDate > Date() {
            ProgressView(timerInterval: startDate...fireDate, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: state.symbolName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
            .progressViewStyle(.circular)
            .tint(tint)
        } else {
            Image(systemName: state.symbolName)
                .foregroundStyle(tint)
        }
    }
}

extension MianyuWidgetAttributes {
    fileprivate static var preview: MianyuWidgetAttributes {
        MianyuWidgetAttributes(name: "综合状态", reminderIdentifier: "preview.overall")
    }
}

extension MianyuWidgetAttributes.ContentState {
    fileprivate static var relaxed: MianyuWidgetAttributes.ContentState {
        MianyuWidgetAttributes.ContentState(
            title: "恢复在线",
            primaryValue: "HRV 61ms",
            detail: "今天可以维持正常强度",
            tone: WidgetVisualTone.relaxed.rawValue,
            symbolName: "waveform.path.ecg",
            supplementalSubtitle: "HRV 61ms · 恢复在线"
        )
    }

    fileprivate static var hydration: MianyuWidgetAttributes.ContentState {
        MianyuWidgetAttributes.ContentState(
            title: "记得补水",
            primaryValue: "40%",
            detail: "现在补 250ml 会更舒服",
            tone: WidgetVisualTone.mild.rawValue,
            symbolName: "drop.fill",
            supplementalSubtitle: "40% · 记得补水",
            fireDate: Date().addingTimeInterval(25 * 60),
            startDate: Date()
        )
    }
}

#if ENABLE_WIDGET_PREVIEWS
#Preview("Notification", as: .content, using: MianyuWidgetAttributes.preview) {
    MianyuWidgetLiveActivity()
} contentStates: {
    MianyuWidgetAttributes.ContentState.relaxed
    MianyuWidgetAttributes.ContentState.hydration
}
#endif
