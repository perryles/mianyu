import Foundation
import Security

/// Provider 只依赖取钥匙能力，测试可注入内存实现且不会接触真实 Keychain。
nonisolated protocol AISecretsProviding: Sendable {
    func qwenAPIKey() throws -> String
    func hasQwenAPIKey() -> Bool
}

/// 按环境变量、Keychain 的顺序解析千问 API Key；不提供内置凭据。
nonisolated final class AISecretsStore: @unchecked Sendable {
    static let shared = AISecretsStore()

    private let service: String
    private let qwenAccount = "qwen-api-key"

    init(service: String = "com.boundesu.BioBalance.ai") {
        self.service = service
    }

    func qwenAPIKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        for key in ["HEALTH_AI_API_KEY", "BIOBALANCE_ALIYUN_AI_API_KEY", "BIOBALANCE_AI_API_KEY"] {
            if let value = nonBlankSecret(environment[key]) {
                // 本机 Scheme 注入的开发密钥在首次请求时迁移到 Keychain。
                try? saveQwenAPIKey(value)
                return value
            }
        }
        if let value = keychainValue(account: qwenAccount) {
            return value
        }
        throw AIServiceError.missingAPIKey
    }

    /// 配置页只读取已安全保存的 Keychain 值，不把环境变量回写到界面。
    func storedQwenAPIKey() -> String {
        keychainValue(account: qwenAccount) ?? ""
    }

    func hasQwenAPIKey() -> Bool {
        (try? qwenAPIKey()) != nil
    }

    func saveQwenAPIKey(_ value: String?) throws {
        let trimmed = nonBlankSecret(value)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: qwenAccount
        ]
        guard let trimmed else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AIServiceError.keychainFailure(status: status)
            }
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AIServiceError.keychainFailure(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw AIServiceError.keychainFailure(status: updateStatus)
        }
    }

    private func keychainValue(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return nonBlankSecret(value)
    }
}

extension AISecretsStore: AISecretsProviding {}

nonisolated private func nonBlankSecret(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}
