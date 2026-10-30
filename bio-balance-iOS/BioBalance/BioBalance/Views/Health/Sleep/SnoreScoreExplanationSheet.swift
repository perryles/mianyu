/// SnoreScoreExplanationSheet 由睡眠详情页调用，作为「鼾声评分」说明弹层。
/// 负责定义评分分解项（SnoreScoreBreakdownItem）的数据模型并展示评分权重。

import SwiftUI

struct SnoreScoreBreakdownItem: Identifiable {
    let id = UUID()
    let title: String
    let weightText: String
    let tint: Color
    let value: Int
}

struct SnoreScoreExplanationSheet: View {
    let breakdown: [SnoreScoreBreakdownItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 46, height: 6)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("鼾声评分说明")
                                .font(.appSystem(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.onAccent)
                            Text("鼾声片段会按发生时段归类到睡眠阶段，各阶段加权计算总分。分数越低，通常代表整夜更安静。")
                                .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.onAccent.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 14) {
                            ForEach(breakdown) { item in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(item.tint)
                                        .frame(width: 16, height: 16)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.appSystem(size: 18, weight: .black, design: .rounded))
                                            .foregroundColor(Theme.Colors.onAccent)
                                        Text(item.weightText)
                                            .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(Theme.Colors.onAccent.opacity(0.48))
                                    }

                                    Spacer()

                                    Text("\(item.value)")
                                        .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                                        .foregroundColor(item.tint)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Theme.Colors.surface.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("评分说明")
                        .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "F5A623"))
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
