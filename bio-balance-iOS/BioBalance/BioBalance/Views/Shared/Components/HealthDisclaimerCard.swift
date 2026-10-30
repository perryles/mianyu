/// HealthDisclaimerCard 由多模块复用调用，作为「健康免责声明」共享卡片。
/// 负责以常规/紧凑两种样式提示数据仅供健康参考，不作为医疗诊断。

import SwiftUI

/// 健康Disclaimer卡片组件 作为共享界面层里的内容展示卡片。
/// 负责给多个模块复用的布局、展示逻辑或导出能力。
struct HealthDisclaimerCard: View {
    /// Style 枚举，作为内部辅助类型，用于细分外层共享布局与通用界面能力中的状态或分支。
    enum Style {
        case regular
        case compact

        var spacing: CGFloat {
            switch self {
            case .regular: return 10
            case .compact: return 6
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .regular: return 14
            case .compact: return 12
            }
        }

        var titleSize: CGFloat {
            switch self {
            case .regular: return 14
            case .compact: return 12
            }
        }

        var messageSize: CGFloat {
            switch self {
            case .regular: return 12
            case .compact: return 11
            }
        }

        var padding: CGFloat {
            switch self {
            case .regular: return 16
            case .compact: return 14
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .regular: return 22
            case .compact: return 18
            }
        }
    }

    let message: String
    var title: String = "免责声明"
    var style: Style = .regular
    var strokeColor: Color = Theme.Colors.surfaceBorder
    var backgroundColor: Color = Theme.Colors.surface
    var showsIcon: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            HStack(spacing: 8) {
                if showsIcon {
                    Image(systemName: "exclamationmark.shield")
                        .font(.appSystem(size: style.iconSize, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Text(title)
                    .font(.appSystem(size: style.titleSize, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Text(message)
                .font(.appSystem(size: style.messageSize, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(style.padding)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }
}
