/// SubjectCutoutService 负责把识别照片中的商品/食物主体抠出（去背景）。
/// 使用 Vision 前景实例掩码（iOS 17+）；系统不支持或未识别到主体时返回 nil，调用方回退原图。

import Foundation
import UIKit
import Vision

enum SubjectCutoutService {
    /// 抠出最大前景主体；失败返回 nil。
    static func cutoutSubject(from image: UIImage) async -> UIImage? {
        guard #available(iOS 17.0, *) else { return nil }
        guard let cgImage = image.cgImage else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else {
                return nil
            }
            let maskedBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
            let context = CIContext()
            guard let outputCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            return UIImage(cgImage: outputCGImage)
        } catch {
            return nil
        }
    }
}
