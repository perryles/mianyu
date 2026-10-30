/// NoDataStateView 由各数据展示页调用，作为「无数据」共享占位页。
/// 负责展示空状态图标/标题/消息与可选操作按钮。

import SwiftUI

/// 无数据状态视图 由上级页面或路由调用，作为辅助界面里的界面或内容组件。
/// 负责承载弹层、空状态、引导态或局部补充信息，帮助主流程表达更完整。
struct NoDataStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        systemImage: String = "tray",
        title: String = "暂无数据",
        message: String = "当前还没有可展示的记录。",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        BBEmptyStateView(
            systemImage: systemImage,
            title: title,
            message: message,
            actionTitle: actionTitle,
            action: action
        )
    }
}