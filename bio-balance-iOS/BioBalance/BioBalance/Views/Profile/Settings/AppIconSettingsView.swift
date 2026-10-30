/// AppIconSettingsView 由设置页图标入口调用，作为「应用图标」切换页。
/// 负责展示图标选项预览并执行切换，不影响健康或账号数据。

import SwiftUI
import UIKit

/// 允许用户切换应用图标，不修改任何健康数据或账户数据。
struct AppIconSettingsView: View {
    @State private var selectedIconName: String?
    @State private var isUpdating = false
    @State private var errorMessage: String?

    private let icons: [AppIconChoice] = [
        .init(name: nil, title: "经典", accessibilityLabel: "经典图标", previewAssetName: "ClassicAppIconPreview"),
        .init(name: "AppIconBalance", title: "活力", accessibilityLabel: "活力图标", previewAssetName: "BalanceAppIconPreview")
    ]

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("选择你喜欢的桌面图标。切换时，iOS 会显示一次系统确认提示。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(icons) { icon in
                            iconButton(icon)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("应用图标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .disabled(isUpdating)
        .overlay {
            if isUpdating {
                ProgressView("正在切换…")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("无法切换图标", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "请稍后重试。"))
        }
        .onAppear {
            selectedIconName = UIApplication.shared.alternateIconName
        }
    }

    private func iconButton(_ icon: AppIconChoice) -> some View {
        let isSelected = selectedIconName == icon.name

        return Button {
            changeIcon(to: icon.name)
        } label: {
            VStack(spacing: 12) {
                Image(icon.previewAssetName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                HStack(spacing: 6) {
                    Text(icon.title)
                        .font(.headline)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Colors.mintGreen)
                    }
                }
                .foregroundStyle(.primary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? Theme.Colors.mintGreen : .clear, lineWidth: 2)
                    }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(isSelected)
    }

    private func changeIcon(to name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = String(localized: "当前设备不支持切换应用图标。")
            return
        }

        isUpdating = true
        UIApplication.shared.setAlternateIconName(name) { error in
            Task { @MainActor in
                isUpdating = false
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    selectedIconName = UIApplication.shared.alternateIconName
                }
            }
        }
    }
}

private struct AppIconChoice: Identifiable {
    var id: String { name ?? "primary" }
    let name: String?
    let title: LocalizedStringKey
    let accessibilityLabel: LocalizedStringKey
    let previewAssetName: String
}
