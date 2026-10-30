import XCTest
@testable import BioBalance

nonisolated final class WatchCustomThemeTests: XCTestCase {
    // MARK: - 槽位解析

    @MainActor func testSlotResolverMapsHRVThresholds() {
        XCTAssertEqual(WatchThemeSlotResolver.slot(hrv: 60, stress: 10), .excellent)
        XCTAssertEqual(WatchThemeSlotResolver.slot(hrv: 48, stress: 0), .excellent)
        XCTAssertEqual(WatchThemeSlotResolver.slot(hrv: 30, stress: 10), .normal)
        XCTAssertEqual(WatchThemeSlotResolver.slot(hrv: 25, stress: 10), .normal)
        XCTAssertEqual(WatchThemeSlotResolver.slot(hrv: 10, stress: 10), .mild)
    }

    @MainActor func testSlotResolverOverloadBeatsHRV() {
        XCTAssertEqual(WatchThemeSlotResolver.slot(hrv: 60, stress: 80), .overloaded)
    }

    @MainActor func testSlotResolverFallsBackToStressWithoutHRV() {
        XCTAssertEqual(WatchThemeSlotResolver.slot(hrv: 0, stress: 10), .normal)
        XCTAssertEqual(WatchThemeSlotResolver.slot(hrv: 0, stress: 60), .mild)
    }

    @MainActor func testFallbackChainAlwaysContainsNormalAndSelf() {
        for slot in WatchThemeSlot.allCases {
            let chain = WatchThemeSlotResolver.fallbackChain(for: slot)
            XCTAssertTrue(chain.contains(slot))
            XCTAssertTrue(chain.contains(.normal))
            // normal 是兜底槽位，链即自身；其余槽位覆盖全部槽位且不重复。
            if slot == .normal {
                XCTAssertEqual(chain, [.normal])
            } else {
                XCTAssertEqual(chain.count, WatchThemeSlot.allCases.count)
                XCTAssertEqual(Set(chain), Set(WatchThemeSlot.allCases))
            }
        }
    }

    // MARK: - Meta Codable

    @MainActor func testThemeMetaCodableRoundTrip() throws {
        var theme = CustomWatchTheme(
            id: "theme-1",
            name: "Suki",
            slots: [
                .excellent: WatchThemeSlotMedia(slot: .excellent, fileExtension: "png", isAnimated: false, fileSize: 1234),
                .normal: WatchThemeSlotMedia(slot: .normal, fileExtension: "gif", isAnimated: true, fileSize: 45678)
            ]
        )
        theme.updatedAt = theme.createdAt

        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(CustomWatchTheme.self, from: data)

        XCTAssertEqual(decoded, theme)
    }

    @MainActor func testThemeMetaDecodingDropsUnknownSlots() throws {
        let json = """
        {"id":"theme-2","name":"A","createdAt":0,"updatedAt":0,
         "slots":{"excellent":{"slot":"excellent","fileExtension":"png","isAnimated":false,"fileSize":1},
                  "legacy":{"slot":"legacy","fileExtension":"png","isAnimated":false,"fileSize":2}}}
        """
        let decoded = try JSONDecoder().decode(CustomWatchTheme.self, from: Data(json.utf8))
        XCTAssertEqual(Array(decoded.slots.keys), [.excellent])
    }

    // MARK: - 策略常量

    @MainActor func testNameNormalizationTrimsAndLimits() {
        XCTAssertEqual(WatchCustomThemePolicy.normalizedThemeName("  我的名字  "), "我的名字")
        let long = String(repeating: "名", count: 30)
        XCTAssertEqual(WatchCustomThemePolicy.normalizedThemeName(long).count, WatchCustomThemePolicy.maximumNameLength)
    }

    // MARK: - 素材管线（编码约束）

    @MainActor func testGIFEncodingProducesAnimatedFile() throws {
        let frame = makeSolidCGImage(color: .red)
        let frames = Array(repeating: frame, count: 8)
        let data = try encodeGIFForTesting(frames: frames, frameDuration: 0.1)

        let source = CGImageSourceCreateWithData(data as CFData, nil)
        XCTAssertNotNil(source)
        XCTAssertEqual(CGImageSourceGetCount(source!), frames.count)

        let properties = CGImageSourceCopyPropertiesAtIndex(source!, 0, nil) as? [CFString: Any]
        let gifDictionary = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = gifDictionary?[kCGImagePropertyGIFDelayTime] as? Double
        XCTAssertEqual(delay ?? 0, 0.1, accuracy: 0.02)
    }

    @MainActor func testPNGEncodingScalesToMaxDimensionAndKeepsAlpha() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        }
        let data = try encodePNGForTesting(image: image)
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let longest = max(cg.width, cg.height)
        XCTAssertLessThanOrEqual(longest, Int(WatchCustomThemePolicy.maximumStaticImageDimension))
        XCTAssertTrue(cg.alphaInfo != .none)
    }

    // MARK: - Helpers

    @MainActor func testAsyncPipelineEncodesStaticAndAnimatedInputs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchThemeAsync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let frame = makeSolidCGImage(color: .red)
        let inputs = [
            WatchThemePickedMedia(kind: .staticImage, image: UIImage(cgImage: frame), frames: [], frameDuration: 0, removeBackground: false),
            WatchThemePickedMedia(kind: .animated, image: nil, frames: [frame, frame], frameDuration: 0.1, removeBackground: false)
        ]
        for input in inputs {
            let metadata = try await WatchThemeMediaPipeline.process(
                media: input, slot: .normal, themeDirectory: directory
            )
            let fileURL = directory.appendingPathComponent("normal.\(metadata.fileExtension)")
            let data = try Data(contentsOf: fileURL)
            XCTAssertEqual(metadata.fileSize, data.count)
            XCTAssertEqual(metadata.isAnimated, input.kind == .animated)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetCount(source), input.kind == .animated ? 2 : 1)
        }
    }

    @MainActor private func makeSolidCGImage(color: UIColor, size: CGSize = CGSize(width: 64, height: 64)) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.cgImage!
    }

    /// WatchThemeMediaPipeline.encodeGIF 是 private；这里走公开入口的等价路径（同参数写入临时目录）。
    @MainActor private func encodeGIFForTesting(frames: [CGImage], frameDuration: Double) throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchCustomThemeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let media = WatchThemePickedMedia(
            kind: .animated,
            image: nil,
            frames: frames,
            frameDuration: frameDuration,
            removeBackground: false
        )
        _ = try WatchThemeMediaPipeline.processForTesting(
            media: media,
            slot: .normal,
            themeDirectory: directory
        )
        let url = directory.appendingPathComponent("\(WatchThemeSlot.normal.rawValue).gif")
        return try Data(contentsOf: url)
    }

    @MainActor private func encodePNGForTesting(image: UIImage) throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchCustomThemeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let media = WatchThemePickedMedia(
            kind: .staticImage,
            image: image,
            frames: [],
            frameDuration: 0,
            removeBackground: false
        )
        _ = try WatchThemeMediaPipeline.processForTesting(
            media: media,
            slot: .excellent,
            themeDirectory: directory
        )
        let url = directory.appendingPathComponent("\(WatchThemeSlot.excellent.rawValue).png")
        return try Data(contentsOf: url)
    }
}
