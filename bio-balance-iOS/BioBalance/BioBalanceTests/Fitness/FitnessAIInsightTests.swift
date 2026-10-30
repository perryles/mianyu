import XCTest
@testable import BioBalance

nonisolated final class FitnessAIInsightTests: XCTestCase {
    @MainActor private let engine = FitnessAIInsightEngine()

    @MainActor func testMissingSignalsProduceInsufficientConclusionWithoutInventingScores() {
        let insight = engine.makeInsight(from: .placeholder)

        XCTAssertEqual(insight.confidence, .insufficient)
        XCTAssertEqual(insight.title, "先建立你的训练基线")
        XCTAssertTrue(insight.evidence.contains { $0.contains("缺少") })
    }

    @MainActor func testHighLoadAndLowRecoveryAreExplainedAsImbalance() {
        let insight = engine.makeInsight(from: makeContext(load: 82, recovery: 38))

        XCTAssertEqual(insight.confidence, .ready)
        XCTAssertEqual(insight.title, "训练负荷暂时跑在恢复前面")
        XCTAssertTrue(insight.evidence.contains { $0.contains("负荷 82") && $0.contains("恢复 38") })
    }

    @MainActor func testIncreasingFrequencyProducesRisingTrendConclusion() {
        let context = makeContext(
            recentTrainingDays: 4,
            previousTrainingDays: 2,
            load: 56,
            recovery: 58,
            performanceChange: 9
        )
        let insight = engine.makeInsight(from: context)

        XCTAssertEqual(insight.title, "训练节奏正在向上抬升")
    }

    @MainActor func testFitnessPromptContainsOnlyAggregatedTrainingFields() {
        let context = makeContext(load: 61, recovery: 67)
        let messages = HealthAIContextPromptBuilder().makeMessages(
            question: "解释最近训练趋势",
            scope: .fitness(context),
            history: []
        )
        let prompt = messages.map(\.content).joined(separator: "\n")

        XCTAssertTrue(prompt.contains("近 7 天训练天数：3"))
        XCTAssertTrue(prompt.contains("当前训练负荷：61/100"))
        XCTAssertTrue(prompt.contains("不得生成训练动作、组数、次数"))
        XCTAssertFalse(prompt.contains("经纬度"))
        XCTAssertFalse(prompt.contains("原始样本值"))
    }

    @MainActor func testFitnessServiceFallsBackToDeterministicExplanationWhenProviderIsUnavailable() async throws {
        let service = HealthAIService(registry: AIProviderRegistry())
        let answer = try await service.ask(
            question: "解释最近训练趋势",
            scope: .fitness(makeContext(load: 61, recovery: 67)),
            history: []
        )

        XCTAssertEqual(answer.source, .deterministic)
        XCTAssertEqual(answer.summary, "训练与恢复目前比较同步")
    }

    @MainActor private func makeContext(
        recentTrainingDays: Int = 3,
        previousTrainingDays: Int = 2,
        load: Int?,
        recovery: Int?,
        performanceChange: Int = 3
    ) -> FitnessAIInsightContext {
        FitnessAIInsightContext(
            dateText: "2026-08-02T00:00:00Z",
            recentTrainingDays: recentTrainingDays,
            previousTrainingDays: previousTrainingDays,
            recentMinutes: 128,
            previousMinutes: 94,
            currentLoadScore: load,
            currentRecoveryScore: recovery,
            performanceScore: 72,
            performanceChange: performanceChange,
            hrvSampleDays: 4,
            activitySampleDays: 7,
            latestWorkoutSummary: "跑步 · 32 分钟"
        )
    }
}
