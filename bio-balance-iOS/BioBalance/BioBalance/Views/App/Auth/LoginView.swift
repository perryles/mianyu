/// LoginView 由 AppLaunchView 与登录态判断调用，作为「登录」入口页。
/// 负责 Apple 登录、游客试用、协议入口，并管理登录态与游客态切换。

import SwiftUI
import AuthenticationServices
import UIKit

// MARK: - 登录页配色（static let 只解析一次 hex，避免 body 重求值时重复创建 Scanner）
private enum LoginPalette {
    // PEN-2 P0-3/P0-1：文字对比度提到 ≥4.5:1，并补深色模式变体。
    static let background = Color(light: "F4F4F2", dark: "17181A")
    static let subtitle = Color(light: "5F6F7C", dark: "C3CDD6")
    static let brandTop = Color(light: "5B6571", dark: "B7C0CA")
    static let brandBottom = Color(light: "343A42", dark: "7E8892")
    static let appleButton = Color(hex: "343838")
    static let guestText = Color(light: "4E5964", dark: "C9D1D8")
    static let guestBorder = Color(light: "D8DCDE", dark: "3A3A3C")
    static let legalText = Color(light: "66706C", dark: "B9C2CC")
    static let legalLink = Color(light: "2F6496", dark: "6FA8DC")
}

struct LoginView: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("isGuest") private var isGuest: Bool = false
    @AppStorage("purchase_pending") private var purchasePending: Bool = false
    @AppStorage("userNickname") private var userNickname: String = ""
    @AppStorage("userUsername") private var userUsername: String = ""

    @State private var isAppleSigningIn = false
    @State private var errorMessage = ""
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    @State private var appleAuthorization = AppleAuthorizationCoordinator()

    var body: some View {
        ZStack {
            Color(LoginPalette.background)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: adaptiveLayout.prefersTwoPaneLayout ? 20 : 8)

                        AdaptiveHeroLayout(spacing: adaptiveLayout.usesExpandedLayout ? 36 : 6, verticalAlignment: .center) {
                            mascotHero
                        } trailing: {
                            loginContent
                        }
                        .padding(.horizontal, adaptiveLayout.prefersTwoPaneLayout ? 56 : 0)

                        Spacer(minLength: adaptiveLayout.prefersTwoPaneLayout ? 20 : 8)
                    }
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingTermsOfService) {
            NavigationStack {
                TermsOfServiceView()
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
    }

    private var mascotHero: some View {
        GeometryReader { proxy in
            let size = min(
                proxy.size.width * (adaptiveLayout.prefersTwoPaneLayout ? 0.88 : 0.72),
                adaptiveLayout.prefersTwoPaneLayout ? 430 : 280
            )

            LoginMascot()
                .frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: adaptiveLayout.prefersTwoPaneLayout ? 460 : 280)
        .allowsHitTesting(false)
    }

    private var loginContent: some View {
        VStack(spacing: adaptiveLayout.prefersTwoPaneLayout ? 24 : 12) {
            VStack(spacing: adaptiveLayout.prefersTwoPaneLayout ? 16 : 7) {
                Text(purchasePending ? LocalizedStringKey("登录后继续完成解锁") : LocalizedStringKey("每天，更了解自己的状态"))
                    .font(.appSystem(size: adaptiveLayout.prefersTwoPaneLayout ? 26 : 21, weight: .black, design: .rounded))
                    .foregroundColor(LoginPalette.subtitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text("眠屿")
                    .font(.appSystem(size: adaptiveLayout.prefersTwoPaneLayout ? 58 : 46, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [LoginPalette.brandTop, LoginPalette.brandBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }

            VStack(spacing: 10) {
                appleLoginButton
                guestLoginButton
            }

            if !errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundColor(Theme.Colors.accentRed)

                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentRed)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            }

            legalAgreementLine
        }
        .frame(maxWidth: adaptiveLayout.prefersTwoPaneLayout ? 430 : .infinity)
        .padding(.horizontal, adaptiveLayout.prefersTwoPaneLayout ? 28 : 24)
    }

    private var appleLoginButton: some View {
        Button(action: startAppleLogin) {
            ZStack {
                Capsule()
                    .fill(LoginPalette.appleButton)

                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.appSystem(size: adaptiveLayout.prefersTwoPaneLayout ? 25 : 22, weight: .black))
                    Text("使用 Apple 账号登录")
                        .font(.appSystem(size: adaptiveLayout.prefersTwoPaneLayout ? 20 : 18, weight: .black, design: .rounded))
                }
                .foregroundColor(.white)
                .opacity(isAppleSigningIn ? 0 : 1)

                if isAppleSigningIn {
                    ProgressView()
                        .tint(Theme.Colors.onAccent)
                }
            }
            .frame(height: adaptiveLayout.prefersTwoPaneLayout ? 74 : 58)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isAppleSigningIn)
        .accessibilityLabel("使用 Apple 账号登录")
    }

    private var guestLoginButton: some View {
        Button(action: enterGuestMode) {
            HStack(spacing: 9) {
                Image(systemName: "person.crop.circle")
                    .font(.appSystem(size: adaptiveLayout.prefersTwoPaneLayout ? 20 : 18, weight: .bold))

                Text("游客进入")
                    .font(.appSystem(size: adaptiveLayout.prefersTwoPaneLayout ? 17 : 16, weight: .black, design: .rounded))
            }
            .foregroundColor(LoginPalette.guestText)
            .frame(maxWidth: .infinity)
            .frame(height: adaptiveLayout.prefersTwoPaneLayout ? 58 : 48)
            .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(LoginPalette.guestBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isAppleSigningIn)
        .accessibilityLabel("以游客身份进入")
    }

    private var legalAgreementLine: some View {
        HStack(spacing: 4) {
            Text("继续即表示你已阅读并同意")
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(LoginPalette.legalText)

            legalButton(title: "隐私政策") {
                showingPrivacyPolicy = true
            }

            Text("和")
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(LoginPalette.legalText)

            legalButton(title: "用户协议") {
                showingTermsOfService = true
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .padding(.top, 2)
    }

    private func legalButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(LoginPalette.legalLink)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private func startAppleLogin() {
        isAppleSigningIn = true
        errorMessage = ""
        appleAuthorization.start { result in
            handleAppleLogin(result)
        }
    }

    private func handleAppleLogin(_ result: Result<ASAuthorization, Error>) {
        isAppleSigningIn = true
        errorMessage = ""

        do {
            try AppleSignInManager.shared.handle(result)
            AppleSignInManager.shared.refreshLocalProfileFromBackend { _ in
                let info = UserInfoStore.load()
                userNickname = info.nickname ?? ""
                userUsername = info.username ?? ""
                isLoggedIn = true
                isGuest = false
                isAppleSigningIn = false
                Task { await SubscriptionManager.shared.refreshEntitlement() }
            }
        } catch {
            isAppleSigningIn = false
            // 用户主动取消登录时静默处理，不显示任何错误文字
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                errorMessage = ""
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func enterGuestMode() {
        errorMessage = ""
        isLoggedIn = false
        isGuest = true
        userNickname = "游客"
        userUsername = ""
        purchasePending = false
        Task { await SubscriptionManager.shared.refreshEntitlement() }
    }
}

#Preview {
    LoginView()
}

struct LoginMascot: View {
    var body: some View {
        Image("ProfileHeaderMascot")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("眠屿 吉祥物")
    }
}

@Observable
private final class AppleAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @ObservationIgnored private var completion: ((Result<ASAuthorization, Error>) -> Void)?
    @ObservationIgnored private var authorizationController: ASAuthorizationController?

    func start(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        authorizationController = controller
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        finish(with: .success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(with: .failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeWindow = scenes
            .flatMap(\.windows)
            .first { $0.isKeyWindow }

        return activeWindow ?? ASPresentationAnchor()
    }

    private func finish(with result: Result<ASAuthorization, Error>) {
        let completion = completion
        self.completion = nil
        authorizationController = nil

        DispatchQueue.main.async {
            completion?(result)
        }
    }
}
