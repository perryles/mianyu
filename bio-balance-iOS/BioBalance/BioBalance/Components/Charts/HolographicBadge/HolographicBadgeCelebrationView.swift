/// 解锁庆祝弹窗：参考「恭喜你新获得1枚勋章」的沉浸式弹层。
/// 金色标题 + 大奖章（拖拽联动）+ 任务达成摘要 + 「收入囊中」主按钮。

import SwiftUI

struct HolographicBadgeCelebrationView: View {
    /// 待庆祝的徽章（按解锁时间倒序）；弹窗逐枚展示。
    let badges: [HolographicBadgeStatus]
    /// 点「收入囊中」后整组弹窗关闭。
    var onFinished: () -> Void

    @State private var index = 0
    @State private var tilt = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: HolographicBadgeStatus? {
        badges.indices.contains(index) ? badges[index] : nil
    }

    var body: some View {
        ZStack {
            // 模态遮罩只做轻微压暗，保持与全局浅色体系一致
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: dismissCurrent)

            if let badge = current {
                VStack(spacing: 0) {
                    closeButton
                    content(badge)
                }
                .background(
                    HolographicBadgePalette.surface,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(HolographicBadgePalette.surfaceStroke, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 24, y: 8)
                .padding(.horizontal, 16)
            }

            // 彩带覆盖整屏，不被卡片裁切
            ConfettiOverlay(intensity: 1.2)
        }
    }

    private var closeButton: some View {
        HStack {
            Spacer()
            Button(action: dismissCurrent) {
                Image(systemName: "xmark")
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.Colors.secondarySurface))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func content(_ badge: HolographicBadgeStatus) -> some View {
        let title = String(localized: String.LocalizationValue(badge.definition.titleKey))
        VStack(spacing: 22) {
            congratulationTitle

            HolographicMedalView(
                theme: badge.definition.theme,
                symbol: badge.definition.symbol,
                headerText: badge.definition.isMonthly ? monthText(badge) : nil,
                tiltX: tilt.width / 50,
                tiltY: tilt.height / 50
            )
            .frame(width: 190, height: 190)
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : Double(tilt.height) / 3),
                axis: (x: 1, y: 0, z: 0)
            )
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : Double(tilt.width) / 3),
                axis: (x: 0, y: 1, z: 0)
            )
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard !reduceMotion else { return }
                        tilt = CGSize(
                            width: min(50, max(-50, value.translation.width)),
                            height: min(50, max(-50, value.translation.height))
                        )
                    }
                    .onEnded { _ in tilt = .zero }
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tilt)

            VStack(spacing: 6) {
                Text(title)
                    .font(.appSystem(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(requirementText(badge))
                    .font(.appSystem(size: 14, weight: .regular))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(unlockDateText(badge))
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            collectButton(title)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
    }

    private var congratulationTitle: some View {
        let count = badges.count
        let base = String(localized: "恭喜你新获得")
        let countText = count > 1 ? String(localized: "\(count) 枚") : String(localized: "1枚")
        let tail = String(localized: "勋章")
        return Text(base + countText + tail)
            .font(.appSystem(size: 25, weight: .heavy, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(hex: "D9A32B"), Color(hex: "A9780F")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }

    private func requirementText(_ badge: HolographicBadgeStatus) -> String {
        String(
            localized: String.LocalizationValue(
                badge.definition.requirementKey.replacingOccurrences(
                    of: "%lld",
                    with: "\(badge.definition.requiredDays)"
                )
            )
        )
    }

    private func unlockDateText(_ badge: HolographicBadgeStatus) -> String {
        if let dateText = badge.unlockedDateText() {
            return String(localized: "\(dateText) 点亮")
        }
        return String(localized: "已点亮")
    }

    private func collectButton(_ title: String) -> some View {
        Button(action: collectCurrent) {
            Text("收入囊中")
                .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "5B431F"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(hex: "FCE9B0"), Color(hex: "EDBE5C")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: Color(hex: "EDBE5C").opacity(0.35), radius: 12, y: 5)
        }
        .buttonStyle(CardPressButtonStyle())
        .padding(.top, 8)
    }

    // MARK: - 操作

    private func collectCurrent() {
        guard let badge = current else {
            onFinished()
            return
        }
        HolographicBadgeStore.shared.markCelebrated(badgeID: badge.id)
        if index + 1 < badges.count {
            index += 1
            tilt = .zero
        } else {
            onFinished()
        }
    }

    private func dismissCurrent() {
        // 点关闭视为确认，避免下次启动重复弹（与「收入囊中」等效）。
        if let badge = current {
            HolographicBadgeStore.shared.markCelebrated(badgeID: badge.id)
        }
        onFinished()
    }

    private func monthText(_ badge: HolographicBadgeStatus) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("M")
        let reference = badge.unlockedAt ?? Date()
        return String(localized: "\(formatter.string(from: reference))月")
    }
}

private struct CardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? MotionTokens.cardPressScale : 1)
            .animation(MotionTokens.cardPressAnimation, value: configuration.isPressed)
    }
}
