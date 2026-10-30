/// CloudKitSharingSheet 由社交共享页调用，作为「CloudKit 共享」面板。
/// 负责封装 UICloudSharingController，处理共享邀请的保存、失败和停止。

import CloudKit
import SwiftUI
import UIKit

struct CloudKitSharingSheet: UIViewControllerRepresentable {
    let payload: CloudKitShareInvitePayload
    let onSaved: () -> Void
    let onFailed: (Error) -> Void
    let onStoppedSharing: () -> Void
    let onSavedShareSource: (any UIActivityItemSource) -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        // share URL 属于访问凭据，不得写入控制台或持久日志。
        print("[社交共享] 创建系统分享面板 share=\(payload.share.recordID.recordName) participants=\(payload.share.participants.count)")
        let controller = UICloudSharingController(share: payload.share, container: payload.container)
        controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSaved: onSaved,
            onFailed: onFailed,
            onStoppedSharing: onStoppedSharing,
            onSavedShareSource: onSavedShareSource
        )
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onSaved: () -> Void
        let onFailed: (Error) -> Void
        let onStoppedSharing: () -> Void
        let onSavedShareSource: (any UIActivityItemSource) -> Void

        init(
            onSaved: @escaping () -> Void,
            onFailed: @escaping (Error) -> Void,
            onStoppedSharing: @escaping () -> Void,
            onSavedShareSource: @escaping (any UIActivityItemSource) -> Void
        ) {
            self.onSaved = onSaved
            self.onFailed = onFailed
            self.onStoppedSharing = onStoppedSharing
            self.onSavedShareSource = onSavedShareSource
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            if let ckError = error as? CKError {
                print("[社交共享] 保存共享失败 ckCode=\(ckError.code.rawValue) codeName=\(ckError.code) description=\(ckError.localizedDescription)")
            } else {
                print("[社交共享] 保存共享失败 error=\(error.localizedDescription)")
            }
            onFailed(error)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "好友健康摘要与共享待办"
        }

        func itemType(for csc: UICloudSharingController) -> String? {
            "com.boundesu.BioBalance.health-share"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            print("[社交共享] 共享已保存 participants=\(csc.share?.participants.count ?? 0)")
            onSavedShareSource(csc.activityItemSource())
            onSaved()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            print("[社交共享] 用户停止了共享")
            onStoppedSharing()
        }
    }
}
