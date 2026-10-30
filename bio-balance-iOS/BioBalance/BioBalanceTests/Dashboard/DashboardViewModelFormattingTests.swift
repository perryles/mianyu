import Foundation
import XCTest
@testable import BioBalance

/// DashboardViewModel+MetricsCards（PEN-14 拆分后）格式化与卡片构建单元测试。
///
/// 只调用纯格式化 / 卡片派生方法，使用本地输入，不依赖 HealthKit 授权或网络。
nonisolated final class DashboardViewModelFormattingTests: XCTestCase {

    @MainActor private var viewModel: DashboardViewModel!

    @MainActor override func setUp() async throws {
        try await super.setUp()
        viewModel = DashboardViewModel()
    }

    @MainActor override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    @MainActor private func point(_ timestamp: Int64, _ value: Double) -> TimeSeriesPointDouble {
        TimeSeriesPointDouble(timestamp: timestamp, value: value)
    }

    // MARK: - formatValue

    @MainActor func testFormatValueFormatsWithRequestedDigits() {
        XCTAssertEqual(viewModel.formatValue(3.14159, digits: 2, fallback: "暂无"), "3.14")
        XCTAssertEqual(viewModel.formatValue(80.4, digits: 0, fallback: "暂无"), "80")
        XCTAssertEqual(viewModel.formatValue(80.6, digits: 0, fallback: "暂无"), "81")
    }

    @MainActor func testFormatValueFallsBackForNil() {
        XCTAssertEqual(viewModel.formatValue(nil, digits: 1, fallback: "暂无"), "暂无")
    }

    // MARK: - deltaText

    @MainActor func testDeltaTextNilComparison() {
        XCTAssertEqual(viewModel.deltaText(current: nil, previous: 60, unit: "bpm", positiveWord: "升高", negativeWord: "降低"), "暂无昨日对比")
        XCTAssertEqual(viewModel.deltaText(current: 60, previous: nil, unit: "bpm", positiveWord: "升高", negativeWord: "降低"), "暂无昨日对比")
    }

    @MainActor func testDeltaTextFlatComparison() {
        let text = viewModel.deltaText(current: 60, previous: 60, unit: "bpm", positiveWord: "升高", negativeWord: "降低")
        XCTAssertTrue(text.contains("持平"))
    }

    @MainActor func testDeltaTextRendersDeltaAndWord() {
        let up = viewModel.deltaText(current: 70, previous: 65, unit: "bpm", positiveWord: "升高", negativeWord: "降低")
        XCTAssertTrue(up.contains("升高"))
        XCTAssertTrue(up.contains("5"))
        XCTAssertTrue(up.contains("bpm"))

        let down = viewModel.deltaText(current: 60, previous: 70, unit: "bpm", positiveWord: "升高", negativeWord: "降低")
        XCTAssertTrue(down.contains("降低"))
        XCTAssertTrue(down.contains("10"))
    }

    @MainActor func testDeltaTextUsesOneDecimalForPercent() {
        let text = viewModel.deltaText(current: 10.4, previous: 10.0, unit: "%", positiveWord: "增加", negativeWord: "降低")
        XCTAssertTrue(text.contains("0.4"))
    }

    // MARK: - sanitizeTrend / previousValue / positiveValue

    @MainActor func testSanitizeTrendFiltersNegativeSortsAndKeepsLastSeven() {
        let trend = [
            point(5, -1),
            point(3, 30),
            point(7, 40),
            point(1, 10),
            point(8, 50),
            point(9, 60),
            point(10, 70),
            point(11, 80),
            point(12, 90)
        ]
        let sanitized = viewModel.sanitizeTrend(trend)
        XCTAssertEqual(sanitized.map(\.value), [30, 40, 50, 60, 70, 80, 90])
        XCTAssertEqual(sanitized.map(\.timestamp), [3, 7, 8, 9, 10, 11, 12])
    }

    @MainActor func testPreviousValueReturnsYesterdaysValue() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let trend = [
            point(Int64(yesterday.timeIntervalSince1970), 65),
            point(Int64(today.timeIntervalSince1970), 70)
        ]
        XCTAssertEqual(viewModel.previousValue(in: trend, relativeTo: today), 65)
    }

    @MainActor func testPreviousValueNilWithoutYesterday() {
        let today = Calendar.current.startOfDay(for: Date())
        let trend = [point(Int64(today.timeIntervalSince1970), 70)]
        XCTAssertNil(viewModel.previousValue(in: trend, relativeTo: today))
    }

    @MainActor func testPositiveValueFiltersNonPositive() {
        XCTAssertNil(viewModel.positiveValue(0))
        XCTAssertNil(viewModel.positiveValue(-3))
        XCTAssertEqual(viewModel.positiveValue(5), 5)
    }

    // MARK: - lastUpdatedText

    @MainActor func testLastUpdatedTextFromTrend() {
        let date = Date(timeIntervalSince1970: 1_730_000_000)
        let trend = [point(Int64(date.timeIntervalSince1970), 10)]
        XCTAssertEqual(
            viewModel.lastUpdatedText(from: trend),
            date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
        )
    }

    @MainActor func testLastUpdatedTextEmptyTrend() {
        XCTAssertEqual(viewModel.lastUpdatedText(from: []), "暂无日期")
    }

    // MARK: - 卡片构建

    @MainActor func testMakeHRVCardStatusTones() {
        let high = viewModel.makeHRVCard(current: 70, previous: nil, trend: [])
        XCTAssertEqual(high.statusTone, .positive)
        XCTAssertEqual(high.statusText, "优秀")
        XCTAssertEqual(high.valueText, "70")
        XCTAssertEqual(high.unitText, "ms")

        let normal = viewModel.makeHRVCard(current: 50, previous: nil, trend: [])
        XCTAssertEqual(normal.statusTone, .normal)
        XCTAssertEqual(normal.statusText, "正常")

        let low = viewModel.makeHRVCard(current: 30, previous: nil, trend: [])
        XCTAssertEqual(low.statusTone, .caution)
        XCTAssertEqual(low.statusText, "偏低")

        let missing = viewModel.makeHRVCard(current: nil, previous: nil, trend: [])
        XCTAssertEqual(missing.statusTone, .muted)
        XCTAssertEqual(missing.statusText, "暂无")
        XCTAssertEqual(missing.valueText, "暂无")
    }

    @MainActor func testMakeRestingHeartRateCardStatusTones() {
        XCTAssertEqual(viewModel.makeRestingHeartRateCard(current: 55, previous: nil, trend: []).statusTone, .positive)
        XCTAssertEqual(viewModel.makeRestingHeartRateCard(current: 65, previous: nil, trend: []).statusTone, .normal)
        XCTAssertEqual(viewModel.makeRestingHeartRateCard(current: 75, previous: nil, trend: []).statusTone, .caution)
    }

    @MainActor func testMakeWristTemperatureCardStatusTones() {
        XCTAssertEqual(viewModel.makeWristTemperatureCard(current: 36.5, previous: nil, trend: []).statusTone, .normal)
        XCTAssertEqual(viewModel.makeWristTemperatureCard(current: 38, previous: nil, trend: []).statusTone, .caution)
        XCTAssertEqual(viewModel.makeWristTemperatureCard(current: nil, previous: nil, trend: []).statusTone, .muted)
    }

    @MainActor func testMakeWalkingAsymmetryCardStatusTones() {
        XCTAssertEqual(viewModel.makeWalkingAsymmetryCard(current: 8, previous: nil, trend: []).statusTone, .normal)
        XCTAssertEqual(viewModel.makeWalkingAsymmetryCard(current: 12, previous: nil, trend: []).statusTone, .caution)
        XCTAssertEqual(viewModel.makeWalkingAsymmetryCard(current: 20, previous: nil, trend: []).statusTone, .caution)
    }

    @MainActor func testMakeSunlightCardStatusTones() {
        XCTAssertEqual(viewModel.makeSunlightCard(current: 25, previous: nil, trend: []).statusTone, .positive)
        XCTAssertEqual(viewModel.makeSunlightCard(current: 10, previous: nil, trend: []).statusTone, .normal)
        XCTAssertEqual(viewModel.makeSunlightCard(current: nil, previous: nil, trend: []).statusTone, .muted)
    }

    @MainActor func testCardsCarryDeltaAndLastUpdatedText() {
        let date = Date(timeIntervalSince1970: 1_730_000_000)
        let card = viewModel.makeHRVCard(current: 70, previous: 60, trend: [point(Int64(date.timeIntervalSince1970), 65)])
        // HRV 卡片单位是 ms；差值文案随语言本地化，这里只校验数值与单位（中英文都包含）。
        XCTAssertTrue(card.deltaText.contains("10"))
        XCTAssertTrue(card.deltaText.contains("ms"))
        XCTAssertEqual(card.lastUpdatedText, date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits)))
    }
}
