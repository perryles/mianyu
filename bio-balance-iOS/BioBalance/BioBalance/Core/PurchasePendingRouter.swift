/// Purchase Pending Router 负责应用内的共享核心能力，用于处理深链、登录、订阅、评估结果或购买流程等基础服务。
import Foundation

/// PurchasePending路由器 作为核心能力层里的跳转或流程协调入口。
/// 负责核心业务服务与应用基础能力。
nonisolated struct PurchasePendingRouter {
    nonisolated static func consume(pending: Bool) -> (shouldShowPaywall: Bool, pending: Bool) {
        if pending {
            return (true, false)
        }
        return (false, pending)
    }
}
