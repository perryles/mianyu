import SwiftUI
import UIKit

/// 程序级首次引导 V3。只在最终确认后写入完成标记。
struct AppOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: AppOnboardingStore
    @State private var isFinishing = false
    @State private var isTransitioning = false
    @State private var transitionDirection: OnboardingTransitionDirection = .forward
    @State private var transitionOffset: CGFloat = 1
    @State private var transitionOpacity = 0.0

    private let onComplete: @MainActor () -> Void
    private let evaluateHealthAuthorization: @MainActor () async -> HealthAuthorizationPhase
    private let requestHealthAuthorization: @MainActor () async -> HealthAuthorizationPhase

    init(
        initialStep: AppOnboardingStep = .welcome,
        defaults: UserDefaults = .standard,
        evaluateHealthAuthorization: @escaping @MainActor () async -> HealthAuthorizationPhase = {
            await HealthAuthorizationCoordinator.shared.evaluate()
            return HealthAuthorizationCoordinator.shared.phase
        },
        requestHealthAuthorization: @escaping @MainActor () async -> HealthAuthorizationPhase = {
            await HealthAuthorizationCoordinator.shared.requestAuthorizationIfNeeded()
        },
        onComplete: @escaping @MainActor () -> Void
    ) {
        _store = State(initialValue: AppOnboardingStore(currentStep: initialStep, defaults: defaults))
        self.evaluateHealthAuthorization = evaluateHealthAuthorization
        self.requestHealthAuthorization = requestHealthAuthorization
        self.onComplete = onComplete
    }

    var body: some View {
        rootContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
            .preferredColorScheme(.light)
            .tint(OnboardingV3Palette.brandGreen)
            .task {
                await store.refreshHealthAuthorization(using: evaluateHealthAuthorization)
            }
    }

    private var rootContent: some View {
        ZStack {
            OnboardingV3Palette.pageBackground.ignoresSafeArea()

            stepContent

            OnboardingTransitionWash(
                direction: transitionDirection,
                offsetProgress: transitionOffset,
                opacity: transitionOpacity
            )
            .frame(height: 390)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 46)
        }
        .opacity(isFinishing ? 0 : 1)
        .allowsHitTesting(!isFinishing && !isTransitioning)
    }

    private var footer: some View {
        OnboardingFooter(
            step: store.currentStep,
            isLoading: store.isRequestingAuthorization || isFinishing || isTransitioning,
            healthPhase: store.healthAuthorizationPhase,
            primaryAction: { primaryAction() },
            secondaryAction: healthSecondaryAction
        )
        .opacity(isFinishing ? 0 : 1)
    }

    private var healthSecondaryAction: (() -> Void)? {
        guard store.currentStep == .healthPermission else { return nil }
        return { skipHealthAuthorization() }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch store.currentStep {
        case .welcome:
            OnboardingWelcomeView(step: store.currentStep, goBack: nil)
        case .focus:
            OnboardingFocusView(
                step: store.currentStep,
                selectedFocus: store.selectedFocus,
                selectFocus: { store.selectFocus($0) },
                goBack: { previousStep() }
            )
        case .healthPermission:
            OnboardingHealthPermissionView(
                step: store.currentStep,
                phase: store.healthAuthorizationPhase,
                goBack: { previousStep() }
            )
        case .watch:
            OnboardingWatchView(step: store.currentStep, goBack: { previousStep() })
        case .dailyPreview:
            OnboardingDailyPreviewView(step: store.currentStep, goBack: { previousStep() })
        case .ready:
            OnboardingReadyView(step: store.currentStep, goBack: { previousStep() })
        }
    }

    private func primaryAction() {
        switch store.currentStep {
        case .welcome, .focus, .watch, .dailyPreview:
            transition(to: .forward) { store.next() }
        case .healthPermission:
            if store.healthAuthorizationPhase.canContinueWithoutRequest {
                transition(to: .forward) { store.next() }
            } else {
                Task {
                    let phase = await store.requestHealthAuthorization(using: requestHealthAuthorization)
                    if phase.shouldPlaySuccessHaptic {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
            }
        case .ready:
            completeOnboarding()
        }
    }

    private func skipHealthAuthorization() {
        guard !store.isRequestingAuthorization, !isTransitioning else { return }
        transition(to: .forward) { store.next() }
    }

    private func previousStep() {
        guard store.currentStep != .welcome else { return }
        transition(to: .backward) { store.previous() }
    }

    private func transition(
        to direction: OnboardingTransitionDirection,
        mutation: @escaping @MainActor () -> Void
    ) {
        guard !isTransitioning else { return }
        guard !reduceMotion else {
            mutation()
            return
        }

        isTransitioning = true
        transitionDirection = direction
        transitionOffset = direction.initialOffset
        transitionOpacity = 0

        withAnimation(OnboardingMotion.transitionHalf) {
            transitionOffset = 0
            transitionOpacity = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(OnboardingMotion.transitionHalfDuration))

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mutation()
            }

            withAnimation(OnboardingMotion.transitionHalf) {
                transitionOffset = direction.finalOffset
                transitionOpacity = 0
            }

            try? await Task.sleep(for: .seconds(OnboardingMotion.transitionHalfDuration))
            isTransitioning = false
        }
    }

    private func completeOnboarding() {
        guard !isFinishing else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        isFinishing = true
        store.markCompleted()
        onComplete()
    }
}

#Preview("完整引导") {
    AppOnboardingView(onComplete: {})
}

#Preview("关注重点") {
    AppOnboardingView(initialStep: .focus, onComplete: {})
}

#Preview("健康权限 - 等待系统选择") {
    AppOnboardingView(
        initialStep: .healthPermission,
        evaluateHealthAuthorization: { .promptAvailable },
        requestHealthAuthorization: { .authorizedNoData },
        onComplete: {}
    )
}

#Preview("Apple Watch") {
    AppOnboardingView(initialStep: .watch, onComplete: {})
}

#Preview("今日状态") {
    AppOnboardingView(initialStep: .dailyPreview, onComplete: {})
}

#Preview("开始使用") {
    AppOnboardingView(initialStep: .ready, onComplete: {})
}
