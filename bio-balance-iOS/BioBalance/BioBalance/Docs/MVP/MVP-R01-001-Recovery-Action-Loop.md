# MVP-R01-001 恢复行动闭环

## 1. 文档信息

- 分类：`R01 恢复与周期回顾`
- 优先级：P1
- 首发端：iPhone；复用现有 Watch/Widget 状态投影
- 状态：已完成首期
- 数据位置：本机 SwiftData `daily-recovery-orchestration`

## 2. 用户问题

用户已经能看到每日恢复建议并标记完成、稍后或跳过，但完成后缺少轻量体感反馈和阶段回看，无法确认哪些行动更容易坚持。

## 3. MVP 范围

1. 保留现有每日一个主目标、最多两个辅助行动的预算。
2. 行动支持完成、稍后、跳过、不适用和撤销。
3. 完成后可选记录“更舒服 / 差不多 / 更吃力”三档体感；不要求填写自由文本。
4. 提供最近 7 天回看：计划行动数、已处理数、完成数、完成率和体感反馈分布。
5. 回看只描述完成事实和主观体感，不把指标变化归因于行动。
6. Watch/Widget 写回若缺少标题或日期，仍可保存状态；iPhone 后续读取时保守展示。

## 4. 数据合同

扩展现有 `DailyRecoveryActionStateRecord`，新增可选字段以兼容旧 payload：

- `actionTitle: String?`
- `plannedFor: Date?`
- `feedback: DailyRecoveryActionFeedback?`
- `feedbackUpdatedAt: Date?`

稳定主键仍为 `actionID`。反馈更新不得改变行动状态，不进入 App Group、WCSession payload 或 CloudKit。

## 5. 状态规则

1. 只有 `completed` 状态允许写入体感反馈。
2. 撤销处理时恢复为 `pending` 并清除体感反馈，不删除原计划记录或缩小完成率分母。
3. 重复写入同一状态按 `updatedAt` 覆盖，不生成重复记录。
4. 7 天汇总按 `plannedFor` 过滤；旧记录缺少该字段时回退到 `updatedAt`。
5. `snoozed` 属于已处理但不属于已完成。

## 6. 页面结构

1. 每日行动卡：状态操作 + 完成后的三档体感。
2. 恢复闭环入口卡：显示最近 7 天完成率和反馈覆盖。
3. 回看页：完成事实、反馈分布、保守解释和隐私说明。

## 7. 不做

- 不自动判断行动疗效。
- 不因跳过或不适用降低健康评分。
- 不上传自由文本、行动明细或主观体感到 CloudKit。
- 不自动安排运动治疗、用药或高风险行为。

## 8. 验收标准

1. 完成行动后可以保存、修改和清除体感反馈。
2. 最近 7 天统计不重复计数，完成率分母只包含实际计划行动。
3. 无记录时展示诚实空态。
4. 旧版行动状态可以正常解码。
5. Widget 重复写回不会产生重复 Outcome。
6. VoiceOver 能读出行动标题、状态和体感按钮。

## 9. 聚焦测试

- `RecoveryActionLoopEngineTests`
- `DailyRecoveryOrchestrationStoreTests` 中的兼容解码与反馈更新用例
