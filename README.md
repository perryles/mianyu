# 眠屿 · Mianyu

**从睡眠、压力与日常记录出发，理解自己的健康节律。**

眠屿（Mianyu）是一款以本地数据为基础的原生健康应用。本仓库 `bio-balance` 包含 iOS、Apple Watch、Widget 与 HarmonyOS 客户端，面向希望了解健康数据分析、原生交互与隐私优先架构的开发者。源码按非商业许可公开，商业使用需另行获得书面授权。

iOS 是核心端，使用 SwiftUI、HealthKit 与 CloudKit；HarmonyOS 使用 ArkTS 与 ArkUI，提供本地优先的健康记录与趋势能力。两端功能与数据接入方式有所不同，当前不提供跨 Apple / 华为生态的数据互通。

> **项目状态**：持续开发中，部分能力需要真机、平台授权或云服务配置，克隆源码不等于获得完整线上服务。本项目采用非商业源码可见许可，详见 [LICENSE](./LICENSE)；不属于 OSI 定义的开源软件。
>
> **健康用途**：应用中的评分、趋势与 AI 内容用于日常健康管理参考，不能替代医疗诊断、治疗或专业医疗建议。

## 功能概览

### iOS / Apple Watch

- **今日概览**：汇总健康指标、睡眠恢复、压力与每日行动。
- **睡眠与恢复**：睡眠记录、节律分析、睡眠趋势与相关报告。
- **压力与活动**：压力评估、身体电量、心率与 HRV 趋势、活动与健身记录。
- **日常健康记录**：饮水、咖啡因、心情、日照、呼吸正念、用药与症状等。
- **健康专题**：经期 / 孕期、健康档案、目标与周报。
- **设备联动**：Apple Watch、桌面 Widget、表盘 Complication 与 App Group 快照。
- **同步与共享**：基于 iCloud / CloudKit 的白名单数据同步，以及好友健康共享。
- **AI 辅助**：健康问答、餐食 / 饮品识别与处方文字结构化；可用性取决于供应商配置与网络，识别结果需人工确认。

### HarmonyOS

- 今日状态、步数 / 静息心率 / 睡眠概览与近 7 天趋势。
- 心情、饮水、呼吸、日照、咖啡因、用药与症状的本地记录。
- 喝水、用药与久坐本地提醒，以及隐私与授权管理。
- Health Service Kit 只读健康数据接入；华为账号与需显式开启的 AGC Cloud DB 同步实现。

HarmonyOS 当前是 iOS 功能的子集，尚无 Widget、Watch、经期、好友共享或生成式 AI。详细状态、平台配置与验收事项见 [HarmonyOS README](./bio-balance-Harmony/README.md)。

## 架构与数据边界

- **本地优先**：本地记录不以自建后端为运行前提；健康数据读取仍需相应平台授权，云端 AI 需要联网。
- **Apple 生态同步**：iOS 多设备与云同步统一使用 iCloud / CloudKit；Watch 与 Widget 通过 WatchConnectivity / App Group 等机制协作。
- **HarmonyOS 同步**：使用独立的华为账号与 AGC Cloud DB 接入，不与 iCloud 互通；服务配置和真机验收要求见子项目文档。
- **最小化数据**：云同步以各业务域字段白名单和授权为边界，不应上传 HealthKit 原始样本、原始音频、图片、位置或模型对话全文。
- **区分同步与 AI 请求**：照片不进入 CloudKit 不代表照片不离开设备。当前餐食 / 饮品识别会向千问发送处理后的图片，健康问答会发送所需上下文，处方结构化发送经本机 OCR 与清洗后的文字。详见 [AI 架构与请求边界](./bio-balance-iOS/BioBalance/BioBalance/Core/AI/README.md)。

`bio-balance-backend` 与 `bio-balance-admin-web` 是独立维护的可选工程，**不包含在本仓库中**，仅服务管理后台与 AI 编排；运行客户端和 iOS 云同步无需部署它们。

## 仓库结构

```text
bio-balance/
├── bio-balance-iOS/
│   ├── BioBalance/
│   │   ├── BioBalance.xcodeproj/       # Xcode 工程
│   │   ├── BioBalance/                # iPhone 应用
│   │   ├── BioBalanceWatch Watch App/  # Apple Watch 应用
│   │   ├── BioBalanceWidgetExtension/ # iOS 小组件
│   │   ├── BioBalanceComplications/   # 表盘复杂功能
│   │   ├── Shared/                    # 跨 Target 共享契约
│   │   └── BioBalanceTests/           # 测试
│   └── CODE_WIKI.md                   # 架构与开发索引
├── bio-balance-Harmony/               # HarmonyOS 原生工程与接入文档
└── AGENTS.md                          # 仓库协作约定
```

## 快速开始

### 获取源码

```sh
git clone https://github.com/perryles/bio-balance.git
cd bio-balance
```

### iOS

**环境**：macOS、支持工程所用 SDK 的 Xcode 与 iOS Simulator。当前工程使用 Swift 6，iOS 最低部署版本为 **18.6**，watchOS 为 **10.0**；个别新系统能力有额外可用性检查。最低部署版本不代表最低 Xcode 版本，具体以当前源码及本机编译结果为准。

1. 打开工程：

   ```sh
   open bio-balance-iOS/BioBalance/BioBalance.xcodeproj
   ```

2. 选择 `BioBalance` Scheme 与已安装的 iPhone 模拟器。
3. 真机运行前，在各 Target 的 Signing & Capabilities 中配置自己的开发团队与签名。派生项目需一致配置主 App / 扩展的 Bundle Identifier、App Group、iCloud 容器及相关代码引用；仅修改主 App 的 Bundle Identifier 不足以完成配置。
4. HealthKit 数据、Apple Watch 联动、推送、iCloud 同步和订阅等能力需要分别配置与验证。仓库中的原项目容器和服务标识不代表你拥有相应服务的访问权限。
5. 云端 AI 使用你自己的供应商凭据；配置入口与请求策略见 [AI 文档](./bio-balance-iOS/BioBalance/BioBalance/Core/AI/README.md)。不要将个人密钥写入源码或提交到仓库。

模拟器 Debug 构建（无需设备签名）：

```sh
cd bio-balance-iOS/BioBalance
xcodebuild build \
  -project BioBalance.xcodeproj \
  -scheme BioBalance \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

其他共享 Scheme：`BioBalanceWatch Watch App`、`BioBalanceWidgetExtension`、`BioBalanceComplications`。更多构建与数据流说明见 [iOS Code Wiki](./bio-balance-iOS/CODE_WIKI.md)。

### HarmonyOS

**环境参考**：DevEco Studio 6.0.1、HarmonyOS SDK 6.1.1（API 24）、ArkTS / ArkUI Stage 模型。

1. 用 DevEco Studio 打开 `bio-balance-Harmony/`。
2. 在该目录执行 `ohpm install`，等待工程同步完成。
3. 仅构建未签名 HAP，可按 [构建与测试说明](./bio-balance-Harmony/README.md#构建与测试) 执行。
4. 真机健康数据接入需完成调试签名、AppGallery Connect 应用关联、Health Service Kit 服务申请与用户授权；将工程中的 `REPLACE_WITH_AGC_CLIENT_ID` 替换为自己的配置。
5. 账号与云同步另需完成 AGC Cloud DB 配置及真机验收，详见 [AGC 配置清单](./bio-balance-Harmony/AGC_CONFIG.md)。

未授权或无健康数据时应显示真实的空状态，不使用演示数值代替测量结果。

## 验证与测试

只构建和测试受影响的子项目，具体约定见 [根 AGENTS.md](./AGENTS.md) 与 [iOS AGENTS.md](./bio-balance-iOS/AGENTS.md)。

iOS 可先查询本机模拟器，再运行与改动相关的测试：

```sh
xcrun simctl list devices available

# 在 bio-balance-iOS/BioBalance/ 下执行，设备名称替换为本机可用设备
xcodebuild test \
  -project BioBalance.xcodeproj \
  -scheme BioBalance \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BioBalanceTests/CloudKitDataPolicyTests
```

模拟器测试不能替代 HealthKit 授权、Watch 联动、CloudKit 账号切换与共享等真机验收。CloudKit 的 Schema 部署、验收矩阵与排障流程见 [运维 Runbook](./bio-balance-iOS/BioBalance/BioBalance/Docs/CloudKitOperationsRunbook.md)。HarmonyOS 的未签名构建和本地单元测试命令见其 [README](./bio-balance-Harmony/README.md#构建与测试)。

## 开发文档

- [iOS 架构与代码索引](./bio-balance-iOS/CODE_WIKI.md)
- [iOS 页面组织](./bio-balance-iOS/BioBalance/BioBalance/Views/README.md)
- [健康算法概览](./bio-balance-iOS/BioBalance/BioBalance/Core/Algorithms/README.md)
- [睡眠算法与模块](./bio-balance-iOS/BioBalance/BioBalance/Core/Algorithms/Sleep/README.md)
- [压力评估算法](./bio-balance-iOS/BioBalance/BioBalance/Core/Algorithms/Stress/Assessment/STRESS_CALCULATION.md)
- [VO₂ Max 算法](./bio-balance-iOS/BioBalance/BioBalance/Core/Algorithms/Stress/VO2Max/VO2MAX_CALCULATION.md)
- [CloudKit 同步基础设施](./bio-balance-iOS/BioBalance/BioBalance/Core/CloudKit/README.md)
- [数据隐私实现](./bio-balance-iOS/BioBalance/BioBalance/Docs/DataPrivacyImplementation.md)
- [AI 架构与供应商接入](./bio-balance-iOS/BioBalance/BioBalance/Core/AI/README.md)
- [HarmonyOS 架构](./bio-balance-Harmony/ARCHITECTURE.md)
- [HarmonyOS 隐私边界](./bio-balance-Harmony/DATA_PRIVACY_ALIGNMENT.md)

## 参与贡献

欢迎通过 [Issues](https://github.com/perryles/bio-balance/issues) 反馈问题、讨论功能，也欢迎提交 [Pull Request](https://github.com/perryles/bio-balance/pulls)。

1. 较大改动先开 Issue 说明问题、预期行为与涉及平台。
2. 阅读所在子项目的协作约定，保持一次改动聚焦一个问题。
3. 用户可见名称统一为「眠屿 / Mianyu」；iOS 文案使用 String Catalog，HarmonyOS 文案使用资源文件，所有文案不添加动画效果。
4. 涉及采集、持久化、云同步或共享时，说明数据最小化与字段白名单；不要在 Issue、日志、截图或测试样本中提交真实健康资料、个人身份信息或凭据。
5. 提交前完成相关构建与聚焦测试，在 PR 中说明改动、验证结果与尚未覆盖的真机场景。

反馈问题时请附系统 / 开发工具版本、受影响模块、复现步骤与预期 / 实际表现。疑似凭据泄露请勿在公开 Issue 粘贴密钥或含密钥的截图。

## 许可证与商业授权

本项目采用 [Mianyu 非商业源码可见许可证 1.0](./LICENSE)。你可以在遵守许可的前提下，为个人学习、教学、研究及其他非商业目的使用、修改和分发本项目；分发时须保留许可与署名，标明修改，并提供相应源码。

**未经事先书面授权，不得商业使用**，包括出售应用或衍生版本、收费订阅或托管服务、广告变现、商业产品集成，以及企业内部业务运营使用。商业授权请通过 [项目维护者主页](https://github.com/perryles) 所列联系方式联系；不要在公开讨论中提交合同或私人信息。

该许可限制商业用途，因此本项目属于“源码可见”，不属于 OSI 定义的开源软件。许可仅覆盖有权授权的本项目原创内容；第三方依赖、素材与平台服务适用各自条款。贡献规则见 [CONTRIBUTING.md](./CONTRIBUTING.md)，安全问题处理见 [SECURITY.md](./SECURITY.md)。

## 公开发布前检查

- 核对第三方代码、字体、图片、音频与模型资源的来源及分发权利。
- 当前源码已移除默认 AI 供应商密钥；维护者仍须在供应商侧撤销或轮换旧密钥，并检查和清理 Git 历史、已发布产物与日志。删除当前文件中的值不能撤销历史泄露。
- 使用独立开发者账号验证签名、容器与平台服务配置，避免依赖维护者的私有服务资源。
- 本次文档与配置整理不代表已经完成整个仓库的凭据、隐私或第三方授权审计。
