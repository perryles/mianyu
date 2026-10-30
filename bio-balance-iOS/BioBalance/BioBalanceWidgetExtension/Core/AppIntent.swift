/// App Intent 定义 Widget 相关的共享能力或辅助逻辑，负责支撑小组件的数据读取、样式组织与交互行为。
//
//  AppIntent.swift
//  BioBalanceWidget
//
//  Created by lihaha on 2026/4/15.
//

import WidgetKit
import AppIntents

enum WidgetFocusMode: String, AppEnum {
    case automatic
    case recovery
    case sleep
    case stress
    case activity
    case hydration

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "聚焦内容")
    }

    static var caseDisplayRepresentations: [WidgetFocusMode: DisplayRepresentation] {
        [
            .automatic: DisplayRepresentation(title: "自动"),
            .recovery: DisplayRepresentation(title: "恢复"),
            .sleep: DisplayRepresentation(title: "睡眠"),
            .stress: DisplayRepresentation(title: "压力"),
            .activity: DisplayRepresentation(title: "活动"),
            .hydration: DisplayRepresentation(title: "补水")
        ]
    }
}

extension WidgetFocusMode {
    var sharedMode: SharedWidgetFocusMode {
        switch self {
        case .automatic:
            return .automatic
        case .recovery:
            return .recovery
        case .sleep:
            return .sleep
        case .stress:
            return .stress
        case .activity:
            return .activity
        case .hydration:
            return .hydration
        }
    }
}

/// ConfigurationAppIntent结构体 作为核心能力层里的辅助类型。
/// 负责Widget 展示与配置。
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "综合状态小组件" }
    static var description: IntentDescription { "选择你想优先查看的健康聚焦内容。" }

    @Parameter(title: "聚焦", default: .automatic)
    var focus: WidgetFocusMode
}