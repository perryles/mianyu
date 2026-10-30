import Foundation

/// 餐食功能的稳定边界。UI 和保存流程只依赖这个协议，不感知 DashScope 或 Core AI。
nonisolated protocol MealImageAnalysisProviding: Sendable {
    func analyze(_ request: AIMealAnalysisRequest) async throws -> AIMealAnalysisResult
}

/// 当前产品要求餐食图片固定直连千问视觉，不读取旧的本地模型优先设置。
nonisolated struct RoutedMealImageAnalysisProvider: MealImageAnalysisProviding {
    let registry: AIProviderRegistry

    init(registry: AIProviderRegistry = .live()) {
        self.registry = registry
    }

    func analyze(_ request: AIMealAnalysisRequest) async throws -> AIMealAnalysisResult {
        try request.validateCommonInput()
        guard let provider = registry.visionProvider(id: .qwen) else {
            throw AIServiceError.disabledProvider
        }
        return try await provider.analyze(request)
    }
}

nonisolated enum MealImageAnalysisProviderFactory {
    /// 若没有可用视觉 Provider，analyze 会返回 disabledProvider，UI 随后进入手动录入。
    static func makeDefault() -> any MealImageAnalysisProviding {
        RoutedMealImageAnalysisProvider()
    }
}
