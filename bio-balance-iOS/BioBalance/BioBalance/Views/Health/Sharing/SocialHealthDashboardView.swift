/// 「好友」首页：设计稿「好友 · 实时状态」的动态卡片流。
/// 展示好友健康摘要动态（睡眠/步速）、邀请进度与共享工具入口；
/// 数据边界遵循 ICLOUD_DATA_ARCHITECTURE：只呈现对方主动共享的最近 7 天摘要。

import Charts
import SwiftUI

struct SocialDashboardPresentation: Equatable {
    let friendCount: Int
    let pendingCount: Int
    let mutualCount: Int

    var totalConnectionCount: Int { friendCount + pendingCount }

    var primarySummary: String {
        if friendCount == 0 { return String(localized: "邀请一位好友，开始安全共享") }
        if mutualCount > 0 { return String(localized: "\(friendCount) 位好友保持连接") }
        return String(localized: "\(friendCount) 位好友与你共享")
    }

    var pendingSummary: String? {
        pendingCount == 0 ? nil : String(localized: "\(pendingCount) 个邀请待回应")
    }
}

/// 首页顶部「好友动态 / 我的好友」分段。
private enum FriendFeedTab: String, CaseIterable, Identifiable {
    case activity
    case myFriends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return String(localized: "好友动态")
        case .myFriends: return String(localized: "我的好友")
        }
    }
}

struct SocialHealthDashboardView: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Bindable var viewModel: SocialViewModel

    let onInvite: () -> Void
    let onRefresh: () -> Void
    let onManageTodos: () -> Void
    let onManageCountdowns: () -> Void
    let onStopSharing: () -> Void
    let onSelectFriend: (FriendHealthProfile) -> Void
    let onRemoveOutgoingShare: (OutgoingShareProfile) -> Void

    @State private var selectedTab: FriendFeedTab = .activity
    @State private var showingSpecialFocus = false
    @State private var showingAddFriend = false
    @State private var inviteAfterAddFriendDismissal = false
    @State private var showingShareSettings = false
    @State private var showingShareReportCard = false
    @State private var activityDetailFriend: FriendHealthProfile?

    private let ink = Color(hex: "12141A")
    private let secondaryInk = Color(hex: "6B7585")
    private var canvas: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "ECF5FF"), Color(hex: "F8FBFF")],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [sky.opacity(0.14), .clear],
                center: UnitPoint(x: 0.92, y: 0.06),
                startRadius: 0,
                endRadius: 340
            )
        }
    }
    private let trackInk = Color(hex: "F1F4F8")
    private let accent = Theme.Colors.mintGreen
    private let accentSoft = Color(hex: "DDF1EC")
    private let sky = Theme.Colors.accentBlue
    private let skySoft = Color(hex: "E7F0F9")
    private let amber = Theme.Colors.accentOrange
    private let amberSoft = Color(hex: "F8EBDD")
    private let sleepTint = Color(hex: "6C7CE0")
    private let sleepBarTint = Color(hex: "D6CCFF")
    private let walkTint = Color(hex: "3FBF9F")
    private let liveTint = Color(hex: "29AD73")
    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()
            AdaptivePageScrollView(style: .page, topPadding: 4, bottomPadding: 96, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    feedHeader
                    feedTabs
                    if let message = statusMessage { statusBanner(message) }
                    switch selectedTab {
                    case .activity: activityFeed
                    case .myFriends: myFriendsList
                    }
                    if selectedTab == .myFriends {
                        sharedToolsSection
                    }
                    privacyFooter
                }
            }
        }
        .toolbarBackground(Color(hex: "F1F7FC"), for: .navigationBar)
        .navigationDestination(item: $activityDetailFriend) { friend in
            SocialActivityDetailView(friend: friend) { profile in
                onSelectFriend(profile)
            }
            .toolbar(.hidden, for: .tabBar)
        }
        .sheet(isPresented: $showingSpecialFocus) {
            NavigationStack {
                SocialSpecialFocusView(friends: viewModel.sharingState.friends)
            }
            .adaptiveSheetChrome(style: .page, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingShareSettings) {
            NavigationStack {
                SocialShareSettingsView(
                    friendName: nil,
                    onSave: { _ in onRefresh() },
                    onStopAllSharing: onStopSharing
                )
            }
            .adaptiveSheetChrome(style: .page, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingAddFriend, onDismiss: {
            guard inviteAfterAddFriendDismissal else { return }
            inviteAfterAddFriendDismissal = false
            onInvite()
        }) {
            NavigationStack {
                SocialAddFriendView(onInvite: {
                    inviteAfterAddFriendDismissal = true
                    showingAddFriend = false
                }, friends: viewModel.sharingState.friends,
                   outgoingShares: viewModel.sharingState.outgoingShares,
                   myProfile: viewModel.sharingState.myPublicProfile,
                   onSearch: viewModel.lookupFriend)
            }
            .adaptiveSheetChrome(style: .page, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingShareReportCard) {
            NavigationStack {
                SocialShareReportCardView(myStatus: viewModel.sharingState.myStatus)
            }
            .adaptiveSheetChrome(style: .page, dragIndicator: .visible)
        }
    }

    // MARK: - 设计稿头部：大标题 + 副标题 + 添加按钮

    private var feedHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("好友")
                    .font(.appSystem(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                Text("实时看见彼此的状态")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
            }
            Spacer(minLength: 8)
            Menu {
                Button(action: onInvite) {
                    Label("邀请好友", systemImage: "person.badge.plus")
                }
                Button {
                    showingAddFriend = true
                } label: {
                    Label("添加好友", systemImage: "person.crop.circle.badge.plus")
                }
                Button {
                    showingSpecialFocus = true
                } label: {
                    Label("特别关注", systemImage: "star")
                }
                Button(action: onRefresh) {
                    Label("刷新好友状态", systemImage: "arrow.clockwise")
                }
                Button {
                    showingShareSettings = true
                } label: {
                    Label("分享设置", systemImage: "lock.shield")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.appSystem(size: 20, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.Colors.surface, in: Circle())
                    .overlay {
                        Circle().stroke(Theme.Colors.surfaceBorder.opacity(0.5), lineWidth: 1)
                    }
            }
            .accessibilityLabel("添加好友")
        }
        .padding(.horizontal, adaptiveLayout.usesExpandedLayout ? 12 : 4)
    }

    // MARK: - 顶部「好友动态 / 我的好友」分段

    private var feedTabs: some View {
        HStack(spacing: 0) {
            ForEach(FriendFeedTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.appSystem(size: 13, weight: selectedTab == tab ? .bold : .medium, design: .rounded))
                        .foregroundStyle(selectedTab == tab ? ink : secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: ink.opacity(0.06), radius: 4, y: 1)
                            }
                        }
                        .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(trackInk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, adaptiveLayout.usesExpandedLayout ? 12 : 4)
    }

    // MARK: - 好友动态流

    private var activityFeed: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !viewModel.sharingState.friends.isEmpty || viewModel.sharingState.outgoingShares.isEmpty == false {
                sectionHeading(
                    "今天",
                    detail: viewModel.sharingState.friends.isEmpty ? "等待好友更新" : "\(viewModel.sharingState.friends.count) 位好友有新状态"
                )
            }
            if let pendingInvite = viewModel.sharingState.pendingInvite {
                pendingInviteCard(pendingInvite)
            }
            ForEach(viewModel.sharingState.outgoingShares) { profile in
                outgoingShareCard(profile)
            }
            ForEach(viewModel.sharingState.friends) { friend in
                Button {
                    activityDetailFriend = friend
                } label: {
                    friendActivityCard(friend)
                }
                .buttonStyle(.plain)
            }
            if viewModel.sharingState.friends.isEmpty
                && viewModel.sharingState.outgoingShares.isEmpty
                && viewModel.sharingState.pendingInvite == nil {
                emptyFeedCard
            }
        }
        .padding(.horizontal, adaptiveLayout.usesExpandedLayout ? 12 : 4)
    }

    /// 好友动态卡：头像行 + 内嵌健康摘要小卡（设计稿的浅色底纹 + 大数值 + 进度条）。
    private func friendActivityCard(_ friend: FriendHealthProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                avatar(String(friend.name.prefix(1)), tint: friend.relationshipState.storyTint, online: !friend.isStale)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(shortRelativeText(friend.lastUpdated))
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(friend.isStale ? amber : liveTint)
                            .lineLimit(1)
                        if !friend.isStale {
                            Circle()
                                .fill(liveTint)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundStyle(secondaryInk.opacity(0.6))
                    .accessibilityHidden(true)
            }

            if friend.isStale {
                Label("缓存摘要，可能不是最新", systemImage: "clock")
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(amber)
            }

            friendSnapshotStrip(friend)
                .padding(.leading, 56)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开好友健康摘要")
    }

    /// 快照小卡：设计稿的浅蓝底纹卡（🌙 正在睡觉 / 大号时长 / 时段 / 进度条），
    /// 无睡眠数据时退化为步速样式。
    @ViewBuilder
    private func friendSnapshotStrip(_ friend: FriendHealthProfile) -> some View {
        let sleepDays = friend.snapshot.days.filter { $0.sleepMinutes != nil }
        if !sleepDays.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundStyle(sleepTint)
                    Text(friend.statusText)
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                }
                Text(friend.sleepText)
                    .font(.appSystem(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Colors.secondaryBackground)
                        Capsule()
                            .fill(sleepBarTint)
                            .frame(width: sleepProgressWidth(proxy.size.width, friend: friend))
                    }
                }
                .frame(height: 8)
                .accessibilityLabel("近 7 天睡眠进度")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "F5F7FF"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(friend.walkingText)
                            .font(.appSystem(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(ink)
                    } icon: {
                        Image(systemName: "figure.walk")
                            .font(.appSystem(size: 12, weight: .bold))
                            .foregroundStyle(walkTint)
                    }
                    Text("近 7 天步速")
                        .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(hex: "F5F7FF"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// 睡眠进度条宽度：用平均睡眠占 8 小时目标的比例，缺数据时保留最低可见宽度。
    private func sleepProgressWidth(_ available: CGFloat, friend: FriendHealthProfile) -> CGFloat {
        let minutes = friend.snapshot.highlights.averageSleepMinutes ?? 0
        let ratio = min(max(Double(minutes) / 480, 0.08), 1)
        return available * ratio
    }

    private func pendingInviteCard(_ invite: PendingInvite) -> some View {
        HStack(spacing: 12) {
            avatar("邀", tint: sky, online: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(invite.displayName)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text("邀请已准备好，等待发送或对方接受")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(shortDate(invite.createdAt))
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryInk)
        }
        .padding(16)
        .background(skySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(sky.opacity(0.18), lineWidth: 1)
        }
    }

    private func outgoingShareCard(_ profile: OutgoingShareProfile) -> some View {
        HStack(spacing: 12) {
            avatar(String(profile.displayName.prefix(1)), tint: amber, online: false)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(profile.displayName)
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(profile.relationshipState == .pendingOutgoingInvite ? "邀请中" : "已共享")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(amber.opacity(0.12), in: Capsule())
                }
                Text(profile.acceptanceText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                Button(
                    profile.relationshipState == .pendingOutgoingInvite ? "撤回邀请" : "停止向此人共享",
                    systemImage: "person.crop.circle.badge.minus",
                    role: .destructive
                ) { onRemoveOutgoingShare(profile) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .accessibilityLabel("管理与\(profile.displayName)的共享")
        }
        .padding(16)
        .background(amberSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(amber.opacity(0.16), lineWidth: 1)
        }
    }

    private var emptyFeedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "person.2.badge.plus")
                    .font(.appSystem(size: 20, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 46, height: 46)
                    .background(accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("把健康关心留给熟悉的人")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text("好友接受邀请后，对方主动共享的睡眠与步速摘要会出现在这里。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onInvite) {
                HStack(spacing: 8) {
                    if isInviteBusy {
                        ProgressView().tint(Theme.Colors.onAccent)
                    } else {
                        Image(systemName: "person.badge.plus")
                    }
                    Text(inviteButtonTitle)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                }
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isInviteDisabled)
            .opacity(isInviteDisabled ? 0.48 : 1)
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - 我的好友列表

    private var myFriendsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(
                "我的好友",
                detail: viewModel.sharingState.friends.isEmpty ? "等待第一位好友" : "\(viewModel.sharingState.friends.count) 位"
            )
            if viewModel.sharingState.friends.isEmpty {
                emptyFeedCard
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.sharingState.friends) { friend in
                        Button { onSelectFriend(friend) } label: { friendRow(friend) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if !viewModel.sharingState.outgoingShares.isEmpty {
                pendingInvitations
            }
        }
        .padding(.horizontal, adaptiveLayout.usesExpandedLayout ? 12 : 4)
    }

    private func friendRow(_ friend: FriendHealthProfile) -> some View {
        HStack(spacing: 14) {
            avatar(String(friend.name.prefix(1)), tint: friend.relationshipState.storyTint, online: !friend.isStale)
            VStack(alignment: .leading, spacing: 6) {
                Text(friend.name)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(friend.sleepText, systemImage: "moon.fill")
                    Label(friend.walkingText, systemImage: "figure.walk")
                }
                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryInk)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundStyle(secondaryInk)
                .frame(width: 32, height: 44)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(friend.relationshipState.storyTint.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开好友健康摘要")
    }

    private var pendingInvitations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("待处理邀请", systemImage: "paperplane.fill")
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(amber)
                .padding(.top, 4)
            ForEach(viewModel.sharingState.outgoingShares) { outgoingRow($0) }
        }
    }

    private func outgoingRow(_ profile: OutgoingShareProfile) -> some View {
        HStack(spacing: 14) {
            avatar(String(profile.displayName.prefix(1)), tint: amber, online: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Text(profile.acceptanceText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
            }
            Spacer(minLength: 4)
            Menu {
                Button(
                    profile.relationshipState == .pendingOutgoingInvite ? "撤回邀请" : "停止向此人共享",
                    systemImage: "person.crop.circle.badge.minus",
                    role: .destructive
                ) { onRemoveOutgoingShare(profile) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 40)
                    .background(amberSoft, in: Circle())
            }
            .accessibilityLabel("管理与\(profile.displayName)的共享")
        }
        .padding(14)
        .background(amberSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(amber.opacity(0.16), lineWidth: 1)
        }
    }

    // MARK: - 共享工具与页脚

    private var sharedToolsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("一起记得", detail: "你管理，对方只读查看")
            VStack(spacing: 0) {
                toolCard("共享待办", todoSummary, "checklist", accent, accentSoft, onManageTodos)
                Divider().padding(.leading, 64)
                toolCard("倒数日", countdownSummary, "calendar.badge.clock", sky, skySoft, onManageCountdowns)
                Divider().padding(.leading, 64)
                toolCard("特别关注", specialFocusSummary, "star.fill", Color(hex: "FFC94D").opacity(0.9), Color(hex: "FFF7E0")) { showingSpecialFocus = true }
                Divider().padding(.leading, 64)
                toolCard("健康报告分享", "生成我的周报卡片", "square.and.arrow.up.fill", liveTint, Color(hex: "E5F7F0")) { showingShareReportCard = true }
            }
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder.opacity(0.6), lineWidth: 1)
            }
        }
        .padding(.horizontal, adaptiveLayout.usesExpandedLayout ? 12 : 4)
    }

    private func toolCard(
        _ title: String,
        _ value: String,
        _ symbol: String,
        _ tint: Color,
        _ background: Color,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(background, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(value)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundStyle(secondaryInk)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var privacyFooter: some View {
        Label("好友邀请通过 iCloud 私密共享发送，健康摘要与共同事项均保持只读。", systemImage: "lock.shield.fill")
            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, adaptiveLayout.usesExpandedLayout ? 16 : 8)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
    }

    // MARK: - 状态横幅

    private var statusMessage: String? {
        let state = viewModel.sharingState
        if state.inviteFlowState == .preparing { return "正在准备 iCloud 好友邀请..." }
        if let message = state.inviteResultMessage { return message }
        if !state.isICloudAvailable && state.phase == .loaded {
            return String(localized: "iCloud 当前不可用。请在系统设置中登录 Apple ID 并开启 iCloud Drive 后重试。")
        }
        if let error = state.errorMessage { return error }
        if state.staleFriendCacheState != .none { return "部分好友信息来自本地缓存，刷新后会自动更新。" }
        return nil
    }

    @ViewBuilder
    private func statusBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.appSystem(size: 15, weight: .bold))
                .foregroundStyle(statusTint)
                .frame(width: 24, height: 24)
            Text(message)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(statusTint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(statusTint.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 通用小组件

    private func avatar(_ text: String, tint: Color, online: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(text.isEmpty ? "友" : text)
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.11), in: Circle())
                .overlay {
                    Circle().stroke(tint.opacity(0.2), lineWidth: 1)
                }
            if online {
                Circle()
                    .fill(accent)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().stroke(.white, lineWidth: 2) }
                    .accessibilityHidden(true)
            }
        }
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(ink)
            Spacer(minLength: 8)
            Text(detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)
                .multilineTextAlignment(.trailing)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private func shortRelativeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - 邀请按钮状态

    private var isInviteBusy: Bool {
        viewModel.isAuthorizingInvite || [.preparing, .presenting].contains(viewModel.sharingState.inviteFlowState)
    }

    private var isInviteDisabled: Bool {
        isInviteBusy
            || viewModel.sharingState.myStatus.permissionState == .unavailable
            || (viewModel.sharingState.phase == .loaded && !viewModel.sharingState.isICloudAvailable)
    }

    private var inviteButtonTitle: String {
        if viewModel.isAuthorizingInvite { return "正在连接健康数据" }
        switch viewModel.sharingState.inviteFlowState {
        case .preparing: return "正在准备邀请"
        case .presenting: return "系统邀请已打开"
        case .sent: return "继续邀请好友"
        default: return viewModel.sharingState.myStatus.permissionState == .needsPermission ? "授权并邀请好友" : "邀请好友"
        }
    }

    private var statusSymbol: String {
        if !viewModel.sharingState.isICloudAvailable { return "icloud.slash" }
        if viewModel.sharingState.inviteFlowState == .sent { return "paperplane.fill" }
        if viewModel.sharingState.errorMessage != nil { return "exclamationmark.triangle.fill" }
        return "arrow.triangle.2.circlepath"
    }

    private var statusTint: Color {
        if viewModel.sharingState.inviteFlowState == .sent { return accent }
        if viewModel.sharingState.errorMessage != nil || !viewModel.sharingState.isICloudAvailable {
            return Theme.Colors.accentRed
        }
        return sky
    }

    private var todoSummary: String {
        let count = viewModel.sharingState.myStatus.snapshot?.sharedTodoListSummary?.itemCount ?? 0
        return count == 0 ? "暂无共享事项" : "已共享 \(count) 项"
    }

    private var countdownSummary: String {
        let count = viewModel.sharingState.myStatus.snapshot?.sharedCountdownItems.count ?? 0
        return count == 0 ? "暂无共享日期" : "已共享 \(count) 个"
    }

    private var specialFocusSummary: String {
        let count = viewModel.sharingState.friends.count
        return count == 0 ? "关注重要状态" : "\(count) 位好友"
    }
}

#Preview {
    NavigationStack {
        SocialHealthDashboardView(
            viewModel: SocialViewModel(),
            onInvite: {},
            onRefresh: {},
            onManageTodos: {},
            onManageCountdowns: {},
            onStopSharing: {},
            onSelectFriend: { _ in },
            onRemoveOutgoingShare: { _ in }
        )
    }
}
