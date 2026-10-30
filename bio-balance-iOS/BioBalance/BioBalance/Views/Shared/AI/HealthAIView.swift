/// HealthAIView 由今日页与健康详情页调用，作为「AI 健康助手」对话页。
/// 负责管理对话消息列表、流式响应、追问推荐与输入提交，支持今日/健康画像两种作用域。

import SwiftUI

@MainActor @Observable
final class HealthAIViewModel {
    var messages: [HealthAIChatMessage] = []
    var inputText: String = ""
    var isSending = false
    var errorMessage: String?
    var followUps: [String] = []
    /// 流式响应期间的累积文本快照（用于实时渲染）
    var streamingText: String?

    private let service: HealthAIServiceProtocol
    private let scope: HealthAIScope
    private(set) var lastSubmittedQuestion: String?

    var heroSubtitle: String { scope.heroSubtitle }
    var composerStatus: String { scope.composerStatus }
    var inputPlaceholder: String { scope.inputPlaceholder }
    var quickQuestions: [String] { scope.quickQuestions }
    var loadingDetailMessage: String { scope.loadingMessage }

    var lastMessageScrollKey: String {
        guard let last = messages.last else { return "empty" }
        return "\(last.id.uuidString)-\(last.text)-\(last.isLoading)-\(last.isError)"
    }

    init(
        scope: HealthAIScope,
        initialPrompt: String? = nil,
        service: HealthAIServiceProtocol
    ) {
        self.scope = scope
        self.service = service
        self.messages = [
            HealthAIChatMessage(
                role: .assistant,
                text: scope.welcomeMessage
            )
        ]

        self.inputText = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    convenience init(context: HealthAIContext, initialPrompt: String? = nil) {
        self.init(scope: .today(context), initialPrompt: initialPrompt, service: HealthAIService())
    }

    convenience init(profileDigest: HealthProfileAIDigest, initialPrompt: String? = nil) {
        self.init(
            scope: .healthProfile(digest: profileDigest),
            initialPrompt: initialPrompt,
            service: HealthAIService()
        )
    }

    func submitCurrentInput() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        await submit(question: trimmed)
    }

    func stagePrompt(_ prompt: String) {
        inputText = prompt
    }

    func submitFollowUp(_ prompt: String) async {
        await submit(question: prompt)
    }

    func retryLastQuestion() async {
        guard let lastSubmittedQuestion else { return }
        await submit(question: lastSubmittedQuestion)
    }

    private func submit(question: String) async {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil
        streamingText = nil
        lastSubmittedQuestion = question

        messages.append(HealthAIChatMessage(role: .user, text: question))
        let loadingID = UUID()
        messages.append(
            HealthAIChatMessage(
                id: loadingID,
                role: .assistant,
                text: scope.loadingMessage,
                isLoading: true
            )
        )

        do {
            let stream = service.askStreaming(question: question, scope: scope, history: messages)
            for try await event in stream {
                switch event {
                case .textSnapshot(let text):
                    streamingText = text
                case .completed(let answer):
                    followUps = answer.followUps
                    streamingText = nil
                    replaceLoadingMessage(
                        id: loadingID,
                        with: HealthAIChatMessage(
                            role: .assistant,
                            text: answer.displayText,
                            answerPayload: answer
                        )
                    )
                }
            }
        } catch {
            streamingText = nil
            errorMessage = error.localizedDescription
            replaceLoadingMessage(
                id: loadingID,
                with: HealthAIChatMessage(
                    role: .assistant,
                    text: error.localizedDescription,
                    isError: true
                )
            )
        }

        isSending = false
    }

    private func replaceLoadingMessage(id: UUID, with message: HealthAIChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            messages.append(message)
            return
        }
        messages[index] = message
    }
}

struct HealthAIView: View {
    private static let messageTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: HealthAIViewModel
    @FocusState private var isInputFocused: Bool

    init(context: HealthAIContext, initialPrompt: String? = nil) {
        let scope = HealthAIScope.today(context)
        _viewModel = State(wrappedValue: HealthAIViewModel(scope: scope, initialPrompt: initialPrompt, service: HealthAIService()))
    }

    init(profileDigest: HealthProfileAIDigest, initialPrompt: String? = nil) {
        let scope = HealthAIScope.healthProfile(digest: profileDigest)
        _viewModel = State(wrappedValue: HealthAIViewModel(scope: scope, initialPrompt: initialPrompt, service: HealthAIService()))
    }

    init(fitnessContext: FitnessAIInsightContext, initialPrompt: String? = nil) {
        let scope = HealthAIScope.fitness(fitnessContext)
        _viewModel = State(wrappedValue: HealthAIViewModel(scope: scope, initialPrompt: initialPrompt, service: HealthAIService()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            agentHero
                            conversationWorkspace

                            if let errorMessage = viewModel.errorMessage {
                                errorCard(errorMessage)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isInputFocused = false
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastID = viewModel.messages.last?.id {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.lastMessageScrollKey) { _, _ in
                        if let lastID = viewModel.messages.last?.id {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.streamingText) { _, _ in
                        if let lastID = viewModel.messages.last?.id {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }

                composer
            }
            .background(assistantBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
            }
            .navigationTitle("眠屿 AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var assistantBackground: some View {
        HealthDetailPageBackground(
            topGlow: Color(hex: "C8DEFA"),
            lowerGlow: Color(hex: "DDEBFA")
        )
    }

    private var agentHero: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.appSystem(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "2E64F5"))
                .frame(width: 36, height: 36)
                .bbTintedChip(tint: Color.white, in: Circle(), tintOpacity: 0.05)

            VStack(alignment: .leading, spacing: 3) {
                Text("眠屿 AI")
                    .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(viewModel.heroSubtitle)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .healthDetailSurface(padding: 16)
    }

    private var conversationWorkspace: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.messages.count == 1 {
                emptyConversationPrompt
            }

            ForEach(viewModel.messages) { message in
                messageRow(message)
                    .id(message.id)

            }

            if !viewModel.followUps.isEmpty {
                followUpSection
            }
        }

    }

    private var emptyConversationPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常用问题")
                .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.quickQuestions, id: \.self) { question in
                    promptButton(question)
                }
            }
        }
        .healthDetailSurface(padding: 14)
    }

    private func promptButton(_ text: String) -> some View {
        Button {
            viewModel.stagePrompt(text)
            isInputFocused = true
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.appSystem(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "2E64F5"))
                    .padding(.top, 2)
                Text(text)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("继续追问")
                .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: 8) {
                ForEach(viewModel.followUps, id: \.self) { prompt in
                    Button {
                        Task { await viewModel.submitFollowUp(prompt) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrowshape.turn.up.right.fill")
                                .font(.appSystem(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: "2E64F5"))
                            Text(prompt)
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "2E64F5"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.appSystem(size: 10, weight: .bold))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .bbTintedSurface(tint: Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous), tintStrength: 0.03, shadow: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSending)
                }
            }
        }
    }

    private func messageRow(_ message: HealthAIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant || message.role == .system {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(Theme.Colors.pastelMint, in: Circle())
                    .accessibilityHidden(true)
                bubble(message, isUser: false)
            } else {
                Spacer(minLength: 44)
                bubble(message, isUser: true)
            }
        }
        .padding(.vertical, 8)
    }

    private func bubble(_ message: HealthAIChatMessage, isUser: Bool) -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            if let payload = message.answerPayload, !isUser, payload.hasStructuredContent {
                structuredAnswerCard(payload)
            } else {
                messageContent(message, isUser: isUser)
            }

            if !isUser, let source = message.answerPayload?.source {
                answerSourceLabel(source)
            }

            if message.isLoading {
                if let streaming = viewModel.streamingText {
                    streamingTextView(streaming)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Theme.Colors.textSecondary)
                        Text(viewModel.loadingDetailMessage)
                            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(isUser ? 14 : 0)
        .background(isUser ? Theme.Colors.secondarySurface : Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .textSelection(.enabled)
    }

    private func answerSourceLabel(_ source: AIResponseSource) -> some View {
        Label(
            "回答来源：\(source.displayLabel)",
            systemImage: source.isLocal ? "iphone" : "cloud"
        )
        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
        .foregroundColor(Theme.Colors.textTertiary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.Colors.secondarySurface, in: Capsule())
        .accessibilityLabel("回答来源，\(source.displayLabel)")
    }

    private func structuredAnswerCard(_ payload: HealthAIAnswerPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = payload.summary {
                structuredSection("结论", lines: [summary], accent: Color(hex: "2E64F5"), emphasized: true)
            }
            if !payload.basis.isEmpty {
                structuredSection("依据", lines: payload.basis, accent: Color(hex: "3E9BE8"))
            }
            if !payload.actions.isEmpty {
                structuredSection("建议", lines: payload.actions, accent: Theme.Colors.mintGreen)
            }
            if !payload.risks.isEmpty {
                structuredSection("留意", lines: payload.risks, accent: Color(hex: "F3A53B"))
            }
            if !payload.followUps.isEmpty {
                structuredSection("下一步可问", lines: payload.followUps, accent: Color(hex: "8B7CFF"))
            }
        }
    }

    private func structuredSection(_ title: String, lines: [String], accent: Color, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.appSystem(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer(minLength: 0)

            }

            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Theme.Colors.textSecondary)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(line)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .lineSpacing(4)
    }

    @ViewBuilder
    private func messageContent(_ message: HealthAIChatMessage, isUser: Bool) -> some View {
        if isUser {
            Text(message.text)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else if let attributed = markdownAttributedString(from: message.text) {
            Text(attributed)
                .tint(Color(hex: "2E64F5"))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(message.text)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func streamingTextView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let attributed = markdownAttributedString(from: text) {
                Text(attributed)
                    .tint(Color(hex: "2E64F5"))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text)
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.Colors.textTertiary)
                Text("正在生成…")
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
    }

    private func markdownAttributedString(from text: String) -> AttributedString? {
        guard !text.isEmpty else { return nil }
        return try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(Color(hex: "FF7A59"))
            Text(message)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
            Button("重试") {
                Task { await viewModel.retryLastQuestion() }
            }
            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .bbTintedSurface(tint: Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous), tintStrength: 0.03, shadow: false)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack {
                Text("继续追问")
                    .font(.appSystem(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text(viewModel.isSending ? "正在生成回答" : viewModel.composerStatus)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            HStack(spacing: 10) {
                TextField(viewModel.inputPlaceholder, text: $viewModel.inputText, axis: .vertical)
                    .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .bbTintedSurface(tint: Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous), tintStrength: 0.03, shadow: false)

                Button {
                    Task { await viewModel.submitCurrentInput() }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: viewModel.isSending ? "hourglass" : "arrow.up")
                            .font(.appSystem(size: 15, weight: .bold))
                        Text("发送")
                            .font(.appSystem(size: 10, weight: .black, design: .rounded))
                    }
                    .foregroundColor(Color(hex: "2E64F5"))
                    .frame(width: 52, height: 52)
                    .bbTintedChip(tint: Color.white, in: Circle(), tintOpacity: 0.05)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Theme.Colors.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Colors.surfaceBorder)
                .frame(height: 1)
        }
    }
}
