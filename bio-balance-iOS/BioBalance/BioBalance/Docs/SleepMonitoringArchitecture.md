# Mianyu Sleep Monitoring Architecture

## Module Diagram

```mermaid
flowchart LR
    Watch["Apple Watch\nWatchSleepSignalService"] --> WC["WatchConnectivity"]
    WC --> Orchestrator["SleepMonitoringOrchestrator"]
    Focus["Sleep Focus / Manual Arm"] --> Orchestrator
    Orchestrator --> Audio["SleepAudioCaptureService"]
    Audio --> Worker["SleepAudioInferenceWorker\nbounded serial queue"]
    Worker --> Inference["SleepAudioInferenceProviding\nFluidAudio / baseline fallback"]
    Inference --> Pipeline["SnoreDetectionPipeline\nexclude speech-like / steady-noise windows"]
    Pipeline --> Scoring["SleepScoringEngine"]
    Scoring --> Repo["SleepSessionRepository"]
    Scoring --> HK["SleepHealthKitWriter"]
    Repo --> CK["SleepCloudKitSyncService"]
    Repo --> Today["Today Sleep Card / Sleep Detail"]
```

## Data Flow

```mermaid
flowchart TD
    A["User arms sleep monitoring"] --> B["Watch sends probableSleep / iPhone auto-arms"]
    B --> C["iPhone local AVAudioEngine sampling"]
    C --> D["1-second audio windows"]
    D --> E["Bounded serial inference worker"]
    E --> F["SleepAudioInferenceProviding\nVAD/activity result"]
    F --> G["SnoreDetectionPipeline\nRMS fallback if needed"]
    G --> H["Sleep score + snore summary"]
    H --> I["Local repository + App Group"]
    I --> J["Minimal HealthKit writeback if needed"]
    I --> K["CloudKit private sync"]
    I --> L["Today Page / Watch / Widget refresh"]
```

## Sequence

```mermaid
sequenceDiagram
    participant User
    participant Watch
    participant iPhone
    participant HK as HealthKit
    participant CK as CloudKit
    participant Today

    User->>Watch: 睡前佩戴
    User->>iPhone: Sleep Focus / 手动开始监测
    Watch->>iPhone: probableSleep / sleepStateChanged
    iPhone->>iPhone: AVAudioEngine 采集 1 秒窗口
    iPhone->>iPhone: 有界 worker 串行调用 FluidAudio / baseline provider
    iPhone->>iPhone: 排除 speech-like / steady-noise 后运行 SnoreDetectionPipeline
    iPhone->>iPhone: SleepScoringEngine
    iPhone->>HK: 仅在必要时补写 sleepAnalysis
    iPhone->>CK: 写入结构化摘要
    iPhone->>Today: 更新睡眠卡片与详情页
    iPhone->>Watch: 返回 sleepDeviceStatus / sleepSessionSummary
```

## ASCII

```text
+-------------------+        +---------------------------+
| Apple Watch       |        | iPhone                    |
| - sleep signals   |------->| SleepMonitoringOrchestrator|
| - heart/activity  |  WC    | - audio capture           |
+-------------------+        | - snore detection         |
                             | - scoring / insights      |
                             +-------------+-------------+
                                           |
                    +----------------------+----------------------+
                    |                                             |
             +------+-------+                             +-------+------+
             | HealthKit    |                             | CloudKit      |
             | minimal save |                             | private sync  |
             +------+-------+                             +-------+------+
                    |                                             |
                    +----------------------+----------------------+
                                           |
                                   +-------+-------+
                                   | Today / Sleep |
                                   | Watch / Widget|
                                   +---------------+
```
