# Mianyu 压力模块排查手册

这份文档专门用于排查当前 Mianyu 压力模块的问题。

适用范围：

- Stress 3.1 算法结果异常
- 今日页面压力卡片没有更新
- 压力二级页面显示不一致
- Widget / Watch 没同步到最新压力
- API / HealthKit / 本地真值链路谁出了问题不好判断

---

## 1. 先记住一条主线

当前压力链路的优先顺序应该理解为：

1. `StressRealtimeEngine` 算出当前压力真值
2. `HealthDataManager` 把真值写入 `RealtimeHealth`
3. `StressPresentation` 把当前与今日结果映射成页面文案
4. 二级页面读取 `realtimeHealth` / `history.stressPoints`
5. AppGroup / Widget / Watch 同步读取同一份真值

所以排查时也要按这个顺序看。

---

## 2. 关键日志前缀

### 2.1 核心引擎

日志前缀：

```text
[Stress]
```

来源：

- [StressRealtimeEngine.swift](./Engine/StressRealtimeEngine.swift)

表示：

- 3.1 核心引擎已经真正执行

会打印的关键字段：

- `bpm`
- `hrv`
- `baselineHRV`
- `baselineRHR`
- `workoutBlend`
- `recoveryDebt`
- `raw`
- `smoothed`
- `state`
- `driver`
- `explain`
- `confidence`

如果你看到：

- 根本没有 `[Stress]`
  - 说明引擎没跑到
- `raw` 有值但 `smoothed` 一直不变
  - 说明可能被 EMA 平滑卡住，或者前次值一直没更新
- `state=nil` 不会发生
  - 如果出现异常状态字符串，说明映射层或持久化层有问题

---

### 2.2 iPhone 真值写回

日志前缀：

```text
[Stress][HealthDataManager]
```

来源：

- [HealthDataManager.swift](../../../Health/HealthDataManager.swift)

表示：

- 3.0 结果已经被 `HealthDataManager` 接住，并准备写回 `RealtimeHealth`

关键字段：

- `bpm`
- `hrv`
- `stress`
- `state`
- `explain`
- `confidence`

判读方式：

- 有 `[Stress]` 但没有 `[Stress][HealthDataManager]`
  - 说明引擎跑了，但主同步链路没完成写回
- `[Stress][HealthDataManager]` 的 `score/state/reason` 和 `[Stress]` 不一致
  - 说明中间装配逻辑或 fallback 混入了旧值

---

### 2.3 AppGroup / Widget / Watch 同步

日志前缀：

```text
[Stress][AppGroup]
```

来源：

- [HealthDataManager.swift](../../../Health/HealthDataManager.swift)

表示：

- 当前压力真值已经写入 AppGroup，Widget / Watch 理论上可以消费

关键字段：

- `stress`
- `state`
- `explain`
- `trend`

判读方式：

- `[Stress][HealthDataManager]` 有值，但 `[Stress][AppGroup]` 没值
  - 说明真值有了，但没同步出去
- `[Stress][AppGroup]` 正常，但 Widget / Watch 不动
  - 说明问题在 Widget / Watch 读取层，不在算法层

---

### 2.4 今日页面卡片映射

日志前缀：

```text
[StressPresentation]
```

来源：

- [StressModels.swift](./Domain/StressModels.swift)

表示：

- `RealtimeHealth` 已经被映射为页面使用的 `StressPresentationAssessment`

关键字段：

- `stress`
- `state`
- `explain`
- `mappedTitle`
- `mappedBand`

判读方式：

- 有 `[Stress][HealthDataManager]`，但没有 `[StressPresentation]`
  - 说明页面卡片没有走 3.0 展示映射
- `[StressPresentation]` 的 `score/band` 不符合预期
  - 说明 `StressPresentation` 的状态映射规则有问题
- `[StressPresentation]` 正常，但首页卡片没变
  - 说明 View 层没刷新，或页面没有消费新的 assessment

---

### 2.5 压力主页

日志前缀：

```text
[StressRoot]
```

来源：

- [StressRootView.swift](../../../../Views/Health/Stress/StressRootView.swift)

表示：

- 压力模块首页已经加载完成“今日预览”数据

关键字段：

- `loaded preview points`
- `realtime`
- `historyToday`

判读方式：

- `realtime > 0` 但 `preview points = 0`
  - 说明有当前值，但今天曲线历史还没进来
- `historyToday > 0` 但 `loaded preview points = 0`
  - 说明重建/合并逻辑没有把历史点给到预览层

---

### 2.6 今日曲线页

日志前缀：

```text
[StressTodayCurve]
```

来源：

- 旧 `StressTodayCurveView` 已移除；当前曲线由压力主页与 `PressureDetailView` 承接。

关键字段：

- `loaded points`
- `realtime`
- `displayedCurrent`

判读方式：

- `realtime > 0` 但 `displayedCurrent = 0`
  - 说明当前显示逻辑没吃到 realtime
- `loaded points` 很少但 `historyToday` 很多
  - 说明 `HealthStressEstimator.todayStressPoints(...)` 的优先级或过滤逻辑有问题

---

### 2.7 压力详情页

日志前缀：

```text
[PressureDetail]
```

来源：

- [PressureDetailView.swift](../../../../Views/Health/Stress/PressureDetailView.swift)

关键字段：

- `period`
- `points`
- `realtime`
- `avg`
- `mappedTitle`
- `mappedScore`

判读方式：

- `realtime` 有值但 `mappedTitle` 看起来还是旧口径
  - 说明详情页仍未消费 `StressDailyEngine` 的今日综合结果
- `period=day` 时结果不对，但其他 period 正常
  - 说明今日口径和历史口径切换逻辑有问题

---

### 2.8 压力历史页

日志前缀：

```text
[StressHistory]
[StressHistory][HealthKit]
```

来源：

- `StressHistoryView.swift` 已移除；历史日志前缀仅用于排查旧版本。

关键字段：

- `range`
- `records`
- `dailySummaries`
- `source`
- `daily`
- `realtime`
- `merged`

判读方式：

- `source=暂无数据`
  - API 和 HealthKit 两边都没形成有效历史
- `daily > 0` 但 `records = 0`
  - 说明 merge/filter 逻辑把记录丢掉了
- `source=历史记录 + 健康 App` 但图表不对
  - 说明合并后的排序/分组逻辑有问题

---

### 2.9 相关性页

日志前缀：

```text
[StressCorrelation]
[StressCorrelation][HealthKit]
```

来源：

- 旧 `StressCorrelationView` 已移除；当前关联分析由 `EmotionStressCorrelationView` 承接。

关键字段：

- `metric`
- `apiPoints`
- `source`
- `fallback=HealthKit`
- `hrvPoints`
- `bpmPoints`
- `realtime`

判读方式：

- `apiPoints=0 fallback=HealthKit`
  - 表示当前走的是本地重建逻辑
- `hrvPoints=0 bpmPoints=0`
  - 说明今天样本不足，相关性图为空属于数据问题，不是 UI 问题

---

## 3. 常见问题怎么排

### 3.1 首页压力卡片没变

按顺序看：

1. `[Stress]`
2. `[Stress][HealthDataManager]`
3. `[StressPresentation]`

结论：

- 1 没有：引擎没跑
- 1 有，2 没有：真值没写回
- 2 有，3 没有：卡片没走 3.0 展示映射
- 3 有，但 UI 还没变：View 刷新或绑定问题

### 3.2 今日曲线页和首页不一致

按顺序看：

1. `[Stress][HealthDataManager]`
2. `[StressRoot]`
3. `[StressTodayCurve]`
4. `[PressureDetail]`

结论：

- 真值一致，但点数不同
  - 问题多半在历史点来源
- `displayedCurrent` 和 realtime 不一致
  - 问题在当前页的 current 取值逻辑

### 3.3 Widget / Watch 不更新

按顺序看：

1. `[Stress][HealthDataManager]`
2. `[Stress][AppGroup]`

结论：

- 1 有、2 没有：没写入 AppGroup
- 2 有，但前台没动：读取层 / 刷新层问题

### 3.4 历史页没有数据

按顺序看：

1. `[StressHistory][HealthKit]`
2. `[StressHistory]`

结论：

- `daily=0 realtime=0`
  - HealthKit 本身样本不够
- `merged=0`
  - 合并逻辑有问题

---

## 4. 推荐的调试顺序

以后排压力问题，建议固定按这个顺序：

1. `Stress`
2. `Stress HealthDataManager`
3. `Stress AppGroup`
4. `StressPresentation`
5. `StressRoot / StressTodayCurve / PressureDetail`
6. `StressHistory / StressCorrelation`

一句话理解：

- **先看有没有算出来**
- **再看有没有写回**
- **再看有没有同步出去**
- **最后看页面有没有消费到**

---

## 5. 相关文档

如果你想看算法和架构本身，请配合 [STRESS_CALCULATION.md](./STRESS_CALCULATION.md) 一起看。本仓库 `bio-balance-iOS/` 下的配套文档：

- [CODE_WIKI.md](../../../../../../CODE_WIKI.md)：iOS 工程总览、目录结构与关键类索引
- [VO2MAX_CALCULATION.md](../VO2Max/VO2MAX_CALCULATION.md)：心肺能力计算与估算兜底
