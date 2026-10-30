import XCTest
@testable import BioBalance

nonisolated final class DeepLinkStoreTests: XCTestCase {
    @MainActor func testHomeDeepLinkRoutesToHome() throws {
        let url = try XCTUnwrap(URL(string: "biobalance://home"))

        XCTAssertEqual(MianyuDeepLink(url: url), .home)
    }

    @MainActor func testHomeDeepLinkRejectsAdditionalPath() throws {
        let url = try XCTUnwrap(URL(string: "biobalance://home/unexpected"))

        XCTAssertNil(MianyuDeepLink(url: url))
    }
}
