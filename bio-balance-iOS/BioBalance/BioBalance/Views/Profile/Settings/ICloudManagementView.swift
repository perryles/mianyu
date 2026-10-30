/// ICloudManagementView 由 ProfileView iCloud 入口调用，作为「iCloud 管理」页面。
/// 负责集中管理 眠屿 写入 CloudKit 的各业务域同步开关。

import CloudKit
import SwiftUI

/// 集中管理 眠屿 写入 CloudKit 的各业务域。
struct ICloudManagementView: View {
    @AppStorage(CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled)
    private var drinkExperienceSyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled)
    private var sleepSummarySyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled)
    private var medicationHealthSyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.pregnancySyncEnabled)
    private var pregnancySyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.goalMascotSyncEnabled)
    private var goalMascotSyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.onboardingPreferenceSyncEnabled)
    private var onboardingPreferenceSyncEnabled = true
    @AppStorage(CloudKitDataPolicy.PreferenceKey.socialSharingEnabled)
    private var socialSharingEnabled = true

    @State private var accountStatus: CKAccountStatus?
    @State private var isCheckingAccount = false
    @State private var isRefreshing = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsSuccess = true

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            AdaptivePageScrollView(topPadding: 14, bottomPadding: 88) {
                VStack(alignment: .leading, spacing: 16) {
                    accountCard

                    syncSummaryCard

                    SettingsSectionCard(title: "健康与生活数据") {
                        VStack(spacing: 0) {
                            toggleRow(icon: "fork.knife", tint: Color(hex: "FF9F43"), title: "餐饮数据同步", subtitle: "同步结构化记录，不包含原始图片和精确位置", isOn: $drinkExperienceSyncEnabled)
                            rowDivider
                            toggleRow(icon: "bed.double.fill", tint: Color(hex: "7D8BFF"), title: "睡眠数据同步", subtitle: "同步睡眠摘要，不上传录音和打鼾片段", isOn: $sleepSummarySyncEnabled)
                            rowDivider
                            toggleRow(icon: "cross.case.fill", tint: Color(hex: "536FE8"), title: "药物与处方同步", subtitle: "同步确认后的结构化药物、处方和病症资料", isOn: $medicationHealthSyncEnabled)
                            rowDivider
                            toggleRow(icon: "figure.and.child.holdinghands", tint: Color(hex: "E98AB3"), title: "孕期资料同步", subtitle: "同步孕期档案、体重和胎动记录", isOn: $pregnancySyncEnabled)
                        }
                    }

                    SettingsSectionCard(title: "功能与共享") {
                        VStack(spacing: 0) {
                            toggleRow(icon: "person.text.rectangle.fill", tint: Color(hex: "4E8EF7"), title: "引导偏好同步", subtitle: "同步关注领域、健康目标和主动填写的基础资料", isOn: $onboardingPreferenceSyncEnabled)
                            rowDivider
                            toggleRow(icon: "pawprint.fill", tint: Color(hex: "B78CFF"), title: "吉祥物数据同步", subtitle: "同步吉祥物档案、成长进度和 XP 记录", isOn: $goalMascotSyncEnabled)
                            rowDivider
                            toggleRow(icon: "person.2.fill", tint: Theme.Colors.mintGreen, title: "社交共享", subtitle: "允许好友发现、健康摘要邀请和协作待办", isOn: $socialSharingEnabled)
                        }
                    }

                    syncButton

                    if let feedbackMessage {
                        feedbackBanner(message: feedbackMessage)
                    }

                    privacyNote
                }
            }
        }
        .navigationTitle("iCloud 管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAccountStatus() }
        .onChange(of: drinkExperienceSyncEnabled) { _, enabled in
            synchronizeAfterEnabling(.drinkExperience, enabled: enabled)
        }
        .onChange(of: sleepSummarySyncEnabled) { _, enabled in
            synchronizeAfterEnabling(.sleepSummary, enabled: enabled)
        }
        .onChange(of: medicationHealthSyncEnabled) { _, enabled in
            synchronizeAfterEnabling(.medicationHealth, enabled: enabled)
        }
        .onChange(of: pregnancySyncEnabled) { _, enabled in
            synchronizeAfterEnabling(.pregnancy, enabled: enabled)
        }
        .onChange(of: goalMascotSyncEnabled) { _, enabled in
            synchronizeAfterEnabling(.goalMascot, enabled: enabled)
        }
        .onChange(of: onboardingPreferenceSyncEnabled) { _, enabled in
            synchronizeAfterEnabling(.onboardingPreference, enabled: enabled)
        }
        .onChange(of: socialSharingEnabled) { _, enabled in
            synchronizeAfterEnabling(.socialSharing, enabled: enabled)
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 15) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                    Image(systemName: accountIcon)
                        .font(.appSystem(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 6) {
                    Text("iCloud")
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                    Text(accountTitle)
                        .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(accountDescription)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(accountStatus == .available ? Color(hex: "61E6A8") : Color.white.opacity(0.72))
                    .frame(width: 7, height: 7)
                Text(accountStatus == .available ? "连接正常" : "点击重新检查")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                Spacer()
                if isCheckingAccount {
                    ProgressView().tint(Theme.Colors.onAccent).controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.appSystem(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Theme.Colors.surface.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture {
                guard !isCheckingAccount else { return }
                Task { await refreshAccountStatus() }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: "4089F6"), Color(hex: "625DEB")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: Color(hex: "536FE8").opacity(0.2), radius: 18, y: 9)
    }

    private var syncSummaryCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.Colors.surfaceBorder, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(enabledItemCount) / 6)
                    .stroke(Theme.Colors.accentBlue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(enabledItemCount)")
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("同步项目")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("已开启 \(enabledItemCount) 项 · 共 6 项")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Spacer()
            Text(enabledItemCount == 6 ? "全部开启" : "自定义")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(enabledItemCount == 6 ? Theme.Colors.mintGreen : Theme.Colors.accentBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((enabledItemCount == 6 ? Theme.Colors.mintGreen : Theme.Colors.accentBlue).opacity(0.1), in: Capsule())
        }
        .padding(17)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func toggleRow(icon: String, tint: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        SettingsToggleDetailRow(icon: icon, tint: tint, title: title, subtitle: subtitle, isOn: isOn)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 86)
    }

    private var syncButton: some View {
        Button {
            Task { await synchronizeEnabledDomains() }
        } label: {
            HStack(spacing: 10) {
                if isRefreshing {
                    ProgressView().tint(Theme.Colors.onAccent)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                }
                Text(isRefreshing ? "正在同步" : "立即同步已开启项目")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(colors: [Theme.Colors.accentBlue, Color(hex: "625DEB")], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing || accountStatus != .available)
        .opacity(accountStatus == .available ? 1 : 0.48)
    }

    private func feedbackBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: feedbackIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(feedbackIsSuccess ? Theme.Colors.mintGreen : Color(hex: "FF9F43"))
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(Theme.Colors.accentBlue)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("关于隐私")
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("数据保存在当前 Apple ID 的 iCloud 中。关闭同步不会删除已保存的数据，再次开启后会恢复同步。")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 8)
    }

    private var enabledItemCount: Int {
        [drinkExperienceSyncEnabled, sleepSummarySyncEnabled, medicationHealthSyncEnabled,
         pregnancySyncEnabled, onboardingPreferenceSyncEnabled, goalMascotSyncEnabled, socialSharingEnabled]
            .filter { $0 }.count
    }

    private var accountIcon: String {
        if isCheckingAccount || accountStatus == nil { return "icloud" }
        return accountStatus == .available ? "checkmark.icloud.fill" : "icloud.slash.fill"
    }

    private var accountTitle: String {
        switch accountStatus {
        case .available: return String(localized: "iCloud 已连接")
        case .noAccount: return String(localized: "未登录 iCloud")
        case .restricted: return String(localized: "iCloud 访问受限")
        case .couldNotDetermine: return String(localized: "无法确认 iCloud 状态")
        case .temporarilyUnavailable: return String(localized: "iCloud 暂时不可用")
        case nil: return String(localized: "正在检查 iCloud")
        @unknown default: return String(localized: "iCloud 状态未知")
        }
    }

    private var accountDescription: String {
        accountStatus == .available
            ? "你的数据可在同一 Apple ID 的设备间保持同步"
            : "请检查系统设置中的 Apple ID 与 iCloud Drive"
    }

    private func refreshAccountStatus() async {
        guard !isCheckingAccount else { return }
        isCheckingAccount = true
        defer { isCheckingAccount = false }
        accountStatus = await ICloudSyncCoordinator.shared.accountStatus()
    }

    @MainActor
    private func synchronizeEnabledDomains() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        feedbackMessage = nil
        feedbackIsSuccess = true
        defer { isRefreshing = false }

        let report = await ICloudSyncCoordinator.shared.synchronizeEnabledDomains(includePregnancy: true)
        accountStatus = report.accountStatus
        if report.accountStatus != .available {
            feedbackIsSuccess = false
            feedbackMessage = String(localized: "iCloud 当前不可用，请检查账户与网络设置")
        } else if report.failureCount > 0 {
            feedbackIsSuccess = false
            feedbackMessage = String(localized: "已同步 \(report.successfulCount) 项，\(report.failureCount) 项未完成，可稍后重试")
        } else {
            feedbackMessage = String(localized: "已同步 \(report.successfulCount) 个开启的项目")
        }
    }

    private func synchronizeAfterEnabling(_ domain: ICloudSyncDomain, enabled: Bool) {
        guard enabled else { return }
        Task {
            let outcome = await ICloudSyncCoordinator.shared.synchronize(domain)
            guard outcome.state == .failed else { return }
            feedbackIsSuccess = false
            feedbackMessage = outcome.message ?? "同步未完成，请稍后重试"
        }
    }
}

#Preview {
    NavigationStack { ICloudManagementView() }
        .environment(AppFontScaleStore.shared)
}
