import SwiftUI

/// One learning task's form sections use the same scaffold and native row controls as completion.
/// The app owns its controller/profile; this view owns only an unsaved key draft and connect state.
/// Switching task tabs changes view identity, keeping draft keys out of the other role's form.
struct LearningModelConfigurationView: View {
    @ObservedObject var controller: LearningModelController
    @ObservedObject var profile: LearningModelSettings
    @ObservedObject var suggestionSettings: SuggestionSettingsModel
    var downloads: ModelDownloadManager?
    var searchService: HuggingFaceSearchService? = nil
    @State private var apiKey = ""
    @State private var credentialError: String?
    @State private var pendingDeletion: RuntimeModelOption?

    var body: some View {
        Group {
            Section("Engine") {
                Picker(selection: backendBinding) {
                    ForEach(LearningModelBackend.allCases) { Text($0.label).tag($0) }
                } label: {
                    SettingsRowLabel(title: "Engine", description: taskDescription, systemImage: "cpu")
                }
                .pickerStyle(.menu).disabled(profile.powerSwitchingEnabled)
            }
            powerSection
            if profile.snapshot.backend == .local { Section("Runtime") {
                LabeledContent {
                    Text(controller.status).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                } label: {
                    SettingsRowLabel(title: "Model Status", description: "Whether this task's local model is loaded and ready to generate.", systemImage: "info.circle")
                }
                LabeledContent {
                    Text(selectedModel).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                } label: {
                    SettingsRowLabel(title: "当前模型", description: "显示实际配置；下载模型后还需要在此选择。", systemImage: "shippingbox")
                }
            } }
            switch profile.snapshot.backend {
            case .local: localSections
            case .endpoint:
                endpointModelSection
            }
            endpointConnectionSection
        }
        .onAppear {
            controller.refreshModels()
            do { apiKey = try profile.apiKey() ?? ""; credentialError = nil }
            catch { credentialError = error.localizedDescription }
            if profile.snapshot.backend == .endpoint, controller.endpointConnection.state == .idle {
                Task { await controller.discoverEndpoint() }
            }
        }
        .onChange(of: profile.snapshot.backend) { _, backend in
            if backend == .endpoint, controller.endpointConnection.state == .idle {
                Task { await controller.discoverEndpoint() }
            }
        }
        .alert("Delete Model?", isPresented: Binding(get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }), presenting: pendingDeletion) { model in
            Button("Delete") { downloads?.deleteModel(filename: model.filename); refreshModels(); pendingDeletion = nil }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { model in Text("Remove \(model.displayName) from Cotabby's local models folder?") }
    }

    private var taskDescription: String {
        profile.role == .translation
            ? "为整句翻译选择内置 GGUF 或独立 Endpoint，建议使用翻译专用模型。"
            : "为语块切分与对应选择内置指令 GGUF 或独立 Endpoint；只对齐已经确定的原文和译文。"
    }

    private var selectedModel: String {
        let selection = profile.snapshot
        let name = selection.backend == .local ? selection.localModel : selection.endpointModel
        return name.isEmpty ? "尚未配置模型" : name
    }

    @ViewBuilder
    private var localSections: some View {
        Section("Models") {
            Text(profile.role == .translation ? "请选择翻译模型，模型在本机运行。" :
                "请选择指令模型切分与对齐语块，原有 Base 续写模型不适合此任务。")
                .font(.caption).foregroundStyle(.secondary)
            if controller.availableModels.isEmpty {
                Text("No local GGUF models found. Download one below or add your own model file.")
                    .foregroundStyle(.secondary)
            }
            Picker(selection: localModelBinding) {
                Text("请选择模型").tag("")
                if !profile.snapshot.localModel.isEmpty, !controller.availableModels.contains(where: { $0.filename == profile.snapshot.localModel }) {
                    Text("\(profile.snapshot.localModel)（文件不可用）").tag(profile.snapshot.localModel)
                }
                ForEach(controller.availableModels) { Text($0.displayName).tag($0.filename) }
            } label: {
                SettingsRowLabel(title: "Selected Model", description: profile.powerSwitchingEnabled ? "Set automatically by power source. Use the On Battery / Plugged In pickers above." : "从已下载或导入的 GGUF 文件中选择。", systemImage: "shippingbox")
            }
            .pickerStyle(.menu).disabled(profile.powerSwitchingEnabled)
            Picker(selection: templateBinding) {
                ForEach(LearningChatTemplate.available(for: profile.role)) { Text($0.label).tag($0) }
            } label: {
                SettingsRowLabel(title: "指令模板", description: "默认自动识别；重命名或特殊规格的模型可手动指定。", systemImage: "text.alignleft")
            }
            .pickerStyle(.menu).disabled(profile.powerSwitchingEnabled)
            if let downloads {
                DownloadableModelCatalogView(modelDownloadManager: downloads, onRefreshModels: refreshModels,
                    catalog: profile.role == .translation ? LearningRuntimeCatalog.translationModels : LearningRuntimeCatalog.analysisModels)
                if let searchService {
                    HuggingFaceModelBrowserView(searchService: searchService,
                        modelDownloadManager: downloads, onRefreshModels: refreshModels)
                }
            }
        }
        if let downloads { ModelsFolderSection(downloads: downloads, refresh: refreshModels) }
        if !controller.availableModels.isEmpty {
            Section("Installed") {
                ForEach(controller.availableModels) { model in
                    if let downloads {
                        InstalledRuntimeModelRow(model: model, selected: model.filename == profile.snapshot.localModel,
                            downloads: downloads,
                            select: profile.powerSwitchingEnabled ? nil : { profile.localModel = model.filename },
                            delete: { pendingDeletion = model })
                    }

                }
            }
        }
    }

    private var endpointModelSection: some View {
        Section("Model") {
            LabeledContent {
                HStack(spacing: 6) {
                    TextField("", text: endpointModelBinding, prompt: Text("Enter model identifier"))
                        .labelsHidden().textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 320).disabled(profile.powerSwitchingEnabled)
                    Menu {
                        ForEach(controller.endpointConnection.models) { option in
                            Button(option.id) { profile.endpointModel = option.id }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down").frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .disabled(controller.endpointConnection.models.isEmpty || profile.powerSwitchingEnabled)
                    .help("连接服务后选择模型，也可以手动填写标识符。")
                    .accessibilityLabel("选择服务模型")
                }
            } label: {
                SettingsRowLabel(title: "Model", description: "此任务独立使用的服务模型名称。", systemImage: "shippingbox")
            }
            LabeledContent("API Format", value: "Chat Completions")
        }
    }

    private var endpointConnectionSection: some View {
        ModelEndpointConnectionSection(baseURL: $profile.baseURL, keyDraft: $apiKey,
            connection: controller.endpointConnection, credentialError: credentialError,
            privacyWarning: privacyWarning,
            transmissionNote: profile.role == .translation ? "使用此 Endpoint 时，服务接收本次原文和语言方向。" :
                "使用此 Endpoint 时，服务接收本次原文、已显示的译文和语言方向。",
            connect: {
                let draft = apiKey
                Task { await controller.connect(using: draft); credentialError = nil }
            },
            reset: controller.resetEndpointBaseURL,
            clearKey: {
                apiKey = ""
                credentialError = profile.saveAPIKey(nil) ? nil : profile.credentialMessage
            })
    }
    private var privacyWarning: String? {
        guard let config = try? OpenAICompatibleEndpointConfiguration(baseURLString: profile.baseURL,
            modelName: profile.endpointModel, apiMode: .chatCompletions), config.hostScope != .loopback else { return nil }
        return config.hostScope == .publicInternet ? "使用此 Endpoint 时，这些文字会发送到你配置的 HTTPS 远端服务。" :
            "使用此 Endpoint 时，这些文字会发送到你配置的局域网服务。"
    }
    private var backendBinding: Binding<LearningModelBackend> {
        Binding(get: { profile.snapshot.backend }, set: { profile.backend = $0 })
    }
    private var localModelBinding: Binding<String> {
        Binding(get: { profile.snapshot.localModel }, set: { profile.localModel = $0 })
    }
    private var endpointModelBinding: Binding<String> {
        Binding(get: { profile.snapshot.endpointModel }, set: { profile.endpointModel = $0 })
    }
    private var templateBinding: Binding<LearningChatTemplate> {
        Binding(get: { profile.snapshot.template }, set: { profile.template = $0 })
    }
    private func refreshModels() { downloads?.refreshModelStates(); controller.refreshModels() }
}
