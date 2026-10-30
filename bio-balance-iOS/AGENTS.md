# AGENTS.md — bio-balance-iOS

Mianyu iOS / watchOS / Widget 应用（Swift、SwiftUI、SwiftData、HealthKit、CloudKit）。本文件是本子目录内 coding agent 的入口指令。

## 按任务读取的权威上下文

| 文档 | 何时必读 |
|---|---|
| [`CODE_WIKI.md`](CODE_WIKI.md) | 仅在需要跨模块定位、构建依赖或数据流信息时 |

## 受限区域

仅当任务本身需要对应的 capability、容器、schema 或权限数据流变更时修改；无需因文件未被点名而重复询问：

- `BioBalance/BioBalance/BioBalance.entitlements` 及各 extension 的 entitlements：容器 ID 固定为 `iCloud.com.boundesu.BioBalance`；Watch/Widget/Complication 不得补加 CloudKit entitlement。
- `CloudKit/BioBalanceDevelopment.ckdb`：schema 基线，只能与 CloudKit Console 的实际部署同步维护，不得单方面编辑。
- 已上线的 CloudKit record type / 字段：只允许兼容性新增，不得重命名、删除或复用为不同语义；`schemaVersion` 只增不减。
- 容器创建必须走 `CloudKitDataPolicy.makeContainer()`，禁止引入 `CKContainer.default()`。
- 各 `PrivacyInfo.xcprivacy` 与 `InfoPlist.xcstrings` 中的权限用途描述：改动需与实际数据流核对。

## 聚焦测试路由

默认运行 `BioBalanceTests/` 中与改动直接相关的聚焦测试。改动横跨多个 CloudKit 数据策略、传输、睡眠同步或社交共享边界时，才在 `BioBalance/` 目录运行以下完整回归矩阵（详见 Runbook 第 2 节）：

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

- 模拟器测试只验证策略、编解码与 Stub 行为；真机验收矩阵与发布门禁见 Runbook 第 4、7 节，agent 不得代替真机验收宣告通过。
