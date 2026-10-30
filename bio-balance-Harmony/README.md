# 眠屿 for HarmonyOS

「眠屿」纯 HarmonyOS 原生健康节律应用，使用 DevEco Studio、ArkTS 与 ArkUI 实现，不依赖 WebView、跨端框架、后端服务或第三方 UI 库。应用采用 **Stage 模型**，按 `entryability / pages / model / service` 分层组织（详见 `ARCHITECTURE.md`）。

架构定位（与仓库根 `AGENTS.md` 对齐）：

- **本地优先**：未登录、离线或华为运动健康服务异常时，本机记录、提醒等本地功能继续可用，云端不是运行前提；
- **健康数据最小化**：只读取产品功能实际消费的数据（步数、静息心率、睡眠摘要），只读不写不删、不上传；
- **不依赖 Java 后端**：多设备/云同步方案与 iOS 不同（iOS 用 iCloud/CloudKit），鸿蒙端本地优先，如需云同步评估 AGC Cloud 并按白名单设计。

## 文档索引

- `ARCHITECTURE.md`：架构与数据层说明（PEN-9）
- `DATA_PRIVACY_ALIGNMENT.md`：健康数据接入与隐私边界对齐（PEN-11）
- `AGC_CONFIG.md`：AGC / 签名 / 权限配置清单（PEN-8）
- `RECOVERY_NOTES.md`：PEN-7 源码恢复溯源说明

## 当前能力

- 首页：今日状态（本地综合评估）、静息心率/睡眠/步数/饮水概览、今日优先行动
- 每日记录：心情、饮水、1 分钟呼吸，以及日照/咖啡因/用药/症状记录（独立详情页，可添加、删除，仅本机保存）
- 睡眠详情：近 7 天睡眠时长与评分、最近一晚深睡/浅睡/REM/清醒分期统计（仅本机读取，分期不落盘）
- 健康提醒：喝水/用药/久坐每日定时提醒，可开关与设置时间（本地 reminderAgentManager 调度）
- 趋势：Health Service Kit 近 7 天真实步数、睡眠、静息心率摘要
- 我的：步数目标、健康提醒设置、撤销运动健康授权、隐私与数据页和今日记录重置
- 隐私与数据：「我的」页可进入，说明权限用途、读取范围、数据边界（只读不写、仅本机、不参与云备份）与云同步白名单
- 本地持久化：通过 HarmonyOS Preferences 保存每日状态与记录，每日自动切换新记录
- 华为运动健康：读取当日步数、静息心率和最近睡眠（含分期明细），分别维护三类授权，部分授权时仍可刷新已授权数据
- 安全边界：健康结论标明为本地健康管理参考，并保留紧急症状提示

首页的步数、静息心率和睡眠来自 Health Service Kit，趋势页使用近 7 天日常活动聚合结果；未授权、设备不支持或无数据时显示 `--`，不会用演示数值冒充测量结果。每个数据域都携带独立的读取状态：真实零数据正常更新，读取失败则保留该域已有的内存值与步数 Preferences，不显示为已同步。

## 与 iOS 对齐进度

> 状态图例：✅ 已对齐（鸿蒙为 iOS 子集，见备注）／🟡 进行中或部分对齐／❌ 缺失。

| 功能域 | iOS | 鸿蒙 | 状态 | 备注 |
|---|---|---|---|---|
| 基础配置（bundleName / 显示名 / 图标 / 版本） | ✅ | ✅ | ✅ 已对齐 | PEN-8，见 `AGC_CONFIG.md` |
| 首页概览（状态分 / 心率 / 睡眠 / 步数 / 饮水 / 今日行动） | ✅ | ✅ | ✅ 已对齐 | 鸿蒙为子集（静息心率替代实时心率） |
| 每日记录（心情 / 饮水 / 1 分钟呼吸） | ✅ | ✅ | ✅ 已对齐 | 本机保存 |
| 日照 / 咖啡因 / 用药 / 症状记录 | ✅ | ✅ | ✅ 已对齐 | 独立详情页、可增删、仅本机 |
| 睡眠详情（近 7 天时长 / 评分 + 最近一晚分期） | ✅ | ✅ | ✅ 已对齐 | 分期仅内存聚合，不落盘 |
| 健康提醒（喝水 / 用药 / 久坐定时提醒） | ✅ | ✅ | ✅ 已对齐 | reminderAgentManager 本地调度，固定文案不含健康数值 |
| 趋势（近 7 天步数 / 静息心率 / 睡眠） | ✅ | ✅ | ✅ 已对齐 | 鸿蒙为子集 |
| 隐私与数据页 | ✅ 系统权限说明 | ✅ 应用内隐私页 | ✅ 已对齐 | PEN-11 |
| 健康数据读写边界 | ⚠️ 部分类型写回 | ✅ 严格只读不写不删 | ✅ 鸿蒙更严格 | PEN-6 |
| 健康数据云备份 | ⚠️ 参与系统备份 | ✅ 不参与系统云备份 | ✅ 鸿蒙更严格 | `backup_config.json` 已收窄 |
| 多设备云同步 | ✅ iCloud/CloudKit | ✅ AGC Cloud DB | ✅ 已实现 | 默认关闭、全重叠可靠拉取、逻辑版本冲突、Preferences outbox；不依赖 Java 后端 |
| 用药处方 / 服药计划 | ✅ | 🟡 部分 | 🟡 部分对齐 | 仅每日用药提醒 + 本机用药记录（名称/剂量），无处方管理 |
| Widget / 小组件 | ✅ | ❌ | ❌ 缺失 | 鸿蒙当前无 Widget 能力 |
| watchOS / Complication | ✅ | ❌ | ❌ 缺失 | 当前发布仅声明 `phone`；Watch 端需独立 UI、路由与真机验收后再声明 |
| 经期模块 | ✅ | ❌ | ❌ 缺失 | 无对应功能 |
| 好友共享 | ✅ | ❌ | ❌ 缺失 | 无共享功能 |
| AI 内容（生成式 / 自然语言） | ✅ | ❌ | ❌ 缺失 | 红线：生成内容默认不入云 |
| 账号 / 订阅 / 内购 | ✅ | 🟡 华为账号 | 🟡 部分 | 已实现华为账号登录/退出；订阅与内购仍未实现 |

## 架构与数据层

应用按 Stage 模型分层：`entryability`（入口）→ `pages`（页面）→ `model`（本地模型/存储）→ `service`（系统能力封装）。

- 健康数据流：`HuaweiHealthService`（Health Service Kit 只读）→ 逐域 `success/errorCode` 快照 → `HealthSyncPolicy` 选择性合并 → 首页/睡眠详情/趋势展示；静息心率、睡眠时长/评分与分期**不落盘**，每次启动重新读取；仅当步数读取成功时，才把每日聚合值随当日状态写入本机 Preferences。
- 每日记录流：`CheckinRecordStore` → `bio_balance_checkin_records` Preferences（按日期分 key）。
- 提醒流：`ReminderService` → `reminderAgentManager` 发布每日提醒，设置与 reminderId 存 `bio_balance_reminders` Preferences。
- 云同步：登录华为账号并显式开启后，白名单摘要进入 Preferences outbox。当前 AGC Cloud DB SDK 不提供服务端 change token/单调变更序列，因此每轮从 `(0, "")` 起按 `(revision, 账号分区物理 recordId)` 全重叠分页回放、页内去重并与本地缓存确定性合并；持久化 cursor 仅作观测，不作为下轮查询下界，从而不会漏掉迟到的同 revision/较小 ID。冲突使用单调逻辑 `revision → deviceId`，不依赖设备墙钟。coordinator 与 transport 在写入前通过 Account Kit 实时 OpenID 双重门禁；不一致时先清空旧账号同步状态、绑定实际账号、递增 generation、关闭同步，禁止 Cloud DB upsert。可重试与永久失败分别保留并明确返回 `partial_failure` / `failed`，本地保存不受云端失败影响。
- 云边界：只允许日期、聚合健康摘要、心情规则码/饮水、目标和通知开关；原始健康样本、RR、睡眠 segment、用药/症状/自由文本、媒体、位置、AI 内容与凭据禁止上传。`backup_config.json` 保持 `allowToBackupRestore: false`。

详细说明（分层、路由、数据流、存储键清单、隐私红线与未来云同步设计）见 **`ARCHITECTURE.md`**。

## 环境

- DevEco Studio 6.0.1 或兼容版本
- HarmonyOS SDK 6.1.1（API 24）
- ArkTS / ArkUI Stage 模型

## 运行

> AGC / 签名 / 权限完整配置清单见 `AGC_CONFIG.md`（当前 client_id 与签名均为占位待办）。

1. 在 DevEco Studio 中打开本目录 `bio-balance-Harmony`。
2. 等待 ohpm 与 Hvigor 同步完成（命令行首次构建前先执行 `ohpm install`）。
3. 在 `File > Project Structure > Signing Configs` 配置调试签名。
4. 在 AppGallery Connect 创建/关联应用、申请 Health Service Kit，并申请“日常活动数据（读）”“心率数据（读）”“睡眠数据（读）”。
5. 把 `entry/src/main/module.json5` 中 `REPLACE_WITH_AGC_CLIENT_ID` 替换成 AppGallery Connect 的 Client ID。
6. 确保工程包名、签名证书指纹与 AppGallery Connect 配置一致。
7. 选择安装了华为运动健康且已登录华为账号的 HarmonyOS 真机运行 `entry`。

## 构建与测试

> 环境参考：DevEco Studio 6.0.1 / HarmonyOS SDK 6.1.1（API 24）。以下命令在工程根目录 `bio-balance-Harmony/` 执行；未配置签名时仍可生成 unsigned HAP、可运行本地单元测试。

```shell
# 0) 首次拉取依赖（含 @ohos/hypium 测试框架）
ohpm install

# 1) 构建（生成未签名 HAP，产物位于 entry/build/default/outputs/default/）
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  --mode module -p product=default -p module=entry@default \
  -p buildMode=debug assembleHap --no-daemon

# 2) 本地单元测试（entry/src/test，含 HealthScoreEngine 评分用例）
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  --mode module -p product=default -p module=entry@default \
  -p buildMode=debug test --no-daemon
```

- 本地单测结果与覆盖率报告生成于 `entry/.test/default/outputs/test/reports/`（覆盖健康评分，以及无授权、部分授权、读取失败、真实零数据和旧数据保护策略）。
- **ohosTest（真机/模拟器 UI 测试）**：`entry/src/ohosTest/` 当前仅有测试模块脚手架（`module.json5`），尚无测试用例；接入真机后在 DevEco Studio 选择 `entry` 测试配置运行。健康数据相关用例需在已授权华为运动健康、并安装华为运动健康 App 的真机上执行。

## 关键代码

- `entry/src/main/ets/pages/Index.ets`：ArkUI 四页主界面与交互
- `entry/src/main/ets/pages/SleepDetailPage.ets`：睡眠详情（近 7 天时长/评分与分期统计）
- `entry/src/main/ets/pages/ReminderSettingsPage.ets`：喝水/用药/久坐提醒设置
- `entry/src/main/ets/pages/CheckinDetailPage.ets`：日照/咖啡因/用药/症状记录详情页
- `entry/src/main/ets/pages/PrivacyPage.ets`：隐私与数据页（权限用途对齐 iOS、数据边界与云同步白名单说明）
- `entry/src/main/ets/pages/AccountSyncPage.ets`：华为账号登录、显式同步开关与手动同步
- `entry/src/main/ets/model/CloudSyncContract.ets`：云字段白名单、schema 与冲突策略
- `entry/src/main/ets/service/CloudSyncCoordinator.ets`：增量拉取、outbox 推送、确认与重试编排
- `entry/src/main/ets/service/AgcCloudSyncTransport.ets`：AGC Cloud DB `MianyuSyncRecord` 适配
- `entry/src/main/ets/model/HealthScoreEngine.ets`：可单元测试的本地评分逻辑
- `entry/src/main/ets/model/HealthSyncPolicy.ets`：逐域授权/读取结果合同与失败保护合并策略
- `entry/src/main/ets/model/CheckinRecordStore.ets`：日照/咖啡因/用药/症状的本机 Preferences 存储
- `entry/src/main/ets/service/HuaweiHealthService.ets`：Health Service Kit 初始化、授权和健康数据读取（含睡眠分期，只读不写不删）
- `entry/src/main/ets/service/ReminderService.ets`：本地定时提醒发布/取消与通知授权
- `entry/src/main/ets/entryability/EntryAbility.ets`：Stage 模型应用入口
- `entry/src/test/LocalUnit.test.ets`：本地单元测试（HealthScoreEngine）

## 下一步建议

1. 为静息心率增加逐日折线图；未来 Wearable 独立模块需遵守仅返回最新 HealthSequence 的平台限制。
2. 补充 ohosTest 真机用例（授权流程 / 健康数据读取展示）。
3. 在 AGC 创建 `mianyu_sync` zone 与 `MianyuSyncRecord` schema 后完成双真机增量同步验收。

## Health Service Kit 说明

- Phone/Tablet：当日步数使用 `aggregateData(dailyActivities)`；静息心率使用 `readData(restingHeartRate)`；睡眠使用 `readData(sleepRecord)`。
- Wearable（未来独立模块）：官方 HealthSequence 接口从 5.1.1(19) Release 起支持，目前只返回手表侧最新一条记录，请求中的时间范围暂不生效；当前发布不声明 Wearable。
- Health Service Kit 权限是联盟服务审批权限与用户授权的交集，不能只靠 `module.json5` 声明获得。
- 当前实现只请求读权限，不调用 `saveData` 或 `deleteData`。

官方文档：

- [Health Service Kit 开发接入](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/health-harmonyos)
- [管理用户授权](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/health-add-permissions)
- [管理运动健康采样数据](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/health-samplepoint-manage)
- [管理健康记录](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/health-healthsequence-manage)
- [Wearable 读取 HealthSequence](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/health-wearable-healthsequence-manage)
