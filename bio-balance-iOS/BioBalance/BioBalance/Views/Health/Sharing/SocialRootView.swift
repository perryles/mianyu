/// SocialRootView 由健康首页社交入口调用，作为「好友」模块根页面。
/// 负责管理邀请流程、共享管理入口与好友详情导航；视觉呈现由 SocialHealthDashboardView 完成。

import SwiftUI
import UIKit

struct SocialRootView: View {
    @State private var viewModel = SocialViewModel()
    let onBack: (() -> Void)?
    @State private var selectedFriend: FriendHealthProfile?
    @State private var outgoingShareToRemove: OutgoingShareProfile?
    @State private var confirmingStopSharing = false
    @State private var showingCountdownManager = false
    @State private var showingTodoManager = false
    @State private var activitySource: UIActivityItemSource?
    @State private var pendingActivitySource: UIActivityItemSource?

    var body: some View {
        SocialHealthDashboardView(
            viewModel: viewModel,
            onInvite: startAddFriendFlow,
            onRefresh: viewModel.refreshSharing,
            onManageTodos: { showingTodoManager = true },
            onManageCountdowns: { showingCountdownManager = true },
            onStopSharing: { confirmingStopSharing = true },
            onSelectFriend: { selectedFriend = $0 },
            onRemoveOutgoingShare: { outgoingShareToRemove = $0 }
        )
        .healthDetailNavigation(title: HealthPageName.friends)
        .toolbar {
            if let onBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onBack()
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadData()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.sharingState.inviteFlowState == .confirming },
                set: { if !$0 { viewModel.introInviteSheetWillDismiss() } }
            ),
            onDismiss: {
                viewModel.introInviteSheetDidDismiss()
            }
        ) {
            InviteFriendIntroSheet(
                permissionState: viewModel.sharingState.myStatus.permissionState,
                isAuthorizing: viewModel.isAuthorizingInvite,
                authorizationMessage: viewModel.inviteAuthorizationMessage,
                onConfirm: viewModel.confirmInviteFlow,
                onCancel: viewModel.cancelInviteFlow
            )
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(item: $viewModel.activeShareSheet, onDismiss: {
            finishInviteConfiguration()
        }) { payload in
            CloudKitSharingSheet(
                payload: payload,
                onSaved: viewModel.inviteShareDidPrepare,
                onFailed: viewModel.inviteShareDidFail,
                onStoppedSharing: viewModel.inviteShareDidStopSharing,
                onSavedShareSource: { source in
                    pendingActivitySource = source
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { activitySource != nil },
            set: { if !$0 { activitySource = nil } }
        )) {
            if let activitySource {
                UIActivityViewControllerWrapper(source: activitySource) { completed, error in
                    self.activitySource = nil
                    viewModel.inviteDeliveryDidFinish(completed: completed, error: error)
                }
            }
        }
        .navigationDestination(item: $selectedFriend) { friend in
                SocialFriendDetailView(
                    friend: friend,
                    onRemove: {
                        viewModel.removeFriend(friend)
                    }
                )
                .toolbar(.hidden, for: .tabBar)
        }
        .sheet(isPresented: $showingCountdownManager) {
            NavigationStack {
                CountdownManagerView()
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingTodoManager) {
            NavigationStack {
                SharedTodoManagerView()
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .alert("共享提醒", isPresented: Binding(
            get: { viewModel.sharingState.errorMessage != nil },
            set: { if !$0 { viewModel.clearSharingError() } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(viewModel.sharingState.errorMessage ?? "")
        }
        .alert("停止我的共享？", isPresented: $confirmingStopSharing) {
            Button("取消", role: .cancel) { }
            Button("停止共享", role: .destructive) {
                viewModel.stopSharing()
            }
        } message: {
            Text("停止后，对方将无法继续看到你的健康摘要更新。")
        }
        .confirmationDialog(
            outgoingShareToRemove?.relationshipState == .pendingOutgoingInvite ? "撤回这条邀请？" : "停止向这位好友共享？",
            isPresented: Binding(
                get: { outgoingShareToRemove != nil },
                set: { if !$0 { outgoingShareToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let profile = outgoingShareToRemove {
                Button(
                    profile.relationshipState == .pendingOutgoingInvite ? "撤回邀请" : "停止共享",
                    role: .destructive
                ) {
                    outgoingShareToRemove = nil
                    viewModel.removeOutgoingShare(profile)
                }
            }
            Button("取消", role: .cancel) {
                outgoingShareToRemove = nil
            }
        } message: {
            Text("此操作只撤销你发出的共享；不会删除本机健康数据。")
        }
        .onChange(of: viewModel.sharingState.postAcceptNavigationTarget?.id, initial: true) { _, _ in
            if let target = viewModel.consumePostAcceptNavigationTarget() {
                selectedFriend = target
            }
        }
    }

    private func startAddFriendFlow() {
        viewModel.beginInviteFlow()
    }

    private func finishInviteConfiguration() {
        let source = pendingActivitySource
        pendingActivitySource = nil
        viewModel.inviteConfigurationSheetDismissed(willPresentShareComposer: source != nil)
        guard let source else { return }
        DispatchQueue.main.async {
            activitySource = source
        }
    }
}

private struct UIActivityViewControllerWrapper: UIViewControllerRepresentable {
    let source: UIActivityItemSource
    let onComplete: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            onComplete(completed, error)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        SocialRootView(onBack: nil)
    }
}
