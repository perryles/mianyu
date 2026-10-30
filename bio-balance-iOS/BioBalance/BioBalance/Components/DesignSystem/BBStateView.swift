/// BB State View 定义可复用界面组件，负责沉淀通用样式、交互结构或设计系统能力。
import SwiftUI

/// BB状态视图 由上级页面或路由调用，作为设计系统里的界面或内容组件。
/// 负责通用组件与设计系统能力。
struct BBStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let primaryActionTitle: String?
    let primaryAction: (() -> Void)?
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?
    
    init(
        systemImage: String,
        title: String,
        message: String,
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: systemImage)
                .font(.appSystem(size: 34, weight: .semibold))
                .foregroundColor(Color.black)
                .padding(.bottom, 6)
            
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(Theme.Colors.textPrimary)
            
            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            
            if let primaryActionTitle, let primaryAction {
                VStack(spacing: Theme.Spacing.compact) {
                    BBPrimaryButton(title: primaryActionTitle) {
                        primaryAction()
                    }
                    
                    if let secondaryActionTitle, let secondaryAction {
                        BBSecondaryButton(title: secondaryActionTitle) {
                            secondaryAction()
                        }
                    }
                }
                .padding(.top, Theme.Spacing.compact)
            }
        }
        .padding(Theme.Spacing.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}

/// BB空状态视图 由上级页面或路由调用，作为设计系统里的界面或内容组件。
/// 负责通用组件与设计系统能力。
struct BBEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        systemImage: String = "tray",
        title: String = String(localized: "暂无数据"),
        message: String = String(localized: "当前还没有可展示的记录。"),
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            BBInlineEmptyState(systemImage: systemImage, title: title, message: message)
            if let actionTitle, let action {
                BBPrimaryButton(title: actionTitle, action: action)
            }
        }
        .padding(Theme.Spacing.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// BB错误状态视图 由上级页面或路由调用，作为设计系统里的界面或内容组件。
/// 负责通用组件与设计系统能力。
struct BBErrorStateView: View {
    let title: String
    let message: String
    let retryTitle: String
    let retry: () -> Void
    
    init(
        title: String = "加载失败",
        message: String = "发生了未知错误，请稍后再试。",
        retryTitle: String = "重试",
        retry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }
    
    var body: some View {
        BBStateView(
            systemImage: "exclamationmark.octagon.fill",
            title: title,
            message: message,
            primaryActionTitle: retryTitle,
            primaryAction: retry
        )
    }
}

/// Inline empty content shared by records, reports and health detail cards.
struct BBInlineEmptyState: View {
    let systemImage: String
    let title: String
    var message: String = ""
    var accent: Color = Theme.Colors.mintGreen

    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.compact) {
                Circle().fill(accent.opacity(0.16)).frame(width: 5, height: 5)
                Image(systemName: systemImage)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(accent)
                    .frame(width: 54, height: 54)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.inset))
                Circle().fill(accent.opacity(0.16)).frame(width: 5, height: 5)
            }
            .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.compact) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !message.isEmpty {
                    Text(message)
                        .font(Theme.Typography.supporting)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineSpacing(3)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.extraLarge)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [accent.opacity(0.07), Color.pink.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
    }
}
