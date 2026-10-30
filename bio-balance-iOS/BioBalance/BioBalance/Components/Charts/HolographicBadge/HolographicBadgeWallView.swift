/// 全息徽章墙：头部统计（获得 N 枚 · 超过 X% 用户）+ 按系列分组的网格。
/// 已解锁徽章带「新获得」角标（庆祝确认后 7 天内显示）；点击进入详情。

import SwiftUI
import Combine

struct HolographicBadgeWallView: View {
    @State private var statuses: [HolographicBadgeStatus] = []
    @State private var selectedBadgeID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSummary
                seriesSections
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(HolographicBadgePalette.canvas.ignoresSafeArea())
        .navigationTitle("全息徽章")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .holographicBadgesDidChange).receive(on: RunLoop.main)) { _ in
            reload()
        }
        .navigationDestination(item: $selectedBadgeID) { badgeID in
            HolographicBadgeDetailView(badgeID: badgeID)
        }
    }

    private func reload() {
        statuses = HolographicBadgeStore.shared.allStatuses()
    }

    // MARK: - 头部统计

    private var headerSummary: some View {
        let unlocked = statuses.filter(\.isUnlocked).count
        let percentile = HolographicBadgeStore.shared.percentileText(unlocked: unlocked)
        return VStack(alignment: .leading, spacing: 10) {
            Text("我的徽章")
                .font(.appSystem(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: 6) {
                Text("获得 \(unlocked) 枚徽章")
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
                if let percentile {
                    Text("· " + percentile)
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(HolographicBadgePalette.goldText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 系列分组

    @ViewBuilder
    private var seriesSections: some View {
        let seriesNames = orderedSeriesNames()
        ForEach(seriesNames, id: \.self) { series in
            let items = statuses.filter { localized($0.definition.seriesKey) == series }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(series)
                        .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
                        ForEach(items) { status in
                            BadgeWallCell(status: status) {
                                selectedBadgeID = status.id
                            }
                        }
                    }
                }
            }
        }
    }

    private func orderedSeriesNames() -> [String] {
        var names: [String] = []
        for status in statuses {
            let name = localized(status.definition.seriesKey)
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }
}

// MARK: - 网格单元格

private struct BadgeWallCell: View {
    let status: HolographicBadgeStatus
    let onTap: () -> Void
    @State private var tiltX: CGFloat = 0
    @State private var tiltY: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 「新获得」角标：解锁后 7 天内显示。
    private var showsNewTag: Bool {
        guard let unlockedAt = status.unlockedAt else { return false }
        return Date().timeIntervalSince(unlockedAt) < 7 * 24 * 3600
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                HolographicMedalView(
                    theme: status.definition.theme,
                    symbol: status.definition.symbol,
                    headerText: status.definition.isMonthly ? monthText : nil,
                    tiltX: tiltX,
                    tiltY: tiltY
                )
                .frame(width: 92, height: 92)
                .overlay(alignment: .topTrailing) {
                    if showsNewTag {
                        NewBadgeTag()
                            .offset(x: 7, y: -6)
                    }
                }

                VStack(spacing: 3) {
                    Text(localizedTitle)
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(status.isUnlocked ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        .lineLimit(1)
                    Text(status.isUnlocked ? unlockedText : progressText)
                        .font(.appSystem(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(BadgeCellButtonStyle())
        .onHover { hovering in
            // iPad 指针悬停的轻微视角联动
            guard !reduceMotion else { return }
            tiltX = hovering ? 0.25 : 0
            tiltY = hovering ? -0.15 : 0
        }
        .accessibilityLabel(accessibilityText)
    }

    private var localizedTitle: String {
        String(localized: String.LocalizationValue(status.definition.titleKey))
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("M")
        let reference = status.unlockedAt ?? Date()
        return String(localized: "\(formatter.string(from: reference))月")
    }

    private var unlockedText: String {
        if let text = status.unlockedDateText() {
            return String(localized: "\(text) 点亮")
        }
        return localizedTitle
    }

    private var progressText: String {
        String(localized: "已完成 \(status.progressDays)/\(status.definition.requiredDays) 天")
    }

    private var accessibilityText: String {
        if status.isUnlocked {
            return localizedTitle + ", " + String(localized: "已获得")
        }
        return localizedTitle + ", " + progressText
    }
}

private struct NewBadgeTag: View {
    var body: some View {
        Text("新获得")
            .font(.appSystem(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.Colors.onAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(hex: "E85D5D"), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.8))
            .shadow(color: Color.black.opacity(0.3), radius: 3, y: 2)
    }
}

private struct BadgeCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(MotionTokens.cardPressAnimation, value: configuration.isPressed)
    }
}
