/// Theme 定义可复用界面组件，负责沉淀通用样式、交互结构或设计系统能力。
import SwiftUI
import UIKit

/// 按当前地区格式化整数百分比。
func localizedPercent<Value: BinaryInteger>(_ wholePercent: Value) -> String {
    (Double(wholePercent) / 100)
        .formatted(.percent.precision(.fractionLength(0)))
}

/// 将 0...1 的比例按当前地区格式化为百分比。
func localizedPercentRatio<Value: BinaryFloatingPoint>(_ ratio: Value) -> String {
    Double(ratio).formatted(.percent.precision(.fractionLength(0)))
}

/// App字体缩放Level枚举 作为通用组件层里的能力或分类定义。
/// 负责描述通用组件与设计系统能力过程中会用到的状态、分类或分支。
enum AppFontScaleLevel: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4

    var id: Int { rawValue }

    static var storageKey: String { "app_font_scale_level" }
    static var current: AppFontScaleLevel {
        AppFontScaleStore.shared.level
    }

    var scaleMultiplier: CGFloat {
        switch self {
        case .one: return 0.92
        case .two: return 1.0
        case .three: return 1.08
        case .four: return 1.16
        }
    }

    var compactSpacingMultiplier: CGFloat {
        switch self {
        case .one: return 0.92
        case .two: return 1.0
        case .three: return 1.04
        case .four: return 1.08
        }
    }

    var displayTitle: String {
        switch self {
        case .one: return "小"
        case .two: return "标准"
        case .three: return "大"
        case .four: return "超大"
        }
    }

    var previewText: String {
        switch self {
        case .one: return "预览文字更紧凑"
        case .two: return "预览文字标准"
        case .three: return "预览文字偏大"
        case .four: return "预览文字更大"
        }
    }
}

/// App字体缩放存储器 作为通用组件层里的数据读写与状态保存入口。
/// 负责通用组件与设计系统能力。
@MainActor
@Observable
final class AppFontScaleStore {
    static let shared = AppFontScaleStore()

    private(set) var level: AppFontScaleLevel

    private let sharedDefaults: UserDefaults?
    private let standardDefaults: UserDefaults

    private init(
        sharedDefaults: UserDefaults? = AppGroupManager.userDefaults(),
        standardDefaults: UserDefaults = .standard
    ) {
        self.sharedDefaults = sharedDefaults
        self.standardDefaults = standardDefaults

        let resolvedLevel = Self.resolveInitialLevel(sharedDefaults: sharedDefaults, standardDefaults: standardDefaults)
        self.level = resolvedLevel
        persist(resolvedLevel, shouldReloadWidgets: false)
    }

    func update(level newLevel: AppFontScaleLevel) {
        guard level != newLevel else {
            persist(newLevel, shouldReloadWidgets: false)
            return
        }
        level = newLevel
        persist(newLevel, shouldReloadWidgets: true)
    }

    private func persist(_ level: AppFontScaleLevel, shouldReloadWidgets: Bool) {
        standardDefaults.set(level.rawValue, forKey: AppFontScaleLevel.storageKey)
        sharedDefaults?.set(level.rawValue, forKey: AppFontScaleLevel.storageKey)

        if shouldReloadWidgets {
            WidgetRefreshCoordinator.refresh(reason: .appearance)
        }
    }

    private static func resolveInitialLevel(sharedDefaults: UserDefaults?, standardDefaults: UserDefaults) -> AppFontScaleLevel {
        if let sharedDefaults,
           let level = AppFontScaleLevel(rawValue: sharedDefaults.integer(forKey: AppFontScaleLevel.storageKey)),
           level != .two || sharedDefaults.object(forKey: AppFontScaleLevel.storageKey) != nil {
            return level
        }

        if let level = AppFontScaleLevel(rawValue: standardDefaults.integer(forKey: AppFontScaleLevel.storageKey)),
           level != .two || standardDefaults.object(forKey: AppFontScaleLevel.storageKey) != nil {
            return level
        }

        return .two
    }
}

private struct AppFontScaleLevelEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppFontScaleLevel = .current
}

extension EnvironmentValues {
    var appFontScaleLevel: AppFontScaleLevel {
        get { self[AppFontScaleLevelEnvironmentKey.self] }
        set { self[AppFontScaleLevelEnvironmentKey.self] = newValue }
    }
}

/// 主题结构体 作为通用组件层里的辅助类型。
/// 负责通用组件与设计系统能力。
struct Theme {
    // MARK: - 色彩
    /// Colors 结构体，作为内部辅助类型，用于配合外层通用组件与设计系统能力。
    struct Colors {
        // 中性底色搭配深色文字，强调色用于操作与状态。
        static let background = Color.white // 无卡片化布局的纯白背景
        static let surface = Color.white
        static let pageBackground = Color(hex: "F7F8F9")
        static let secondaryBackground = Color(hex: "E9EBED") // 次级背景，用于分隔块或底衬
        static let secondarySurface = Color(hex: "F5F6F7")
        static let surfaceBorder = Color(hex: "E4E6E8")
        
        static let textPrimary = Color(hex: "242628") // 主标题与正文
        static let textSecondary = Color(hex: "595E62") // 深灰文字
        static let textTertiary = Color(hex: "6C6C70") // 浅灰文字（对比度 ≥4.5:1，PEN-2 P0-3）
        static let onAccent = Color.white
        static let primaryAction = textPrimary
        
        // 参考色板：柔和彩色只用于图形填充，不用于小字号文字。
        static let pastelCyan = Color(hex: "BFE6EA")
        static let pastelGreen = Color(hex: "D3E9B9")
        static let pastelYellow = Color(hex: "F9E589")
        static let pastelMint = Color(hex: "C4E6D5")

        // 强调色体系
        static let mintGreen = Color(hex: "007A74") // 核心强调色（加深保证文字对比度 ≥4.5:1，PEN-2 P0-3）
        static let mintGreenLight = Color(hex: "007A74").opacity(0.15)
        
        static let accentRed = Color(hex: "D70015") // 警示或高对比度强调色（加深保证文字对比度，PEN-2 P0-3）
        static let accentOrange = Color(hex: "B25000") // 中等级提示或谨慎状态色（加深保证文字对比度，PEN-2 P0-3）
        static let accentBlue = Color(hex: "0066CC") // 行动点或链接色（加深保证文字对比度，PEN-2 P0-3）
        
        static let lightGray = Color(hex: "E5E5EA") // 淡灰色，用于分隔线
        
        static let white = Color.white
        static let clear = Color.clear
    }
    
    // MARK: - 字体
    /// Typography 结构体，作为内部辅助类型，用于配合外层通用组件与设计系统能力。
    struct Typography {
        private static func scaledSize(_ size: CGFloat, level: AppFontScaleLevel = .current) -> CGFloat {
            size * level.scaleMultiplier
        }

        static func scaled(size: CGFloat, weight: Font.Weight, design: Font.Design = .default, level: AppFontScaleLevel = .current) -> Font {
            .system(size: scaledSize(size, level: level), weight: weight, design: design)
        }

        // 页面只使用这组语义层级，避免相邻组件出现大量近似字号。
        static var pageTitle: Font { scaled(size: 28, weight: .black, design: .rounded) }
        static var sectionTitle: Font { scaled(size: 20, weight: .bold, design: .rounded) }
        static var cardTitle: Font { scaled(size: 17, weight: .bold, design: .rounded) }
        static var body: Font { scaled(size: 16, weight: .regular, design: .rounded) }
        static var bodyMedium: Font { scaled(size: 16, weight: .medium, design: .rounded) }
        static var bodyBold: Font { scaled(size: 16, weight: .bold, design: .rounded) }
        static var supporting: Font { scaled(size: 13, weight: .medium, design: .rounded) }
        static var label: Font { scaled(size: 12, weight: .bold, design: .rounded) }
        static var caption: Font { scaled(size: 13, weight: .regular, design: .rounded) }
        static var captionBold: Font { scaled(size: 13, weight: .bold, design: .rounded) }

        // 兼容原有命名；新页面优先使用上方的语义名称。
        static var title: Font { pageTitle }
        static var headline: Font { sectionTitle }
        
        // 超大号文本，用于特殊视觉锚点
        static var hero: Font { scaled(size: 48, weight: .heavy, design: .serif) }
    }
    
    // MARK: - 布局与样式
    /// Layout 结构体，作为内部辅助类型，用于配合外层通用组件与设计系统能力。
    struct Layout {
        static let pagePadding: CGFloat = Spacing.medium
        static let sectionSpacing: CGFloat = Spacing.large
        static let contentSpacing: CGFloat = Spacing.small
        static let padding: CGFloat = Spacing.large
        /// 兼容既有页面；新代码按语义使用 `Theme.Radius.card`。
        static let cornerRadius: CGFloat = Radius.card
    }

    struct Spacing {
        static let hairline: CGFloat = 4
        static let compact: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let extraLarge: CGFloat = 24
        static let section: CGFloat = 32
    }

    /// 圆角只按组件层级取值，业务页面不再自行发明 14/18/22/26 等相近规格。
    struct Radius {
        static let control: CGFloat = 12
        static let inset: CGFloat = 16
        static let card: CGFloat = 22
        static let hero: CGFloat = 28
    }

    struct Stroke {
        static let subtleWidth: CGFloat = 0.75
        static let standardWidth: CGFloat = 1
        static let subtleOpacity: Double = 0.65
    }

    struct Shadow {
        struct Token {
            let color: Color
            let radius: CGFloat
            let y: CGFloat
        }

        static let none = Token(color: .clear, radius: 0, y: 0)
        static let raised = Token(color: .black.opacity(0.035), radius: 8, y: 3)
        static let floating = Token(color: .black.opacity(0.04), radius: 16, y: 8)
    }
    
    // MARK: - 图标
    /// Icons 结构体，作为内部辅助类型，用于配合外层通用组件与设计系统能力。
    struct Icons {
        static let today = "sun.max.fill"
        static let action = "figure.run"
        static let trend = "chart.bar.fill"
        static let health = "heart.text.square.fill"
        static let settings = "gearshape.fill"
        
        static let checkmark = "checkmark.circle.fill"
        static let chevronRight = "chevron.right"
        static let plus = "plus"
        static let close = "xmark"
    }
}

// MARK: - 动效令牌

/// 动效参数标准（统一收敛「今日页 + 健康页」动效改造所需参数，避免散落魔法数字）。
/// 每个场景都提供 reduceMotion（辅助功能-减弱动态效果）降级版本：
/// - 数字过渡：`.contentTransition(.numericText())` + `.snappy`；reduceMotion 下 `.identity` + `nil`（直出）。
/// - 卡片按压：`scale 0.975` + `opacity 0.92` + `spring(0.28/0.82)`；reduceMotion 下不缩放、不透明、无动画（直出）。
/// - 区块分组渐入：`spring(0.62/0.86)` + `delay(0.05~0.06 * index)`；reduceMotion 下 `nil`（直出）。
/// - 展开 / 收起：`spring(0.4/0.88)` + `.opacity.combined(with: .move(edge: .top))`；reduceMotion 下 `nil` + `.identity`（直出）。
/// - 环绘制：`spring(0.6/0.8)`（沿用现有，不改参数）；reduceMotion 下 `nil`（直出）。
/// - 图表 tooltip：`opacity` + `offset(y: 4→0)` + `easeOut(0.2)`；reduceMotion 下直出。
enum MotionTokens {
    // MARK: - 数字过渡
    /// 数字/数值变化的过渡方式：逐位滚动。
    static let numberTransition: ContentTransition = .numericText()
    /// 数字过渡动画（`.snappy`，或可替换为 `easeOut(duration: 0.25)`）。
    static let numberAnimation: Animation = .snappy
    /// reduceMotion 降级：直接切换数字，不做滚动过渡。
    static let numberTransitionReduced: ContentTransition = .identity
    /// reduceMotion 降级：无数字过渡动画。
    static let numberAnimationReduced: Animation? = nil

    // MARK: - 卡片按压
    /// 卡片按压缩放比例。
    static let cardPressScale: CGFloat = 0.975
    /// 卡片按压透明度。
    static let cardPressOpacity: CGFloat = 0.92
    /// 卡片按压动画。
    static let cardPressAnimation: Animation = .spring(response: 0.28, dampingFraction: 0.82)
    /// reduceMotion 降级：不缩放。
    static let cardPressScaleReduced: CGFloat = 1.0
    /// reduceMotion 降级：不透明。
    static let cardPressOpacityReduced: CGFloat = 1.0
    /// reduceMotion 降级：无按压动画。
    static let cardPressAnimationReduced: Animation? = nil

    // MARK: - 区块分组渐入
    /// 区块分组渐入动画（今日页沿用）。
    static let sectionAppearAnimation: Animation = .spring(response: 0.62, dampingFraction: 0.86)
    /// 区块渐入延迟步长（0.05~0.06 * index）。
    static let sectionAppearDelayStep: TimeInterval = 0.06
    /// 区块渐入延迟，按分组索引错开。
    static func sectionAppearDelay(index: Int) -> TimeInterval {
        sectionAppearDelayStep * TimeInterval(index)
    }
    /// reduceMotion 降级：区块直出。
    static let sectionAppearAnimationReduced: Animation? = nil

    // MARK: - 展开 / 收起
    /// 展开 / 收起动画。
    static let expandAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.88)
    /// 展开 / 收起过渡。
    static let expandTransition: AnyTransition = .opacity.combined(with: .move(edge: .top))
    /// reduceMotion 降级：无展开 / 收起动画。
    static let expandAnimationReduced: Animation? = nil
    /// reduceMotion 降级：无过渡（直出）。
    static let expandTransitionReduced: AnyTransition = .identity

    // MARK: - 环绘制
    /// 进度环绘制动画（沿用现有参数，不修改）。
    static let ringDrawAnimation: Animation = .spring(response: 0.6, dampingFraction: 0.8)
    /// reduceMotion 降级：环直出。
    static let ringDrawAnimationReduced: Animation? = nil

    // MARK: - 图表绘制
    /// 折线、面积和柱形从最终数据状态绘制出来；文字不使用此动画。
    static let chartDrawAnimation: Animation = .easeOut(duration: 0.55)
    /// 给 SwiftUI 一次布局机会后再开始绘制，避免首帧直接落在终态。
    static let chartDrawDelay: Duration = .milliseconds(24)
    /// reduceMotion 下图形直接显示最终状态。
    static let chartDrawAnimationReduced: Animation? = nil

    // MARK: - 图表 tooltip
    /// tooltip 过渡动画。
    static let tooltipAnimation: Animation = .easeOut(duration: 0.2)
    /// tooltip 入场纵向位移（y: 4→0）。
    static let tooltipOffsetY: CGFloat = 4
    /// reduceMotion 降级：tooltip 直出。
    static let tooltipAnimationReduced: Animation? = nil

    // MARK: - 状态视图入场
    /// 状态视图（空 / 错误）轻量入场的纵向位移（y: 6→0）。
    static let stateAppearOffsetY: CGFloat = 6
}

extension Font {
    private static func appScaledSize(_ size: CGFloat, level: AppFontScaleLevel = .current) -> CGFloat {
        size * level.scaleMultiplier
    }

    private static func baseSize(for textStyle: Font.TextStyle) -> CGFloat {
        switch textStyle {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .subheadline: return 15
        case .body: return 17
        case .callout: return 16
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default:
            return 17
        }
    }

    static func appSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        level: AppFontScaleLevel = .current
    ) -> Font {
        .system(size: appScaledSize(size, level: level), weight: weight, design: design)
    }

    static func appSystem(
        _ style: Font.TextStyle,
        design: Font.Design = .default,
        level: AppFontScaleLevel = .current
    ) -> Font {
        // 语义文本样式交给系统 Dynamic Type 缩放（PEN-2 P0-2），
        // 不再转回固定点数；自研 AppFontScaleLevel 仅作用于 appSystem(size:) 固定字号。
        .system(style, design: design)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Color {
    /// 根据系统外观返回浅色/深色变体（PEN-2 P0-1 深色模式基础设施）。
    /// 用法：`Color(light: "F5F5F2", dark: "1C1C1E")`，后续迁移视图时优先使用语义色或此辅助方法。
    init(light: String, dark: String) {
        self.init(light: Color(hex: light), dark: Color(hex: dark))
    }

    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
