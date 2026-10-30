import Foundation
import XCTest
@testable import BioBalance

nonisolated final class AIConfigurationTests: XCTestCase {
    @MainActor func testCloudProvidersAreAllowedByDefault() {
        XCTAssertTrue(AIBuildPolicy.allowsDirectCloudProviders)
        XCTAssertTrue(QwenConfiguration.default.isEnabled)
    }

    @MainActor func testQwenKeyRequiresExternalConfiguration() throws {
        let store = AISecretsStore(
            service: "com.boundesu.BioBalance.ai.tests.\(UUID().uuidString)"
        )

        let names = ["HEALTH_AI_API_KEY", "BIOBALANCE_ALIYUN_AI_API_KEY", "BIOBALANCE_AI_API_KEY"]
        guard !names.contains(where: {
            !(ProcessInfo.processInfo.environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }) else {
            throw XCTSkip("External AI credentials are configured in this test process")
        }
        XCTAssertThrowsError(try store.qwenAPIKey()) { error in
            guard case AIServiceError.missingAPIKey = error else {
                return XCTFail("Expected missingAPIKey")
            }
        }
        XCTAssertFalse(store.hasQwenAPIKey())
    }

    @MainActor func testOlderQwenConfigurationReceivesNewDefaults() throws {
        let suite = "AIConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldPayload: [String: Any] = [
            "isEnabled": true,
            "textEndpoint": "https://example.test/text",
            "textModel": "qwen-old",
            "visionEndpoint": "https://example.test/vision",
            "visionModel": "qwen-vl-old"
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: oldPayload),
            forKey: "ai.provider.qwen.configuration.v2"
        )

        let configuration = AIProviderConfigurationStore(defaults: defaults).qwen

        XCTAssertEqual(configuration.textModel, "qwen-old")
        XCTAssertEqual(configuration.retryPolicy, .default)
    }

    @MainActor func testQwenKeyIsStoredInKeychain() throws {
        let store = AISecretsStore(service: "com.boundesu.BioBalance.ai.tests.\(UUID().uuidString)")
        defer {
            try? store.saveQwenAPIKey(nil)
        }

        try store.saveQwenAPIKey("test-secret")

        XCTAssertEqual(store.storedQwenAPIKey(), "test-secret")
    }
}
