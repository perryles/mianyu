import SwiftUI
import UIKit

struct OnboardingFocusView: View {
    let step: AppOnboardingStep
    let selectedFocus: AppOnboardingFocus
    let selectFocus: (AppOnboardingFocus) -> Void
    let goBack: (() -> Void)?

    var body: some View {
        OnboardingStepScaffold(
            step: step,
            title: String(localized: "先选一个，你最在意的方向"),
            detail: String(localized: "眠屿会据此调整首页的优先展示，不会影响其他健康数据。"),
            goBack: goBack
        ) {
            FocusSelectionHero(selectedFocus: selectedFocus, selectFocus: selectFocus)
        }
    }
}

private struct FocusSelectionHero: View {
    let selectedFocus: AppOnboardingFocus
    let selectFocus: (AppOnboardingFocus) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingHeroSurface {
            VStack(alignment: .leading, spacing: 0) {
                Text("最近，你最想先看懂什么？")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(OnboardingV3Palette.textPrimary)
                Text("选择一个方向，之后也能随时调整")
                    .font(.system(size: 10))
                    .foregroundStyle(OnboardingV3Palette.muted)
                    .padding(.top, 5)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(AppOnboardingFocus.allCases) { focus in
                        Button {
                            guard focus != selectedFocus else { return }
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectFocus(focus)
                        } label: {
                            FocusCard(focus: focus, isSelected: focus == selectedFocus)
                        }
                        .buttonStyle(FocusPressStyle())
                        .accessibilityAddTraits(focus == selectedFocus ? .isSelected : [])
                        .accessibilityLabel(focus.title)
                        .accessibilityValue(focus == selectedFocus ? "已选择" : "未选择")
                        .accessibilityHint(focus.detail)
                    }
                }
                .padding(.top, 18)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
            .background(alignment: .topTrailing) {
                Circle()
                    .fill(Color(hex: "C2F0DE").opacity(0.34))
                    .frame(width: 170, height: 170)
                    .offset(x: 57, y: -66)
            }
        }
    }
}

private struct FocusCard: View {
    let focus: AppOnboardingFocus
    let isSelected: Bool

    private var fill: Color {
        switch focus {
        case .sleep: Color(hex: "EBFAF5")
        case .stress: Color(hex: "F0EDFF")
        case .activity: Color(hex: "EBF2FF")
        case .body: Color(hex: "FFF2DE")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: focus.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? OnboardingV3Palette.brandGreen : OnboardingV3Palette.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(Theme.Colors.surface, in: Circle())
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(OnboardingV3Palette.brandGreen, in: Circle())
                }
            }
            Spacer(minLength: 4)
            Text(focus.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OnboardingV3Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(focus.detail)
                .font(.system(size: 9))
                .foregroundStyle(OnboardingV3Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isSelected ? OnboardingV3Palette.brandGreen : Color(hex: "E8EDF2"),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FocusPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}
