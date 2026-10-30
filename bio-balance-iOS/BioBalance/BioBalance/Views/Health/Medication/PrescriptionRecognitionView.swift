import SwiftUI

struct PrescriptionRecognitionView: View {
    @Bindable var store: MedicationCenterStore
    @Binding var path: [MedicationRoute]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
                Text("处方识别可能存在错误，请以处方原件以及医生或药师指导为准。")
                    .font(.caption).foregroundStyle(Theme.Colors.accentBlue).padding().frame(maxWidth: .infinity, alignment: .leading).background(Theme.Colors.accentBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            }.padding(16).padding(.bottom, 24)
        }
        .medicationPage(title: "用药处方识别", subtitle: "核对识别结果，再加入用药计划")
    }

    @ViewBuilder private var content: some View {
        switch store.recognitionState {
        case .idle:
            MedicationCard {
                VStack(spacing: 18) {
                    Image(systemName: "doc.viewfinder").font(.system(size: 52)).foregroundStyle(Theme.Colors.mintGreen).accessibilityHidden(true)
                    Text("拍摄或选择一张清晰的处方照片").font(.headline).multilineTextAlignment(.center)
                    MedicationPrimaryButton(title: "拍摄处方") { Task { await store.recognizePrescription() } }
                    BBSecondaryButton(title: "从相册选择") { Task { await store.recognizePrescription() } }
                }.frame(maxWidth: .infinity)
            }
        case .recognizing:
            MedicationCard(tint: Theme.Colors.mintGreen) {
                VStack(spacing: 16) { ProgressView().controlSize(.large); Text("正在识别处方…").font(.headline); Text("图片仅用于本次识别，请稍候。").font(.caption).foregroundStyle(Theme.Colors.textTertiary) }.frame(maxWidth: .infinity).padding(.vertical, 34)
            }
        case .failed(let message):
            ContentUnavailableView("识别失败", systemImage: "exclamationmark.triangle", description: Text(message))
                .frame(maxWidth: .infinity).padding().background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20))
            MedicationPrimaryButton(title: "重新识别") { store.resetRecognition() }
        case .result(let items):
            resultContent(items)
        }
    }

    private func resultContent(_ items: [RecognizedMedication]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            MedicationCard(tint: Theme.Colors.mintGreen) { HStack(spacing: 14) { Image(systemName: "doc.text.magnifyingglass").font(.title).foregroundStyle(Theme.Colors.mintGreen); VStack(alignment: .leading, spacing: 4) { BBStatusBadge.success("识别完成"); Text(items.isEmpty ? "未识别到药品" : "已读取处方内容").font(.headline); Text("识别到 \(items.count) 项药品，请逐项核对。").font(.caption).foregroundStyle(Theme.Colors.textTertiary) } } }
            MedicationSectionHeader(title: "识别结果", detail: "\(items.count) 项")
            if items.isEmpty { ContentUnavailableView("无识别结果", systemImage: "doc.text", description: Text("请重新拍摄清晰、完整的处方。")) }
            else {
                MedicationCard {
                    VStack(spacing: 0) { ForEach(Array(items.enumerated()), id: \.element.id) { index, item in Button { path.append(.instruction(item.medicationID)) } label: { HStack(spacing: 12) { Text("\(index + 1)").font(.caption.bold()).foregroundStyle(Theme.Colors.accentOrange).frame(width: 34, height: 34).background(Theme.Colors.accentOrange.opacity(0.1), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text(item.name).font(.subheadline.bold()).foregroundStyle(Theme.Colors.textPrimary).lineLimit(2); Text("\(item.specification) · \(item.frequency)").font(.caption).foregroundStyle(Theme.Colors.textTertiary) }; Spacer(); BBStatusBadge.warning("需核对"); Image(systemName: "chevron.right").font(.caption) }.frame(minHeight: 70).contentShape(Rectangle()) }.buttonStyle(.plain); if index < items.count - 1 { Divider().padding(.leading, 46) } } }
                }
            }
            HStack { BBSecondaryButton(title: "重新识别") { store.resetRecognition() }; MedicationPrimaryButton(title: "确认并加入计划", isDisabled: items.isEmpty) { store.addRecognizedToPlan(items); path.append(.plan) } }
        }
    }
}
