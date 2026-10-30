/// WatchPromoView 作为帮助支持模块的支撑类型，负责定义表盘宣传数据。
/// 负责描述表盘功能特性列表与表盘模板预览结构。

import SwiftUI

// MARK: - 数据模型
/// 表盘Feature结构体 作为帮助支持模块里的辅助类型。
/// 负责帮助支持与 FAQ 展示。
struct WatchFaceFeature: Identifiable {
    let id = UUID()
    let iconName: String
    let title: String
}

/// 表盘Template结构体 作为帮助支持模块里的辅助类型。
/// 负责帮助支持与 FAQ 展示。
struct WatchFaceTemplate: Identifiable {
    let kind: OfficialWatchFaceKind
    let previewImageName: String
    let subtitle: String
    let features: [WatchFaceFeature]

    var id: OfficialWatchFaceKind { kind }
    var title: String { kind.displayName }
}

// MARK: - 主视图
/// 手表宣传视图 由上级页面或路由调用，作为帮助支持模块里的界面或内容组件。
/// 负责帮助支持与 FAQ 展示。
struct WatchPromoView: View {
    @State private var showTutorial = false
    @State private var watchFaceLaunchState: WatchFaceLaunchState = .idle
    @State private var watchFaceResourceStatuses: [OfficialWatchFaceKind: WatchFaceResourceStatus] = [:]
    @State private var activeWatchFaceKind: OfficialWatchFaceKind = .recoveryOverview
    
    let templates: [WatchFaceTemplate] = [
        WatchFaceTemplate(
            kind: .recoveryOverview,
            previewImageName: "BalenWatch-RecoveryOverview-preview",
            subtitle: "用一张表盘把恢复、睡眠、步数和习惯入口放到最顺手的位置。",
            features: [
            WatchFaceFeature(iconName: "face.smiling", title: "表情"),
            WatchFaceFeature(iconName: "bed.double.fill", title: "睡眠"),
            WatchFaceFeature(iconName: "figure.walk", title: "步数"),
            WatchFaceFeature(iconName: "sun.max.fill", title: "晒太阳")
        ]),
        WatchFaceTemplate(
            kind: .dualModule,
            previewImageName: "BalenWatch-DualModule-preview",
            subtitle: "保留更清爽的主视图，同时把喝水和咖啡因这类高频习惯入口放上表盘。",
            features: [
            WatchFaceFeature(iconName: "drop.fill", title: "喝水"),
            WatchFaceFeature(iconName: "cup.and.saucer.fill", title: "咖啡因")
        ])
    ]

    private var selectedWatchFaceTemplate: WatchFaceTemplate {
        templates.first(where: { $0.kind == activeWatchFaceKind }) ?? templates[0]
    }

    private func isResourceAvailable(for kind: OfficialWatchFaceKind) -> Bool {
        watchFaceResourceStatuses[kind]?.isAvailable ?? false
    }

    private var activeWatchFaceResourceAvailable: Bool {
        isResourceAvailable(for: activeWatchFaceKind)
    }

    private var watchFaceAvailabilityLabel: String {
        activeWatchFaceResourceAvailable ? "可立即添加" : "待打包资源"
    }

    private var launchStateTitle: String {
        switch watchFaceLaunchState {
        case .idle:
            return String(localized: "\(selectedWatchFaceTemplate.title) 已准备好")
        case .launching:
            return String(localized: "正在打开官方流程")
        case .openedOfficialFlow:
            return String(localized: "已打开官方添加流程")
        case .failed(.notPaired):
            return String(localized: "还没有配对 Apple Watch")
        case .failed(.watchAppNotInstalled):
            return String(localized: "Watch App 尚未安装")
        case .failed(.resourceMissing):
            return String(localized: "待打包表盘资源")
        case .failed(.userCancelled):
            return String(localized: "本次添加已取消")
        case .failed(.watchUnavailable):
            return String(localized: "当前设备不可用")
        case .failed(.systemFailure):
            return String(localized: "表盘添加未完成")
        }
    }

    private var launchStateDetail: String {
        switch watchFaceLaunchState {
        case .idle:
            return String(localized: "点击“添加表盘”后，会跳转到苹果官方 Watch 流程继续确认。")
        case .launching:
            return String(localized: "正在检查配对状态、Watch App 安装情况和表盘资源。")
        case .openedOfficialFlow:
            return String(localized: "请在 Apple 官方流程中完成下一步，返回后这里会继续保留你的默认组件模板。")
        case .failed(let error):
            return error.errorDescription ?? "暂时无法打开表盘添加流程。"
        }
    }

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()
            ambientBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    WatchPromoHeroCard(showTutorial: $showTutorial)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    officialWatchFaceCard
                        .padding(.horizontal, 16)

                    WatchPromoQuickStepsCard(showTutorial: $showTutorial)
                        .padding(.horizontal, 16)

                    WatchPromoTemplateList(
                        templates: templates,
                        activeKind: activeWatchFaceKind,
                        isResourceAvailable: isResourceAvailable(for:),
                        launchAction: launchWatchFace
                    )
                    .padding(.horizontal, 16)

                    Text("当前页面仅展示已接入 App 的真实表盘资源。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 18)
                }
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("Watch 表盘组件")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTutorial) {
            WatchPromoTutorialSheet()
        }
        .onAppear {
            refreshWatchFaceResourceStatus()
        }
    }

    private var ambientBackground: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Theme.Colors.mintGreen.opacity(0.14))
                    .frame(width: 200, height: 200)
                    .blur(radius: 34)
                    .offset(x: -46, y: -34)
                Spacer()
                Circle()
                    .fill(Color(hex: "DFF1FF").opacity(0.72))
                    .frame(width: 170, height: 170)
                    .blur(radius: 30)
                    .offset(x: 28, y: -18)
            }
            Spacer()
        }
        .ignoresSafeArea()
    }

    private var launchStatusSymbolName: String {
        switch watchFaceLaunchState {
        case .idle:
            return "sparkles"
        case .launching:
            return "arrow.up.right.circle"
        case .openedOfficialFlow:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var launchStatusTint: Color {
        switch watchFaceLaunchState {
        case .idle:
            return Theme.Colors.mintGreen
        case .launching:
            return Color(hex: "8FD7FF")
        case .openedOfficialFlow:
            return Theme.Colors.mintGreen
        case .failed:
            return Color(hex: "FFB340")
        }
    }

    private func launchWatchFace(_ kind: OfficialWatchFaceKind) {
        activeWatchFaceKind = kind
        refreshWatchFaceResourceStatus()
        guard isResourceAvailable(for: kind) else {
            watchFaceLaunchState = .failed(.resourceMissing)
            return
        }
        watchFaceLaunchState = .launching
        Task {
            let result = await WatchFaceLibraryManager.shared.addFace(kind)
            await MainActor.run {
                refreshWatchFaceResourceStatus()
                watchFaceLaunchState = result
            }
        }
    }

    private func refreshWatchFaceResourceStatus() {
        var statuses: [OfficialWatchFaceKind: WatchFaceResourceStatus] = [:]
        for kind in OfficialWatchFaceKind.allCases {
            statuses[kind] = WatchFaceLibraryManager.shared.resourceStatus(for: kind)
        }
        watchFaceResourceStatuses = statuses
        if !activeWatchFaceResourceAvailable {
            watchFaceLaunchState = .failed(.resourceMissing)
        } else if watchFaceLaunchState == .failed(.resourceMissing) {
            watchFaceLaunchState = .idle
        }
    }

    private var officialWatchFaceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedWatchFaceTemplate.title)
                        .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent)
                    Text(selectedWatchFaceTemplate.subtitle)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(watchFaceAvailabilityLabel)
                    .font(.appSystem(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(hex: "0E1D32"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
            }

            HStack(spacing: 16) {
                Spacer(minLength: 0)
                WatchPromoWatchMock(imageName: selectedWatchFaceTemplate.previewImageName, size: CGSize(width: 168, height: 198))
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ForEach(templates) { template in
                    Button {
                        activeWatchFaceKind = template.kind
                        refreshWatchFaceResourceStatus()
                    } label: {
                        Text(template.title)
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(activeWatchFaceKind == template.kind ? Color(hex: "10233F") : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                activeWatchFaceKind == template.kind
                                    ? Color.white
                                    : Color.white.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: launchStatusSymbolName)
                        .foregroundColor(launchStatusTint)
                    Text(launchStateTitle)
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent)
                }

                Text(launchStateDetail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Theme.Colors.surface.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                launchWatchFace(activeWatchFaceKind)
            } label: {
                HStack(spacing: 8) {
                    if watchFaceLaunchState == .launching {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color(hex: "10233F"))
                    } else {
                        Image(systemName: "applewatch")
                    }
                    Text(watchFaceLaunchState == .launching ? "正在打开..." : (activeWatchFaceResourceAvailable ? "添加表盘" : "等待表盘资源"))
                }
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [Color.white, Color(hex: "DDF7FF")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(watchFaceLaunchState == .launching || !activeWatchFaceResourceAvailable)

            Text(
                activeWatchFaceResourceAvailable
                    ? "将打开 Watch 官方流程完成下一步。当前已接入的 2 款真实表盘都可以从这里发起添加。"
                    : "当前构建未发现 \(selectedWatchFaceTemplate.kind.expectedPath)，需把真实表盘资源加入 眠屿 主 App target 后才能发起官方流程。"
            )
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.onAccent.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "102744"),
                    Color(hex: "173A5F"),
                    Color(hex: "112941")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 12)
    }
}

private struct WatchPromoStepRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundColor(Theme.Colors.onAccent)
                .frame(width: 22, height: 22)
                .background(Theme.Colors.mintGreen)
                .clipShape(Circle())
            
            Text(text)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
        }
    }
}

private struct WatchPromoHeroCard: View {
    @Binding var showTutorial: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "0E1330"),
                            Color(hex: "2A2546"),
                            Color(hex: "15152B")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 210, height: 210)
                    .blur(radius: 1)
                    .offset(x: 110, y: -90)

                Circle()
                    .fill(Color(hex: "007F79").opacity(0.18))
                    .frame(width: 180, height: 180)
                    .blur(radius: 2)
                    .offset(x: -120, y: 110)

                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 260, height: 140)
                    .blur(radius: 0.5)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -70, y: -40)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("把恢复状态放上表盘")
                        .font(.appSystem(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent)

                    Text("把 HRV、睡眠、压力和习惯入口放进最顺手的位置，抬腕就能看到今天最关键的信号。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    heroPill(title: "已接入", value: "2 款真实表盘", tint: Theme.Colors.mintGreen)
                    heroPill(title: "方式", value: "官方添加", tint: Color(hex: "8FD7FF"))
                }

                HStack {
                    Spacer()
                    WatchPromoWatchMock(imageName: "BalenWatch-RecoveryOverview-preview", size: CGSize(width: 168, height: 198))
                    Spacer()
                }

                Text("iPhone 发起添加 → Watch 官方流程继续")
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent.opacity(0.86))

                Button(action: {
                    showTutorial = true
                }) {
                    Text("详细教程")
                        .font(.appSystem(size: 16, weight: .semibold))
                        .foregroundColor(Theme.Colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            LinearGradient(
                                colors: [Theme.Colors.mintGreen, Color(hex: "6FD2FF")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 12)
    }

    private func heroPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.onAccent.opacity(0.7))
            Text(value)
                .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.onAccent)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WatchPromoQuickStepsCard: View {
    @Binding var showTutorial: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("使用说明")
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("iPhone 发起")
                    .font(.appSystem(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(hex: "7D8BFF"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "7D8BFF").opacity(0.12), in: Capsule())
            }

            stepRow(index: "01", title: "先选 1 款真实表盘", detail: "当前可选恢复概览和双模块，页面只展示这 2 款已经接入 App 的资源。")
            stepRow(index: "02", title: "进入 Watch 官方流程", detail: "系统会接管后续的添加或确认步骤，你只需要继续按提示完成。")
            stepRow(index: "03", title: "回到手表调整默认模板", detail: "如需切换综合状态、压力、恢复或心率，可在 Watch 端表盘设置里继续改。")

            Button {
                showTutorial = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                    Text("查看完整教程")
                }
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.accentBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 10)
    }

    private func stepRow(index: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(index)
                .font(.appSystem(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(Color(hex: "7D8BFF"))
                .frame(width: 30, height: 30)
                .background(Color(hex: "7D8BFF").opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WatchPromoTemplateList: View {
    let templates: [WatchFaceTemplate]
    let activeKind: OfficialWatchFaceKind
    let isResourceAvailable: (OfficialWatchFaceKind) -> Bool
    let launchAction: (OfficialWatchFaceKind) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                WatchPromoTemplateRow(
                    template: template,
                    index: index + 1,
                    isActive: template.kind == activeKind,
                    isAvailable: isResourceAvailable(template.kind),
                    launchAction: launchAction
                )
                    .padding(.vertical, 22)
                    .padding(.horizontal, 18)

                if index != templates.count - 1 {
                    Divider()
                        .background(Theme.Colors.lightGray)
                        .padding(.leading, 18)
                }
            }
        }
        .background(Theme.Colors.surface.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 10)
    }
}

private struct WatchPromoTemplateRow: View {
    let template: WatchFaceTemplate
    let index: Int
    let isActive: Bool
    let isAvailable: Bool
    let launchAction: (OfficialWatchFaceKind) -> Void

    var body: some View {
        VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 18) {
                WatchPromoWatchMock(imageName: template.previewImageName, size: CGSize(width: 126, height: 148))

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text(String(format: "%02d", index))
                            .font(.appSystem(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(hex: "7D8BFF"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "7D8BFF").opacity(0.12), in: Capsule())

                        Text(template.title)
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    Text(template.subtitle)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(template.features) { feature in
                        HStack(spacing: 10) {
                            featureTag(for: feature)
                            Text(feature.title)
                                .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            HStack {
                Spacer()
                if isActive {
                    Text("当前选中")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.accentBlue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Theme.Colors.accentBlue.opacity(0.10),
                            in: Capsule()
                        )
                }

                Button {
                    launchAction(template.kind)
                } label: {
                    Text(isAvailable ? "添加表盘" : "资源缺失")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(isAvailable ? .white : Theme.Colors.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            isAvailable ? Theme.Colors.mintGreen : Color(hex: "E9EEF5"),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable)
                Spacer()
            }
        }
    }

    private func featureTag(for feature: WatchFaceFeature) -> some View {
        Image(systemName: feature.iconName)
            .font(.appSystem(size: 11, weight: .bold))
            .foregroundColor(Theme.Colors.mintGreen)
            .frame(width: 26, height: 26)
            .background(Theme.Colors.mintGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WatchPromoWatchMock: View {
    let imageName: String
    let size: CGSize

    private var previewUIImage: UIImage? {
        if let assetImage = UIImage(named: imageName) {
            return assetImage
        }

        guard let url = Bundle.main.url(
            forResource: imageName,
            withExtension: "png",
            subdirectory: "WatchFaces/Previews"
        ) else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.width * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.92), Color(white: 0.70)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 6)

            RoundedRectangle(cornerRadius: size.width * 0.24, style: .continuous)
                .fill(Color.black)
                .frame(width: size.width - 8, height: size.height - 8)
                .overlay(
                    Group {
                        if let previewUIImage {
                            Image(uiImage: previewUIImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.black
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: size.width * 0.24, style: .continuous))
                )

            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.92), Color(white: 0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 6, height: size.height * 0.14)
                .offset(x: size.width * 0.52, y: -size.height * 0.12)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.72))
                .frame(width: 4, height: size.height * 0.22)
                .offset(x: size.width * 0.51, y: size.height * 0.12)
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct WatchPromoTutorialSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("详细教程")
                        .font(.appSystem(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        WatchPromoStepRow(number: "1", text: "在 iPhone 的“Watch 表盘组件”页点击“添加表盘”。")
                        WatchPromoStepRow(number: "2", text: "系统会打开 Apple 官方 Watch 添加流程继续确认。")
                        WatchPromoStepRow(number: "3", text: "添加完成后，可在表盘编辑里为单个组件改模板。")
                        WatchPromoStepRow(number: "4", text: "如果想改默认组件模板，可打开 Watch 端左上角的表盘设置。")
                    }
                    .padding(16)
                    .background(Theme.Colors.surface.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 6)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("常见异常")
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text("1) 确认 iPhone 与 Apple Watch 已完成配对\n2) 确认 眠屿 Watch App 已安装在手表上\n3) 若当前版本提示资源缺失，说明恢复概览或双模块的真实 .watchface 文件还没有打包进 iPhone App")
                            .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .background(Theme.Colors.surface.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.Colors.pageBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("关闭")
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
            }
        }
    }
}

/// 手表宣传预览提供器 作为帮助支持模块里的预览辅助类型。
/// 负责帮助支持与 FAQ 展示。
struct WatchPromoView_Previews: PreviewProvider {
    static var previews: some View {
        WatchPromoView()
    }
}
