# 华为手表数据接入 iOS（无自建后台方案）

最后核对：2026-07-30

## 1. 结论（修正）

华为有两条官方方向，不能只考虑 Apple 健康桥接：

### 路线 A：华为账号授权 + Huawei Health Kit iOS（优先申请验证）

```text
华为手表 -> 华为健康云
             -> 用户在 Mianyu 发起华为账号登录/授权
             -> Huawei Health Kit iOS API
             -> Mianyu 本地 Store / 本机算法
```

华为 Health Kit 官方入口明确标注支持 **iOS**，并说明应用在用户授权后可调用 API 读取华为及生态伙伴开放的健身健康数据。这就是“登录相应账号后拉取数据”的正规实现方向。

它仍然需要先完成华为开发者注册、创建应用、配置 iOS Bundle ID/签名信息、申请 Health Kit 服务与具体数据权限，并通过华为审核。是否可以完全不部署 Mianyu 后台，要以接入控制台给该 iOS 应用开放的 SDK/API 和实际授权流程为准：

- 若官方 iOS SDK 能在客户端完成账号授权、令牌管理和数据读取，则可以不依赖 Mianyu 后台；
- 若选用的接口要求服务端持有 secret、签名请求或交换长期凭据，则不能把 secret 放进 iOS App，需要改用路线 B，或另行批准最小服务端；
- “用户能登录华为运动健康”不等于第三方应用自动获得 Health Kit 权限，仍需开发者准入和用户对具体数据范围授权。

### 路线 B：华为运动健康 -> Apple 健康（无需厂商 API 准入）

在“不依赖 Mianyu 后台”且尚未取得 Huawei Health Kit 权限时，可先落地：

```text
华为手表
  -> 华为运动健康 iOS App（厂商负责蓝牙、设备账号和设备云同步）
  -> Apple 健康 / HealthKit（用户逐项授权）
  -> Mianyu iPhone App（只读所需类型、本机计算、本地优先）
  -> Widget / Apple Watch（现有 App Group / WatchConnectivity 最小投影）
```

两条路线都不应直连私有蓝牙协议，也不把健康原始样本上传 CloudKit。路线 A 的令牌只能由华为官方 SDK/安全存储按其合同管理；禁止把口令、client secret 或长期令牌写入日志、UserDefaults、CloudKit。路线 B 能读取哪些数据取决于华为运动健康实际写入 Apple 健康的范围。

## 2. 两条路线如何选择

- iOS 已把 Apple 健康作为第三方健康数据的系统授权与汇聚层；用户可在健康 App 中查看和管理数据来源与访问权限。
- 当前 Mianyu 已使用 `HKHealthStore` 读取活动、心率、HRV、睡眠、血氧、呼吸率、体重、训练等类型，不需要增加华为账号体系或网络同步层。
- Huawei Health Kit 账号路线有机会获得比 Apple 健康桥接更完整的华为设备数据，应先做开发者准入和 iOS SDK PoC。
- HealthKit 桥接开发成本更低，且与当前代码直接兼容，可作为首发方案和账号路线不可用时的降级方案。
- iOS 不允许一个普通第三方 App 直接读取另一个 App 的私有数据库；是否写入 HealthKit 必须由华为运动健康实现并由用户授权。

因此建议决策顺序为：**先申请 Huawei Health Kit iOS 权限并验证纯客户端授权；同时保留 Apple 健康桥接作为可独立运行的基础路径**。抓取账号数据、私有蓝牙协议和非官方聚合服务仍不列为方案。

## 3. Huawei Health Kit 账号路线 PoC 门禁

在写生产代码前完成以下最小验证：

1. 华为开发者控制台可以为当前 iOS Bundle ID 开通 Health Kit。
2. 官方 SDK 支持的最低 iOS 版本与项目部署目标兼容。
3. 列出获批数据 scopes、数据类型、历史回溯范围、频率限制、地区限制和删除接口。
4. 验证登录、取消授权、令牌过期、换华为账号、设备离线补传和账号删除。
5. 用代理/日志检查客户端包中不存在 client secret，令牌只进入 Keychain 或官方 SDK 安全容器。
6. 确认 API 是否允许纯客户端调用；只要文档要求服务端 secret 或服务端签名，本任务就停止该路线，不能用混淆代码代替服务端保密。
7. 建立 `HuaweiHealthProvider` 协议，将厂商 DTO 映射到内部标准模型；不要先写回 HealthKit 再读回来。
8. 数据仍按本地优先处理；华为服务不可用不能阻断 Mianyu 的 HealthKit 与本地功能。

## 4. Apple 健康桥接配置流程

产品内应提供以下引导，而不是让用户登录 Mianyu 后台：

1. 在 iPhone 安装华为运动健康并完成手表配对，确认手表数据已出现在华为运动健康中。
2. 在华为运动健康的隐私/数据共享设置中开启“同步到 Apple 健康”（入口名称可能随地区与版本变化）。
3. 在 iOS 的“健康”App 中给华为运动健康开启其需要写入的数据类型。
4. 在“健康”App 中给 Mianyu 开启对应读取权限。
5. 先打开华为运动健康并等待手表同步，再打开 Mianyu；首版不要承诺手表离线或厂商 App 被系统挂起时的实时到达。
6. 在 Apple 健康中打开某个指标的“数据来源与访问权限”，确认最近样本确实来自华为运动健康，然后再用 Mianyu 自检页确认。

需要在 UI 中明确区分三种状态：未授权、已授权但 Apple 健康无样本、已有可读样本。HealthKit 为保护隐私不会向读取方明确返回“用户拒绝读取”，现有 `HealthAuthorizationCoordinator` 已遵守这一限制。

## 5. 与当前代码的匹配情况

| 能力 | 当前实现 | 华为桥接判断 |
|---|---|---|
| 步数、活动能量、训练 | `HealthKitManager+Activity.swift`、`HealthKitManager+Workout.swift` | Apple 健康出现对应样本后可读；注意手机和手表重复贡献 |
| 心率、静息心率 | `HealthKitManager+Heart.swift` | 可读性取决于华为运动健康实际写入类型 |
| HRV SDNN | `heartRateVariabilitySDNN` | 不能把华为 App 内的 HRV/压力值等同于 HealthKit SDNN；必须以 Apple 健康样本为准 |
| 睡眠 | `HealthKitManager+Sleep.swift` | 已支持多来源区间合并；阶段值是否存在需逐型号验证 |
| 血氧、呼吸率 | 已在授权集合并有查询能力 | 厂商是否写入 Apple 健康及写入频率需验证 |
| 腕温 | `appleSleepingWristTemperature` | Apple 专用语义，不应预期华为体温自动映射到该类型 |
| 压力、身体电量 | Mianyu 本机算法 | HealthKit 没有通用的华为“压力”原始类型；应从可读 HR/HRV/睡眠重新计算，不导入厂商评分 |
| ECG、血压 | 代码有读取入口 | 强依赖型号、地区监管能力和厂商是否写入 HealthKit；默认按不可用设计 |

当前 `registerObserversIfNeeded()` 只监听心率、HRV、睡眠、步数、活动能量、静息心率和训练。其他类型即使由华为运动健康写入，也主要依赖前台/手动全量刷新。

## 6. 目前缺什么

### P0：上线前必须完成

- **真机兼容矩阵**：至少覆盖目标华为手表型号、当前/最低 iOS、华为运动健康中国区与计划发布地区版本；逐项记录 Apple 健康中的实际类型、单位、来源 bundle、时间戳、延迟和删除行为。
- **Huawei Health Kit 准入与 PoC**：确认 iOS 客户端支持、获批 scopes、是否需要服务端 secret，以及账号注销/撤权合同；未完成前不能承诺“登录华为账号即可同步”。
- **桥接自检页**：只在本机展示每个关键 HealthKit 类型“最近样本时间、来源 App 显示名、是否有数据”，不得显示华为账号，也不得上传健康数值或来源清单。
- **来源与重复策略**：当前多数查询汇总所有来源。需要定义手机计步、华为手表、Apple Watch 同时存在时的优先级或统计策略；不能把同一时段的数量简单相加。
- **能力降级**：卡片必须按类型显示“不支持/未同步/暂无数据”，不能用 0 冒充真实测量，也不能由“华为手表已连接”推断某类型可用。
- **隐私文案**：说明数据通过用户授权的 Apple 健康在本机读取；Mianyu 不登录华为账号、不把 HealthKit 原始样本写入 CloudKit。

### P1：建议补齐

- 用 `HKSourceQuery` 或样本的 `sourceRevision` 做来源诊断，但业务逻辑不要写死未经真机确认的 bundle identifier。
- 为主要类型采用 `HKObserverQuery + HKAnchoredObjectQuery` 和本地 anchor，降低全量重扫成本并正确处理更新/删除；anchor 只保存在本机。
- 增加时间窗去重和来源优先级单元测试，睡眠继续使用区间并集，quantity 类型按 HealthKit statistics/source 语义分别处理。
- 增加“最后从 Apple 健康刷新时间”和手动刷新入口；不要把后台 delivery 的 `.immediate` 描述为实时保证。

### 明确不做

- 不逆向华为手表蓝牙协议。
- 不在客户端内置 Huawei client secret、用户口令或自行管理的长期 refresh token；官方 SDK 明确允许的安全令牌流程按其合同实现。
- 不通过 Mianyu 后台中转华为健康数据。
- 不把华为运动健康中的专有压力、睡眠评分当作可从 HealthKit 读取的标准字段。

## 7. 验收用例

1. 仅佩戴华为手表，无 Apple Watch：步数/心率/睡眠在华为运动健康出现后，确认 Apple 健康和 Mianyu 依次可见。
2. 同时携带 iPhone：验证步数、能量不被重复累计。
3. 同时佩戴 Apple Watch：验证来源显示、睡眠重叠合并和主要来源策略。
4. 关闭华为运动健康的 Apple 健康写权限：Mianyu 保留历史本地结果，不把“无新增”显示为 0。
5. 关闭 Mianyu 读取权限：不反复弹空授权框，不声称用户拒绝，只引导检查健康设置。
6. 厂商 App 未打开、手表离线、跨日睡眠、补传旧数据、时区切换、样本删除均需覆盖。
7. 抓取日志与 Crash 附件，确认没有健康数值、华为账号、令牌或自由文本。
8. 账号路线另测：授权 scope 最小化、拒绝部分 scope、token 过期、撤权、换号、账号删除和地区不可用。

## 8. 官方资料

- Apple：[Connect apps and add your health records to Health on iPhone](https://support.apple.com/guide/iphone/connect-apps-and-add-your-health-records-iph5ede58c3d/ios)
- Apple Developer：[Reading data from HealthKit](https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit)
- Apple Developer：[HKObserverQuery](https://developer.apple.com/documentation/healthkit/hkobserverquery)
- Apple Developer：[HKAnchoredObjectQuery](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)
- Huawei Developer：[HUAWEI Health Kit](https://developer.huawei.com/consumer/en/hms/huaweihealth/)
- Huawei Developer：[Health Kit Development Guide](https://developer.huawei.com/consumer/en/doc/development/HMSCore-Guides/dev-process-0000001050166278)
- Apple App Store（厂商发布页）：[HUAWEI Health](https://apps.apple.com/app/huawei-health/id1325481372)

> 文档边界：官方页面能证明系统/平台能力，不代表每个华为手表型号都会把全部指标写入 Apple 健康。发布承诺必须以第 5、6 节的目标型号真机结果为准。
