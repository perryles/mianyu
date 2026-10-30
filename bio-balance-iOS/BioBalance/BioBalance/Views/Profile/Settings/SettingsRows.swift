/// SettingsRows 提供设置页内复用的基础行组件。
import SwiftUI

/// SettingsRow 由设置页及其子页面调用，用来展示普通跳转行。
struct SettingsRow: View {
    let icon: String
    var color: Color = Theme.Colors.mintGreen
    let title: String
    var value: String? = nil
    var showArrow: Bool = true
    
    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: icon)
                .font(.appSystem(size: 18, weight: .medium))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15))
                .clipShape(Circle())
            
            Text(title)
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textPrimary)
            
            Spacer()
            
            if let value = value {
                Text(value)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            
            if showArrow {
                Image(systemName: Theme.Icons.chevronRight)
                    .font(.appSystem(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.compact)
        .padding(.horizontal, Theme.Spacing.compact)
        .contentShape(Rectangle())
    }
}

/// SettingsToggleRow 由设置页及其子页面调用，用来展示带开关的设置行。
struct SettingsToggleRow: View {
    let icon: String
    var color: Color = Theme.Colors.mintGreen
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: icon)
                .font(.appSystem(size: 18, weight: .medium))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15))
                .clipShape(Circle())
            
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .tint(Theme.Colors.mintGreen)
        }
        .padding(.vertical, Theme.Spacing.compact)
        .padding(.horizontal, Theme.Spacing.compact)
    }
}
