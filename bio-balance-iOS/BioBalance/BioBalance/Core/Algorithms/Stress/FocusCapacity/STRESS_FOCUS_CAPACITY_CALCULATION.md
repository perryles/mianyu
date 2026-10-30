# Stress Focus Capacity 2.0 计算规范

本文是 Mianyu 专注任务条件算法的唯一完整规范，对应 `StressFocusCapacityEngine` 2.0。界面文案使用“专注能力”，代码、类型和文件统一使用 `StressFocusCapacity`。

专注能力不是认知测验、生产力评分、注意力障碍筛查或医疗结论。它只回答一个较窄的问题：基于当前可用健康与行为数据，此刻适合安排多大强度、持续多久的认知任务。

## 实现边界

| 职责 | 文件 |
| --- | --- |
| 输入、输出、分档和内容模型 | `Domain/StressFocusCapacityModels.swift` |
| 六维评分、缺失数据和置信度 | `Engine/StressFocusCapacityEngine.swift` |
| 状态、说明、分量和行动文案 | `Presentation/StressFocusCapacityPresentation.swift` |
| 今日页数据装配与 SwiftUI 展示 | `Views/Today/Dashboard/DashboardView.swift` |
| 算法边界测试 | `BioBalanceTests/Stress/StressFocusCapacityEngineTests.swift` |

`Core/Algorithms/Stress` 不依赖 SwiftUI。页面只能装配 `StressFocusCapacityInput`、调用引擎并渲染 Assessment，不得复制公式、权重或阈值。

## 输出合同

`StressFocusCapacityAssessment` 输出：

| 字段 | 含义 |
| --- | --- |
| `algorithmVersion` | 当前固定为 `2.0` |
| `score` | `0...100`；综合压力缺失时为 `nil` |
| `band` | `unavailable / depleted / limited / available / strong` |
| `confidence` | `0...1`；综合压力缺失时为 `nil` |
| `stressHeadroom` | 非线性压力余量 |
| `bodyBatteryScore` | 身体电量输入的规范化值 |
| `sleepReadiness` | 睡眠认知储备 |
| `circadianReadiness` | 醒后昼夜节律适配度 |
| `movementReadiness` | 连续久坐对应的活动刷新度 |
| `hydrationReadiness` | 按醒后进度校正的补水状态 |
| `availableDimensionCount` | 本次实际参与合成的维度数，范围 `0...6`；unavailable 时为 0 |

`score == nil` 与 `score == 0` 含义不同：前者表示缺少必需输入，后者表示已有输入明确落在最低任务条件。

## 数据流

```text
StressDailyEngine / StressRealtimeEngine
  -> cardStressAssessment
StressBodyBatteryEngine
  -> bodyBatteryCurrentValue
SleepViewModel
  -> sleepMinutes / sleepGoalMinutes / sleepScore / wakeDate
DashboardSedentaryState
  -> sedentaryMinutes
HabitViewModel
  -> waterIntakeMl / waterTargetMl
StressFocusCapacityInput
  -> StressFocusCapacityEngine
  -> StressFocusCapacityAssessment
  -> StressFocusCapacityPresentation
  -> 今日页卡片与详情页
```

今日页优先使用有效的今日综合压力，缺失时回退当前压力。专注引擎不自行读取 HealthKit、UserDefaults、缓存或网络。

## 输入有效性

| 输入 | 是否必需 | 有效规则 | 无效时处理 |
| --- | --- | --- | --- |
| `stressScore` | 是 | 任意整数，进入引擎后限制到 `0...100` | `nil` 直接返回 unavailable |
| `bodyBatteryScore` | 否 | 存在时限制到 `0...100` | 退出加权 |
| `stressConfidence` | 否 | 有限数，限制到 `0...1` | 按压力质量回退 |
| `sleepMinutes` | 否 | `> 0`，且 `sleepGoalMinutes > 0` | 时长项退出睡眠子评分 |
| `sleepScore` | 否 | `> 0`，限制到 `0...100` | 评分项退出睡眠子评分 |
| `wakeDate` | 否 | 相对 `now` 的醒后时长在 `0...24` 小时 | 节律与补水维度退出 |
| `sedentaryMinutes` | 否 | 页面确认久坐来源可靠后传入；负数按 0 | 退出加权 |
| `waterIntakeMl` | 否 | `> 0`，且 `waterTargetMl > 0` | 退出加权，不把 0 当作脱水证据 |

今日页只有在久坐状态来源为 ready，且已经出现真实久坐或最近活动证据时才传入 `sedentaryMinutes`。默认等待态不得伪装成“刚活动完”。

## 六维权重

| 维度 | 符号 | 标称权重 |
| --- | --- | ---: |
| 压力余量 | `S` | 0.45 |
| 身体电量 | `B` | 0.20 |
| 睡眠储备 | `L` | 0.15 |
| 昼夜节律 | `C` | 0.10 |
| 活动刷新 | `M` | 0.07 |
| 补水进度 | `H` | 0.03 |

权重总和为 `1.00`。压力余量是唯一必需维度，其余维度按数据可用性动态加入。

## 维度计算

所有维度最终四舍五入并限制到 `0...100`。

### 压力余量

先限制综合压力：

```text
p = clamp(stressScore, 0, 100) / 100
S = round(100 * (1 - p^1.35))
```

指数 `1.35` 让高压力区间比线性反转更敏感。压力为 100 时余量为 0；页面不得恢复旧的 `100 - stress * 0.72` 公式。

### 身体电量

```text
B = clamp(bodyBatteryScore, 0, 100)
```

身体电量由 `StressBodyBatteryEngine` 负责夜间恢复基线与日内负荷积分。专注引擎不重新计算 HRV、心率、训练负荷或夜间恢复。

### 睡眠储备

时长项：

```text
durationRatio = clamp(sleepMinutes / sleepGoalMinutes, 0, 1)
durationScore = durationRatio * 100
```

评分项：

```text
qualityScore = clamp(sleepScore, 0, 100)
```

两项都存在时：

```text
L = round(durationScore * 0.45 + qualityScore * 0.55)
```

只存在一项时，使用该项本身，不补中性值。超过睡眠目标不会带来 100 以上的奖励。睡眠在身体电量之外保留 `0.15` 权重，是为了表达认知任务对睡眠时长与质量的直接敏感性；不得再叠加原始 HRV 或心率。

### 昼夜节律

令 `h = (now - wakeDate) / 3600`。仅接受 `0 <= h <= 24`：

```text
0 <= h < 1   : C = 70 + 20h
1 <= h < 8   : C = 90 + min(6, h - 1)
8 <= h < 12  : C = 96 - 4.5(h - 8)
12 <= h < 16 : C = 78 - 8.25(h - 12)
16 <= h <=24 : C = max(20, 45 - 5(h - 16))
```

该曲线只使用实际醒后时长，不用固定钟点替代个人作息。它是低权重节律修正，不代表个体 chronotype 已完成校准。

### 活动刷新

令 `m = max(0, sedentaryMinutes)`：

```text
0 <= m < 30    : M = 96
30 <= m < 60   : M = 96 - 0.70(m - 30)
60 <= m < 90   : M = 75 - 0.85(m - 60)
90 <= m < 120  : M = 50 - 0.67(m - 90)
m >= 120       : M = max(20, 30 - 0.12(m - 120))
```

该维度表达连续静坐后的任务条件变化，不是活动量目标，也不奖励高强度训练。近期活动状态可靠且当前未计时久坐时，页面传入 0；授权、睡眠、关闭、无样本和读取失败状态均不参与。

### 补水进度

补水使用醒后进度，而不是直接用全天目标：

```text
expectedFraction = clamp(hoursSinceWake / 16, 0.15, 1)
expectedIntake = waterTargetMl * expectedFraction
paceRatio = clamp(waterIntakeMl / expectedIntake, 0, 1)
H = round(45 + 55 * paceRatio)
```

醒后早期至少按全天目标的 15% 作为比较基准；达到当前应有进度即为 100，不因超量饮水继续加分。饮水量为 0 可能表示未记录，因此整个维度退出，不输出 45 分。

## 综合合成

设本次有效维度集合为 `D`，每项分数为 `x_i`，标称权重为 `w_i`：

```text
availableWeight = sum(w_i for i in D)
focusCapacity = round(exp(sum(w_i * log(x_i)) / availableWeight))
```

这是按实际可用权重重归一化的加权几何平均。选择几何平均是为了保留短板效应：高压力、低电量或严重睡眠不足中的任一项，都应比同权重算术平均更明显地限制复杂任务条件。

特殊规则：

- `stressScore == nil`：返回 unavailable，不使用身体电量或行为数据单独出分。
- 压力余量或任一明确有效维度四舍五入为 0：最终分直接为 0，避免 `log(0)`。
- 缺失维度：完全退出分子和分母，不补 0、50 或上次值。
- 所有最终分限制到 `0...100`。

## 置信度

优先使用有效的 `stressConfidence`。缺失或非有限时按 `StressDataQuality` 回退：

| 压力质量 | 回退置信度 |
| --- | ---: |
| `high` | 0.86 |
| `medium` | 0.62 |
| `low` | 0.38 |
| `unavailable` | 0.25 |

证据覆盖度是实际参与维度的标称权重之和：

```text
evidenceCoverage = sum(availableDimensionWeights)
confidence = clamp(stressConfidence * 0.75 + evidenceCoverage * 0.25, 0, 1)
```

因此只有压力余量时覆盖度为 `0.45`；六维完整时为 `1.00`。`availableDimensionCount` 用于页面解释数据完整度，但置信度使用加权覆盖度，不按维度数量简单平均。

当前 Presentation 的完整度文案：

| 维度数 | 文案 |
| --- | --- |
| 5...6 | 多维数据较完整 |
| 3...4 | 多维数据可参考 |
| 1...2 | 有限维度估算 |
| 0 | 等待同步 |

## 分档与任务含义

| 分数 | `StressFocusCapacityBand` | 页面状态 | 建议含义 |
| --- | --- | --- | --- |
| 80...100 | `strong` | 适合深度专注 | 可安排连续思考与复杂任务，仍保留短恢复 |
| 55...79 | `available` | 适合推进重点 | 适合分段推进，减少通知与频繁切换 |
| 30...54 | `limited` | 适合短段处理 | 优先短任务和低阻力事项，复杂工作拆小 |
| 0...29 | `depleted` | 先降负荷 | 先恢复、补水或走动，再用短任务复核状态 |
| 无分数 | `unavailable` | 等待数据 | 等待综合压力及其他健康数据同步 |

分档阈值只在 `StressFocusCapacityEngine.band(for:)` 维护；展示文案只在 `StressFocusCapacityPresentation` 维护。

## 可复现实例

以下示例固定 `stressConfidence = 0.80`、`stressQuality = high`、睡眠目标 480 分钟、饮水目标 2,000 ml。

| 场景 | 输入摘要 | 六维分量 `S/B/L/C/M/H` | 输出 |
| --- | --- | --- | --- |
| 多维状态充足 | 压力 25、电量 80、睡眠 480 分/90 分、醒后 4 小时、久坐 10 分钟、饮水 600 ml | `85/80/95/93/96/100` | `87 strong`，置信度 `85%` |
| 多维状态受限 | 压力 65、电量 45、睡眠 330 分/60 分、醒后 13 小时、久坐 95 分钟、饮水 600 ml | `44/45/64/70/47/65` | `50 limited`，置信度 `85%` |
| 只有压力 | 压力 45，其余缺失 | `66/--/--/--/--/--` | `66 available`，置信度约 `71%` |

示例来自当前引擎实算。修改公式、取整、权重或边界后必须重新生成并更新本表。

## 历史趋势降级

`estimatedScore(stressScore:)` 只计算压力余量：

```text
historicalEstimatedFocus = stressHeadroom(stressScore)
```

它用于缺少逐时睡眠、醒来时间、久坐和饮水上下文的历史曲线，不等同于完整六维评估。历史估算不得描述成当时真实认知能力，也不得与当前六维分数做精确因果比较。

## 页面数据装配与性能合同

- 打开今日专注能力页面时，只消费今日页已经持有的 `StressFocusCapacityAssessment` 与压力历史，不得额外发起 HRV、心率或静息心率 HealthKit 查询。
- `StressFocusCapacityTrendSnapshot` 在页面创建时一次性完成当天筛选、排序、历史降级映射、当前点补齐、均值、极值与区间计数；SwiftUI 渲染阶段只读取快照。
- 用户主动切换周、月、年或历史日期时可以按需加载对应趋势；返回今天的日视图后应立即复用当天快照。
- 页面性能优化不得改变六维当前分数、历史降级公式、10 分钟当前点补齐规则或区间统计边界。

## 明确不接入的输入

- 咖啡因全天总量：缺少剂量时间、半衰期、个体耐受与睡眠债背景时，既可能提高主观警觉，也可能掩盖疲劳，暂不参与。
- 原始 HRV、心率和静息心率：已经进入综合压力与身体电量，禁止再次直接加权。
- 步数和全天运动分钟：缺少最近活动时间与强度上下文，不能代表当前专注窗口。
- 情绪、自评生产力和任务完成量：当前没有稳定、结构化且可比较的输入合同。

新增维度前必须说明独立信息增益，避免和现有维度重复计权。

## 测试合同

`StressFocusCapacityEngineTests` 至少覆盖：

- 压力升高时分数单调下降，高压力进入低分区。
- 相同压力下，低身体电量限制分数。
- 综合压力缺失时不出分。
- 越界输入被限制到 `0...100`。
- 睡眠不足降低 `sleepReadiness` 与最终分。
- 醒后过长降低 `circadianReadiness` 与最终分。
- 长时间久坐降低 `movementReadiness` 与最终分。
- 补水使用醒后进度，不直接使用全天完成率。
- 六维完整时置信度高于只有压力的降级结果。

改动任一公式时，除单元测试外还应检查阈值两侧、缺失单项、缺失多项、未来醒来时间、醒后超过 24 小时、饮水 0、久坐负数和显式 0 分输入。

## 版本与兼容

- 当前算法版本：`2.0`。
- 版本只写入 `StressFocusCapacityAssessment.algorithmVersion`，不写入类型名。
- 修改权重、指数、分段斜率、必需输入、置信度或分档阈值时必须升级版本。
- 只修改不影响含义的文案或布局时不升级算法版本。
- 当前 Assessment 为今日页即时派生结果，没有独立持久化合同；未来若同步到 Watch、Widget 或服务端，必须连同版本、置信度、维度数和各分量一起传递。
- 不同版本结果进入趋势或回测时必须分组，不能直接混合成同一基线。

## 校准与验证

2.0 的权重和分段曲线是确定性经验模型，不代表已经完成临床或人群验证。提高“精准度”需要在隐私合规前提下收集与任务相关、可比较的自评或行为标签，并至少评估：

- 同一用户内，分数与短时任务难度、持续时长和主观费力度的关系。
- 不同作息、年龄、训练状态和设备采样密度下的误差。
- 各维度的边际信息增益，确认睡眠与身体电量没有产生过强重复贡献。
- 分档的校准度，而不只看总体相关系数。
- 缺失数据模式是否系统性偏向某类用户。

在没有验证结果前，界面必须使用“估算”“任务条件”“参考”等表述，不得声称测量了真实认知能力。

## 修改清单

调整专注算法时必须同步：

1. 更新 `StressFocusCapacityInput` 与 `StressFocusCapacityAssessment`。
2. 更新 `StressFocusCapacityEngine` 的公式、权重、版本和边界。
3. 更新 `StressFocusCapacityPresentation` 的分量说明、完整度和免责声明。
4. 更新今日页数据装配，确认等待态不会被当作有效 0 值。
5. 扩充 `StressFocusCapacityEngineTests`。
6. 重新生成本文可复现实例。
7. 更新 `README.md` 与 `STRESS_CALCULATION.md` 的入口摘要。
8. 构建 iOS，并检查等待态、1/6 与 6/6 维度、四个分档和历史降级曲线。

## 局限与声明

该算法使用消费级传感器、用户记录和有限上下文。感染、药物、咖啡因、疼痛、情绪事件、传感器佩戴、错误睡眠窗口、漏记饮水和久坐授权都可能影响结果。它不能诊断疲劳、注意力障碍、睡眠障碍或任何疾病，也不能替代医疗建议或正式认知评估。
