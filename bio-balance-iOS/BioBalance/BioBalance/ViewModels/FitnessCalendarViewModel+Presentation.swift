import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// FitnessCalendarViewModel 展示模型构建子模块（精简后保留反馈交互）。
/// 从原 FitnessCalendarViewModel.swift 拆出；再按职责拆分至 +Calendar / +Overview / +Performance / +Progress / +Detail / +Formatting。
/// 对外接口不变。

@MainActor
extension FitnessCalendarViewModel {

    func playSelectionFeedback() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    func playSuccessFeedback() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

}
