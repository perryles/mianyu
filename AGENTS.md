# AGENTS.md — bio-balance 仓库根

本仓库是 monorepo，包含多个独立子项目。请优先阅读所在子目录的作用域化 AGENTS.md；子目录指令与本文件冲突时以子目录为准。

## 子项目路由

| 目录 | 内容 | 技术栈 | 作用域化指令 |
|---|---|---|---|
| `bio-balance-iOS/` | iOS / watchOS / Widget 应用（核心端） | Swift / SwiftUI / SwiftData / HealthKit / CloudKit | `bio-balance-iOS/AGENTS.md` |
| `bio-balance-Harmony/` | HarmonyOS 应用（本地优先、离线可用） | ArkTS / ArkUI / Preferences | 暂无 |
| `bio-balance-admin-web/` | 管理后台 Web | Vue 3 / TypeScript / Vite / Naive UI / UnoCSS | 暂无 |
| `bio-balance-backend/` | **可选**后端（仅管理后台/AI 编排；App 端多设备/云同步使用 iCloud/CloudKit，**不依赖本后端**） | Spring Boot 3.x / Sa-Token / MyBatis-Plus / Redis / WebSocket | 暂无 |

**架构方向（硬性）**：多设备/云同步统一走 iOS iCloud/CloudKit，不依赖 Java 后端；`bio-balance-backend` 为可选组件，只服务于管理后台与 AI 编排。

## 按任务读取的权威文档

| 文档 | 何时必读 |
|---|---|
| `bio-balance-iOS/AGENTS.md` | iOS / watchOS / Widget 任务；具体文档、CloudKit 边界和验证规则以该文件为准 |
| `bio-balance-Harmony/README.md` | 鸿蒙任务需要构建、运行或确认工程约定时 |
| `README.md`（仓库根） | 需要仓库整体定位或首次环境设置时 |

## 设计约束

- **文字不加动效**：所有文案（含 Widget / Complication / 鸿蒙端）不得添加动画效果。
- **显示名**：中文「眠屿」，英文 `Mianyu`，跨端（iOS / HarmonyOS / Widget / Complications）保持一致。
- **多语言本地化**：iOS 用户可见文案走 `Localizable.xcstrings` / `InfoPlist.xcstrings`；鸿蒙端文案集中在资源文件，禁止硬编码散落。

## 工作流指引

### 构建与测试

只验证受影响的子项目：

| 子项目 | 默认验证 | 按需操作 |
|---|---|---|
| iOS | 在 `bio-balance-iOS/BioBalance/` 做 Debug 模拟器构建，并按 `bio-balance-iOS/AGENTS.md` 运行聚焦测试 | Release、真机和 CloudKit 完整矩阵按任务需要执行；若模拟器不可用，先用 `xcrun simctl list devices available` 选择已安装设备 |
| HarmonyOS | 按 `bio-balance-Harmony/README.md` 构建未签名 HAP | 签名或运行按任务需要执行 |
| 管理后台 | 在 `bio-balance-admin-web/` 运行与改动相关的 `pnpm run build`、`pnpm run typecheck` 或 `pnpm run lint` | 仅依赖缺失或清单变更时运行 `pnpm install`；仅需本地服务器时运行 `pnpm run dev` |
| 可选后端 | 在 `bio-balance-backend/` 运行 `mvn -q -pl ruoyi-server -am test` | 仅需本地服务器时运行 `mvn -q -pl ruoyi-server -am spring-boot:run -DskipTests` |

### 编码规范

- **隐私优先**：新功能涉及数据采集、持久化、云、日志或共享时做数据最小化评估；相关字段必须走白名单合同。
- **范围限定**：不要跨子项目"顺手"修改；一次任务的变更应限定在其所属子目录内，除非任务明确要求跨端。
- **跨端一致性**：跨端一致性是结果约束；任务未明确要求跨端修改时，只修改当前子项目，并报告其他端可能需要的后续调整。
- **可编译**：完成一个连贯改动后构建受影响目标；高风险改动可分阶段验证。鸿蒙改动保持 hvigor 可构建。
- **完成条件**：实现请求、运行与改动直接相关的可用验证，并修复由本次改动导致的失败；无法运行的验证在交付时说明。
