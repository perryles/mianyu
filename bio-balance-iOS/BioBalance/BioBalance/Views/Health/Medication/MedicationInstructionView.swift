import SwiftUI

struct MedicationInstructionView: View {
    let info: MedicationInfo
    @Binding var path: [MedicationRoute]
    @State private var scrollTarget: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MedicationCard(tint: Theme.Colors.mintGreen) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Image(systemName: "pills.fill").font(.title).foregroundStyle(Theme.Colors.mintGreen); VStack(alignment: .leading) { Text(info.name).font(.title3.bold()).lineLimit(3); Text("示例规格：\(info.specification)").font(.caption).foregroundStyle(Theme.Colors.textTertiary) } }
                            detailPair("通用名", info.genericName); detailPair("剂型", info.dosageForm); detailPair("生产企业", info.manufacturer)
                            Divider()
                            Text("说明书摘要").font(.caption.bold()).foregroundStyle(Theme.Colors.mintGreen)
                            Text(info.indications).font(.subheadline)
                        }
                    }
                    MedicationSectionHeader(title: "快捷入口", detail: "点一下跳到对应内容")
                    HStack(spacing: 8) { jumpButton("用法用量", "usage", Theme.Colors.accentBlue); jumpButton("注意事项", "precautions", Theme.Colors.mintGreen); jumpButton("不良反应", "adverse", Theme.Colors.accentOrange); jumpButton("禁忌", "contra", Theme.Colors.accentRed) }
                    MedicationCard {
                        VStack(alignment: .leading, spacing: 0) {
                            section("适应症", info.indications, "indications")
                            Divider()
                            section("用法用量", info.usage, "usage")
                            Divider()
                            section("注意事项", info.precautions, "precautions")
                            Divider()
                            section("常见不良反应", info.adverseReactions, "adverse")
                        }
                    }
                    MedicationCard { section("禁忌与特殊人群", "\(info.contraindications)\n\n\(info.specialPopulation)", "contra") }
                    Text("本页面内容仅供健康管理参考，请以药品包装内附说明书及医生或药师指导为准。")
                        .font(.caption).foregroundStyle(Theme.Colors.textTertiary).padding().frame(maxWidth: .infinity, alignment: .leading).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18))
                    MedicationPrimaryButton(title: "加入我的用药计划") { path.append(.plan) }
                }.padding(16).padding(.bottom, 24)
            }
            .onChange(of: scrollTarget) { _, target in guard let target else { return }; withAnimation { proxy.scrollTo(target, anchor: .top) }; scrollTarget = nil }
        }
        .medicationPage(title: "药品说明书", subtitle: "先看重点，需要时再展开完整内容")
    }

    private func detailPair(_ title: String, _ value: String) -> some View { HStack(alignment: .top) { Text(title).font(.caption).foregroundStyle(Theme.Colors.textTertiary).frame(width: 62, alignment: .leading); Text(value).font(.caption.bold()).foregroundStyle(Theme.Colors.textPrimary) } }
    private func section(_ title: String, _ body: String, _ id: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(body).font(.subheadline).foregroundStyle(Theme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true) }.padding(.vertical, 14).id(id) }
    private func jumpButton(_ title: String, _ id: String, _ color: Color) -> some View { Button { scrollTarget = id } label: { Text(title).font(.caption.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity, minHeight: 44).background(color.opacity(0.09), in: Capsule()) }.buttonStyle(.plain) }
}
