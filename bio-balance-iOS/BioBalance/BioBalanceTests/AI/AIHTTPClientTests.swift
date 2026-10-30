import Foundation
import Synchronization
import XCTest
@testable import BioBalance

nonisolated final class AIHTTPClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    @MainActor func testRetries429ThenSucceeds() async throws {
        MockURLProtocol.enqueue(statusCode: 429, body: #"{"message":"busy"}"#)
        MockURLProtocol.enqueue(statusCode: 200, body: #"{"value":"ok"}"#)
        let client = makeClient()
        let request = URLRequest(url: URL(string: "https://example.test/chat")!)

        let response: TestResponse = try await client.send(
            request,
            retryPolicy: AIRetryPolicy(maxAttempts: 2, baseDelayMilliseconds: 1, maximumDelayMilliseconds: 1)
        )

        XCTAssertEqual(response.value, "ok")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    @MainActor func testDoesNotRetry400() async {
        MockURLProtocol.enqueue(statusCode: 400, body: #"{"message":"bad request"}"#)
        let client = makeClient()
        let request = URLRequest(url: URL(string: "https://example.test/chat")!)

        do {
            let _: TestResponse = try await client.send(
                request,
                retryPolicy: AIRetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maximumDelayMilliseconds: 1)
            )
            XCTFail("应抛出 400 错误")
        } catch let AIServiceError.httpError(statusCode, message) {
            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(message, "bad request")
        } catch {
            XCTFail("错误类型不正确：\(error)")
        }
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    @MainActor func testCapsAttemptsAndHandlesExtremeBackoffWithoutOverflow() async {
        for _ in 0..<10 {
            MockURLProtocol.enqueue(statusCode: 503, body: #"{"message":"busy"}"#)
        }
        let client = makeClient()
        let request = URLRequest(url: URL(string: "https://example.test/chat")!)

        do {
            _ = try await client.sendData(
                request,
                retryPolicy: AIRetryPolicy(
                    maxAttempts: 100,
                    baseDelayMilliseconds: .max,
                    maximumDelayMilliseconds: 0
                )
            )
            XCTFail("应在重试上限后抛出 503")
        } catch let AIServiceError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 503)
        } catch {
            XCTFail("错误类型不正确：\(error)")
        }
        XCTAssertEqual(MockURLProtocol.requestCount, 10)
    }

    @MainActor func testRejectsOversizedResponse() async {
        MockURLProtocol.enqueue(statusCode: 200, body: "0123456789")
        let client = makeClient(maximumResponseBytes: 5)
        let request = URLRequest(url: URL(string: "https://example.test/chat")!)

        do {
            _ = try await client.sendData(request)
            XCTFail("应拒绝超过上限的响应")
        } catch AIServiceError.responseTooLarge {
            XCTAssertEqual(MockURLProtocol.requestCount, 1)
        } catch {
            XCTFail("错误类型不正确：\(error)")
        }
    }

    @MainActor func testRejectsOversizedDeclaredContentLengthWithoutRetrying() async {
        MockURLProtocol.enqueue(
            statusCode: 200,
            body: "ok",
            headerFields: [
                "Content-Type": "application/json",
                "Content-Length": "10"
            ]
        )
        let client = makeClient(maximumResponseBytes: 5)
        let request = URLRequest(url: URL(string: "https://example.test/chat")!)

        do {
            _ = try await client.sendData(request)
            XCTFail("应根据 Content-Length 提前拒绝超过上限的响应")
        } catch AIServiceError.responseTooLarge {
            XCTAssertEqual(MockURLProtocol.requestCount, 1)
        } catch {
            XCTFail("错误类型不正确：\(error)")
        }
    }

    @MainActor func testStreamSSEDecodesMultiByteUTF8Content() async throws {
        let body = """
        data: {"choices":[{"delta":{"content":"你好"}}]}

        data: {"choices":[{"delta":{"content":"，今天的压力偏高😊"}}]}

        data: [DONE]

        """
        MockURLProtocol.enqueue(
            statusCode: 200,
            body: body,
            headerFields: ["Content-Type": "text/event-stream"]
        )
        let client = makeClient()
        let request = URLRequest(url: URL(string: "https://example.test/chat")!)

        var snapshots: [String] = []
        for try await snapshot in try await client.streamSSE(request) {
            snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshots, ["你好", "你好，今天的压力偏高😊"])
    }

    @MainActor func testStreamSSEAcceptsDataPrefixWithoutSpaceAndMissingTrailingNewline() async throws {
        // data: 后无空格 + 末尾行无换行直接关闭连接。
        let body = "data:{\"choices\":[{\"delta\":{\"content\":\"睡眠充足\"}}]}\n\ndata:{\"choices\":[{\"delta\":{\"content\":\"，继续保持\"}}]}"
        MockURLProtocol.enqueue(
            statusCode: 200,
            body: body,
            headerFields: ["Content-Type": "text/event-stream"]
        )
        let client = makeClient()
        let request = URLRequest(url: URL(string: "https://example.test/chat")!)

        var snapshots: [String] = []
        for try await snapshot in try await client.streamSSE(request) {
            snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshots.last, "睡眠充足，继续保持")
    }

    @MainActor func testStreamSSERejectsOversizedAccumulatedContent() async throws {
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"0123456789\"}}]}\n\ndata: [DONE]\n\n"
        MockURLProtocol.enqueue(
            statusCode: 200,
            body: body,
            headerFields: ["Content-Type": "text/event-stream"]
        )
        let client = makeClient(maximumResponseBytes: 40)
        let request = URLRequest(url: URL(string: "https://example.test/chat")!)

        do {
            for try await _ in try await client.streamSSE(request) {}
            XCTFail("应拒绝超过上限的累积内容")
        } catch AIServiceError.responseTooLarge {
            // 预期：行缓冲或累积内容触发上限。
        } catch {
            XCTFail("错误类型不正确：\(error)")
        }
    }

    @MainActor private func makeClient(
        maximumResponseBytes: Int = AIHTTPClient.defaultMaximumResponseBytes
    ) -> AIHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return AIHTTPClient(
            session: URLSession(configuration: configuration),
            maximumResponseBytes: maximumResponseBytes
        )
    }
}

nonisolated private struct TestResponse: Decodable, Sendable {
    let value: String
}

nonisolated private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var responses: [(statusCode: Int, body: Data, headerFields: [String: String])] = []
        var count = 0
    }
    private static let state = Mutex(State())

    static var requestCount: Int {
        state.withLock { $0.count }
    }

    static func reset() {
        state.withLock {
            $0.responses = []
            $0.count = 0
        }
    }

    static func enqueue(
        statusCode: Int,
        body: String,
        headerFields: [String: String] = ["Content-Type": "application/json"]
    ) {
        state.withLock {
            $0.responses.append((statusCode, Data(body.utf8), headerFields))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let item = Self.state.withLock {
            $0.count += 1
            return $0.responses.removeFirst()
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: item.statusCode,
            httpVersion: nil,
            headerFields: item.headerFields
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: item.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
