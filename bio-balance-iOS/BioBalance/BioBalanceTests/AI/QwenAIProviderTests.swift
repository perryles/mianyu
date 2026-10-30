import Foundation
import Synchronization
import XCTest
@testable import BioBalance

nonisolated final class QwenAIProviderTests: XCTestCase {
    @MainActor func testTextRequestUsesBearerAndConfiguredModel() async throws {
        let suite = "QwenAIProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configurationStore = AIProviderConfigurationStore(defaults: defaults)
        var configuration = QwenConfiguration.default
        configuration.textModel = "qwen-test"
        configuration.retryPolicy = AIRetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 1, maximumDelayMilliseconds: 1)
        configurationStore.qwen = configuration

        RequestCaptureURLProtocol.reset()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestCaptureURLProtocol.self]
        let provider = QwenAIProvider(
            configurationStore: configurationStore,
            secretsStore: StubSecretsStore(),
            httpClient: AIHTTPClient(session: URLSession(configuration: sessionConfiguration))
        )

        let response = try await provider.generateText(
            AITextRequest(
                capability: .healthChat,
                messages: [AITextMessage(role: .user, content: "测试问题")]
            )
        )

        XCTAssertEqual(response.content, "测试回答")
        XCTAssertEqual(RequestCaptureURLProtocol.authorization, "Bearer test-key")
        XCTAssertEqual(RequestCaptureURLProtocol.model, "qwen-test")
    }

    @MainActor func testTextRequestForcesAliyunDefaultsWhenStoredConfigurationIsDisabledOrInvalid() async throws {
        let suite = "QwenAIProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configurationStore = AIProviderConfigurationStore(defaults: defaults)
        var configuration = QwenConfiguration.default
        configuration.isEnabled = false
        configuration.textEndpoint = "https://not-dashscope.example.test/v1/chat/completions"
        configuration.textModel = "  "
        configuration.retryPolicy = AIRetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 1, maximumDelayMilliseconds: 1)
        configurationStore.qwen = configuration

        RequestCaptureURLProtocol.reset()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestCaptureURLProtocol.self]
        let provider = QwenAIProvider(
            configurationStore: configurationStore,
            secretsStore: StubSecretsStore(),
            httpClient: AIHTTPClient(session: URLSession(configuration: sessionConfiguration))
        )

        _ = try await provider.generateText(
            AITextRequest(
                capability: .healthChat,
                messages: [AITextMessage(role: .user, content: "测试问题")]
            )
        )

        XCTAssertEqual(RequestCaptureURLProtocol.model, QwenConfiguration.default.textModel)
        XCTAssertEqual(RequestCaptureURLProtocol.requestHost, "dashscope.aliyuncs.com")
        XCTAssertEqual(RequestCaptureURLProtocol.maxTokens, 1_500)
    }

    @MainActor func testMealVisionRequestUsesDirectAliyunDataURLAndVisionContract() async throws {
        let suite = "QwenAIProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configurationStore = AIProviderConfigurationStore(defaults: defaults)
        var configuration = QwenConfiguration.default
        configuration.retryPolicy = AIRetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 1, maximumDelayMilliseconds: 1)
        configurationStore.qwen = configuration
        RequestCaptureURLProtocol.reset(
            responseContent: #"{"status":"recognized","primaryName":"沙拉","confidence":0.91,"foods":[{"name":"沙拉","calories":180,"confidence":0.9}],"warnings":[],"reason":null}"#
        )

        let provider = makeProvider(configurationStore: configurationStore)
        let result = try await provider.analyze(
            AIMealAnalysisRequest(images: [AIMealImageInput(data: Data([0xFF, 0xD8, 0xFF]))])
        )

        XCTAssertEqual(result.provider, .qwen)
        XCTAssertEqual(result.model, "qwen-vl-plus")
        XCTAssertEqual(
            RequestCaptureURLProtocol.requestURL,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        )
        XCTAssertEqual(RequestCaptureURLProtocol.requestHost, "dashscope.aliyuncs.com")
        XCTAssertEqual(RequestCaptureURLProtocol.model, "qwen-vl-plus")
        XCTAssertEqual(RequestCaptureURLProtocol.maxTokens, 2_048)
        XCTAssertEqual(RequestCaptureURLProtocol.responseFormatType, "json_object")
        XCTAssertEqual(RequestCaptureURLProtocol.imageDataURLs.count, 1)
        XCTAssertTrue(RequestCaptureURLProtocol.imageDataURLs.first?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    @MainActor func testDrinkVisionRequestUsesDirectAliyunDataURLAndStrictJSON() async throws {
        let suite = "QwenAIProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configurationStore = AIProviderConfigurationStore(defaults: defaults)
        var configuration = QwenConfiguration.default
        configuration.retryPolicy = AIRetryPolicy(maxAttempts: 1, baseDelayMilliseconds: 1, maximumDelayMilliseconds: 1)
        configurationStore.qwen = configuration
        RequestCaptureURLProtocol.reset(
            responseContent: #"{"status":"recognized","primaryName":"冰美式","storeName":"示例咖啡","confidence":0.94,"candidates":[{"name":"冰美式","confidence":0.94}],"warnings":[],"reason":null}"#
        )

        let provider = makeProvider(configurationStore: configurationStore)
        let result = try await provider.analyzeDrink(
            AIDrinkAnalysisRequest(image: AIMealImageInput(data: Data([0xFF, 0xD8, 0xFF])))
        )

        XCTAssertEqual(result.provider, .qwen)
        XCTAssertEqual(result.model, "qwen-vl-plus")
        XCTAssertEqual(
            RequestCaptureURLProtocol.requestURL,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        )
        XCTAssertEqual(RequestCaptureURLProtocol.requestHost, "dashscope.aliyuncs.com")
        XCTAssertEqual(RequestCaptureURLProtocol.model, "qwen-vl-plus")
        XCTAssertEqual(RequestCaptureURLProtocol.maxTokens, 500)
        XCTAssertEqual(RequestCaptureURLProtocol.responseFormatType, "json_object")
        XCTAssertEqual(RequestCaptureURLProtocol.imageDataURLs.count, 1)
        XCTAssertTrue(RequestCaptureURLProtocol.imageDataURLs.first?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    @MainActor func testMealDecoderRejectsAbstainedAndMarksLowConfidenceForReview() throws {
        let abstained = Data(#"{"status":"abstained","primaryName":null,"confidence":0,"foods":[],"warnings":[],"reason":"图片不清楚"}"#.utf8)
        XCTAssertThrowsError(try AIMealStructuredResponseDecoder.decode(abstained, provider: .qwen, model: "test"))

        let lowConfidence = Data(#"{"status":"recognized","primaryName":"沙拉","confidence":0.5,"foods":[{"name":"沙拉","calories":180,"confidence":0.5}],"warnings":[],"reason":null}"#.utf8)
        let result = try AIMealStructuredResponseDecoder.decode(lowConfidence, provider: .qwen, model: "test")
        XCTAssertTrue(result.requiresReview)
        XCTAssertEqual(result.estimatedCalories, 180)
    }

    @MainActor func testMealDecoderRejectsPartiallyInvalidFoodsAndOutOfRangeConfidence() {
        let invalidFood = Data(#"{"status":"recognized","confidence":0.9,"foods":[{"name":"沙拉","calories":180},{"name":"饮料","calories":-1}]}"#.utf8)
        let invalidConfidence = Data(#"{"status":"recognized","confidence":1.2,"foods":[{"name":"沙拉","calories":180}]}"#.utf8)

        XCTAssertThrowsError(try AIMealStructuredResponseDecoder.decode(invalidFood, provider: .qwen, model: "test"))
        XCTAssertThrowsError(try AIMealStructuredResponseDecoder.decode(invalidConfidence, provider: .qwen, model: "test"))
    }

    @MainActor func testMealDecoderRejectsTooManyFoodsAndFlagsTotalMismatch() throws {
        let foods = (0..<21).map { #"{"name":"食物\#($0)","calories":10}"# }.joined(separator: ",")
        let tooMany = Data(#"{"status":"recognized","confidence":0.9,"foods":[\#(foods)]}"#.utf8)
        XCTAssertThrowsError(try AIMealStructuredResponseDecoder.decode(tooMany, provider: .qwen, model: "test"))

        let mismatch = Data(#"{"status":"recognized","confidence":0.9,"estimatedCalories":999,"foods":[{"name":"沙拉","calories":180}]}"#.utf8)
        let result = try AIMealStructuredResponseDecoder.decode(mismatch, provider: .qwen, model: "test")
        XCTAssertEqual(result.estimatedCalories, 180)
        XCTAssertTrue(result.requiresReview)
    }

    @MainActor func testMealDecoderIgnoresExtraFieldsWhenResponseIsComplete() throws {
        let response = Data(
            #"{"status":"recognized","primaryName":"紫米杂粮饭配蔬菜鸡肉","confidence":0.85,"estimatedCalories":620,"foods":[{"name":"紫米杂粮饭","calories":400,"confidence":0.9},{"name":"炒鸡肉","calories":150,"confidence":0.8},{"name":"蔬菜","calories":60,"confidence":0.75}],"warnings":[],"reason":null,"language":"zh_CN","imageAnalysis":{"mainDish":"紫米杂粮饭"}}"#.utf8
        )

        let result = try AIMealStructuredResponseDecoder.decode(response, provider: .qwen, model: "test")

        XCTAssertEqual(result.primaryName, "紫米杂粮饭配蔬菜鸡肉")
        XCTAssertEqual(result.estimatedCalories, 610)
        XCTAssertTrue(result.requiresReview)
    }

    @MainActor func testMealDecoderRecoversCompletedContractBeforeTruncatedExtraFieldForReview() throws {
        let response = Data(
            #"{"status":"recognized","primaryName":"紫米杂粮饭配蔬菜鸡肉","confidence":0.85,"estimatedCalories":620,"foods":[{"name":"紫米杂粮饭","calories":400,"confidence":0.9},{"name":"炒鸡肉","calories":150,"confidence":0.8},{"name":"蔬菜","calories":60,"confidence":0.75}],"warnings":["份量为视觉估算"],"reason":null,"language":"zh_CN","alternativeInterpretations":{"possibleVariations":["如果包含更多油脂""#.utf8
        )

        let result = try AIMealStructuredResponseDecoder.decode(response, provider: .qwen, model: "test")

        XCTAssertEqual(result.primaryName, "紫米杂粮饭配蔬菜鸡肉")
        XCTAssertEqual(result.estimatedCalories, 610)
        XCTAssertTrue(result.requiresReview)
    }

    @MainActor func testMealDecoderDoesNotRecoverWhenRequiredFoodsAreTruncated() {
        let response = Data(
            #"{"status":"recognized","primaryName":"午餐","confidence":0.85,"foods":[{"name":"米饭","calories":400},{"name":"鸡肉""#.utf8
        )

        XCTAssertThrowsError(try AIMealStructuredResponseDecoder.decode(response, provider: .qwen, model: "test"))
    }

    @MainActor func testMealDecoderAcceptsFencedWrappedJSONAndCommonFieldVariants() throws {
        let response = Data(
            """
            餐食识别结果如下：
            ```json
            {
              "result": {
                "status": "recognized",
                "primary_name": "鸡肉饭",
                "confidence": "0.88",
                "estimated_calories": "420",
                "food_items": [
                  {"food_name": "鸡肉", "estimated_calories": 220.4, "confidence": "0.86"},
                  {"food_name": "米饭", "estimated_calories": "199.6", "confidence": 0.9}
                ],
                "warning": "热量为图片估算"
              }
            }
            ```
            """.utf8
        )

        let result = try AIMealStructuredResponseDecoder.decode(response, provider: .qwen, model: "test")

        XCTAssertEqual(result.primaryName, "鸡肉饭")
        XCTAssertEqual(result.foods.map(\.calories), [220, 200])
        XCTAssertEqual(result.estimatedCalories, 420)
        XCTAssertEqual(result.warnings, ["热量为图片估算"])
        XCTAssertFalse(result.requiresReview)
    }

    @MainActor func testMealDecoderAcceptsUsableFoodsWithoutStatusButRequiresReview() throws {
        let response = Data(
            #"{"meal":{"name":"水果碗","score":"0.92","items":[{"label":"草莓","kcal":"48"},{"label":"酸奶","kcal":120.2}]}}"#.utf8
        )

        let result = try AIMealStructuredResponseDecoder.decode(response, provider: .qwen, model: "test")

        XCTAssertEqual(result.primaryName, "水果碗")
        XCTAssertEqual(result.estimatedCalories, 168)
        XCTAssertTrue(result.requiresReview)
    }

    @MainActor func testMealDecoderNormalizesApproximateCaloriesAndPercentageConfidenceForReview() throws {
        let response = Data(
            #"{"status":"成功","confidence":"86%","foods":[{"name":"沙拉","calories":"约 180 kcal","confidence":85}]}"#.utf8
        )

        let result = try AIMealStructuredResponseDecoder.decode(response, provider: .qwen, model: "test")

        XCTAssertEqual(result.estimatedCalories, 180)
        XCTAssertEqual(result.confidence, 0.86, accuracy: 0.001)
        XCTAssertEqual(result.foods.first?.confidence ?? 0, 0.85, accuracy: 0.001)
        XCTAssertTrue(result.requiresReview)
    }

    @MainActor func testMealDecoderAcceptsChineseFieldsAndFoodMapForReview() throws {
        let response = Data(
            #"{"识别结果":{"状态":"需确认","餐食名称":"家常午餐","总热量":"约 450 千卡","食物列表":{"米饭":"250 kcal","番茄炒蛋":"200 kcal"},"提示":"份量需要确认"}}"#.utf8
        )

        let result = try AIMealStructuredResponseDecoder.decode(response, provider: .qwen, model: "test")

        XCTAssertEqual(Set(result.foods.map(\.name)), Set(["米饭", "番茄炒蛋"]))
        XCTAssertEqual(result.estimatedCalories, 450)
        XCTAssertEqual(result.warnings, ["份量需要确认"])
        XCTAssertTrue(result.requiresReview)
    }

    @MainActor func testMealDecoderStillRejectsNumericValuesWithoutAnyNumber() {
        let response = Data(
            #"{"status":"recognized","foods":[{"name":"沙拉","calories":"无法估算"}]}"#.utf8
        )

        XCTAssertThrowsError(try AIMealStructuredResponseDecoder.decode(response, provider: .qwen, model: "test"))
    }

    @MainActor func testMealInputRejectsUnsafeMimeType() {
        let request = AIMealAnalysisRequest(
            images: [AIMealImageInput(data: Data([1]), mimeType: "image/jpeg;base64,malformed")]
        )

        XCTAssertThrowsError(try request.validateCommonInput()) { error in
            guard case AIMealAnalysisError.unsupportedImageFormat = error else {
                return XCTFail("错误类型不正确：\(error)")
            }
        }
    }

    @MainActor func testMealAnalysisErrorDiagnosticCodes() {
        XCTAssertEqual(AIMealAnalysisError.invalidImageCount.diagnosticCode, "invalid_image_count")
        XCTAssertEqual(AIMealAnalysisError.unsupportedImageFormat.diagnosticCode, "unsupported_image_format")
        XCTAssertEqual(AIMealAnalysisError.imageTooLarge.diagnosticCode, "image_too_large")
        XCTAssertEqual(AIMealAnalysisError.abstained(nil).diagnosticCode, "abstained")
        XCTAssertEqual(AIMealAnalysisError.invalidStructuredResponse.diagnosticCode, "invalid_structured_response")
    }

    @MainActor func testDrinkDecoderRejectsAbstainedInvalidConfidenceAndTooManyCandidates() {
        let abstained = Data(#"{"status":"abstained","primaryName":null,"storeName":null,"confidence":0,"candidates":[],"warnings":[],"reason":"没有看清饮品"}"#.utf8)
        let invalidConfidence = Data(#"{"status":"recognized","primaryName":"咖啡","storeName":null,"confidence":1.1,"candidates":[],"warnings":[],"reason":null}"#.utf8)
        let candidates = (0..<6).map { #"{"name":"候选\#($0)","confidence":0.8}"# }.joined(separator: ",")
        let tooManyCandidates = Data(#"{"status":"recognized","primaryName":"咖啡","storeName":null,"confidence":0.8,"candidates":[\#(candidates)],"warnings":[],"reason":null}"#.utf8)

        XCTAssertThrowsError(try AIDrinkStructuredResponseDecoder.decode(abstained, provider: .qwen, model: "test"))
        XCTAssertThrowsError(try AIDrinkStructuredResponseDecoder.decode(invalidConfidence, provider: .qwen, model: "test"))
        XCTAssertThrowsError(try AIDrinkStructuredResponseDecoder.decode(tooManyCandidates, provider: .qwen, model: "test"))
    }

    @MainActor func testFiveSectionAnswerParser() {
        let markdown = """
        ## 结论
        今天适合稳住节奏。
        ## 依据
        - 睡眠样本不足。
        ## 建议
        - 先补水。
        ## 留意
        - 结合体感观察。
        ## 下一步可问
        - 今晚怎么安排？
        """
        let result = HealthAIAnswerParser().parse(markdown)
        XCTAssertEqual(result.summary, "今天适合稳住节奏。")
        XCTAssertEqual(result.actions, ["先补水。"])
        XCTAssertEqual(result.followUps, ["今晚怎么安排？"])
    }

    @MainActor private func makeProvider(configurationStore: AIProviderConfigurationStore) -> QwenAIProvider {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestCaptureURLProtocol.self]
        return QwenAIProvider(
            configurationStore: configurationStore,
            secretsStore: StubSecretsStore(),
            httpClient: AIHTTPClient(session: URLSession(configuration: sessionConfiguration))
        )
    }
}

private struct StubSecretsStore: AISecretsProviding {
    func qwenAPIKey() throws -> String { "test-key" }
    func hasQwenAPIKey() -> Bool { true }
}

nonisolated private final class RequestCaptureURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var capturedAuthorization: String?
        var capturedModel: String?
        var capturedRequestHost: String?
        var capturedRequestURL: String?
        var capturedMaxTokens: Int?
        var capturedResponseFormatType: String?
        var capturedImageDataURLs: [String] = []
        var stubResponseData = RequestCaptureURLProtocol.makeResponseData(content: "测试回答")
    }
    private static let state = Mutex(State())

    static var authorization: String? { state.withLock { $0.capturedAuthorization } }
    static var model: String? { state.withLock { $0.capturedModel } }
    static var requestHost: String? { state.withLock { $0.capturedRequestHost } }
    static var requestURL: String? { state.withLock { $0.capturedRequestURL } }
    static var maxTokens: Int? { state.withLock { $0.capturedMaxTokens } }
    static var responseFormatType: String? { state.withLock { $0.capturedResponseFormatType } }
    static var imageDataURLs: [String] { state.withLock { $0.capturedImageDataURLs } }

    static func reset(responseContent: String = "测试回答") {
        state.withLock {
            $0 = State()
            $0.stubResponseData = makeResponseData(content: responseContent)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.state.withLock { state in
            state.capturedAuthorization = request.value(forHTTPHeaderField: "Authorization")
            state.capturedRequestHost = request.url?.host
            state.capturedRequestURL = request.url?.absoluteString
            if let data = requestBodyData(),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                state.capturedModel = object["model"] as? String
                state.capturedMaxTokens = object["max_tokens"] as? Int
                state.capturedResponseFormatType = (object["response_format"] as? [String: Any])?["type"] as? String
                state.capturedImageDataURLs = Self.extractImageDataURLs(from: object)
            }
        }
        let data = Self.state.withLock { $0.stubResponseData }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestBodyData() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func extractImageDataURLs(from object: [String: Any]) -> [String] {
        guard let messages = object["messages"] as? [[String: Any]] else { return [] }
        return messages.flatMap { message -> [String] in
            guard let content = message["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { item in
                guard item["type"] as? String == "image_url",
                      let imageURL = item["image_url"] as? [String: Any] else { return nil }
                return imageURL["url"] as? String
            }
        }
    }

    private static func makeResponseData(content: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]]
        ])
    }
}
