# Algorithms 模块

`Core/Algorithms` 是 Mianyu 所有纯健康计算引擎的统一归属。每个子模块接受来自 HealthKit 适配层的结构化输入，输出确定性评估结果，供 ViewModel、展示层和跨端同步消费。

## 设计原则

| 原则 | 说明 |
| --- | --- |
| 无 UI 依赖 | 任何算法子模块不依赖 SwiftUI、UIKit 或平台展示框架 |
| 确定性 | 相同输入在任何环境下产生相同输出，不依赖网络或随机数 |
| 个人基线优先 | 所有生理评分基于个人历史基线，不使用固定人群阈值 |
| 缺失数据归一化 | 缺失分量退出加权并降低置信度，不补 0 或固定中性值 |
| 版本隔离 | 算法版本写入输出，不同版本样本不混合聚合 |
| iPhone 真值来源 | Watch、Widget 和 Complication 只消费同步结果，不重新计算 |

## 目录结构

```text
Core/Algorithms/
├── README.md                          本文件
├── Stress/                            综合压力与派生评估
│   ├── Assessment/                    实时压力 3.0（双通道、EMA、置信度）
│   ├── BodyBattery/                   身体电量（夜间恢复 + 日内负荷积分）
│   ├── FocusCapacity/                 专注任务条件 2.0（六维几何平均）
│   ├── VO2Max/                        心肺能力 3.1（五分量加权估算）
│   └── README.md                      压力模块维护指南
├── Heart/                             心律相关评估
│   └── RhythmStability/               心律稳定性 1.2（事件聚合参考）
│       ├── Domain/                    心律信号 DTO 与领域模型
│       ├── Adapters/                  HealthKit 信号到评分输入
│       ├── Engine/                    评分引擎与规则
│       ├── Presentation/              卡片与详情页文案
│       └── HEART_RHYTHM_STABILITY_CALCULATION.md 心律稳定性算法合同
└── Sleep/                             睡眠监测与评分
    ├── SleepRhythmScoringEngine.swift 睡眠质量与节律评分 3.3（证据感知、动态权重）
    ├── SleepTemporalEvidenceAdapter.swift 会话区间与阶段时间轴证据适配
    ├── SleepRegularityEvidenceAdapter.swift 多晚就寝规律性证据适配
    ├── SleepMonitoringCore.swift      睡眠评分、鼾声检测、监测编排
    ├── SleepAudioInference.swift      音频特征推断（RMS、MFCC、梅尔频带）
    ├── LateNightRecoveryEngine.swift  夜间恢复引擎
    ├── SleepEnvironmentTrendEngine.swift  睡眠环境趋势
    ├── SleepRhythmRebuildModels.swift 睡眠节律重建模型
    └── README.md                      睡眠算法规范与维护合同
```

## 数据流概览

```text
HealthKit
  → HealthKitManager (Core/Health)
  → Adapters（各子模块的 HealthKit 适配器）
  → Engine（纯计算引擎）
  → Output（Assessment / Summary / Trajectory）
  → Presentation / ViewModel / AppGroup / Watch / Widget
```

## 算法子模块一览

| 子模块 | 当前版本 | 主要输出 | 算法规范 |
| --- | ---: | --- | --- |
| 综合压力 | 3.0 | `StressEvaluation` | `Stress/Assessment/STRESS_CALCULATION.md` |
| 身体电量 | 1.1 | `BodyBatteryTrajectory` | `Stress/BodyBattery/STRESS_BODY_BATTERY_CALCULATION.md` |
| 专注能力 | 2.0 | `StressFocusCapacityAssessment` | `Stress/FocusCapacity/STRESS_FOCUS_CAPACITY_CALCULATION.md` |
| 心肺能力 | 3.0 | `VO2MaxDailyAssessment` | `Stress/VO2Max/VO2MAX_CALCULATION.md` |
| 心律稳定性 | 1.2 | `HeartRhythmStabilityResult` | `Heart/RhythmStability/HEART_RHYTHM_STABILITY_CALCULATION.md` |
| 睡眠评分 | 3.3 | `SleepSessionSummary` / `SleepRhythmScoreResult` | `Sleep/README.md` |

## 共享约定

### 置信度体系

所有引擎输出置信度（`0...1`），表达输入依据的完整度，不表示医学准确率。置信度低时页面应告知用户"数据仍在积累"，不得用固定分数掩盖 unavailable。

### 测试合同

每个算法子模块在 `BioBalanceTests/` 下维护对应测试文件，至少覆盖：

- 正常输入的预期输出
- 缺失数据的降级行为
- 边界值与越界输入的限制
- 不同版本样本的隔离

### 新增算法模块

1. 在 `Core/Algorithms/` 下创建新目录，遵循 `Domain/` → `Engine/` → `Presentation/` 分层。
2. 编写算法规范 `.md`，包含公式、权重、边界、版本和测试合同。
3. 在本 README 的子模块一览表中注册。
4. 确保不依赖 SwiftUI，不引入第三方依赖。

### 修改既有算法

公式、阈值、权重或缺失数据语义发生变化时，代码、回归测试和对应规范文档必须在同一次变更中更新。行为不兼容时递增算法版本；仅重命名、注释和等价重构不递增版本。

## 局限与声明

所有算法基于消费级传感器和有限上下文，是健康趋势的估算参考，不是医学诊断、心理评估或治疗建议。运动、咖啡因、感染、药物、传感器佩戴质量、采样密度和个体差异都可能影响结果。
