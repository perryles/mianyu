/// Dashboard Module Settings 定义业务数据模型，负责承载页面渲染、状态计算或模块通信所需的数据结构。
import Foundation
import SwiftUI

/// 仪表盘模块枚举 作为数据模型层里的状态与分类定义。
/// 负责描述业务数据结构定义过程中会用到的状态、分类或分支。
enum DashboardModuleKey: String, CaseIterable, Identifiable, Sendable {
    case hero
    case healthGuide
    case notificationGuide
    case sedentaryReminder
    case bodySignals
    case trends
    case sleepRecovery
    case otherMetrics
    case faq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hero: return "今日头卡"
        case .healthGuide: return "健康权限引导"
        case .notificationGuide: return "通知引导"
        case .sedentaryReminder: return "久坐提醒"
        case .bodySignals: return "身体信号"
        case .trends: return "今日趋势"
        case .sleepRecovery: return "夜间恢复"
        case .otherMetrics: return "身体指数"
        case .faq: return "常见问题"
        }
    }

    var subtitle: String {
        switch self {
        case .hero: return "首页顶部的综合状态与压力摘要"
        case .healthGuide: return "未授权健康数据时显示的引导卡片"
        case .notificationGuide: return "通知未开启时显示的引导卡片"
        case .sedentaryReminder: return "久坐计时、提醒和自动开始控制"
        case .bodySignals: return "综合压力与心肺耐力等核心指标"
        case .trends: return "HRV 与压力波动趋势图"
        case .sleepRecovery: return "睡眠摘要与夜间恢复入口"
        case .otherMetrics: return "HRV、静息心率、步态等扩展指标"
        case .faq: return "今日页底部的常见问题入口"
        }
    }

    var storageKey: String {
        "dashboard_module_visible_\(rawValue)"
    }

    var defaultValue: Bool {
        true
    }
}

/// PageCustomizationToggleDefinition结构体 作为数据模型层里的辅助类型。
/// 负责业务数据结构定义。
struct PageCustomizationToggleDefinition: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let storageKey: String
    let defaultValue: Bool
    let symbol: String
    let tintHex: String

    var tint: Color {
        Color(hex: tintHex)
    }
}

/// PageCustomization枚举 作为数据模型层里的状态与分类定义。
/// 负责描述业务数据结构定义过程中会用到的状态、分类或分支。
enum PageCustomizationKind: String, Identifiable, Sendable {
    case today

    var id: String { rawValue }

    var title: String {
        "今日页面"
    }

    var subtitle: String {
        "保留你今天最想先看到的模块，让首页更干净。"
    }

    var summaryTitle: String {
        "首页布局"
    }

    var footerPrompt: String {
        "自定义面板"
    }

    var emptyTitle: String {
        "今日页面已暂时隐藏"
    }

    var emptySubtitle: String {
        "可以通过下方“自定义面板”重新打开需要的模块。"
    }

    var icon: String {
        "sun.max.fill"
    }

    var accentHex: String {
        "38C793"
    }

    var accent: Color {
        Color(hex: accentHex)
    }

    var definitions: [PageCustomizationToggleDefinition] {
        [
            definition(for: DashboardModuleKey.hero, symbol: "rectangle.tophalf.inset.filled", tintHex: "4C7DFF"),
            definition(for: DashboardModuleKey.healthGuide, symbol: "heart.text.square.fill", tintHex: "F46B5A"),
            definition(for: DashboardModuleKey.notificationGuide, symbol: "bell.badge.fill", tintHex: "FFB340"),
            definition(for: DashboardModuleKey.sedentaryReminder, symbol: "figure.seated.side", tintHex: "38C793"),
            definition(for: DashboardModuleKey.bodySignals, symbol: "waveform.path.ecg", tintHex: "5E5CE6"),
            definition(for: DashboardModuleKey.trends, symbol: "chart.line.uptrend.xyaxis", tintHex: "32ADE6"),
            definition(for: DashboardModuleKey.sleepRecovery, symbol: "bed.double.fill", tintHex: "7D8BFF"),
            definition(for: DashboardModuleKey.otherMetrics, symbol: "square.grid.2x2.fill", tintHex: "8EC5FF"),
            definition(for: DashboardModuleKey.faq, symbol: "questionmark.circle.fill", tintHex: "7A88A3")
        ]
    }

    private func definition(
        for module: DashboardModuleKey,
        symbol: String,
        tintHex: String
    ) -> PageCustomizationToggleDefinition {
        PageCustomizationToggleDefinition(
            id: module.rawValue,
            title: module.title,
            subtitle: module.subtitle,
            storageKey: module.storageKey,
            defaultValue: module.defaultValue,
            symbol: symbol,
            tintHex: tintHex
        )
    }

}
