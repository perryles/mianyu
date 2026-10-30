#if DEBUG || INTERNAL_AI
import SwiftUI

/// 仅供内部构建使用的 AI 调试配置，不应出现在普通 Release 包中。
struct InternalAISettingsView: View {
    @State private var model: InternalAISettingsModel

    init(
        configurationStore: AIProviderConfigurationStore = .shared,
        secretsStore: AISecretsStore = .shared
    ) {
        _model = State(
            initialValue: InternalAISettingsModel(
                configurationStore: configurationStore,
                secretsStore: secretsStore
            )
        )
    }

    var body: some View {
        Form {
            Section("千问") {
                LabeledContent("今日健康问答", value: "阿里云千问（首选）")
                SecureField("DashScope API Key", text: $model.apiKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("健康文本") {
                TextField("Endpoint", text: $model.configuration.textEndpoint, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("模型", text: $model.configuration.textModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("餐食与饮品视觉") {
                LabeledContent("Provider", value: "阿里云千问（强制）")
                TextField("Endpoint", text: $model.configuration.visionEndpoint, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("模型", text: $model.configuration.visionModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("本地 Fallback") {
                LabeledContent("Foundation Models", value: model.foundationModelsStatus)
            }

            Section {
                Button(action: model.save) {
                    Label("保存配置", systemImage: "square.and.arrow.down")
                }
                Button(action: model.testConnection) {
                    HStack {
                        Label("测试文本连接", systemImage: "network")
                        Spacer()
                        if model.isTesting { ProgressView() }
                    }
                }
                .disabled(model.isTesting)

                if let feedback = model.feedback {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("连接测试不会记录 API Key、提示词或健康指标。千问不可用时将尝试 Apple Foundation Models 本地推理。")
            }
        }
        .navigationTitle("内部 AI 配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

/// 集中管理表单状态和异步测试，避免把 Keychain 操作散落在 SwiftUI 视图中。
@MainActor @Observable
private final class InternalAISettingsModel {
    var configuration: QwenConfiguration
    var apiKey: String
    var feedback: String?
    var isTesting = false

    private let configurationStore: AIProviderConfigurationStore
    private let secretsStore: AISecretsStore

    var foundationModelsStatus: String {
        let provider = AppleFoundationModelsTextProvider.shared
        return provider.isAvailable(for: .healthChat) ? "可用" : "不可用"
    }

    init(configurationStore: AIProviderConfigurationStore, secretsStore: AISecretsStore) {
        self.configurationStore = configurationStore
        self.secretsStore = secretsStore
        configuration = configurationStore.qwen
        apiKey = secretsStore.storedQwenAPIKey()
    }

    func save() {
        do {
            configuration.isEnabled = true
            configurationStore.qwen = configuration
            try secretsStore.saveQwenAPIKey(apiKey)
            feedback = "配置已保存。"
        } catch {
            feedback = error.localizedDescription
        }
    }

    func testConnection() {
        save()
        isTesting = true
        feedback = nil
        Task {
            do {
                try await QwenAIProvider.shared.testTextConnection()
                feedback = "连接成功。"
            } catch {
                feedback = error.localizedDescription
            }
            isTesting = false
        }
    }
}
#endif
