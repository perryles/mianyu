import SwiftUI

// MARK: - Badge Size

/// 状态标签尺寸预设
enum BBStatusBadgeSize {
    case small
    case regular
    case large

    var font: Font {
        switch self {
        case .small: return Theme.Typography.scaled(size: 10, weight: .bold, design: .rounded)
        case .regular: return Theme.Typography.label
        case .large: return Theme.Typography.captionBold
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return Theme.Spacing.hairline
        case .regular: return Theme.Spacing.compact
        case .large: return Theme.Spacing.small
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small, .regular: return Theme.Spacing.hairline
        case .large: return Theme.Spacing.compact
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: return 10
        case .regular: return 12
        case .large: return 13
        }
    }
}

// MARK: - Badge Variant

/// 标签变体风格
enum BBStatusBadgeVariant {
    /// 浅色背景 + 染色文字（默认）
    case tinted
    /// 实心背景 + 白色文字
    case filled
    /// 仅描边 + 染色文字
    case outlined
}

// MARK: - BB Status Badge

struct BBStatusBadge: View {
    let title: String
    let systemImage: String?
    let tint: Color
    var size: BBStatusBadgeSize = .regular
    var variant: BBStatusBadgeVariant = .tinted
    var isPulsing: Bool = false

    init(
        title: String,
        systemImage: String? = nil,
        tint: Color,
        size: BBStatusBadgeSize = .regular,
        variant: BBStatusBadgeVariant = .tinted,
        isPulsing: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.size = size
        self.variant = variant
        self.isPulsing = isPulsing
    }

    var body: some View {
        Group {
            if let systemImage {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .font(.appSystem(size: size.iconSize, weight: .bold))
                }
            } else {
                Text(title)
            }
        }
        .font(size.font)
        .foregroundColor(foregroundColor)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(backgroundView)
        .overlay {
            borderView
        }
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var foregroundColor: Color {
        switch variant {
        case .tinted: return tint
        case .filled: return Theme.Colors.onAccent
        case .outlined: return tint
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .tinted:
            Capsule().fill(tint.opacity(0.10))
        case .filled:
            Capsule().fill(tint)
        case .outlined:
            Capsule().fill(Color.clear)
        }
    }

    @ViewBuilder
    private var borderView: some View {
        switch variant {
        case .tinted:
            Capsule().stroke(tint.opacity(0.16), lineWidth: 1)
        case .filled:
            EmptyView()
        case .outlined:
            Capsule().stroke(tint.opacity(0.5), lineWidth: 1)
        }
    }
}

// MARK: - Convenience Initializers

extension BBStatusBadge {
    /// 成功状态标签
    static func success(_ title: String = "成功") -> BBStatusBadge {
        BBStatusBadge(title: title, systemImage: "checkmark", tint: Theme.Colors.mintGreen)
    }

    /// 警告状态标签
    static func warning(_ title: String = "注意") -> BBStatusBadge {
        BBStatusBadge(title: title, systemImage: "exclamationmark.triangle.fill", tint: Theme.Colors.accentOrange)
    }

    /// 错误状态标签
    static func error(_ title: String = "异常") -> BBStatusBadge {
        BBStatusBadge(title: title, systemImage: "xmark.circle.fill", tint: Theme.Colors.accentRed)
    }

    /// 信息状态标签
    static func info(_ title: String = "提示") -> BBStatusBadge {
        BBStatusBadge(title: title, systemImage: "info.circle.fill", tint: Theme.Colors.accentBlue)
    }

    /// 进行中状态标签
    static func inProgress(_ title: String = "进行中") -> BBStatusBadge {
        BBStatusBadge(title: title, systemImage: "circle.dotted", tint: Theme.Colors.mintGreen, isPulsing: true)
    }
}

// MARK: - 预览

#Preview("Status Badges") {
    VStack(spacing: 16) {
        HStack(spacing: 8) {
            BBStatusBadge.success()
            BBStatusBadge.warning()
            BBStatusBadge.error()
            BBStatusBadge.info()
        }

        HStack(spacing: 8) {
            BBStatusBadge(title: "Small", tint: .blue, size: .small)
            BBStatusBadge(title: "Regular", tint: .blue, size: .regular)
            BBStatusBadge(title: "Large", tint: .blue, size: .large)
        }

        HStack(spacing: 8) {
            BBStatusBadge(title: "Tinted", systemImage: "star.fill", tint: .orange, variant: .tinted)
            BBStatusBadge(title: "Filled", systemImage: "star.fill", tint: .orange, variant: .filled)
            BBStatusBadge(title: "Outlined", systemImage: "star.fill", tint: .orange, variant: .outlined)
        }

        BBStatusBadge.inProgress("同步中")
    }
    .padding()
}
