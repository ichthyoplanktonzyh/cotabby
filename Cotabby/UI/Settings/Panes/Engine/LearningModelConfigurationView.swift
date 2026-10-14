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
            Section(String(localized: "Engine", table: "Learning",
                comment: "Settings section for choosing this learning task's local or endpoint engine.")) {
                Picker(selection: backendBinding) {
                    ForEach(LearningModelBackend.allCases) { Text($0.label).tag($0) }
                } label: {
                    SettingsRowLabel(title: String(localized: "Engine", table: "Learning",
                        comment: "Label for the setting that selects this task's model engine."),
                        description: taskDescription, systemImage: "cpu")
                }
                .pickerStyle(.menu).disabled(profile.powerSwitchingEnabled)
            }
            powerSection
            if profile.snapshot.backend == .local { Section(String(localized: "Runtime", table: "Learning",
                comment: "Settings section for the current state of this task's local runtime.")) {
                LabeledContent {
                    Text(controller.status).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                } label: {
                    SettingsRowLabel(title: String(localized: "Model status", table: "Learning",
                        comment: "Label for the current readiness state of the local model."),
                        description: String(localized: "Shows whether this task's local model is loaded and ready to generate.",
                            table: "Learning", comment: "Description of the local model status field."),
                        systemImage: "info.circle")
                }
                LabeledContent {
                    Text(selectedModel).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                } label: {
                    SettingsRowLabel(title: String(localized: "Current model", table: "Learning",
                        comment: "Label for the model file or endpoint model currently selected for this task."),
                        description: String(localized: "Shows the active selection. Downloaded models must also be selected here.",
                            table: "Learning", comment: "Explains that downloading a model does not select it automatically."),
                        systemImage: "shippingbox")
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
        .alert(String(localized: "Delete model?", table: "Learning",
            comment: "Confirmation alert shown before removing a local model file."),
            isPresented: Binding(get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }), presenting: pendingDeletion) { model in
            Button(String(localized: "Delete", table: "Learning",
                comment: "Confirms removing a downloaded local model.")) {
                downloads?.deleteModel(filename: model.filename); refreshModels(); pendingDeletion = nil
            }
            Button(String(localized: "Cancel", table: "Learning",
                comment: "Cancels removing a downloaded local model."), role: .cancel) { pendingDeletion = nil }
        } message: { model in
            Text(String(
                localized: "Remove \(model.displayName) from Lingrove's local models folder?",
                table: "Learning",
                comment: "Confirmation message naming the local model file that will be removed."
            ))
        }
    }

    private var taskDescription: String {
        profile.role == .translation
            ? String(localized: """
            Choose a local GGUF or a separate endpoint for sentence translation. A translation-focused model is recommended.
            """,
                table: "Learning", comment: "Description of the translation task's engine setting.")
            : String(localized: """
            Choose a local instruction-tuned GGUF or a separate endpoint for chunk alignment. Only confirmed source and translation \
            text is aligned.
            """,
                table: "Learning", comment: "Description of the chunk-alignment task's engine setting.")
    }

    private var selectedModel: String {
        let selection = profile.snapshot
        let name = selection.backend == .local ? selection.localModel : selection.endpointModel
        return name.isEmpty
            ? String(localized: "No model configured", table: "Learning",
                comment: "Value shown when this learning task has no active model selection.")
            : name
    }

    @ViewBuilder
    private var localSections: some View {
        Section(String(localized: "Models", table: "Learning",
            comment: "Settings section for selecting or downloading a local model.")) {
            Text(profile.role == .translation
                ? String(localized: "Choose a translation model. It runs on this Mac.", table: "Learning",
                    comment: "Instruction above the local model picker for the translation task.")
                : String(localized: """
                Choose an instruction-tuned model for chunk alignment. Base continuation models are not suited to this task.
                """,
                    table: "Learning", comment: "Instruction above the local model picker for chunk alignment."))
                .font(.caption).foregroundStyle(.secondary)
            if controller.availableModels.isEmpty {
                Text(String(localized: "No local GGUF models found. Download one below or add your own model file.",
                    table: "Learning", comment: "Empty state shown when no local GGUF model is installed."))
                    .foregroundStyle(.secondary)
            }
            Picker(selection: localModelBinding) {
                Text(String(localized: "Choose a model", table: "Learning",
                    comment: "Empty choice shown before the user selects a local learning model.")).tag("")
                if !profile.snapshot.localModel.isEmpty, !controller.availableModels.contains(where: { $0.filename == profile.snapshot.localModel }) {
                    Text(String(localized: "\(profile.snapshot.localModel) (file unavailable)", table: "Learning",
                        comment: "Picker entry for a previously selected local model file that is no longer available."))
                        .tag(profile.snapshot.localModel)
                }
                ForEach(controller.availableModels) { Text($0.displayName).tag($0.filename) }
            } label: {
                SettingsRowLabel(title: String(localized: "Selected model", table: "Learning",
                    comment: "Label for choosing the local GGUF model used by this learning task."),
                    description: profile.powerSwitchingEnabled
                        ? String(localized: "Set automatically by power source. Use the On Battery / Plugged In pickers above.",
                            table: "Learning", comment: "Explains that power profiles choose the active model automatically.")
                        : String(localized: "Choose from downloaded or imported GGUF files.",
                            table: "Learning", comment: "Explains that the local model picker lists downloaded and imported GGUF files."),
                    systemImage: "shippingbox")
            }
            .pickerStyle(.menu).disabled(profile.powerSwitchingEnabled)
            Picker(selection: templateBinding) {
                ForEach(LearningChatTemplate.available(for: profile.role)) { Text($0.label).tag($0) }
            } label: {
                SettingsRowLabel(title: String(localized: "Instruction template", table: "Learning",
                    comment: "Label for choosing the prompt format expected by a local instruction model."),
                    description: String(localized: """
                    Detected automatically by default. Choose one manually for renamed models or unusual variants.
                    """,
                        table: "Learning", comment: "Explains when the local model's instruction template may need manual selection."),
                    systemImage: "text.alignleft")
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
            Section(String(localized: "Installed", table: "Learning",
                comment: "Settings section listing installed local learning models.")) {
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
        Section(String(localized: "Model", table: "Learning",
            comment: "Settings section for the endpoint model identifier used by this learning task.")) {
            LabeledContent {
                HStack(spacing: 6) {
                    TextField("", text: endpointModelBinding,
                        prompt: Text(String(localized: "Enter model identifier", table: "Learning",
                            comment: "Placeholder for the configured endpoint model name or identifier.")))
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
                    .help(String(localized: "Connect to choose a model, or enter an identifier manually.", table: "Learning",
                        comment: "Tooltip explaining that endpoint models can be discovered or entered manually."))
                    .accessibilityLabel(String(localized: "Choose endpoint model", table: "Learning",
                        comment: "VoiceOver label for opening the list of discovered endpoint models."))
                }
            } label: {
                SettingsRowLabel(title: String(localized: "Model", table: "Learning",
                    comment: "Label for the endpoint model identifier used by this learning task."),
                    description: String(localized: "Endpoint model name used only for this task.",
                        table: "Learning", comment: "Explains that this endpoint model choice is independent of other tasks."),
                    systemImage: "shippingbox")
            }
            LabeledContent(String(localized: "API format", table: "Learning",
                comment: "Label for the API request format used by this learning endpoint."),
                value: String(localized: "Chat Completions", table: "Learning",
                    comment: "OpenAI-compatible chat-completions API format."))
        }
    }

    private var endpointConnectionSection: some View {
        ModelEndpointConnectionSection(baseURL: $profile.baseURL, keyDraft: $apiKey,
            connection: controller.endpointConnection, credentialError: credentialError,
            privacyWarning: privacyWarning,
            transmissionNote: profile.role == .translation
                ? String(localized: "With this endpoint, the service receives the current source text and language direction.",
                    table: "Learning", comment: "Disclosure of what the configured endpoint receives for translation requests.")
                : String(localized: """
                With this endpoint, the service receives the current source text, displayed translation, and language direction.
                """,
                    table: "Learning", comment: "Disclosure of what the configured endpoint receives for chunk-alignment requests."),
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
        return config.hostScope == .publicInternet
            ? String(localized: "With this endpoint, this text is sent to the configured HTTPS remote service.",
                table: "Learning", comment: "Privacy notice shown when the learning endpoint uses a public HTTPS host.")
            : String(localized: "With this endpoint, this text is sent to the configured local-network service.",
                table: "Learning", comment: "Privacy notice shown when the learning endpoint uses a LAN host.")
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
