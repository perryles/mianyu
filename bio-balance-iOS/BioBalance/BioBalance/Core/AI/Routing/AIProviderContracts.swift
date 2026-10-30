import Foundation

/// 稳定逻辑标识不等同于具体模型名；换模型时无需修改业务层。
nonisolated enum AIProviderID: Hashable, Sendable, Codable {
    case qwen
    case appleOnDevice
    case kimi
    case deepSeek
    case miniMax
    case deterministic
    case custom(String)

    var rawValue: String {
        switch self {
        case .qwen: return "qwen"
        case .appleOnDevice: return "apple-on-device"
        case .kimi: return "kimi"
        case .deepSeek: return "deepseek"
        case .miniMax: return "minimax"
        case .deterministic: return "deterministic"
        case .custom(let value): return "custom:\(value)"
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "qwen": self = .qwen
        case "apple-on-device": self = .appleOnDevice
        case "kimi": self = .kimi
        case "deepseek": self = .deepSeek
        case "minimax": self = .miniMax
        case "deterministic": self = .deterministic
        default:
            self = .custom(String(rawValue.dropFirst(rawValue.hasPrefix("custom:") ? 7 : 0)))
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Provider 可声明的最小能力集合；路由只按能力匹配，不按供应商名称猜测。
nonisolated enum AICapability: String, Codable, Hashable, Sendable {
    case healthChat
    case healthAnalysis
    case prescriptionStructuring
    case mealVision
    case drinkVision
}

/// 注册表使用描述信息完成能力过滤，不能根据供应商名称推断视觉能力。
nonisolated struct AIProviderDescriptor: Sendable, Equatable {
    let id: AIProviderID
    let displayName: String
    let capabilities: Set<AICapability>
    let isLocal: Bool
}

/// 随回答传递到 UI 的真实来源快照，避免页面根据当前配置猜测历史回答由谁生成。
nonisolated struct AIResponseSource: Codable, Hashable, Sendable {
    let providerID: AIProviderID
    let displayName: String
    let model: String?
    let isLocal: Bool

    init(
        providerID: AIProviderID,
        displayName: String,
        model: String? = nil,
        isLocal: Bool
    ) {
        self.providerID = providerID
        self.displayName = String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.model = normalizedModel.isEmpty ? nil : String(normalizedModel.prefix(80))
        self.isLocal = isLocal
    }

    static let deterministic = AIResponseSource(
        providerID: .deterministic,
        displayName: "本地确定性健康引擎",
        isLocal: true
    )

    var displayLabel: String {
        guard let model else { return displayName }
        return "\(displayName) · \(model)"
    }
}

/// 与具体云端 SDK 无关的文本消息格式。
nonisolated struct AITextMessage: Codable, Sendable, Equatable {
    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

/// 文本 Provider 的统一请求；当前只允许健康文本能力。
nonisolated struct AITextRequest: Sendable {
    let capability: AICapability
    let messages: [AITextMessage]

    init(capability: AICapability, messages: [AITextMessage]) {
        precondition(
            capability == .healthChat ||
                capability == .healthAnalysis ||
                capability == .prescriptionStructuring
        )
        self.capability = capability
        self.messages = messages
    }
}

/// 统一文本响应，并保留实际 Provider 与模型用于审计日志。
nonisolated struct AITextResponse: Sendable, Equatable {
    let content: String
    let providerID: AIProviderID
    let model: String
}

/// 所有 Provider 的公共元数据与运行时可用性契约。
nonisolated protocol AIProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }
    func isAvailable(for capability: AICapability) -> Bool
}

/// 文本和视觉协议刻意分开，避免所有 Provider 被迫实现不支持的输入类型。
nonisolated protocol AITextProviding: AIProvider {
    func generateText(_ request: AITextRequest) async throws -> AITextResponse
}

nonisolated protocol AIVisionProviding: AIProvider {
    func analyze(_ request: AIMealAnalysisRequest) async throws -> AIMealAnalysisResult
}

/// 流式文本 Provider：返回累积文本快照的 AsyncThrowingStream。
/// 每次 yield 的 String 是到当前为止的完整累积文本（snapshot 模式，非 delta）。
nonisolated protocol AIStreamingTextProviding: AITextProviding {
    func streamText(_ request: AITextRequest) async throws -> AsyncThrowingStream<String, Error>
}

/// 饮品打卡与餐食热量的结构化输出不同，使用独立协议避免混用 Prompt 和 DTO。
nonisolated protocol AIDrinkVisionProviding: AIProvider {
    func analyzeDrink(_ request: AIDrinkAnalysisRequest) async throws -> AIDrinkAnalysisResult
}
