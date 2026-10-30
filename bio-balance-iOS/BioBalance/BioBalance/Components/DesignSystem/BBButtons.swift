/// BB Buttons 定义可复用界面组件，负责沉淀通用样式、交互结构或设计系统能力。
import SwiftUI

// MARK: - Button Styles

/// BBPrimary结构体 作为设计系统里的辅助类型。
/// 负责通用组件与设计系统能力。
struct BBPrimaryButtonStyle: ButtonStyle {
    var isFullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.bodyBold)
            .foregroundColor(Theme.Colors.onAccent)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.compact)
            .frame(minHeight: 44)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(Theme.Colors.primaryAction.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

/// BBSecondary结构体 作为设计系统里的辅助类型。
/// 负责通用组件与设计系统能力。
struct BBSecondaryButtonStyle: ButtonStyle {
    var isFullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.bodyBold)
            .foregroundColor(Theme.Colors.textPrimary.opacity(configuration.isPressed ? 0.75 : 1))
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.compact)
            .frame(minHeight: 44)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.Colors.textPrimary.opacity(configuration.isPressed ? 0.75 : 1), lineWidth: Theme.Stroke.standardWidth)
            )
    }
}

/// 破坏性按钮样式（如删除、退出等危险操作）
struct BBDestructiveButtonStyle: ButtonStyle {
    var isFullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.bodyBold)
            .foregroundColor(Theme.Colors.onAccent)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.compact)
            .frame(minHeight: 44)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(Theme.Colors.accentRed.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

/// 染色按钮样式（使用自定义主题色）
struct BBTintedButtonStyle: ButtonStyle {
    let tint: Color
    var isFullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.bodyBold)
            .foregroundColor(tint)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.compact)
            .frame(minHeight: 44)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

/// 共享卡片按压反馈样式：轻微缩放 + 透明度变化，让入口卡片更有“可按”质感。
/// 行为与健康页原有 `HealthHubPressableStyle` 完全一致：
/// `scaleEffect(0.975)` + `opacity(0.92)` + `.spring(response: 0.28, dampingFraction: 0.82)`。
/// reduceMotion 下降级为直出（不缩放、不透明、无动画）。
struct BBCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                reduceMotion
                    ? MotionTokens.cardPressScaleReduced
                    : (configuration.isPressed ? MotionTokens.cardPressScale : 1.0)
            )
            .opacity(
                reduceMotion
                    ? MotionTokens.cardPressOpacityReduced
                    : (configuration.isPressed ? MotionTokens.cardPressOpacity : 1.0)
            )
            .animation(
                reduceMotion ? MotionTokens.cardPressAnimationReduced : MotionTokens.cardPressAnimation,
                value: configuration.isPressed
            )
    }
}

extension View {
    /// 便捷入口：为卡片 / 入口按钮套用共享按压反馈样式。
    /// 声明在 View 上，使 Button 与 NavigationLink（内部按 Button 渲染）都能使用；
    /// buttonStyle(_:) 本身是 View 方法，NavigationLink 上同样生效。
    func bbCardButtonStyle() -> some View {
        buttonStyle(BBCardButtonStyle())
    }
}

// MARK: - Button Components

/// BBPrimary按钮组件 作为设计系统里的交互按钮组件。
/// 负责通用组件与设计系统能力。
struct BBPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isFullWidth: Bool = false
    var isLoading: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        Button {
            guard !isLoading, !isDisabled else { return }
            action()
        } label: {
            HStack(spacing: Theme.Spacing.compact) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.onAccent))
                        .scaleEffect(0.8)
                }
                Text(title)
            }
        }
        .buttonStyle(BBPrimaryButtonStyle(isFullWidth: isFullWidth))
        .opacity(isDisabled ? 0.45 : 1.0)
        .allowsHitTesting(!isDisabled && !isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isDisabled ? .isStaticText : .isButton)
    }
}

/// BBSecondary按钮组件 作为设计系统里的交互按钮组件。
/// 负责通用组件与设计系统能力。
struct BBSecondaryButton: View {
    let title: String
    let action: () -> Void
    var isFullWidth: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        Button {
            guard !isDisabled else { return }
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(BBSecondaryButtonStyle(isFullWidth: isFullWidth))
        .opacity(isDisabled ? 0.45 : 1.0)
        .allowsHitTesting(!isDisabled)
        .accessibilityLabel(title)
    }
}

/// 带图标的按钮组件
struct BBIconButton: View {
    let systemImage: String
    let title: String?
    let action: () -> Void
    var tint: Color = Theme.Colors.textPrimary
    var size: CGFloat = 44

    init(systemImage: String, title: String? = nil, tint: Color = Theme.Colors.textPrimary, size: CGFloat = 44, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.tint = tint
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.compact) {
                Image(systemName: systemImage)
                    .font(.appSystem(size: size * 0.38, weight: .semibold))

                if let title {
                    Text(title)
                        .font(Theme.Typography.supporting)
                }
            }
            .foregroundColor(tint)
            .frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title ?? systemImage)
    }
}

/// 破坏性操作按钮
struct BBDestructiveButton: View {
    let title: String
    let action: () -> Void
    var isFullWidth: Bool = false
    var isLoading: Bool = false

    var body: some View {
        Button {
            guard !isLoading else { return }
            action()
        } label: {
            HStack(spacing: Theme.Spacing.compact) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.onAccent))
                        .scaleEffect(0.8)
                }
                Text(title)
            }
        }
        .buttonStyle(BBDestructiveButtonStyle(isFullWidth: isFullWidth))
        .accessibilityLabel(title)
    }
}

/// 染色按钮组件（适合带强调色的次级操作）
struct BBTintedButton: View {
    let title: String
    let tint: Color
    let action: () -> Void
    var systemImage: String? = nil
    var isFullWidth: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.compact) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
        }
        .buttonStyle(BBTintedButtonStyle(tint: tint, isFullWidth: isFullWidth))
        .accessibilityLabel(title)
    }
}

// MARK: - 预览

#Preview("Button Gallery") {
    VStack(spacing: 16) {
        BBPrimaryButton(title: "主操作按钮", action: {}, isFullWidth: true)
        BBPrimaryButton(title: "加载中", action: {}, isLoading: true)
        BBPrimaryButton(title: "已禁用", action: {}, isDisabled: true)
        BBSecondaryButton(title: "次要操作", action: {}, isFullWidth: true)
        BBDestructiveButton(title: "删除数据", action: {}, isFullWidth: true)
        BBTintedButton(title: "开始锻炼", tint: Theme.Colors.mintGreen, action: {}, systemImage: "figure.run", isFullWidth: true)
        HStack {
            BBIconButton(systemImage: "heart.fill", tint: .red, action: {})
            BBIconButton(systemImage: "square.and.arrow.up", title: "分享", action: {})
        }
    }
    .padding()
}
