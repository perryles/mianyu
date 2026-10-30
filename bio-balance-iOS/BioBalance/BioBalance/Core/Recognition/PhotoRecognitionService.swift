import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PhotoRecognitionUseCase: String, Codable, Sendable {
    case drinkStamp
    case mealCalorie
}

nonisolated struct PhotoRecognitionCandidate: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let confidence: Double
}

nonisolated struct PhotoRecognitionResult: Codable, Sendable, Identifiable {
    var id: String { "\(useCase.rawValue)-\(primaryName)-\(Int(capturedAt.timeIntervalSince1970))" }
    var useCase: PhotoRecognitionUseCase
    var primaryName: String
    var candidates: [PhotoRecognitionCandidate]
    var storeName: String?
    var cityName: String?
    var capturedAt: Date
    var confidence: Double
    var locationSummary: SharedLocationSummary?
    var errorMessage: String?
    var estimatedCalories: Int?
    var recognizedFoods: [MealFoodItem]?
    var aiProviderID: String?
    var aiModel: String?

    var aiSourceLabel: String? {
        guard let aiProviderID, !aiProviderID.isEmpty else { return nil }
        let providerName = aiProviderID == AIProviderID.qwen.rawValue ? "阿里云千问" : aiProviderID
        guard let aiModel, !aiModel.isEmpty else { return providerName }
        return "\(providerName) · \(aiModel)"
    }

    /// Provider 要求人工复核或返回提示时，不把结果当作确定事实。
    var requiresReview: Bool {
        confidence < 0.8 || !(errorMessage?.isEmpty ?? true)
    }
}

nonisolated enum PhotoRecognitionServiceError: LocalizedError {
    case compressionFailed
    case invalidPhotoData
    case imageTooLarge
    case timedOut

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "图片压缩失败"
        case .invalidPhotoData:
            return String(localized: "无法读取所选照片，请重新选择。")
        case .imageTooLarge:
            return String(localized: "照片体积过大，请选择另一张照片。")
        case .timedOut:
            return String(localized: "识别请求超时，请检查网络后重试，或手动记录这餐。")
        }
    }
}

nonisolated final class PhotoRecognitionService: @unchecked Sendable {
    static let shared = PhotoRecognitionService()

    private let mealAnalysisProvider: any MealImageAnalysisProviding
    private let drinkAnalysisProvider: any DrinkImageAnalysisProviding

    init(
        mealAnalysisProvider: any MealImageAnalysisProviding = MealImageAnalysisProviderFactory.makeDefault(),
        drinkAnalysisProvider: any DrinkImageAnalysisProviding = DrinkImageAnalysisProviderFactory.makeDefault()
    ) {
        self.mealAnalysisProvider = mealAnalysisProvider
        self.drinkAnalysisProvider = drinkAnalysisProvider
    }

    func recognize(
        imageData: Data,
        useCase: PhotoRecognitionUseCase
    ) async -> Result<PhotoRecognitionResult, Error> {
        do {
            let compressed = try await Self.prepareImageData(imageData)
            switch useCase {
            case .mealCalorie:
                return .success(try await withThrowingTaskGroup(of: PhotoRecognitionResult.self) { group in
                    group.addTask { try await self.recognizeMeal(compressedData: compressed) }
                    group.addTask {
                        try await Task.sleep(for: .seconds(45))
                        throw PhotoRecognitionServiceError.timedOut
                    }
                    let value = try await group.next()!
                    group.cancelAll()
                    return value
                })
            case .drinkStamp:
                return .success(try await recognizeDrink(compressedData: compressed))
            }
        } catch {
            return .failure(error)
        }
    }

    /// 将 Provider-neutral 草稿映射到现有 DTO，保持当前确认页和本地存储兼容。
    private func recognizeMeal(
        compressedData: Data
    ) async throws -> PhotoRecognitionResult {
        let capturedAt = Date()
        let analysis = try await mealAnalysisProvider.analyze(
            AIMealAnalysisRequest(
                images: [AIMealImageInput(data: compressedData)],
                capturedAt: capturedAt,
                localeIdentifier: Locale.current.identifier
            )
        )

        // 识别结果仍是待确认草稿；此处只做旧页面所需的 DTO 映射，不直接写入本地记录或 HealthKit。
        let foods = analysis.foods.enumerated().map { index, food in
            MealFoodItem(
                id: "meal-food-\(index)-\(UUID().uuidString)",
                name: food.name,
                calories: food.calories,
                proteinGrams: food.proteinGrams,
                carbohydrateGrams: food.carbohydrateGrams,
                fatGrams: food.fatGrams,
                fiberGrams: food.fiberGrams,
                servingAmount: food.estimatedAmount,
                servingUnit: food.unit,
                confidence: food.confidence,
                nutritionSource: .aiEstimate
            )
        }
        let candidates = analysis.foods.prefix(3).enumerated().map { index, food in
            PhotoRecognitionCandidate(
                id: "meal-candidate-\(index)",
                title: food.name,
                confidence: food.confidence ?? analysis.confidence
            )
        }
        let warning = analysis.warnings.isEmpty
            ? (analysis.requiresReview ? "AI 估算置信度较低，请确认食物和热量。" : nil)
            : analysis.warnings.joined(separator: "；")

        let result = PhotoRecognitionResult(
            useCase: .mealCalorie,
            primaryName: analysis.primaryName,
            candidates: candidates,
            storeName: nil,
            cityName: nil,
            capturedAt: capturedAt,
            confidence: analysis.confidence,
            locationSummary: nil,
            errorMessage: warning,
            estimatedCalories: analysis.estimatedCalories,
            recognizedFoods: foods,
            aiProviderID: analysis.provider.rawValue,
            aiModel: analysis.model
        )
        return result
    }

    private func recognizeDrink(compressedData: Data) async throws -> PhotoRecognitionResult {
        let capturedAt = Date()
        async let analysisTask = drinkAnalysisProvider.analyze(
            AIDrinkAnalysisRequest(
                image: AIMealImageInput(data: compressedData),
                capturedAt: capturedAt,
                localeIdentifier: Locale.current.identifier
            )
        )
        async let locationTask = resolvedLocationSummary()
        let (analysis, locationSummary) = try await (analysisTask, locationTask)
        let candidates = analysis.candidates.enumerated().map { index, candidate in
            PhotoRecognitionCandidate(
                id: "drink-candidate-\(index)",
                title: candidate.name,
                confidence: candidate.confidence
            )
        }
        let warning = analysis.warnings.isEmpty
            ? (analysis.requiresReview ? "AI 识别置信度较低，请确认饮品与店名。" : nil)
            : analysis.warnings.joined(separator: "；")
        let result = PhotoRecognitionResult(
            useCase: .drinkStamp,
            primaryName: analysis.primaryName,
            candidates: candidates,
            storeName: analysis.storeName,
            cityName: nil,
            capturedAt: capturedAt,
            confidence: analysis.confidence,
            locationSummary: locationSummary,
            errorMessage: warning,
            estimatedCalories: nil,
            recognizedFoods: nil,
            aiProviderID: analysis.provider.rawValue,
            aiModel: analysis.model
        )
        return result
    }

    /// ImageIO 在后台完成解码、方向校正和缩放，避免大图阻塞 SwiftUI 的 MainActor。
    static func prepareImageData(_ sourceData: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try encodeBoundedJPEG(sourceData)
        }.value
    }

    private static func encodeBoundedJPEG(_ sourceData: Data) throws -> Data {
        let maximumDimension = 2_048
        let maximumBytes = 5 * 1_024 * 1_024
        guard !sourceData.isEmpty,
              let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw PhotoRecognitionServiceError.compressionFailed
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw PhotoRecognitionServiceError.compressionFailed
        }

        let compressionQualities: [Double] = [0.82, 0.68, 0.54, 0.4]
        for quality in compressionQualities {
            let destinationData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                destinationData as CFMutableData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else { continue }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else { continue }
            let data = Data(referencing: destinationData)
            if data.count <= maximumBytes { return data }
        }
        throw PhotoRecognitionServiceError.imageTooLarge
    }

    private func resolvedLocationSummary() async -> SharedLocationSummary? {
        let state = await LocationSharingService.shared.requestAuthorizationIfNeeded()
        guard state == .authorized else { return nil }
        return await LocationSharingService.shared.fetchCurrentSummaryIfAuthorized()
    }
}
