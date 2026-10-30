/// BB Card 定义可复用界面组件，负责沉淀通用样式、交互结构或设计系统能力。
import SwiftUI

// MARK: - Card Style

/// BB结构体 作为设计系统里的辅助类型。
/// 负责通用组件与设计系统能力。
struct BBCardStyle {
    var contentPadding: CGFloat
    var cornerRadius: CGFloat
    var shadow: Theme.Shadow.Token

    static let standard = BBCardStyle(
        contentPadding: Theme.Spacing.medium,
        cornerRadius: Theme.Radius.card,
        shadow: Theme.Shadow.none
    )

    static let inset = BBCardStyle(
        contentPadding: Theme.Spacing.small,
        cornerRadius: Theme.Radius.inset,
        shadow: Theme.Shadow.none
    )

    static let hero = BBCardStyle(
        contentPadding: Theme.Spacing.large,
        cornerRadius: Theme.Radius.hero,
        shadow: Theme.Shadow.floating
    )

    static let elevated = BBCardStyle(
        contentPadding: Theme.Spacing.medium,
        cornerRadius: Theme.Radius.card,
        shadow: Theme.Shadow.raised
    )

    static let compact = BBCardStyle(
        contentPadding: Theme.Spacing.small,
        cornerRadius: Theme.Radius.control,
        shadow: Theme.Shadow.none
    )
}

// MARK: - BB Card

/// BB卡片组件 作为设计系统里的内容展示卡片。
/// 负责通用组件与设计系统能力。
struct BBCard<Content: View>: View {
    private let style: BBCardStyle
    private let tint: Color?
    private let content: Content

    init(style: BBCardStyle = .standard, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.style = style
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(style.contentPadding)
            .bbCardSurface(style: style, tint: tint)
    }


}

// MARK: - BB Card with Header

/// 带标题的卡片组件
struct BBTitledCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color? = nil
    var style: BBCardStyle = .standard
    @ViewBuilder let content: () -> Content

    var body: some View {
        BBCard(style: style, tint: tint) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                HStack(spacing: Theme.Spacing.compact) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.appSystem(size: 14, weight: .bold))
                            .foregroundColor(tint ?? Theme.Colors.mintGreen)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.Typography.cardTitle)
                            .foregroundColor(Theme.Colors.textPrimary)

                        if let subtitle {
                            Text(subtitle)
                                .font(Theme.Typography.supporting)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                content()
            }
        }
    }
}

// MARK: - Page Header

/// 主 Tab 与一级页面的统一标题头。文字本身不添加动效。
struct BBPageHeader<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    copy
                    trailing
                }
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.small) {
                    copy
                    Spacer(minLength: Theme.Spacing.compact)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
            Text(title)
                .font(Theme.Typography.pageTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(Theme.Typography.supporting)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
    }
}

extension BBPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Card Modifier

private struct BBCardModifier: ViewModifier {
    let style: BBCardStyle
    let tint: Color?

    func body(content: Content) -> some View {
        BBCard(style: style, tint: tint) {
            content
        }
    }
}

private struct BBCardSurfaceModifier: ViewModifier {
    let style: BBCardStyle
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        let isShadowless = style.shadow.radius == 0
        let shadowColor = Color(hex: "283857").opacity(isShadowless ? 0 : 0.07)

        if #available(iOS 26.0, *) {
            content
                .bbLiquidGlassSurface(
                    tint: tint ?? .white,
                    in: shape,
                    tintStrength: tint == nil ? 0.02 : 0.06,
                    shadow: false
                )
                .shadow(
                    color: shadowColor,
                    radius: isShadowless ? 10 : 14,
                    x: 0,
                    y: isShadowless ? 5 : 6
                )
        } else {
            content
                .background(Color.white.opacity(0.86), in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.88), lineWidth: 1)
                }
                .shadow(
                    color: shadowColor,
                    radius: isShadowless ? 10 : 14,
                    x: 0,
                    y: isShadowless ? 5 : 6
                )
        }
    }
}

extension View {
    func bbCard(style: BBCardStyle = .standard, tint: Color? = nil) -> some View {
        modifier(BBCardModifier(style: style, tint: tint))
    }


    /// 只应用统一承载面，不额外添加内边距。适合列表分组、按钮和已有布局的容器。
    func bbCardSurface(style: BBCardStyle = .standard, tint: Color? = nil) -> some View {
        modifier(BBCardSurfaceModifier(style: style, tint: tint))
    }
}

// MARK: - 预览

#Preview("Card Variants") {
    ScrollView {
        VStack(spacing: 16) {
            BBCard {
                Text("Standard Card")
            }

            BBCard(style: .elevated, tint: Theme.Colors.mintGreen) {
                Text("Elevated Tinted Card")
            }

            BBCard(style: .hero) {
                Text("Hero Card")
            }

            BBTitledCard(title: "活动概览", subtitle: "今日数据", systemImage: "figure.run", tint: Theme.Colors.mintGreen) {
                Text("卡片内容区域")
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding()
    }
}
