/// 我的设备页负责展示 Apple Watch 的连接、同步和排障入口。
import Foundation
import SwiftUI
import UIKit

/// MyDeviceView 采用设备状态 Hero，集中承载设备连接和同步操作。
struct MyDeviceView: View {
    @Bindable private var healthDataManager = HealthDataManager.shared
    @State private var isSyncingAppleWatch = false

    @Environment(\.openURL) private var openURL
    @Environment(\.adaptiveLayout) private var adaptiveLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            HealthDetailPageBackground()

            VStack(spacing: 0) {
                heroBackgroundColor
                    .frame(height: 200)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)

            AdaptivePageScrollView(
                style: .reading,
                topPadding: 16,
                bottomPadding: 40,
                showsIndicators: false
            ) {
                VStack(spacing: 20) {
                    pageHeroSection
                    syncPathCard
                    appleWatchActionsCard
                    if !isWatchReady {
                        connectionGuideCard
                    }
                    supportActionsCard
                }
            }
        }
        .healthDetailNavigation(title: "我的设备")
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            healthDataManager.refreshWatchSessionState()
        }
    }
}

private extension MyDeviceView {
    var pageHeroSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Label("Apple Watch", systemImage: "applewatch")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "455366"))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.surface.opacity(0.72), in: Capsule())

                Spacer(minLength: 8)

                Label(connectivityText, systemImage: heroIsActive ? "checkmark.circle.fill" : "clock.fill")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(heroTint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(heroTint.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("设备连接")
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(heroTint)
                    Text(heroTitle)
                        .font(.appSystem(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(heroSummary)
                        .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                DeviceHeroArtwork(
                    symbol: heroSymbol,
                    tint: heroTint,
                    isActive: heroIsActive
                )
                .frame(width: 124, height: 124)
            }

            VStack(spacing: 8) {
                heroFact(
                    title: "系统配对",
                    value: healthDataManager.isWatchPaired ? String(localized: "已完成") : String(localized: "未配对"),
                    symbol: "link"
                )
                heroFact(
                    title: "Watch App",
                    value: healthDataManager.isWatchAppInstalled ? String(localized: "已安装") : String(localized: "待安装"),
                    symbol: "app.badge.checkmark"
                )
                heroFact(title: "最近同步", value: lastWatchSyncText, symbol: "arrow.triangle.2.circlepath")
            }

            Button(action: performHeroAction) {
                HStack(spacing: 8) {
                    if isSyncingAppleWatch {
                        ProgressView()
                            .tint(Theme.Colors.onAccent)
                    } else {
                        Image(systemName: heroActionSymbol)
                            .font(.appSystem(size: 15, weight: .black))
                    }

                    Text(heroActionTitle)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(heroActionColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSyncingAppleWatch)
            .opacity(isSyncingAppleWatch ? 0.48 : 1)
        }
        .padding(.horizontal, adaptiveLayout.usesExpandedLayout ? 32 : 22)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [heroBackgroundColor, Color.white.opacity(0.74)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 36,
                bottomTrailingRadius: 36,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .padding(.horizontal, -adaptiveLayout.outerPadding)
        .padding(.top, -16)
    }

    func heroFact(title: LocalizedStringKey, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.appSystem(size: 12, weight: .black))
                .foregroundColor(heroTint)
                .frame(width: 26, height: 26)
                .background(heroTint.opacity(0.11), in: Circle())
            Text(title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    var syncPathCard: some View {
        deviceSurface {
            VStack(alignment: .leading, spacing: 16) {
                deviceSectionHeader(
                    title: "健康摘要同步",
                    subtitle: String(localized: "查看数据从 iPhone 到 Apple Watch 的准备状态。"),
                    symbol: "arrow.triangle.2.circlepath.icloud.fill",
                    tint: Color(hex: "316DF4"),
                    badge: syncReadinessText
                )

                VStack(spacing: 0) {
                    syncStepRow(
                        title: "系统配对",
                        detail: healthDataManager.isWatchPaired ? String(localized: "iPhone 与手表已建立配对") : String(localized: "需要先在 Watch App 中完成配对"),
                        symbol: "iphone.and.arrow.forward.inward",
                        isReady: healthDataManager.isWatchPaired
                    )
                    syncStepConnector(isReady: healthDataManager.isWatchPaired)
                    syncStepRow(
                        title: "手表端应用",
                        detail: healthDataManager.isWatchAppInstalled ? String(localized: "眠屿已安装到 Apple Watch") : String(localized: "等待安装眠屿手表端应用"),
                        symbol: "applewatch",
                        isReady: healthDataManager.isWatchAppInstalled
                    )
                    syncStepConnector(isReady: healthDataManager.isWatchAppInstalled)
                    syncStepRow(
                        title: "健康摘要",
                        detail: healthDataManager.isWatchReachable ? String(localized: "当前可发送最新健康摘要") : String(localized: "手表在线后将继续后台同步"),
                        symbol: "heart.text.square.fill",
                        isReady: healthDataManager.isWatchReachable
                    )
                }
            }
        }
    }

    var appleWatchActionsCard: some View {
        deviceSurface {
            VStack(alignment: .leading, spacing: 4) {
                Text("同步与操作")
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(statusInsightText)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)

                deviceActionButton(
                    title: "重新检查连接",
                    subtitle: "刷新配对、安装与在线状态",
                    symbol: "arrow.clockwise",
                    tint: Color(hex: "2BA77A")
                ) {
                    healthDataManager.refreshWatchSessionState()
                }

                Divider()
                    .padding(.leading, 52)

                deviceActionButton(
                    title: "打开系统设置",
                    subtitle: "检查 眠屿 的系统权限",
                    symbol: "gearshape.fill",
                    tint: Color(hex: "316DF4")
                ) {
                    openSystemSettings()
                }
            }
        }
    }

    var connectionGuideCard: some View {
        deviceSurface {
            VStack(alignment: .leading, spacing: 16) {
                Text("连接检查")
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("按以下步骤检查 Apple Watch 的连接状态。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                supportDeviceRow(
                    title: "Apple Watch",
                    status: connectivityText,
                    detail: appleSupportStepDetail,
                    symbol: "applewatch",
                    tint: appleStatusColor,
                    statusTint: appleStatusColor
                )
            }
        }
    }

    var supportActionsCard: some View {
        deviceSurface {
            VStack(alignment: .leading, spacing: 4) {
                Text("更多帮助")
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.bottom, 6)

                NavigationLink {
                    FAQListView()
                } label: {
                    deviceActionLabel(
                        title: "手表常见问题",
                        subtitle: "查看配对、安装与同步说明",
                        symbol: "questionmark.bubble.fill",
                        tint: Color(hex: "D78745"),
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 52)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "586CDE"))
                        .frame(width: 42, height: 42)
                        .background(Color(hex: "EEF1FF"), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("同步说明")
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("仅在你的 iPhone 与 Apple Watch 之间同步健康摘要，不会经过眠屿后端。")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
            }
        }
    }
}

private extension MyDeviceView {
    var statusGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    func deviceSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .background(
                Color.white.opacity(0.96),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 14, x: 0, y: 7)
    }

    func deviceSectionHeader(
        title: LocalizedStringKey,
        subtitle: String,
        symbol: String,
        tint: Color,
        badge: String
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tint.opacity(0.11))

                Image(systemName: symbol)
                    .font(.appSystem(size: 21, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 6)

                    Text(badge)
                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.11), in: Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text(subtitle)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func deviceMetricTile(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundColor(tint)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "202938"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(title)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func deviceActionButton(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            deviceActionLabel(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                tint: tint,
                showsChevron: false
            )
        }
        .buttonStyle(.plain)
    }

    func deviceActionLabel(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        symbol: String,
        tint: Color,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.11))

                Image(systemName: symbol)
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: showsChevron ? "chevron.right" : "arrow.up.right")
                .font(.appSystem(size: 12, weight: .black))
                .foregroundColor(Color(hex: "A2A9B5"))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 9)
    }

    func supportDeviceRow(
        title: LocalizedStringKey,
        status: String,
        detail: String,
        symbol: String,
        tint: Color,
        statusTint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.11))

                Image(systemName: symbol)
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(status)
                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(statusTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            statusTint.opacity(0.10),
                            in: Capsule()
                        )
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    func syncStepRow(
        title: LocalizedStringKey,
        detail: String,
        symbol: String,
        isReady: Bool
    ) -> some View {
        let accent = isReady ? Color(hex: "2BA77A") : Color(hex: "D98B2B")

        return HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.appSystem(size: 17, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: isReady ? "checkmark.circle.fill" : "clock.fill")
                .font(.appSystem(size: 18, weight: .black))
                .foregroundColor(accent)
                .accessibilityLabel(isReady ? String(localized: "已就绪") : String(localized: "待完成"))
        }
        .padding(.vertical, 4)
    }

    func syncStepConnector(isReady: Bool) -> some View {
        Rectangle()
            .fill((isReady ? Color(hex: "2BA77A") : Color(hex: "D8DFE8")).opacity(0.38))
            .frame(width: 2, height: 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
    }
}

private extension MyDeviceView {
    var heroBackgroundColor: Color {
        if healthDataManager.isWatchReachable { return Color(hex: "DFF5EA") }
        if healthDataManager.isWatchPaired && healthDataManager.isWatchAppInstalled {
            return Color(hex: "FFF1D9")
        }
        return Color(hex: "EAEFF6")
    }

    var heroTint: Color { appleStatusColor }

    var heroSymbol: String {
        healthDataManager.isWatchPaired ? "applewatch.watchface" : "applewatch.slash"
    }

    var heroIsActive: Bool { healthDataManager.isWatchReachable }

    var heroTitle: String {
        if healthDataManager.isWatchReachable { return String(localized: "手表已准备就绪") }
        if healthDataManager.isWatchPaired && !healthDataManager.isWatchAppInstalled {
            return String(localized: "安装手表端 App")
        }
        if healthDataManager.isWatchPaired { return String(localized: "保持手表在身边") }
        return String(localized: "先连接你的手表")
    }

    var heroSummary: String { connectionSummary }

    var heroActionTitle: String {
        if healthDataManager.isWatchReachable { return String(localized: "同步最新数据") }
        if !healthDataManager.isWatchPaired { return String(localized: "重新检查配对") }
        if !healthDataManager.isWatchAppInstalled { return String(localized: "检查安装状态") }
        return String(localized: "同步后台数据")
    }

    var heroActionSymbol: String {
        canSyncAppleWatchData ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
    }

    var heroActionColor: Color { Color(hex: "316DF4") }

    func performHeroAction() {
        healthDataManager.refreshWatchSessionState()
        guard canSyncAppleWatchData else { return }
        isSyncingAppleWatch = true
        Task {
            await HealthDataManager.shared.syncAllData()
            healthDataManager.refreshWatchSessionState()
            isSyncingAppleWatch = false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    var canSyncAppleWatchData: Bool {
        healthDataManager.isWatchPaired && healthDataManager.isWatchAppInstalled
    }

    var isWatchReady: Bool {
        healthDataManager.isWatchPaired
            && healthDataManager.isWatchAppInstalled
            && healthDataManager.isWatchReachable
    }

    var syncReadinessText: String {
        if isWatchReady { return String(localized: "全部就绪") }
        if healthDataManager.isWatchPaired { return String(localized: "还差一步") }
        return String(localized: "需要设置")
    }
}

private extension MyDeviceView {
    var appleStatusColor: Color {
        if !healthDataManager.isWatchPaired { return Color(hex: "7D8797") }
        if !healthDataManager.isWatchAppInstalled { return Color(hex: "D98B2B") }
        if healthDataManager.isWatchReachable { return Color(hex: "2BA77A") }
        if healthDataManager.watchActivationState == .activated { return Color(hex: "D98B2B") }
        return Color(hex: "7D8797")
    }

    var connectivityText: String {
        if !healthDataManager.isWatchPaired { return String(localized: "未配对") }
        if !healthDataManager.isWatchAppInstalled { return String(localized: "待安装") }
        if healthDataManager.isWatchReachable { return String(localized: "已连接") }
        if healthDataManager.watchActivationState == .activated { return String(localized: "等待连接") }
        return String(localized: "未激活")
    }

    var watchConnectionMetricText: String {
        if !healthDataManager.isWatchPaired { return String(localized: "未配对") }
        if !healthDataManager.isWatchAppInstalled { return String(localized: "待安装") }
        if healthDataManager.isWatchReachable { return String(localized: "在线") }
        if healthDataManager.watchActivationState == .activated { return String(localized: "后台等待") }
        return String(localized: "未激活")
    }

    var watchConnectionMetricSymbol: String {
        if !healthDataManager.isWatchPaired { return "link.badge.plus" }
        if !healthDataManager.isWatchAppInstalled { return "arrow.down.circle.fill" }
        if healthDataManager.isWatchReachable { return "dot.radiowaves.left.and.right" }
        return "clock.arrow.circlepath"
    }

    var watchConnectionMetricColor: Color {
        if healthDataManager.isWatchReachable { return Color(hex: "2BA77A") }
        if healthDataManager.isWatchPaired { return Color(hex: "D98B2B") }
        return Color(hex: "7D8797")
    }

    var connectionSummary: String {
        if !healthDataManager.isWatchPaired {
            return String(localized: "还没有检测到已配对的 Apple Watch，可先刷新状态或前往系统设置检查。")
        }
        if !healthDataManager.isWatchAppInstalled {
            return String(localized: "已经检测到 Apple Watch，但手表端 App 还没有安装完成。")
        }
        if !healthDataManager.isWatchReachable {
            return String(localized: "设备已经配对，当前会在手表再次在线后继续后台同步。")
        }
        return String(localized: "Apple Watch 当前在线，可以接收最新健康摘要。")
    }

    var statusInsightText: String {
        if !healthDataManager.isWatchPaired {
            return String(localized: "请先在 iPhone 和 Apple Watch 之间完成系统级配对，再返回这里刷新状态。")
        }
        if !healthDataManager.isWatchAppInstalled {
            return String(localized: "先在手表上安装并打开一次 眠屿，后续健康摘要和表盘内容会更稳定。")
        }
        if !healthDataManager.isWatchReachable {
            return String(localized: "Watch 不在线时仍可通过后台上下文补同步，手表端再次打开后会自动收到最新摘要。")
        }
        return String(localized: "连接已经就绪，可把 iPhone 上最新的心率、HRV、活动和睡眠摘要同步到 Watch。")
    }

    var lastWatchSyncText: String {
        guard let date = healthDataManager.lastWatchSyncDate else { return String(localized: "暂无记录") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var appleSupportStepDetail: String {
        if !healthDataManager.isWatchPaired {
            return String(localized: "先使用 iPhone 上的 Watch App 完成系统配对。")
        }
        if !healthDataManager.isWatchAppInstalled {
            return String(localized: "在 Watch App 中安装眠屿，并在手表上打开一次。")
        }
        return String(localized: "配对与手表端 App 均已就绪。")
    }
}

private struct DeviceHeroArtwork: View {
    let symbol: String
    let tint: Color
    let isActive: Bool

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 2)
                .frame(width: 124, height: 104)
                .scaleEffect(isAnimating && isActive && !reduceMotion ? 1.04 : 0.96)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(tint.opacity(0.26), lineWidth: 2)
                .frame(width: 104, height: 86)
                .scaleEffect(isAnimating && isActive && !reduceMotion ? 1.03 : 0.98)

            Image(systemName: symbol)
                .font(.system(size: 62, weight: .light))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .shadow(color: tint.opacity(0.18), radius: 12, x: 0, y: 8)

            Image(systemName: isActive ? "checkmark.circle.fill" : "clock.fill")
                .font(.appSystem(size: 20, weight: .bold))
                .foregroundStyle(isActive ? Color(hex: "2BA77A") : Color(hex: "D98B2B"))
                .background(Theme.Colors.surface, in: Circle())
                .offset(x: 38, y: 36)
        }
        .onAppear {
            guard isActive, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue && !reduceMotion {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            } else {
                isAnimating = false
            }
        }
        .accessibilityHidden(true)
    }
}
