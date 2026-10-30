import SwiftUI

struct WatchAIView: View {
    var receiver: WatchConnectivityReceiver
    @Environment(\.dismiss) private var dismiss

    private let quickQuestions = [
        String(localized: "我今天整体恢复得怎么样？"),
        String(localized: "为什么今天压力偏高？"),
        String(localized: "今晚最该优先调整什么？"),
        String(localized: "现在适合继续运动吗？")
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pulse AI")
                    .font(.watchAppSystem(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("基于今天已同步的健康摘要，给你保守、可执行的建议。")
                    .font(.watchAppSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                ForEach(quickQuestions, id: \.self) { question in
                    Button(question) { receiver.askAI(question) }
                        .font(.watchAppSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(receiver.isAIWorking || !receiver.isReachable)
                }

                if receiver.isAIWorking {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("正在整理今天的信号…")
                    }
                    .font(.watchAppSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                }
                if let error = receiver.aiErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.watchAppSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.orange.opacity(0.9))
                }
                if let answer = receiver.aiAnswer { answerView(answer) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.black.opacity(0.92))
        .navigationTitle("AI")
        .onAppear {
            receiver.markAIAnswerRead()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func answerView(_ answer: WatchAIAnswer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(answer.summary.isEmpty ? answer.rawMarkdown : answer.summary)
                .font(.watchAppSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            answerSection(title: String(localized: "依据"), items: answer.basis)
            answerSection(title: String(localized: "建议"), items: answer.actions)
            answerSection(title: String(localized: "留意"), items: answer.risks)
            answerSection(title: String(localized: "下一步可问"), items: answer.followUps)
        }
        .padding(12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func answerSection(title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.watchAppSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.65, green: 0.78, blue: 1.0))
                ForEach(items.prefix(3), id: \.self) { item in
                    Text("• \(item)")
                        .font(.watchAppSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
