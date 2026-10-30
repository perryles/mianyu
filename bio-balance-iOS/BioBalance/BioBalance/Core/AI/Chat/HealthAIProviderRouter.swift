import Foundation

/// Provider 选择与 Prompt、UI 分离，后续增加本地模型时不改变健康数据边界。
struct HealthAIProviderDecision: Sendable {
    let providerID: AIProviderID
    let fallbackProviderID: AIProviderID?
    let reason: String
}

/// 今日问答首选千问，千问不可用时回落 Apple Foundation Models 本地推理。
/// 长期档案保留本地确定性 responder，不进入 Provider 路由。
enum HealthAIProviderRouter {
    static func decide(
        for scope: HealthAIScope,
        registry: AIProviderRegistry = .live()
    ) -> HealthAIProviderDecision {
        if case .profile = scope {
            return HealthAIProviderDecision(
                providerID: .deterministic,
                fallbackProviderID: nil,
                reason: "档案解读当前使用本地聚合 responder"
            )
        }

        let qwenAvailable = scope.permitsRemoteRequest
            && registry.textProvider(id: .qwen, capability: .healthChat) != nil
        let localAvailable = registry.textProvider(id: .appleOnDevice, capability: .healthChat) != nil

        if qwenAvailable {
            return HealthAIProviderDecision(
                providerID: .qwen,
                fallbackProviderID: localAvailable ? .appleOnDevice : nil,
                reason: "千问云端可用，Apple 本地模型作为 fallback"
            )
        }
        if localAvailable {
            return HealthAIProviderDecision(
                providerID: .appleOnDevice,
                fallbackProviderID: nil,
                reason: "千问不可用，使用 Apple Foundation Models 本地推理"
            )
        }
        // 千问配置不可用且本地模型不可用时，仍声明千问让 Service 层报出明确错误。
        return HealthAIProviderDecision(
            providerID: .qwen,
            fallbackProviderID: nil,
            reason: "千问是必需 Provider，但当前配置不可用；本地模型也不可用"
        )
    }
}
