/// Widget Design System 定义 WidgetKit 小组件入口或配置，负责把应用中的关键数据以系统小组件的形式展示出来。
import SwiftUI
import WidgetKit

/// 小组件视觉色调枚举 作为小组件扩展里的状态与分类定义。
/// 负责描述Widget 展示与配置过程中会用到的状态、分类或分支。
enum WidgetVisualTone: String, CaseIterable, Sendable {
    case waiting
    case relaxed
    case steady
    case mild
    case caution
    case high

    var backgroundAssetName: String {
        switch self {
        case .waiting: return "TodayPressureWaiting"
        case .relaxed: return "TodayPressureRelaxed"
        case .steady: return "TodayPressureSteady"
        case .mild: return "TodayPressureMild"
        case .caution: return "TodayPressureCaution"
        case .high: return "TodayPressureHigh"
        }
    }

    var accent: Color {
        switch self {
        case .waiting: return WidgetPalette.accentGray
        case .relaxed: return WidgetPalette.mintGreen
        case .steady: return WidgetPalette.accentBlue
        case .mild: return WidgetPalette.brandCyan
        case .caution: return WidgetPalette.accentOrange
        case .high: return WidgetPalette.accentRed
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .waiting: return WidgetPalette.accentBlue
        case .relaxed: return WidgetPalette.brandCyan
        case .steady: return WidgetPalette.mintGreen
        case .mild: return WidgetPalette.accentBlue
        case .caution: return WidgetPalette.brandCyan
        case .high: return WidgetPalette.accentOrange
        }
    }
}

/// 小组件卡片主题结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct WidgetCardTheme: Sendable {
    let title: String
    let subtitle: String
    let emphasis: String
    let symbolName: String
    let tone: WidgetVisualTone
}

/// 小组件色板枚举 作为小组件扩展里的能力或分类定义。
/// 负责描述Widget 展示与配置过程中会用到的状态、分类或分支。
enum WidgetPalette {
    // 与主 App Theme 保持同一套中性色；扩展 target 不直接依赖主 App 类型。
    static let background = Color(hex: "F7F8F9")
    static let surface = Color.white
    static let secondarySurface = Color(hex: "F5F6F7")
    static let surfaceBorder = Color(hex: "E4E6E8")
    static let textPrimary = Color(hex: "242628")
    static let textSecondary = Color(hex: "595E62")
    static let textTertiary = Color(hex: "6C6C70")
    static let textPrimaryDark = Color.white.opacity(0.96)
    static let textSecondaryDark = Color.white.opacity(0.82)
    static let textTertiaryDark = Color.white.opacity(0.64)
    static let softCloud = secondarySurface
    static let brandBlue = Color(hex: "1F85FF")
    static let brandCyan = Color(hex: "1BCDE4")
    static let brandGreen = Color(hex: "2BE66B")
    static let mintGreen = Color(hex: "007A74")
    static let accentBlue = Color(hex: "0066CC")
    static let accentRed = Color(hex: "D70015")
    static let accentOrange = Color(hex: "B25000")
    static let accentGray = textTertiary
    static let blush = Color(hex: "FFC8D1")
    static let glassHighlight = Color.white.opacity(0.72)
    static let glassShadow = Color.black.opacity(0.10)
    static let glassDarkFill = Color.black.opacity(0.24)
    static let glassLightFill = Color.white.opacity(0.28)
    static let glassDarkStroke = Color.white.opacity(0.14)
}

enum WidgetGlassMetrics {
    static let outerRadiusSmall: CGFloat = 24
    static let outerRadiusMedium: CGFloat = 30
    static let outerRadiusLarge: CGFloat = 34
    static let innerRadius: CGFloat = 18
    static let tileRadius: CGFloat = 16
    static let outerPaddingSmall: CGFloat = 16
    static let outerPadding: CGFloat = 20
    static let innerPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 10
    static let smallCornerOrbSize: CGFloat = 62
    static let smallCornerOrbInset: CGFloat = 14
    static let mediumOrbSize: CGFloat = 118
    static let mediumOrbTrailingInset: CGFloat = 20
    static let mediumContentTrailingReserve: CGFloat = 122
}

/// 深色、数据优先的卡片表面采用紧凑信息层级：
/// 先展示一个主指标，再展示一个可视化，最后提供简短说明。
/// 无论系统外观如何都保持深色，以确保分类颜色在小组件图库和主屏幕中
/// 始终表达一致含义。
struct WidgetReferenceCardBackground: View {
    let tint: Color
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            LinearGradient(
                colors: [Color(hex: "11141A"), Color(hex: "080A0E")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [tint.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 180
            )
            LinearGradient(
                colors: [Color.white.opacity(0.05), .clear, Color.black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.11), lineWidth: 0.8))
    }
}

struct WidgetReferenceHeader: View {
    let icon: String
    let title: String
    let status: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(.widgetAppSystem(size: 9, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.82)))
                .widgetAccentable()

            Spacer(minLength: 2)

            Text(status)
                .font(.widgetAppSystem(size: 9, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.54)))
                .widgetAccentable()
        }
    }
}

struct WidgetReferenceMetric: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.widgetAppSystem(size: 32, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(unit)
                .font(.widgetAppSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct WidgetReferenceBars: View {
    let values: [Double]
    let tint: Color
    var secondaryTint: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            let clampedValues = values.map { min(1, max(0, $0)) }
            let peakIndex = clampedValues.enumerated().max { lhs, rhs in
                lhs.element < rhs.element
            }?.offset

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.055))
                            .frame(height: 0.5)
                        Spacer(minLength: 0)
                    }
                }

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(clampedValues.enumerated()), id: \.offset) { index, clamped in
                        let color = index.isMultiple(of: 3) ? (secondaryTint ?? tint) : tint
                        let barHeight = max(4, proxy.size.height * clamped)
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Color.white.opacity(0.07))
                            if clamped > 0 {
                                Capsule()
                                    .fill(color.opacity(0.94))
                                    .frame(height: barHeight)
                                    .widgetAccentable()

                                if index == peakIndex {
                                    Circle()
                                        .fill(Color.white.opacity(0.92))
                                        .frame(width: 4, height: 4)
                                        .offset(y: -(barHeight - 2))
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct WidgetReferenceSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 0.5)
                        Spacer(minLength: 0)
                    }
                }

                if values.count == 1, let value = values.first {
                    let clamped = min(1, max(0, value))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width, height: 4)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * (1 - clamped))
                        .widgetAccentable()

                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(tint, lineWidth: 2))
                        .position(
                            x: max(3, proxy.size.width - 3),
                            y: min(proxy.size.height - 3, max(3, proxy.size.height * (1 - clamped)))
                        )
                } else if values.count > 1 {
                    Path { path in
                        for (index, value) in values.enumerated() {
                            let x = proxy.size.width * CGFloat(index) / CGFloat(values.count - 1)
                            let y = proxy.size.height * CGFloat(1 - min(1, max(0, value)))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.015)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        for (index, value) in values.enumerated() {
                            let x = proxy.size.width * CGFloat(index) / CGFloat(values.count - 1)
                            let y = proxy.size.height * CGFloat(1 - min(1, max(0, value)))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .widgetAccentable()

                    if let value = values.last {
                        let clamped = min(1, max(0, value))
                        Circle()
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(tint, lineWidth: 2))
                            .position(
                                x: max(3.5, proxy.size.width - 3.5),
                                y: min(proxy.size.height - 3.5, max(3.5, proxy.size.height * (1 - clamped)))
                            )
                            .widgetAccentable()
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct WidgetReferenceProgressTrack: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                if clamped > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.70), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(5, proxy.size.width * clamped))
                        .widgetAccentable()

                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(tint, lineWidth: 1.5))
                        .position(
                            x: min(proxy.size.width - 3, max(3, proxy.size.width * clamped)),
                            y: proxy.size.height / 2
                        )
                        .widgetAccentable()
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct WidgetReferenceStat: Identifiable {
    let id: String
    let value: String
    let label: String
    let tint: Color

    init(id: String? = nil, value: String, label: String, tint: Color) {
        self.id = id ?? label
        self.value = value
        self.label = label
        self.tint = tint
    }
}

struct WidgetReferenceFooter: View {
    let stats: [WidgetReferenceStat]

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.11))
                        .frame(width: 0.5, height: 20)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(stat.value)
                        .font(.widgetAppSystem(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(stat.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .widgetAccentable()
                    Text(stat.label)
                        .font(.widgetAppSystem(size: 7, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.46))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct WidgetGlassStyle: Sendable {
    let baseFill: Color
    let secondaryFill: Color
    let stroke: Color
    let highlight: Color
    let shadow: Color
}

private func widgetGlassStyle(for tone: WidgetVisualTone, colorScheme: ColorScheme) -> WidgetGlassStyle {
    let accent = tone.accent
    if colorScheme == .dark {
        return WidgetGlassStyle(
            baseFill: WidgetPalette.glassDarkFill,
            secondaryFill: accent.opacity(0.18),
            stroke: WidgetPalette.glassDarkStroke,
            highlight: Color.white.opacity(0.16),
            shadow: Color.black.opacity(0.24)
        )
    }

    return WidgetGlassStyle(
        baseFill: WidgetPalette.glassLightFill,
        secondaryFill: accent.opacity(0.12),
        stroke: Color.white.opacity(0.62),
        highlight: WidgetPalette.glassHighlight,
        shadow: WidgetPalette.glassShadow
    )
}

struct WidgetGlassContainer<Content: View>: View {
    let tone: WidgetVisualTone
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let style = widgetGlassStyle(for: tone, colorScheme: colorScheme)

        ZStack {
            WidgetBackgroundImage(tone: tone)
            LinearGradient(
                colors: [
                    style.highlight.opacity(colorScheme == .dark ? 0.20 : 0.72),
                    style.baseFill,
                    style.secondaryFill
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [tone.accent.opacity(colorScheme == .dark ? 0.18 : 0.14), .clear],
                center: .topLeading,
                startRadius: 12,
                endRadius: 220
            )
        }
        .clipShape(shape)
        .overlay(shape.fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.18)))
        .overlay(shape.strokeBorder(style.stroke, lineWidth: 0.9))
        .overlay(
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [style.highlight.opacity(0.75), .clear, style.shadow.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(content)
    }
}

struct WidgetGlassTile<Content: View>: View {
    let tint: Color
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.09 : 0.92),
                                tint.opacity(colorScheme == .dark ? 0.16 : 0.08),
                                Color.black.opacity(colorScheme == .dark ? 0.10 : 0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        shape.fill(Color.white.opacity(colorScheme == .dark ? 0.03 : 0.12))
                    )
                    .overlay(
                        shape.strokeBorder(
                            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.40),
                            lineWidth: 0.8
                        )
                    )
                )
    }
}

struct WidgetGlassBadge: View {
    let icon: String
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.widgetAppSystem(size: 10, weight: .bold))
            Text(text)
                .font(.widgetAppSystem(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.12), tint.opacity(0.18)]
                            : [Color.white.opacity(0.92), tint.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(Capsule().strokeBorder(tint.opacity(colorScheme == .dark ? 0.28 : 0.14), lineWidth: 0.8))
    }
}

/// 小组件视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct WidgetCardBackground: View {
    let tone: WidgetVisualTone
    let cornerRadius: CGFloat

    var body: some View {
        WidgetGlassContainer(tone: tone, cornerRadius: cornerRadius) { EmptyView() }
    }
}

/// 小组件背景Image结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct WidgetBackgroundImage: View {
    let tone: WidgetVisualTone
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark ? darkBackgroundColors : backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var backgroundColors: [Color] {
        switch tone {
        case .waiting:
            return [Color.white, WidgetPalette.softCloud, Color.white]
        case .relaxed:
            return [Color.white, WidgetPalette.mintGreen.opacity(0.18), WidgetPalette.brandCyan.opacity(0.14)]
        case .steady:
            return [Color.white, WidgetPalette.accentBlue.opacity(0.16), WidgetPalette.softCloud]
        case .mild:
            return [Color.white, WidgetPalette.brandCyan.opacity(0.18), WidgetPalette.accentOrange.opacity(0.08)]
        case .caution:
            return [Color.white, WidgetPalette.accentOrange.opacity(0.16), WidgetPalette.blush.opacity(0.10)]
        case .high:
            return [Color.white, WidgetPalette.accentRed.opacity(0.12), WidgetPalette.blush.opacity(0.16)]
        }
    }

    /// 深色模式使用深底 + 低透明度色调渐变，避免纯白底盖过深色文字方案
    private var darkBackgroundColors: [Color] {
        let base = Color(hex: "17181D")
        let deep = Color(hex: "23242B")
        switch tone {
        case .waiting:
            return [base, deep, base]
        default:
            return [base, tone.accent.opacity(0.24), deep]
        }
    }
}

/// 小组件强调标签组件 作为小组件扩展里的信息标签组件。
/// 负责Widget 展示与配置。
struct WidgetAccentChip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        WidgetGlassBadge(icon: icon, text: text, tint: tint)
    }
}

/// 小组件信息标签组件 作为小组件扩展里的信息标签组件。
/// 负责Widget 展示与配置。
struct WidgetInfoPill: View {
    let icon: String
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.widgetAppSystem(size: 10, weight: .bold))
            Text(text)
                .font(.widgetAppSystem(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(colorScheme == .dark ? WidgetPalette.textSecondaryDark : WidgetPalette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.76)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.12), lineWidth: 1))
    }
}

/// 小组件指标卡片组件 作为小组件扩展里的内容展示卡片。
/// 负责Widget 展示与配置。
struct WidgetMetricCard: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WidgetGlassTile(tint: tint, cornerRadius: WidgetGlassMetrics.tileRadius) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.widgetAppSystem(size: 11, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                Text(value)
                    .font(.widgetAppSystem(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? WidgetPalette.textPrimaryDark : WidgetPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

/// 小组件操作标签组件 作为小组件扩展里的信息标签组件。
/// 负责Widget 展示与配置。
struct WidgetActionCapsule: View {
    let title: String
    let icon: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.widgetAppSystem(size: 11, weight: .bold))
            Text(title)
                .font(.widgetAppSystem(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.84)))
        .overlay(Capsule().strokeBorder(tint.opacity(colorScheme == .dark ? 0.30 : 0.16), lineWidth: 1))
    }
}

/// 小组件操作卡片组件 作为小组件扩展里的内容展示卡片。
/// 负责Widget 展示与配置。
struct WidgetActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WidgetGlassTile(tint: tint, cornerRadius: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.widgetAppSystem(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.widgetAppSystem(size: 13, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? WidgetPalette.textPrimaryDark : WidgetPalette.textPrimary)
                    Text(subtitle)
                        .font(.widgetAppSystem(size: 11, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// 小组件环形视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct WidgetRingView: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.06, min(1, progress)))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint, tint.opacity(0.90)], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

/// 小组件进度结构体 作为小组件扩展里的辅助类型。
/// 负责Widget 展示与配置。
struct WidgetProgressStrip: View {
    let title: String
    let value: String
    let progress: Double
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WidgetGlassTile(tint: tint, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.widgetAppSystem(size: 12, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                    Spacer(minLength: 0)
                    Text(value)
                        .font(.widgetAppSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(colorScheme == .dark ? WidgetPalette.textSecondaryDark : WidgetPalette.textSecondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.14))
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * max(0, min(1, progress)))
                    }
                }
                .frame(height: 7)
            }
        }
    }
}

/// 小组件解读视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct WidgetInsightBanner: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WidgetGlassTile(tint: tint, cornerRadius: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.widgetAppSystem(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(tint.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.widgetAppSystem(size: 11, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                    Text(value)
                        .font(.widgetAppSystem(size: 12, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? WidgetPalette.textSecondaryDark : WidgetPalette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

/// 小组件空状态视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct WidgetEmptyStateBanner: View {
    let title: String
    let detail: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WidgetGlassTile(tint: tint, cornerRadius: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.widgetAppSystem(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.92)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.widgetAppSystem(size: 11, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? WidgetPalette.textSecondaryDark : WidgetPalette.textSecondary)
                    Text(detail)
                        .font(.widgetAppSystem(size: 12, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? WidgetPalette.textTertiaryDark : WidgetPalette.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(detail)")
    }
}

/// 小组件配件摘要视图 由上级页面或路由调用，作为小组件扩展里的界面或内容组件。
/// 负责Widget 展示与配置。
struct WidgetAccessorySummaryView: View {
    let label: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        // 锁屏配件由系统做 vibrancy/着色渲染，使用语义色而非固定调色板颜色
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .widgetAccentable()
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

func widgetRelativeSyncText(for date: Date?, staleAfter: TimeInterval = 6 * 60 * 60, now: Date = Date()) -> String {
    guard let date else { return String(localized: "待同步") }
    if widgetDataState(for: date, staleAfter: staleAfter, now: now) == .stale { return String(localized: "数据较旧") }
    let delta = max(0, Int(now.timeIntervalSince(date)))
    if delta < 60 { return String(localized: "刚刚") }
    if delta < 3600 { return String(localized: "\(delta / 60) 分钟前") }
    return String(localized: "\(delta / 3600) 小时前")
}

func widgetClockText(for date: Date?, staleAfter: TimeInterval = 6 * 60 * 60, now: Date = Date()) -> String {
    guard let date else { return String(localized: "待同步") }
    if widgetDataState(for: date, staleAfter: staleAfter, now: now) == .stale { return String(localized: "较旧") }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

/// 小组件数据枚举 作为小组件扩展里的状态与分类定义。
/// 负责描述Widget 展示与配置过程中会用到的状态、分类或分支。
enum WidgetDataState: Sendable {
    case missing
    case fresh
    case stale
}

func widgetDataState(for lastSyncTime: Date?, staleAfter interval: TimeInterval = 6 * 60 * 60, now: Date = Date()) -> WidgetDataState {
    guard let lastSyncTime else { return .missing }
    return now.timeIntervalSince(lastSyncTime) > interval ? .stale : .fresh
}

func widgetHasValidValue(_ value: Double?) -> Bool {
    guard let value else { return false }
    return value > 0
}

func widgetHasValidValue(_ value: Int?) -> Bool {
    guard let value else { return false }
    return value > 0
}

func widgetIsFreshAndValid(_ value: Double?, lastSyncTime: Date?, staleAfter: TimeInterval = 6 * 60 * 60, now: Date = Date()) -> Bool {
    widgetHasValidValue(value) && widgetDataState(for: lastSyncTime, staleAfter: staleAfter, now: now) == .fresh
}

func widgetIsFreshAndValid(_ value: Int?, lastSyncTime: Date?, staleAfter: TimeInterval = 6 * 60 * 60, now: Date = Date()) -> Bool {
    widgetHasValidValue(value) && widgetDataState(for: lastSyncTime, staleAfter: staleAfter, now: now) == .fresh
}

func widgetIsFreshStress(_ value: Double?, lastSyncTime: Date?, staleAfter: TimeInterval = 6 * 60 * 60, now: Date = Date()) -> Bool {
    guard let value, value >= 0 else { return false }
    return widgetDataState(for: lastSyncTime, staleAfter: staleAfter, now: now) == .fresh
}

func widgetStaleStateDetail(metric: String) -> String {
    String(localized: "上次同步时间较早，\(metric) 仅供参考")
}

func widgetToneForStress(_ stress: Double?) -> WidgetVisualTone {
    guard let stress, stress >= 0 else { return .waiting }
    switch stress {
    case ..<30: return .relaxed
    case ..<50: return .steady
    case ..<70: return .mild
    case ..<85: return .caution
    default: return .high
    }
}

func widgetStressLabel(_ stress: Double?) -> String {
    guard let stress, stress >= 0 else { return String(localized: "待同步") }
    switch stress {
    case ..<30: return String(localized: "放松")
    case ..<50: return String(localized: "平稳")
    case ..<70: return String(localized: "轻度压力")
    case ..<85: return String(localized: "注意压力")
    default: return String(localized: "压力偏高")
    }
}

func widgetDurationText(minutes: Int?) -> String {
    guard let minutes, minutes > 0 else { return "--" }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if Locale.preferredLanguages.first?.hasPrefix("zh") == true {
        if remainingMinutes == 0 { return String(localized: "\(hours)小时") }
        return String(localized: "\(hours)小时\(remainingMinutes)分钟")
    }
    if remainingMinutes == 0 { return "\(hours)h" }
    return "\(hours)h \(remainingMinutes)m"
}

func widgetOptionalIntText(_ value: Int?, suffix: String = "") -> String {
    guard let value else { return "--" }
    return "\(value)\(suffix)"
}

func widgetOptionalDoubleText(_ value: Double?, suffix: String = "") -> String {
    guard let value else { return "--" }
    return "\(Int(value.rounded()))\(suffix)"
}

func widgetProgressNarrative(progress: Double?, low: String, medium: String, high: String, empty: String = String(localized: "等待同步")) -> String {
    guard let progress else { return empty }
    switch progress {
    case 0.8...: return high
    case 0.45..<0.8: return medium
    default: return low
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
