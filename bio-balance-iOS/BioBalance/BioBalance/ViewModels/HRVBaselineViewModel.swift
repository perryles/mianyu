import SwiftUI

/// HRV基线视图模型 作为视图模型层里的界面状态管理入口。
/// 负责连接界面与底层数据源，处理状态管理、业务计算和用户操作响应。
@MainActor
@Observable
final class HRVBaselineViewModel {
    var nights: [HealthKitManager.NightlyHRV] = []
    var baselineMs: Double?
    private(set) var baselineState = HealthBaselineStrategy.state(for: [], metric: .hrvSDNN)
    var lastNightMs: Double?
    var isLoading = false
    var errorMessage: String?
    
    func load(days: Int = 14) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let data = try await HealthKitManager.shared.fetchNightlyHRVAverages(days: days)
                let state = HealthBaselineStrategy.state(for: data.map(\.avgMs), metric: .hrvSDNN)
                let last = data.last?.avgMs
                
                await MainActor.run {
                    nights = data
                    baselineState = state
                    baselineMs = state.isUsable ? state.value : nil
                    lastNightMs = last
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    nights = []
                    baselineState = HealthBaselineStrategy.state(for: [], metric: .hrvSDNN)
                    baselineMs = nil
                    lastNightMs = nil
                    isLoading = false
                    errorMessage = "读取 HealthKit HRV 失败，请确认已授予 HRV 与睡眠权限。"
                }
            }
        }
    }
    
}
