# 鸿蒙端架构与数据层说明（PEN-9）

本文档说明「眠屿」鸿蒙端（`bio-balance-Harmony`）的工程分层、页面路由、数据流与本机数据层，
并对照 iOS 端（`bio-balance-iOS`）的架构取向。健康数据隐私边界（只读不写不删、仅本机、不上传）
是硬性约束，任何实现不得放宽；健康数据接入与隐私边界的完整盘点见
`DATA_PRIVACY_ALIGNMENT.md`（PEN-11），AGC / 签名 / 权限配置见 `AGC_CONFIG.md`（PEN-8）。

## 1. 总体分层

| 层 | 目录 | 职责 |
|---|---|---|
| 入口 | `entry/src/main/ets/entryability/EntryAbility.ets` | Stage 模型 UIAbility，`onWindowStageCreate` 加载 `pages/Index` |
| 备份扩展 | `entry/src/main/ets/entrybackupability/EntryBackupAbility.ets` | 系统备份扩展；`backup_config.json` 为 `allowToBackupRestore: false`（不参与系统云备份/恢复） |
| 页面 | `entry/src/main/ets/pages/` | ArkUI 页面：`Index`（四 Tab 主界面）+ 4 个详情页 |
| 模型 | `entry/src/main/ets/model/` | 本地业务逻辑与存储：`HealthScoreEngine`（纯计算）、`HealthSyncPolicy`（健康逐域合并策略）、`CheckinRecordStore`（Preferences 存储） |
| 服务 | `entry/src/main/ets/service/` | 系统能力封装：Health Service Kit 只读、提醒/通知、华为账号、Preferences outbox 与 AGC Cloud DB |

依赖方向：`pages → model / service`。`service` 只封装系统能力（Health Service Kit、提醒/通知、
Preferences），`model` 保存纯策略。唯一网络边界是 `AgcCloudSyncTransport` 对华为 AGC Cloud DB 的调用；
工程不依赖 Java 后端，也不直接使用 `http`/`fetch`/`axios`/`rpc`。

## 2. 页面与路由

`entry/src/main/resources/base/profile/main_pages.json` 注册 5 个页面：

| 页面 | 文件 | 说明 |
|---|---|---|
| 首页 | `pages/Index.ets` | 四 Tab 主界面（首页 / 记录 / 趋势 / 我的），`selectedTab` 切换 |
| 睡眠详情 | `pages/SleepDetailPage.ets` | 近 7 天时长/评分 + 最近一晚分期（深睡/浅睡/REM/清醒） |
| 每日记录详情 | `pages/CheckinDetailPage.ets` | 日照/咖啡因/用药/症状记录增删（按 `router` 参数 `type` 区分） |
| 提醒设置 | `pages/ReminderSettingsPage.ets` | 喝水/用药/久坐提醒开关与时间 |
| 隐私与数据 | `pages/PrivacyPage.ets` | 权限用途、读取范围、数据边界与云同步白名单说明 |
| 账号与云同步 | `pages/AccountSyncPage.ets` | 华为账号登录、显式同步开关、手动同步与白名单说明 |

页面跳转使用 `this.getUIContext().getRouter().pushUrl({ url: 'pages/...', params })`。

## 3. 数据流

### 3.1 健康数据：Health Service Kit → 内存 → UI

`HuaweiHealthService` 分别检查步数、静息心率和睡眠授权；部分授权时只调用已授权类型。
`readTodaySnapshot()` 为每个域返回独立的 `attempted/success/errorCode`，并读取：

- **步数**：`aggregateData(dailyActivities)`，近 7 天按日聚合（`sum`）；
- **静息心率**：`readData(restingHeartRate)`，近 7 天每日最新值；
- **睡眠**：`readData(sleepRecord)`（`withDetails = true`），近 7 天时长/评分 + 最近一晚
  深睡/浅睡/REM/清醒分期（仅内存聚合，不落盘）。

快照只在内存持有，`HealthSyncPolicy` 仅合并读取成功的域，供首页、睡眠详情页、趋势页展示。
真实零值属于成功读取，会正常替换旧值；读取失败的域保留既有内存状态，不更新时间，也不冒充
“已同步”。**静息心率、睡眠时长/评分、睡眠分期不写入任何持久化**，每次启动重新读取；
仅当步数域读取成功时，才把「每日聚合值」随当日状态写入本机 Preferences
（`bio_balance_local_state`，非原始样本），失败时保留原值。

### 3.2 每日记录：CheckinRecordStore → Preferences

`CheckinRecordStore` 管理日照/咖啡因/用药/症状四类记录，统一存于
`bio_balance_checkin_records` Preferences，按日期分 key（`sunlight_<date>` 等）。记录包含
用药名称/剂量与症状类型/强度等明细，**仅保存在本机，不上传**（未来云同步只允许白名单摘要，
见第 5 节）。

### 3.3 提醒：ReminderService → reminderAgentManager + Preferences

`ReminderService` 通过 `reminderAgentManager.publishReminder` 发布喝水/用药/久坐每日定时提醒；
开关与时间存 `bio_balance_reminders` Preferences，同时缓存已发布的 `reminderId`（开启时先取消
旧提醒再发布，关闭时取消并清除缓存）。提醒内容为固定文案，**不包含任何健康明细数值**。

### 3.4 每日状态与设置：Index.ets → Preferences

`Index.ets` 将当日状态（饮水杯数、心情、步数、今日行动、日期）与设置（步数目标、通知开关）
存于 `bio_balance_local_state` Preferences；启动时按日期 key 判断是否为新的一天，是则自动切换
到新的空记录。

## 4. 数据存储清单（本机 Preferences）

| Preferences 文件 | 写入方 | 键 | 内容 |
|---|---|---|---|
| `bio_balance_local_state` | `pages/Index.ets` | `date` / `waterCups` / `steps` / `hasSteps` / `mood` / `actionCompleted` / `notificationEnabled` / `dailyStepGoal` | 每日状态 + 步数每日聚合值/可用性 + 设置 |
| `bio_balance_checkin_records` | `model/CheckinRecordStore.ets` | `sunlight_<date>` / `caffeine_<date>` / `medication_<date>` / `symptom_<date>` | 日照分钟数；咖啡因/用药/症状记录 JSON 数组 |
| `bio_balance_reminders` | `service/ReminderService.ets` | `<key>_enabled` / `<key>_hour` / `<key>_minute` / `reminderId_<key>` | 提醒开关、时间与已发布 reminderId |

**仅内存、不落盘**：静息心率、睡眠时长/评分、睡眠分期、近 7 天健康序列（用于趋势页展示）。

## 5. 云同步流程与隐私红线

本地保存先完成；仅当用户已登录且显式开启同步时，`Index` 才通过 `CloudSyncPolicy.sanitize`
生成白名单摘要并写入 `bio_balance_cloud_sync` outbox。`CloudSyncCoordinator` 领取到期项目，
AGC upsert 成功后确认删除；可重试失败按服务端建议与指数退避中较大值延期，永久失败保留为
`permanent_failure` 并由 coordinator 返回失败状态。当前 AGC SDK 无服务端 change token/单调变更序列，
所以每轮从序列起点按 `(revision, 账号分区物理 recordId)` 全重叠稳定分页并去重；持久化 cursor 仅作
观测值、不作下一轮下界，可覆盖游标提交后迟到的同 revision/较小 ID。只有完整拉取成功才合并缓存。
冲突依次比较单调逻辑
`revision`、`deviceId`，设备 `updatedAt` 仅作元数据，不参与游标或冲突。同步先拉取推进逻辑时钟，
再对待发记录重定基；有本地 outbox 的记录不会被本轮远端合并覆盖。云失败不影响本地保存，
拉取失败也不会以空数组覆盖本地缓存。

1. **白名单上传**：仅允许每日步数/静息心率聚合、睡眠会话聚合、心情规则码、饮水、步数目标、
   通知开关及技术字段。原始样本、RR、睡眠 segment、用药/症状/自由文本、媒体、位置、AI 内容与
   凭据禁止上传。日志仅含 operation 与计数，不含健康值或用户文本。
2. **不参与系统云备份**：`entry/src/main/resources/base/profile/backup_config.json` 为
   `allowToBackupRestore: false`，应用数据整体不进入华为系统云备份/云恢复。
3. **云不是运行前提**：未授权、离线或健康服务异常时，本地记录与提醒继续可用；云端失败
   不得表现为本地保存失败。
4. **账号最小化与隔离**：Preferences 只持久化华为 OpenID 作为不透明账号键，不保存
   authorizationCode、ID token 或其他凭据。登录恢复、显式登录和退出都先绑定账号；账号变化会
   清空旧账号 cursor/逻辑时钟/云缓存/outbox、递增 generation、关闭同步并要求重新显式开启。
   coordinator 在拉取、推送、ACK/重试和游标提交前后复核账号与 generation，换号即中止本轮。
   Cloud DB 物理主键由不透明账号键与逻辑 recordId 组合，避免不同账号的同名摘要互相覆盖。
   每轮拉取前、拉取后及每次 push 前读取 Account Kit 当前 OpenID；transport 在 upsert 紧邻位置再次校验。
   不一致时原子绑定实际账号、清空旧同步状态并关闭同步。最终安全边界是 Cloud DB 服务端 ACL：
   create/update/read 仅允许认证 principal OpenID 等于记录 `accountId`；客户端检查负责提前拒绝，
   服务端规则负责封闭检查与 upsert 之间的系统级换号竞态。

## 6. 与 iOS 架构对照

| 维度 | iOS（`bio-balance-iOS`） | 鸿蒙（本工程） |
|---|---|---|
| 本地存储 | SwiftData + UserDefaults/AppGroup | Preferences（`@ohos.data.preferences`） |
| 健康数据源 | HealthKit（多类型，部分写回） | Health Service Kit（3 类，严格只读不写不删） |
| 云同步 | iCloud/CloudKit 增量同步 | AGC Cloud DB 增量同步（默认关闭、白名单、outbox/LWW） |
| 系统备份 | 参与系统级备份 | 不参与（`allowToBackupRestore: false`） |
| 跨端扩展 | Widget / Watch / Complication | 无（`deviceTypes` 声明 `phone` / `wearable`，Watch 端未实现） |
| 后端依赖 | 不依赖 Java 后端 | 不依赖 Java 后端 |

## 7. 验证方式

- **构建**：`hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon`（未签名时生成 unsigned HAP）。
- **本地单测**：`hvigorw ... test --no-daemon`，执行 `entry/src/test/LocalUnit.test.ets`
  （健康评分，以及无授权、部分授权、读取失败、真实零数据、旧数据保护用例），报告生成于
  `entry/.test/default/outputs/test/reports/`。
- **ohosTest**：`entry/src/ohosTest/` 目前仅有脚手架（`module.json5`），无用例；真机接入后
  在 DevEco Studio 运行 `entry` 测试配置。
