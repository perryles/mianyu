# Stress 3.1 计算逻辑

本文是 Mianyu 压力算法的计算规范。目录结构、集成链路、缓存兼容、调试和维护清单见同目录 `README.md`。

## 输出口径

- 当前压力：`StressRealtimeEngine` 基于最新生理信号输出的 `StressEvaluation`。
- 今日综合：`StressDailyEngine` 对当天由实时引擎产生的有效当前压力样本进行时间桶聚合。
- 历史重建：只用于图表观察，不参与 3.1 今日综合。

算法版本写入 `StressResult.algorithmVersion`，当前为 `3.1`。不同版本或不同来源的样本不能混合聚合。

## 最低数据要求

当前压力至少满足一组条件：

```text
fresh HR + usable resting-HR baseline
或
fresh HR + usable 30-minute HR trend
或
fresh HRV + usable HRV baseline
```

其中：

- HR 测量后 10 分钟内有效。
- HRV 60 分钟内满权；60 分钟到 4 小时线性降权；4 小时后失效。
- 基线需要值存在，并且 `sampleCount >= minimumSampleCount`。
- 没有静息心率基线时，连续心率设备可以使用最近 5 分钟相对前 5 到 30 分钟的趋势通道。
- HRV 缺失时该维度完全退出加权，不补固定 50；静息心率缺失时不使用统一默认值。
- 睡眠恢复和趋势可以缺失，但会降低置信度。
- 不满足最低条件时返回 unavailable，不产生默认分数。

## 实时分量

所有结果最终限制在 `0...100`。

### HRV 基线偏离

```text
dropRatio = clamp((baselineHRV - currentHRV) / baselineHRV, -0.30, 1.00)
hrvDeviation = clamp(50 + dropRatio * 120)
```

HRV 越低于个人基线，压力分越高。没有可用 HRV 基线时，该项不参与计算。

### 心率基线偏离

```text
hrDeviation = clamp(35 + (currentHR - restingHRBaseline) * 2.2)
```

没有可用静息心率基线时，该项不参与计算。

### 30 分钟趋势

HRV 使用最近 10 分钟与前 10 到 30 分钟的中位数：

```text
ratio = clamp((priorMedian - recentMedian) / baselineHRV, -0.20, 0.60)
hrvTrend = clamp(50 + ratio * 140)
```

心率使用最近 5 分钟与前 5 到 30 分钟的中位数：

```text
hrTrend = clamp(50 + (recentMedian - priorMedian) * 4)
```

趋势窗口一律相对 `input.now` 计算，因此历史回放可复现。

### 睡眠恢复债

恢复分按可用项重新归一化：

| 项目 | 权重 |
| --- | ---: |
| 睡眠时长相对 450 分钟 | 0.30 |
| 睡眠效率 | 0.25 |
| 夜间 HRV 相对基线 | 0.25 |
| 夜间最低心率相对基线 | 0.20 |

```text
recoveryDebt = 100 - recoveryScore
```

没有任何恢复数据时，恢复债不参与实时加权。

### 昼夜节律

昼夜分量根据实际睡眠区间、醒后 90 分钟、习惯睡眠窗口、睡前两小时和傍晚窗口计算。它是上下文修正，不替代生理信号和个人基线。

### 运动上下文

运动类型给出基础身体负荷，心率储备和运动强度继续修正。非运动状态：

```text
workoutBlend = 0
```

运动结束后：

```text
workoutBlend = activeBlend * exp(-minutesSinceEnd / 20)
```

运动中的心理通道会按 `1 - workoutBlend * 0.65` 抑制，避免把运动性心率升高直接解释为精神压力。

## 双通道合成

心理通道：

```text
weightedMean(
  hrvDeviation * 0.32 * hrvFreshness,
  hrDeviation  * 0.22,
  hrvTrend     * 0.14,
  hrTrend      * 0.10,
  recoveryDebt * 0.14,
  circadian    * 0.08
)
```

身体通道：

```text
weightedMean(
  hrDeviation  * 0.28,
  hrTrend      * 0.18,
  hrvDeviation * 0.14 * hrvFreshness,
  workoutLoad  * 0.28,
  recoveryDebt * 0.12
)
```

缺失项不补固定中性值，只按实际参与项重新归一化。最终原始分：

```text
raw = mental * (1 - workoutBlend) + physical * workoutBlend
```

主导因素按各项高于中性点 `50` 的实际加权升压贡献排序，不按未加权原始分或绝对偏差排序。HRV 高于基线、心率低于基线等保护性偏差不会生成升压建议；没有升压因素时解释代码为 `stable_physiology`。

## EMA 与状态滞回

```text
smoothed = alpha * raw + (1 - alpha) * previousSmoothed
```

| 场景 | alpha |
| --- | ---: |
| 稳定序列 | 0.12 |
| 常规变化 | 0.20 |
| 原始分跳变至少 15、跨两级或运动中 | 0.32 |

向高压力状态升级时，原始分必须越过候选状态下界。向低压力状态释放时，平滑分必须低于原状态下界 5 分，避免边界附近反复跳变。

## 状态与 UI 五档

| 分数 | `StressState` | `StressBand` |
| --- | --- | --- |
| 0...14 | recovery | relaxed |
| 15...29 | relaxed | relaxed |
| 30...49 | normal | steady |
| 50...69 | strained | mild |
| 70...84 | highStress | caution |
| 85...100 | overloaded | high |

阈值唯一来源是 `StressRules.swift`。

## 置信度与质量

| 信息 | 权重 |
| --- | ---: |
| 新鲜 HR | 0.25 |
| HRV 及其新鲜度 | 0.25 |
| 静息心率基线样本量 | 0.10 |
| HRV 基线样本量 | 0.10 |
| 30 分钟趋势覆盖 | 0.15 |
| 恢复数据完整度 | 0.15 |

```text
confidence = availableWeightedEvidence / 1.00
```

恢复数据项按其实际可用权重之和贡献 `0...0.15`，不是任意一项存在就获得全部恢复置信度。质量：`confidence < 0.35` 为 low，`0.35..<0.72` 为 medium，`>=0.72` 为 high。

## 今日综合

只接受满足以下条件的样本：当天、分数 `0...100`、质量不是 unavailable、算法版本为当前版本、来源为 `realtime`。

由 HealthKit 历史心率/HRV 重建的七分钟点属于 `reconstructed`，只允许进入曲线与报告，不得写入今日综合样本缓存，也不得标记成实时真值。

1. 按固定 7 分钟时间桶分组。
2. 每桶分数取中位数，置信度取均值，质量取最低值。
3. 至少 4 个桶，首末有效桶跨度至少 30 分钟。
4. 对桶分数计算均值、最新值和 P90。

```text
daily = round(0.70 * bucketMean + 0.20 * latestBucket + 0.10 * bucketP90)
```

今日综合不会再次叠加 HRV、静息心率、睡眠恢复或运动因素。单次异常峰值只通过 P90 的 10% 和所在时间桶参与，不能直接支配全天结果。

## 无 HRV 与缺失数据

- 第三方手表只提供心率和静息心率时，按心率相对个人静息基线计算，HRV 权重退出。
- 没有静息心率、但存在连续心率时，使用最近 5 分钟相对前 5 到 30 分钟的心率趋势。
- 只有孤立心率、没有个人基线也没有趋势时返回 unavailable，不使用默认静息心率制造分数。
- 历史图表按实际可用的 HRV 偏离、心率偏离和心率趋势动态重归一化；任何缺失维度都不会以 0、50 或人群默认值参与。

## 专注任务条件

专注任务条件由 `StressFocusCapacityEngine` 计算，算法版本为 `2.0`。它消费压力结果，但拥有独立的输入、版本、六维合成与置信度合同；完整规范见 `../FocusCapacity/STRESS_FOCUS_CAPACITY_CALCULATION.md`。

```text
stressHeadroom = round(100 * (1 - (clamp(stress, 0, 100) / 100)^1.35))
focusCapacity = round(exp(sum(weight * log(score)) / sum(availableWeight)))
```

压力余量是唯一必需维度。身体电量、睡眠储备、昼夜节律、活动刷新和补水进度按可用性加入；缺失维度退出加权，不补固定中性值或 0 分。综合压力与身体电量已经吸收 HRV、心率和静息心率，本层禁止再次逐项加权。

## unavailable

| 原因 | 条件 |
| --- | --- |
| `noPhysiologicalSignal` | 没有可用的新鲜 HR/HRV |
| `staleHeartRate` | HR 超过 10 分钟 |
| `staleHrv` | HRV 超过 4 小时 |
| `staleResult` | 已计算的当前结果超过 10 分钟，只能作为历史信息 |
| `baselineCalibrating` | 有新鲜信号但对应个人基线不可用 |
| `noDailySamples` | 没有当前版本的当天有效样本 |
| `insufficientDailyCoverage` | 不足 4 个桶或跨度不足 30 分钟 |

unavailable 必须继续向 Presentation 和同步层传播，不能替换为 0、35 或上次有效分数。

## 局限

该算法是消费级传感器上的健康趋势估算，不是医学或心理诊断。运动、咖啡因、感染、药物、传感器佩戴质量、采样稀疏和个体自主神经差异都可能影响结果。权重、7 分钟桶、30 分钟跨度、EMA 和滞回边界仍需真实用户数据验证。
