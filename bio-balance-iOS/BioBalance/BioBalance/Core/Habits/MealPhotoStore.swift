import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 餐食照片仅保存在本机 Application Support；CloudKit 只同步结构化确认结果。
nonisolated final class MealPhotoStore: @unchecked Sendable {
    static let shared = MealPhotoStore()

    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = root.appendingPathComponent("MealPhotos", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func savePreparedJPEG(_ data: Data, recordID: String) throws -> (photo: String, thumbnail: String) {
        let safeID = recordID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let photoName = "meal-\(safeID).jpg"
        let thumbnailName = "meal-\(safeID)-thumb.jpg"
        try data.write(to: directory.appendingPathComponent(photoName), options: .atomic)
        try makeThumbnail(data, destination: directory.appendingPathComponent(thumbnailName))
        return (photoName, thumbnailName)
    }

    func url(for filename: String?) -> URL? {
        guard let filename, !filename.contains("/"), !filename.contains("..") else { return nil }
        let url = directory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func removeFiles(forRecordID recordID: String) {
        let safeID = recordID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        try? fileManager.removeItem(at: directory.appendingPathComponent("meal-\(safeID).jpg"))
        try? fileManager.removeItem(at: directory.appendingPathComponent("meal-\(safeID)-thumb.jpg"))
    }

    private func makeThumbnail(_ data: Data, destination: URL) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320
              ] as CFDictionary),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
    }
}
