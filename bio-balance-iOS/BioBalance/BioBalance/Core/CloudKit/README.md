# Core / CloudKit

本目录是 Bio Balance 的 CloudKit 基础设施层，负责统一数据边界、SDK 访问、错误处理、重试和可选的增量同步。业务模块应在自己的 Repository 中完成模型与 `CKRecord` 的转换，不要绕过本层直接散落 CloudKit 操作。

CloudKit Dashboard 部署、真机验收、故障恢复和发布门禁见 [`Docs/CloudKitOperationsRunbook.md`](../../Docs/CloudKitOperationsRunbook.md)。

## 文件职责

| 文件 | 职责 |
|---|---|
| `CloudKitDataPolicy.swift` | 容器标识、数据库边界、Zone、Record Type、元数据字段、同步偏好和账号绑定 Key 的唯一事实来源 |
| `CloudKitSupport.swift` | 领域错误、重试策略、结构化日志、`CloudKitClientProtocol` 与系统 SDK 默认实现 |
| `CloudKitSyncEngineTransport.swift` | iOS 17+ 的可选 `CKSyncEngine` 增量同步传输层、冲突策略和按 Zone 的迁移开关 |
| `ICloudSyncCoordinator.swift` | 账户状态检查、同步偏好判定、启动/手动同步编排与结果汇总 |

## 分层与依赖方向

CloudKit 的“核心能力”放在本目录，但界面不属于核心层。正确依赖方向为：

```text
Views/Profile/Settings/ICloudManagementView
                ↓
Core/CloudKit/ICloudSyncCoordinator
                ↓
Feature Store / Feature Repository
                ↓
Core/CloudKit/CloudKitSupport
                ↓
           Apple CloudKit SDK
```

- `ICloudManagementView` 只负责展示账户状态、开关、进度与结果，不得直接读写 `CKRecord`。
- `ICloudSyncCoordinator` 只做跨业务域编排，不复制业务模型的合并规则。
- 餐饮、睡眠、药物、孕期、吉祥物和社交的 Repository 仍留在各自 Feature 目录。
- `CloudKitDataPolicy` 是所有稳定字符串与默认偏好的唯一事实来源，View 和 Repository 不得自行声明 Key。

## 数据边界

- 本地 Store / `UserDefaults.standard`：离线业务真值。CloudKit 失败不得阻断本地保存和展示。
- App Group：仅用于同设备 App、Widget、Watch 与 Live Activity 的短期投影。
- CloudKit private database：当前 Apple ID 的可选跨设备恢复。
- CloudKit shared database：必须由用户显式邀请或接受的共享数据。
- CloudKit public database：只能保存公开资料，严禁健康数据、症状、用药、睡眠明细或可推导的敏感摘要。

当前容器为 `iCloud.com.boundesu.BioBalance`，必须与主 App entitlement 和 CloudKit Dashboard 保持一致。

## 当前同步项与默认值

`BioBalanceApp.init()` 会先调用 `CloudKitDataPolicy.registerDefaultPreferences()`。`UserDefaults.register(defaults:)` 只提供缺省值，不会覆盖用户已保存的选择。

| 同步域 | Preference Key | 默认 | 启动自动同步 | 手动“全部同步” |
|---|---|---:|---:|---:|
| 餐饮结构化记录 | `icloud.drink-experience-sync.enabled` | 开 | 是 | 是 |
| 睡眠摘要 | `icloud.sleep-summary-sync.enabled` | 开 | 是 | 是 |
| 药物、处方与病症 | `icloud.medication-health-sync.enabled` | 开 | 是 | 是 |
| 孕期档案、体重与胎动 | `icloud.pregnancy-sync.enabled` | 开 | 否，按需加载 | 是 |
| 吉祥物档案与 XP | `icloud.goal-mascot-sync.enabled` | 开 | 是 | 是 |
| 好友健康摘要与协作共享 | `icloud.social-sharing.enabled` | 开 | 是 | 是 |

孕期域保持按需加载，避免每次 App 启动都访问尚未使用的孕期 Zone。进入孕期功能或在 iCloud 管理页手动同步时再读取。

## 管理页与同步流程

入口位于“我的 → iCloud 管理”，View 文件为 `Views/Profile/Settings/ICloudManagementView.swift`。

### App 启动

1. 注册六个同步域的默认偏好。
2. 完成 HealthKit、登录和订阅恢复。
3. 调用 `synchronizeEnabledDomains(includePregnancy: false)`。
4. 协调器先检查 `CKAccountStatus`；账户不可用时不调用任何业务同步。
5. 按偏好顺序调用各 Feature Store / Repository。CloudKit 失败不影响本地数据使用。

### 用户打开单项开关

View 调用 `ICloudSyncCoordinator.synchronize(_:)`。协调器会再次确认偏好已开启，然后只调度该业务域。关闭开关不会自动删除云端数据。

### 用户手动同步

View 调用 `synchronizeEnabledDomains(includePregnancy: true)`。返回的 `ICloudSyncReport` 包含账户状态、成功数和失败数，界面应显示真实结果，不得在未检查结果时统一提示“同步成功”。

`requested` 表示 Feature Store 已接受同步请求，但它的内部延迟任务尚未返回服务器最终结果；当前吉祥物同步属于此类。

## 同步模式

默认使用 Legacy 模式：Repository 通过 `CloudKitOperationExecutor` 与 `CloudKitClientProtocol` 执行查询和写入，适合每个 Zone 数百条以内的数据。

记录量明显增长、需要断点续传或增量变更时，可按 Zone 启用 `CKSyncEngine`：

```swift
CloudKitSyncTransportResolver.enableSyncEngine(
    forZone: CloudKitDataPolicy.Zone.drinkExperience
)
```

切换在 Repository 下次初始化时生效。回退方式：

```swift
CloudKitSyncTransportResolver.disableSyncEngine(
    forZone: CloudKitDataPolicy.Zone.drinkExperience
)
```

不要同时让 Legacy 与 SyncEngine 对同一 Zone 执行写入。迁移不允许修改既有 Zone、Record Type 或稳定 Record ID。

## 新增 CloudKit 业务域

1. 在 `CloudKitDataPolicy.Zone` 添加独占 Zone；不要与其他功能共用。
2. 在 `CloudKitDataPolicy.RecordType` 添加稳定类型；上线后只增不改。
3. 如需 SyncEngine，在 `SyncEngineStateKey` 和 `syncEngineConfig` 中登记状态 Key。
4. 为敏感数据增加显式同步偏好，并定义账号绑定 Key。
5. Repository 通过 `CloudKitClientProtocol` 访问 CloudKit，并使用 `CloudKitOperationExecutor.run` 统一映射错误与有限重试。
6. Record 至少写入 `schemaVersion`、`createdAt` 和 `updatedAt`；冲突合并依赖 `updatedAt`。
7. 使用稳定且可幂等的 Record ID，删除策略必须明确是硬删除还是带 `deletedAt` 的软删除。
8. 在 `ICloudSyncDomain` 登记领域与 Preference Key，并在 `ICloudSyncCoordinator.synchronize(_:)` 接入业务同步入口。
9. 在 `ICloudManagementView` 增加开关和对应的启用回调；View 不得直接调用 Repository。
10. 添加 Policy、默认偏好、编码兼容、账号切换、冲突和离线降级测试。
11. 在 Development 环境验证后，将 Schema 部署到 Production；TestFlight 与 App Store 不读取 Development Schema。

## Repository 接入示例

```swift
let context = CloudKitLoggerContext(
    operation: "saveDrinkExperience",
    database: .private,
    zoneID: CloudKitDataPolicy.Zone.drinkExperience,
    recordID: record.recordID.recordName
)

let saved = try await executor.run(context: context) {
    try await client.save(record: record, in: container.privateCloudDatabase)
}
```

日志上下文只能包含技术标识，不要写入标题、备注、症状、药名或健康数值。

## CKSyncEngine 使用约束

- 每个 Transport 实例只接受配置 Zone 和 Record Type 的事件。
- Repository 必须维护本地 Outbox，并实现 `CloudKitSyncEngineEventHandler`。
- 本地变更后调用 `scheduleSend(recordIDs:)`；可提供稳定 ID，也可留空让 Transport 从 Outbox 登记待处理项。
- 本地删除后调用 `scheduleDelete(recordIDs:)`。
- `initialize()` 是幂等的；损坏的序列化状态会被清除并安全执行 initial sync。
- Apple ID 登出或切换时会清理同步状态和对应账号绑定，敏感域同步会关闭，必须由用户重新确认。
- 当前采用 per-zone 引擎；同时启用超过三个 Zone 时，应改为单一共享引擎加 Zone 路由。

## 冲突策略

- `lastWriteWins`：按业务字段 `updatedAt` 选择新版本。
- `mergeFields`：数值取大、日期取新，其他字段按整体 `updatedAt` 选择。只适用于字段确实满足该语义的模型。
- `askDelegate`：由业务 Repository 决定。用于追加事实、复合对象或不能机械合并的数据。

不要对剂量、症状强度等字段默认使用“数值取大”；此类数据应采用稳定事件 ID 或业务代理处理冲突。

## 隐私与账号安全

- 最小化上传字段，不同步图片、音频、自由文本、位置和 AI 原始上下文，除非产品另有清晰授权。
- 私有库不等于无需授权；敏感同步开关必须尊重用户选择。
- 每次上传前校验当前 CloudKit 用户与本地账号绑定，防止 Apple ID 切换后把旧本地数据上传到新账号。
- 退出登录、关闭同步和删除账号必须定义本地数据、云端 Zone、共享数据三者各自的处理方式。
- 好友共享遵循最小可见范围、可撤回和只读优先原则。

### 关闭同步与删除数据的区别

- 关闭开关：停止后续自动同步，保留本地与已有云端数据。
- 重新开启：立即请求该业务域同步，再由 Feature 的冲突规则合并。
- 删除云端数据：必须是独立的明确操作，需要二次确认，且只删除选定业务域的 Zone。
- 删除共享数据：需同时处理 `CKShare` 和参与者关系，不能等同于删除 private Zone。

当前管理页只提供同步开关和手动同步，尚未提供通用的“删除各域云端数据”入口。在各 Repository 完成可验证的 per-zone 删除接口前，不应在 UI 中放置看似可用的清理按钮。

## 测试与排障

相关测试：

- `CloudKitDataPolicyTests.swift`
- `CKSyncEngineTransportTests.swift`
- `SleepCloudKitSyncTests.swift`
- `SocialSharingPermissionTests.swift`

建议优先检查：

1. iCloud 账号状态以及 App 的 iCloud entitlement。
2. 容器标识、环境（Development / Production）和 Schema 是否一致。
3. Zone、Record Type 与索引是否已部署。
4. 同步偏好与账号绑定是否因账号切换被关闭。
5. 管理页报告的成功/失败数，以及是否只是 `requested` 状态。
6. `com.boundesu.BioBalance / CloudKit` 和 `SyncEngine` 分类日志。
7. 限流错误的 `retryAfter`、配额、权限、冲突与 Zone 被删除情况。

运行核心测试：

```sh
xcodebuild test \
  -project BioBalance.xcodeproj \
  -scheme BioBalance \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BioBalanceTests/CloudKitDataPolicyTests \
  -only-testing:BioBalanceTests/CKSyncEngineTransportTests
```

真机或 CloudKit 集成测试不可替代 Stub 单元测试；账号切换、共享接受、Production Schema 和 silent push 必须在真实环境单独验收。
