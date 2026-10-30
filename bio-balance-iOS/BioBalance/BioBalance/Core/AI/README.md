# Mianyu AI 架构

本目录统一管理云端 AI、本地确定性健康引擎、健康问答、处方文字结构化、餐食图片分析和饮品图片分析。业务页面只依赖 Feature 层协议，不直接调用供应商 API。

主应用最低部署版本为 iOS 18.6，可以直接使用该版本已提供的 Swift Concurrency 和 `URLSession` 异步接口。Apple Core AI 模型运行时是独立的 iOS 27 能力，仍必须保留编译条件和 `#available(iOS 27.0, *)` 检查。

## 目录职责

```text
Core/AI/
├── Networking/       通用 HTTP、重试、配置和 Keychain 密钥
├── Routing/          Provider ID、能力协议、注册表和路由策略
├── Providers/Qwen/   DashScope 文本与视觉请求、DTO、解析和安全日志
├── Chat/             健康问答编排、五段式答案解析、本地 fallback
├── Meal/             图片输入、严格 JSON 校验、待确认餐食/饮品结果
├── Engines/          不依赖网络的确定性健康计算
├── Context/          健康上下文、快照和 Prompt 构建
├── Shared/           纯模型和跨模块值类型
├── Persistence/      UserDefaults 等本地持久化
└── Internal/         仅内部构建可见的 AI 配置页面
```

## Provider 与能力

`AIProviderID` 是稳定逻辑标识，目前包含：

- `.qwen`：第一阶段唯一真实接入的云端 Provider。
- `.deterministic`：健康功能的本地确定性 responder。
- `.appleOnDevice`：Apple 本地模型的稳定逻辑标识；当前只保留餐食 Core AI 适配器。
- `.kimi`、`.deepSeek`、`.miniMax`：仅预留 ID，尚未注册网络实现或未经验证的模型名。
- `.custom(String)`：后续内部实验 Provider。

能力通过 `AICapability` 明确声明：`.healthChat`、`.healthAnalysis`、`.prescriptionStructuring`、`.mealVision`、`.drinkVision`。注册表只返回已声明当前能力且运行时可用的 Provider。处方结构化复用文本 Provider，但使用独立能力和严格 JSON 合同，不与健康问答 Prompt 混用。

## 当前请求流

今日健康问答强制使用千问，不再静默回落本地确定性 responder。所有构建类型都会调用千问；旧配置中的关闭状态会被忽略，损坏或空白的 Endpoint、模型字段会恢复为阿里云默认值。云端不可用时页面直接显示错误，避免把本地规则回答误认为云端结果。今日上下文可以附带仅供本地使用的长期档案，但该字段不会阻断云端路由，也不会进入今日 Prompt。长期健康档案页面当前仍始终使用本地 responder。

餐食和饮品图片都固定使用千问视觉，不读取旧的 Apple 本地模型优先设置。两条链路都把后台压缩后的 JPEG 作为 Base64 Data URL 直接发送至 DashScope，不使用 Mianyu 文件服务器、图片上传接口或识别后端。饮品位置只在设备本地读取和保存，不会发送给千问。Apple Core AI 适配器仍作为未来能力保留，但不会进入当前餐食识别路由。

普通 Release 与内部构建使用相同的 Provider 路由策略。`AISecretsStore` 不包含默认 DashScope API Key；开发者需通过环境变量或内部配置页的 Keychain 存储提供自己的凭据。所有凭证都无效时，今日健康问答直接报错，餐食功能转入手动录入。

处方图片不直接发送给千问。`Core/Recognition/PrescriptionRecognitionService.swift` 先用设备端 Vision OCR 提取文字、移除常见姓名/证件/电话/地址字段并限制长度，再调用 `.prescriptionStructuring`。千问不可用时保留本地 OCR 草稿和有限的剂量模式匹配，所有结果仍必须进入人工确认页。

## 千问配置

千问使用 DashScope OpenAI-compatible Chat Completions：

- 健康文本默认 Endpoint：`https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`
- 健康文本默认模型：`qwen-plus`
- 餐食和饮品视觉默认 Endpoint：同上，但配置独立保存
- 餐食和饮品视觉默认模型：`qwen-vl-plus`

两种能力共用同一个 DashScope API Key，但模型、Endpoint 和请求 DTO 分开。当前版本不内置 Key，按环境变量、Keychain 的顺序读取；Endpoint、模型和开关存 UserDefaults。历史 Core AI 偏好字段仅为旧配置解码兼容保留，不参与当前路由。内部配置页只在 `DEBUG` 或 `INTERNAL_AI` 编译。

## 错误、重试与日志

`AIHTTPClient` 只重试网络中断、408、429 和 5xx。取消、鉴权失败、参数错误、安全拒答、解析错误不会重试，也不会切换到另一个云端模型。今日健康问答在重试耗尽后直接返回云端错误，不会伪装成本地成功回答；取消始终向上传播。

单次请求最多尝试 10 次，即使持久化配置被手工改成更大的值也不会突破该上限。HTTP 响应正文默认限制为 2 MB；客户端会先校验 `Content-Length`，并在异步字节流读取过程中持续执行上限。超过上限直接返回 `responseTooLarge`，不重试也不进入 Provider fallback。服务端错误文案会压成单行并限制为 240 个字符，避免把超长调试正文带到 UI 或日志。

日志只允许记录 Provider ID、模型、能力、耗时、状态和 fallback 原因。禁止记录 API Key、图片 Base64、完整 Prompt、健康指标和模型原始回答。

## Prompt 输入边界

健康问题去除首尾空白后最多保留 2,000 个字符，空问题直接返回 `invalidRequest`。请求只携带最近 4 条有效的用户或助手历史消息，每条最多 1,500 个字符；system、loading 和 UI 已插入的当前问题副本不会再次发送。

健康上下文中的自由文本字段会先去除换行、压成单行并限制长度，再进入 Prompt。长期档案摘要也只允许经过清洗和数量限制的聚合字段，不能上传原始 HealthKit 序列或自由备注。

Apple 本地模型 Provider 在上述字符边界之外还有独立的 token 预算：历史对话通过 `Transcript` 一次性注入会话，按上下文窗口从最新往旧保留，为回答固定预留 1,024 token。iOS 26.4 及以上使用 `contextSize` 与 `tokenCount(for:)` 真实计数，更早版本按字符数保守估算（窗口按 4,096 计）。

## 结构化输出

健康回答由 `HealthAIAnswerParser` 统一解析以下五段：结论、依据、建议、留意、下一步可问。无法解析时保留原始文本展示，但不会伪造结构化字段。

每条健康回答同时携带实际 `AIResponseSource`。Pulse AI 页面按回答显示 Provider 名称和实际模型；今日问答只接受千问回答，长期档案本地回答标记为“本地确定性健康引擎”。

餐食输入只接受 JPEG、PNG、WebP、HEIC 和 HEIF，公共请求允许 1 到 10 张非空图片；具体 Provider 可以继续收紧数量和字节上限。千问当前限制单图 5 MB、总量 20 MB。

相机或相册原图通过 ImageIO 在后台完成方向校正、最长边 2048 像素的缩放和 JPEG 编码，最终请求图片不超过 5 MB，避免大图解码阻塞 SwiftUI 主线程。

餐食视觉只接受不超过 512 KB 的单个严格 JSON 对象。非餐食、图片不清晰或无法估算时 Provider 必须返回 `abstained`，且 `foods` 必须为空。识别结果必须包含 1 到 20 项有效食物：名称最多 80 个字符，单项热量必须在 `0...5000`，所有已提供的置信度必须在 `0...1`。主名称最多 120 个字符，警告最多 5 条且每条最多 160 个字符，模型报告的总热量必须在 `0...100000`。

低于 0.8 的总置信度、`needs_review` 状态，或模型报告总热量与逐项合计不一致时，结果会标记 `requiresReview`。分析结果只是草稿，必须经过现有确认页才能保存，禁止生成演示数据代替真实结果。

饮品输出同样使用严格 JSON：主名称必填、置信度必须在 `0...1`，候选最多 5 项。餐食和饮品确认后会把实际 Provider、模型与置信度持久化到记录，并通过当前 iCloud 用户的 CloudKit private database 同步结构化数据；照片、文件 ID 和旧图片 URL 不进入 CloudKit。

## 接入新 Provider

1. 为供应商创建独立目录，例如 `Providers/Kimi/`。
2. 实现 `AITextProviding` 或 `AIVisionProviding`，只声明实际验证过的能力。
3. 把实现注册到 `AIProviderRegistry`，不要在 Chat、Meal 或 UI 中写供应商分支。
4. 在对应业务路由中配置顺序；一次只调用一个 Provider。
5. OpenAI-compatible 文本模型可以复用通用适配思路，但供应商差异必须由 profile 描述，不得强制发送未验证的 `temperature`、thinking 或视觉参数。
6. 增加请求 DTO、鉴权头、重试边界、取消行为、能力过滤和解析测试。

未来 iOS 27 Core AI 健康聊天仍使用 `.appleOnDevice`。只有聊天 `.aimodel`、分词器、生成循环、取消处理和五段式输出契约全部完成后，才可注册 `.healthChat`。其内部可依次选择自定义 Core AI 模型、Foundation Models 系统模型和确定性 responder，上层 Feature API 不需要再次修改。

## 本地开发凭据

在 Xcode 的 Edit Scheme → Run → Arguments → Environment Variables 中添加 `HEALTH_AI_API_KEY`，值填写自己的 DashScope API Key。兼容变量为 `BIOBALANCE_ALIYUN_AI_API_KEY`、`BIOBALANCE_AI_API_KEY`，按此顺序作为后备；不要同时配置多个不同密钥。内部配置页也可以把密钥保存到本机 Keychain。

环境变量中的非空密钥会在首次请求时尝试保存到 Keychain。删除 Scheme 变量不会自动删除已保存的 Keychain 密钥；可在内部配置页清除。缺少凭据时返回 `missingAPIKey`，不会使用仓库共享密钥。不要将含真实密钥的共享 Scheme、截图或配置提交到仓库。
