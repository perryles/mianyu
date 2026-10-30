import Foundation
import os

/// 用户数据隐私红线相关的稳定模型：数据域注册表、导出白名单与审计/导出/删除结果类型。
///
/// ## 边界（硬约束）
/// - 只导出「当前用户自己的白名单聚合字段」，不含健康原始明细（HealthKit 样本、RR 间期、
///   音频、图片/文件引用、精确位置、AI 元数据、模型对话全文等）。
/// - 删除范围 = 本地 SwiftData + 当前 Apple ID 私有 CloudKit 记录；好友共享与公开资料
///   走各自的生命周期接口（停止共享 / 公开资料清理），不混入私有记录删除。
/// - 导出/删除过程日志只记录 domain / zone / 数量，禁止输出任何 payload 内容（日志脱敏）。
nonisolated enum UserDataPrivacyRegistry {
    /// 内部基础设施域：不参与导出；「删除我的数据」时一并清除（属于队列/缓存，
    /// 清除后由对应 Store 按需重建，不属于用户可见业务数据）。
    static let internalDomains: Set<String> = ["local-sync-outbox", "app-data-cache", "__migration"]

    /// 域展示名（设置页与导出文件使用）。未知域回退为原始 domain。
    static func displayName(for domain: String) -> String {
        switch domain {
        case "caffeine-dose": return "咖啡因记录"
        case "mood": return "情绪记录"
        case "action-day": return "每日行动打卡"
        case "mental-assessment": return "心理自评（GAD-7 / PHQ-9）"
        case "drink-experience": return "餐饮记录"
        case "period": return "经期记录"
        case "medication-health": return "用药与补剂"
        case "medication-prescription": return "处方档案"
        case "countdown": return "倒计时事项"
        case "shared-todo": return "共享待办"
        case "recovery-challenge": return "恢复挑战"
        case "daily-wellness": return "每日轻养生"
        case "goals": return "目标与吉祥物"
        case "sleep-environment-management": return "睡眠环境记录"
        case "sleep-rhythm-protection": return "睡眠节律保护"
        case "self-observation": return "症状自评"
        case "daily-health-snapshot": return "每日健康快照（聚合）"
        case "daily-recovery-orchestration": return "每日恢复计划"
        case "daily-recovery-cooldown": return "恢复建议冷却"
        case "care-task": return "照护任务"
        case "local-sync-outbox": return "同步队列（内部）"
        case "app-data-cache": return "数据缓存（内部）"
        default: return domain
        }
    }

    /// 每域导出白名单（payload JSON 的 key）。
    ///
    /// 导出只保留「白名单 ∩ 实际字段」，白名单之外的字段一律不导出（fail-closed）：
    /// - 自由文本（note / 备注 / 指令）不导出；
    /// - 健康明细、图片/文件引用、精确位置、AI 元数据、HealthKit 样本引用不导出；
    /// - `period`、`daily-health-snapshot`、`shared-todo` 等敏感域只导出聚合元数据。
    static func exportWhitelist(for domain: String) -> Set<String> {
        switch domain {
        case "caffeine-dose":
            return ["id", "amountMg", "consumedAt", "source"]
        case "mood":
            return ["id", "moodID", "title", "backendEmotionCode", "intensity", "loggedAt", "backendRecordedAt"]
        case "action-day":
            return [
                "id", "date", "completedActions", "waterMl", "caffeineMg", "sunlightMinutes",
                "mindfulnessMinutes", "standHours", "isShared", "fitnessCheckinMode",
                "manualWorkoutMinutes", "manualWorkoutDistanceKm", "manualWorkoutEffort",
                "dailyMood", "checkedInAt", "updatedAt"
            ]
        case "mental-assessment":
            return ["kind", "recordedAt", "answers", "score", "source", "syncedToHealthKitAt"]
        case "drink-experience":
            return [
                "id", "storeName", "cityName", "drinkName", "capturedAt", "status",
                "isGeneratedFromRecognition", "updatedAt"
            ]
        case "period":
            // 经期明细（流量/疼痛/备注等）不导出，仅保留更新时间戳做聚合展示。
            return ["updatedAt"]
        case "medication-health":
            return [
                "id", "category", "name", "amount", "unit", "purpose", "takenAt",
                "planID", "logicalPlanID", "planRevision", "revision",
                "reactionState", "followUpMinutes", "backendRecordedAt",
                "effectiveFrom", "effectiveUntil"
            ]
        case "medication-prescription":
            return ["id", "medications", "conditions", "documentDate", "importedAt", "updatedAt"]
        case "countdown":
            return ["id", "title", "targetDate", "isPinned", "isShared", "createdAt", "updatedAt"]
        case "shared-todo":
            // 只导出清单元数据，不导出条目明细（可能含他人写入的备注）。
            return ["id", "title", "isShared", "updatedAt"]
        case "recovery-challenge":
            return [
                "id", "kind", "startDate", "targetDays", "currentStreak", "status",
                "reminderEnabled", "createdAt", "completedAt", "failedAt", "abandonedAt"
            ]
        case "daily-wellness":
            return ["id", "date", "microRecoveryCount", "updatedAt"]
        case "goals":
            return [
                "id", "title", "category", "symbol", "targetValue", "unit",
                "linkedActionKind", "isActive", "createdAt",
                "goalID", "date", "value", "isCompleted", "updatedAt",
                "name", "level", "xp", "rewardCount", "lastXPDate", "nameUpdatedAt",
                "amount", "awardedAt"
            ]
        case "daily-health-snapshot":
            // 派生健康聚合快照只导出版本与时间戳，不导出 metrics 明细。
            return ["schemaVersion", "date", "generatedAt"]
        case "daily-recovery-orchestration":
            return ["date", "updatedAt", "schemaVersion"]
        case "daily-recovery-cooldown":
            return ["id", "kind", "date", "updatedAt"]
        case "care-task":
            return [
                "id", "category", "title", "targetValue", "unit", "linkedModule",
                "logicalTaskID", "revision", "effectiveFrom", "effectiveUntil",
                "taskID", "slotIndex", "scheduledAt", "durationMinutes"
            ]
        default:
            // 未知域只导出元数据（domain/kind/recordID/时间），保证 fail-closed。
            return []
        }
    }
}

/// 导出文件格式。
nonisolated enum UserDataExportFormat: String, CaseIterable, Sendable {
    case json
    case csv

    var fileExtension: String { rawValue }
}

/// 单个数据域的审计/导出摘要。
nonisolated struct UserDataDomainSummary: Codable, Sendable, Hashable {
    let domain: String
    let displayName: String
    let recordCount: Int
    let earliestAt: Date?
    let latestAt: Date?
}

/// 审计报告：本机 SwiftData 各数据域现状 + CloudKit 同步开关状态。
nonisolated struct UserDataAuditReport: Codable, Sendable {
    let generatedAt: Date
    let domainSummaries: [UserDataDomainSummary]
    let cloudSyncEnabled: [CloudSyncDomainStatus]

    var totalRecordCount: Int {
        domainSummaries.reduce(0) { $0 + $1.recordCount }
    }
}

/// CloudKit 某个同步域的开关状态（盘点「云端有什么」的轻量投影）。
nonisolated struct CloudSyncDomainStatus: Codable, Sendable, Hashable {
    let domain: String
    let displayName: String
    let isEnabled: Bool
    let zoneName: String?
}

/// 单个 CloudKit zone 的删除结果。
nonisolated struct CloudZoneDeletionResult: Sendable, Hashable {
    enum State: String, Sendable, Hashable {
        /// 已删除（含「原本就没有该 zone / 无记录」的空删除）。
        case deleted
        /// 当前 Apple ID 不可用或未登录，跳过云端删除。
        case unavailable
        /// 删除失败，保留数据等待重试。
        case failed
        /// 共享/公开数据走各自生命周期接口，结果合并到这里。
        case completed
    }

    let zoneName: String
    let state: State
    let recordCount: Int
    let message: String?

    init(zoneName: String, state: State, recordCount: Int = 0, message: String? = nil) {
        self.zoneName = zoneName
        self.state = state
        self.recordCount = recordCount
        self.message = message
    }
}

/// 「删除我的数据」整体报告。
nonisolated struct UserDataDeletionReport: Sendable {
    let localSwiftDataCleared: Bool
    let localRecordCount: Int
    let cloudResults: [CloudZoneDeletionResult]

    var cloudFailureCount: Int {
        cloudResults.filter { $0.state == .failed }.count
    }

    var cloudUnavailable: Bool {
        cloudResults.allSatisfy { $0.state == .unavailable }
    }

    /// 是否「全部清除」：本地已清空，且每个 CloudKit zone 都处于已清除状态
    /// （`.deleted` / `.completed`）。iCloud 不可用（`.unavailable`）或删除失败
    /// （`.failed`）都意味着云端数据仍保留，不能视为全部清除。
    var isFullyCleared: Bool {
        localSwiftDataCleared && cloudResults.allSatisfy { $0.state == .deleted || $0.state == .completed }
    }
}

/// 导出/删除共享的隐私脱敏日志入口。
///
/// 只允许输出 domain / zone / record 数量与格式名；payload、字段值、内容一律禁止记录。
nonisolated enum UserDataPrivacyLogger {
    static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "UserDataPrivacy")

    #if DEBUG
    /// 测试专用捕获钩子：按文本捕获所有隐私日志，供单元测试断言日志脱敏
    /// （任何日志行都不包含业务 payload）。仅 DEBUG 构建可用，发布构建不含此路径。
    nonisolated(unsafe) static var testCapture: (@Sendable (String) -> Void)?
    #endif

    /// 统一以 `privacy: .public` 记录。调用方只允许传入 domain / zone / 数量等
    /// 脱敏后的摘要文本，禁止传入任何 payload 内容。
    static func info(_ message: String) {
        #if DEBUG
        testCapture?(message)
        #endif
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        #if DEBUG
        testCapture?(message)
        #endif
        logger.error("\(message, privacy: .public)")
    }
}

/// 「删除我的数据」二次确认流程（状态机）。
///
/// 删除是破坏性操作（硬约束：必须二次确认 + 文案说明）。流程把两步确认显式建模为状态：
/// 1. `requestDeletion()`：用户点击「删除我的数据」，弹出范围说明弹窗（第一次确认）；
/// 2. `proceedToFinalConfirmation()`：第一次确认通过，弹出「最后确认」弹窗（第二次确认）；
/// 3. `confirmFinalDeletion()`：用户明确点击「彻底删除」才真正执行删除。
///
/// 任何一步取消（`cancelDeletion()`）都会回到 `.idle`，绝不执行删除；未经过两步确认
/// 直接调用 `confirmFinalDeletion()` 会被忽略（fail-closed）；删除执行中忽略一切新的
/// 请求（防重复触发）。
@MainActor
final class DataPrivacyDeletionFlow {
    enum Phase: Equatable, Sendable {
        /// 初始状态：未发起删除。
        case idle
        /// 第一次确认（范围说明弹窗）展示中。
        case awaitingFirstConfirmation
        /// 第二次确认（最后确认弹窗）展示中。
        case awaitingFinalConfirmation
        /// 删除执行中。
        case deleting
        /// 删除完成。
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var lastReport: UserDataDeletionReport?

    private let deletion: @MainActor () async -> UserDataDeletionReport

    init(deletion: @escaping @MainActor () async -> UserDataDeletionReport) {
        self.deletion = deletion
    }

    /// 用户点击「删除我的数据」：进入第一次确认。尚未执行任何删除。
    func requestDeletion() {
        guard phase == .idle else { return }
        phase = .awaitingFirstConfirmation
    }

    /// 第一次确认通过：进入第二次（最后）确认。仍未执行任何删除。
    func proceedToFinalConfirmation() {
        guard phase == .awaitingFirstConfirmation else { return }
        phase = .awaitingFinalConfirmation
    }

    /// 任一步取消：回到初始状态，不执行删除。
    func cancelDeletion() {
        guard phase == .awaitingFirstConfirmation || phase == .awaitingFinalConfirmation else { return }
        phase = .idle
    }

    /// 用户明确确认「彻底删除」：执行删除。未经过两步确认时被忽略（fail-closed）。
    func confirmFinalDeletion() async {
        guard phase == .awaitingFinalConfirmation else { return }
        phase = .deleting
        lastReport = await deletion()
        phase = .finished
    }
}
