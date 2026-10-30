import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Foundation Models (iOS 26+) 本地文本 Provider。
/// 设备端推理，健康数据不离开设备；当千问不可用时可作为 fallback。
/// 支持 @Generable 结构化输出和流式响应。
nonisolated struct AppleFoundationModelsTextProvider: AIStreamingTextProviding, @unchecked Sendable {
    static let shared = AppleFoundationModelsTextProvider()
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "FoundationModels")
    private static let maximumResponseCharacters = 20_000
    /// 为模型回答预留的 token 数，历史裁剪时从上下文窗口中扣除。
    private static let reservedResponseTokens = 1_024
    /// iOS 26.4 之前无法读取真实上下文窗口时的保守估计值。
    private static let fallbackContextSize = 4_096

    let descriptor = AIProviderDescriptor(
        id: .appleOnDevice,
        displayName: "Apple 本地模型",
        capabilities: [.healthChat, .healthAnalysis],
        isLocal: true
    )

    func isAvailable(for capability: AICapability) -> Bool {
        guard capability == .healthChat || capability == .healthAnalysis else { return false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    // MARK: - 批处理（AITextProviding）

    func generateText(_ request: AITextRequest) async throws -> AITextResponse {
        guard request.capability == .healthChat || request.capability == .healthAnalysis else {
            throw AIServiceError.unsupportedOperation(provider: .appleOnDevice)
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await generateWithFoundationModels(request)
        }
        #endif
        throw AIServiceError.disabledProvider
    }

    // MARK: - 流式调用（AIStreamingTextProviding）

    func streamText(_ request: AITextRequest) async throws -> AsyncThrowingStream<String, Error> {
        guard request.capability == .healthChat || request.capability == .healthAnalysis else {
            throw AIServiceError.unsupportedOperation(provider: .appleOnDevice)
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await streamWithFoundationModels(request)
        }
        #endif
        throw AIServiceError.disabledProvider
    }

    // MARK: - Foundation Models 实现

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateWithFoundationModels(_ request: AITextRequest) async throws -> AITextResponse {
        let (session, prompt) = try await makeSessionWithHistory(request)
        let startedAt = Date()

        // 使用 @Generable 结构化生成（healthChat 能力）。
        if request.capability == .healthChat {
            let response = try await session.respond(
                to: prompt,
                generating: HealthAIGenerableAnswer.self
            )
            let content = response.content.toMarkdown()
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIServiceError.emptyResponse
            }
            Self.logger.info("provider=apple-on-device capability=\(request.capability.rawValue, privacy: .public) mode=generable durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=success")
            return AITextResponse(content: content, providerID: .appleOnDevice, model: "apple-foundation-model")
        }

        // healthAnalysis 等其他能力使用纯文本。
        let response = try await session.respond(to: prompt)
        let content = String(response.content.prefix(Self.maximumResponseCharacters))
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.emptyResponse
        }
        Self.logger.info("provider=apple-on-device capability=\(request.capability.rawValue, privacy: .public) mode=text durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=success")
        return AITextResponse(content: content, providerID: .appleOnDevice, model: "apple-foundation-model")
    }

    @available(iOS 26.0, *)
    private func streamWithFoundationModels(_ request: AITextRequest) async throws -> AsyncThrowingStream<String, Error> {
        let (session, prompt) = try await makeSessionWithHistory(request)
        let startedAt = Date()

        // healthChat 使用 @Generable 结构化流式输出。
        if request.capability == .healthChat {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    let stream = session.streamResponse(
                        to: prompt,
                        generating: HealthAIGenerableAnswer.self
                    )
                    do {
                        for try await partial in stream {
                            try Task.checkCancellation()
                            let snapshot = partial.content.toMarkdownSnapshot()
                            if !snapshot.isEmpty {
                                continuation.yield(snapshot)
                            }
                        }
                        Self.logger.info("provider=apple-on-device capability=\(request.capability.rawValue, privacy: .public) mode=stream-generable durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=success")
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        Self.logger.error("provider=apple-on-device mode=stream-generable status=failed error=\(String(describing: type(of: error)), privacy: .public)")
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }

        // healthAnalysis 使用纯文本流式。
        return AsyncThrowingStream { continuation in
            let task = Task {
                let stream = session.streamResponse(to: prompt)
                do {
                    for try await partial in stream {
                        try Task.checkCancellation()
                        let text = String(partial.content.prefix(Self.maximumResponseCharacters))
                        if !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    Self.logger.info("provider=apple-on-device capability=\(request.capability.rawValue, privacy: .public) mode=stream-text durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) status=success")
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    Self.logger.error("provider=apple-on-device mode=stream-text status=failed error=\(String(describing: type(of: error)), privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - 会话与上下文记录

    /// 构造带历史上下文的会话：历史通过 Transcript 一次性注入，
    /// 不再逐条 respond 重放（重放会对每条历史消息真实推理一次）。
    @available(iOS 26.0, *)
    private func makeSessionWithHistory(_ request: AITextRequest) async throws -> (session: LanguageModelSession, prompt: String) {
        guard SystemLanguageModel.default.isAvailable else {
            throw AIServiceError.disabledProvider
        }

        let instructions = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n")

        let conversationMessages = request.messages.filter { $0.role != .system }
        guard let lastUserMessage = conversationMessages.last(where: { $0.role == .user }) else {
            throw AIServiceError.invalidRequest
        }

        let historyMessages = Array(
            conversationMessages.dropLast(conversationMessages.last?.role == .user ? 1 : 0)
        )
        let trimmedHistory = await trimHistoryToTokenBudget(
            historyMessages,
            instructions: instructions,
            question: lastUserMessage.content
        )

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            transcript: makeTranscript(instructions: instructions, history: trimmedHistory)
        )
        return (session, lastUserMessage.content)
    }

    /// 将 system 指令与历史对话转换为 Foundation Models Transcript。
    @available(iOS 26.0, *)
    private func makeTranscript(instructions: String, history: [AITextMessage]) -> Transcript {
        var entries: [Transcript.Entry] = []
        if !instructions.isEmpty {
            entries.append(.instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: instructions))],
                toolDefinitions: []
            )))
        }
        for message in history {
            let segments: [Transcript.Segment] = [.text(Transcript.TextSegment(content: message.content))]
            switch message.role {
            case .user:
                entries.append(.prompt(Transcript.Prompt(segments: segments)))
            case .assistant:
                entries.append(.response(Transcript.Response(assetIDs: [], segments: segments)))
            case .system:
                break
            }
        }
        return Transcript(entries: entries)
    }

    // MARK: - 令牌预算

    /// 按上下文窗口 token 预算从最新往旧保留历史消息。
    /// iOS 26.4+ 使用真实 contextSize 与 tokenCount；更早版本按字符数保守估算。
    @available(iOS 26.0, *)
    private func trimHistoryToTokenBudget(
        _ history: [AITextMessage],
        instructions: String,
        question: String
    ) async -> [AITextMessage] {
        guard !history.isEmpty else { return history }

        if #available(iOS 26.4, *) {
            do {
                let model = SystemLanguageModel.default
                let instructionTokens = try await model.tokenCount(for: instructions)
                let questionTokens = try await model.tokenCount(for: question)
                var budget = model.contextSize - Self.reservedResponseTokens - instructionTokens - questionTokens
                guard budget > 0 else { return [] }

                var kept: [AITextMessage] = []
                for message in history.reversed() {
                    let cost = try await model.tokenCount(for: message.content)
                    guard budget >= cost else { break }
                    budget -= cost
                    kept.insert(message, at: 0)
                }
                return kept
            } catch {
                Self.logger.error("provider=apple-on-device mode=token-count status=failed error=\(String(describing: type(of: error)), privacy: .public)")
                // token 计数失败时退回字符估算。
            }
        }

        // 字符数估算：中文约 1 字符 1 token，英文会被高估，属于保守方向。
        var budget = Self.fallbackContextSize - Self.reservedResponseTokens - instructions.count - question.count
        guard budget > 0 else { return [] }
        var kept: [AITextMessage] = []
        for message in history.reversed() {
            let cost = message.content.count
            guard budget >= cost else { break }
            budget -= cost
            kept.insert(message, at: 0)
        }
        return kept
    }
    #endif
}
