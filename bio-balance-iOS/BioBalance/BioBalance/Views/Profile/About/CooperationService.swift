import Foundation

protocol CooperationService {
    func prepareSubmission(_ application: CooperationApplication) async throws -> MailDraft
}

struct MailCooperationService: CooperationService {
    func prepareSubmission(_ application: CooperationApplication) async throws -> MailDraft {
        let name = application.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let organization = application.organization.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = application.contact.trimmingCharacters(in: .whitespacesAndNewlines)
        let idea = application.idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CooperationServiceError.missingName }
        guard !contact.isEmpty else { throw CooperationServiceError.missingContact }
        guard !idea.isEmpty else { throw CooperationServiceError.missingIdea }

        let body = """
        合作类型：\(application.cooperationType.title)
        合作身份：\(application.identity.title)
        称呼：\(name)
        品牌 / 机构：\(organization.isEmpty ? "未填写" : organization)
        联系方式：\(contact)

        合作想法：
        \(idea)
        """
        return MailDraft(
            recipients: [ProfileExternalLinks.emailAddress],
            subject: "眠屿 · \(application.cooperationType.title)申请",
            body: body,
            attachments: []
        )
    }
}
