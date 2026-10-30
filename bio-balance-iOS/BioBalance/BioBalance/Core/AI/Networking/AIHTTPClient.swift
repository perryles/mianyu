import Foundation
import Security

/// 网络 Provider 共用的配置、传输、响应和安全存储错误。
nonisolated enum AIServiceError: LocalizedError, Sendable {
    case missingAPIKey
    case disabledProvider
    case invalidRequest
    case invalidURL
    case invalidResponse
    case responseTooLarge
    case httpError(statusCode: Int, message: String?)
    case decodingFailed
    case emptyResponse
    case keychainFailure(status: OSStatus)
    case unsupportedOperation(provider: AIProviderID)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return String(localized: "AI API Key 尚未配置。")
        case .disabledProvider:
            return String(localized: "AI Provider 当前未启用。")
        case .invalidRequest:
            return String(localized: "请输入有效的问题后再试。")
        case .invalidURL:
            return String(localized: "AI 服务地址无效。")
        case .invalidResponse:
            return String(localized: "AI 服务返回了无效响应。")
        case .responseTooLarge:
            return String(localized: "AI 服务返回的数据过大，请稍后重试。")
        case .httpError(let statusCode, let message):
            return message ?? "AI 请求失败，状态码 \(statusCode)。"
        case .decodingFailed:
            return String(localized: "AI 响应解析失败。")
        case .emptyResponse:
            return String(localized: "AI 服务没有返回有效内容。")
        case .keychainFailure:
            return String(localized: "AI API Key 无法安全保存，请稍后重试。")
        case .unsupportedOperation(let provider):
            return String(localized: "\(provider.rawValue) 不支持当前 AI 操作。")
        }
    }
}

/// 控制单次 HTTP 请求的总尝试次数和指数退避上限。
nonisolated struct AIRetryPolicy: Codable, Sendable, Equatable {
    let maxAttempts: Int
    let baseDelayMilliseconds: UInt64
    let maximumDelayMilliseconds: UInt64

    static let `default` = AIRetryPolicy(
        maxAttempts: 3,
        baseDelayMilliseconds: 400,
        maximumDelayMilliseconds: 2_000
    )
}

/// AI Provider 共用的 HTTP 执行器，统一处理状态码、解码和瞬时故障重试。
actor AIHTTPClient {
    /// 防止损坏或手工修改的持久化配置触发无界网络请求。
    private static let maximumAttempts = 10
    static let defaultMaximumResponseBytes = 2 * 1_024 * 1_024

    private let session: URLSession
    private let maximumResponseBytes: Int

    init(
        session: URLSession = .shared,
        maximumResponseBytes: Int = AIHTTPClient.defaultMaximumResponseBytes
    ) {
        self.session = session
        self.maximumResponseBytes = max(1, maximumResponseBytes)
    }

    func send<Response: Decodable & Sendable>(
        _ request: URLRequest,
        retryPolicy: AIRetryPolicy = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> Response {
        let data = try await sendData(request, retryPolicy: retryPolicy)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AIServiceError.decodingFailed
        }
    }

    func sendData(
        _ request: URLRequest,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> Data {
        let attempts = min(Self.maximumAttempts, max(1, retryPolicy.maxAttempts))
        var lastError: Error = AIServiceError.invalidResponse

        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await receiveData(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIServiceError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    let error = AIServiceError.httpError(
                        statusCode: httpResponse.statusCode,
                        message: Self.errorMessage(from: data)
                    )
                    guard Self.isRetryable(statusCode: httpResponse.statusCode), attempt + 1 < attempts else {
                        throw error
                    }
                    lastError = error
                    try await wait(beforeAttempt: attempt + 1, policy: retryPolicy)
                    continue
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard Self.isRetryable(error: error), attempt + 1 < attempts else {
                    throw error
                }
                lastError = error
                try await wait(beforeAttempt: attempt + 1, policy: retryPolicy)
            }
        }
        throw lastError
    }

    /// SSE 流式请求：返回 DashScope 兼容的增量文本快照 AsyncThrowingStream。
    /// 每次 yield 的 String 是到当前为止的完整累积内容（snapshot 模式）。
    func streamSSE(_ request: URLRequest) async throws -> AsyncThrowingStream<String, Error> {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            // 非成功状态时收集错误信息
            var errorData = Data()
            for try await byte in bytes {
                guard errorData.count < 4_096 else { break }
                errorData.append(byte)
            }
            throw AIServiceError.httpError(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: errorData)
            )
        }
        let maximumResponseBytes = maximumResponseBytes
        return AsyncThrowingStream { continuation in
            let task = Task {
                var accumulated = ""
                var accumulatedBytes = 0
                // 按字节缓冲整行，行结束后再整体 UTF-8 解码；
                // 逐字节转 Character 会把多字节字符（中文等）拆成乱码。
                var lineBuffer = Data()

                // 处理一行 SSE 数据；返回 true 表示收到 [DONE]，流应结束。
                func handleLine(_ rawLine: Data) throws -> Bool {
                    var lineData = rawLine
                    if lineData.last == 0x0D {
                        lineData.removeLast()
                    }
                    let line = String(decoding: lineData, as: UTF8.self)
                    guard line.hasPrefix("data:") else { return false }
                    // SSE 规范中 data: 后的空格可选，payload 是 JSON，两侧去白安全。
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { return true }
                    if let delta = Self.extractDeltaContent(from: payload) {
                        accumulatedBytes += delta.utf8.count
                        guard accumulatedBytes <= maximumResponseBytes else {
                            throw AIServiceError.responseTooLarge
                        }
                        accumulated += delta
                        continuation.yield(accumulated)
                    }
                    return false
                }

                do {
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        // 0x0A（\n）不会出现在 UTF-8 多字节序列内部，按字节切行是安全的。
                        if byte == 0x0A {
                            let lineData = lineBuffer
                            lineBuffer.removeAll(keepingCapacity: true)
                            if try handleLine(lineData) {
                                continuation.finish()
                                return
                            }
                        } else {
                            guard lineBuffer.count < maximumResponseBytes else {
                                throw AIServiceError.responseTooLarge
                            }
                            lineBuffer.append(byte)
                        }
                    }
                    // 服务端末尾未追加换行就关闭连接时，仍需处理残留的最后一行。
                    if !lineBuffer.isEmpty {
                        _ = try handleLine(lineBuffer)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 从 SSE JSON 行中提取 choices[0].delta.content 增量文本。
    private static func extractDeltaContent(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }

    /// 使用异步字节流在下载过程中执行上限，避免先把异常响应完整载入内存。
    private func receiveData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        let expectedLength = response.expectedContentLength
        guard expectedLength < 0 || expectedLength <= Int64(maximumResponseBytes) else {
            throw AIServiceError.responseTooLarge
        }

        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(Int(expectedLength))
        }
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else {
                throw AIServiceError.responseTooLarge
            }
            data.append(byte)
        }
        return (data, response)
    }

    private func wait(beforeAttempt attempt: Int, policy: AIRetryPolicy) async throws {
        let multiplier = UInt64(1 << min(attempt - 1, 8))
        let maximumDelay = policy.maximumDelayMilliseconds
        let baseDelay = min(policy.baseDelayMilliseconds, maximumDelay)
        // 先比较除法结果，避免异常配置在乘法阶段产生 UInt64 溢出。
        let delay = baseDelay > maximumDelay / multiplier
            ? maximumDelay
            : baseDelay * multiplier
        try await Task.sleep(for: .milliseconds(delay))
    }

    /// 只重试瞬时故障；鉴权、参数与安全拒答不会进入重试。
    private static func isRetryable(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private static func isRetryable(error: Error) -> Bool {
        if let serviceError = error as? AIServiceError,
           case .httpError(let statusCode, _) = serviceError {
            return isRetryable(statusCode: statusCode)
        }
        guard let urlError = error as? URLError else { return false }
        // 设备明确离线时不重试——重试不会恢复网络，且会阻塞 fallback 到本地模型。
        guard urlError.code != .notConnectedToInternet else { return false }
        return [
            .timedOut,
            .networkConnectionLost,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed
        ].contains(urlError.code)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any] {
            return boundedErrorMessage(error["message"] as? String)
        }
        return boundedErrorMessage(object["message"] as? String ?? object["msg"] as? String)
    }

    /// 服务端错误只作为简短用户提示，不允许携带超长正文或多行调试信息。
    private static func boundedErrorMessage(_ value: String?) -> String? {
        let normalized = value?
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ") ?? ""
        return normalized.isEmpty ? nil : String(normalized.prefix(240))
    }
}
