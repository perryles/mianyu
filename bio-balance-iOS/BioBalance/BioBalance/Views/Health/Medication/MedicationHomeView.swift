import SwiftUI

struct MedicationHomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var store: MedicationCenterStore
    @Binding var path: [MedicationRoute]
    let onClose: () -> Void
    @State private var showingTemporaryRecord = false
    @State private var showingAddPlan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader
                medicationOverview
                if let next = store.nextDose { nextDoseCard(next) }
                MedicationSectionHeader(title: "今天的计划", detail: "\(store.completedCount) / \(store.schedules.count) 完成")
                if store.schedules.isEmpty {
                    ContentUnavailableView("暂无用药计划", systemImage: "pills", description: Text("新增计划后会显示在这里。"))
                        .frame(maxWidth: .infinity).padding().background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    MedicationCard {
                        VStack(spacing: 0) {
                            ForEach(Array(store.schedules.enumerated()), id: \.element.id) { index, item in
                                MedicationRow(item: item) { path.append(.instruction(item.medicationID)) }
                                if index < store.schedules.count - 1 { Divider().padding(.leading, 96) }
                            }
                        }
                    }
                }
                medicationSymptomReviewEntry
                MedicationSectionHeader(title: "快速操作")
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 10),
                        count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
                    ),
                    spacing: 10
                ) {
                    quickAction("扫描处方", "doc.text.viewfinder", Theme.Colors.accentBlue) { path.append(.prescription) }
                    quickAction("临时记录", "plus", Theme.Colors.mintGreen) { showingTemporaryRecord = true }
                    quickAction("管理计划", "list.bullet", Theme.Colors.accentOrange) { path.append(.plan) }
                }
                MedicationCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Theme.Colors.mintGreen)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("按医嘱记录与提醒").font(.subheadline.bold())
                            Text("眠屿只帮助记录和提醒，不会替你调整剂量或用法。").font(.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Spacer(minLength: 4)
                        Image("ActionHeaderMascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 58, height: 58)
                            .accessibilityHidden(true)
                    }
                }
                Button { path.append(.plan) } label: {
                    HStack { VStack(alignment: .leading) { Text("查看全部用药计划").font(.subheadline.bold()); Text("\(store.schedules.count) 项计划").font(.caption).foregroundStyle(Theme.Colors.textTertiary) }; Spacer(); Image(systemName: "chevron.right") }
                        .foregroundStyle(Theme.Colors.textPrimary).padding().frame(minHeight: 58).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(HealthDetailPageBackground(
            topGlow: Color(hex: "C9DDF8"),
            lowerGlow: Color(hex: "E1E9FC")
        ))
        .sheet(isPresented: $showingTemporaryRecord) {
            MedicationLogSheet(draft: MedicationDraft())
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingAddPlan) {
            MedicationPlanSheet(draft: MedicationPlanDraft())
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 14) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .systemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回健康")

            VStack(alignment: .leading, spacing: 2) {
                Text("用药")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("管理今天的用药安排")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer(minLength: 4)

            Button { showingAddPlan = true } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.Colors.mintGreen)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .systemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新增用药计划")
        }
        .frame(minHeight: 64)
    }

    private var medicationOverview: some View {
        ModernReportMetricsPanel(
            title: String(localized: "用药概览"),
            metrics: [
                ModernReportMetric(
                    title: String(localized: "今日计划"),
                    value: String(localized: "\(store.schedules.count) 项"),
                    tint: Theme.Colors.accentBlue,
                    symbol: "pills.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "已完成"),
                    value: String(localized: "\(store.completedCount) 项"),
                    tint: Theme.Colors.mintGreen,
                    symbol: "checkmark.circle.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "待处理"),
                    value: String(localized: "\(store.schedules.count - store.completedCount) 项"),
                    tint: Theme.Colors.accentOrange,
                    symbol: "clock.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "下一次"),
                    value: store.nextDose?.time ?? String(localized: "暂无"),
                    tint: Color(hex: "8068FF"),
                    symbol: "alarm.fill"
                )
            ]
        )
    }

    private var medicationSymptomReviewEntry: some View {
        Button { path.append(.symptomReview) } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    reviewEntryIcon
                    reviewEntryCopy
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        reviewEntryIcon
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    reviewEntryCopy
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(Theme.Colors.mintGreen.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("14 天药症回看")
        .accessibilityHint("查看最近 14 天真实记录的汇总和时间重叠")
        .accessibilityIdentifier("medication.symptom-review.entry")
    }

    private var reviewEntryIcon: some View {
        Image(systemName: "calendar.badge.clock")
            .font(.title3.bold())
            .foregroundStyle(Theme.Colors.mintGreen)
            .frame(width: 44, height: 44)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    private var reviewEntryCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("14 天药症回看")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("基于本机记录即时汇总，不补齐未记录的日期。")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nextDoseCard(_ item: MedicationScheduleItem) -> some View {
        MedicationCard(tint: Theme.Colors.mintGreen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("下一次用药").font(.subheadline.bold()).foregroundStyle(Theme.Colors.mintGreen); Spacer(); BBStatusBadge(title: "15 分钟后", tint: Theme.Colors.mintGreen) }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 20) { nextDoseTime(item); nextDoseDescription(item) }
                    VStack(alignment: .leading, spacing: 8) { nextDoseTime(item); nextDoseDescription(item) }
                }
                Button("标记为已服用") { store.updateStatus(id: item.id, status: .taken) }
                    .font(.subheadline.bold()).foregroundStyle(Theme.Colors.mintGreen).frame(maxWidth: .infinity, minHeight: 44).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 15))
            }
        }
    }

    private func nextDoseTime(_ item: MedicationScheduleItem) -> some View {
        Text(item.time).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(Theme.Colors.textPrimary)
    }

    private func nextDoseDescription(_ item: MedicationScheduleItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(item.name) · \(item.dose)").font(.headline).lineLimit(2)
            Text("\(item.timing) · 提醒已开启").font(.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func quickAction(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            let content = VStack(alignment: .leading, spacing: 5) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 32, height: 32).background(color.opacity(0.1), in: Circle())
                Text(title).font(.caption.bold()).foregroundStyle(Theme.Colors.textPrimary)
                Text(quickActionSubtitle(title)).font(.caption2).foregroundStyle(Theme.Colors.textTertiary)
            }

            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .frame(width: 40, height: 40)
                        .background(color.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline).foregroundStyle(Theme.Colors.textPrimary)
                        Text(quickActionSubtitle(title)).font(.subheadline).foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
            } else {
                content
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(quickActionSubtitle(title))
    }

    private func quickActionSubtitle(_ title: String) -> String {
        switch title {
        case "扫描处方": return "从照片识别"
        case "临时记录": return "刚刚吃过一项"
        default: return "调整时间提醒"
        }
    }
}
