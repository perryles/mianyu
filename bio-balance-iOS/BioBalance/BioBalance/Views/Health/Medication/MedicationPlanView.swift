import SwiftUI

struct MedicationPlanView: View {
    @Bindable var store: MedicationCenterStore
    @Binding var path: [MedicationRoute]
    @State private var selectedItem: MedicationScheduleItem?
    @State private var showingAddPlan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MedicationCard(tint: Theme.Colors.mintGreen) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("今日计划").font(.subheadline.bold()).foregroundStyle(Theme.Colors.mintGreen); Spacer(); Text("下一次 \(store.nextDose?.time ?? "--:--")").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6).background(Theme.Colors.surface, in: Capsule()) }
                        Text("\(store.completedCount) / \(store.schedules.count) 完成").font(.title.bold())
                        ProgressView(value: Double(store.completedCount), total: Double(max(store.schedules.count, 1))).tint(Theme.Colors.mintGreen)
                    }
                }
                MedicationSectionHeader(title: "今天的计划", detail: "点击状态可修改")
                if store.schedules.isEmpty {
                    ContentUnavailableView("暂无计划", systemImage: "calendar.badge.plus", description: Text("点击下方按钮添加第一项计划。"))
                        .frame(maxWidth: .infinity).padding().background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    MedicationCard {
                        VStack(spacing: 0) {
                            ForEach(Array(store.schedules.enumerated()), id: \.element.id) { index, item in
                                HStack(spacing: 4) {
                                    MedicationRow(item: item, showChevron: false) { path.append(.instruction(item.medicationID)) }
                                    Menu { ForEach(MedicationCenterDoseStatus.allCases, id: \.self) { status in Button(status.title) { store.updateStatus(id: item.id, status: status) } } } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("修改\(item.name)状态")
                                }
                                if index < store.schedules.count - 1 { Divider().padding(.leading, 96) }
                            }
                        }
                    }
                }
                MedicationCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("提醒设置").font(.headline); Spacer(); Text("\(store.schedules.count) 项已开启").font(.caption.bold()).foregroundStyle(Theme.Colors.mintGreen) }
                        Label("到点提醒 · 静默时段 23:00–07:00", systemImage: "bell.fill").font(.caption)
                        Label("漏记只提示，不自动推断已服用", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                Text("请按医生或药师指导用药；计划仅用于提醒与记录。").font(.caption).foregroundStyle(Theme.Colors.accentBlue).frame(maxWidth: .infinity).padding().background(Theme.Colors.accentBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                MedicationPrimaryButton(title: "新增用药计划") { showingAddPlan = true }
            }.padding(16).padding(.bottom, 24)
        }
        .medicationPage(title: "用药计划", subtitle: "把每天要吃的药安排清楚")
        .sheet(isPresented: $showingAddPlan) { MedicationPlanSheet(draft: MedicationPlanDraft()).adaptiveSheetChrome(style: .reading, dragIndicator: .visible) }
    }
}
