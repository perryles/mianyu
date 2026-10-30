import XCTest
@testable import BioBalance

nonisolated final class ProfileSupportFlowTests: XCTestCase {
    @MainActor func testFAQDataSourceKeepsFigmaContentShape() {
        XCTAssertEqual(FAQDataSource.items.count, 23)
        XCTAssertEqual(FAQDataSource.featuredItems.count, 4)
        XCTAssertEqual(FAQDataSource.count(for: .stressRecovery), 4)
        XCTAssertEqual(FAQDataSource.count(for: .watchSync), 4)
        XCTAssertEqual(FAQDataSource.count(for: .sleep), 5)
        XCTAssertEqual(FAQDataSource.count(for: .dataPrivacy), 4)
        XCTAssertEqual(FAQDataSource.count(for: .accountOther), 6)
    }

    @MainActor func testFAQSearchMatchesQuestionAnswerAndSummary() {
        XCTAssertTrue(FAQDataSource.filteredItems(searchText: "HRV").contains { $0.id == "stress-hrv-basics" })
        XCTAssertTrue(FAQDataSource.filteredItems(searchText: "CloudKit").contains { $0.id == "icloud-sync" })
        XCTAssertTrue(FAQDataSource.filteredItems(searchText: "第三方设备").contains { $0.id == "other-watch" })
        XCTAssertTrue(FAQDataSource.filteredItems(searchText: "不存在的问题").isEmpty)
    }

    @MainActor func testFeedbackDraftUsesMianyuBrandAndKeepsAttachments() async throws {
        let attachment = FeedbackAttachment(data: Data([0x01]), mimeType: "image/jpeg", fileName: "screen.jpg")
        let request = FeedbackRequest(type: .feature, message: "希望增加趋势说明", contact: "hello@example.com", attachments: [attachment])

        let draft = try await MailFeedbackService().prepareSubmission(request)

        XCTAssertEqual(draft.recipients, ["support@boundesu.com"])
        XCTAssertTrue(draft.subject.contains("眠屿"))
        XCTAssertFalse(draft.subject.contains("BalenWatch"))
        XCTAssertEqual(draft.attachments.count, 1)
    }

    @MainActor func testFeedbackRejectsMoreThanFiveAttachments() async {
        let attachments = (0..<6).map {
            FeedbackAttachment(data: Data([UInt8($0)]), mimeType: "image/jpeg", fileName: "screen-\($0).jpg")
        }
        let request = FeedbackRequest(type: .issue, message: "问题描述", contact: "", attachments: attachments)

        do {
            _ = try await MailFeedbackService().prepareSubmission(request)
            XCTFail("Expected attachment limit validation")
        } catch FeedbackServiceError.tooManyAttachments {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor func testCooperationTypePrefillsMatchingIdentity() {
        XCTAssertEqual(CooperationApplication(cooperationType: .content).identity, .creator)
        XCTAssertEqual(CooperationApplication(cooperationType: .brand).identity, .brand)
        XCTAssertEqual(CooperationApplication(cooperationType: .community).identity, .community)
    }

    @MainActor func testCooperationDraftIsCreatedOnlyAfterFormValidation() async throws {
        var application = CooperationApplication(cooperationType: .brand)
        application.name = "眠屿伙伴"
        application.organization = "示例品牌"
        application.contact = "partner@example.com"
        application.idea = "共同设计用户优先的联名体验"

        let draft = try await MailCooperationService().prepareSubmission(application)

        XCTAssertEqual(draft.recipients, ["support@boundesu.com"])
        XCTAssertTrue(draft.subject.contains("品牌联名"))
        XCTAssertFalse(draft.subject.contains("BalenWatch"))
    }
}
