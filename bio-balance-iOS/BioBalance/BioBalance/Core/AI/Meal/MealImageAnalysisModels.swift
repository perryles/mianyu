import Foundation

/// 单张待分析图片的原始数据与 MIME 类型。
nonisolated struct AIMealImageInput: Sendable {
    static let supportedMimeTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif"
    ]

    let data: Data
    let mimeType: String

    init(data: Data, mimeType: String = "image/jpeg") {
        self.data = data
        self.mimeType = mimeType
    }

    var normalizedMimeType: String {
        mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var hasSupportedMimeType: Bool {
        Self.supportedMimeTypes.contains(normalizedMimeType)
    }
}

/// 餐食识别的统一请求，允许云端与本地 Provider 共享同一输入契约。
nonisolated struct AIMealAnalysisRequest: Sendable {
    let images: [AIMealImageInput]
    let note: String?
    let capturedAt: Date
    let localeIdentifier: String

    init(
        images: [AIMealImageInput],
        note: String? = nil,
        capturedAt: Date = Date(),
        localeIdentifier: String = Locale.current.identifier
    ) {
        self.images = images
        self.note = note
        self.capturedAt = capturedAt
        self.localeIdentifier = localeIdentifier
    }

    /// 所有视觉 Provider 共用的输入边界；单个 Provider 可继续收紧图片数量和大小。
    func validateCommonInput() throws {
        guard (1...10).contains(images.count), images.allSatisfy({ !$0.data.isEmpty }) else {
            throw AIMealAnalysisError.invalidImageCount
        }
        guard images.allSatisfy(\.hasSupportedMimeType) else {
            throw AIMealAnalysisError.unsupportedImageFormat
        }
    }
}

/// 单项食物的估算热量和可选置信度。
nonisolated struct AIMealFoodEstimate: Sendable, Equatable {
    let name: String
    let calories: Int
    let confidence: Double?
    let estimatedAmount: Double?
    let unit: String?
    let proteinGrams: Double?
    let carbohydrateGrams: Double?
    let fatGrams: Double?
    let fiberGrams: Double?

    init(
        name: String,
        calories: Int,
        confidence: Double?,
        estimatedAmount: Double? = nil,
        unit: String? = nil,
        proteinGrams: Double? = nil,
        carbohydrateGrams: Double? = nil,
        fatGrams: Double? = nil,
        fiberGrams: Double? = nil
    ) {
        self.name = name
        self.calories = calories
        self.confidence = confidence
        self.estimatedAmount = estimatedAmount
        self.unit = unit
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
    }
}

/// 供确认页展示的餐食草稿；保存前必须尊重 `requiresReview`。
nonisolated struct AIMealAnalysisResult: Sendable, Equatable {
    let primaryName: String
    let foods: [AIMealFoodEstimate]
    let estimatedCalories: Int
    let confidence: Double
    let requiresReview: Bool
    let warnings: [String]
    let provider: AIProviderID
    let model: String
}

/// 餐食输入校验、模型弃答和结构化输出错误。
nonisolated enum AIMealAnalysisError: LocalizedError, Sendable {
    case invalidImageCount
    case unsupportedImageFormat
    case imageTooLarge
    case abstained(String?)
    case invalidStructuredResponse

    var diagnosticCode: String {
        switch self {
        case .invalidImageCount:
            return "invalid_image_count"
        case .unsupportedImageFormat:
            return "unsupported_image_format"
        case .imageTooLarge:
            return "image_too_large"
        case .abstained:
            return "abstained"
        case .invalidStructuredResponse:
            return "invalid_structured_response"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidImageCount:
            return String(localized: "请选择 1 到 10 张餐食图片。")
        case .unsupportedImageFormat:
            return String(localized: "图片格式不受支持，请使用 JPEG、PNG、WebP、HEIC 或 HEIF。")
        case .imageTooLarge:
            return String(localized: "图片数据过大，请减少图片数量或重新选择。")
        case .abstained(let reason):
            return mealNonBlank(reason) ?? "没有识别到足够明确的餐食，请重新拍摄或手动记录。"
        case .invalidStructuredResponse:
            return String(localized: "AI 返回的餐食数据格式无效，请重试或手动记录。")
        }
    }
}

nonisolated private func mealNonBlank(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : String(trimmed.prefix(240))
}
