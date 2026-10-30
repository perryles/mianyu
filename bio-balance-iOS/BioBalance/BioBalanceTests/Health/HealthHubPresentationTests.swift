import XCTest
@testable import BioBalance

nonisolated final class HealthHubPresentationTests: XCTestCase {
    @MainActor func testEveryExpandedToolExplainsItsPurpose() {
        let tools = HealthHubPresentationBuilder.healthToolCapabilities
        XCTAssertEqual(tools.count, 10)
        XCTAssertTrue(tools.allSatisfy { !($0.toolExplanation ?? "").isEmpty })
        XCTAssertEqual(Set(tools.compactMap(\.toolExplanation)).count, tools.count)
        XCTAssertTrue(HealthCapabilityItem.bodyAge.toolExplanation?.contains("估算") == true)
        XCTAssertTrue(HealthCapabilityItem.wristTemperature.toolExplanation?.contains("并非体温计") == true)
        XCTAssertTrue(HealthCapabilityItem.environmentNoise.toolExplanation?.contains("并非实时") == true)
    }

    @MainActor func testToolValuesUnifyMissingDataWithoutHidingRealZero() {
        for value in ["", "--", "暂无", "暂无数据", " -- "] {
            XCTAssertTrue(HealthHubPresentationBuilder.isMissingToolValue(value))
            XCTAssertEqual(HealthHubPresentationBuilder.toolValueText(value: value, unit: "待同步"), "暂无数据")
        }
        XCTAssertEqual(HealthHubPresentationBuilder.toolValueText(value: "0", unit: "%"), "0 %")
        XCTAssertEqual(HealthHubPresentationBuilder.toolValueText(value: "36.2", unit: "℃"), "36.2 ℃")
        XCTAssertEqual(HealthHubPresentationBuilder.toolValueText(value: "记录", unit: ""), "记录")
    }

    @MainActor func testEmptyBuildingProfileDoesNotShowAZeroScore() {
        let summary = makeSummary(status: .building, growthScore: 0, recommendations: [], risks: [], completeness: [])
        XCTAssertEqual(HealthHubPresentationBuilder.profileMetric(from: summary).valueText, "--")
        XCTAssertEqual(HealthHubPresentationBuilder.profileMetric(from: summary).progress, 0)
    }

    @MainActor func testProfileExplanationSeparatesEvidenceFromLongTermScore() {
        let noData = HealthHubPresentationBuilder.profileExplanation(from: nil)
        XCTAssertTrue(noData.contains("日常记录"))
        let building = makeSummary(status: .building, growthScore: 0, recommendations: [], risks: [])
        XCTAssertTrue(HealthHubPresentationBuilder.profileExplanation(from: building).contains("不是健康评分"))
        let established = makeSummary(recommendations: [], risks: [])
        XCTAssertTrue(HealthHubPresentationBuilder.profileExplanation(from: established).contains("不代表今天的状态"))
    }

    @MainActor func testHealthHomeKeepsReportEntryUnitsAndAccessibleSignalContent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("BioBalance/Views/Health/Hub/HealthHubView.swift"), encoding: .utf8)
        let dashboard = try XCTUnwrap(source.range(of: "private var healthReferenceDashboard"))
        let end = try XCTUnwrap(source.range(of: "private var healthHubAdditionalHorizontalInset"))
        XCTAssertTrue(source[dashboard.lowerBound..<end.lowerBound].contains("figmaHealthReportEntry"))
        XCTAssertTrue(source.contains("长期健康概览"))
        XCTAssertTrue(source.contains("照护与行动"))
        XCTAssertTrue(source.contains("已同步的静息心率，并非实时心率"))
        XCTAssertTrue(source.contains("bpm"))
        XCTAssertTrue(source.contains("dynamicTypeSize.isAccessibilitySize ? 0"))
        XCTAssertTrue(source.contains("profileExplanation(from: healthProfileSummary)"))
    }

    @MainActor func testReferenceActionGridUsesTwoColumnsAndFallsBackForAccessibility() {
        XCTAssertEqual(
            HealthHubReferenceLayout.actionColumnCount(isAccessibilitySize: false),
            2
        )
        XCTAssertEqual(
            HealthHubReferenceLayout.actionColumnCount(isAccessibilitySize: true),
            1
        )
    }

    @MainActor func testReferenceLayoutUsesSleepFeatureAndAdaptiveToolGrid() {
        XCTAssertEqual(HealthHubReferenceLayout.featuredAction, .sleep)
        XCTAssertEqual(HealthHubReferenceLayout.toolColumnCount(isAccessibilitySize: false), 2)
        XCTAssertEqual(HealthHubReferenceLayout.toolColumnCount(isAccessibilitySize: true), 1)
        XCTAssertEqual(HealthHubReferenceLayout.toolRowCount(itemCount: 9, isAccessibilitySize: false), 5)
        XCTAssertEqual(HealthHubReferenceLayout.toolRowCount(itemCount: 9, isAccessibilitySize: true), 9)
    }

    @MainActor func testReviewCardsUseOneColumnOnPhoneAndThreeColumnsOnExpandedWidth() {
        XCTAssertEqual(
            HealthHubReferenceLayout.reviewColumnCount(
                availableWidth: 390,
                isAccessibilitySize: false
            ),
            1
        )
        XCTAssertEqual(
            HealthHubReferenceLayout.reviewColumnCount(
                availableWidth: 620,
                isAccessibilitySize: false
            ),
            3
        )
        XCTAssertEqual(
            HealthHubReferenceLayout.reviewColumnCount(
                availableWidth: 620,
                isAccessibilitySize: true
            ),
            1
        )
    }

    @MainActor func testDomainsAndGroupsKeepTheEditorialOrder() {
        let sections = HealthHubPresentationBuilder.domainSections

        XCTAssertEqual(sections.map(\.domain), [.bodyFoundation, .lifestyle, .specialtyCare])
        XCTAssertEqual(sections[0].groups.map(\.title), ["体能与代谢", "身体画像", "关键体征"])
        XCTAssertEqual(sections[1].groups.map(\.title), ["日常计划", "恢复与行为", "环境健康"])
        XCTAssertEqual(sections[2].groups.map(\.title), ["用药与症状", "生殖健康", "共享支持"])
    }

    @MainActor func testMedicationToolKeepsTheMedicationAndSymptomsEntryLabel() {
        XCTAssertEqual(HealthCapabilityItem.medicationSymptoms.title, "用药与症状")
        XCTAssertTrue(HealthHubPresentationBuilder.allCapabilities.contains(.medicationSymptoms))
    }

    @MainActor func testEveryCapabilityAppearsExactlyOnceInDomainHierarchy() {
        let items = HealthHubPresentationBuilder.allDomainItems

        XCTAssertEqual(items.count, HealthCapabilityItem.allCases.count)
        XCTAssertEqual(Set(items), Set(HealthCapabilityItem.allCases))
    }

    @MainActor func testCategorySwitchReturnsTheExpectedToolsForEachDomain() {
        XCTAssertEqual(
            HealthHubPresentationBuilder.capabilities(in: .bodyFoundation),
            [.fitness, .activeEnergy, .basalEnergy, .bodyAge, .bodyProfile, .healthProfile, .wristTemperature, .walkingAsymmetry]
        )
        XCTAssertEqual(
            HealthHubPresentationBuilder.capabilities(in: .lifestyle),
            [.dailyAction, .drink, .meal, .mood, .sedentary, .environmentNoise]
        )
        XCTAssertEqual(
            HealthHubPresentationBuilder.capabilities(in: .specialtyCare),
            [.medicationSymptoms, .reproductiveHealth, .friends]
        )
    }

    @MainActor func testReferenceTodayGridKeepsFourSecondaryEntryPointsWithoutDuplicatingSleep() {
        let quickActions = HealthHubPresentationBuilder.referenceQuickActions

        XCTAssertEqual(
            quickActions.map(\.id),
            ["dailyAction", "drink", "meal", "mood"]
        )
        XCTAssertEqual(quickActions.count, 4)
        XCTAssertEqual(Set(quickActions.map(\.id)).count, quickActions.count)
    }

    @MainActor func testReferenceToolCategoriesKeepSixFiltersAndExposeEveryCapability() {
        XCTAssertEqual(
            HealthHubToolCategory.allCases.map(\.title),
            ["常用", "运动", "身体", "代谢", "记录", "其他"]
        )
        XCTAssertEqual(
            HealthHubPresentationBuilder.capabilities(in: HealthHubToolCategory.common),
            [.fitness, .activeEnergy, .basalEnergy, .bodyAge, .bodyProfile, .healthProfile, .wristTemperature, .walkingAsymmetry]
        )

        let exposed = Set(
            HealthHubToolCategory.allCases.flatMap {
                HealthHubPresentationBuilder.capabilities(in: $0)
            }
        )
        XCTAssertEqual(exposed, Set(HealthHubPresentationBuilder.allCapabilities))
    }

    @MainActor func testAllCapabilitiesKeepTheFlatHealthHubOrder() {
        XCTAssertEqual(
            HealthHubPresentationBuilder.allCapabilities,
            [
                .fitness,
                .activeEnergy,
                .basalEnergy,
                .bodyAge,
                .bodyProfile,
                .healthProfile,
                .wristTemperature,
                .walkingAsymmetry,
                .dailyAction,
                .drink,
                .meal,
                .mood,
                .sedentary,
                .environmentNoise,
                .medicationSymptoms,
                .reproductiveHealth,
                .friends
            ]
        )
    }

    @MainActor func testHealthToolsExcludeEveryEntryAlreadyShownAbove() {
        let items = HealthHubPresentationBuilder.healthToolCapabilities
        let featured: Set<HealthCapabilityItem> = [
            .fitness, .healthProfile, .drink, .meal, .mood, .medicationSymptoms, .friends
        ]

        XCTAssertEqual(items.count, HealthCapabilityItem.allCases.count - featured.count)
        XCTAssertEqual(Set(items), Set(HealthCapabilityItem.allCases).subtracting(featured))
        XCTAssertTrue(items.allSatisfy { !featured.contains($0) })
    }

    @MainActor func testCollapsedToolBoardShowsSixDistinctHighValueCapabilities() {
        let items = HealthHubPresentationBuilder.collapsedCapabilities

        XCTAssertEqual(items, [.healthProfile, .activeEnergy, .bodyAge, .bodyProfile, .drink, .medicationSymptoms])
        XCTAssertEqual(Set(items).count, 6)
        XCTAssertTrue(items.allSatisfy(HealthHubPresentationBuilder.allCapabilities.contains))
    }

    @MainActor func testBuildingProfilePresentsEvidenceInsteadOfAZeroGrowthScore() {
        let summary = makeSummary(
            status: .building,
            growthScore: 0,
            recommendations: [],
            risks: [],
            completeness: [
                .init(title: "睡眠", state: .synced, detail: "已同步", sampleCount: 7),
                .init(title: "活动", state: .insufficient, detail: "样本不足", sampleCount: 1)
            ]
        )

        let metric = HealthHubPresentationBuilder.profileMetric(from: summary)

        XCTAssertEqual(metric.title, "档案依据")
        XCTAssertEqual(metric.valueText, String(summary.dataQuality.score))
        XCTAssertEqual(metric.progress, summary.dataQuality.score)
        XCTAssertNotEqual(metric.valueText, String(summary.growthScore))
    }

    @MainActor func testEstablishedProfilePresentsTheGrowthScore() {
        let summary = makeSummary(
            status: .growing,
            growthScore: 78,
            recommendations: [],
            risks: []
        )

        let metric = HealthHubPresentationBuilder.profileMetric(from: summary)

        XCTAssertEqual(metric.title, "成长分")
        XCTAssertEqual(metric.valueText, "78")
        XCTAssertEqual(metric.progress, 78)
    }

    @MainActor func testNoDataProducesAUsefulBuildingState() {
        let items = HealthHubPresentationBuilder.focusItems(from: nil)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, .building)
        XCTAssertEqual(items.first?.module, .healthKit)
        XCTAssertFalse(items.first?.detail.isEmpty ?? true)
        XCTAssertEqual(items.first?.evidenceText, "等待本地健康样本")
        XCTAssertEqual(HealthHubPresentationBuilder.focusSectionCopy(for: items).title, "档案正在形成")
    }

    @MainActor func testFocusRecommendationsSortByPriorityAndDoNotRepeatModules() {
        let summary = makeSummary(
            recommendations: [
                .init(title: "保持散步", detail: "继续当前步数", reason: "节律稳定", priority: .low, module: .activity),
                .init(title: "先补睡眠", detail: "今晚提前休息", reason: "睡眠偏少", priority: .medium, module: .sleep),
                .init(title: "补齐行动", detail: "先完成一项行动", reason: "连续性下降", priority: .high, module: .habits)
            ],
            risks: [
                .init(title: "行动波动", detail: "最近波动", suggestion: "恢复固定节律", module: .habits)
            ]
        )

        let items = HealthHubPresentationBuilder.focusItems(from: summary)

        XCTAssertEqual(items.map(\.title), ["补齐行动", "先补睡眠", "保持散步"])
        XCTAssertEqual(items.map(\.module), [.habits, .sleep, .activity])
        XCTAssertEqual(Set(items.map(\.module)).count, items.count)
    }

    @MainActor func testRiskOutranksMediumAndLowRecommendations() {
        let summary = makeSummary(
            recommendations: [
                .init(title: "继续散步", detail: "维持轻活动", reason: "活动基础尚可", priority: .medium, module: .activity),
                .init(title: "保持饮水", detail: "继续当前安排", reason: "习惯较稳定", priority: .low, module: .habits)
            ],
            risks: [
                .init(title: "睡眠节律波动", detail: "近几晚入睡时间变晚", suggestion: "今晚提前收尾", module: .sleep)
            ]
        )

        let items = HealthHubPresentationBuilder.focusItems(from: summary)

        XCTAssertEqual(items.first?.title, "睡眠节律波动")
        XCTAssertEqual(items.first?.reason, "近几晚入睡时间变晚")
        XCTAssertEqual(items.first?.detail, "今晚提前收尾")
    }

    @MainActor func testSameModuleKeepsTheHighestWeightedCandidate() {
        let summary = makeSummary(
            recommendations: [
                .init(title: "保持当前睡眠", detail: "维持当前作息", reason: "近期较稳", priority: .low, module: .sleep)
            ],
            risks: [],
            changes: [
                .init(
                    title: "入睡时间持续后移",
                    detail: "近一周入睡窗口比此前更晚。",
                    kind: .risk,
                    impact: .sleep,
                    relatedModule: .sleep
                )
            ]
        )

        let items = HealthHubPresentationBuilder.focusItems(from: summary)

        XCTAssertEqual(items.filter { $0.module == .sleep }.count, 1)
        XCTAssertEqual(items.first?.title, "入睡时间持续后移")
    }

    @MainActor func testInsufficientDataLowersAConcernBelowReliableCandidate() {
        let summary = makeSummary(
            recommendations: [
                .init(title: "补足睡眠", detail: "今晚早点休息", reason: "睡眠时长偏短", priority: .high, module: .sleep),
                .init(title: "减少久坐", detail: "下午起身活动", reason: "连续久坐变长", priority: .high, module: .sedentary)
            ],
            risks: [],
            completeness: [
                .init(title: "睡眠", state: .insufficient, detail: "样本不足", sampleCount: 1),
                .init(title: "习惯记录", state: .synced, detail: "已有样本", sampleCount: 7)
            ]
        )

        let items = HealthHubPresentationBuilder.focusItems(from: summary)

        XCTAssertEqual(items.first?.title, "减少久坐")
        XCTAssertEqual(items.last?.title, "补足睡眠")
        XCTAssertEqual(items.first?.evidenceText, "近 30 天 · 7 个有效样本")
        XCTAssertEqual(items.last?.evidenceText, "近 30 天 · 仅 1 个样本")
    }

    @MainActor func testSectionCopyMatchesTheStrongestContentInsteadOfAlwaysClaimingConcern() {
        let maintainSummary = makeSummary(
            recommendations: [
                .init(title: "保持散步", detail: "继续当前安排", reason: "活动节律稳定", priority: .low, module: .activity)
            ],
            risks: []
        )
        let observeSummary = makeSummary(
            recommendations: [
                .init(title: "观察睡眠", detail: "继续记录", reason: "仍需连续样本", priority: .medium, module: .sleep)
            ],
            risks: []
        )

        XCTAssertEqual(
            HealthHubPresentationBuilder.focusSectionCopy(
                for: HealthHubPresentationBuilder.focusItems(from: maintainSummary)
            ).title,
            "目前值得继续保持"
        )
        XCTAssertEqual(
            HealthHubPresentationBuilder.focusSectionCopy(
                for: HealthHubPresentationBuilder.focusItems(from: observeSummary)
            ).title,
            "接下来值得观察"
        )
    }

    @MainActor private func makeSummary(
        status: HealthProfileStatus = .growing,
        growthScore: Int = 78,
        recommendations: [HealthProfileActionRecommendation],
        risks: [HealthProfileRiskTendency],
        changes: [HealthProfileChange] = [],
        completeness: [HealthProfileDataCompleteness] = [
            .init(title: "睡眠", state: .synced, detail: "已同步", sampleCount: 7),
            .init(title: "活动", state: .synced, detail: "已同步", sampleCount: 7),
            .init(title: "习惯记录", state: .synced, detail: "已同步", sampleCount: 7)
        ]
    ) -> HealthProfileSummary {
        HealthProfileSummary(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            range: .thirtyDays,
            headline: "长期状态稳定",
            status: status,
            growthScore: growthScore,
            dimensions: [],
            changes: changes,
            tags: [],
            milestones: [],
            riskTendencies: risks,
            actionRecommendations: recommendations,
            dataCompleteness: completeness
        )
    }
}
