import Foundation
import XCTest
@testable import BioBalance

nonisolated final class CoreAIContractTests: XCTestCase {
    @MainActor func testPromptKeepsFourValidHistoryMessagesWithoutDuplicatingCurrentQuestion() {
        let currentQuestion = String(repeating: "问", count: 2_500)
        let longHistory = String(repeating: "答", count: 2_000)
        let history = [
            HealthAIChatMessage(role: .user, text: "old-1"),
            HealthAIChatMessage(role: .assistant, text: "old-2"),
            HealthAIChatMessage(role: .user, text: "old-3"),
            HealthAIChatMessage(role: .assistant, text: "old-4"),
            HealthAIChatMessage(role: .assistant, text: longHistory),
            HealthAIChatMessage(role: .system, text: "hidden"),
            HealthAIChatMessage(role: .user, text: currentQuestion),
            HealthAIChatMessage(role: .assistant, text: "  \n "),
            HealthAIChatMessage(role: .assistant, text: "loading", isLoading: true)
        ]

        let messages = HealthAIContextPromptBuilder().makeMessages(
            question: currentQuestion,
            scope: .today(makeContext()),
            history: history
        )
        let conversation = Array(messages.dropFirst(2))
        let normalizedQuestion = String(currentQuestion.prefix(HealthAIContextPromptBuilder.maximumQuestionCharacters))

        XCTAssertEqual(conversation.count, 5)
        XCTAssertEqual(
            Array(conversation.map(\.content).prefix(4)),
            ["old-2", "old-3", "old-4", String(longHistory.prefix(1_500))]
        )
        XCTAssertEqual(conversation.last?.content, normalizedQuestion)
        XCTAssertEqual(conversation.filter { $0.content == normalizedQuestion }.count, 1)
        XCTAssertFalse(conversation.contains { $0.content == "hidden" || $0.content == "loading" })
    }

    @MainActor func testServiceRejectsBlankQuestionBeforeRouting() async {
        let service = HealthAIService(registry: AIProviderRegistry())

        do {
            _ = try await service.ask(question: "  \n ", scope: .today(makeContext()), history: [])
            XCTFail("空问题不应进入路由")
        } catch AIServiceError.invalidRequest {
            // Expected.
        } catch {
            XCTFail("错误类型不正确：\(error)")
        }
    }

    @MainActor func testServiceReportsLocalAnswerSource() async throws {
        let service = HealthAIService(registry: AIProviderRegistry())

        let answer = try await service.ask(
            question: "今天怎么恢复？",
            scope: .healthProfile(digest: makeProfileDigest()),
            history: []
        )

        XCTAssertEqual(answer.source, AIResponseSource.deterministic)
        XCTAssertEqual(answer.source?.displayLabel, "本地确定性健康引擎")
    }

    @MainActor func testServiceReportsActualRemoteProviderAndModel() async throws {
        let provider = SourceReportingTextProvider()
        let service = HealthAIService(registry: AIProviderRegistry(textProviders: [provider]))

        let answer = try await service.ask(
            question: "今天怎么恢复？",
            scope: .today(makeContext(healthProfileSummary: makeProfileDigest())),
            history: []
        )

        XCTAssertEqual(answer.source?.providerID, .qwen)
        XCTAssertEqual(answer.source?.displayLabel, "测试千问 · qwen-source-test")
        XCTAssertFalse(answer.source?.isLocal ?? true)
    }

    @MainActor func testTodayPromptDoesNotUploadAttachedProfileSummary() {
        let privateHeadline = "仅供本地使用的长期档案"
        let context = makeContext(
            healthProfileSummary: makeProfileDigest(headline: privateHeadline)
        )

        let messages = HealthAIContextPromptBuilder().makeMessages(
            question: "今天怎么恢复？",
            scope: .today(context),
            history: []
        )

        XCTAssertTrue(HealthAIScope.today(context).permitsRemoteRequest)
        XCTAssertFalse(messages.contains { $0.content.contains(privateHeadline) })
    }

    @MainActor func testTodayServiceDoesNotSilentlyFallbackAfterRemoteFailure() async {
        let service = HealthAIService(
            registry: AIProviderRegistry(textProviders: [FailingSourceTextProvider()])
        )

        do {
            _ = try await service.ask(
                question: "今天怎么恢复？",
                scope: .today(makeContext()),
                history: []
            )
            XCTFail("今日云端失败时不应静默返回本地回答")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("错误类型不正确：\(error)")
        }
    }

    @MainActor func testBaselineThresholdsRemainInternallyConsistent() {
        let state = HealthBaselineStrategy.state(
            for: [42],
            metric: .hrvSDNN,
            minimumSampleCount: -5,
            trustedSampleCount: 0
        )

        XCTAssertEqual(state.minimumSampleCount, 1)
        XCTAssertEqual(state.trustedSampleCount, 1)
        XCTAssertLessThanOrEqual(state.minimumSampleCount, state.trustedSampleCount)
    }

    @MainActor func testFutureSnapshotIsNotFresh() {
        let now = Date()
        let snapshot = DailyDeterministicHealthSnapshot(
            schemaVersion: DailyDeterministicHealthSnapshot.currentSchemaVersion,
            date: now,
            generatedAt: now.addingTimeInterval(60),
            engineVersions: .current,
            metrics: []
        )

        XCTAssertEqual(snapshot.freshness(at: now), .stale)
    }

    @MainActor func testSleepGoalResolverUsesValidLegacyValueAndSafeDefault() {
        let suite = "CoreAIContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(20.0, forKey: "daily_sleep_goal_hours")
        defaults.set(8.0, forKey: "sleepGoalHours")

        XCTAssertEqual(SleepGoalResolver.configuredGoalMinutes(defaults: defaults), 480)
        defaults.removeObject(forKey: "sleepGoalHours")
        XCTAssertEqual(SleepGoalResolver.goalMinutes(defaultValue: .max, defaults: defaults), 480)
    }

    @MainActor private func makeContext(
        healthProfileSummary: HealthProfileAIDigest? = nil
    ) -> HealthAIContext {
        HealthAIContext(
            dateText: "2026-07-22T12:00:00Z",
            sleep: .init(
                durationMinutes: nil,
                score: nil,
                startLocalTime: nil,
                endLocalTime: nil,
                awakeCount: nil,
                deepMinutes: nil,
                remMinutes: nil
            ),
            recoveryVitals: .init(
                nightlyHrvMs: nil,
                nightlyAverageHeartRate: nil,
                nightlyRespiratoryRate: nil,
                wristTemperatureCelsius: nil
            ),
            todayVitals: .init(
                currentHeartRate: nil,
                restingHeartRate: nil,
                recentAverageRestingHeartRate: nil,
                todayAverageHrv: nil,
                recentAverageHrv: nil
            ),
            stress: .init(
                score: nil,
                currentScore: nil,
                dailyScore: nil,
                band: "insufficient",
                title: "样本不足",
                summary: "当前没有足够样本。"
            ),
            activity: .init(
                stepsToday: nil,
                exerciseMinutesToday: nil,
                standHoursToday: nil,
                walkingSpeedMpsToday: nil
            ),
            recoveryBehavior: .init(
                sedentaryElapsedMinutesCurrent: nil,
                sedentaryTotalMinutesToday: nil,
                sedentaryLongestSessionMinutesToday: nil,
                activeBreakCountToday: nil
            ),
            caffeineConsumedTodayMg: nil,
            caffeineEstimatedRemainingMg: nil,
            daylightMinutesToday: nil,
            waterMlToday: nil,
            sleepGoalMinutes: nil,
            recoveryScriptPlan: nil,
            healthProfileSummary: healthProfileSummary,
            disclaimer: "仅供健康管理参考。"
        )
    }

    @MainActor private func makeProfileDigest(
        headline: String = "测试长期档案"
    ) -> HealthProfileAIDigest {
        HealthProfileAIDigest(
            headline: headline,
            status: "建立中",
            growthScore: 50,
            topTags: [],
            topRisks: [],
            nextActions: [],
            recentChanges: []
        )
    }
}

private struct SourceReportingTextProvider: AITextProviding {
    let descriptor = AIProviderDescriptor(
        id: .qwen,
        displayName: "测试千问",
        capabilities: [.healthChat],
        isLocal: false
    )

    func isAvailable(for capability: AICapability) -> Bool {
        capability == .healthChat
    }

    func generateText(_ request: AITextRequest) async throws -> AITextResponse {
        AITextResponse(
            content: "## 结论\n测试回答",
            providerID: .qwen,
            model: "qwen-source-test"
        )
    }
}

private struct FailingSourceTextProvider: AITextProviding {
    let descriptor = AIProviderDescriptor(
        id: .qwen,
        displayName: "测试千问",
        capabilities: [.healthChat],
        isLocal: false
    )

    func isAvailable(for capability: AICapability) -> Bool {
        capability == .healthChat
    }

    func generateText(_ request: AITextRequest) async throws -> AITextResponse {
        throw URLError(.timedOut)
    }
}
