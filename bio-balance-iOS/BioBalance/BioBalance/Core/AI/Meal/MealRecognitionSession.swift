import Foundation
import Observation
import UIKit

/// 餐食识别流程的显式状态机。
/// Hub 页与识别页只读该状态驱动 UI，不再各自维护零散的 Bool 标志。
nonisolated enum MealRecognitionState {
    case idle
    /// 正在校正方向、压缩图片（已在后台完成解码）
    case preparing
    /// 图片就绪，等待/进行云端识别
    case recognizing
    /// 识别成功但置信度不足，需要用户重点核对
    case lowConfidence(PhotoRecognitionResult)
    /// 识别成功且可直接进入确认
    case success(PhotoRecognitionResult)
    /// 识别失败，附带可恢复的错误
    case failure(MealRecognitionFailure)
}

/// 识别失败的可恢复分类。UI 据此给出不同 CTA，而不是单一"知道了"。
nonisolated enum MealRecognitionFailure: Equatable {
    case invalidImage
    case imageTooLarge
    case networkUnavailable
    case timeout
    case recognitionFailed(String?)
    case cancelled

    init(error: Error) {
        switch error {
        case let urlError as URLError:
            switch urlError.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                self = .networkUnavailable
            case .timedOut:
                self = .timeout
            case .cancelled:
                self = .cancelled
            default:
                self = .recognitionFailed(urlError.localizedDescription)
            }
        case PhotoRecognitionServiceError.invalidPhotoData, PhotoRecognitionServiceError.compressionFailed:
            self = .invalidImage
        case PhotoRecognitionServiceError.imageTooLarge:
            self = .imageTooLarge
        case PhotoRecognitionServiceError.timedOut:
            self = .timeout
        case AIMealAnalysisError.abstained:
            self = .recognitionFailed(error.localizedDescription)
        default:
            self = .recognitionFailed(error.localizedDescription)
        }
    }

    /// 面向用户的标题与建议文案；全部可恢复，不出现"知道了"式死胡同。
    var title: String {
        switch self {
        case .invalidImage:
            return String(localized: "无法读取这张图片")
        case .imageTooLarge:
            return String(localized: "图片过大，识别失败")
        case .networkUnavailable:
            return String(localized: "当前无法连接网络")
        case .timeout:
            return String(localized: "识别请求超时")
        case .recognitionFailed:
            return String(localized: "没有识别到明确食物")
        case .cancelled:
            return String(localized: "识别已取消")
        }
    }

    var message: String {
        switch self {
        case .invalidImage:
            return String(localized: "图片数据无法解析，可以重新拍摄或换一张照片。")
        case .imageTooLarge:
            return String(localized: "请重新拍摄或换一张较小的照片再试。")
        case .networkUnavailable:
            return String(localized: "你仍然可以手动记录这餐，网络恢复后再试拍照识别。")
        case .timeout:
            return String(localized: "网络响应较慢，可以重试或先手动记录。")
        case .recognitionFailed(let detail):
            let fallback = String(localized: "尽量让食物完整出现在画面中，光线充足，避免严重遮挡。")
            guard let detail, !detail.isEmpty else { return fallback }
            return detail
        case .cancelled:
            return String(localized: "可以重新开始识别或手动记录。")
        }
    }

    /// 无障碍与诊断用的稳定标识。
    var diagnosticCode: String {
        switch self {
        case .invalidImage: "invalid_image"
        case .imageTooLarge: "image_too_large"
        case .networkUnavailable: "network_unavailable"
        case .timeout: "timeout"
        case .recognitionFailed: "recognition_failed"
        case .cancelled: "cancelled"
        }
    }
}

/// 一次识别会话：从图片选择到确认/放弃的完整上下文。
/// 同一会话内重复进入结果页不会重新调用 AI（结果缓存于 session 内）。
@MainActor
@Observable
final class MealRecognitionSession {
    /// 原始 UIImage 仅用于当前确认流程展示；不持久化原图。
    private(set) var photoImage: UIImage?
    private(set) var state: MealRecognitionState = .idle
    /// 用户在结果页做过任何修改后置位，用于退出时提示"未保存"。
    private(set) var hasUnsavedEdits = false
    /// 是否存在可复用的识别结果（编辑返回不重复调用 AI）。
    private(set) var hasCachedResult = false

    private var recognitionTask: Task<Void, Never>?
    private var preparedImageData: Data?

    /// 已压缩待上传/待保存的图片数据；仅保存成功前存在，随 finish() 释放。
    var preparedImageDataForSave: Data? {
        preparedImageData
    }

    var isBusy: Bool {
        switch state {
        case .preparing, .recognizing: return true
        default: return false
        }
    }

    /// 成功/低置信度时携带的结果。
    var result: PhotoRecognitionResult? {
        switch state {
        case .success(let result), .lowConfidence(let result): return result
        default: return nil
        }
    }

    var failure: MealRecognitionFailure? {
        if case .failure(let failure) = state { return failure }
        return nil
    }

    // MARK: - 识别入口

    /// 用相机或相册的原始数据开始一次新识别；若已有缓存结果则直接复用。
    func start(imageData: Data, photoImage: UIImage?, service: PhotoRecognitionService = .shared) {
        guard !isBusy else { return }
        self.photoImage = photoImage ?? UIImage(data: imageData)
        // 新图片意味着新一轮识别：清掉上一轮缓存，避免误复用。
        hasCachedResult = false
        hasUnsavedEdits = false
        state = .preparing
        recognitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await PhotoRecognitionService.prepareImageData(imageData)
                guard !Task.isCancelled else { return }
                self.preparedImageData = prepared
                self.state = .recognizing
                let outcome = await service.recognize(imageData: prepared, useCase: .mealCalorie)
                guard !Task.isCancelled else { return }
                switch outcome {
                case .success(let result):
                    let isLowConfidence = result.confidence < 0.6 || result.requiresReview
                    self.state = isLowConfidence ? .lowConfidence(result) : .success(result)
                    self.hasCachedResult = true
                case .failure(let error):
                    self.state = .failure(MealRecognitionFailure(error: error))
                }
            } catch is CancellationError {
                self.state = .idle
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failure(MealRecognitionFailure(error: error))
            }
        }
    }

    /// 用户主动取消：终止网络任务并回到空闲，不留悬挂 Task。
    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        state = .idle
    }

    /// 相册等来源在识别前就失败时，直接进入失败态（不发网络请求）。
    func failBeforeStart(_ failure: MealRecognitionFailure) {
        recognitionTask?.cancel()
        recognitionTask = nil
        state = .failure(failure)
    }

    /// 重新识别当前图片（失败重试 / 更换意图前的复用路径）。
    func retry(service: PhotoRecognitionService = .shared) {
        guard let preparedImageData, !isBusy else { return }
        state = .recognizing
        recognitionTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await service.recognize(imageData: preparedImageData, useCase: .mealCalorie)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let result):
                let isLowConfidence = result.confidence < 0.6 || result.requiresReview
                self.state = isLowConfidence ? .lowConfidence(result) : .success(result)
                self.hasCachedResult = true
            case .failure(let error):
                self.state = .failure(MealRecognitionFailure(error: error))
            }
        }
    }

    // MARK: - 会话结果管理

    /// 用户在结果页修改了食物或餐次。
    func markEdited() {
        hasUnsavedEdits = true
    }

    /// 保存成功后清空会话（照片展示引用与临时数据一并释放）。
    func finish() {
        recognitionTask?.cancel()
        recognitionTask = nil
        photoImage = nil
        preparedImageData = nil
        state = .idle
        hasUnsavedEdits = false
        hasCachedResult = false
    }
}
