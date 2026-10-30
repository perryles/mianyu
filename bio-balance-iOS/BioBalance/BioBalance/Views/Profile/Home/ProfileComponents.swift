/// ProfileComponents 作为 Profile 模块的共享扩展，负责定义辅助常量与组件。
/// 负责提供外部链接、通知名常量与 AboutView 等个人页辅助视图。

import SwiftUI

/// 「我的 / 其他」下叙事型页面共用的顶部结构。
/// 保持三页的信息层级一致，同时允许每页用自己的语义色和图标表达身份。

/// About视图 由上级页面或路由调用，作为个人资料模块里的界面或内容组件。
/// 负责个人资料与账户入口。
struct AboutView: View {
    private var appVersionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var buildText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        ProfileSettingsPage(title: "关于", subtitle: "参考应用设置样式，收敛成更简洁的信息页。") {
            ProfileSection(title: "应用信息") {
                HStack(spacing: 12) {
                    aboutInfoPill(title: "版本", value: appVersionText, tint: Theme.Colors.mintGreen)
                    aboutInfoPill(title: "构建", value: buildText, tint: Theme.Colors.accentBlue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            ProfileSection(title: "简要说明") {
                ProfileInfoRow(title: "产品定位", value: "更清楚地理解身体状态")
                Divider().padding(.leading, 74)
                ProfileInfoRow(title: "支持平台", value: "iPhone · Apple Watch")
                Divider().padding(.leading, 74)
                ProfileInfoRow(title: "数据来源", value: "HealthKit 与本机同步")
            }

            ProfileSection(title: "帮助与法律") {
                ProfileNavigationRow(title: "帮助与反馈", subtitle: "查看常见问题和支持入口", icon: "questionmark.bubble.fill") {
                    HelpFeedbackView()
                }
                Divider().padding(.leading, 74)
                ProfileNavigationRow(title: "隐私政策", subtitle: "了解我们如何保护你的数据", icon: "hand.raised.fill") {
                    PrivacyPolicyView()
                }
                Divider().padding(.leading, 74)
                ProfileNavigationRow(title: "服务条款", subtitle: "查看产品使用说明", icon: "doc.text.fill") {
                    TermsOfServiceView()
                }
            }
        }
    }

    private func aboutInfoPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}


struct ProfileWellnessHeroItem: Identifiable {
    let value: String
    let label: String

    var id: String { label }
}

/// 目标与阈值共用的沉浸式设置页，延续“我的设备”和“我们的故事”的视觉语言。
struct ProfileWellnessSettingsPage<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @State private var hasAppeared = false

    let title: String
    let eyebrow: String
    let headline: String
    let summary: String
    let symbol: String
    let tint: Color
    let background: Color
    let items: [ProfileWellnessHeroItem]
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            HealthDetailPageBackground()

            VStack(spacing: 0) {
                background.frame(height: 360)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)

            AdaptivePageScrollView(
                style: .reading,
                topPadding: 0,
                bottomPadding: 56,
                showsIndicators: false
            ) {
                VStack(spacing: 18) {
                    hero
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: reduceMotion || hasAppeared ? 0 : 14)

                    VStack(spacing: 16) { content }
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: reduceMotion || hasAppeared ? 0 : 20)
                }
            }
        }
        .appSecondaryNavigation(title: LocalizedStringKey(title))
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.88)) {
                    hasAppeared = true
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            Text(eyebrow)
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1.2)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: 132, height: 132)
                    .shadow(color: tint.opacity(0.14), radius: 22, y: 12)

                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 2)
                    .frame(width: 106, height: 106)

                Image(systemName: symbol)
                    .font(.appSystem(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeat(1), value: hasAppeared)
            }

            VStack(spacing: 8) {
                Text(headline)
                    .font(.appSystem(size: 27, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text(summary)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(items) { item in
                    VStack(spacing: 4) {
                        Text(item.value)
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "1D2635"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(item.label)
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "788391"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 26)
        .background(
            background,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .padding(.horizontal, -adaptiveLayout.outerPadding)
    }
}

/// 个人设置Page结构体 作为个人资料模块里的辅助类型。
/// 负责个人资料与账户入口。
struct ProfileSettingsPage<Content: View>: View {
    @AppStorage("app_font_scale_level") private var appFontScaleLevelRaw: Int = 2
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            ProfileSoftBackground()

            AdaptivePageScrollView(style: .reading, topPadding: Theme.Spacing.small, bottomPadding: appFontScaleLevelRaw == 1 ? 88 : 96) {
                VStack(spacing: Theme.Spacing.medium) { content }
            }
        }
        .appSecondaryNavigation(title: LocalizedStringKey(title))
    }
}

struct ProfileSoftBackground: View {
    var body: some View {
        Theme.Colors.pageBackground
        .ignoresSafeArea()
    }
}


/// 个人区块组件 作为个人资料模块里的布局区块组件。
/// 负责个人资料与账户入口。
struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            Text(title)
                .font(Theme.Typography.cardTitle)
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, Theme.Spacing.hairline)
            .bbCardSurface()
        }
    }
}

struct ProfileNavigationRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            ProfileRowShell(title: title, subtitle: subtitle, icon: icon) {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.scaled(size: 13, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}



struct ProfileHintCard: View {
    /// Item 结构体，作为内部辅助类型，用于配合外层个人资料与账户入口。
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    let title: String
    let rows: [Item]

    var body: some View {
        ProfileSection(title: title) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.label)
                            .font(Theme.Typography.scaled(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: 72, alignment: .leading)

                        Text(row.value)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)

                    if index != rows.count - 1 {
                        Divider().padding(.leading, 90)
                    }
                }
            }
        }
    }
}

struct ProfileStatusRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let value: String
    let tint: Color

    var body: some View {
        ProfileRowShell(title: title, subtitle: subtitle, icon: icon, tint: tint) {
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundColor(tint == Theme.Colors.textTertiary ? Theme.Colors.textSecondary : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(tint.opacity(0.10), in: Capsule())
        }
    }
}

/// 个人Toggle行组件 作为个人资料模块里的列表行组件。
/// 负责个人资料与账户入口。


struct ProfileWheelPickerOption<Value: Hashable> {
    let value: Value
    let label: String
}

struct ProfileWheelSelectorRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let valueText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))

                    Image(systemName: icon)
                        .font(.appSystem(size: 18, weight: .bold))
                        .foregroundColor(tint)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(subtitle)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(valueText)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ProfileWheelPickerSheet<Value: Hashable>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let valueSummary: String
    let tint: Color
    let options: [ProfileWheelPickerOption<Value>]
    @Binding var selection: Value

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Capsule()
                    .fill(Color(hex: "D8E2EF"))
                    .frame(width: 42, height: 5)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.appSystem(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitle)
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Text(valueSummary)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(tint.opacity(0.12), in: Capsule())

                VStack(spacing: 10) {
                    Text("上下滑动滚轮选择数值")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)

                    Picker(title, selection: $selection) {
                        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                            Text(option.label)
                                .tag(option.value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .frame(height: 216)
                    .clipped()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.96), tint.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(tint.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 20)

                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ProfileSoftBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
    }
}

/// 个人Slider行组件 作为个人资料模块里的列表行组件。
/// 负责个人资料与账户入口。

struct ProfileActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = Theme.Colors.mintGreen
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileRowShell(title: title, subtitle: subtitle, icon: icon, tint: tint) {
                if isLoading {
                    ProgressView()
                        .tint(tint)
                } else {
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.scaled(size: 13, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// 个人信息行组件 作为个人资料模块里的列表行组件。
/// 负责个人资料与账户入口。
struct ProfileInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
    }
}

struct ProfileRowShell<Trailing: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = Theme.Colors.mintGreen
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(Theme.Typography.scaled(size: 17, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: Theme.Spacing.small)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
    }
}
