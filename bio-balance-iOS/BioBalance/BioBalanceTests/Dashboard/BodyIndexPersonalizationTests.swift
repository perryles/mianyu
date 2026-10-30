import Testing
@testable import BioBalance

struct BodyIndexPersonalizationTests {
    @Test("每个身体指数都有个性化内容", arguments: [
        DashboardOtherMetricDestination.hrv,
        .restingHeartRate,
        .vo2Max,
        .wristTemperature,
        .sunlight,
        .walkingAsymmetry,
        .heartRhythm
    ])
    func everyMetricHasPersonalizedContent(_ destination: DashboardOtherMetricDestination) {
        let content = BodyIndexPersonalization.content(
            for: destination,
            points: [],
            currentValue: nil,
            heartRhythmResult: .unavailable
        )

        #expect(!content.headline.isEmpty)
        #expect(!content.detail.isEmpty)
        #expect(destination == .sunlight || content.facts.count == 4)
        #expect(content.actions.count == 2)
    }

    @Test("日照不足时建议补足本地自然光")
    func lowSunlightUsesPersonalizedGap() {
        let content = BodyIndexPersonalization.content(
            for: .sunlight,
            points: [],
            currentValue: 8,
            heartRhythmResult: .unavailable
        )

        #expect(content.headline.contains("12"))
    }

    @Test("减少动态效果时个人坐标保持静止")
    func personalizedMotionRespectsReduceMotion() {
        let active = BodyIndexPersonalizationMotion.resolve(reduceMotion: false, isActive: true)
        let reduced = BodyIndexPersonalizationMotion.resolve(reduceMotion: true, isActive: true)

        #expect(active.primaryNodeScale > 1)
        #expect(active.weatherOffset < 0)
        #expect(reduced == .static)
    }
}
