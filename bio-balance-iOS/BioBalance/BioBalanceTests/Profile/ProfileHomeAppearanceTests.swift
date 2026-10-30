import XCTest

nonisolated final class ProfileHomeAppearanceTests: XCTestCase {
    @MainActor func testProfileHomeUsesClearIconsOnSoftColorTiles() throws {
        let source = try sourceText(
            relativePath: "BioBalance/Views/Profile/Home/ProfileView.swift"
        )

        XCTAssertTrue(source.contains("Color(hex: \"3F7F6C\")"))
        XCTAssertTrue(source.contains("Color(hex: \"527897\")"))
        XCTAssertTrue(source.contains("Color(hex: \"917041\")"))
        XCTAssertTrue(source.contains("Color(hex: \"75648E\")"))
        XCTAssertTrue(source.contains(".fill(tint.opacity(0.09))"))
        XCTAssertFalse(source.contains("Color(hex: \"FFB340\")"))
        XCTAssertFalse(source.contains("Color(hex: \"35C97A\")"))
        XCTAssertFalse(source.contains("Color(hex: \"7D8BFF\")"))
        XCTAssertFalse(source.contains("Color(hex: \"B78CFF\")"))
    }

    @MainActor func testProfileHeatmapCapsItsStrongestFillBelowFullStrength() throws {
        let source = try sourceText(
            relativePath: "BioBalance/Views/Profile/Home/ProfileHeatmapCardView.swift"
        )

        XCTAssertTrue(source.contains("case 85...: return vitalityFill.opacity(0.72)"))
        XCTAssertFalse(source.contains("case 85...: return Theme.Colors.mintGreen.opacity(0.9)"))
    }

    @MainActor private func sourceText(relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
