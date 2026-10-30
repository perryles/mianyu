/// ReproductiveHealthRecordView 作为生理健康快照的展示支撑。
/// 负责定义快照展示状态枚举（加载中/本地周期回退/已解析快照）并提供状态解析逻辑。

import CloudKit
import Foundation
import SwiftUI

enum ReproductiveHealthSnapshotPresentation: Equatable {
    case loading
    case localPeriodFallback
    case resolvedSnapshot

    static func resolve(
        hasLoadedSnapshot: Bool,
        hasLoadedPeriodSection: Bool,
        syncStatus: PregnancySyncStatus
    ) -> ReproductiveHealthSnapshotPresentation {
        if hasLoadedSnapshot {
            return .resolvedSnapshot
        }
        if hasLoadedPeriodSection {
            return .localPeriodFallback
        }
        if case .failed = syncStatus {
            return .localPeriodFallback
        }
        return .loading
    }
}

struct ReproductiveHealthRecordView: View {
    @Bindable var periodViewModel: PeriodViewModel
    @State private var pregnancyViewModel: PregnancyViewModel
    private let initialSection: ReproductiveHealthSection
    @State private var hasLoadedPeriodSection = false
    @State private var showingPregnancySetup = false
    @State private var didHandleInitialSection = false

    @MainActor
    init(
        periodViewModel: PeriodViewModel,
        initialSection: ReproductiveHealthSection = .defaultSection
    ) {
        self.periodViewModel = periodViewModel
        self.initialSection = initialSection
        _pregnancyViewModel = State(initialValue: PregnancyViewModel())
    }

    var body: some View {
        resolvedContent
            .healthDetailNavigation(title: HealthPageName.femaleHealth)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await loadInitialState()
            }
            .onChange(of: pregnancyViewModel.hasActivePregnancy) { wasActive, isActive in
                guard wasActive != isActive, !isActive else { return }
                hasLoadedPeriodSection = false
                loadPeriodSectionIfNeeded()
            }
            .sheet(isPresented: $showingPregnancySetup) {
                PregnancySettingsSheet(
                    profile: pregnancyViewModel.activeProfile,
                    viewModel: pregnancyViewModel
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSUbiquityIdentityDidChange)) { _ in
                handlePregnancyAccountChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                handlePregnancyAccountChange()
            }
    }

    @ViewBuilder
    private var resolvedContent: some View {
        switch ReproductiveHealthSnapshotPresentation.resolve(
            hasLoadedSnapshot: pregnancyViewModel.hasLoadedSnapshot,
            hasLoadedPeriodSection: hasLoadedPeriodSection,
            syncStatus: pregnancyViewModel.syncStatus
        ) {
        case .loading:
            pregnancyLoadingGate
        case .localPeriodFallback:
            localPeriodFallbackContent
        case .resolvedSnapshot:
            switch ReproductiveHealthSection.resolved(
                hasActivePregnancy: pregnancyViewModel.hasActivePregnancy
            ) {
            case .period:
                periodRecordContent
            case .pregnancy:
                PregnancyRecordView(
                    viewModel: pregnancyViewModel,
                    isEmbedded: true
                )
            }
        }
    }

    private var periodRecordContent: some View {
        VitalityPeriodRecordView(
            viewModel: periodViewModel,
            isEmbedded: true,
            reloadsOnAppear: false,
            onStartPregnancy: {
                showingPregnancySetup = true
            }
        )
    }

    private var localPeriodFallbackContent: some View {
        periodRecordContent
            .safeAreaInset(edge: .top, spacing: 0) {
                pregnancyCloudStatusBanner
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
    }

    private var pregnancyCloudStatusBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if pregnancyViewModel.syncStatus.isBusy {
                        ProgressView()
                            .tint(Color(hex: "42BE9B"))
                    } else {
                        Image(systemName: "icloud.slash.fill")
                            .foregroundColor(Color(hex: "C63F78"))
                    }
                }
                .font(.appSystem(size: 17, weight: .bold))
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(pregnancyCloudStatusTitle)
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "35383F"))
                    Text(pregnancyCloudStatusDetail)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if case .failed = pregnancyViewModel.syncStatus {
                Button {
                    Task { await loadInitialState() }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(
                            Color(hex: "42BE9B"),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("重试 iCloud 孕期记录")
            }
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white, lineWidth: 1)
        }
        .shadow(color: Color(hex: "8E7A92").opacity(0.08), radius: 12, x: 0, y: 6)
    }

    private var pregnancyCloudStatusTitle: String {
        pregnancyViewModel.syncStatus.isBusy
            ? "正在重新连接 iCloud"
            : "iCloud 孕期记录暂不可用"
    }

    private var pregnancyCloudStatusDetail: String {
        if case .failed(let message) = pregnancyViewModel.syncStatus {
            return String(localized: "\(message) 本地经期记录仍可正常使用。")
        }
        return String(localized: "本地经期记录仍可正常使用，连接恢复后会重新确认孕期状态。")
    }

    private var pregnancyLoadingGate: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "FCE8F4"),
                    Color(hex: "F8F7FA"),
                    Color(hex: "EEF7F4")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(Color(hex: "42BE9B"))
                    .scaleEffect(1.15)

                Text("正在读取周期健康记录")
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "535861"))
            }
            .frame(maxWidth: 320)
            .padding(24)
            .background(Theme.Colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: Color(hex: "8E7A92").opacity(0.08), radius: 14, x: 0, y: 8)
            .padding(.horizontal, 24)
        }
    }

    @MainActor
    private func loadInitialState() async {
        if !pregnancyViewModel.hasLoadedSnapshot {
            await pregnancyViewModel.load()
        }
        guard pregnancyViewModel.hasLoadedSnapshot else {
            loadPeriodFallbackIfNeeded()
            return
        }

        if !pregnancyViewModel.hasActivePregnancy {
            loadPeriodSectionIfNeeded()
        }

        if !didHandleInitialSection {
            didHandleInitialSection = true
            if initialSection == .pregnancy, !pregnancyViewModel.hasActivePregnancy {
                showingPregnancySetup = true
            }
        }
    }

    private func handlePregnancyAccountChange() {
        showingPregnancySetup = false
        Task {
            await pregnancyViewModel.handleICloudAccountChange()
            guard pregnancyViewModel.hasLoadedSnapshot else {
                loadPeriodFallbackIfNeeded()
                return
            }
            guard !pregnancyViewModel.hasActivePregnancy else { return }
            hasLoadedPeriodSection = false
            loadPeriodSectionIfNeeded()
        }
    }

    private func loadPeriodFallbackIfNeeded() {
        guard case .failed = pregnancyViewModel.syncStatus else { return }
        loadPeriodSectionIfNeeded()
    }

    private func loadPeriodSectionIfNeeded() {
        guard !hasLoadedPeriodSection else { return }
        hasLoadedPeriodSection = true
        periodViewModel.reload(days: 90)
        periodViewModel.selectLog(date: periodViewModel.selectedLogDate)
    }
}
