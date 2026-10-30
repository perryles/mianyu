import Foundation

/// 今日健康问答和餐食识别默认允许使用已配置的云端 Provider。
/// Provider 仍需通过启用状态、HTTPS Endpoint 和有效 API Key 三项运行时检查。
nonisolated enum AIBuildPolicy {
    static var allowsDirectCloudProviders: Bool {
        true
    }
}

/// 千问文本与视觉使用独立配置，避免把文本模型误用于图片请求。
nonisolated struct QwenConfiguration: Codable, Sendable, Equatable {
    var isEnabled: Bool
    var textEndpoint: String
    var textModel: String
    var visionEndpoint: String
    var visionModel: String
    var retryPolicy: AIRetryPolicy

    init(
        isEnabled: Bool,
        textEndpoint: String,
        textModel: String,
        visionEndpoint: String,
        visionModel: String,
        retryPolicy: AIRetryPolicy
    ) {
        self.isEnabled = isEnabled
        self.textEndpoint = textEndpoint
        self.textModel = textModel
        self.visionEndpoint = visionEndpoint
        self.visionModel = visionModel
        self.retryPolicy = retryPolicy
    }

    /// 旧配置可能缺少 retryPolicy；缺失时填入默认值保证平滑升级。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled
        textEndpoint = try container.decodeIfPresent(String.self, forKey: .textEndpoint) ?? Self.default.textEndpoint
        textModel = try container.decodeIfPresent(String.self, forKey: .textModel) ?? Self.default.textModel
        visionEndpoint = try container.decodeIfPresent(String.self, forKey: .visionEndpoint) ?? Self.default.visionEndpoint
        visionModel = try container.decodeIfPresent(String.self, forKey: .visionModel) ?? Self.default.visionModel
        retryPolicy = try container.decodeIfPresent(AIRetryPolicy.self, forKey: .retryPolicy) ?? Self.default.retryPolicy
    }

    static let `default` = QwenConfiguration(
        isEnabled: true,
        textEndpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        textModel: "qwen-plus",
        visionEndpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        visionModel: "qwen-vl-plus",
        retryPolicy: .default
    )
}

/// 保存不敏感的 Provider 配置；用户覆盖的 API Key 由 AISecretsStore 写入 Keychain。
nonisolated final class AIProviderConfigurationStore: @unchecked Sendable {
    static let shared = AIProviderConfigurationStore()

    private let defaults: UserDefaults
    private let key = "ai.provider.qwen.configuration.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var qwen: QwenConfiguration {
        get {
            guard let data = defaults.data(forKey: key),
                  let value = try? JSONDecoder().decode(QwenConfiguration.self, from: data) else {
                return .default
            }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }

    /// 恢复默认值时只清理非敏感配置；API Key 由 AISecretsStore 单独管理。
    func resetQwenConfiguration() {
        defaults.removeObject(forKey: key)
    }
}
