import Foundation

#if canImport(CoreAI)
import CoreAI
import CoreImage
import CoreVideo
#endif

/// Apple Core AI 的系统、模型资产、接口契约和推理输出错误。
nonisolated enum AppleCoreAIMealAnalysisError: LocalizedError, Sendable {
    case unsupportedSystem
    case modelMissing
    case invalidModelAsset
    case invalidModelContract(String)
    case invalidImage
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return String(localized: "Apple Core AI 需要 iOS 27 或更高版本的受支持设备。")
        case .modelMissing:
            return String(localized: "Apple Core AI 餐食模型尚未安装。")
        case .invalidModelAsset:
            return String(localized: "Apple Core AI 餐食模型资源无效。")
        case .invalidModelContract(let detail):
            return String(localized: "Apple Core AI 餐食模型接口不兼容：\(detail)")
        case .invalidImage:
            return String(localized: "餐食图片无法转换为 Core AI 模型输入。")
        case .invalidOutput:
            return String(localized: "Apple Core AI 模型返回了无效结果。")
        }
    }
}

/// `apple/coreai-models` 导出的餐食模型运行适配器。
///
/// 模型契约：
/// - Bundle 资源：`BioBalanceMealAnalyzer.aimodel`
/// - 函数：`analyze`
/// - 图像输入：`image`
/// - UTF-8 JSON 输出：`result_json_utf8`（一维 UInt8 NDArray，可用 0 填充）
nonisolated struct AppleCoreAIMealImageAnalysisProvider: AIVisionProviding {
    static let modelResourceName = "BioBalanceMealAnalyzer"
    static let modelResourceExtension = "aimodel"
    static let functionName = "analyze"
    static let imageInputName = "image"
    static let resultOutputName = "result_json_utf8"

    let modelURL: URL

    let descriptor = AIProviderDescriptor(
        id: .appleOnDevice,
        displayName: "Apple Core AI（本地）",
        capabilities: [.mealVision],
        isLocal: true
    )

    /// 仓库没有有效 .aimodel 时返回 nil，因此注册表不会把占位实现判定为可用。
    static var registeredProvider: AppleCoreAIMealImageAnalysisProvider? {
        guard let url = bundledModelURL(), canRun(modelAt: url) else { return nil }
        return AppleCoreAIMealImageAnalysisProvider(modelURL: url)
    }

    static func bundledModelURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: modelResourceName, withExtension: modelResourceExtension)
    }

    static func canRun(modelAt url: URL) -> Bool {
        #if canImport(CoreAI)
        if #available(anyAppleOS 27.0, *) {
            return AIModelAsset.isValid(at: url)
        }
        #endif
        return false
    }

    func isAvailable(for capability: AICapability) -> Bool {
        capability == .mealVision && Self.canRun(modelAt: modelURL)
    }

    func analyze(_ request: AIMealAnalysisRequest) async throws -> AIMealAnalysisResult {
        try request.validateCommonInput()
        guard request.images.count == 1, let image = request.images.first else {
            throw AIMealAnalysisError.invalidImageCount
        }

        #if canImport(CoreAI)
        if #available(anyAppleOS 27.0, *) {
            return try await analyzeWithCoreAI(image.data)
        }
        #endif
        throw AppleCoreAIMealAnalysisError.unsupportedSystem
    }
}

#if canImport(CoreAI)
@available(anyAppleOS 27.0, *)
private extension AppleCoreAIMealImageAnalysisProvider {
    func analyzeWithCoreAI(_ imageData: Data) async throws -> AIMealAnalysisResult {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw AppleCoreAIMealAnalysisError.modelMissing
        }
        guard AIModelAsset.isValid(at: modelURL) else {
            throw AppleCoreAIMealAnalysisError.invalidModelAsset
        }

        let options = SpecializationOptions.default
        let model: AIModel
        if let cached = try AIModelCache.default.model(for: modelURL, options: options) {
            model = cached
        } else {
            model = try await AIModel.specialize(
                contentsOf: modelURL,
                options: options,
                cache: .default,
                cachePolicy: .persistent
            )
        }

        guard let function = try model.loadFunction(named: Self.functionName) else {
            throw AppleCoreAIMealAnalysisError.invalidModelContract("缺少 \(Self.functionName) 函数")
        }
        guard case let .image(imageDescriptor)? = function.descriptor.inputDescriptor(of: Self.imageInputName) else {
            throw AppleCoreAIMealAnalysisError.invalidModelContract("缺少 image 图像输入")
        }
        guard case let .ndArray(outputDescriptor)? = function.descriptor.outputDescriptor(of: Self.resultOutputName),
              outputDescriptor.scalarType == .uint8,
              outputDescriptor.rank == 1 else {
            throw AppleCoreAIMealAnalysisError.invalidModelContract("result_json_utf8 必须是一维 UInt8 NDArray")
        }

        let rawPixelBuffer = try makePixelBuffer(from: imageData, descriptor: imageDescriptor)
        let pixelBuffer = CVReadOnlyPixelBuffer(unsafeBuffer: rawPixelBuffer)
        let stream = ComputeStream()
        let outputs = try function.encode(
            inputs: [Self.imageInputName: InferenceFunction.AsyncValue(pixelBuffer)],
            to: stream
        )
        guard let output = outputs[Self.resultOutputName],
              let array = try await output.ndArray,
              array.scalarType == .uint8,
              array.shape.count == 1 else {
            throw AppleCoreAIMealAnalysisError.invalidOutput
        }

        let elementCount = array.shape[0]
        guard elementCount > 0, elementCount <= 512 * 1_024 else {
            throw AppleCoreAIMealAnalysisError.invalidOutput
        }
        let view = array.view(as: UInt8.self)
        guard view.isContiguous else {
            throw AppleCoreAIMealAnalysisError.invalidOutput
        }
        let paddedData = view.withUnsafePointer { pointer, _, _ in
            Data(bytes: pointer, count: elementCount)
        }
        let jsonData = Data(paddedData.prefix { $0 != 0 })
        return try AIMealStructuredResponseDecoder.decode(
            jsonData,
            provider: .appleOnDevice,
            model: modelURL.deletingPathExtension().lastPathComponent
        )
    }

    func makePixelBuffer(from data: Data, descriptor: ImageDescriptor) throws -> CVPixelBuffer {
        guard let source = CIImage(data: data), !source.extent.isEmpty else {
            throw AppleCoreAIMealAnalysisError.invalidImage
        }

        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            descriptor.width,
            descriptor.height,
            descriptor.pixelFormatType,
            attributes,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw AppleCoreAIMealAnalysisError.invalidImage
        }

        let targetWidth = CGFloat(descriptor.width)
        let targetHeight = CGFloat(descriptor.height)
        let scale = max(targetWidth / source.extent.width, targetHeight / source.extent.height)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let crop = CGRect(
            x: scaled.extent.midX - targetWidth / 2,
            y: scaled.extent.midY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
        let normalized = scaled
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        CIContext(options: [.cacheIntermediates: false]).render(
            normalized,
            to: pixelBuffer,
            bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return pixelBuffer
    }
}
#endif
