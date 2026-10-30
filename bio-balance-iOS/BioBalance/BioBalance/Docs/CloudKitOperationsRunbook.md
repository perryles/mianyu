# CloudKit 上线与运维手册

本文档面向 Bio Balance 的开发、测试和发布人员，用于在不暴露健康数据的前提下验证 CloudKit 配置、部署 Schema 和排查线上问题。

## 1. 系统边界

| Target | 直接访问 CloudKit | 数据通道 | 说明 |
|---|---:|---|---|
| Mianyu iPhone App | 是 | CloudKit + App Group | 唯一持有 CloudKit entitlement 的 Target |
| Mianyu Watch App | 否 | WatchConnectivity + App Group | 不应直接依赖 CloudKit 容器 |
| Widget Extension | 否 | App Group 投影 | 只读取主 App 生成的轻量快照 |
| Complications | 否 | App Group 投影 | 不存储业务真值 |

当前 CloudKit Container：

```text
iCloud.com.boundesu.BioBalance
```

本地 Schema 基线：

```text
bio-balance-iOS/CloudKit/BioBalanceDevelopment.ckdb
```

Schema 文件是代码审查和自动化测试的基线，CloudKit Console 中的实际 Schema 才是运行环境的最终状态。两者必须同步维护。

## 2. 发布前静态检查

### Entitlement

主 App `BioBalance/BioBalance.entitlements` 必须包含：

```text
com.apple.developer.icloud-container-identifiers
  - iCloud.com.boundesu.BioBalance
com.apple.developer.icloud-services
  - CloudKit
```

Watch、Widget 和 Complications 当前只需 App Group。除非已经完成独立的账户、冲突、隐私和失败降级设计，不要给 extension 补加 CloudKit entitlement。

### 代码与 Schema

- `CloudKitDataPolicy.containerIdentifier` 与 entitlement 完全一致。
- 每个敏感业务域使用独立 private Zone。
- Record Type 只允许新增，不重命名已上线类型。
- Production 已包含本版本所有 Record Type、Field 和 Queryable Index。
- private/shared 健康记录没有授予 `_world` 读权限。
- public database 只包含可公开资料，不包含健康数值和可推导的敏感摘要。

### 本地检查命令

在 `bio-balance-iOS/BioBalance` 目录执行：

```sh
xcodebuild test \
  -project BioBalance.xcodeproj \
  -scheme BioBalance \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BioBalanceTests/CloudKitDataPolicyTests \
  -only-testing:BioBalanceTests/CKSyncEngineTransportTests \
  -only-testing:BioBalanceTests/SleepCloudKitSyncTests \
  -only-testing:BioBalanceTests/SocialSharingPermissionTests
```

模拟器测试只验证策略、编解码和 Stub 行为，不代表真实 iCloud 账户可用。

## 3. CloudKit Console 部署

1. 选择 `iCloud.com.boundesu.BioBalance`。
2. 在 Development 环境核对 Record Types、Fields、Indexes 和 Security Roles。
   验证被全量查询的四个 record type（`BBSleepSession`、`BBMascotXPGrant`、`BBDrinkExperience`、`BBMedicationPrescription`）
   的系统字段 `___recordID`（recordName）已标记 **Queryable**；缺失时全量拉取会报
   `Field 'recordName' is not marked queryable`，该域跨设备恢复直接失败。
3. 使用专用测试 Apple ID 运行真机集成用例。
4. 导出或人工对照 Development Schema 变更，更新仓库中的 `.ckdb` 基线。
5. 将兼容性 Schema 变更部署到 Production。
6. 部署后重新打开 Production 环境，确认索引和权限与 Development 一致。
7. 最后才提交 TestFlight 构建。TestFlight 验收必须用新账户和存量账户各执行一次。

不要在 Production Console 中直接修改真实用户健康记录来“修复”客户端问题。应先确定可重复的迁移或恢复策略。

## 4. 真机验收矩阵

| 场景 | 期望结果 |
|---|---|
| 首次安装，iCloud 已登录 | 六项偏好显示开启；孕期域不在启动时强制读取 |
| iCloud 未登录 | 管理页显示不可用；手动同步按钮禁用；本地功能可继续使用 |
| 关闭某一项同步 | 后续全局同步跳过该域；不删除本地或云端已有数据 |
| 再次开启某项 | 立即请求该域同步；不等待下次 App 启动 |
| 手动同步全部 | 包含孕期域；界面显示实际成功数与失败数 |
| 断网后新增本地记录 | 本地保存成功；不因 CloudKit 错误丢失或卡住界面 |
| 恢复网络 | 再次同步后按业务域冲突规则合并 |
| 同一 Apple ID 的第二台设备 | 只恢复允许上传的结构化数据；图片、音频和 AI 原始上下文不出现 |
| Apple ID 切换 | 已实现账号绑定的敏感域停止自动上传，等待用户重新确认 |
| 好友邀请撤回 | 参与者失去访问；不影响拥有者 private database 中的其他域 |

## 5. 敏感数据检查清单

允许进入 CloudKit 的数据必须是功能恢复所需的最小结构化字段。

| 默认禁止上传 | 处理方式 |
|---|---|
| 餐饮图片、文件 URL、精确位置 | 只保留本机，云端使用结构化摘要 |
| 睡眠录音、打鼾片段、音频特征 | 只保留本机，云端使用会话摘要 |
| 处方原图、OCR 全文 | 只上传用户确认后的结构化字段 |
| AI Prompt、原始回答、Provider 调试上下文 | 不作为健康记录的 CloudKit 字段 |
| 完整精确位置轨迹 | 不进入好友共享；如需位置只能使用明确授权的粗粒度结果 |

日志、埋点和 Crash 附件同样遵循该边界。可记录 Zone、Record Type、稳定技术 ID、CKError code 和耗时；不记录用户备注、药名、症状、数值或自由文本。

## 6. 故障分级与恢复

| 现象 | 优先检查 | 处理 |
|---|---|---|
| 所有域都失败 | Apple ID、iCloud Drive、Container entitlement | 保留本地数据，提示账户不可用，不做全量重试循环 |
| 仅 TestFlight/商店版失败 | Production Schema | 对比 Development 与 Production 的 Type、Field、Index、Role |
| 单个域失败 | 该 Zone 与 Record Type | 只重试该域，不阻断其他同步项 |
| `requestRateLimited` | `retryAfter` | 遵循服务端延迟，禁止立即循环重试 |
| `quotaExceeded` | iCloud 配额 | 停止写入并告知用户；不自动删除云端记录 |
| `serverRecordChanged` | `updatedAt` 和业务冲突策略 | 使用对应 Feature 的合并策略，不盲目覆盖 |
| Zone 被删除 | 是否为用户主动清理 | 只在用户再次开启或写入时重建，防止删除后立即复活 |
| `Field 'recordName' is not marked queryable` | 该 record type 的 `___recordID` 是否标记 Queryable；对比 `.ckdb` 基线 | 在 Development 补索引并验证，再部署 Production；本地数据不受影响，无需清库 |

## 7. 发布门禁

下列条件全部满足才能将包含 CloudKit Schema 变更的版本提交审核：

- [ ] Policy 和 Schema 单元测试通过。
- [ ] Development Schema 与仓库 `.ckdb` 基线一致。
- [ ] Production Schema 已先于 App 构建部署。
- [ ] 新装、升级、断网、账户切换和双设备合并已真机验收。
- [ ] 关闭同步后没有隐式上传。
- [ ] 日志和分析事件不包含敏感 Payload。
- [ ] PrivacyInfo.xcprivacy、隐私政策和 App Store 隐私回答与实际数据流一致。
- [ ] 好友共享已验证邀请、接受、撤回、退出和参与者权限。

## 8. 明确的当前限制

- iCloud 管理页尚未提供通用的 per-zone 云端删除入口。
- 吉祥物 Store 的同步是延迟任务，管理页只能报告 `requested`，不能报告服务器最终成功。
- 孕期 Repository 是 CloudKit-backed 实现；全局协调器会尊重偏好，但业务页还需要本地 Repository 才能在关闭 iCloud 时保证完整的离线编辑。
- 手动同步目前是按域顺序执行，用于避免同时刷新多个敏感 Store；未来只能在确认 Store 与 CloudKit 限流安全后并行化。

