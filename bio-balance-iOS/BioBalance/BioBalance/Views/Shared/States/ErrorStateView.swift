/// ErrorStateView 由各数据加载页调用，作为「错误状态」共享占位页。
/// 负责展示加载失败标题/消息并提供重试按钮。

import SwiftUI

/// 错误状态视图 由上级页面或路由调用，作为辅助界面里的界面或内容组件。
/// 负责承载弹层、空状态、引导态或局部补充信息，帮助主流程表达更完整。
struct ErrorStateView: View {
    let title: String
    let message: String
    let retryTitle: String
    let retry: () -> Void
    
    init(
        title: String = "加载失败",
        message: String = "发生了未知错误，请稍后再试。",
        retryTitle: String = "重试",
        retry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }
    
    var body: some View {
        BBErrorStateView(
            title: title,
            message: message,
            retryTitle: retryTitle,
            retry: retry
        )
    }
}