# 鸿蒙 .ets 源码恢复说明（PEN-7）

2026-08 排查确认：`entry/src/main/ets/` 源码从未进入 git 历史，工作树为空；
但 `entry/build/`（被误提交的构建产物）中保留了完整的编译中间产物，据此恢复/重建了全部源码。

## 恢复来源

- `entry/build/default/cache/.../esmodule/debug/entry/src/main/ets/pages/Index.ts`
  —— 由原始 `Index.ets` 编译生成的 ArkUI 命令式代码（2263 行），含全部状态/逻辑/文案。
- `entry/build/.../model/HealthScoreEngine.ts`、`entrybackupability/EntryBackupAbility.ts`
  —— 与原始 .ets 几乎逐行一致。
- `entry/build/.../service/HuaweiHealthService.protoBin`
  —— Health Service Kit 封装类的编译字节码，通过字符串表还原了类结构、方法、错误文案。
- `entry/build/default/intermediates/loader_out/default/ets/modules 2.abc`
  —— 全量字节码，确认 EntryAbility 为标准模板（onCreate/onWindowStageCreate/...）。

## 恢复/重建的文件

| 文件 | 状态 |
|---|---|
| `entry/src/main/ets/entryability/EntryAbility.ets` | 重建（标准模板 + loadContent('pages/Index')） |
| `entry/src/main/ets/entrybackupability/EntryBackupAbility.ets` | 恢复（与原编译产物一致） |
| `entry/src/main/ets/model/HealthScoreEngine.ets` | 恢复（与原编译产物一致，单测可验证） |
| `entry/src/main/ets/service/HuaweiHealthService.ets` | 重建（按 protoBin 还原 API 面与文案） |
| `entry/src/main/ets/pages/Index.ets` | 重建（四 Tab：首页/记录/趋势/我的，按编译产物还原） |

附带变更：`AppScope/.../string.json`、`entry/.../string.json` 应用显示名改为「眠屿」（对齐 iOS）。

## 验证

- `hvigorw --mode module -p product=default assembleHap` 构建成功（产物 unsigned hap，与原始一致，未配置签名）。
- `HealthScoreEngine` 单测用例已按公式人工验算通过（62 / 81 / 51 / 50 / 0）。

## 已知限制 / 下一步

1. 仓库提交的 `oh_modules/@ohos/hypium` 不完整（缺 `src/main` 源码），`hvigorw test`
   无法编译；需要 `ohpm install` 后提交完整依赖，或让 CI 在构建前执行 `ohpm install`。
2. `module.json5` 的 `client_id` 仍为占位符 `REPLACE_WITH_AGC_CLIENT_ID`；
   联调华为运动健康授权前需替换为真实 AGC Client ID 并配置签名。
3. `entry/build/` 被提交进 git（应加入 .gitignore），保留它是为了恢复溯源，后续可清理。
4. 隐私红线：健康数据仅本机 `preferences` 存储 + 只读授权读取华为运动健康，日志不含健康明细。
