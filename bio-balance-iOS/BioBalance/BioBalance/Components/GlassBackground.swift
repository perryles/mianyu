/// `GlassBackground` 定义项目级玻璃卡片能力。
///
/// 这份文件的目标不是“做一套好看的背景”，而是把项目里与玻璃材质相关的能力统一收口，
/// 让页面在不同系统版本上都能保持行为稳定。
///
/// 设计原则：
/// - 不依赖新系统专属材质 API，保证当前最低系统目标稳定可编译。
/// - 保证层次、可读性和交互反馈稳定。
/// - 公共 API 只提供“页面最常见的三个粒度”：surface、chip、primary button。
/// - 调用方只关心用途和主染色，不在业务页面里重复写材质细节。
import SwiftUI

/// 兼容旧调用方式的玻璃背景 modifier。
///
/// 当前实现仍然委托给项目原有的 `bbCard()`，原因是：
/// - 旧页面大量使用 `glassCard()`，直接切换底层样式会带来视觉回归风险。
/// - 历史玻璃卡和新式染色表面职责不同。
/// - 当调用方只是想要“旧版卡片观感”时，应继续保持原行为。
struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.bbCard()
    }
}

extension View {
    /// 旧版玻璃卡片入口。
    ///
    /// 适用场景：
    /// - 历史页面已经稳定使用 `glassCard()`。
    /// - 页面希望继续沿用项目原有卡片观感。
    ///
    /// 注意：
    /// - 这个 API 不是下方染色表面能力的别名。
    /// - 如果新页面需要更细粒度的染色表面，请优先选择下方的 surface/chip/primary button API。
    func glassCard() -> some View {
        self.modifier(GlassBackground())
    }

    /// 为小型内容块提供统一的染色胶囊/标签效果。
    ///
    /// 适用场景：
    /// - 胶囊标签
    /// - 小按钮
    /// - 指标 pill
    /// - 小图标承托底
    /// - 小尺寸“当前 / 进行中 / 已开启”状态块
    ///
    /// 参数说明：
    /// - `tint`：玻璃层的染色主色。
    /// - `shape`：玻璃裁剪形状，建议传入 `Capsule`、`Circle`、`RoundedRectangle`。
    /// - `tintOpacity`：染色强度，默认适合信息型小组件。
    ///   一般建议：
    ///   - `0.08 ~ 0.12`：信息型标签、辅助提示
    ///   - `0.14 ~ 0.20`：需要更强存在感的小型操作块
    /// 使用建议：
    /// - 当页面已经有自己的 `padding / frame` 时，优先把这些布局放在调用前，再套这个 modifier。
    /// - `shape` 由调用方决定，这样可以避免在公共层里把“圆角半径”写死。
    func bbTintedChip<S: InsettableShape>(
        tint: Color,
        in shape: S,
        tintOpacity: Double = 0.10
    ) -> some View {
        modifier(BBTintedChipModifier(tint: tint, shape: shape, tintOpacity: tintOpacity))
    }

    /// 为主操作按钮提供统一的染色按钮样式。
    ///
    /// 适用场景：
    /// - 页面主 CTA
    /// - 全宽确认按钮
    /// - 强调型操作按钮
    /// - 需要比普通 chip 更强点击感的主操作
    ///
    /// 参数说明：
    /// - `tint`：按钮主染色。
    /// - `shape`：按钮外轮廓形状，通常为圆角矩形。
    /// 使用建议：
    /// - 这个 API 只负责按钮底，不负责文字颜色、字号、图标布局。
    /// - 调用方应先把按钮内容排版完整，再在最外层调用该 API。
    func bbTintedPrimaryButton<S: InsettableShape>(
        tint: Color,
        in shape: S
    ) -> some View {
        modifier(BBTintedPrimaryButtonModifier(tint: tint, shape: shape))
    }

    /// 为中大型卡片或内容面板提供统一的染色表面效果。
    ///
    /// 适用场景：
    /// - 页面主卡片
    /// - 中大型状态卡
    /// - 重点信息面板
    /// - 需要统一玻璃底的内容容器
    ///
    /// 参数说明：
    /// - `tint`：玻璃表面的主染色。
    /// - `shape`：容器外轮廓形状。
    /// - `tintStrength`：染色强度，建议 `0.08 ~ 0.18`。
    /// - `shadow`：是否启用轻阴影，默认开启。
    /// - `interactive`：仅在整个表面本身可点击时开启触摸反馈。
    func bbTintedSurface<S: InsettableShape>(
        tint: Color,
        in shape: S,
        tintStrength: CGFloat = 0.12,
        shadow: Bool = true
    ) -> some View {
        background(
            BBTintedSurface(
                tint: tint,
                shape: shape,
                tintStrength: tintStrength,
                shadow: shadow
            )
        )
    }

    /// iOS 26 Liquid Glass 卡片表面：在系统玻璃效果上叠加轻染色与描边。
    ///
    /// 适用场景：
    /// - 需要强调层次的新版卡片（健身分析、训练月历等）
    /// - 悬浮在页面背景之上的指标面板
    ///
    /// 版本策略：iOS 26+ 走系统 `glassEffect(.regular(tint:))`；更早系统自动降级为
    /// `bbTintedSurface` 同款染色白卡，保证部署目标（iOS 18.6）上观感一致、可编译。
    /// 描边统一在两个分支外层补齐，避免分支间边框差异。
    @ViewBuilder
    func bbLiquidGlassSurface<S: InsettableShape>(
        tint: Color,
        in shape: S,
        tintStrength: CGFloat = 0.10,
        shadow: Bool = true,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(
                BBLiquidGlassSurfaceModifier(
                    tint: tint,
                    shape: shape,
                    tintStrength: tintStrength,
                    shadow: shadow,
                    interactive: interactive
                )
            )
        } else {
            self
                .bbTintedSurface(tint: tint, in: shape, tintStrength: tintStrength, shadow: shadow)
                .overlay {
                    shape
                        .strokeBorder(Theme.Colors.surfaceBorder, lineWidth: 1)
                }
        }
    }
}

/// 通用染色承载面。
///
/// 适用场景：
/// - 页面主卡片
/// - 分组 section 容器
/// - 中大型信息面板
/// - 卡片列表中的统一背景面
///
/// 设计目标：
/// - 提供一致的视觉样式，避免页面风格断层。
/// - 不把排版、padding、字体层级耦合进公共组件，保持“只管表面、不管内容”。
///
/// 参数说明：
/// - `tint`：玻璃整体染色。
/// - `shape`：卡片形状。
/// - `tintStrength`：染色强度，建议 0.08~0.18。
/// - `shadow`：是否启用轻阴影，默认开启。
///
/// 使用建议：
/// - 如果页面是整块 section 容器，通常 `tintStrength` 取 `0.10 ~ 0.14` 即可。
/// - 如果页面想强调某个状态色（例如警告、进行中、成功），可以提高到 `0.16 ~ 0.20`。
/// - `shadow` 更适合悬浮卡片；贴底、贴边容器可以关闭，避免层次过重。
struct BBTintedSurface<S: InsettableShape>: View {
    let tint: Color
    let shape: S
    let tintStrength: CGFloat
    var shadow: Bool = true

    var body: some View {
        let strength = min(max(Double(tintStrength), 0), 1)

        shape
            .fill(Color.white)
            .overlay {
                shape
                    .fill(tint.opacity(strength))
            }
            .overlay(
                shape
                    .strokeBorder(Theme.Colors.surfaceBorder, lineWidth: Theme.Stroke.standardWidth)
            )
            .shadow(
                color: shadow ? Theme.Shadow.raised.color : .clear,
                radius: shadow ? Theme.Shadow.raised.radius : 0,
                x: 0,
                y: shadow ? Theme.Shadow.raised.y : 0
            )
    }
}

/// `bbTintedChip(...)` 的底层实现。
/// 之所以独立成 `ViewModifier`，是为了让外部调用点保持简洁，同时统一小尺寸组件样式。
private struct BBTintedChipModifier<S: InsettableShape>: ViewModifier {
    let tint: Color
    let shape: S
    let tintOpacity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .background(tint.opacity(tintOpacity), in: shape)
            .overlay(
                shape
                    .strokeBorder(Theme.Colors.surfaceBorder.opacity(0.8), lineWidth: 0.8)
            )
    }
}

/// `bbTintedPrimaryButton(...)` 的底层实现。
/// 和普通 chip 分开，是因为主按钮需要更高的染色强度与更强的操作感。
private struct BBTintedPrimaryButtonModifier<S: InsettableShape>: ViewModifier {
    let tint: Color
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .background(tint, in: shape)
    }
}

/// `bbLiquidGlassSurface(...)` 的 iOS 26+ 实现。
/// 系统 Liquid Glass 承担折射材质；轻染色叠加在玻璃上强调业务主色，
/// 阴影保持与 `BBTintedSurface` 相同的量级以统一层次。
private struct BBLiquidGlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let tint: Color
    let shape: S
    let tintStrength: CGFloat
    let shadow: Bool
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(
                        Glass.regular.tint(tint.opacity(min(max(Double(tintStrength), 0), 1))).interactive(),
                        in: shape
                    )
                    .shadow(
                        color: shadow ? Theme.Shadow.floating.color : .clear,
                        radius: shadow ? Theme.Shadow.floating.radius : 0,
                        x: 0,
                        y: shadow ? Theme.Shadow.floating.y : 0
                    )
            } else {
                content
                    .glassEffect(
                        Glass.regular.tint(tint.opacity(min(max(Double(tintStrength), 0), 1))),
                        in: shape
                    )
                    .shadow(
                        color: shadow ? Theme.Shadow.floating.color : .clear,
                        radius: shadow ? Theme.Shadow.floating.radius : 0,
                        x: 0,
                        y: shadow ? Theme.Shadow.floating.y : 0
                    )
            }
        } else {
            // struct 本身不标 @available 时兜底走染色表面（当前调用方已做分支，此分支仅为编译完整）。
            content
                .bbTintedSurface(tint: tint, in: shape, tintStrength: tintStrength, shadow: shadow)
        }
    }
}
