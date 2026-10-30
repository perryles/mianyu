import Testing
@testable import BioBalance

struct BodyIndexShareContentTests {
    @Test("分享值会保留身体指数单位", arguments: [
        ("48", "ms", "48 ms"),
        ("62", "bpm", "62 bpm"),
        ("18", "分钟", "18 分钟"),
        ("97", "分", "97 分")
    ])
    func valueIncludesUnit(_ value: String, _ unit: String, _ expected: String) {
        let content = makeContent(valueText: value, unitText: unit)

        #expect(content.formattedValue == expected)
    }

    @Test("无数据时不会在占位符后拼接单位")
    func unavailableValueDoesNotAppendUnit() {
        #expect(makeContent(valueText: "—", unitText: "ms").formattedValue == "—")
        #expect(makeContent(valueText: "暂无", unitText: "bpm").formattedValue == "暂无")
    }

    @Test("分享文案包含周期、个性化结论与指标依据")
    func plainTextContainsUsefulContext() {
        let content = makeContent(
            facts: [
                .init(title: "个人基线", value: "52 ms", symbol: "scope"),
                .init(title: "昨夜睡眠", value: "430 分钟", symbol: "bed.double.fill")
            ]
        )

        #expect(content.plainText.contains("今天"))
        #expect(content.plainText.contains("接近你的周期常态"))
        #expect(content.plainText.contains("个人基线：52 ms"))
        #expect(content.plainText.contains("仅供日常健康管理参考"))
    }

    private func makeContent(
        valueText: String = "48",
        unitText: String = "ms",
        facts: [BodyIndexPersonalizedFact] = []
    ) -> BodyIndexShareContent {
        BodyIndexShareContent(
            title: "心率变异性",
            periodText: "今天",
            valueText: valueText,
            unitText: unitText,
            statusText: "相对平稳",
            headline: "最近数值接近你的周期常态",
            detail: "当前与个人均值差异较小。",
            facts: facts,
            sampleCaption: "共 8 个有效样本"
        )
    }
}
