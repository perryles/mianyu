/// HealthProfileViewModel 作为 HealthProfileView 的视图模型，负责管理健康画像数据。
/// 负责处理画像摘要的加载、授权状态追踪与时间范围切换。

import SwiftUI

@MainActor
@Observable
final class HealthProfileViewModel {
    var summary: HealthProfileSummary?
    var isLoading = false
    var isAuthorizing = false
    var authorizationMessage: String?
    var selectedRange: HealthProfileRange = .thirtyDays

    private let store: HealthProfileSummaryStore
    private var loadTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?

    init() {
        self.store = HealthProfileSummaryStore.shared
    }

    init(store: HealthProfileSummaryStore) {
        self.store = store
    }

    func load(forceRefresh: Bool = false) {
        loadTask?.cancel()
        isLoading = true
        let range = selectedRange
        loadTask = Task { @MainActor in
            let result = await store.summary(range: range, forceRefresh: forceRefresh)
            guard !Task.isCancelled, selectedRange == range else { return }
            summary = result
            isLoading = false
        }
    }

    func requestHealthAuthorization() {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        let requestedRange = selectedRange
        authorizationTask?.cancel()
        authorizationTask = Task { @MainActor in
            defer { isAuthorizing = false }
            do {
                try await HealthKitManager.shared.requestAuthorization()
                guard !Task.isCancelled else { return }
                authorizationMessage = "健康权限检查已完成，正在重新生成档案。"
                let result = await store.summary(range: requestedRange, forceRefresh: true)
                guard !Task.isCancelled else { return }
                if selectedRange == requestedRange {
                    summary = result
                } else {
                    load(forceRefresh: true)
                }
            } catch {
                authorizationMessage = "暂时无法更新健康权限，可以稍后再试。"
            }
        }
    }
}
