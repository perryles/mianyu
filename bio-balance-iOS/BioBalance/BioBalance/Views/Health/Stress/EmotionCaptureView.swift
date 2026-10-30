import SwiftUI

struct EmotionCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedEmotion: EmotionKind = .calm
    @State private var intensity = 3
    @State private var factors: Set<String> = []
    @State private var note = ""
    @State private var feedbackTrigger = 0

    private let factorOptions = [
        String(localized: "工作"), String(localized: "睡眠"), String(localized: "身体"),
        String(localized: "家庭"), String(localized: "社交"), String(localized: "学习"),
        String(localized: "其他")
    ]

    var body: some View {
        ZStack {
            EmotionStressStyle.page.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    EmotionStressPageHeader(title: String(localized: "记录情绪"), subtitle: String(localized: "花一点时间，感受此刻的自己"))
                    sectionTitle("此刻感觉如何？")
                    emotionGrid
                    sectionTitle("情绪强度")
                    EmotionIntensityControl(selection: $intensity)
                    sectionTitle("可能受什么影响？")
                    factorGrid
                    sectionTitle("想补充些什么？")
                    noteEditor
                    Button("保存记录", action: save)
                        .buttonStyle(BBPrimaryButtonStyle(isFullWidth: true))
                        .accessibilityHint("将当前情绪写入本机情绪记录")
                }
                .padding(.horizontal, EmotionStressStyle.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.selection, trigger: feedbackTrigger)
    }

    private var emotionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
            ForEach(EmotionKind.allCases) { emotion in
                let isSelected = selectedEmotion == emotion
                Button {
                    selectedEmotion = emotion
                    feedbackTrigger += 1
                } label: {
                    VStack(spacing: 8) {
                        EmotionIconView(emotion: emotion, size: 34)
                        Text(emotion.title)
                            .font(.subheadline.weight(isSelected ? .bold : .medium))
                            .foregroundStyle(EmotionStressStyle.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: 82)
                    .background(isSelected ? EmotionStressStyle.mintFill : .white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? EmotionStressStyle.mint : EmotionStressStyle.border, lineWidth: isSelected ? 1.5 : 1)
                    }
                }
                .buttonStyle(EmotionSelectionButtonStyle(reduceMotion: reduceMotion))
                .accessibilityLabel(emotion.title)
                .accessibilityValue(isSelected ? "已选择" : "未选择")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var factorGrid: some View {
        FlowLayout(spacing: 8) {
            ForEach(factorOptions, id: \.self) { factor in
                let isSelected = factors.contains(factor)
                Button {
                    if isSelected { factors.remove(factor) } else { factors.insert(factor) }
                } label: {
                    Text(factor)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? EmotionStressStyle.mint : EmotionStressStyle.secondary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(isSelected ? EmotionStressStyle.mintFill : .white, in: Capsule())
                        .overlay(Capsule().stroke(isSelected ? EmotionStressStyle.mint : EmotionStressStyle.border))
                }
                .buttonStyle(.plain)
                .accessibilityValue(isSelected ? "已选择" : "未选择")
            }
        }
    }

    private var noteEditor: some View {
        TextEditor(text: $note)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 108)
            .padding(12)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EmotionStressStyle.border))
            .accessibilityLabel("备注")
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.headline.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = MoodEntry(
            id: UUID().uuidString,
            moodID: selectedEmotion.moodID,
            title: selectedEmotion.title,
            backendEmotionCode: selectedEmotion.backendCode,
            intensity: intensity * 20,
            factors: factors.sorted(),
            note: trimmed.isEmpty ? nil : trimmed,
            loggedAt: .now,
            backendRecordedAt: nil
        )
        MoodStore.shared.save(entry)
        dismiss()
    }
}

private struct EmotionSelectionButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: configuration.isPressed ? 0.12 : 0.18), value: configuration.isPressed)
    }
}

private struct EmotionIntensityControl: View {
    @Binding var selection: Int
    private let labels = ["很轻", "轻微", "明显", "较强", "很强"]

    var body: some View {
        EmotionStressCard {
            VStack(spacing: 12) {
                GeometryReader { proxy in
                    let segment = proxy.size.width / 4
                    ZStack(alignment: .leading) {
                        Capsule().fill(EmotionStressStyle.track).frame(height: 4)
                        Capsule().fill(EmotionStressStyle.mintMuted)
                            .frame(width: segment * CGFloat(selection - 1), height: 4)
                        HStack(spacing: 0) {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) { selection = value }
                                } label: {
                                    Circle()
                                        .fill(value <= selection ? EmotionStressStyle.mint : .white)
                                        .overlay(Circle().stroke(value <= selection ? EmotionStressStyle.mint : EmotionStressStyle.grayGreen, lineWidth: 2))
                                        .frame(width: value == selection ? 16 : 12, height: value == selection ? 16 : 12)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(labels[value - 1])
                                .accessibilityValue(value == selection ? "当前强度" : "")
                                .accessibilityAddTraits(value == selection ? .isSelected : [])
                            }
                        }
                    }
                }
                .frame(height: 44)
                HStack {
                    ForEach(labels, id: \.self) { Text($0).font(.caption2).foregroundStyle(EmotionStressStyle.secondary).frame(maxWidth: .infinity) }
                }
                Text("当前：\(labels[selection - 1])")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(EmotionStressStyle.mint)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// iOS 16+ 的轻量换行布局，用于影响因素标签。
private struct FlowLayout: Layout {
    let spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

#Preview { NavigationStack { EmotionCaptureView() } }
