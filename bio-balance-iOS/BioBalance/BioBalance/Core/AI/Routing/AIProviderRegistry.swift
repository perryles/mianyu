import Foundation

/// Provider 注册中心只负责保存实现、能力过滤和运行时可用性查询。
/// Chat、Meal 等 Feature 决定具体调用顺序。
nonisolated struct AIProviderRegistry: Sendable {
    private let textProviders: [AIProviderID: any AITextProviding]
    private let visionProviders: [AIProviderID: any AIVisionProviding]
    private let drinkVisionProviders: [AIProviderID: any AIDrinkVisionProviding]

    init(
        textProviders: [any AITextProviding] = [],
        visionProviders: [any AIVisionProviding] = [],
        drinkVisionProviders: [any AIDrinkVisionProviding] = []
    ) {
        // 重复 ID 属于注册配置错误；保留首个实现可避免启动时崩溃，并维持调用方给定的优先级。
        self.textProviders = Dictionary(
            textProviders.map { ($0.descriptor.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.visionProviders = Dictionary(
            visionProviders.map { ($0.descriptor.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.drinkVisionProviders = Dictionary(
            drinkVisionProviders.map { ($0.descriptor.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func drinkVisionProvider(id: AIProviderID) -> (any AIDrinkVisionProviding)? {
        guard let provider = drinkVisionProviders[id],
              provider.descriptor.capabilities.contains(.drinkVision),
              provider.isAvailable(for: .drinkVision) else {
            return nil
        }
        return provider
    }

    func textProvider(id: AIProviderID, capability: AICapability) -> (any AITextProviding)? {
        guard let provider = textProviders[id],
              provider.descriptor.capabilities.contains(capability),
              provider.isAvailable(for: capability) else {
            return nil
        }
        return provider
    }

    func visionProvider(id: AIProviderID) -> (any AIVisionProviding)? {
        guard let provider = visionProviders[id],
              provider.descriptor.capabilities.contains(.mealVision),
              provider.isAvailable(for: .mealVision) else {
            return nil
        }
        return provider
    }

    func availableProviderIDs(for capability: AICapability) -> [AIProviderID] {
        let providers: [any AIProvider]
        switch capability {
        case .mealVision:
            providers = visionProviders.values.map { $0 as any AIProvider }
        case .drinkVision:
            providers = drinkVisionProviders.values.map { $0 as any AIProvider }
        case .healthChat, .healthAnalysis, .prescriptionStructuring:
            providers = textProviders.values.map { $0 as any AIProvider }
        }
        return providers
            .filter { $0.descriptor.capabilities.contains(capability) && $0.isAvailable(for: capability) }
            .map(\.descriptor.id)
            .sorted { $0.rawValue < $1.rawValue }
    }

    static func live() -> AIProviderRegistry {
        let qwen = QwenAIProvider.shared
        let foundationModels = AppleFoundationModelsTextProvider.shared
        var visionProviders: [any AIVisionProviding] = [qwen]
        if let apple = AppleCoreAIMealImageAnalysisProvider.registeredProvider {
            visionProviders.append(apple)
        }
        // 长期档案 responder 接收强类型摘要，由 HealthAIService 直接调用，不伪装成通用文本 Provider。
        return AIProviderRegistry(
            textProviders: [qwen, foundationModels],
            visionProviders: visionProviders,
            drinkVisionProviders: [qwen]
        )
    }
}
