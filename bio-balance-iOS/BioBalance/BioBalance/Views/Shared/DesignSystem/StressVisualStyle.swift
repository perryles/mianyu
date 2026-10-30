/// StressVisualStyle 作为今日页的支撑类型，负责定义压力可视化风格。
/// 负责描述压力级别对应的插画变体（轨道/绽放/流动等）与配色方案。

import SwiftUI

/// 今日压力Illustration枚举 作为今日页里的状态与分类定义。
/// 负责描述今天页健康概览展示过程中会用到的状态、分类或分支。
enum StressIllustrationVariant: String, CaseIterable, Sendable {
    case waitingOrbit
    case relaxedBloom
    case steadyFlow
    case mildLift
    case cautionPulse
    case highStorm
}

/// 今日压力视觉结构体 作为今日页里的辅助类型。
/// 负责今天页健康概览展示。
struct StressVisualStyle: Equatable, Sendable {
    let band: StressBand
    let accentHex: String
    let secondaryHex: String
    let glowHex: String
    let heroGradientHexes: [String]
    let illustrationVariant: StressIllustrationVariant
    let adviceSymbol: String
    let metricSymbol: String
    let chartEmptyText: String
    let highlightScaleSegment: Int?
    let buttonHex: String

    static func style(for band: StressBand) -> StressVisualStyle {
        switch band {
        case .waiting:
            return StressVisualStyle(
                band: band,
                accentHex: "6C6C70",
                secondaryHex: "B9C0FF",
                glowHex: "E8ECFF",
                heroGradientHexes: ["8E91A5", "A5A8BA"],
                illustrationVariant: .waitingOrbit,
                adviceSymbol: "applewatch.radiowaves.left.and.right",
                metricSymbol: "hourglass",
                chartEmptyText: "继续佩戴 Apple Watch，等待今日数据同步",
                highlightScaleSegment: nil,
                buttonHex: "7FD4AE"
            )
        case .relaxed:
            return StressVisualStyle(
                band: band,
                accentHex: "34C759",
                secondaryHex: "8DE5C4",
                glowHex: "E8FAF1",
                heroGradientHexes: ["E8FBF2", "D9F8EB"],
                illustrationVariant: .relaxedBloom,
                adviceSymbol: "leaf.fill",
                metricSymbol: "sparkles",
                chartEmptyText: "当前状态轻松，等待更多样本补全全天趋势",
                highlightScaleSegment: 0,
                buttonHex: "34C759"
            )
        case .steady:
            return StressVisualStyle(
                band: band,
                accentHex: "007F79",
                secondaryHex: "2FD1D8",
                glowHex: "D2F6F4",
                heroGradientHexes: ["CFF8F4", "B7EEF1"],
                illustrationVariant: .steadyFlow,
                adviceSymbol: "water.waves",
                metricSymbol: "circle.hexagongrid.fill",
                chartEmptyText: "当前趋势平稳，继续记录可看到更完整的节律变化",
                highlightScaleSegment: 1,
                buttonHex: "007F79"
            )
        case .mild:
            return StressVisualStyle(
                band: band,
                accentHex: "FF9F0A",
                secondaryHex: "FFB347",
                glowHex: "FFE3BC",
                heroGradientHexes: ["FFE0B6", "FFD39A"],
                illustrationVariant: .mildLift,
                adviceSymbol: "sun.min.fill",
                metricSymbol: "figure.mind.and.body",
                chartEmptyText: "当前处于轻度压力，继续同步可判断是否持续上升",
                highlightScaleSegment: 2,
                buttonHex: "7FD4AE"
            )
        case .caution:
            return StressVisualStyle(
                band: band,
                accentHex: "FF7A00",
                secondaryHex: "FFA45A",
                glowHex: "FFE8D7",
                heroGradientHexes: ["FFF0E6", "FFDCC3"],
                illustrationVariant: .cautionPulse,
                adviceSymbol: "bell.badge.fill",
                metricSymbol: "bolt.heart.fill",
                chartEmptyText: "压力已偏高，请继续记录以判断是否需要立即调整节奏",
                highlightScaleSegment: 3,
                buttonHex: "7FD4AE"
            )
        case .high:
            return StressVisualStyle(
                band: band,
                accentHex: "D70015",
                secondaryHex: "FF8A80",
                glowHex: "FFE4E3",
                heroGradientHexes: ["FFF0EF", "FFD9D6"],
                illustrationVariant: .highStorm,
                adviceSymbol: "exclamationmark.triangle.fill",
                metricSymbol: "waveform.path.ecg.rectangle",
                chartEmptyText: "当前为高压状态，请优先休息并观察后续变化",
                highlightScaleSegment: 4,
                buttonHex: "7FD4AE"
            )
        }
    }
}

extension StressVisualStyle {
    var accentColor: Color { Color(hex: accentHex) }
    var secondaryColor: Color { Color(hex: secondaryHex) }
    var glowColor: Color { Color(hex: glowHex) }
    @MainActor var heroGradient: [Color] { heroGradientHexes.map { Color(hex: $0) } }
    var buttonColor: Color { Color(hex: buttonHex) }
    var heroImageName: String {
        switch band {
        case .waiting:
            return "TodayPressureWaiting"
        case .relaxed:
            return "TodayPressureRelaxed"
        case .steady:
            return "TodayPressureSteady"
        case .mild:
            return "TodayPressureMild"
        case .caution:
            return "TodayPressureCaution"
        case .high:
            return "TodayPressureHigh"
        }
    }

    var scaleSegmentColors: [Color] {
        [
            Color(hex: "A7E7C4"),
            Color(hex: "7DDBE3"),
            Color(hex: "FFC778"),
            Color(hex: "FFA45A"),
            Color(hex: "FF8A80")
        ]
    }

    var scaleValue: Double? {
        switch band {
        case .waiting:
            return nil
        case .relaxed:
            return 14
        case .steady:
            return 34
        case .mild:
            return 56
        case .caution:
            return 77
        case .high:
            return 92
        }
    }
}
