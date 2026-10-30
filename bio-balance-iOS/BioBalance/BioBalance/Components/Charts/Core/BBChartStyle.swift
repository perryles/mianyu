/// BB Chart Style 定义可复用界面组件，负责沉淀通用样式、交互结构或设计系统能力。
import SwiftUI
import Charts

/// BB枚举 作为设计系统里的状态与分类定义。
/// 负责描述通用组件与设计系统能力过程中会用到的状态、分类或分支。
enum BBChartStyle {
    static let linePrimary = Color.black
    static let lineSecondary = Color.gray
    static let areaPrimary = Theme.Colors.pastelCyan.opacity(0.5)
    static let areaSecondary = Theme.Colors.pastelGreen.opacity(0.5)
    static let point = Color.black.opacity(0.55)

    static let goalLine = Color.gray
    static let goalLineStroke = StrokeStyle(lineWidth: 1, dash: [4, 4])

    /// 图表语义色，保持“趋势线 / 基线 / 选中态 / 网格”在不同业务页里的含义一致。
    static let trendLine = Color(hex: "44515F")
    static let baseline = Color(hex: "00A79D")
    static let selection = Color(hex: "27313C")
    static let grid = Color(hex: "E8EAEC")
    static let plotBackground = Color.white
    static let surfaceBorder = Color(hex: "DDE6EF").opacity(0.82)
    static let elevatedSurface = Color.white

    /// 白色卡片承载图表，色彩集中在数据标记上。
    static func cardGradient(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white,
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 图表绘图区底色：只负责承托坐标轴和 marks，不承载业务状态。
    static func plotGradient(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                plotBackground,
                plotBackground
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 指标胶囊底色：用于图表上方/下方的当前值、均值、峰值等摘要。
    static func metricPillGradient(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                tint.opacity(0.07),
                tint.opacity(0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Emotion {
        static let happy = Color(hex: "20A66A")
        static let neutral = Color(hex: "3988E6")
        static let tired = Color(hex: "E5922D")
        static let anxious = Color(hex: "8A62C7")
        static let sad = Color(hex: "7B8794")
        static let unknown = Color(hex: "A0A8AE")

        static func color(for code: String) -> Color {
            switch code {
            case "happy": happy
            case "neutral": neutral
            case "tired": tired
            case "anxious": anxious
            case "sad": sad
            default: unknown
            }
        }

        static func title(for code: String) -> String {
            switch code {
            case "happy": "开心"
            case "neutral": "平静"
            case "tired": "疲惫"
            case "anxious": "焦虑"
            case "sad": "悲伤"
            default: code
            }
        }
    }

    /// Vitality Body 枚举，作为内部辅助类型，用于细分外层通用组件与设计系统能力中的状态或分支。
    enum VitalityBody {
        static let axis = Color(hex: "A2AFC4")
        static let grid = Color(hex: "DCE4F1")
        static let emptyBackground = Color(hex: "F7F3F6")
        static let emptyCard = Color.white.opacity(0.58)
    }
}

/// 图表标题区：只放标题、说明和一个可选图标，业务按钮和筛选器放在调用方。
struct BBChartHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String = "chart.xyaxis.line"
    var tint: Color = Theme.Colors.accentBlue
    var titleSize: CGFloat = 19
    var iconSize: CGFloat = 34
    var iconSymbolSize: CGFloat = 15

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.appSystem(size: iconSymbolSize, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: iconSize, height: iconSize)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

enum BBChartMetricPillSize: Equatable {
    case compact
    case regular

    var titleSize: CGFloat {
        switch self {
        case .compact: 10
        case .regular: 11
        }
    }

    var valueSize: CGFloat {
        switch self {
        case .compact: 14
        case .regular: 18
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: 14
        case .regular: 16
        }
    }
}

/// 图表摘要胶囊：统一承载“当前值 / 均值 / 极值”等短指标，不直接解释业务。
struct BBChartMetricPill: View {
    let title: String
    let value: String
    let tint: Color
    var size: BBChartMetricPillSize = .compact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: size.titleSize, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.appSystem(size: size.valueSize, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, size == .compact ? 10 : 12)
        .padding(.vertical, size == .compact ? 9 : 12)
        .background(BBChartStyle.metricPillGradient(tint: tint), in: RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 0.8)
        )
    }
}

/// 图表图例项：统一线段、圆点、三角等视觉说明，避免每个业务页自己拼 HStack。
struct BBChartLegendItem: View {
    enum Symbol {
        case line
        case dot
        case triangle
        case system(String)
    }

    let title: String
    let tint: Color
    var symbol: Symbol = .line

    var body: some View {
        HStack(spacing: 5) {
            symbolView

            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var symbolView: some View {
        switch symbol {
        case .line:
            Capsule()
                .fill(tint)
                .frame(width: 14, height: 2)
        case .dot:
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
        case .triangle:
            Image(systemName: "triangle.fill")
                .font(.appSystem(size: 8, weight: .bold))
                .foregroundStyle(tint)
        case .system(let name):
            Image(systemName: name)
                .font(.appSystem(size: 10, weight: .bold))
                .foregroundStyle(tint)
        }
    }
}

/// 图表选中读数条：参考 Pulse 的轻量 readout，用于展示当前选中点或默认最后一点。
struct BBChartSelectionReadout: View {
    let title: String
    let value: String
    var detail: String? = nil
    let tint: Color
    var systemImage: String = "scope"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .bbChartPlotSurface(tint: tint, cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }
}

/// 通用图表卡片：提供标题、空状态和 Pulse 式玻璃外壳，具体 Chart 内容由调用方传入。
struct BBChartCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let isEmpty: Bool
    var emptyTitle: String = String(localized: "暂无数据")
    var emptySystemImage: String = "chart.xyaxis.line"
    var systemImage: String = "chart.xyaxis.line"
    var tint: Color = Theme.Colors.accentBlue
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        isEmpty: Bool,
        emptyTitle: String = String(localized: "暂无数据"),
        emptySystemImage: String = "chart.xyaxis.line",
        systemImage: String = "chart.xyaxis.line",
        tint: Color = Theme.Colors.accentBlue,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.systemImage = systemImage
        self.tint = tint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BBChartHeader(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)

            if isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: emptySystemImage)
                        .font(.appSystem(size: 26, weight: .semibold))
                    Text(emptyTitle)
                        .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(height: 132)
                .frame(maxWidth: .infinity)
                .bbChartPlotSurface(tint: tint, cornerRadius: 18)
            } else {
                content()
            }
        }
        .padding(16)
        .bbChartSurface(tint: tint, cornerRadius: 26)
    }
}

private struct BBChartSurfaceModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    let shadow: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .bbLiquidGlassSurface(
                    tint: tint,
                    in: shape,
                    tintStrength: 0.06,
                    shadow: false
                )
                .shadow(
                    color: Color(hex: "283857").opacity(shadow ? 0.07 : 0),
                    radius: 14,
                    x: 0,
                    y: 6
                )
        } else {
            content
                .background(Color.white.opacity(0.86), in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.88), lineWidth: 1)
                }
                .shadow(
                    color: Color(hex: "283857").opacity(shadow ? 0.07 : 0),
                    radius: 14,
                    x: 0,
                    y: 6
                )
        }
    }
}

private struct BBChartPlotSurfaceModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(BBChartStyle.plotGradient(tint: tint), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BBChartStyle.grid.opacity(0.48), lineWidth: 1)
            )
    }
}

extension View {
    /// 图表外壳：适合整张趋势卡片；调用方负责 padding，避免重复内边距。
    func bbChartSurface(tint: Color = Theme.Colors.accentBlue, cornerRadius: CGFloat = 26, shadow: Bool = true) -> some View {
        modifier(BBChartSurfaceModifier(tint: tint, cornerRadius: cornerRadius, shadow: shadow))
    }

    /// 图表绘图区底：适合 Chart plot、空状态和迷你图，不应包裹整张卡片。
    func bbChartPlotSurface(tint: Color = Theme.Colors.accentBlue, cornerRadius: CGFloat = 18) -> some View {
        modifier(BBChartPlotSurfaceModifier(tint: tint, cornerRadius: cornerRadius))
    }
}

extension LineMark {
    func bbPrimaryLine() -> some ChartContent {
        foregroundStyle(BBChartStyle.linePrimary)
            .interpolationMethod(.catmullRom)
    }
    
    func bbSecondaryLine() -> some ChartContent {
        foregroundStyle(BBChartStyle.lineSecondary)
            .interpolationMethod(.catmullRom)
    }
}

extension AreaMark {
    func bbPrimaryArea() -> some ChartContent {
        foregroundStyle(BBChartStyle.areaPrimary)
            .interpolationMethod(.catmullRom)
    }
    
    func bbSecondaryArea() -> some ChartContent {
        foregroundStyle(BBChartStyle.areaSecondary)
            .interpolationMethod(.catmullRom)
    }
}

extension BarMark {
    func bbPrimaryBar(opacity: Double = 0.75) -> some ChartContent {
        foregroundStyle(Color.black.opacity(opacity))
    }
}

extension PointMark {
    func bbPoint() -> some ChartContent {
        foregroundStyle(BBChartStyle.point)
    }
}

extension RuleMark {
    func bbGoalLine() -> some ChartContent {
        foregroundStyle(BBChartStyle.goalLine)
            .lineStyle(BBChartStyle.goalLineStroke)
    }
}
