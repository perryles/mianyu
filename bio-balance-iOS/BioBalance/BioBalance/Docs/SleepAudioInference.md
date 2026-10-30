# Sleep audio inference

睡眠音频诊断页和正式睡眠监测共用同一套音频窗口与推理 provider。页面入口位于“应用设置 -> 帮助与支持 -> 睡眠音频诊断”。

## 已验证的边界

- 约 1 秒音频窗口，实时计算 RMS、dBFS 和 zero-crossing rate；FluidAudio 推理统一使用 16 kHz 单声道样本。
- 10 秒自动停止，支持手动停止。
- 只在内存中处理窗口，不写入文件，不上传音频。
- `SleepAudioInferenceProviding` 隔离第三方模型；默认 provider 是 `ResilientSleepAudioInferenceProvider`，优先使用 `FluidAudioSleepAudioInferenceProvider`，初始化或单次推理失败时回落到 `BaselineSleepAudioInferenceProvider`。provider 在音频采集前通过 `prepare()` 完成模型初始化，避免在音频回调中首次加载模型。
- 正式 `SleepAudioCaptureService` 和睡眠音频诊断页都通过 `SleepAudioInferenceProviderFactory` 使用同一个默认 provider。
- 正式睡眠会话结束时，`SnoreDetectionPipeline` 优先消费窗口结果，排除 `speechLike` 和 `steadyNoise`，没有结果时才回退到旧 RMS 规则。
- 音频 tap 只负责复制样本与切窗；`SleepAudioInferenceWorker` 用有界队列串行调用模型，最多保留 4 个待处理窗口和 43,200 个结果（约 12 小时）。

## FluidAudio 可选接入边界

当前 Mianyu app target 不硬依赖 FluidAudio。`SleepAudioInference.swift` 通过 `#if canImport(FluidAudio)` 保留可选 provider；未解析该包时自动使用 `BaselineSleepAudioInferenceProvider`，不会阻塞工程构建或睡眠监测。

需要重新启用模型增强时，在网络可正常完成 SwiftPM 解析的环境中添加：

```text
https://github.com/FluidInference/FluidAudio.git
```

重新接入时必须锁定一个可解析的发布版本，不使用浮动的 `main`。`FluidAudioSleepAudioInferenceProvider` 使用 16 kHz 单声道 Float 样本调用 `VadManager`；语音窗口标记为 `speechLike`，非语音窗口再由本地特征区分安静、持续噪声和活动声。

provider 只负责模型初始化和单窗口推理；不要把 FluidAudio 类型暴露给睡眠评分、HealthKit 或报告页面。

## 下一步验收

1. 真机首次加载时间、常驻内存、温升和耗电。
2. 夜间说话、电视声、风扇声与鼾声片段的 VAD 混淆矩阵。
3. 锁屏/后台可持续时间，以及无网络冷启动。
4. 生产链路已接入 provider 抽象；下一步用同一批窗口比较 FluidAudio 与 baseline 的混淆矩阵，并在真机上观察模型加载、耗电和锁屏后台稳定性。
