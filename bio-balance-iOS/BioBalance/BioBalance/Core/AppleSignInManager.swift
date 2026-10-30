import AuthenticationServices
import Foundation

extension Notification.Name {
    static let appleSignInIdentityDidChange = Notification.Name("appleSignInIdentityDidChange")
}

/// Apple 登录管理器 作为核心能力层里的登录服务入口。
/// 负责承接 Apple 登录授权、保存账号标识，并同步登录态变更通知。
@MainActor
final class AppleSignInManager {
    static let shared = AppleSignInManager()

    static let appleUserIdentifierKey = "appleSignInUserIdentifier"
    static let appleEmailKey = "appleSignInEmail"
    static let appleFullNameKey = "appleSignInFullName"
    static let authProviderKey = "authProvider"

    private init() {}

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handle(_ result: Result<ASAuthorization, Error>) throws {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AppleSignInError.invalidCredential
            }
            persist(credential: credential)
        case .failure(let error):
            throw error
        }
    }

    func restorePreviousSignInIfNeeded() async {
        let defaults = UserDefaults.standard
        guard let userIdentifier = defaults.string(forKey: Self.appleUserIdentifierKey),
              !userIdentifier.isEmpty else {
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        let credentialState = await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: userIdentifier) { state, _ in
                continuation.resume(returning: state)
            }
        }

        switch credentialState {
        case .authorized:
            defaults.set(true, forKey: "isLoggedIn")
            defaults.set(false, forKey: "isGuest")
            NotificationCenter.default.post(name: .appleSignInIdentityDidChange, object: nil)
        case .revoked, .notFound:
            signOutLocally()
        default:
            break
        }
    }

    func signOutLocally() {
        clearLocalSession()
        NotificationCenter.default.post(name: .appleSignInIdentityDidChange, object: nil)
    }

    func signOut(completion: (() -> Void)? = nil) {
        // 本地优先：无自建后端，登出仅清理本机会话。
        clearLocalSession()
        NotificationCenter.default.post(name: .appleSignInIdentityDidChange, object: nil)
        completion?()
    }

    func deleteAccount(completion: @escaping (Bool, String?) -> Void) {
        let defaults = UserDefaults.standard
        let isGuest = defaults.bool(forKey: "isGuest")

        if isGuest {
            clearLocalSession()
            NotificationCenter.default.post(name: .appleSignInIdentityDidChange, object: nil)
            completion(true, nil)
            return
        }

        // 本地优先：无自建后端，删除账号仅清理本机会话。
        clearLocalSession()
        NotificationCenter.default.post(name: .appleSignInIdentityDidChange, object: nil)
        completion(true, nil)
    }

    func refreshLocalProfileFromBackend(completion: ((Bool) -> Void)? = nil) {
        // 本地优先：无自建后端，直接按无远端资料处理。
        completion?(false)
    }

    func updateLocalProfile(nickname: String?, username: String?) {
        let defaults = UserDefaults.standard
        let resolvedNickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines)

        UserInfoStore.save(
            nickname: resolvedNickname?.isEmpty == false ? resolvedNickname : nil,
            username: resolvedUsername?.isEmpty == false ? resolvedUsername : nil,
            defaults: defaults
        )
    }

    private func clearLocalSession() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "isLoggedIn")
        defaults.set(false, forKey: "isGuest")
        defaults.removeObject(forKey: Self.appleUserIdentifierKey)
        defaults.removeObject(forKey: Self.appleEmailKey)
        defaults.removeObject(forKey: Self.appleFullNameKey)
        defaults.removeObject(forKey: Self.authProviderKey)
        defaults.removeObject(forKey: "authToken")
        defaults.removeObject(forKey: "purchase_pending")
        UserInfoStore.save(nickname: nil, username: nil, defaults: defaults)
    }

    static func resolveNickname(
        fullName: PersonNameComponents?,
        email: String?,
        existingNickname: String?
    ) -> String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default

        if let fullName {
            let displayName = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
            if !displayName.isEmpty {
                return displayName
            }
        }

        if let existingNickname, !existingNickname.isEmpty {
            return existingNickname
        }

        if let email, !email.isEmpty {
            return email.split(separator: "@").first.map(String.init) ?? email
        }

        return String(localized: "Apple 用户")
    }

    private func persist(credential: ASAuthorizationAppleIDCredential) {
        let defaults = UserDefaults.standard
        let existing = UserInfoStore.load(defaults: defaults)

        let email = credential.email ?? defaults.string(forKey: Self.appleEmailKey) ?? existing.username
        let nickname = Self.resolveNickname(
            fullName: credential.fullName,
            email: email,
            existingNickname: existing.nickname
        )

        defaults.set(credential.user, forKey: Self.appleUserIdentifierKey)
        defaults.set(email, forKey: Self.appleEmailKey)
        defaults.set(nickname, forKey: Self.appleFullNameKey)
        defaults.set("apple", forKey: Self.authProviderKey)
        defaults.set(true, forKey: "isLoggedIn")
        defaults.set(false, forKey: "isGuest")

        UserInfoStore.save(
            nickname: nickname,
            username: email ?? "Apple ID",
            defaults: defaults
        )
        NotificationCenter.default.post(name: .appleSignInIdentityDidChange, object: nil)
    }
}

/// Apple登录In错误枚举 作为核心能力层里的错误状态定义。
/// 负责描述核心业务服务与应用基础能力过程中会用到的状态、分类或分支。
enum AppleSignInError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return String(localized: "Apple 登录凭证无效")
        }
    }
}
