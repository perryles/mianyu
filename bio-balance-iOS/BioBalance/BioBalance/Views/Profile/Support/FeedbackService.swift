import Foundation

enum FeedbackType: String, CaseIterable, Identifiable {
    case issue
    case feature
    case accountData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .issue: String(localized: "问题反馈")
        case .feature: String(localized: "功能建议")
        case .accountData: String(localized: "账号数据")
        }
    }
}

struct FeedbackAttachment: Identifiable, Hashable {
    let id: UUID
    let data: Data
    let mimeType: String
    let fileName: String

    init(id: UUID = UUID(), data: Data, mimeType: String, fileName: String) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
    }
}

struct FeedbackRequest {
    let type: FeedbackType
    let message: String
    let contact: String
    let attachments: [FeedbackAttachment]
}

enum FeedbackServiceError: LocalizedError {
    case emptyMessage
    case messageTooLong
    case tooManyAttachments

    var errorDescription: String? {
        switch self {
        case .emptyMessage: String(localized: "请先填写问题描述。")
        case .messageTooLong: String(localized: "问题描述不能超过 1000 个字符。")
        case .tooManyAttachments: String(localized: "最多只能添加 5 张图片。")
        }
    }
}

protocol FeedbackService {
    func prepareSubmission(_ request: FeedbackRequest) async throws -> MailDraft
}

struct MailFeedbackService: FeedbackService {
    func prepareSubmission(_ request: FeedbackRequest) async throws -> MailDraft {
        let message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw FeedbackServiceError.emptyMessage }
        guard message.count <= 1000 else { throw FeedbackServiceError.messageTooLong }
        guard request.attachments.count <= 5 else { throw FeedbackServiceError.tooManyAttachments }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let contact = request.contact.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = """
        反馈类型：\(request.type.title)
        联系方式：\(contact.isEmpty ? "未填写" : contact)

        \(message)

        ---
        眠屿 \(version)
        """
        let attachments = request.attachments.map {
            MailAttachment(data: $0.data, mimeType: $0.mimeType, fileName: $0.fileName)
        }
        return MailDraft(
            recipients: [ProfileExternalLinks.emailAddress],
            subject: "眠屿 · \(request.type.title)",
            body: body,
            attachments: attachments
        )
    }
}
