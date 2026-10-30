/// 添加好友页：设计稿「添加好友」（6:67）。
/// 搜索、二维码 / 邀请链接入口与「可能认识的人」列表。
/// 添加动作复用现有 iCloud 邀请流程（onInvite）；
/// 推荐列表当前无服务端来源，展示引导文案占位，不伪造用户数据。

import SwiftUI

struct SocialAddFriendView: View {
    /// 触发现有 iCloud 邀请流程（与首页「邀请好友」一致）。
    let onInvite: () -> Void
    let friends: [FriendHealthProfile]
    let outgoingShares: [OutgoingShareProfile]
    let myProfile: PublicUserProfile?
    let onSearch: @MainActor (String) async throws -> PublicUserProfile

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResult: PublicUserProfile?
    @State private var searchMessage: String?
    @State private var isSearching = false

    private let ink = Color(hex: "12141A")
    private let secondaryInk = Color(hex: "6E7887")
    private let canvas = Color(hex: "F6F9FB")
    private let trackInk = Color(hex: "F1F4F8")
    private let accent = Theme.Colors.mintGreen
    private let sky = Theme.Colors.accentBlue
    private let skySoft = Color(hex: "E8F7FF")
    private let mintSoft = Color(hex: "EDFCF2")

    var body: some View {
        AdaptivePageScrollView(topPadding: 8, bottomPadding: 40) {
            VStack(alignment: .leading, spacing: 20) {
                searchField
                if let searchResult { searchResultCard(searchResult) }
                if let searchMessage {
                    Text(searchMessage)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryInk)
                        .padding(.horizontal, 4)
                }
                inviteChannels
                suggestionSection
            }
        }
        .background(canvas)
        .navigationTitle("添加好友")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

    private var invitationIllustration: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 68, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 180, height: 160)
                .background {
                    Circle()
                        .fill(mintSoft)
                        .frame(width: 156, height: 156)
                        .offset(x: -32)
                    Circle()
                        .fill(skySoft.opacity(0.8))
                        .frame(width: 140, height: 140)
                        .offset(x: 40, y: 12)
                }
                .accessibilityHidden(true)
            Text("找到你关心的人")
                .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("添加好友")
                .font(.appSystem(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(ink)
            Text("找到你关心的人")
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)
        }
        .padding(.horizontal, 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.appSystem(size: 14, weight: .semibold))
                .foregroundStyle(secondaryInk)
            TextField("搜索用户 ID", text: $searchText)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(performSearch)
            if isSearching {
                ProgressView().controlSize(.small)
            } else {
                Button(action: performSearch) {
                    Image(systemName: "arrow.right")
                        .frame(width: 44, height: 44)
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(trackInk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 2)
        .accessibilityHint("使用对方公开的眠屿用户 ID 搜索")
    }

    private func performSearch() {
        guard !isSearching else { return }
        isSearching = true
        searchResult = nil
        searchMessage = nil
        Task { @MainActor in
            defer { isSearching = false }
            do {
                let profile = try await onSearch(searchText)
                searchResult = profile
                if profile.recordName == myProfile?.recordName {
                    searchMessage = "不能添加自己。"
                } else if friends.contains(where: { $0.ownerUserRecordName == profile.recordName }) {
                    searchMessage = "你们已经是好友。"
                } else if outgoingShares.contains(where: { $0.ownerUserRecordName == profile.recordName }) {
                    searchMessage = "邀请已发送，正在等待对方确认。"
                }
            } catch {
                searchMessage = "没有找到这个用户 ID，请检查后重试。"
            }
        }
    }

    private func searchResultCard(_ profile: PublicUserProfile) -> some View {
        let cannotInvite = profile.recordName == myProfile?.recordName
            || friends.contains(where: { $0.ownerUserRecordName == profile.recordName })
            || outgoingShares.contains(where: { $0.ownerUserRecordName == profile.recordName })
        return HStack(spacing: 12) {
            Text(String(profile.displayName.prefix(1)))
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .frame(width: 44, height: 44)
                .background(skySoft, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName).font(.headline)
                Text("@\(profile.handle)").font(.caption).foregroundStyle(secondaryInk)
            }
            Spacer()
            Button("邀请") { onInvite() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(cannotInvite)
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var inviteChannels: some View {
        VStack(spacing: 10) {
            channelCard(
                symbol: "qrcode",
                tint: sky,
                background: skySoft,
                title: "我的二维码",
                detail: "让好友扫码添加",
                action: onInvite
            )
            channelCard(
                symbol: "link",
                tint: accent,
                background: mintSoft,
                title: "邀请链接",
                detail: "分享给微信好友",
                action: onInvite
            )
        }
    }

    private func channelCard(
        symbol: String,
        tint: Color,
        background: Color,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(detail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryInk)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundStyle(secondaryInk)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开 iCloud 邀请")
    }

    /// 设计稿的「可能认识的人」区。当前隐私策略不读取通讯录也不做服务端推荐，
    /// 因此用说明占位，搜索内容仅做本地过滤已有共享连接。
    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("可能认识的人")
                .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                Image(systemName: "person.2.viewfinder")
                    .font(.appSystem(size: 17, weight: .semibold))
                    .foregroundStyle(sky)
                    .frame(width: 40, height: 40)
                    .background(skySoft, in: Circle())
                Text("眠屿不会读取你的通讯录。你可以搜索公开用户 ID，或通过二维码与邀请链接添加好友。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

#Preview {
    NavigationStack {
        SocialAddFriendView(
            onInvite: {},
            friends: [],
            outgoingShares: [],
            myProfile: nil,
            onSearch: { _ in throw CloudKitDomainError.profileNotFound }
        )
    }
}
