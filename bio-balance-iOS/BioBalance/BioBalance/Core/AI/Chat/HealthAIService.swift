import Foundation
import OSLog

/// 健康问答 Feature 的稳定入口，统一今日千问调用和长期档案本地解读。
protocol HealthAIServiceProtocol: Sendable {
    func ask(question: String, scope: HealthAIScope, history: [HealthAIChatMessage]) async throws -> HealthAIAnswerPayload
    func askStreaming(question: String, scope: HealthAIScope, history: [HealthAIChatMessage]) -> AsyncThrowingStream<HealthAIStreamingEvent, Error>
}

extension HealthAIServiceProtocol {
    func ask(question: String, context: HealthAIContext, history: [HealthAIChatMessage]) async throws -> HealthAIAnswerPayload {
        try await ask(question: question, scope: .today(context), history: history)
    }
}

/// 编排路由、Prompt、千问请求、fallback、回答解析和来源标记。
struct HealthAIService: HealthAIServiceProtocol {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "HealthAI")

    private let registry: AIProviderRegistry
    private let promptBuilder: HealthAIContextPromptBuilder
    private let answerParser: HealthAIAnswerParser
    private let profileFallbackResponder: HealthAIProfileLocalResponder

    init(
        registry: AIProviderRegistry = .live(),
        promptBuilder: HealthAIContextPromptBuilder = .init(),
        answerParser: HealthAIAnswerParser = .init()
    ) {
        self.registry = registry
        self.promptBuilder = promptBuilder
        self.answerParser = answerParser
        profileFallbackResponder = HealthAIProfileLocalResponder()
    }

    func ask(question: String, scope: HealthAIScope, history: [HealthAIChatMessage]) async throws -> HealthAIAnswerPayload {
        guard let question = promptBuilder.normalizedQuestion(question) else {
            throw AIServiceError.invalidRequest
        }
        let decision = HealthAIProviderRouter.decide(for: scope, registry: registry)

        // 长期档案始终使用本地确定性 responder。
        if case .profile(let profile) = scope {
            return profileFallbackResponder
                .answer(question: question, digest: profile.digest)
                .withSource(.deterministic)
        }

        // 首选 Provider 请求。
        let primaryResult = await attemptProvider(
            id: decision.providerID,
            question: question,
            scope: scope,
            history: history
        )
        switch primaryResult {
        case .success(let payload):
            return payload
        case .failure(let primaryError):
            // 取消不进入 fallback。
            if primaryError is CancellationError { throw primaryError }

            // 尝试 fallback Provider。
            if let fallbackID = decision.fallbackProviderID,
               AIFailurePolicy.permitsFallback(after: primaryError) {
                Self.logger.info("provider=\(decision.providerID.rawValue, privacy: .public) fallback=\(fallbackID.rawValue, privacy: .public) reason=primary-failed")
                let fallbackResult = await attemptProvider(
                    id: fallbackID,
                    question: question,
                    scope: scope,
                    history: history
                )
                switch fallbackResult {
                case .success(let payload):
                    return payload
                case .failure(let fallbackError):
                    if fallbackError is CancellationError { throw fallbackError }
                    if let localAnswer = fitnessLocalAnswer(question: question, scope: scope) {
                        return localAnswer
                    }
                    // fallback 也失败时返回原始错误，更具诊断价值。
                    Self.logger.error("provider=\(fallbackID.rawValue, privacy: .public) status=fallback-failed error=\(String(describing: type(of: fallbackError)), privacy: .public)")
                    throw primaryError
                }
            }
            if let localAnswer = fitnessLocalAnswer(question: question, scope: scope) {
                return localAnswer
            }
            throw primaryError
        }
    }

    // MARK: - 流式调用

    func askStreaming(
        question: String,
        scope: HealthAIScope,
        history: [HealthAIChatMessage]
    ) -> AsyncThrowingStream<HealthAIStreamingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let normalizedQuestion = promptBuilder.normalizedQuestion(question) else {
                        throw AIServiceError.invalidRequest
                    }
                    let decision = HealthAIProviderRouter.decide(for: scope, registry: registry)

                    // 长期档案直接返回本地结果。
                    if case .profile(let profile) = scope {
                        let payload = profileFallbackResponder
                            .answer(question: normalizedQuestion, digest: profile.digest)
                            .withSource(.deterministic)
                        continuation.yield(.completed(payload))
                        continuation.finish()
                        return
                    }

                    let messages = promptBuilder.makeMessages(
                        question: normalizedQuestion,
                        scope: scope,
                        history: history
                    )
                    let request = AITextRequest(capability: .healthChat, messages: messages)

                    // 尝试流式 primary provider。
                    let primaryResult = await streamProvider(
                        id: decision.providerID,
                        request: request,
                        continuation: continuation
                    )
                    if case .success = primaryResult { return }

                    // Primary 失败，尝试 fallback。
                    if case .failure(let primaryError) = primaryResult {
                        if primaryError is CancellationError {
                            continuation.finish(throwing: primaryError)
                            return
                        }
                        if let fallbackID = decision.fallbackProviderID,
                           AIFailurePolicy.permitsFallback(after: primaryError) {
                            Self.logger.info("provider=\(decision.providerID.rawValue, privacy: .public) stream-fallback=\(fallbackID.rawValue, privacy: .public)")
                            let fallbackResult = await streamProvider(
                                id: fallbackID,
                                request: request,
                                continuation: continuation
                            )
                            if case .success = fallbackResult { return }
                            if case .failure(let fallbackError) = fallbackResult {
                                if fallbackError is CancellationError {
                                    continuation.finish(throwing: fallbackError)
                                } else if let localAnswer = fitnessLocalAnswer(question: normalizedQuestion, scope: scope) {
                                    continuation.yield(.completed(localAnswer))
                                    continuation.finish()
                                } else {
                                    continuation.finish(throwing: primaryError)
                                }
                                return
                            }
                        }
                        if let localAnswer = fitnessLocalAnswer(question: normalizedQuestion, scope: scope) {
                            continuation.yield(.completed(localAnswer))
                            continuation.finish()
                            return
                        }
                        continuation.finish(throwing: primaryError)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func fitnessLocalAnswer(question: String, scope: HealthAIScope) -> HealthAIAnswerPayload? {
        guard case .fitness(let context) = scope else { return nil }
        return FitnessAIInsightLocalResponder().answer(question: question, context: context)
    }

    /// 尝试对指定 Provider 执行流式请求；成功时 yield 事件并 finish，失败时返回错误。
    private func streamProvider(
        id: AIProviderID,
        request: AITextRequest,
        continuation: AsyncThrowingStream<HealthAIStreamingEvent, Error>.Continuation
    ) async -> Result<Void, Error> {
        guard let provider = registry.textProvider(id: id, capability: .healthChat) else {
            return .failure(AIServiceError.disabledProvider)
        }

        // 优先使用流式接口。
        if let streamingProvider = provider as? any AIStreamingTextProviding {
            do {
                let stream = try await streamingProvider.streamText(request)
                var lastSnapshot = ""
                for try await snapshot in stream {
                    try Task.checkCancellation()
                    lastSnapshot = snapshot
                    continuation.yield(.textSnapshot(snapshot))
                }
                // 流结束，解析最终回答。
                let payload = answerParser.parse(lastSnapshot).withSource(
                    AIResponseSource(
                        providerID: provider.descriptor.id,
                        displayName: provider.descriptor.displayName,
                        model: "stream",
                        isLocal: provider.descriptor.isLocal
                    )
                )
                continuation.yield(.completed(payload))
                continuation.finish()
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        // 不支持流式，降级为 batch。
        do {
            let response = try await provider.generateText(request)
            let payload = answerParser.parse(response.content).withSource(
                AIResponseSource(
                    providerID: provider.descriptor.id,
                    displayName: provider.descriptor.displayName,
                    model: response.model,
                    isLocal: provider.descriptor.isLocal
                )
            )
            continuation.yield(.textSnapshot(response.content))
            continuation.yield(.completed(payload))
            continuation.finish()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 批处理辅助

    private func attemptProvider(
        id: AIProviderID,
        question: String,
        scope: HealthAIScope,
        history: [HealthAIChatMessage]
    ) async -> Result<HealthAIAnswerPayload, Error> {
        guard let provider = registry.textProvider(id: id, capability: .healthChat) else {
            return .failure(AIServiceError.disabledProvider)
        }
        let startedAt = Date()
        do {
            let response = try await provider.generateText(
                AITextRequest(
                    capability: .healthChat,
                    messages: promptBuilder.makeMessages(question: question, scope: scope, history: history)
                )
            )
            guard response.providerID == provider.descriptor.id else {
                return .failure(AIServiceError.invalidResponse)
            }
            Self.logger.info("provider=\(response.providerID.rawValue, privacy: .public) model=\(response.model, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=success")
            let payload = answerParser.parse(response.content).withSource(
                AIResponseSource(
                    providerID: provider.descriptor.id,
                    displayName: provider.descriptor.displayName,
                    model: response.model,
                    isLocal: provider.descriptor.isLocal
                )
            )
            return .success(payload)
        } catch {
            Self.logger.error("provider=\(id.rawValue, privacy: .public) status=failed durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)")
            return .failure(error)
        }
    }
}
