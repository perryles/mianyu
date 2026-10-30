#if DEBUG

import Foundation
import HealthKit
import OSLog

/// HealthKit Debug Dump 作为健康数据能力层里的调试辅助。
/// 负责在 Dashboard 首次进入时记录诊断操作与已配置读取类型。
///
/// 隐私约束（必须遵守）：
/// - 整段功能仅在 DEBUG 构建中编译，Release 构建不包含任何相关代码与调用；
/// - 只记录 operation 与 HealthKit 类型标识；
/// - 不查询或打印样本数值、时间、来源、元数据或用户内容。
enum HealthKitDebugDump {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "HealthKitDiagnostics")
    private static let lock = NSLock()
    private static var hasDumpedOnce = false

    /// 首次进入 Dashboard 时调用；进程内只记录一次。
    static func logAuthorizationReadinessIfNeeded() {
        lock.lock()
        if hasDumpedOnce {
            lock.unlock()
            return
        }
        hasDumpedOnce = true
        lock.unlock()

        guard HKHealthStore.isHealthDataAvailable() else {
            logger.info("[HealthKit][Diagnostics] operation=pageEnter")
            return
        }

        let isAuthorized = HealthAuthorizationCoordinator.shared.phase.isAuthorizedLike
            || HealthKitManager.shared.isLikelyAuthorized()
        guard isAuthorized else {
            logger.info("[HealthKit][Diagnostics] operation=pageEnter")
            return
        }

        logger.info("[HealthKit][Diagnostics] operation=pageEnter")
        let readTypes = HealthKitManager.shared.debugAuthorizationReadTypes()
            .sorted { $0.identifier < $1.identifier }
        for type in readTypes {
            logger.info("[HealthKit][Diagnostics] operation=readTypeConfigured recordType=\(type.identifier, privacy: .public)")
        }
        logger.info("[HealthKit][Diagnostics] operation=readinessComplete")
    }
}

#endif
