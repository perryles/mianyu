/// 徽章详情页：聚光舞台 + 可拖拽的立体奖章 + 彩带 + 进度/解锁信息。
/// 未解锁时展示进度条与获取条件；已解锁时展示点亮日期。

import SwiftUI
import Combine

struct HolographicBadgeDetailView: View {
    let badgeID: String

    @State private var status: HolographicBadgeStatus?
    @State private var tilt = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                if let status {
                    stage(status)
                    infoSection(status)
                } else {
                    Text("徽章不存在")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(
            LinearGradient(
                colors: [HolographicBadgePalette.canvasTop, HolographicBadgePalette.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .holographicBadgesDidChange).receive(on: RunLoop.main)) { _ in
            reload()
        }
    }

    private var titleText: String {
        guard let status else { return "" }
        return String(localized: String.LocalizationValue(status.definition.titleKey))
    }

    private func reload() {
        status = HolographicBadgeStore.shared.status(for: badgeID)
    }

    // MARK: - 舞台

    private func stage(_ status: HolographicBadgeStatus) -> some View {
        HolographicStageView {
            HolographicMedalView(
                theme: status.definition.theme,
                symbol: status.definition.symbol,
                headerText: status.definition.isMonthly ? monthText(status) : nil,
                tiltX: normalizedTiltX,
                tiltY: normalizedTiltY
            )
            .frame(width: 230, height: 230)
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
                    .onEnded { _ in
                        tilt = .zero
                    }
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tilt)
        }
        .overlay {
            if status.isUnlocked {
                ConfettiOverlay(intensity: 0.9)
            }
        }
    }

    private var normalizedTiltX: CGFloat { tilt.width / 50 }
    private var normalizedTiltY: CGFloat { tilt.height / 50 }

    private func monthText(_ status: HolographicBadgeStatus) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("M")
        let reference = status.unlockedAt ?? Date()
        return String(localized: "\(formatter.string(from: reference))月")
    }

    // MARK: - 信息区

    @ViewBuilder
    private func infoSection(_ status: HolographicBadgeStatus) -> some View {
        VStack(spacing: 14) {
            Text(String(localized: String.LocalizationValue(status.definition.titleKey)))
                .font(.appSystem(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(String(localized: String.LocalizationValue(status.definition.seriesKey)))
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(HolographicBadgePalette.goldText)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(HolographicBadgePalette.surface)
                )
                .overlay(
                    Capsule().stroke(HolographicBadgePalette.surfaceStroke, lineWidth: 1)
                )

            let requirement = String(
                localized: String.LocalizationValue(
                    status.definition.requirementKey.replacingOccurrences(
                        of: "%lld",
                        with: "\(status.definition.requiredDays)"
                    )
                )
            )
            Text(requirement)
                .font(.appSystem(size: 14, weight: .regular))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            progressBar(status)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func progressBar(_ status: HolographicBadgeStatus) -> some View {
        VStack(spacing: 8) {
            if status.isUnlocked {
                if let dateText = status.unlockedDateText() {
                    Text(String(localized: "\(dateText) 点亮"))
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(HolographicBadgePalette.track)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: status.definition.theme.metal.light),
                                        Color(hex: status.definition.theme.highlight)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, proxy.size.width * status.progressFraction))
                    }
                }
                .frame(height: 8)

                Text(String(localized: "已完成 \(status.progressDays)/\(status.definition.requiredDays) 天"))
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(.top, 4)
    }
}
