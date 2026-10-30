import Foundation
import SwiftUI
import StoreKit
import UIKit

/// Subscription管理器 作为视图模型层里的服务或调度入口。
/// 负责连接界面与底层数据源，处理状态管理、业务计算和用户操作响应。
@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    /// Entitlement Resolution 结构体，作为内部辅助类型，用于配合外层界面状态管理与业务编排。
    nonisolated struct EntitlementResolution: Equatable {
        let isPro: Bool
        let isLifetime: Bool
        let expiresAtSeconds: Double
    }
    
    @ObservationIgnored @AppStorage("isPro") private var storedIsPro: Bool = false
    @ObservationIgnored @AppStorage("debug_force_pro_unlocked") private var debugForceProUnlocked: Bool = false

    @ObservationIgnored @AppStorage("pro_is_lifetime") private var proIsLifetime: Bool = false
    @ObservationIgnored @AppStorage("pro_expires_at") private var proExpiresAt: Double = 0
    @ObservationIgnored @AppStorage("storekit_entitlement_owner_provider") private var storekitEntitlementOwnerProvider: String = ""
    @ObservationIgnored @AppStorage("storekit_entitlement_owner_identifier") private var storekitEntitlementOwnerIdentifier: String = ""
    @ObservationIgnored @AppStorage("storekit_entitlement_owner_email") private var storekitEntitlementOwnerEmail: String = ""
    @ObservationIgnored @AppStorage("simulated_storekit_last_sku") private var simulatedStoreKitLastSKU: String = ""
    @ObservationIgnored @AppStorage("simulated_storekit_expires_at") private var simulatedStoreKitExpiresAt: Double = 0
    @ObservationIgnored @AppStorage("simulated_storekit_is_lifetime") private var simulatedStoreKitIsLifetime: Bool = false

    var isRefreshing: Bool = false
    var isPurchasing: Bool = false
    var lastError: String = ""
    private(set) var productsById: [String: Product] = [:]
    private(set) var productsBySKU: [MembershipSKU: Product] = [:]
    private(set) var usesSimulatedStoreKit: Bool = false
    
    /// Membership SKU 枚举，作为内部辅助类型，用于细分外层界面状态管理与业务编排中的状态或分支。
    enum MembershipSKU: String, CaseIterable {
        case yearly = "pro_yearly"
        case monthly = "pro_monthly"
        case lifetime = "pro_lifetime"

        var candidateProductIDs: [String] {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.boundesu.BioBalance"
            let bundleLowercased = bundleID.lowercased()
            return [
                rawValue,
                "\(bundleID).\(rawValue)",
                "\(bundleLowercased).\(rawValue)",
                "com.boundesu.BioBalance.\(rawValue)",
                "com.boundesu.biobalance.\(rawValue)",
                "com.boundesu.BalenWatch.\(rawValue)",
                "com.boundesu.balenwatch.\(rawValue)"
            ]
        }
    }

    /// Pay Channel 枚举，作为内部辅助类型，用于细分外层界面状态管理与业务编排中的状态或分支。
    enum PayChannel: String, CaseIterable {
        case appleIap = "apple_iap"

        var title: String {
            switch self {
            case .appleIap: "Apple"
            }
        }
    }
    
    /// Entitlement Feature 枚举，作为内部辅助类型，用于细分外层界面状态管理与业务编排中的状态或分支。
    enum EntitlementFeature: Hashable {
        case pro
    }
    
    private var transactionUpdatesTask: Task<Void, Never>?
    private var foregroundTask: Task<Void, Never>?
    private var identityTask: Task<Void, Never>?
    private var didLoadProducts: Bool = false

    private struct AppleIdentity: Equatable {
        let provider: String
        let userIdentifier: String
        let email: String
    }

    // 当前阶段先全量开放原本的会员能力，保留底层订阅状态字段，后续恢复收费时只需切回原判断。
    var isPro: Bool {
        true
    }

    var isDebugForceProUnlocked: Bool {
        debugForceProUnlocked
    }
    
    private init() {
        Task { await refreshEntitlement() }
        Task { await loadProducts() }
        transactionUpdatesTask = Task { await listenForTransactions() }
        foregroundTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                await self?.refreshEntitlement()
            }
        }
        identityTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .appleSignInIdentityDidChange) {
                await self?.refreshEntitlement()
            }
        }
    }
    
    func hasEntitlement(_ feature: EntitlementFeature) -> Bool {
        switch feature {
        case .pro:
            return isPro
        }
    }

    func setDebugForceProUnlocked(_ enabled: Bool) {
        debugForceProUnlocked = enabled
    }
    
    func refreshEntitlement() async {
        isRefreshing = true
        lastError = ""
        if productsBySKU.isEmpty {
            await loadProducts()
        }
        if usesSimulatedStoreKit {
            applySimulatedEntitlementIfNeeded()
            isRefreshing = false
            return
        }
        await updateEntitlementsFromCurrentTransactions()
        isRefreshing = false
    }

    func purchase(sku: MembershipSKU, payChannel: PayChannel = .appleIap) async -> Bool {
        isPurchasing = true
        lastError = ""

        if !didLoadProducts {
            await loadProducts()
        }

        guard payChannel == .appleIap else {
            isPurchasing = false
            lastError = "当前版本仅支持 Apple 订阅"
            return false
        }

        if usesSimulatedStoreKit {
            let purchased = simulatePurchase(for: sku)
            if purchased {
                await applyDebugUnlockIfNeededForTestEnvironment()
            }
            isPurchasing = false
            return purchased
        }

        if productsBySKU[sku] == nil {
            await loadProducts(forceReload: true)
        }

        guard let product = productsBySKU[sku] else {
            isPurchasing = false
            lastError = missingProductMessage(for: [sku])
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateEntitlement(from: transaction)
                await transaction.finish()
                if isPro {
                    await applyDebugUnlockIfNeededForTestEnvironment()
                }
                isPurchasing = false
                return isPro
            case .userCancelled:
                isPurchasing = false
                return false
            case .pending:
                isPurchasing = false
                lastError = "购买待处理"
                return false
            @unknown default:
                isPurchasing = false
                lastError = "购买失败"
                return false
            }
        } catch {
            isPurchasing = false
            lastError = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async -> Bool {
        isPurchasing = true
        lastError = ""

        if usesSimulatedStoreKit {
            applySimulatedEntitlementIfNeeded()
            isPurchasing = false
            if !isPro {
                lastError = "当前还没有可恢复的测试购买记录"
            }
            return isPro
        }

        await updateEntitlementsFromCurrentTransactions()

        if isPro {
            isPurchasing = false
            return true
        }

        do {
            try await AppStore.sync()
        } catch {
            isPurchasing = false
            lastError = error.localizedDescription
            return false
        }

        await updateEntitlementsFromCurrentTransactions()
        isPurchasing = false
        return isPro
    }

    func loadProducts(forceReload: Bool = false) async {
        if !forceReload, didLoadProducts, !productsBySKU.isEmpty { return }
        lastError = ""
        do {
            let ids = Array(Set(MembershipSKU.allCases.flatMap(\.candidateProductIDs)))
            let products = try await Product.products(for: ids)
            var mapped: [String: Product] = [:]
            var bySKU: [MembershipSKU: Product] = [:]
            for p in products {
                mapped[p.id] = p
                if let sku = Self.resolveSKU(for: p.id) {
                    bySKU[sku] = p
                }
            }
            productsById = mapped
            productsBySKU = bySKU
            usesSimulatedStoreKit = false
            didLoadProducts = !products.isEmpty
            if products.isEmpty {
                #if targetEnvironment(simulator)
                enableSimulatedStoreKit(reason: "模拟器未读取到本地 StoreKit 商品，已自动切换到测试购买模式。")
                #else
                lastError = missingProductMessage(for: MembershipSKU.allCases)
                #endif
            } else {
                let missingSKUs = MembershipSKU.allCases.filter { bySKU[$0] == nil }
                if !missingSKUs.isEmpty {
                    lastError = missingProductMessage(for: missingSKUs)
                }
            }
        } catch {
            #if targetEnvironment(simulator)
            enableSimulatedStoreKit(reason: "模拟器当前未连接可用的 StoreKit 商品，已自动切换到测试购买模式。")
            #else
            lastError = error.localizedDescription
            #endif
        }
    }

    private func missingProductMessage(for skus: [MembershipSKU]) -> String {
        let ids = skus.map(\.rawValue).joined(separator: "、")
        return String(localized: "没有读取到商品信息：\(ids)。请确认 App Store Connect 中商品已补齐元数据和审核截图，并已挂到当前 App 版本后再用 TestFlight 真机测试。")
    }

    func displayPrice(for sku: MembershipSKU) -> String? {
        productsBySKU[sku]?.displayPrice ?? simulatedDisplayPrice(for: sku)
    }

    private func listenForTransactions() async {
        for await result in StoreKit.Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            await updateEntitlement(from: transaction)
            await transaction.finish()
        }
    }

    private func updateEntitlementsFromCurrentTransactions() async {
        if let currentIdentity = currentAppleIdentity,
           !canCurrentIdentityUseLocalEntitlement(currentIdentity) {
            clearVisibleEntitlementState()
            lastError = ""
            return
        }

        var hasActivePro = false
        var hasLifetime = false
        var latestExpirySeconds: Double = 0

        for await result in StoreKit.Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }

            guard let sku = Self.resolveSKU(for: transaction.productID) else { continue }

            if sku == .lifetime {
                hasLifetime = true
                hasActivePro = true
                continue
            }

            if let expirationDate = transaction.expirationDate {
                let expirySeconds = expirationDate.timeIntervalSince1970
                latestExpirySeconds = max(latestExpirySeconds, expirySeconds)
                if expirationDate > Date() {
                    hasActivePro = true
                }
            }
        }

        if (hasLifetime || hasActivePro), let currentIdentity = currentAppleIdentity {
            persistEntitlementOwner(currentIdentity)
        }
        proIsLifetime = hasLifetime
        proExpiresAt = latestExpirySeconds
        storedIsPro = hasLifetime || hasActivePro
    }

    private func updateEntitlement(from transaction: StoreKit.Transaction) async {
        guard transaction.revocationDate == nil else {
            await updateEntitlementsFromCurrentTransactions()
            return
        }

        let resolvedSKU = Self.resolveSKU(for: transaction.productID)

        if resolvedSKU == .lifetime {
            proIsLifetime = true
            storedIsPro = true
        } else if let expirationDate = transaction.expirationDate {
            proExpiresAt = max(proExpiresAt, expirationDate.timeIntervalSince1970)
            storedIsPro = expirationDate > Date()
        } else {
            storedIsPro = true
        }

        persistCurrentAppleIdentityAsEntitlementOwner()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private var currentAppleIdentity: AppleIdentity? {
        let defaults = UserDefaults.standard
        let isLoggedIn = defaults.bool(forKey: "isLoggedIn")
        let isGuest = defaults.bool(forKey: "isGuest")
        let authProvider = (defaults.string(forKey: AppleSignInManager.authProviderKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let userIdentifier = (defaults.string(forKey: AppleSignInManager.appleUserIdentifierKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (defaults.string(forKey: AppleSignInManager.appleEmailKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard isLoggedIn, !isGuest, authProvider == "apple", !userIdentifier.isEmpty else {
            return nil
        }

        return AppleIdentity(
            provider: authProvider,
            userIdentifier: userIdentifier,
            email: email.lowercased()
        )
    }

    private func canCurrentIdentityUseLocalEntitlement(_ currentIdentity: AppleIdentity) -> Bool {
        guard !storekitEntitlementOwnerIdentifier.isEmpty else { return true }
        guard storekitEntitlementOwnerProvider == currentIdentity.provider else { return false }
        guard storekitEntitlementOwnerIdentifier == currentIdentity.userIdentifier else { return false }
        if storekitEntitlementOwnerEmail.isEmpty || currentIdentity.email.isEmpty {
            return true
        }
        return storekitEntitlementOwnerEmail == currentIdentity.email
    }

    private func persistCurrentAppleIdentityAsEntitlementOwner() {
        guard let currentIdentity = currentAppleIdentity else { return }
        persistEntitlementOwner(currentIdentity)
    }

    private func persistEntitlementOwner(_ identity: AppleIdentity) {
        storekitEntitlementOwnerProvider = identity.provider
        storekitEntitlementOwnerIdentifier = identity.userIdentifier
        storekitEntitlementOwnerEmail = identity.email
    }

    private func clearVisibleEntitlementState() {
        proIsLifetime = false
        proExpiresAt = 0
        storedIsPro = false
    }

    private func enableSimulatedStoreKit(reason: String) {
        usesSimulatedStoreKit = true
        didLoadProducts = true
        lastError = reason
        applySimulatedEntitlementIfNeeded()
    }

    private func applySimulatedEntitlementIfNeeded() {
        guard usesSimulatedStoreKit else { return }

        if let currentIdentity = currentAppleIdentity,
           !canCurrentIdentityUseLocalEntitlement(currentIdentity) {
            clearVisibleEntitlementState()
            return
        }

        if simulatedStoreKitIsLifetime {
            proIsLifetime = true
            proExpiresAt = 0
            storedIsPro = true
            return
        }

        let expiry = simulatedStoreKitExpiresAt
        let hasActiveExpiry = expiry > Date().timeIntervalSince1970
        proIsLifetime = false
        proExpiresAt = hasActiveExpiry ? expiry : 0
        storedIsPro = hasActiveExpiry
    }

    private func simulatePurchase(for sku: MembershipSKU) -> Bool {
        switch sku {
        case .lifetime:
            simulatedStoreKitIsLifetime = true
            simulatedStoreKitExpiresAt = 0
        case .monthly:
            simulatedStoreKitIsLifetime = false
            simulatedStoreKitExpiresAt = Date().addingTimeInterval(30 * 24 * 60 * 60).timeIntervalSince1970
        case .yearly:
            simulatedStoreKitIsLifetime = false
            simulatedStoreKitExpiresAt = Date().addingTimeInterval(365 * 24 * 60 * 60).timeIntervalSince1970
        }

        simulatedStoreKitLastSKU = sku.rawValue
        persistCurrentAppleIdentityAsEntitlementOwner()
        applySimulatedEntitlementIfNeeded()
        lastError = ""
        return isPro
    }

    private func applyDebugUnlockIfNeededForTestEnvironment() async {
        guard await isTestPurchaseEnvironment() else { return }
        debugForceProUnlocked = true
    }

    private func isTestPurchaseEnvironment() async -> Bool {
        if usesSimulatedStoreKit {
            return true
        }

        #if DEBUG
        return true
        #else
        guard let appTransactionResult = try? await AppTransaction.shared else {
            return false
        }
        guard let appTransaction = try? checkVerified(appTransactionResult) else {
            return false
        }
        let environment = String(describing: appTransaction.environment).lowercased()
        return environment.contains("sandbox") || environment.contains("xcode")
        #endif
    }

    private func simulatedDisplayPrice(for sku: MembershipSKU) -> String? {
        switch sku {
        case .yearly:
            return "¥198.00"
        case .monthly:
            return "¥28.00"
        case .lifetime:
            return "¥398.00"
        }
    }

    private static func resolveSKU(for productID: String) -> MembershipSKU? {
        MembershipSKU.allCases.first { sku in
            sku.candidateProductIDs.contains(productID) || productID.hasSuffix(".\(sku.rawValue)")
        }
    }

    nonisolated static func resolveEntitlement(
        _ dto: MembershipEntitlementDTO,
        now: Date = Date()
    ) -> EntitlementResolution {
        let isLifetime = dto.lifetime ?? false
        let expiryRaw = Double(dto.expires_at ?? 0)
        let expiresAtSeconds = expiryRaw > 10_000_000_000 ? (expiryRaw / 1000) : expiryRaw
        let hasActiveExpiry = expiresAtSeconds > now.timeIntervalSince1970
        let isPro = isLifetime || (dto.pro ?? false) || hasActiveExpiry

        return EntitlementResolution(
            isPro: isPro,
            isLifetime: isLifetime,
            expiresAtSeconds: expiresAtSeconds
        )
    }
}
