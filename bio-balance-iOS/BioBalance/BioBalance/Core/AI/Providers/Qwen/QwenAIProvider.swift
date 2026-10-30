import Foundation
import OSLog

/// DashScope OpenAI-compatible 接口适配器，同时实现健康文本和餐食视觉能力。
/// 请求 DTO、配置和日志均停留在 Provider 边界内，业务层不依赖供应商字段。
nonisolated final class QwenAIProvider: AIStreamingTextProviding, AIVisionProviding, AIDrinkVisionProviding, @unchecked Sendable {
    static let shared = QwenAIProvider()
    private static let dashScopeHost = "dashscope.aliyuncs.com"
    private static let maximumTextResponseCharacters = 20_000
    private static let maximumMealVisionOutputTokens = 2_048

    let descriptor = AIProviderDescriptor(
        id: .qwen,
        displayName: "阿里云千问",
        capabilities: [.healthChat, .healthAnalysis, .prescriptionStructuring, .mealVision, .drinkVision],
        isLocal: false
    )

    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "QwenAI")
    private let configurationStore: AIProviderConfigurationStore
    private let secretsStore: any AISecretsProviding
    private let httpClient: AIHTTPClient

    init(
        configurationStore: AIProviderConfigurationStore = .shared,
        secretsStore: any AISecretsProviding = AISecretsStore.shared,
        httpClient: AIHTTPClient = AIHTTPClient()
    ) {
        self.configurationStore = configurationStore
        self.secretsStore = secretsStore
        self.httpClient = httpClient
    }

    func isAvailable(for capability: AICapability) -> Bool {
        let configuration = effectiveConfiguration
        guard AIBuildPolicy.allowsDirectCloudProviders,
              secretsStore.hasQwenAPIKey() else { return false }
        switch capability {
        case .healthChat, .healthAnalysis, .prescriptionStructuring:
            return dashScopeURL(configuration.textEndpoint) != nil && !configuration.textModel.isBlank
        case .mealVision, .drinkVision:
            return dashScopeURL(configuration.visionEndpoint) != nil && !configuration.visionModel.isBlank
        }
    }

    func generateText(_ request: AITextRequest) async throws -> AITextResponse {
        guard isAvailable(for: request.capability) else {
            throw AIServiceError.disabledProvider
        }
        let configuration = effectiveConfiguration
        guard let url = dashScopeURL(configuration.textEndpoint) else {
            throw AIServiceError.invalidURL
        }
        let apiKey = try secretsStore.qwenAPIKey()
        let body = QwenTextRequest(
            model: configuration.textModel,
            messages: request.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: request.capability == .prescriptionStructuring ? 0.1 : 0.4,
            maxTokens: 1_500,
            stream: false
        )
        let urlRequest = try makeRequest(url: url, apiKey: apiKey, body: body, timeout: 30)
        let startedAt = Date()

        do {
            let response: QwenChatResponse = try await httpClient.send(
                urlRequest,
                retryPolicy: configuration.retryPolicy
            )
            guard let content = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw AIServiceError.emptyResponse
            }
            guard content.count <= Self.maximumTextResponseCharacters else {
                throw AIServiceError.responseTooLarge
            }
            Self.logger.info("provider=qwen capability=\(request.capability.rawValue, privacy: .public) model=\(configuration.textModel, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=success")
            return AITextResponse(content: content, providerID: .qwen, model: configuration.textModel)
        } catch {
            Self.logger.error("provider=qwen capability=\(request.capability.rawValue, privacy: .public) model=\(configuration.textModel, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=\(Self.statusCode(from: error), privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)")
            throw error
        }
    }

    func streamText(_ request: AITextRequest) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable(for: request.capability) else {
            throw AIServiceError.disabledProvider
        }
        let configuration = effectiveConfiguration
        guard let url = dashScopeURL(configuration.textEndpoint) else {
            throw AIServiceError.invalidURL
        }
        let apiKey = try secretsStore.qwenAPIKey()
        let body = QwenTextRequest(
            model: configuration.textModel,
            messages: request.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: request.capability == .prescriptionStructuring ? 0.1 : 0.4,
            maxTokens: 1_500,
            stream: true
        )
        let urlRequest = try makeRequest(url: url, apiKey: apiKey, body: body, timeout: 60)
        let startedAt = Date()

        Self.logger.info("provider=qwen capability=\(request.capability.rawValue, privacy: .public) model=\(configuration.textModel, privacy: .public) mode=stream status=started")
        let stream = try await httpClient.streamSSE(urlRequest)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastSnapshot = ""
                do {
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        lastSnapshot = snapshot
                        continuation.yield(snapshot)
                    }
                    // 验证最终内容。
                    guard !lastSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continuation.finish(throwing: AIServiceError.emptyResponse)
                        return
                    }
                    guard lastSnapshot.count <= Self.maximumTextResponseCharacters else {
                        continuation.finish(throwing: AIServiceError.responseTooLarge)
                        return
                    }
                    Self.logger.info("provider=qwen capability=\(request.capability.rawValue, privacy: .public) model=\(configuration.textModel, privacy: .public) mode=stream durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=success")
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    Self.logger.error("provider=qwen mode=stream status=failed durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func analyze(_ request: AIMealAnalysisRequest) async throws -> AIMealAnalysisResult {
        guard isAvailable(for: .mealVision) else {
            throw AIServiceError.disabledProvider
        }
        try request.validateCommonInput()
        // 限制单图与总量，避免 Base64 放大后形成不可控请求。
        let maximumImageBytes = 5 * 1_024 * 1_024
        let maximumTotalBytes = 20 * 1_024 * 1_024
        guard request.images.allSatisfy({ $0.data.count <= maximumImageBytes }),
              request.images.reduce(0, { $0 + $1.data.count }) <= maximumTotalBytes else {
            throw AIMealAnalysisError.imageTooLarge
        }

        let configuration = effectiveConfiguration
        guard let url = dashScopeURL(configuration.visionEndpoint) else {
            throw AIServiceError.invalidURL
        }
        let apiKey = try secretsStore.qwenAPIKey()
        var userContent = request.images.map {
            QwenVisionContent.imageURL("data:\($0.normalizedMimeType);base64,\($0.data.base64EncodedString())")
        }
        let note = request.note?
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .prefix(500)
        let localeIdentifier = String(request.localeIdentifier.prefix(80))
        userContent.append(
            .text(
                "请识别这些图片中的同一餐食并估算各项热量。拍摄时间：\(ISO8601DateFormatter().string(from: request.capturedAt))；语言：\(localeIdentifier)；用户说明：\(note.map(String.init) ?? "无补充说明")。"
            )
        )

        let body = QwenVisionRequest(
            model: configuration.visionModel,
            messages: [
                .init(role: "system", content: [.text(Self.mealSystemPrompt)]),
                .init(role: "user", content: userContent)
            ],
            temperature: 0.1,
            maxTokens: Self.maximumMealVisionOutputTokens,
            stream: false,
            responseFormat: .init(type: "json_object")
        )
        let urlRequest = try makeRequest(url: url, apiKey: apiKey, body: body, timeout: 60)
        let startedAt = Date()

        do {
            let response: QwenChatResponse = try await httpClient.send(
                urlRequest,
                retryPolicy: configuration.retryPolicy
            )
            guard let content = response.choices.first?.message.content,
                  let data = content.data(using: .utf8) else {
                throw AIMealAnalysisError.invalidStructuredResponse
            }
            // 识别响应包含用户饮食内容，禁止打印原文；结构化解码失败只记录错误类型。
            let result: AIMealAnalysisResult
            do {
                result = try AIMealStructuredResponseDecoder.decode(
                    data,
                    provider: .qwen,
                    model: configuration.visionModel
                )
            } catch {
                Self.logger.error("provider=qwen capability=mealVision stage=decode errorType=\(String(describing: type(of: error)), privacy: .public)")
                throw error
            }
            Self.logger.info("provider=qwen capability=mealVision model=\(configuration.visionModel, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=success")
            return result
        } catch {
            Self.logger.error("provider=qwen capability=mealVision model=\(configuration.visionModel, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=\(Self.statusCode(from: error), privacy: .public) error=\(Self.diagnosticCode(from: error), privacy: .public) errorType=\(String(describing: type(of: error)), privacy: .public)")
            throw error
        }
    }

    func analyzeDrink(_ request: AIDrinkAnalysisRequest) async throws -> AIDrinkAnalysisResult {
        guard isAvailable(for: .drinkVision) else {
            throw AIServiceError.disabledProvider
        }
        try request.validate()
        let maximumImageBytes = 5 * 1_024 * 1_024
        guard request.image.data.count <= maximumImageBytes else {
            throw AIMealAnalysisError.imageTooLarge
        }

        let configuration = effectiveConfiguration
        guard let url = dashScopeURL(configuration.visionEndpoint) else {
            throw AIServiceError.invalidURL
        }
        let apiKey = try secretsStore.qwenAPIKey()
        let localeIdentifier = String(request.localeIdentifier.prefix(80))
        let imageURL = "data:\(request.image.normalizedMimeType);base64,\(request.image.data.base64EncodedString())"
        let body = QwenVisionRequest(
            model: configuration.visionModel,
            messages: [
                .init(role: "system", content: [.text(Self.drinkSystemPrompt)]),
                .init(
                    role: "user",
                    content: [
                        .imageURL(imageURL),
                        .text("识别这张饮品照片。语言：\(localeIdentifier)。店名只有在包装或画面文字清晰可见时才能填写。")
                    ]
                )
            ],
            temperature: 0.1,
            maxTokens: 500,
            stream: false,
            responseFormat: .init(type: "json_object")
        )
        let urlRequest = try makeRequest(url: url, apiKey: apiKey, body: body, timeout: 60)
        let startedAt = Date()

        do {
            let response: QwenChatResponse = try await httpClient.send(
                urlRequest,
                retryPolicy: configuration.retryPolicy
            )
            guard let content = response.choices.first?.message.content,
                  let data = content.data(using: .utf8) else {
                throw AIMealAnalysisError.invalidStructuredResponse
            }
            let result = try AIDrinkStructuredResponseDecoder.decode(
                data,
                provider: .qwen,
                model: configuration.visionModel
            )
            Self.logger.info("provider=qwen capability=drinkVision model=\(configuration.visionModel, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=success")
            return result
        } catch {
            Self.logger.error("provider=qwen capability=drinkVision model=\(configuration.visionModel, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=\(Self.statusCode(from: error), privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)")
            throw error
        }
    }

    func testTextConnection() async throws {
        _ = try await generateText(
            AITextRequest(
                capability: .healthChat,
                messages: [
                    AITextMessage(role: .system, content: "只回答 OK。"),
                    AITextMessage(role: .user, content: "连接测试")
                ]
            )
        )
    }

    /// 云端强制模式不能被旧 UserDefaults 关闭；损坏字段恢复为阿里云默认配置。
    private var effectiveConfiguration: QwenConfiguration {
        var configuration = configurationStore.qwen
        let defaults = QwenConfiguration.default
        configuration.isEnabled = true
        if dashScopeURL(configuration.textEndpoint) == nil {
            configuration.textEndpoint = defaults.textEndpoint
        }
        if configuration.textModel.isBlank {
            configuration.textModel = defaults.textModel
        }
        if dashScopeURL(configuration.visionEndpoint) == nil {
            configuration.visionEndpoint = defaults.visionEndpoint
        }
        if configuration.visionModel.isBlank {
            configuration.visionModel = defaults.visionModel
        }
        return configuration
    }

    private func dashScopeURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == Self.dashScopeHost,
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        return url
    }

    private func makeRequest<Body: Encodable>(
        url: URL,
        apiKey: String,
        body: Body,
        timeout: TimeInterval
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func statusCode(from error: Error) -> String {
        guard let serviceError = error as? AIServiceError,
              case .httpError(let statusCode, _) = serviceError else {
            return "failed"
        }
        return String(statusCode)
    }

    private static func diagnosticCode(from error: Error) -> String {
        if let mealError = error as? AIMealAnalysisError {
            return mealError.diagnosticCode
        }
        return String(describing: type(of: error))
    }

    private static let mealSystemPrompt = """
    你是餐食图片识别助手。只根据用户提供的图片和说明返回估算，不做医疗诊断。
    如果图片不是餐食、内容不清楚或无法合理估算，status 必须返回 abstained，foods 必须为空。
    status 只允许 recognized、needs_review、abstained 三种值；需要用户重点核对时返回 needs_review。
    禁止为了填满字段而猜测不存在的食物。所有热量都是估算值，foods 最多 20 项。
    输出必须是单个 JSON 对象，不能包含 Markdown、代码围栏或额外解释。
    JSON 字段：status、primaryName、confidence、estimatedCalories、foods、warnings、reason。
    foods 每项字段：name、calories、confidence、estimatedAmount、unit、proteinGrams、carbohydrateGrams、fatGrams、fiberGrams。
    confidence 范围为 0 到 1，calories 为非负整数。图片无法可靠判断份量或营养素时对应字段返回 null，不要制造小数精度；unit 仅使用 g、ml、份、个、碗、片、杯。
    根对象只能包含上述 7 个字段，foods 每项只能包含上述 9 个字段；禁止添加 language、captureTime、imageAnalysis、additionalInfo、recommendations、metadata 或任何其他扩展字段。
    reason 必须是根对象最后一个字段；写完 reason 后立即用 } 结束 JSON，不要继续输出分析过程或补充信息。
    calories 和 estimatedCalories 只能填写单个整数，不要带 kcal、千卡、“约”或区间；不确定性写入 warnings。
    示例：{"status":"needs_review","primaryName":"鸡肉饭","confidence":0.72,"estimatedCalories":520,"foods":[{"name":"鸡肉","calories":220,"confidence":0.7,"estimatedAmount":120,"unit":"g","proteinGrams":32,"carbohydrateGrams":0,"fatGrams":5,"fiberGrams":0},{"name":"米饭","calories":300,"confidence":0.75,"estimatedAmount":230,"unit":"g","proteinGrams":6,"carbohydrateGrams":66,"fatGrams":1,"fiberGrams":2}],"warnings":["份量仅根据图片估算"],"reason":null}
    """

    private static let drinkSystemPrompt = """
    你是饮品照片识别助手。只根据图片中可见内容识别饮品，不推断用户位置，不做健康诊断。
    如果图片不是饮品、内容不清楚或无法合理识别，status 必须返回 abstained。
    status 只允许 recognized、needs_review、abstained。置信度不足或候选相近时返回 needs_review。
    primaryName 是饮品名称；storeName 只有在杯身、包装或招牌文字清晰可见时填写，否则必须为 null。
    candidates 最多 5 项，每项只包含 name 和 confidence。warnings 最多 5 条。
    输出必须是单个 JSON 对象，不能包含 Markdown、代码围栏或额外解释。
    JSON 字段：status、primaryName、storeName、confidence、candidates、warnings、reason。
    confidence 范围为 0 到 1。
    """
}

nonisolated private struct QwenTextRequest: Encodable, Sendable {
    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

nonisolated private struct QwenVisionRequest: Encodable, Sendable {
    struct Message: Encodable, Sendable {
        let role: String
        let content: [QwenVisionContent]
    }

    struct ResponseFormat: Encodable, Sendable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

nonisolated private enum QwenVisionContent: Encodable, Sendable {
    case text(String)
    case imageURL(String)

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    struct ImageURL: Encodable, Sendable {
        let url: String
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .imageURL(let value):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURL(url: value), forKey: .imageURL)
        }
    }
}

nonisolated private struct QwenChatResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

nonisolated private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
