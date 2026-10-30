import SwiftUI

struct MedicationOnboardingView: View {
    @State private var currentStep = 0
    let completion: (MedicationRoute?) -> Void

    private let pages: [MedicationOnboardingPage] = [
        .init(icon: "pills.circle.fill", title: "欢迎使用用药中心", message: "帮你记录药品、设置提醒，并更安心地管理每天的用药。", note: "提醒只是辅助记录，不会替代专业医疗指导。", button: "开始"),
        .init(icon: "clock.badge.checkmark.fill", title: "按时提醒，不怕忘记", message: "设置每日、每周或临时用药提醒，帮助你按计划服用。", note: "提醒只是提醒，只有你确认后才会记录为已服用。", button: "下一步"),
        .init(icon: "doc.text.viewfinder", title: "拍照识别处方，更快录入", message: "通过处方识别快速提取药品名称、剂量和频次，再核对后加入计划。", note: "识别结果需人工确认。", button: "下一步"),
        .init(icon: "checkmark.circle.fill", title: "开始建立你的第一个用药计划", message: "添加药品并设置提醒时间，之后就可以在用药主页查看每天的安排。", note: "你随时可以在用药计划中修改提醒与记录状态。", button: "开始添加用药")
    ]

    var body: some View {
        let page = pages[currentStep]
        VStack(spacing: 0) {
            HStack { Text("用药引导").font(.subheadline.bold()).foregroundStyle(Theme.Colors.mintGreen); Spacer(); HStack(spacing: 7) { ForEach(pages.indices, id: \.self) { index in Capsule().fill(index == currentStep ? Theme.Colors.mintGreen : Theme.Colors.lightGray).frame(width: index == currentStep ? 28 : 8, height: 8) } } }.padding(.horizontal, 16).padding(.top, 16)
            Spacer(minLength: 24)
            ZStack {
                RoundedRectangle(cornerRadius: 30).fill(currentStep == 2 ? Theme.Colors.accentBlue.opacity(0.08) : Theme.Colors.mintGreen.opacity(0.08))
                Circle().fill(Color.white.opacity(0.86)).frame(width: 190, height: 190)
                Image("ActionHeaderMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .accessibilityHidden(true)
            }.frame(maxWidth: .infinity).frame(height: 276).padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 14) {
                Text(page.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                Text(page.message).font(.body).foregroundStyle(Theme.Colors.textTertiary).fixedSize(horizontal: false, vertical: true)
                MedicationCard { Label { Text(page.note).font(.subheadline).foregroundStyle(Theme.Colors.textSecondary) } icon: { Image(systemName: currentStep == 2 ? "exclamationmark" : "checkmark").foregroundStyle(Theme.Colors.mintGreen) } }
            }.padding(24)
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                MedicationPrimaryButton(title: page.button) { if currentStep < pages.count - 1 { currentStep += 1 } else { completion(.prescription) } }
                if currentStep == pages.count - 1 { Button("稍后再说") { completion(nil) }.frame(minHeight: 44).foregroundStyle(Theme.Colors.textTertiary) }
                else if currentStep > 0 { Button("返回上一步") { currentStep -= 1 }.frame(minHeight: 44).foregroundStyle(Theme.Colors.textTertiary) }
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(Theme.Colors.pageBackground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}

private struct MedicationOnboardingPage {
    let icon: String
    let title: String
    let message: String
    let note: String
    let button: String
}
