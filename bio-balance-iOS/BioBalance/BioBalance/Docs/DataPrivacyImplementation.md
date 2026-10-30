# 数据导出与删除（隐私合规：健康数据红线）实现说明

任务：PEN-79。实现 iOS 端「导出我的数据 / 删除我的数据」，满足健康数据隐私红线。

## 1. 现状盘点（盘点结论）

实现前项目没有统一的用户数据导出 / 删除入口。逐项盘点：

| 能力 | 现状 | 缺口 |
|---|---|---|
| 本地数据导出 | 无任何导出入口；仅 `TrendCategoryDetailView` 有单指标 CSV 导出（体重等） | 无「导出我的数据」整体入口 |
| 本地数据删除 | `AppDataCacheManager` 只清缓存；各业务 Store 只有单条删除（如 `MedicationPrescriptionStore.delete`、`CountdownStore.delete`） | 无一次性删除全部本地 SwiftData 的入口 |
| CloudKit 删除 | `PregnancyCloudKitRepository.deleteAllPregnancyData()` 可整区删除但无 UI；`CloudKitSharingService.stopSharing()` 可删好友共享 zone；无公开资料删除 | 无覆盖全部私有 zone 的统一删除；无 tombstone 语义说明 |
| 二次确认 | 仅「恢复默认」类弹窗 | 删除/导出前无统一二次确认 |
| 日志脱敏 | CloudKit 仓储统一走结构化日志上下文（只记 op/zone/recordID） | 导出/删除路径需同样约束 |

SwiftData 本机业务域（`Core/Persistence/BioBalanceModelContainer.swift` 统一入口）：`caffeine-dose` / `mood` / `action-day` / `mental-assessment` / `drink-experience` / `period` / `medication-health` / `medication-prescription` / `countdown` / `shared-todo` / `recovery-challenge` / `daily-wellness` / `goals` / `daily-health-snapshot` / `daily-recovery-orchestration` / `daily-recovery-cooldown` / `care-task`，另有内部基础设施域 `local-sync-outbox` / `app-data-cache`。

CloudKit 私有 zone（`CloudKitDataPolicy.Zone`）：`BioBalanceDrinkExperienceZone` / `BioBalanceSleepZone` / `BioBalanceMedicationHealthZone` / `BioBalancePregnancyZone` / `BioBalanceMascotZone` / `BioBalanceOnboardingPreferenceZone`，加上好友共享 zone `FriendHealthShareZone` 与公开库 `UserProfile`。

## 2. 实现范围

### 2.1 导出

- 入口：设置页「数据与隐私 → 导出我的数据 / 删除我的数据」→ 数据管理页。
- 读取本机 SwiftData 全部业务记录（`SwiftDataRecordStore.allRecords()`），按域白名单投影：
  - 白名单定义在 `UserDataPrivacyRegistry.exportWhitelist(for:)`，**只导出白名单 ∩ 实际字段**（fail-closed）。
  - 不导出：自由文本（note/备注/指令）、图片/文件引用（photoURL/cutoutURL）、精确位置（latitude/longitude/locationLabel）、HealthKit 样本引用、AI 元数据。
  - 敏感聚合域（`period` / `daily-health-snapshot` / `shared-todo`）只导出元数据（计数 + 时间范围 + 更新时间戳），不导出明细。
- 格式：JSON（分层：`domains[domain].records[].fields`）与 CSV（统一列：domain/kind/recordID/occurredAt/updatedAt + 白名单扁平标量列）。
- 输出：临时目录生成文件后走系统分享面板（`UIActivityViewController`），支持「存储到文件」与分享。
- 日志脱敏：`UserDataPrivacyLogger` 只记录 format/domains/records 数量，不记录任何 payload 内容。

### 2.2 删除

- 入口：数据管理页「删除我的数据」，**二次确认**（第一个弹窗说明范围 → 第二个弹窗最终确认）。
- 本地：`SwiftDataRecordStore.clearAll()` 清空全部 `LocalDataRecord`（含内部域）。
- CloudKit（`CloudKitUserDataDeleter`）：
  - 6 个私有 zone：逐 record type 全量查询 recordID，按 200 条一批调用
    `CKModifyRecordsOperation`（`modify(recordsToSave: [], recordIDsToDelete:)`）删除。
  - 好友共享 zone：复用 `CloudKitSharingService.stopSharing()`（删除 zone 同时撤销 CKShare）。
  - 公开资料 `UserProfile`：按 `ownerUserRecordName` 尽力查询并删除，失败不阻塞（公开资料非健康红线）。
  - iCloud 不可用：逐 zone 标记 `unavailable`，本地删除仍继续，提示用户登录后重试（删除幂等）。
- 删除顺序：先云端后本地，防止本地残留重新上传复活；删除窗口内临时关闭同步开关，结束后恢复用户原有偏好。
- 删除后刷新 Widget 投影（`WidgetSyncService.refresh`）。

### 2.3 last-write-wins 下的删除语义（tombstone vs 直接删除）

- 私有 zone 是「单写者 + 单所有者」：只有当前 Apple ID 能写，其他设备/用户不会凭空恢复已删除记录，
  因此采用**直接删除（hard delete）**。
  - 优点：云端不残留任何业务 payload（配合日志脱敏，真正“数据消失”），实现与验证都简单。
  - 代价：删除时若 iCloud 不可用没有离线 pending 队列，只能标记 `unavailable` 由用户重试；
    重试幂等安全。
- **tombstone（软删除标记）只在多写者协作场景才有意义**：防止另一台设备用旧快照（last-write-wins）
  把已删除记录重新写回。当前私有域不满足该前提（无共享写入），使用 tombstone 只会让云端保留
  删除标记，反而违背“数据消失”的目标。若未来某个域接入 CKSyncEngine 多写者增量同步或协作待办
  可写共享，再为该域引入 tombstone 语义（`LocalSyncOutbox` 已预留 tombstone 枚举）。

## 3. 边界（硬约束）核对

- Bundle ID `com.boundesu.BioBalance`、CloudKit 容器 `iCloud.com.boundesu.BioBalance`、
  App Group `group.com.biobalance.shared`：未改动。
- 健康原始数据/明细不上云、不导出明文：白名单 fail-closed，健康明细与自由文本被过滤。
- 文字不加动效：数据管理页全部静态文本，无任何动画/动效。
- 同步方向 iCloud/CloudKit：删除复用 `CloudKitDataPolicy.makeContainer()`，不依赖 Java 后端。
- 导出/删除为破坏性操作：删除二次确认 + 文案说明；导出文件为白名单投影。

## 4. 新增 / 修改文件

- 新增 `Core/Privacy/UserDataPrivacyModels.swift`：域注册表、导出白名单、审计/导出/删除结果类型、脱敏日志。
- 新增 `Core/Privacy/UserDataAuditService.swift`：本机 SwiftData + CloudKit 开关盘点。
- 新增 `Core/Privacy/UserDataExportService.swift`：JSON/CSV 导出（白名单投影）。
- 新增 `Core/Privacy/UserDataDeletionService.swift`：本地 + CloudKit 删除编排与逐 zone 执行器。
- 新增 `Views/Profile/Settings/DataPrivacyManagementView.swift`：数据管理页（概览/导出/删除）。
- 修改 `Views/Profile/Settings/SettingsView.swift`：新增「数据与隐私」入口。
- 修改 `Core/Persistence/BioBalanceModelContainer.swift`：新增 `allRecords()` / `clearAll()`。
- 新增测试 `BioBalanceTests/Privacy/UserDataPrivacyTests.swift`。

## 5. 验证

- 模拟器 Debug 构建通过（`xcodebuild -scheme BioBalance -destination 'generic/platform=iOS Simulator' build`）。
- 新增隐私测试 8/8 通过；既有 `SwiftDataPersistenceTests` 8/8、`CloudKitDataPolicyTests` 9/9 通过。
- 真机/签名验证（CloudKit 实际删除、CKShare 撤销、公开资料清理）需要登录 iCloud 的签名设备，
  由测试与构建验证环节安排。
