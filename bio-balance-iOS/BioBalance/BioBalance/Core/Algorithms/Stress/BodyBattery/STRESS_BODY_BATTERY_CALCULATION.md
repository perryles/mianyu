# 身体电量算法规范

## 1. 定位与边界

身体电量是 Mianyu 对“夜间恢复预算减去日内生理负荷”的可解释估算，值域为 `5...100`。它不是能量、热量或医学诊断，也不是 Garmin Body Battery 的复刻。

算法、输入模型、参数和公式只能位于 `Core/Algorithms/Stress/BodyBattery`：

- `Domain/StressBodyBatteryModels.swift`：恢复与负荷领域输入模型。
- `Adapters/StressBodyBatteryHealthKitAdapter.swift`：HealthKit 数据到身体电量输入的转换。
- `Engine/StressBodyBatteryRules.swift`：权重、阈值、归一化和衰减参数。
- `Engine/StressBodyBatteryEngine.swift`：恢复评分、个人基线和日内轨迹编排。

SwiftUI、ViewModel、Watch、Widget 和其他展示层只负责读取数据、传入参数和展示输出，不得复制权重、阈值或用 `100 - stress` 替代身体电量。

`Rules` 是参数真值来源，`Engine` 是计算流程真值来源。参数调整只修改 `Rules` 并同步本文档；轨迹去重、样本筛选、时间分段和积分顺序保留在 `Engine`，避免规则常量与流程编排再次混在一个文件中。

## 2. 输出口径

| 口径 | API | 含义 |
| --- | --- | --- |
| 醒来电量 | `recoveryScore(input:)` | 根据昨夜恢复和个人基线确定当天起点 |
| 当前电量 | `currentValue(...)` | 返回日内轨迹的最后一个点 |
| 日内轨迹 | `trajectory(...)` | 从醒来到终点分段积分后的连续估算 |
| 历史日级估算 | `estimatedDailyLevel(...)` | 缺少逐日恢复与负荷明细时的降级估算 |

`trajectory` 是当前电量的唯一真值来源，`currentValue` 不实现第二套公式。

## 3. 数据维度

### 3.1 夜间恢复

| 维度 | HealthKit / 应用来源 | 有效条件 | 权重 |
| --- | --- | --- | ---: |
| 睡眠时长 | 睡眠分析 | `sleepMinutes > 0` | 0.20 |
| 睡眠效率 | 睡眠区间统计 | `sleepEfficiency > 0` | 0.09 |
| 深睡 + REM 比例 | 睡眠阶段 | 恢复性阶段分钟数 `> 0` | 0.06 |
| 夜间 HRV | SDNN + 个人基线 | 当前值和基线均 `> 0` | 0.25 |
| 夜间平均心率 | 夜间 HR + 个人基线 | 当前值和基线均 `> 0` | 0.15 |
| 夜间呼吸频率 | Respiratory Rate + 个人基线 | 当前值和基线均 `> 0` | 0.10 |
| 睡眠腕温 | Apple Sleeping Wrist Temperature + 个人基线 | 当前值和基线均为有限值 | 0.10 |
| 睡眠呼吸干扰 | Apple Sleeping Breathing Disturbances + 个人基线 | 当前值和基线均 `>= 0` | 0.05 |

夜间平均心率缺失时，可成对回退到静息心率和静息心率基线。不能将夜间心率与静息心率基线交叉配对。

综合睡眠评分不是第九个并列维度。只有睡眠时长、睡眠效率和恢复性睡眠阶段都不可用时，才以 `sleepScoreFallback`、权重 `0.15` 作为回退，避免把睡眠时长重复计分。

### 3.2 日内负荷

| 维度 | HealthKit / 应用来源 | 作用 |
| --- | --- | --- |
| 综合压力 | `Stress` 实时/历史点 | 表示心理与生理综合负荷 |
| 体力强度 | `HKQuantityTypeIdentifierPhysicalEffort` | 以 kcal/(kg*hr)，即 MET，描述当前活动强度 |
| 训练努力 | `WorkoutEffortScore` | 形成训练结束后的恢复债 |
| 估算训练努力 | `EstimatedWorkoutEffortScore` | 实际评分缺失时的降权回退 |
| 训练负荷趋势 | 最近 7 天相对 28 天 | 近期负荷堆积时小幅放大耗电 |

iOS 18+ 使用 `HKWorkoutEffortRelationshipQueryDescriptor` 将训练努力样本关联到具体 `HKWorkout`。同一关系优先取实际训练努力评分，只有实际值缺失时才取估算值。

## 4. 缺失数据原则

1. 缺失分量不补 0、不补固定中性值，只对实际可用分量重新归一化。
2. 需要个人基线的生命体征必须成对存在，否则该分量退出评分。
3. 原始睡眠维度存在时，不叠加综合睡眠评分。
4. `physicalEffort` 缺失时退化为原压力耗电，不把缺失解释为静止。
5. 训练努力缺失时不虚构训练后恢复债。
6. 没有恢复、压力和负荷证据时返回 `nil` / 空轨迹。

## 5. 醒来电量

所有分量分先限制在 `0...100`。

### 5.1 睡眠分量

```text
durationScore = sleepMinutes / max(sleepGoalMinutes, 1) * 100

efficiencyScore = (sleepEfficiency - 0.70) / 0.25 * 100

restorativeRatio = (deepSleepMinutes + remSleepMinutes) / sleepMinutes
restorativeScore = (restorativeRatio - 0.18) / 0.27 * 100
```

效率 70% 对应 0 分，95% 对应 100 分。深睡与 REM 合计占比 18% 对应 0 分，45% 对应 100 分。这些边界只用于连续归一化，不是医学异常阈值。

### 5.2 HRV

```text
hrvDelta = clamp((nightlyHrv - baselineHrv) / baselineHrv, -0.50, 0.40)
hrvScore = 75 + hrvDelta * 100
```

HRV 等于个人基线时为 75 分；低 20% 时为 55 分；高 20% 时为 95 分。

### 5.3 夜间心率

```text
heartRateRise = clamp((currentHeartRate - baselineHeartRate) / baselineHeartRate, -0.15, 0.30)
heartRateScore = 75 - heartRateRise * 200
```

心率等于个人基线时为 75 分；高 10% 时为 55 分；低 5% 时为 85 分。

### 5.4 呼吸频率

```text
respiratoryDeviation = abs(nightlyRespiratoryRate - baseline) / baseline
respiratoryScore = 95 - respiratoryDeviation * 250
```

双向偏离个人基线都会降低恢复分，避免使用固定人群阈值。

### 5.5 睡眠腕温

```text
temperatureDeviation = abs(sleepingWristTemperature - baseline)
temperatureScore = 95 - temperatureDeviation * 30
```

腕温按摄氏度绝对偏差评分。升高和降低都视为恢复稳定性下降的证据。

### 5.6 睡眠呼吸干扰

```text
disturbanceRise = max(0, disturbances - baseline) / max(baseline, 1)
disturbanceScore = 95 - disturbanceRise * 180
```

只惩罚高于个人基线的干扰，低于基线不额外奖励到 95 分以上。分母下限允许长期零干扰的用户建立有效基线，同时避免除零。

### 5.7 动态归一化

```text
recoveryScore = round(
  sum(availableComponentScore * componentWeight) /
  sum(availableComponentWeight)
)
recoveryScore = clamp(recoveryScore, 5, 100)
```

没有任何有效恢复分量时返回 `nil`。动态归一化保证缺少腕温或呼吸干扰的设备不会因为“没采到”而被扣分，但数据越少，估算依据也越少。

## 6. 样本与时间预处理

### 6.1 重复时间戳

压力点按 `timestamp` 去重，相同时间戳后出现的值覆盖先出现的值，再按时间升序排列。不得使用会因重复 key 崩溃的 `Dictionary(uniqueKeysWithValues:)`。

该规则保证输出 `TimeSeriesPoint.id` 唯一，并修复重复时间戳触发的：

```text
Fatal error: Duplicate values for key
```

### 6.2 有效样本

- 压力：`value > 0` 且样本时间不晚于终点。
- 体力强度：MET 为有限正数，且 `endDate > startDate`。
- 训练努力：评分和时长均为有限正数，训练结束时间不晚于终点。
- 未来样本不进入本次轨迹。

### 6.3 醒来时间

1. 实际醒来时间与终点属于同一自然日且不晚于终点时，使用实际值。
2. 否则使用当天 `07:00`。
3. 终点早于 `07:00` 时，将醒来时间收缩到终点。

## 7. 初始电量降级

初始电量按以下优先级确定：

1. 有恢复分：直接作为醒来电量。
2. 无恢复分但有压力或负荷：使用降级起点。
3. 恢复、压力和负荷都没有：返回空轨迹。

```text
fallbackStart = clamp(78 - initialStress * 0.25, 5, 100)
```

只有恢复分且完全没有日内负荷证据时，轨迹保持水平，不虚构耗电。

## 8. 日内负荷融合

积分区间会在压力样本、体力强度样本边界和训练后 `0/1/3/6/12` 小时节点处分段。每段以中点近似当前负荷，内部用 `Double` 连续积分。

### 8.1 压力负荷

相邻压力点使用梯形近似：

```text
intervalStress = (previousStress + currentStress) / 2
stressLoad = clamp(intervalStress, 0, 100) / 100
```

最后一个压力点到终点使用 `fallbackStress`；未提供时使用最后一个有效压力点。

### 8.2 体力负荷

```text
averageMET = mean(activePhysicalEffortSamples)
physicalLoad = clamp((averageMET - 1.5) / 6.5, 0, 1)
```

1.5 MET 以下不额外增加体力负荷，8 MET 及以上达到满负荷。重叠样本取均值，避免来源重复时直接累加。

### 8.3 防重复计分

综合压力可能已经因运动心率升高，因此体力负荷不能与压力直接相加：

```text
combinedLoad = 1 - (1 - stressLoad) * (1 - physicalLoad * 0.70)
```

该概率并集形式只补充压力尚未解释的负荷空间；体力负荷最多以 70% 强度参与。压力和体力都高时，结果仍不会超过 1。

### 8.4 训练后恢复债

每次训练事件：

```text
normalizedEffort = clamp(workoutEffortScore, 1, 10) / 10
durationFactor = clamp(sqrt(durationMinutes / 30), 0.65, 1.60)
sourceFactor = estimated ? 0.90 : 1.00

eventDebt(t) = 0.90
  * normalizedEffort
  * durationFactor
  * sourceFactor
  * exp(-hoursSinceWorkoutEnd / 4)
```

训练后恢复债最多保留 12 小时，多次训练可叠加。训练努力不再次描述训练期间的瞬时 MET，只描述训练结束后的恢复成本。

### 8.5 7 天 / 28 天训练负荷

```text
eventLoad = effortScore * durationMinutes
loadRatio = clamp(recent7DayLoad * 4 / recent28DayLoad, 0, 2)
trainingLoadMultiplier = clamp(1 + max(0, loadRatio - 1) * 0.15, 1, 1.15)
```

至少有 3 条 28 天训练事件才启用。近期负荷低于或等于个人 28 天节奏时不奖励额外电量；明显堆积时耗电最多增加 15%。

## 9. 日内积分

```text
drainPerHour = 0.7
  + (combinedLoad^1.6 * 5.0 + postWorkoutLoad)
  * trainingLoadMultiplier

recoveryPerHour =
  stress < 20
  && physicalLoad < 0.05
  && postWorkoutLoad < 0.10
    ? (20 - stress) / 20 * 1.2
    : 0

nextBattery = clamp(
  currentBattery + (recoveryPerHour - drainPerHour) * elapsedHours,
  5,
  100
)
```

`0.7/小时` 是清醒基础消耗。只有压力、体力负荷和训练后恢复债同时很低时才允许缓慢回充，避免把运动后的低压力误判为恢复。

没有任何新负荷数据时，`physicalLoad = 0`、`postWorkoutLoad = 0`、`trainingLoadMultiplier = 1`，公式严格退化为原压力耗电模型。

## 10. 输出轨迹

正常轨迹包含：

1. 醒来时间的初始电量点。
2. 每个去重后压力样本对应的电量点。
3. 终点对应的最终电量点。

同一时间戳只保留一个输出点。内部连续积分后，输出值才四舍五入为 `Int`，避免高频样本积累舍入误差。

## 11. 历史降级估算

周、月、年区间通常没有逐日完整恢复和 MET/训练努力明细，因此使用：

```text
estimatedDailyLevel = round(clamp(82 - averageStress * 0.55, 5, 100))
```

这只能描述为“日级估算”，不能描述为某个时刻的精确剩余电量。当前自然日有实时轨迹时，应以实时结果替换当天降级点。

## 12. 数据流

```text
HealthKit
  sleep stages / HRV / overnight HR / respiratory rate
  wrist temperature / breathing disturbances
  physical effort / workout effort relationships
        |
        v
HealthKitManager
        |
        v
StressHealthKitAdapter
  -> StressBodyBatteryRecoveryInput
  -> StressBodyBatteryLoadInput
        |
        v
StressBodyBatteryEngine
  -> recoveryScore
  -> trajectory / currentValue
        |
        +--> Dashboard display
        +--> body-battery detail display
        +--> StressFocusCapacityEngine input
```

## 13. 校准与验证

参数调整必须同时满足：

- 使用匿名化的个人纵向数据验证，不能只比较不同用户的绝对值。
- 分别评估醒来分、日内下降斜率和主观疲劳/准备度的一致性。
- 对缺失维度、无 Apple Watch、无训练努力评分和仅压力数据做降级测试。
- 保留重复时间戳、未来样本、零时长睡眠和重叠 MET 样本测试。
- 不以单个生命体征诊断疾病；明显异常只降低恢复稳定性评分。

当前算法是确定性 `1.1` 规则模型。后续基于真实反馈校准时应优先调整个人基线窗口与连续映射曲线，避免继续堆叠高度相关的新权重。
