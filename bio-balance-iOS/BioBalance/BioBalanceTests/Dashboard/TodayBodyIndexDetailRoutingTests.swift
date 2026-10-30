import Testing
@testable import BioBalance

struct TodayBodyIndexDetailRoutingTests {
    @Test("身体指数的所有入口保持独立路由")
    func allBodyIndexDestinationsKeepIndependentRoutes() {
        #expect(DashboardOtherMetricDestination.allCases == [
            .hrv,
            .restingHeartRate,
            .vo2Max,
            .wristTemperature,
            .sunlight,
            .walkingAsymmetry,
            .heartRhythm
        ])
    }

    @Test("心律稳定性在等待数据时仍标明分值单位")
    func heartRhythmKeepsScoreUnitWithoutData() {
        #expect(HeartRhythmStabilityPresentation.unitText(for: .unavailable) == "分")
    }

    @Test("心律概览在无数据时仍提供完整内容")
    func heartRhythmOverviewKeepsAllMetricsWithoutData() {
        let metrics = HeartRhythmStabilityPresentation.overviewMetrics(for: .unavailable)

        #expect(metrics.map(\.title) == ["稳定评分", "分类记录", "异常线索", "心率事件"])
        #expect(metrics.map(\.value) == ["暂无", "0 次", "0 次", "0 次"])
    }
}
