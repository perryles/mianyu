import Foundation

nonisolated protocol DrinkImageAnalysisProviding: Sendable {
    func analyze(_ request: AIDrinkAnalysisRequest) async throws -> AIDrinkAnalysisResult
}

/// 饮品识别固定使用千问视觉，不依赖 Mianyu 图片或识别后端。
nonisolated struct RoutedDrinkImageAnalysisProvider: DrinkImageAnalysisProviding {
    let registry: AIProviderRegistry

    init(registry: AIProviderRegistry = .live()) {
        self.registry = registry
    }

    func analyze(_ request: AIDrinkAnalysisRequest) async throws -> AIDrinkAnalysisResult {
        try request.validate()
        guard let provider = registry.drinkVisionProvider(id: .qwen) else {
            throw AIServiceError.disabledProvider
        }
        return try await provider.analyzeDrink(request)
    }
}

nonisolated enum DrinkImageAnalysisProviderFactory {
    static func makeDefault() -> any DrinkImageAnalysisProviding {
        RoutedDrinkImageAnalysisProvider()
    }
}
