import SwiftUI

/// OpenAI-compatible endpoint connection, credential, and model controls.
/// These members are internal because Swift extensions in separate files cannot share lexical `private` access;
/// the owning view itself remains module-internal.
extension EngineAndModelPaneView {
// MARK: - OpenAI-compatible endpoint

    /// The completion connection remains available even when completion uses a local engine.
    /// The connection model owns discovery, the settings model owns durable
    /// values, and the key draft lives in this view until an explicit Connect saves it to Keychain.
    var endpointConnectionSection: some View {
        ModelEndpointConnectionSection(baseURL: endpointBaseURLBinding, keyDraft: $endpointAPIKeyDraft,
            connection: openAICompatibleConnectionModel, credentialError: endpointCredentialError,
            privacyWarning: endpointPrivacyWarning, connect: refreshEndpointModels, reset: resetEndpointBaseURL,
            clearKey: {
                endpointAPIKeyDraft = ""
                do { try suggestionSettings.saveOpenAICompatibleAPIKey(nil); endpointCredentialError = nil }
                catch { endpointCredentialError = error.localizedDescription }
            })
    }

    /// These controls configure the ordinary endpoint completion engine only. Learning requests
    /// use their separately selected instruction model and always use Chat Completions.
    var endpointModelSection: some View {
        Section("Model") {
            LabeledContent {
                HStack(spacing: 6) {
                    TextField("", text: endpointModelBinding, prompt: Text("Enter model identifier"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 320)

                    Menu {
                        ForEach(openAICompatibleConnectionModel.models) { model in
                            Button(model.id) {
                                suggestionSettings.setOpenAICompatibleModelName(model.id)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(openAICompatibleConnectionModel.models.isEmpty)
                    .help(endpointModelMenuHelp)
                    .accessibilityLabel("Choose a discovered model")
                }
            } label: {
                SettingsRowLabel(
                    title: String(localized: "Model"),
                    description: String(localized: "Choose a model returned by the server or enter its identifier manually."),
                    systemImage: "shippingbox"
                )
            }
            .settingsItem(.endpointModel)

            Picker(selection: endpointAPIModeBinding) {
                Text("Chat Completions").tag(OpenAICompatibleAPIMode.chatCompletions)
                Text("Text Completions").tag(OpenAICompatibleAPIMode.completions)
            } label: {
                SettingsRowLabel(
                    title: String(localized: "API Format"),
                    description: String(localized: """
                    Chat uses /v1/chat/completions (recommended). Text uses /v1/completions for base models that continue a raw prompt.
                    """),
                    systemImage: "arrow.left.arrow.right"
                )
            }
            .pickerStyle(.segmented)
            .settingsItem(.endpointAPIMode)
        }
    }

    func installedModelRow(_ model: RuntimeModelOption) -> some View {
        InstalledRuntimeModelRow(model: model, selected: model.filename == runtimeModel.selectedModelFilename,
            downloads: modelDownloadManager, delete: { pendingDeletionModel = model })
    }
}
