import XCTest
@testable import BioBalance

nonisolated final class ProfileBusinessContactCatalogTests: XCTestCase {
    @MainActor func testBusinessContactCatalogOnlyExposesEmailAndXiaohongshu() {
        XCTAssertEqual(ProfileBusinessContactChannel.allCases, [.email, .xiaohongshu])
    }
}
