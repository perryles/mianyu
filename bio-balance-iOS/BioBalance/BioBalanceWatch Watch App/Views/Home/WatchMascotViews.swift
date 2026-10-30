import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct WatchAnimatedMascotView: View {
    let themeId: String
    let hrv: Double
    let stressValue: Int
    let stressState: String?
    let accent: Color
    var accessibilityHintText: String = String(localized: "轻点互动，拖动跟随")
    var longPressActionName: String = String(localized: "打开全部功能")
    var onLongPress: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragTranslation: CGSize = .zero
    @State private var interactionStartedAt: Date?
    @State private var interactionResetTask: Task<Void, Never>?

    private var isHighStress: Bool {
        stressState.map({ ["highStress", "overloaded"].contains($0) }) == true || (hrv > 0 && hrv < 20)
    }

    private var isRecovered: Bool {
        hrv >= 48 || (hrv <= 0 && stressState.map({ ["recovery", "relaxed"].contains($0) }) == true)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: interactionStartedAt == nil ? 0.25 : 1.0 / 30.0)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let interactionElapsed = interactionStartedAt.map { max(0, context.date.timeIntervalSince($0)) }
            let bounce = interactionElapsed.map(WatchMascotInteractionMotion.bounceOffset) ?? 0
            let spin = interactionElapsed.map(WatchMascotInteractionMotion.spinDegrees) ?? 0
            let burst = interactionElapsed.map(WatchMascotInteractionMotion.burstProgress) ?? 1
            let bob = reduceMotion ? 0 : sin(seconds * (isHighStress ? 8.5 : 2.2)) * (isHighStress ? 0.8 : 1.8)
            let tilt = reduceMotion ? 0 : sin(seconds * (isHighStress ? 11 : 1.6)) * (isHighStress ? 2.4 : 1.8)
            let breath = reduceMotion ? 1 : 1 + (sin(seconds * 2.4) * (isRecovered ? 0.025 : 0.018))

            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.62))
                Circle()
                    .stroke(accent.opacity(0.75), lineWidth: 1.2)
                Circle()
                    .fill(accent.opacity(0.18))
                    .padding(3)

                WatchMascotHeroBadge(themeId: themeId, accent: accent)
                    .frame(width: 58, height: 58)
                    .scaleEffect(0.53)

                if isRecovered {
                    Image(systemName: "sparkle")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 11, y: -12)
                        .opacity(reduceMotion ? 0.85 : 0.55 + 0.35 * sin(seconds * 3.4))
                }

                if !reduceMotion, burst < 1 {
                    ForEach(0..<8, id: \.self) { index in
                        let angle = Double(index) * (.pi * 2 / 8)
                        Circle()
                            .fill(index.isMultiple(of: 2) ? accent : .white)
                            .frame(width: 3, height: 3)
                            .offset(
                                x: cos(angle) * 25 * burst,
                                y: sin(angle) * 25 * burst
                            )
                            .opacity(1 - burst)
                    }
                }
            }
            .scaleEffect(breath)
            .rotationEffect(.degrees(tilt + (reduceMotion ? 0 : spin)))
            .offset(
                x: reduceMotion ? 0 : dragTranslation.width * 0.18,
                y: bob + (reduceMotion ? 0 : dragTranslation.height * 0.12) + (reduceMotion ? 0 : bounce)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .gesture(
            LongPressGesture(minimumDuration: 0.45)
                .exclusively(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    guard case let .second(drag) = value, !reduceMotion else { return }
                    dragTranslation = drag.translation
                }
                .onEnded { value in
                    switch value {
                    case .first:
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                            dragTranslation = .zero
                        }
                        onLongPress()
                    case let .second(drag):
                        finishDrag(drag.translation)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前健康伙伴")
        .accessibilityValue(isHighStress ? "紧张提醒" : (isRecovered ? "恢复良好" : "陪伴中"))
        .accessibilityHint(accessibilityHintText)
        .accessibilityAction(.default) { triggerInteraction() }
        .accessibilityAction(named: longPressActionName) { onLongPress() }
        .onDisappear {
            interactionResetTask?.cancel()
            interactionResetTask = nil
        }
    }

    private func finishDrag(_ translation: CGSize) {
        let travel = hypot(translation.width, translation.height)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            dragTranslation = .zero
        }
        guard WatchMascotInteractionMotion.shouldCelebrate(
            travel: travel,
            didLongPress: false,
            reduceMotion: reduceMotion
        ) else { return }
        triggerInteraction()
    }

    private func triggerInteraction() {
        interactionStartedAt = Date()
        interactionResetTask?.cancel()
        interactionResetTask = Task {
            try? await Task.sleep(for: .seconds(WatchMascotInteractionMotion.duration))
            guard !Task.isCancelled else { return }
            await MainActor.run { interactionStartedAt = nil }
        }
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}

private struct WatchMascotHeroBadge: View {
    let themeId: String
    let accent: Color

    private var style: WatchMascotThemeStyle {
        WatchMascotThemeStyle(themeId: themeId)
    }

    var body: some View {
        ZStack {
            if themeId == "tiger" {
                WatchTigerReferenceMascot()
                    .frame(width: 58, height: 58)
                    .offset(x: -3, y: 2)
            } else if themeId == "bearjoy" {
                WatchBearReferenceMascot()
                    .frame(width: 58, height: 58)
            } else if themeId == "bubble" {
                WatchPandaReferenceMascot()
                    .frame(width: 56, height: 56)
            } else {
                WatchMascotMiniPortrait(themeId: themeId)
                    .frame(width: 50, height: 50)

                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 14, height: 14)
                    .offset(x: 16, y: 5)

                Image(systemName: "sparkles")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .offset(x: 23, y: -14)
            }
        }
    }
}

private struct WatchMascotMiniPortrait: View {
    let themeId: String

    private var style: WatchMascotThemeStyle {
        WatchMascotThemeStyle(themeId: themeId)
    }

    var body: some View {
        WatchMascotFace(style: style.style)
    }
}

private struct WatchMascotThemeStyle {
    let background: Color
    let accent: Color
    let style: WatchMascotThemeKind

    init(themeId: String) {
        switch themeId {
        case "bubble":
            background = Color(hex: "EDFFF5")
            accent = Color(hex: "68D4A2")
            style = .bubble
        case "bosscat":
            background = Color(hex: "FFF9E8")
            accent = Color(hex: "FFD85E")
            style = .bossCat
        case "bearjoy":
            background = Color(hex: "FFF5E7")
            accent = Color(hex: "F0C27B")
            style = .bear
        case "flowercat":
            background = Color(hex: "FFF2F7")
            accent = Color(hex: "FF9BC3")
            style = .flowerCat
        case "bunny":
            background = Color(hex: "FFF4FA")
            accent = Color(hex: "F3A6D2")
            style = .bunny
        case "tiger":
            background = Color(hex: "F5F6FF")
            accent = Color(hex: "8F94FF")
            style = .tiger
        case "piggy":
            background = Color(hex: "FFF4F5")
            accent = Color(hex: "FF9FA8")
            style = .pig
        default:
            background = Color(hex: "F0FFF7")
            accent = Color(hex: "63D6A0")
            style = .joey
        }
    }
}

private enum WatchMascotThemeKind {
    case bubble
    case bossCat
    case bear
    case flowerCat
    case bunny
    case tiger
    case pig
    case joey
}

private struct WatchMascotFace: View {
    let style: WatchMascotThemeKind

    var body: some View {
        switch style {
        case .bubble:
            WatchBubbleMascotView()
        case .bossCat:
            WatchBossCatMascotView()
        case .bear:
            WatchBearMascotView()
        case .flowerCat:
            WatchFlowerCatMascotView()
        case .bunny:
            WatchBunnyMascotView()
        case .tiger:
            WatchTigerMascotView()
        case .pig:
            WatchPigMascotView()
        case .joey:
            WatchJoeyMascotView()
        }
    }
}

private struct WatchJoeyMascotView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "63D6A0"))

            Circle()
                .fill(Color.white)
                .frame(width: 26, height: 26)
                .offset(y: 1)

            Circle()
                .fill(Color(hex: "63D6A0"))
                .frame(width: 9, height: 9)
                .offset(x: -10, y: -10)

            Circle()
                .fill(Color(hex: "63D6A0"))
                .frame(width: 9, height: 9)
                .offset(x: 10, y: -10)

            HStack(spacing: 8) {
                Circle().fill(Color.black.opacity(0.82)).frame(width: 3, height: 3)
                Circle().fill(Color.black.opacity(0.82)).frame(width: 3, height: 3)
            }
            .offset(y: -1)

            Capsule()
                .fill(Color(hex: "FF8A7A"))
                .frame(width: 10, height: 5)
                .offset(y: 8)
        }
    }
}

private struct WatchBubbleMascotView: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "68D4A2"))
            Circle().fill(Color.white.opacity(0.22)).frame(width: 8, height: 8).offset(x: 10, y: -6)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.86)).frame(width: 9, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.86)).frame(width: 9, height: 4)
            }
            .offset(y: -3)
            Capsule().fill(Color.black.opacity(0.82)).frame(width: 10, height: 3).offset(y: 8)
        }
    }
}

private struct WatchBossCatMascotView: View {
    var body: some View {
        ZStack {
            WatchCatHeadShape().fill(Color.white)
            WatchCatHeadShape().stroke(Color.black.opacity(0.82), lineWidth: 1.8)
            WatchCrownShape()
                .fill(Color(hex: "FFD85E"))
                .frame(width: 14, height: 8)
                .offset(y: -15)
            HStack(spacing: 7) {
                WatchArcEyeShape().stroke(Color.black.opacity(0.82), lineWidth: 1.8).frame(width: 8, height: 6)
                WatchArcEyeShape().stroke(Color.black.opacity(0.82), lineWidth: 1.8).frame(width: 8, height: 6).scaleEffect(x: -1, y: 1)
            }
            .offset(y: -1)
            Circle().fill(Color(hex: "C7D4F7")).frame(width: 16, height: 10).offset(y: 7)
        }
    }
}

private struct WatchBearMascotView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "E8BD82"))
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.78), lineWidth: 1.6)
            Circle().fill(Color(hex: "F7DAB0")).frame(width: 10, height: 10).offset(x: -10, y: -10)
            Circle().fill(Color(hex: "F7DAB0")).frame(width: 10, height: 10).offset(x: 10, y: -10)
            HStack(spacing: 8) {
                Circle().fill(Color.black.opacity(0.82)).frame(width: 3, height: 3)
                Circle().fill(Color.black.opacity(0.82)).frame(width: 3, height: 3)
            }
            .offset(y: -2)
            Capsule().fill(Color(hex: "F98E68")).frame(width: 10, height: 6).offset(y: 7)
        }
    }
}

private struct WatchFlowerCatMascotView: View {
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(Color(hex: "FFB1C9"))
                    .frame(width: 10, height: 10)
                    .offset(y: -14)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle().fill(Color(hex: "8FD772"))
            WatchCatHeadShape().stroke(Color.black.opacity(0.78), lineWidth: 1.6).padding(6)
            HStack(spacing: 8) {
                Circle().fill(Color.black.opacity(0.82)).frame(width: 3, height: 3)
                Circle().fill(Color.black.opacity(0.82)).frame(width: 3, height: 3)
            }
            .offset(y: -1)
            Capsule().fill(Color.black.opacity(0.82)).frame(width: 8, height: 2).offset(y: 7)
        }
    }
}

private struct WatchBunnyMascotView: View {
    var body: some View {
        ZStack {
            WatchBunnyHeadShape().fill(Color.white)
            WatchBunnyHeadShape().stroke(Color.black.opacity(0.82), lineWidth: 1.7)
            HStack(spacing: 8) {
                WatchArcEyeShape().stroke(Color.black.opacity(0.82), lineWidth: 1.7).frame(width: 8, height: 5)
                WatchArcEyeShape().stroke(Color.black.opacity(0.82), lineWidth: 1.7).frame(width: 8, height: 5).scaleEffect(x: -1, y: 1)
            }
            .offset(y: -1)
            Circle().fill(Color(hex: "FFB5D0")).frame(width: 4, height: 4).offset(y: 6)
        }
    }
}

private struct WatchTigerMascotView: View {
    var body: some View {
        ZStack {
            WatchCatHeadShape().fill(Color.white)
            WatchCatHeadShape().stroke(Color.black.opacity(0.82), lineWidth: 1.8)
            HStack(spacing: 8) {
                Circle().fill(Color.black.opacity(0.88)).frame(width: 3, height: 3)
                Circle().fill(Color.black.opacity(0.88)).frame(width: 3, height: 3)
            }
            .offset(y: -2)
            Capsule().fill(Color.black.opacity(0.88)).frame(width: 9, height: 2.5).offset(y: 6)
            HStack(spacing: 14) {
                Capsule().fill(Color.black.opacity(0.85)).frame(width: 4, height: 9)
                Capsule().fill(Color.black.opacity(0.85)).frame(width: 4, height: 9)
            }
            .offset(y: -11)
        }
    }
}

private struct WatchPigMascotView: View {
    var body: some View {
        ZStack {
            WatchPigHeadShape().fill(Color.white)
            WatchPigHeadShape().stroke(Color.black.opacity(0.82), lineWidth: 1.8)
            HStack(spacing: 8) {
                WatchArcEyeShape().stroke(Color.black.opacity(0.82), lineWidth: 1.7).frame(width: 8, height: 5)
                WatchArcEyeShape().stroke(Color.black.opacity(0.82), lineWidth: 1.7).frame(width: 8, height: 5).scaleEffect(x: -1, y: 1)
            }
            .offset(y: -2)
            Capsule().fill(Color.black.opacity(0.82)).frame(width: 9, height: 2.5).offset(y: 6)
        }
    }
}

private struct WatchTigerReferenceMascot: View {
    var body: some View {
        ZStack {
            WatchCatHeadShape()
                .fill(Color(red: 0.72, green: 0.89, blue: 0.56))
            WatchCatHeadShape()
                .stroke(Color.black, lineWidth: 2.2)

            HStack(spacing: 10) {
                Capsule().fill(Color.black).frame(width: 10, height: 3)
                Capsule().fill(Color.black).frame(width: 10, height: 3)
            }
            .offset(y: -8)

            HStack(spacing: 16) {
                Circle().fill(Color.black).frame(width: 4, height: 4)
                Circle().fill(Color.black).frame(width: 4, height: 4)
            }
            .offset(y: 1)

            Capsule().fill(Color(red: 0.96, green: 0.76, blue: 0.80)).frame(width: 8, height: 6)
                .offset(y: 7)

            VStack(spacing: 8) {
                Capsule().fill(Color.black).frame(width: 3, height: 10)
                Spacer()
            }
            .padding(.top, 7)

            HStack(spacing: 17) {
                VStack(spacing: 6) {
                    Capsule().fill(Color.black).frame(width: 8, height: 2.5)
                    Capsule().fill(Color.black).frame(width: 8, height: 2.5)
                }
                VStack(spacing: 6) {
                    Capsule().fill(Color.black).frame(width: 8, height: 2.5)
                    Capsule().fill(Color.black).frame(width: 8, height: 2.5)
                }
            }
            .offset(y: 5)

            WatchThumbAccent()
                .frame(width: 24, height: 24)
                .offset(x: -24, y: 8)
        }
    }
}

private struct WatchBearReferenceMascot: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.88, green: 0.78, blue: 0.61))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.28, green: 0.25, blue: 0.20), lineWidth: 2.2)

            Circle().fill(Color(red: 0.76, green: 0.66, blue: 0.49)).frame(width: 10, height: 10).offset(x: -21, y: -16)
            Circle().fill(Color(red: 0.76, green: 0.66, blue: 0.49)).frame(width: 10, height: 10).offset(x: 21, y: -16)

            HStack(spacing: 12) {
                WatchArcEyeShape().stroke(Color.black.opacity(0.75), lineWidth: 2).frame(width: 8, height: 5)
                Circle().fill(Color.black.opacity(0.85)).frame(width: 5, height: 5)
            }
            .offset(y: -2)

            HStack(spacing: 16) {
                Circle().fill(Color(red: 0.94, green: 0.61, blue: 0.52)).frame(width: 8, height: 5)
                Circle().fill(Color(red: 0.94, green: 0.61, blue: 0.52)).frame(width: 8, height: 5)
            }
            .offset(y: 10)

            Capsule().fill(Color.black.opacity(0.8)).frame(width: 12, height: 4).offset(x: -1, y: 9)

            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.98, green: 0.92, blue: 0.64))
                .offset(x: -25, y: -10)
        }
    }
}

private struct WatchPandaReferenceMascot: View {
    var body: some View {
        ZStack {
            WatchCatHeadShape()
                .fill(Color.white)
            WatchCatHeadShape()
                .stroke(Color.black, lineWidth: 2.1)

            Circle().fill(Color(red: 0.72, green: 0.73, blue: 0.80)).frame(width: 16, height: 12).offset(x: -12, y: 8)
            Circle().fill(Color(red: 0.72, green: 0.73, blue: 0.80)).frame(width: 16, height: 12).offset(x: 12, y: 8)

            HStack(spacing: 16) {
                Circle().stroke(Color.black, lineWidth: 2).frame(width: 14, height: 14)
                Circle().stroke(Color.black, lineWidth: 2).frame(width: 14, height: 14)
            }
            .offset(y: -4)

            HStack(spacing: 16) {
                Circle().fill(Color.black).frame(width: 4, height: 4)
                Circle().fill(Color.black).frame(width: 4, height: 4)
            }
            .offset(y: -4)

            Capsule().fill(Color.black).frame(width: 8, height: 4).offset(y: 9)
        }
    }
}

private struct WatchThumbAccent: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white)
                .frame(width: 14, height: 22)
                .rotationEffect(.degrees(28))
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .offset(x: -5, y: 5)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.black, lineWidth: 1.8)
                .frame(width: 14, height: 22)
                .rotationEffect(.degrees(28))
            Circle()
                .stroke(Color.black, lineWidth: 1.8)
                .frame(width: 14, height: 14)
                .offset(x: -5, y: 5)
        }
    }
}

nonisolated private struct WatchCatHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.34), control: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.12))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY - rect.height * 0.18), control: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.maxY - rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.20, y: rect.maxY - rect.height * 0.18), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.06))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.34), control: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.maxY - rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.26, y: rect.minY + rect.height * 0.02), control: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.12))
        path.closeSubpath()
        return path
    }
}

nonisolated private struct WatchBunnyHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.22, width: rect.width * 0.64, height: rect.height * 0.58), cornerSize: CGSize(width: rect.width * 0.28, height: rect.height * 0.28))
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.23, y: rect.minY, width: rect.width * 0.18, height: rect.height * 0.34), cornerSize: CGSize(width: rect.width * 0.12, height: rect.height * 0.12))
        path.addRoundedRect(in: CGRect(x: rect.maxX - rect.width * 0.41, y: rect.minY, width: rect.width * 0.18, height: rect.height * 0.34), cornerSize: CGSize(width: rect.width * 0.12, height: rect.height * 0.12))
        return path
    }
}

nonisolated private struct WatchPigHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.14, width: rect.width * 0.80, height: rect.height * 0.72))
    }
}

nonisolated private struct WatchCrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

nonisolated private struct WatchArcEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}
