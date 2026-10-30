/// WatchThemeMediaPipeline 负责把用户选择的图片 / GIF / Live图 / 视频素材
/// 转码为手表可渲染的静态 PNG 或 5 秒内的 GIF，并提供去除背景与落盘能力。
import Foundation
import AVFoundation
import CoreGraphics
import CoreTransferable
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// WatchThemePickedMedia 是创建页选择素材后的中间表示。
nonisolated struct WatchThemePickedMedia: Sendable {
    enum Kind: Sendable {
        case staticImage
        case animated
    }

    let kind: Kind
    /// 静态图内容（kind == .staticImage 时有值）。
    var image: UIImage?
    /// 动图帧序列（kind == .animated 时有值），已按时长上限截断。
    let frames: [CGImage]
    /// 动图帧间隔（秒）。
    let frameDuration: Double
    /// 用户是否希望去除背景。
    var removeBackground: Bool
}

/// WatchThemeMediaPipeline 收敛素材加载、去背景、缩放与 GIF/PNG 编码。
enum WatchThemeMediaPipeline {
    /// 从 PhotosPickerItem 加载素材，自动识别静态图 / GIF / Live图 / 视频。
    static func load(item: PhotosPickerItem) async -> WatchThemePickedMedia? {
        if item.supportedContentTypes.contains(where: { UTType("com.compuserve.gif")?.conforms(to: $0) == true }),
           let data = try? await item.loadTransferable(type: Data.self),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetCount(source) > 1 {
            return animatedMedia(fromGIFData: data)
        }
        if let video = try? await item.loadTransferable(type: Movie.self) {
            return await animatedMedia(fromVideoURL: video.url)
        }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return WatchThemePickedMedia(kind: .staticImage, image: image, frames: [], frameDuration: 0, removeBackground: false)
        }
        return nil
    }

    /// 对已加载素材执行去背景（仅静态图）与转码，返回槽位元信息与落盘地址。
    static func process(
        media: WatchThemePickedMedia,
        slot: WatchThemeSlot,
        themeDirectory: URL
    ) async throws -> WatchThemeSlotMedia {
        var prepared = media
        if prepared.kind == .staticImage,
           prepared.removeBackground,
           let source = prepared.image,
           let cutout = await SubjectCutoutService.cutoutSubject(from: source) {
            prepared.image = cutout
        }
        let encodingInput = prepared
        return try await Task.detached(priority: .userInitiated) {
            try encodeAndWrite(media: encodingInput, slot: slot, themeDirectory: themeDirectory)
        }.value
    }

    /// 同步转码入口，供单元测试直接调用（不执行去背景）。
    static func processForTesting(
        media: WatchThemePickedMedia,
        slot: WatchThemeSlot,
        themeDirectory: URL
    ) throws -> WatchThemeSlotMedia {
        try encodeAndWrite(media: media, slot: slot, themeDirectory: themeDirectory)
    }

    nonisolated private static func encodeAndWrite(
        media: WatchThemePickedMedia,
        slot: WatchThemeSlot,
        themeDirectory: URL
    ) throws -> WatchThemeSlotMedia {
        switch media.kind {
        case .staticImage:
            let image = media.image ?? UIImage()
            let fileURL = themeDirectory.appendingPathComponent("\(slot.rawValue).png")
            let data = try encodePNG(image: image)
            try data.write(to: fileURL, options: .atomic)
            return WatchThemeSlotMedia(slot: slot, fileExtension: "png", isAnimated: false, fileSize: data.count)
        case .animated:
            let fileURL = themeDirectory.appendingPathComponent("\(slot.rawValue).gif")
            let data = try encodeGIF(frames: media.frames, frameDuration: media.frameDuration)
            try data.write(to: fileURL, options: .atomic)
            return WatchThemeSlotMedia(slot: slot, fileExtension: "gif", isAnimated: true, fileSize: data.count)
        }
    }

    // MARK: - GIF 加载

    private static func animatedMedia(fromGIFData data: Data) -> WatchThemePickedMedia {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return staticFallback
        }
        let frameCount = CGImageSourceGetCount(source)
        let clampedCount = min(frameCount, WatchCustomThemePolicy.maximumAnimationFrameCount)
        var frames: [CGImage] = []
        var totalDuration: Double = 0
        for index in 0..<clampedCount {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(frame)
            totalDuration += gifFrameDelay(source: source, index: index)
        }
        let duration = totalDuration > 0 ? min(totalDuration, WatchCustomThemePolicy.maximumAnimationDuration) : 1.0 / Double(WatchCustomThemePolicy.animationFrameRate)
        let perFrame = duration / Double(max(frames.count, 1))
        return WatchThemePickedMedia(kind: .animated, image: nil, frames: scaleFrames(frames), frameDuration: perFrame, removeBackground: false)
    }

    private static func gifFrameDelay(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 1.0 / Double(WatchCustomThemePolicy.animationFrameRate)
        }
        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? 0
        return delay > 0 ? min(delay, WatchCustomThemePolicy.maximumAnimationDuration) : 1.0 / Double(WatchCustomThemePolicy.animationFrameRate)
    }

    // MARK: - 视频 / Live Photo 加载

    private static func animatedMedia(fromVideoURL url: URL) async -> WatchThemePickedMedia {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else {
            return staticFallback
        }
        let trimmedDuration = min(duration.seconds, WatchCustomThemePolicy.maximumAnimationDuration)
        guard trimmedDuration > 0.1 else { return staticFallback }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let targetFrameCount = min(
            Int(trimmedDuration * Double(WatchCustomThemePolicy.animationFrameRate)),
            WatchCustomThemePolicy.maximumAnimationFrameCount
        )
        guard targetFrameCount > 0 else { return staticFallback }
        let step = trimmedDuration / Double(targetFrameCount)

        var frames: [CGImage] = []
        for index in 0..<targetFrameCount {
            let time = CMTime(seconds: Double(index) * step, preferredTimescale: 600)
            if let frame = try? await generator.image(at: time).image {
                frames.append(frame)
            }
        }
        guard !frames.isEmpty else { return staticFallback }
        let perFrame = 1.0 / Double(WatchCustomThemePolicy.animationFrameRate)
        return WatchThemePickedMedia(kind: .animated, image: nil, frames: scaleFrames(frames), frameDuration: perFrame, removeBackground: false)
    }

    private static var staticFallback: WatchThemePickedMedia {
        WatchThemePickedMedia(kind: .staticImage, image: nil, frames: [], frameDuration: 0, removeBackground: false)
    }

    // MARK: - 缩放与编码

    private static func scaleFrames(_ frames: [CGImage]) -> [CGImage] {
        let maxLength = WatchCustomThemePolicy.maximumAnimatedImageDimension
        return frames.map { frame in
            let longest = CGFloat(max(frame.width, frame.height))
            guard longest > maxLength else { return frame }
            let scale = maxLength / CGFloat(longest)
            let target = CGSize(width: (CGFloat(frame.width) * scale).rounded(), height: (CGFloat(frame.height) * scale).rounded())
            return resize(image: frame, to: target) ?? frame
        }
    }

    private static func resize(image: CGImage, to size: CGSize) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    nonisolated private static func encodePNG(image: UIImage) throws -> Data {
        guard let cgImage = scaleStatic(image).cgImage else {
            throw WatchThemeMediaError.encodingFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw WatchThemeMediaError.encodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw WatchThemeMediaError.encodingFailed
        }
        return output as Data
    }

    nonisolated private static func scaleStatic(_ image: UIImage) -> UIImage {
        let maxLength = WatchCustomThemePolicy.maximumStaticImageDimension
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxLength else { return image }
        let scale = maxLength / CGFloat(longest)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// GIF 编码：首帧含透明通道时输出仍为索引色透明，手表端按普通动图渲染。
    nonisolated private static func encodeGIF(frames: [CGImage], frameDuration: Double) throws -> Data {
        guard !frames.isEmpty else { throw WatchThemeMediaError.encodingFailed }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw WatchThemeMediaError.encodingFailed
        }
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDuration
            ]
        ]
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw WatchThemeMediaError.encodingFailed
        }
        return output as Data
    }
}

/// Movie 包装 PhotosPicker 视频选择的临时文件地址。
struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Movie(url: copy)
        }
    }
}

/// WatchThemeMediaError 描述素材转码过程中的可恢复错误。
enum WatchThemeMediaError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "素材转码失败，请换一张试试"
        }
    }
}
