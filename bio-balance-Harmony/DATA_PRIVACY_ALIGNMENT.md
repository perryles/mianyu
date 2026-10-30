# 鸿蒙健康数据接入与隐私边界对齐（PEN-11）

最后核对：2026-08-07（仓库基线 `741e9cd`）

本文对应 PEN-11，盘点「眠屿」鸿蒙端（`bio-balance-Harmony`）健康数据接入与 iOS 端
（`bio-balance-iOS` / HealthKit）的读取范围与隐私边界，并给出备份收窄方案与未来云同步
字段白名单设计。隐私红线（健康数据最小化、日志脱敏、健康原始数据不上云）是硬性约束，
任何实现不得放宽。

## 1. 读取范围盘点与对齐矩阵

### 1.1 鸿蒙当前申请/读取（PEN-6：只读、不写、不删）

实现文件：`entry/src/main/ets/service/HuaweiHealthService.ets`

- 授权方式：Health Service Kit（`@kit.HealthServiceKit` / `healthStore`），
  AGC 联盟服务审批 + `client_id` + 运行时用户 OAuth 授权；
  `entry/src/main/module.json5` 不声明静态健康数据权限。
- `readDataTypes` 仅三类：
  1. 日常活动（`samplePointHelper.dailyActivities`）→ 步数（含近 7 天按日聚合）；
  2. 静息心率（`samplePointHelper.restingHeartRate`）→ 近 7 天每日最新值；
  3. 睡眠记录（`healthSequenceHelper.sleepRecord`，`readOptions.withDetails = true`）
     → 近 7 天时长/评分 + 最近一晚深睡/浅睡/REM/清醒分期（仅内存聚合，不落盘）。
- `writeDataTypes` 为空数组；全工程无 `saveData` / `deleteData` / 上传调用
  （对 `http` / `axios` / `@ohos.net` / `rpc` / `fetch` / `cloud` 的源码扫描无命中），
  即只读、不写、不删、不上传。
- 步数、静息心率、睡眠授权分别维护；部分授权时仅调用已授权域。读取结果按域返回
  `success/errorCode`，异常域不记录健康数值、不覆盖本机旧值，真实零数据则作为成功结果更新。

### 1.2 iOS 当前读取（HealthKit）

实现文件：`bio-balance-iOS/BioBalance/BioBalance/Core/Health/HealthKitManager.swift`
（`makeAuthorizationTypes()` 与各域 append 方法）。iOS 读取范围远大于鸿蒙，按域分组如下：

| 域 | iOS 读取的 HealthKit 类型（摘要） |
|---|---|
| 活动/身体测量 | StepCount、ActiveEnergyBurned、BasalEnergyBurned、AppleExerciseTime、AppleMoveTime、AppleStandTime、FlightsClimbed、各类 Distance/Running/Cycling/Swimming、VO2Max、PhysicalEffort、AppleWalkingSteadiness、SixMinuteWalkTestDistance 等 |
| 心率/心血管 | HeartRate、RestingHeartRate、HeartRateVariabilitySDNN（HRV）、WalkingHeartRateAverage、HeartRateRecoveryOneMinute、AtrialFibrillationBurden、PeripheralPerfusionIndex、BloodPressure*、ECG、HeartbeatSeries、High/LowHeartRateEvent、IrregularHeartRhythmEvent、HypertensionEvent 等 |
| 睡眠 | SleepAnalysis、AppleSleepingWristTemperature、AppleSleepingBreathingDisturbances、SleepApneaEvent |
| 呼吸 | RespiratoryRate、OxygenSaturation、PeakExpiratoryFlowRate、ForcedExpiratoryVolume1、ForcedVitalCapacity、InhalerUsage |
| 正念/心理 | MindfulSession、StateOfMind、GAD7/PHQ9 评估 |
| 环境声 | EnvironmentalAudioExposure、HeadphoneAudioExposure、EnvironmentalSoundReduction 及事件 |
| 营养/水分 | DietaryWater、DietaryCaffeine、全套 Dietary* 微量营养素、NumberOfAlcoholicBeverages |
| 身体测量 | BodyMass、Height、BodyMassIndex、BodyFatPercentage、LeanBodyMass、WaistCircumference、BodyTemperature、BloodGlucose |
| 特性 | BiologicalSex、BloodType、DateOfBirth、FitzpatrickSkinType、WheelchairUse、ActivityMoveMode |
| 生殖健康 | BasalBodyTemperature、MenstrualFlow、Pregnancy、OvulationTestResult、SexualActivity 等 |
| 其他 | Workout、ActivitySummary、Audiogram、WorkoutRoute、StateOfMind 等 |

iOS 同时申请部分**写入**权限（正念、饮水、咖啡因、经期快捷记录、运动距离、心理状态、
体重/身高/BMI），用于用户主动记录时写回健康 App。

### 1.3 对齐矩阵

| 功能域 | iOS HealthKit | 鸿蒙 Health Service Kit | 对齐状态 | 说明 |
|---|---|---|---|---|
| 步数/日常活动 | ✅ StepCount、ActivitySummary 等 | ✅ dailyActivities（近 7 天按日聚合） | ✅ 已对齐（鸿蒙为子集） | 鸿蒙仅用步数做目标进度与趋势 |
| 静息心率 | ✅ RestingHeartRate | ✅ restingHeartRate（每日最新值） | ✅ 已对齐 | 鸿蒙仅取每日最新一条，更小 |
| 睡眠 | ✅ SleepAnalysis（分期） | ✅ sleepRecord（时长/评分 + 最近一晚分期） | ✅ 已对齐（鸿蒙为子集） | 鸿蒙分期仅在内存聚合，不落盘 |
| 心率（实时） | ✅ HeartRate | ❌ | ⚠️ 鸿蒙缺口 | 当前鸿蒙无实时心率功能，不申请 |
| HRV | ✅ HeartRateVariabilitySDNN | ❌ | ⚠️ 鸿蒙缺口 | 无对应功能，不申请 |
| 活动能量 | ✅ ActiveEnergyBurned 等 | ❌ | ⚠️ 鸿蒙缺口 | 无对应功能，不申请 |
| 呼吸频率 | ✅ RespiratoryRate | ❌ | ⚠️ 鸿蒙缺口 | 无对应功能，不申请 |
| 正念分钟 | ✅ MindfulSession | ❌ | ⚠️ 鸿蒙缺口 | 无对应功能，不申请 |
| 环境声级 | ✅ Environmental/Headphone Audio | ❌ | ⚠️ 鸿蒙缺口 | 无对应功能，不申请 |
| 身体测量/营养/生殖 | ✅ 多类 | ❌ | ⚠️ 鸿蒙缺口 | 无对应功能，不申请 |
| 写入权限 | ✅ 部分类型写回 | ❌ `writeDataTypes` 为空 | ✅ 鸿蒙更严格 | 鸿蒙严格只读不写不删（PEN-6） |

结论：鸿蒙当前只读取**产品功能实际消费的最小集合**（步数、静息心率、睡眠摘要），是
iOS 读取范围的严格子集；在「只读不写不删」上比 iOS 更严格。新增鸿蒙功能若需读取新类型，
必须先完成数据最小化评估并同步更新本文矩阵。

## 2. 隐私边界检查与备份收窄

### 2.1 本机存储与上传检查

- 持久化仅使用 Preferences：
  - `bio_balance_local_state`（`Index.ets`）：日期、饮水、心情、今日行动、步数及可用性、步数目标、通知开关等；
  - `bio_balance_checkin_records`（`CheckinRecordStore.ets`）：日照/咖啡因/用药/症状记录。
- 健康明细：静息心率、睡眠时长/评分与睡眠分期**不落盘**，仅内存持有，每次启动重新读取；
  步数为每日聚合值（非原始样本），随当日状态写入本机 Preferences。
- 上传：全工程无网络/上传代码，健康数据不离开设备（详见 1.1）。
- 日志：仅 `hilog` 输出操作状态与错误码；`errorMessage()` 只映射错误码文案，
  不含健康数值、药名、症状或用户文本（日志脱敏满足）。

### 2.2 系统备份口径与收窄（本次改动）

`entry/src/main/resources/base/profile/backup_config.json` 原为
`allowToBackupRestore: true`，即本应用数据（含 Preferences 中的步数与用药/症状记录）
会进入华为系统云备份/恢复流程，与「健康原始数据/明细不上云」红线冲突。

收窄方案（已实施）：**改为 `allowToBackupRestore: false`**，应用数据整体不参与系统
云备份与云恢复。理由：

- 健康相关数据与普通设置混存在同一 Preferences 文件，当前没有按文件区分
  「健康/非健康」的机制；逐文件 `excludes` 白名单依赖文件路径实现细节，风险高于收益；
- 本应用定位为本地优先，非健康设置（目标、提醒）丢失后可重建，收益远低于隐私风险；
- 与 iOS「HealthKit 原始样本禁入云」的边界取向一致，且更严格（iOS 仍存在系统级备份）。

后续若要恢复云备份：先把健康与非健康存储拆分（例如健康摘要独立 Preferences / 独立
数据库），再在 `backup_config.json` 用 `includes` 白名单只放行非健康文件，并将该决定
回写本文。

## 3. 已实现云同步字段白名单（对齐 iOS CloudKit 白名单合同）

对齐参考：`bio-balance-iOS/ICLOUD_DATA_ARCHITECTURE.md` 第 5 节 Record 合同与第 6 节
隐私分级。原则：**云同步可选（默认关闭），只同步聚合摘要，绝不把健康原始样本/明细序列
上传**。当前实现使用 AGC Cloud DB 并遵守本节白名单，且不引入对 Java 后端
（`bio-balance-backend`）的运行时依赖（架构红线）。

| 记录（建议） | 允许字段 | 禁止字段 |
|---|---|---|
| `DailyStepsSummary` | `dateKey`、`steps`、`updatedAt`、`schemaVersion` | 分钟级步频时间序列、原始计步样本 |
| `DailyRestingHeartRateSummary` | `dateKey`、`restingHeartRate`、`updatedAt`、`schemaVersion` | 原始心率样本、RR 间期、实时心率流 |
| `SleepSessionSummary` | `sessionId`、`dateKey`、`durationMinutes`、`sleepScore`、`deepMinutes`、`shallowMinutes`、`dreamMinutes`、`awakeMinutes`、`updatedAt`、`schemaVersion` | 睡眠分期原始 segment 时间序列、音频/鼾声、自然语言 insight |
| `CheckinSummary`（可选） | `dateKey`、心情/饮水等**稳定枚举或数值** | 用药名称/剂量、症状文本、自由文本 |

硬性规则：

1. 同步默认关闭，用户显式开启后才上传；关闭或失败不得影响本机功能（云不是运行前提）。
2. 每条记录只含稳定 ID 与聚合摘要，不含可推导出原始明细的字段。
3. 云日志只记录操作、record type 与稳定技术 ID，不记录健康数值与用户文本。
4. `CloudSyncPolicy.sanitize` 逐字段构造云模型，禁止把本地模型整体编码上传；新增字段必须先更新本文。
5. 账号仅持久化 OpenID 不透明键，不保存 authorizationCode、ID token 或其他凭据。

## 4. 权限用途说明对齐

iOS（`bio-balance-iOS/.../InfoPlist.xcstrings`，NSHealthShareUsageDescription，zh-Hans）：

> 眠屿 需要读取你的心率、HRV、睡眠、步数、活动能量、呼吸频率、正念分钟、环境声级等健康数据，用于展示趋势、生成恢复建议和提醒。

鸿蒙端 Health Service Kit 的授权页由华为运动健康呈现，系统不展示 App 自定义弹窗文案；
因此在 App 内新增「隐私与数据」页（`entry/src/main/ets/pages/PrivacyPage.ets`，入口为
「我的」页的「隐私与数据」行）对齐用途说明：

- 读取范围：步数、静息心率、睡眠（含最近一晚睡眠分期）；
- 用途：首页健康概览、近 7 天趋势、睡眠详情与本机健康评分；
- 只读不写不删；数据仅保存在本机，不上传；
- 不参与系统云备份（`allowToBackupRestore = false`）；
- 未来云同步仅同步白名单摘要（默认关闭，见第 3 节）；
- 撤销授权入口：「我的」页「撤销运动健康授权」。

## 5. 相关文件

| 文件 | 变更 |
|---|---|
| `entry/src/main/resources/base/profile/backup_config.json` | `allowToBackupRestore` 改为 `false`（收窄） |
| `entry/src/main/ets/pages/PrivacyPage.ets` | 新增「隐私与数据」页 |
| `entry/src/main/resources/base/profile/main_pages.json` | 注册 `pages/PrivacyPage` |
| `entry/src/main/ets/pages/Index.ets` | 「隐私与数据」行跳转新页；运动健康卡片用途文案补充 |
| `entry/src/main/resources/base/element/string.json` | 新增隐私页文案资源 |
| `README.md` / `AGC_CONFIG.md` | 同步说明 |
