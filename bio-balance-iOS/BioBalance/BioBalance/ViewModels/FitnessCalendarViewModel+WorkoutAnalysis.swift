import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// FitnessCalendarViewModel 训练深度分析子模块。
/// 负责为详情页把「选中的某一天」解析成具体训练会话，并按会话加载爬升/分段分析报告。

@MainActor
extension FitnessCalendarViewModel {

    /// 当日训练会话引用：详情页用它在多次训练之间切换分析对象。
    func loadWorkoutSessionReferences(for date: Date) async -> [WorkoutSessionReference] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return (try? await healthKitManager.fetchWorkoutSessionReferences(startDate: start, endDate: end)) ?? []
    }

    /// 加载单次训练的深度分析报告；样本不足时自然返回 nil，由 UI 展示降级态。
    func loadWorkoutAnalysisReport(for reference: WorkoutSessionReference) async -> WorkoutAnalysisReport? {
        (try? await healthKitManager.fetchWorkoutAnalysisReport(for: reference)) ?? nil
    }
}
