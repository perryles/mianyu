# 心律稳定性算法合同（Heart Rhythm Stability）

- 版本：`1.2`（`HeartRhythmStabilityEngine.algorithmVersion`）
- 主要输出：`HeartRhythmStabilityResult`
- 定位：**参考指标，非医疗诊断**。基于 Apple 健康生态可读的心律事件与结论做聚合评分，不做逐搏 RR 自算，不复刻任何厂商私有算法。

## 一、目标与边界

部分第三方厂商的"脉搏波心律失常分析"结果属私有数据，不会同步进 Apple 健康。本模块改用 Apple 健康可读信号自算一个"心律稳定性"参考分：

- 房颤负担 `AtrialFibrillationBurden`
- 心律不齐通知 `IrregularHeartRhythmEvent`
- 高/低心率事件 `HighHeartRateEvent` / `LowHeartRateEvent`
- ECG 结论 `HKElectrocardiogram.Classification`

该分数只用于：今日"身体指数"卡片展示、身体电量的**有界扣分因子**、详情页风险提示与就医建议。所有文案强调"参考、建议就医核实"，不作诊断结论。

## 二、数据流

```text
HealthKit
  → HealthKitManager+HeartRhythm（fetchHeartRhythmSignals）
  → HeartRhythmSignals（Domain DTO，纯值类型，去 HealthKit 化）
  → HeartRhythmStabilityHealthKitAdapter（signals → input）
  → HeartRhythmStabilityEngine.evaluate(input:)
  → HeartRhythmStabilityResult
  → HeartRhythmStabilityPresentation / Dashboard 卡片 / 详情页
  → HeartRhythmStabilityEngine.applyPenalty(bodyIndex:result:)（身体电量扣分）
```

观察窗口：当日 + 最近 7 天（`observationDays`）。被动自动检测事件（心律不齐通知、高/低心率事件）会按窗口做**密度归一化**，ECG 为用户主动测量不折算。

## 三、语义映射（Adapter 约定）

| ECG 结论 | 归类 | 说明 |
| --- | --- | --- |
| `sinusRhythm` | 未见异常 `normalCount` | 窦性心律 |
| `atrialFibrillation` | 疑似房颤 `suspectedAtrialFibrillationCount` | 与心律不齐通知合并统计 |
| `inconclusive`（心率过高/过低/其它） | 疑似早搏 `suspectedEctopicCount` | 结果不确定，视为异常搏动线索 |
| `inconclusivePoorReading` | 信号质量不足 `poorReadingCount` | **数据质量问题、非心律异常**：不计入三分类、不扣分、单独出现不构成证据 |
| `unclassified` | 不计入 | 无法识别/未给出结论 |

- 疑似房颤计数 = `irregularRhythmEventCount + ecgAtrialFibrillationCount`
- 疑似早搏计数 = `ecgInconclusiveCount`（不含 poor reading）
- 未见异常计数 = `ecgSinusCount`
- 高/低心率事件不进入三分类，只作附加提示与扣分。
- **信号质量不足**（poor reading）仅作透明化计数 `poorReadingCount`，若窗口内只有 poor reading 则视为证据不足（`unavailable`）。

## 四、评分公式

从满分 `100` 起，按证据通道扣分，最后 clamp 到 `0...100`。

**密度归一化**：`densityFactor = clamp(7 / observationDays, 0.5, 2.0)`，仅施加于被动事件计数（心律不齐通知、高/低心率）。

**房颤通道（概率并集去重）**：房颤负担、心律不齐通知、ECG 房颤结论三者高度相关（多指向同一房颤），先各自映射为严重度 `s ∈ [0, 1]`，再用概率并集合成，避免同一房颤被重复扣分：

```text
burdenSeverity   = interp(burdenPercent, 断点)                    // 见下方非线性映射
irregularSeverity= min(0.75, irregularCount × densityFactor × 0.2)// 单通道封顶 0.75
ecgAFibSeverity  = min(1.00, ecgAtrialFibrillationCount × 0.5)     // 2 条即达满严重度
afibSeverity     = 1 - (1 - burdenSeverity)(1 - irregularSeverity)(1 - ecgAFibSeverity)
afibPenalty      = afibSeverity × 60                              // 房颤通道封顶 60
```

房颤负担 → 严重度采用**分段线性插值**（`burdenSeverityBreakpoints`），在高负担区间仍保留区分度，避免旧版"10% 即饱和"：

| 负担 | 严重度 | 语义 |
| --- | --- | --- |
| 0% | 0.00 | 无 |
| 2% | 0.20 | 轻微 |
| 10% | 0.50 | 低 |
| 30% | 0.80 | 中 |
| ≥60% | 1.00 | 高 / 接近持续性 |

**其余独立通道（加性扣分）**：

```text
ectopicPenalty   = min(24, ecgInconclusiveCount × 6)              // ECG 不确定（非 poor reading）
hrEventPenalty   = min(20, (highHR + lowHR) × densityFactor × 4)  // 高/低心率事件
score = clamp(round(100 - afibPenalty - ectopicPenalty - hrEventPenalty), 0, 100)
```

权重、阈值与上限集中定义于 `HeartRhythmStabilityRules`，引擎逻辑不得内联硬编码。

### 主导信号排序

参与扣分的分量按扣分幅度降序进入 `dominantSignals`，供详情页解释；房颤三路按各自"单独等效扣分"（严重度 × 通道上限）参与排序，高/低心率事件按事件数排序权重。

## 五、分档

| 分数 | `HeartRhythmStabilityBand` | 语义 |
| --- | --- | --- |
| `85...100` | `steady` | 心律平稳，未见明显异常 |
| `60...84` | `watch` | 存在少量异常线索，建议持续留意 |
| `0...59` | `elevated` | 异常线索较多，建议尽快就医核实 |
| 无证据 | `unavailable` | 证据不足，不评估、不扣分 |

## 六、缺失数据规则

`evaluate(input:)` 无任何证据时返回 `.unavailable`：`score == nil`、`band == .unavailable`、`dataQuality == .unavailable`、`penaltyMultiplier == 1.0`。因此无 Apple Watch 用户该卡片显示"暂无"，且**完全不影响**身体电量与专注能力。

数据完整度 `dataQuality` 按有效来源数量（房颤负担 / 心律不齐通知 / ECG / 高低心率事件）映射：`0 → unavailable`、`1 → low`、`2 → medium`、`≥3 → high`。

## 七、身体电量扣分因子

分数先映射为分数乘子，再按**数据置信度**加权，得到最终有界乘子 `penaltyMultiplier ∈ 0.85...1.0`：

```text
penaltyFreeScoreThreshold = 85
minimumPenaltyMultiplier   = 0.85
score ≥ 85 → rawMultiplier = 1.0（不扣分）
score < 85 → severity      = (85 - score) / 85，clamp 到 0...1
             rawMultiplier = 1.0 - severity × (1.0 - 0.85)
# 置信度加权：低质量证据把扣分向"不扣分"收敛，避免单条噪声显著拉低电量
weight     = { unavailable: 0, low: 0.6, medium: 0.85, high: 1.0 }[dataQuality]
multiplier = clamp(1.0 - (1.0 - rawMultiplier) × weight, 0.85, 1.0)
```

即最多下调约 15%；加权只会把乘子**上调**（更接近不扣分），恒不低于 0.85。置信度加权只作用于身体电量扣分，**不改变**展示用的稳定性分数与分档。组合入口由引擎持有，SwiftUI 层不得自写公式：

```swift
HeartRhythmStabilityEngine.applyPenalty(bodyIndex: rawBodyBatteryValue, result: rhythmResult)
```

`result` 无数据时原值返回。调整后的身体电量继续传入 `StressFocusCapacityEngine`（通过 `bodyBatteryScore` 自然传导），专注能力不单列心律维度。

## 八、测试合同

`BioBalanceTests/Charts/Heart/HeartRhythmStabilityEngineTests.swift` 至少覆盖：

- 高房颤负担导致大幅扣分与 `elevated` 分档。
- 房颤负担**非线性映射**：高负担（如 60%）比中等负担（如 10%）扣分更多，不再在 10% 即饱和；≥60% 起严重度封顶。
- 心律不齐事件密度扣分随事件数递增且遵守上限。
- ECG 房颤结论计入疑似房颤并显著扣分。
- 房颤三路证据（负担 + 通知 + ECG 房颤）用概率并集**去重**：合成扣分小于三路加性之和，且封顶不超过 60。
- 观察窗口**密度归一化**：相同事件数下，短窗口密度更高、扣分更多；长窗口密度稀释、扣分更少。
- ECG poor reading **不扣分、不计疑似早搏**，仅作透明化计数；单独出现返回 `unavailable`。
- **置信度加权**：同一分数下，低数据质量的有效乘子更接近 1（扣身体电量更轻），高质量等于纯分数乘子；三档恒在 `0.85...1.0`。
- 缺失数据返回 `.unavailable`：`score == nil` 且 `penaltyMultiplier == 1.0`（不扣分）。
- `penaltyMultiplier` 边界：始终 `≥ 0.85`、`≤ 1.0`；85 分及以上恒为 `1.0`；高质量低分可触及 `0.85` 下限。
- 三分类计数正确性（窦性→未见异常、房颤→疑似房颤、不确定→疑似早搏，poor reading/unclassified 不计入）。
- `applyPenalty` 对无数据结果保持原值。

## 九、局限与声明

- Apple 心律事件与房颤负担主要来自 Apple Watch，无手表用户无数据。
- 采用事件聚合口径，不逐次标注"疑似早搏/房颤"发生点，只给聚合计数与状态。
- 权重、阈值与扣分上限为初始经验值，仍需真实用户数据校准。
- 结果不是医学诊断，任何异常提示都应引导用户就医核实。
