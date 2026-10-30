import XCTest
@testable import BioBalance

nonisolated final class AIProviderRoutingTests: XCTestCase {
    @MainActor func testRegistryFiltersByCapabilityAndAvailability() {
        let chat = MockTextProvider(id: .kimi, capabilities: [.healthChat], available: true)
        let unavailable = MockTextProvider(id: .deepSeek, capabilities: [.healthChat], available: false)
        let registry = AIProviderRegistry(textProviders: [chat, unavailable])

        XCTAssertNotNil(registry.textProvider(id: .kimi, capability: .healthChat))
        XCTAssertNil(registry.textProvider(id: .kimi, capability: .healthAnalysis))
        XCTAssertNil(registry.textProvider(id: .deepSeek, capability: .healthChat))
        XCTAssertEqual(registry.availableProviderIDs(for: .healthChat), [.kimi])
    }

    @MainActor func testRouterPreservesConfiguredOrder() {
        let qwen = MockTextProvider(id: .qwen, capabilities: [.healthChat], available: true)
        let local = MockTextProvider(id: .deterministic, capabilities: [.healthChat], available: true)
        let registry = AIProviderRegistry(textProviders: [local, qwen])
        let route = AIProviderRoute(capability: .healthChat, providerIDs: [.qwen, .deterministic])

        let providers = AIProviderRouter(registry: registry).textProviders(for: route)

        XCTAssertEqual(providers.map(\.descriptor.id), [.qwen, .deterministic])
    }

    @MainActor func testPrescriptionStructuringUsesOnlyDeclaredTextCapability() {
        let provider = MockTextProvider(
            id: .qwen,
            capabilities: [.healthChat, .prescriptionStructuring],
            available: true
        )
        let registry = AIProviderRegistry(textProviders: [provider])

        XCTAssertNotNil(registry.textProvider(id: .qwen, capability: .prescriptionStructuring))
        XCTAssertEqual(registry.availableProviderIDs(for: .prescriptionStructuring), [.qwen])
    }

    @MainActor func testRegistryKeepsFirstProviderWhenIDsAreDuplicated() {
        let first = MockTextProvider(id: .qwen, displayName: "first", capabilities: [.healthChat], available: true)
        let second = MockTextProvider(id: .qwen, displayName: "second", capabilities: [.healthChat], available: true)

        let registry = AIProviderRegistry(textProviders: [first, second])

        XCTAssertEqual(
            registry.textProvider(id: .qwen, capability: .healthChat)?.descriptor.displayName,
            "first"
        )
    }

    @MainActor func testCancellationAndClientErrorsDoNotFallback() {
        XCTAssertFalse(AIFailurePolicy.permitsFallback(after: CancellationError()))
        XCTAssertFalse(AIFailurePolicy.permitsFallback(after: AIServiceError.httpError(statusCode: 401, message: nil)))
        XCTAssertFalse(AIFailurePolicy.permitsFallback(after: AIServiceError.httpError(statusCode: 400, message: nil)))
        XCTAssertTrue(AIFailurePolicy.permitsFallback(after: AIServiceError.httpError(statusCode: 429, message: nil)))
        XCTAssertTrue(AIFailurePolicy.permitsFallback(after: AIServiceError.httpError(statusCode: 503, message: nil)))
        XCTAssertFalse(AIFailurePolicy.permitsFallback(after: AIServiceError.invalidRequest))
        XCTAssertFalse(AIFailurePolicy.permitsFallback(after: AIServiceError.responseTooLarge))
    }

    @MainActor func testMealVisionDefaultRouteAlwaysSelectsQwen() async throws {
        let qwen = SuccessfulVisionProvider(id: .qwen)
        let apple = SuccessfulVisionProvider(id: .appleOnDevice)
        let registry = AIProviderRegistry(visionProviders: [apple, qwen])
        let provider = RoutedMealImageAnalysisProvider(registry: registry)

        let result = try await provider.analyze(
            AIMealAnalysisRequest(images: [AIMealImageInput(data: Data([1]))])
        )

        XCTAssertEqual(result.provider, .qwen)
        XCTAssertEqual(qwen.callCount, 1)
        XCTAssertEqual(apple.callCount, 0)
    }

    @MainActor func testDrinkVisionRegistryDoesNotReuseMealProvider() {
        let registry = AIProviderRegistry(visionProviders: [CountingVisionProvider()])

        XCTAssertNil(registry.drinkVisionProvider(id: .qwen))
        XCTAssertTrue(registry.availableProviderIDs(for: .drinkVision).isEmpty)
    }

    @MainActor func testDrinkVisionDefaultRouteAlwaysSelectsQwen() async throws {
        let qwen = CountingDrinkVisionProvider(id: .qwen)
        let kimi = CountingDrinkVisionProvider(id: .kimi)
        let registry = AIProviderRegistry(drinkVisionProviders: [kimi, qwen])
        let provider = RoutedDrinkImageAnalysisProvider(registry: registry)

        let result = try await provider.analyze(
            AIDrinkAnalysisRequest(image: AIMealImageInput(data: Data([1])))
        )

        XCTAssertEqual(result.provider, .qwen)
        XCTAssertEqual(qwen.callCount, 1)
        XCTAssertEqual(kimi.callCount, 0)
    }
}

private struct MockTextProvider: AITextProviding {
    let descriptor: AIProviderDescriptor
    let available: Bool

    init(
        id: AIProviderID,
        displayName: String? = nil,
        capabilities: Set<AICapability>,
        available: Bool
    ) {
        descriptor = AIProviderDescriptor(
            id: id,
            displayName: displayName ?? id.rawValue,
            capabilities: capabilities,
            isLocal: false
        )
        self.available = available
    }

    func isAvailable(for capability: AICapability) -> Bool { available }

    func generateText(_ request: AITextRequest) async throws -> AITextResponse {
        AITextResponse(content: "ok", providerID: descriptor.id, model: "mock")
    }
}

private final class CountingVisionProvider: AIVisionProviding, @unchecked Sendable {
    let descriptor = AIProviderDescriptor(
        id: .qwen,
        displayName: "fallback",
        capabilities: [.mealVision],
        isLocal: false
    )
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int { lock.withLock { calls } }

    func isAvailable(for capability: AICapability) -> Bool { capability == .mealVision }

    func analyze(_ request: AIMealAnalysisRequest) async throws -> AIMealAnalysisResult {
        lock.withLock { calls += 1 }
        throw AIServiceError.emptyResponse
    }
}

private final class SuccessfulVisionProvider: AIVisionProviding, @unchecked Sendable {
    let descriptor: AIProviderDescriptor
    private let lock = NSLock()
    private var calls = 0

    init(id: AIProviderID) {
        descriptor = AIProviderDescriptor(
            id: id,
            displayName: id.rawValue,
            capabilities: [.mealVision],
            isLocal: id == .appleOnDevice
        )
    }

    var callCount: Int { lock.withLock { calls } }

    func isAvailable(for capability: AICapability) -> Bool { capability == .mealVision }

    func analyze(_ request: AIMealAnalysisRequest) async throws -> AIMealAnalysisResult {
        lock.withLock { calls += 1 }
        return AIMealAnalysisResult(
            primaryName: "测试餐食",
            foods: [AIMealFoodEstimate(name: "测试餐食", calories: 100, confidence: 0.9)],
            estimatedCalories: 100,
            confidence: 0.9,
            requiresReview: false,
            warnings: [],
            provider: descriptor.id,
            model: "mock"
        )
    }
}

private final class CountingDrinkVisionProvider: AIDrinkVisionProviding, @unchecked Sendable {
    let descriptor: AIProviderDescriptor
    private let lock = NSLock()
    private var calls = 0

    init(id: AIProviderID) {
        descriptor = AIProviderDescriptor(
            id: id,
            displayName: id.rawValue,
            capabilities: [.drinkVision],
            isLocal: false
        )
    }

    var callCount: Int { lock.withLock { calls } }

    func isAvailable(for capability: AICapability) -> Bool { capability == .drinkVision }

    func analyzeDrink(_ request: AIDrinkAnalysisRequest) async throws -> AIDrinkAnalysisResult {
        lock.withLock { calls += 1 }
        return AIDrinkAnalysisResult(
            primaryName: "测试饮品",
            candidates: [],
            storeName: nil,
            confidence: 0.9,
            requiresReview: false,
            warnings: [],
            provider: descriptor.id,
            model: "mock"
        )
    }
}
