/// ProfileView 由 MainTabView 我的 Tab 调用，作为底部 Tab「我的」首页入口。
/// 负责展示个人页的热力图、入口卡与账号状态，并跳转到设置/帮助/资料详情等功能。

import SwiftUI
import UIKit
import Combine

// MARK: - 外部链接

enum ProfileExternalLinks {
    static let emailAddress = "support@boundesu.com"
    static let xiaohongshu = URL(string: "https://www.xiaohongshu.com/user/profile/68f9bcfc0000000037003712")!
    static let supportEmail = URL(string: "mailto:\(emailAddress)")!
}

// MARK: - 通知

extension Notification.Name {
    static let profileVitalityRecordsDidChange = Notification.Name("profileVitalityRecordsDidChange")
}

private enum ProfileHomePalette {
    static let mint = Theme.Colors.mintGreen
    static let blue = Theme.Colors.accentBlue
    static let sand = Color(hex: "FFB340")
    static let lavender = Color(hex: "B98BEA")
    static let graphite = Color(hex: "7D8BFF")
}

// MARK: - 个人主页

/// ProfileView 由 MainTabView 调用，作为底部 Tab「我的」首页入口。
/// 负责展示个人页的入口卡、账号状态和跳转到设置/帮助/资料详情等功能。
struct ProfileView: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("isGuest") private var isGuest: Bool = false
    @State private var vitalityReportViewModel = ReportSummaryViewModel()
    @State private var heatmapVM = ProfileHeatmapViewModel()
    @State private var showingVitalityInfo = false
    @State private var pendingCelebrations: [HolographicBadgeStatus] = []

    var body: some View {
        ZStack {
            profileHomeBackground

            AdaptivePageScrollView(topPadding: Theme.Spacing.small, bottomPadding: 88) {
                VStack(alignment: .leading, spacing: max(Theme.Spacing.large, adaptiveLayout.sectionSpacing)) {
                    ProfileHeatmapCardView(
                        viewModel: heatmapVM,
                        reportDays: vitalityReportViewModel.days,
                        isLoading: vitalityReportViewModel.isLoading,
                        showingVitalityInfo: $showingVitalityInfo
                    )

                    NavigationLink {
                        HolographicBadgeWallView()
                    } label: {
                        profileBottomRowContent(title: String(localized: "全息徽章"), icon: "seal.fill", tint: ProfileHomePalette.lavender)
                            .bbCardSurface()
                    }
                    .buttonStyle(.plain)

                    profileSettingsSection(title: "常用与账号") {
                        profileHomeShortcutCard(title: "我的信息", icon: "person.text.rectangle", tint: ProfileHomePalette.mint) {
                            ProfileDetailView()
                        }
                        profileHomeShortcutCard(title: "应用设置", icon: "gearshape.fill", tint: ProfileHomePalette.sand) {
                            SettingsView()
                        }
                        profileHomeShortcutCard(title: "iCloud 管理", icon: "icloud.fill", tint: ProfileHomePalette.blue) {
                            ICloudManagementView()
                        }
                    }

                    profileSettingsSection(title: "健康与目标") {
                        profileHomeShortcutCard(title: "目标", icon: "target", tint: ProfileHomePalette.mint) {
                            GoalsSettingsView()
                        }
                        profileHomeShortcutCard(title: "阈值", icon: "heart.text.square.fill", tint: ProfileHomePalette.blue) {
                            ThresholdSettingsView()
                        }
                    }

                    profileSettingsSection(title: "设备与扩展") {
                        profileHomeShortcutCard(title: "我的设备", icon: "watch.analog", tint: ProfileHomePalette.lavender) {
                            MyDeviceView()
                        }
                        profileHomeShortcutCard(title: "Watch 表盘组件", icon: "applewatch", tint: ProfileHomePalette.graphite) {
                            WatchPromoView()
                        }
                        profileHomeShortcutCard(title: "Watch 主题", icon: "paintpalette.fill", tint: ProfileHomePalette.lavender) {
                            WatchThemeView()
                        }
                    }

                    profileBottomGroupedSection(title: "其他") {
                        profileBottomNavigationRow(title: "我们的故事", icon: "sun.max.fill", tint: ProfileHomePalette.sand) {
                            BrandStoryView()
                        }
                        profileBottomNavigationRow(title: "商务与合作", icon: "person.2.fill", tint: ProfileHomePalette.mint) {
                            BusinessCooperationView()
                        }
                        profileBottomNavigationRow(title: "帮助与反馈", icon: "questionmark.bubble.fill", tint: ProfileHomePalette.blue) {
                            HelpFeedbackView()
                        }
                    }

                    profileLogoutButton
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            heatmapVM.refresh()
            loadVitalityHealthScores()
            refreshPendingCelebrations()
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileVitalityRecordsDidChange).receive(on: RunLoop.main)) { _ in
            heatmapVM.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .holographicBadgesDidChange).receive(on: RunLoop.main)) { _ in
            refreshPendingCelebrations()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            heatmapVM.refresh()
            loadVitalityHealthScores(force: true)
            refreshPendingCelebrations()
        }
        .fullScreenCover(isPresented: celebrationBinding) {
            HolographicBadgeCelebrationView(badges: pendingCelebrations) {
                pendingCelebrations = []
            }
            .presentationBackground(.clear)
        }
        .alert("活力指数", isPresented: $showingVitalityInfo) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("健康分采用报告同源的睡眠、压力、HRV 与活动综合评分。健康样本不足时会单独显示当天的行为记录，但不会把记录数量当作健康分。")
        }
    }

    // MARK: - 操作

    private func logout() {
        withAnimation {
            isLoggedIn = false
            isGuest = false
        }
    }

    private func loadVitalityHealthScores(force: Bool = false) {
        guard !vitalityReportViewModel.isLoading else { return }
        let hasHealthScores = vitalityReportViewModel.days.contains { $0.score != nil }
        guard heatmapVM.shouldLoadHealthScores(hasScores: hasHealthScores, force: force) else { return }
        heatmapVM.markHealthScoreLoaded()
        vitalityReportViewModel.load(days: 124)
    }

    /// 聚合徽章状态并收集待庆祝解锁；弹窗展示由 fullScreenCover 呈现。
    private func refreshPendingCelebrations() {
        let pending = HolographicBadgeStore.shared.pendingCelebrations()
        if pendingCelebrations.isEmpty, !pending.isEmpty {
            pendingCelebrations = pending
        }
    }

    private var celebrationBinding: Binding<Bool> {
        Binding(
            get: { !pendingCelebrations.isEmpty },
            set: { newValue in
                if !newValue {
                    pendingCelebrations = []
                }
            }
        )
    }

    // MARK: - 布局辅助

    private var profileHomeBackground: some View {
        Theme.Colors.pageBackground.ignoresSafeArea()
    }

    @ViewBuilder
    private func profileSettingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        profileBottomGroupedSection(title: title) {
            VStack(spacing: 0) {
                content()
            }
        }
    }

    @ViewBuilder
    private func profileHomeShortcutCard<Destination: View>(
        title: String,
        icon: String,
        tint: Color,
        isDisabled: Bool = false,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            profileBottomRowContent(title: title, icon: icon, tint: isDisabled ? Theme.Colors.textTertiary : tint)
                .opacity(isDisabled ? 0.62 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private func profileBottomGroupedSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            Text(title)
                .font(Theme.Typography.cardTitle)
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.large)

            profileBottomGroupedList {
                content()
            }
        }
    }

    private func profileBottomGroupedList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.vertical, Theme.Spacing.hairline)
        .bbCardSurface()
    }

    private func profileBottomNavigationRow<Destination: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            profileBottomRowContent(title: title, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func profileBottomRowContent(title: String, icon: String, tint: Color) -> some View {
        PromoCard(title: title, icon: icon, tint: tint)
    }

    private var profileLogoutButton: some View {
        Button(action: logout) {
            Text(isGuest ? "退出访客模式" : "退出登录")
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.accentRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.medium)
                .bbCardSurface()
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.hairline)
    }

}

// MARK: - 日期格式扩展

private extension DateFormatter {
    static let profileBirthday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .long
        return formatter
    }()
}

// MARK: - 预览

#Preview {
    NavigationStack {
        ProfileDetailView()
    }
}
