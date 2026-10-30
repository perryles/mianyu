# AGC / 签名 / 权限 配置清单（PEN-8 对齐 iOS）

本文档记录「眠屿」鸿蒙工程与 iOS 端（`com.boundesu.BioBalance` / 显示名「眠屿」）对齐后的
基础配置，以及上架/联调前需要在 AppGallery Connect（AGC）与签名侧完成的待办项。
未配置真实凭证前，所有 `REPLACE_*` / 待办项保持占位，不影响本地 `assembleHap` 构建。

## 1. 应用标识

| 项 | 鸿蒙（本工程） | iOS（对齐目标） | 状态 |
|---|---|---|---|
| bundleName | `com.boundesu.BioBalance` | Bundle ID `com.boundesu.BioBalance` | ✅ 已对齐 |
| 应用显示名 | `眠屿`（AppScope 与 entry 字符串资源） | CFBundleDisplayName `眠屿` | ✅ 已对齐 |
| vendor | `boundesu` | 组织标识 `boundesu` | ✅ 已对齐 |

> Stage 模型中 `bundleName` 只存在于 `AppScope/app.json5`，`entry/src/main/module.json5`
> 不包含 bundleName 字段（旧 FA 模型才写在 config.json）。已核对 module.json5 无残留旧包名。

## 2. 版本信息

| 项 | 鸿蒙（本工程） | iOS（对齐目标） | 状态 |
|---|---|---|---|
| versionName | `3.0.20` | MARKETING_VERSION `3.0.20` | ✅ 已对齐 |
| versionCode | `1000000`（整数，AGC 唯一递增） | CURRENT_PROJECT_VERSION `1` | ✅ 保留默认，首包上传 AGC 后以 AGC 为准 |
| buildVersion | `1` | — | ✅ 保留 |

> 注意：`versionCode` 每次上传 AGC 必须比上一次大；首次正式包可沿用 `1000000`。

## 3. 图标与启动页

- 应用图标：使用 iOS 主图标素材（`Assets.xcassets/AppIcon.appiconset` 内 1024×1024 图标）作为
  `AppScope/resources/base/media/background.png`，`foreground.png` 为空透明层（layered 图标合成后即原图）。
- 启动页图标：`entry/src/main/resources/base/media/startIcon.png` 使用同一图标（512×512）。
- 状态：✅ 已替换默认模板图标，视觉效果与 iOS 图标一致。

## 4. 权限声明（与 iOS 权限用途说明对齐）

iOS 侧通过 `NSHealthShareUsageDescription` 声明读取心率/睡眠/步数等健康数据的用途。
鸿蒙侧本应用只读取华为运动健康（Health Service Kit `@kit.HealthServiceKit` / `healthStore`），
权限模型是「**AGC 联盟服务审批 + client_id 绑定 + 运行时用户 OAuth 授权**」，与官方
Health Service Kit 示例工程一致——**module.json5 无需声明静态 `requestPermissions`**。

当前实现的数据最小化边界（已在 `entry/src/main/ets/service/HuaweiHealthService.ets` 落地）：

- 只申请读权限：日常活动（步数）、静息心率、睡眠记录；
- `writeDataTypes` 为空，不写入/不删除任何健康数据；
- 健康明细仅本机 `preferences` 存储，日志不包含健康明细；
- 未授权/无数据时显示 `--`，不伪造演示数值。

对齐说明：

| iOS 用途声明 | 鸿蒙对应实现/说明 |
|---|---|
| 读取心率、HRV、睡眠、步数、活动能量等健康数据用于趋势展示与恢复建议 | `healthStore.requestAuthorizations` 仅请求上述三类读数据类型；趋势页仅展示步数/静息心率/睡眠摘要 |
| 数据仅本机/受控使用，最小化采集 | 健康数据仅存本机 preferences，无云端明细上传 |
| 用户可随时撤销授权 | 「我的」页提供撤销运动健康授权入口（`cancelAuthorizations`） |

> 待办（无凭证，未配置）：如需同时读取系统侧健康传感器（如 `@kit.HealthKit` 的计步/心率），
> 才需要在 `module.json5` 增加 `requestPermissions`（如 `ohos.permission.READ_HEALTH_DATA`）。
> 当前功能走 Health Service Kit，不新增。

> PEN-11 更新：读取范围盘点/对齐矩阵、隐私边界与备份收窄、未来云同步字段白名单设计
> 见 `DATA_PRIVACY_ALIGNMENT.md`。备份口径已收窄：`backup_config.json` 的
> `allowToBackupRestore` 改为 `false`（应用数据不参与系统云备份/云恢复），以对齐
> iOS「HealthKit 原始样本禁入云」红线。


## 5. AGC、账号与 Cloud DB 配置清单（待办，无凭证）

以下为正式联调/上架前必须由具备 AGC 权限的账号完成的步骤，当前工程保持占位：

- [ ] 在 AGC 创建/关联应用，包名填 `com.boundesu.BioBalance`。
- [ ] 申请 **Health Service Kit** 服务；在联盟卡片申请数据权限：
      「日常活动数据（读）」「心率数据（读）」「睡眠数据（读）」。
- [ ] 开通 **Account Kit** 与 **Cloud Foundation Kit / Cloud DB**，创建 zone `mianyu_sync`。
- [ ] 将 `MianyuSyncRecord` 的 create/update/read ACL 绑定到 Cloud DB 当前认证 principal：仅当认证
      OpenID 与记录 `accountId` 完全相等时允许操作；禁止匿名写、跨 principal 写和仅依赖客户端过滤。
      若 AGC 控制台/当前服务版本无法表达并验证该规则，云同步不得上线。
- [ ] 创建 `MianyuSyncRecord` schema：`recordId` 为账号不透明键分区后的物理主键（客户端自动编码，
      本地仍使用逻辑 recordId）；其余字段必须与
      `AgcCloudSyncTransport.ets` 完全一致；为 `accountId + revision + recordId` 建联合索引，以支持
      稳定复合分页。当前 SDK 不提供 change token，客户端采用每轮全重叠回放与去重；不得增加白名单外字段。
- [ ] 将 AGC 生成的 **Client ID** 填入 `entry/src/main/module.json5`
      `metadata[].name = "client_id"` 的 `value`（当前占位 `REPLACE_WITH_AGC_CLIENT_ID`）。
- [ ] 配置签名：
      - DevEco Studio `File > Project Structure > Signing Configs` 生成/选择调试与发布证书；
      - 将生成的 SHA256 证书指纹添加到 AGC 应用配置；
      - 在 `build-profile.json5` 的 `app.signingConfigs` 中登记签名（当前为空数组，未签名构建仅出 unsigned hap）。
- [ ] 选择安装了「华为运动健康」且已登录华为账号的真机，完成 OAuth 授权联调。
- [ ] 使用两个登录同一华为账号的真机验证：默认关闭、离线本地保存、恢复后 outbox 重试、全重叠
      分页覆盖迟到记录、逻辑版本冲突、退出/换号后旧 generation 停止同步且竞态写入为 0；从 Cloud DB 控制台抽查无原始
      样本/用药/症状/自由文本/凭据。

## 6. 相关文件

- `AppScope/app.json5`：bundleName / vendor / 版本
- `AppScope/resources/base/element/string.json`：应用显示名
- `entry/src/main/module.json5`：client_id 占位、Ability 配置
- `entry/src/main/ets/service/HuaweiAccountService.ets`：Account Kit 登录/退出，只使用 OpenID
- `entry/src/main/ets/service/AgcCloudSyncTransport.ets`：Cloud DB zone/schema 运行时映射
- `entry/src/main/resources/base/media/*`：启动页图标与 layered 图标
- `entry/src/main/ets/service/HuaweiHealthService.ets`：健康数据只读授权实现
