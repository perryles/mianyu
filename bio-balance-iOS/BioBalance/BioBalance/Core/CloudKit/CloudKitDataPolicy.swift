import CloudKit
import Foundation

/// CloudKit 的全局数据边界、稳定标识与整体数据设计的唯一事实来源。
///
/// ## 三层数据职责（互相不可替代）
/// - `UserDefaults.standard` / 本地 Store：可离线工作的业务真值，是所有功能的基准；
/// - App Group：只保存同设备 extension（Widget / Watch / 灵动岛）消费的短期投影；
/// - CloudKit：只负责可选的跨设备恢复，以及用户显式授权的好友共享。
///
/// ## 数据库边界（对应 `CloudKitDatabaseScope`）
/// - `private`：当前 Apple ID 私有库，用于个人数据的跨设备恢复；
/// - `shared`：CKShare 参与者可见，必须由用户主动邀请 / 接受；
/// - `public`：容器内所有用户可查询，只能放公开资料，**禁止任何健康数据**。
///
/// ## Zone 划分原则
/// 每个功能独占一个 private zone（见 `Zone`），使用户删除单个功能的云数据时
/// 只需清空对应 zone，而不会波及其他 iCloud 功能。因此新增 CloudKit 仓储时
/// **必须**在此登记新的 zone / record type，而不是把不同功能塞进同一个巨大 zone。
///
/// ## 同步偏好边界
/// 餐饮、睡眠、药物/处方、孕期、吉祥物与社交共享默认开启。药症资料只包含
/// 人工确认后的最小结构化字段。所有同步均可在设置中关闭，已保存的用户选择优先于默认值。
///
/// ## 平台演进备忘（iOS 18.6+ / Swift 6.4）
///
/// 1. **Swift 6.4 `@specialized` 与 Sendable 改进**
///    编译器对泛型 async 函数的 Sendable 推断更严格且更精准，现有
///    `CloudKitOperationExecutor.run<T>` 和各仓储的 `@Sendable` 闭包已自动受益。
///    新增仓储或泛型工具时应启用 strict concurrency 检查（`-strict-concurrency=complete`），
///    确保不再依赖 `@unchecked Sendable` 逃生阀。
///
/// 2. **Foundation Models on Private Cloud Compute (PCC) · iCloud+ 配额体系**
///    PCC 模型调用计入 iCloud+ 用户日配额，但 **不影响 CloudKit 数据层**。
///    CloudKit 私有库的存储配额和请求限流与 PCC 完全独立；应用内如果同时使用
///    Foundation Models 和 CloudKit 同步，两者不会互相挤占。
///
/// 3. **CKSyncEngine（iOS 17+）——增量同步 / 离线冲突解决的备选架构（已实现抽象层）**
///    当前各仓储采用 "全量拉取 + last-write-wins 合并" 模式，足够满足现有数据量（≤数百条
///    per zone）。如果未来某个域的记录量显著增长或需要离线冲突自动解决，可将该域的
///    仓储迁移至 `CKSyncEngine`，获得增量变更推送、冲突回调和断点续传能力。
///
///    **启用方式（per-zone 独立控制）：**
///    ```swift
///    CloudKitSyncTransportResolver.enableSyncEngine(forZone: CloudKitDataPolicy.Zone.drinkExperience)
///    ```
///    启用后下次仓储初始化时自动切换 transport；zone / record type 保持不变（已在此注册），
///    仅替换底层同步逻辑。详见 `CloudKitSyncEngineTransport.swift`。
///
/// 新增 CloudKit 仓储时必须复用这里的容器、zone 名、record type 名与元数据字段，
/// 保证 CloudKit Dashboard 中部署的 schema 与代码始终一致。
nonisolated enum CloudKitDataPolicy {
    /// 必须与 `BioBalance.entitlements` 的 iCloud container 完全一致。
    static let containerIdentifier = "iCloud.com.boundesu.BioBalance"

    static func makeContainer() -> CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    /// 注册缺省偏好，不覆盖用户已保存的选择。
    static func registerDefaultPreferences(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            PreferenceKey.drinkExperienceSyncEnabled: true,
            PreferenceKey.sleepSummarySyncEnabled: true,
            PreferenceKey.medicationHealthSyncEnabled: true,
            PreferenceKey.pregnancySyncEnabled: true,
            PreferenceKey.goalMascotSyncEnabled: true,
            PreferenceKey.onboardingPreferenceSyncEnabled: true,
            PreferenceKey.socialSharingEnabled: true
        ])
    }

    /// 跨设备同步的用户控制开关。
    nonisolated enum PreferenceKey {
        /// 餐饮结构化摘要跨设备同步，默认开启且可随时关闭。
        static let drinkExperienceSyncEnabled = "icloud.drink-experience-sync.enabled"

        /// 睡眠摘要跨设备同步，默认开启且可随时关闭。
        static let sleepSummarySyncEnabled = "icloud.sleep-summary-sync.enabled"

        /// 处方、药物和病症只同步用户人工确认后的结构化字段，默认开启且可随时关闭。
        static let medicationHealthSyncEnabled = "icloud.medication-health-sync.enabled"

        /// 孕期档案、体重和胎动记录的私有库同步。
        static let pregnancySyncEnabled = "icloud.pregnancy-sync.enabled"

        /// 目标吉祥物档案和 XP 事实的私有库同步。
        static let goalMascotSyncEnabled = "icloud.goal-mascot-sync.enabled"

        /// 首次引导中用户主动确认的基础资料、关注领域和健康目标。
        static let onboardingPreferenceSyncEnabled = "icloud.onboarding-preference-sync.enabled"

        /// 好友资料发现、健康摘要邀请和协作待办共享总开关。
        static let socialSharingEnabled = "icloud.social-sharing.enabled"
    }

    /// 记录上次成功同步的 CloudKit 用户，防止本机数据在 Apple ID 切换后自动
    /// 上传到另一个账号。它们不是用户偏好，只有一次成功的对应域同步才能建立。
    ///
    /// 检测流程：sync 前取 `fetchUserRecordID().recordName`，与本 key 存储值对比；
    /// 如不匹配则中止上传、清除绑定并关闭该域的自动同步，直到用户手动重新开启。
    nonisolated enum AccountBindingKey {
        static let drinkExperience = "drinkExperienceStore.cloud-account.v1"
        static let sleepSummary = "sleep.monitoring.cloud-account.v1"
        static let medicationHealth = "icloud.medication-health-sync.account.v1"
        static let goalMascot = "goals.store.mascot.cloud-account.v1"
        static let onboardingPreference = "onboarding.preference.cloud-account.v1"
        static let socialSharing = "social.sharing.cloud-account.v1"
    }

    /// 所有 record 共享的稳定元数据字段名，供跨设备合并与审计使用。
    ///
    /// - `schemaVersion`：写入时的 schema 版本号，供未来做前向兼容迁移；
    /// - `createdAt` / `updatedAt`：业务时间戳，`updatedAt` 用于 last-write-wins 合并；
    /// - `deletedAt`：软删除标记（仅在需要保留删除历史的仓储使用）；
    /// - `source`：写入来源标签（如设备类型），仅用于诊断，禁止承载敏感明细。
    nonisolated enum MetadataField {
        static let schemaVersion = "schemaVersion"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let deletedAt = "deletedAt"
        static let source = "source"
    }

    /// 各功能独占的 record zone 名称。一个功能一个 zone，保证可独立删除。
    ///
    /// 除 `friendHealthShare` 位于可共享 zone 外，其余均为当前 Apple ID 的
    /// private zone。**禁止**多个功能复用同一 zone 名，否则无法独立清除数据。
    nonisolated enum Zone {
        /// 私有库 · 用户可控。餐饮 / 餐食的最小结构化记录（不含图片、位置、AI 元数据）。
        static let drinkExperience = "BioBalanceDrinkExperienceZone"

        /// 私有库 · 用户可控。睡眠会话摘要（不含音频、打鼾片段、详细阶段、自然语言分析）。
        static let sleep = "BioBalanceSleepZone"

        /// 私有库 · 默认开启。人工确认后的处方、药物与病症结构化资料。
        static let medicationHealth = "BioBalanceMedicationHealthZone"

        /// 私有库。孕期档案、体重与胎动记录；删除孕期数据即删除整个 zone。
        static let pregnancy = "BioBalancePregnancyZone"

        /// 私有库。目标吉祥物档案与追加型 XP 奖励事实。
        static let goalMascot = "BioBalanceMascotZone"

        /// 私有库。首次引导偏好与基础资料，不包含 HealthKit 样本。
        static let onboardingPreference = "BioBalanceOnboardingPreferenceZone"

        /// 可共享 zone。承载好友只读 CKShare 的健康摘要与共享待办。
        static let friendHealthShare = "FriendHealthShareZone"
    }

    /// 稳定的 record type 名称，必须与 CloudKit Dashboard 部署的 schema 完全一致。
    ///
    /// 修改任何字符串都等同于新建 record type，会导致老数据无法读取，
    /// 因此只允许新增、不允许重命名已上线的类型。
    nonisolated enum RecordType {
        // MARK: private 数据库同步

        /// 餐饮 / 餐食记录（`Zone.drinkExperience`）。
        static let drinkExperience = "BBDrinkExperience"

        /// 睡眠会话摘要（`Zone.sleep`）。
        static let sleepSession = "BBSleepSession"

        /// 人工确认后的处方资料（`Zone.medicationHealth`）。
        static let medicationPrescription = "BBMedicationPrescription"

        // MARK: private 数据库 · 孕期（`Zone.pregnancy`）

        static let pregnancyProfile = "BBPregnancyProfile"
        static let pregnancyWeightEntry = "BBPregnancyWeightEntry"
        static let fetalMovementEntry = "BBFetalMovementEntry"

        // MARK: private 数据库 · 目标吉祥物（`Zone.goalMascot`）

        static let goalMascotProfile = "BBMascotProfile"
        static let goalMascotXPGrant = "BBMascotXPGrant"

        /// 当前用户的首次引导偏好单例记录（`Zone.onboardingPreference`）。
        static let onboardingPreference = "BBOnboardingPreference"

        // MARK: shared 数据库 · 好友共享（`Zone.friendHealthShare`，只读 CKShare）

        /// CKShare 的根记录，聚合健康摘要与共享待办的引用。
        static let healthShareRoot = "HealthShareRoot"
        static let collaborativeTodoList = "CollaborativeTodoList"
        static let collaborativeTodoItem = "CollaborativeTodoItem"

        // MARK: public 数据库 · 仅公开资料（禁止健康数据）

        /// 可被搜索的公开昵称 / 头像资料，用于好友发现。
        static let userProfile = "UserProfile"
    }

    // MARK: - CKSyncEngine 迁移配置

    /// CKSyncEngine 状态持久化的 UserDefaults key。
    ///
    /// CKSyncEngine 需要保存 `State.Serialization` 以实现断点续传；
    /// 每个 zone 一个 key，避免跨域污染。
    nonisolated enum SyncEngineStateKey {
        static let drinkExperience = "ck-sync-engine.state.drinkExperience.v1"
        static let sleep = "ck-sync-engine.state.sleep.v1"
        static let medicationHealth = "ck-sync-engine.state.medicationHealth.v1"
        static let pregnancy = "ck-sync-engine.state.pregnancy.v1"
        static let goalMascot = "ck-sync-engine.state.goalMascot.v1"
    }

    /// 为指定域生成 CKSyncEngine 的标准 zone 配置。
    ///
    /// 返回的配置保证 zone 名和 record type 与已部署 schema 完全一致，
    /// 仅替换底层 transport 而不影响数据格式。
    static func syncEngineConfig(
        forZone zoneName: String,
        recordTypes: [String],
        conflictPolicy: CloudKitSyncConflictPolicy = .lastWriteWins
    ) -> CloudKitSyncEngineZoneConfig {
        let stateKey: String
        switch zoneName {
        case Zone.drinkExperience: stateKey = SyncEngineStateKey.drinkExperience
        case Zone.sleep: stateKey = SyncEngineStateKey.sleep
        case Zone.medicationHealth: stateKey = SyncEngineStateKey.medicationHealth
        case Zone.pregnancy: stateKey = SyncEngineStateKey.pregnancy
        case Zone.goalMascot: stateKey = SyncEngineStateKey.goalMascot
        default: stateKey = "ck-sync-engine.state.\(zoneName).v1"
        }

        return CloudKitSyncEngineZoneConfig(
            zoneName: zoneName,
            recordTypes: recordTypes,
            conflictPolicy: conflictPolicy,
            stateSerializationKey: stateKey
        )
    }

    /// 公开资料记录与 CloudKit 系统 `Users` 记录共存于公开默认区域。
    /// 随机业务 ID 可避免系统记录冲突和确定性 ID 抢占；只有所有者字段与 CloudKit
    /// 只读的创建者系统字段一致时，才能信任该所有者字段。
    nonisolated enum PublicProfile {
        static let recordNamePrefix = "profile."
        static let ownerUserRecordNameField = "ownerUserRecordName"

        static func recordName(id: UUID = UUID()) -> String {
            recordNamePrefix + id.uuidString.lowercased()
        }

        static func validatedOwnerUserRecordName(
            profileRecordName: String,
            declaredOwnerUserRecordName: String?,
            creatorUserRecordName: String?
        ) -> String? {
            guard let declaredOwnerUserRecordName,
                  !declaredOwnerUserRecordName.isEmpty,
                  creatorUserRecordName == declaredOwnerUserRecordName,
                  profileRecordName.hasPrefix(recordNamePrefix),
                  UUID(uuidString: String(profileRecordName.dropFirst(recordNamePrefix.count))) != nil else {
                return nil
            }
            return declaredOwnerUserRecordName
        }
    }
}
