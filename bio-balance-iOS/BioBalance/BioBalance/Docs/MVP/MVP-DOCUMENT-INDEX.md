# Mianyu MVP 文档索引

## 1. 编号规则

MVP 文档统一使用 `MVP-<领域分类号>-<顺序号>`：

| 分类号 | 领域 | 数据边界 |
|---|---|---|
| `R01` | 恢复与周期回顾 | 本机派生与本机 SwiftData，不新增 CloudKit schema |
| `B01` | 行为与个人实验 | 用户主动记录，本机 SwiftData，不宣称因果 |
| `M01` | 用药与症状安全 | 复用现有药症记录，本机派生，不提供诊断或调药建议 |
| `P01` | 健康档案与长期画像 | 复用本机聚合摘要，不新增健康或云端字段 |

## 2. 文档清单

| 文档号 | 优先级 | 功能 | 状态 | 实现入口 |
|---|---|---|---|---|
| `MVP-R01-001` | P1 | [恢复行动闭环](./MVP-R01-001-Recovery-Action-Loop.md) | 已完成首期 | `DailyRecoveryPlanCard`、`RecoveryActionLoopView` |
| `MVP-R01-002` | P1 | [每周健康回顾](./MVP-R01-002-Weekly-Health-Review.md) | 已完成首期 | `WeeklyReportView` |
| `MVP-B01-001` | P2 | [个人生活实验](./MVP-B01-001-Personal-Life-Experiment.md) | 已完成首期 | `PersonalLifeExperimentView` |
| `MVP-M01-001` | P2 | [用药与症状回看](./MVP-M01-001-Medication-Symptom-Review.md) | 已完成首期 | `MedicationSymptomsHubView` |
| `MVP-P01-001` | P1 | [健康档案 UI 与一级页面衔接](./MVP-P01-001-Health-Profile-UI.md) | 已完成可读性第二阶段 | `HealthProfileView`、`DashboardView`、`HealthHubView` |
| `MVP-P01-002` | P1 | [健康重点判断与睡眠承接](./MVP-P01-002-Health-Focus-Sleep-Flow.md) | 已完成第二阶段 | `HealthHubPresentationBuilder`、`HealthHubView`、`SleepView` |

## 3. 通用发布约束

1. 所有功能本地优先，离线时可记录和回看。
2. 缺失数据不按零值参与平均数、趋势或评分。
3. 生成式 AI 不产生事实数值；MVP 均使用确定性规则。
4. 不新增 CloudKit record type；若未来需要跨设备同步，必须先更新 `ICLOUD_DATA_ARCHITECTURE.md`。
5. 文案不添加动画，用户可见文案进入 `Localizable.xcstrings`。
6. 健康变化、行动、用药与症状的时间重合只描述为观察线索，不声称因果或诊断。
