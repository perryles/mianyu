import MessageUI
import SwiftUI

struct MailAttachment: Identifiable, Hashable {
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

struct MailDraft: Identifiable {
    let id = UUID()
    let recipients: [String]
    let subject: String
    let body: String
    let attachments: [MailAttachment]

    var mailtoURL: URL? {
        guard let recipient = recipients.first else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

enum MailComposerResult {
    case sent
    case saved
    case cancelled
    case failed(Error?)
}

struct MailComposer: UIViewControllerRepresentable {
    let draft: MailDraft
    let completion: (MailComposerResult) -> Void

    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(draft.recipients)
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        for attachment in draft.attachments {
            controller.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: (MailComposerResult) -> Void

        init(completion: @escaping (MailComposerResult) -> Void) {
            self.completion = completion
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                switch result {
                case .sent: self.completion(.sent)
                case .saved: self.completion(.saved)
                case .cancelled: self.completion(.cancelled)
                case .failed: self.completion(.failed(error))
                @unknown default: self.completion(.failed(error))
                }
            }
        }
    }
}

@MainActor
enum MailFallback {
    static func copySupportAddress() {
        UIPasteboard.general.string = ProfileExternalLinks.emailAddress
    }
}
