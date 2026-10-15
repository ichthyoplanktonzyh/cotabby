import SwiftUI

/// File overview:
/// Fixed task tabs navigate among completion, translation and learning analysis. Each page uses
/// the established grouped settings scaffold and the app-owned services for its own task.
/// Within completion, the original engine dropdown selects the active engine: Apple Intelligence shows the
/// availability section; picking Open Source shows the local-runtime stack (model picker,
/// downloads, Hugging Face browser, folder controls, installed models). One pane keeps the
/// settings sidebar flat and gives users a single place to manage everything model-related.
struct EngineAndModelPaneView: View {
    @ObservedObject var navigation: SettingsNavigationModel
    var learningModels: LearningModelCollection?
    @ObservedObject var suggestionSettings: SuggestionSettingsModel
    @ObservedObject var openAICompatibleConnectionModel: OpenAICompatibleConnectionModel
    @ObservedObject var foundationModelAvailabilityService: FoundationModelAvailabilityService
    @ObservedObject var runtimeModel: RuntimeBootstrapModel
    @ObservedObject var modelDownloadManager: ModelDownloadManager
    @ObservedObject var huggingFaceSearchService: HuggingFaceSearchService

    @State var pendingDeletionModel: RuntimeModelOption?
    @State var endpointAPIKeyDraft = ""
    @State var endpointCredentialError: String?
    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Model task", table: "Learning"), selection: $navigation.engineTask) {
                ForEach(SettingsEngineTask.allCases) { task in Text(task.label).tag(task) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(String(localized: "Model task", table: "Learning"))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            switch navigation.engineTask {
            case .completion:
                completionPage
            case .translation:
                learningPage(role: .translation)
            case .analysis:
                learningPage(role: .analysis)
            }
        }
        .onAppear {
            // Optional sources must be reconciled even when only Endpoint/Apple sections are
            // visible; reinstalling LM Studio must not silently revive a removed source.
            if UserDefaults.standard.bool(forKey: BundledRuntimeLocator.lmStudioSourceEnabledKey),
               BundledRuntimeLocator.lmStudioModelsDirectoryIfAvailable() == nil {
                UserDefaults.standard.set(false, forKey: BundledRuntimeLocator.lmStudioSourceEnabledKey)
                modelDownloadManager.refreshSearchDirectories()
            }
        }
    }

    /// The completion form retains its original sections, actions and callout. Navigation tabs
    /// sit outside its scroll view so choosing another task cannot change the active engine.
    private var completionPage: some View {
        let contextIdentity = suggestionSettings.completionContextIdentity
        return SettingsPaneScaffold(callout: callout) {
            Section("Engine") {
                Picker(selection: selectedEngineBinding) {
                    // Match onboarding: an engine this Mac cannot run stays listed (so a stored
                    // selection still renders) but is greyed out and labelled, never selectable.
                    // `selectionDisabled` (macOS 14+) disables just that menu item.
                    ForEach(SuggestionEngineKind.allCases) { engine in
                        Text(
                            SuggestionEngineSelectionPolicy.pickerLabel(
                                for: engine,
                                foundationModelAvailable: foundationModelAvailabilityService.isAvailable
                            )
                        )
                        .tag(engine)
                        .selectionDisabled(!isEngineSelectable(engine))
                    }
                } label: {
                    SettingsRowLabel(
                        title: String(localized: "Engine"),
                        description: String(localized: """
                        Apple Intelligence runs on-device using macOS's built-in model (newer Apple Silicon Macs only). Open Source \
                        runs a downloaded model file. Local Endpoint connects to an OpenAI-compatible server you manage.
                        """),
                        systemImage: "cpu"
                    )
                }
                .pickerStyle(.menu)
                .settingsItem(.engine)
            }

            powerSection
            ModelContextSection(
                tokens: Binding(
                    get: { suggestionSettings.completionContextWindowTokens },
                    set: { suggestionSettings.setCompletionContextWindowTokens($0, expectedIdentity: contextIdentity) }),
                maximum: suggestionSettings.selectedEngine == .appleIntelligence
                    ? 4_096
                    : suggestionSettings.selectedEngine == .llamaOpenSource
                        ? ModelContextBudget.maximumLocalTokens : ModelContextBudget.maximumEndpointTokens,
                isEndpoint: suggestionSettings.selectedEngine == .openAICompatible,
                isSystemManaged: suggestionSettings.selectedEngine == .appleIntelligence,
                reset: { suggestionSettings.setCompletionContextWindowTokens(nil, expectedIdentity: contextIdentity) })
                .id(contextIdentity)

            switch suggestionSettings.selectedEngine {
            case .appleIntelligence:
                appleIntelligenceSections
            case .llamaOpenSource:
                openSourceSections
            case .openAICompatible:
                endpointModelSection
            }

            endpointConnectionSection
        }
        .onAppear {
            foundationModelAvailabilityService.refresh()

            suggestionSettings.initializePowerProfiles(
                currentEngine: suggestionSettings.selectedEngine,
                currentModelFilename: runtimeModel.selectedModelFilename,
                currentEndpointModelName: suggestionSettings.openAICompatibleModelName
            )

            loadEndpointAPIKey()
            if suggestionSettings.selectedEngine == .openAICompatible,
               openAICompatibleConnectionModel.state == .idle {
                refreshEndpointModels()
            }
        }
        .onChange(of: suggestionSettings.selectedEngine) { _, engine in
            if engine == .openAICompatible, openAICompatibleConnectionModel.state == .idle {
                refreshEndpointModels()
            }
        }
        .alert(
            String(localized: "Delete Model?"),
            isPresented: pendingDeletionAlertBinding,
            presenting: pendingDeletionModel
        ) { model in
            Button("Delete") { deleteModel(model) }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text(String(localized: "Remove \(model.displayName) from Lingrove's local models folder?", table: "Learning"))
        }
    }

    private func learningPage(role: LearningModelRole) -> some View {
        SettingsPaneScaffold {
            if let learningModels {
                let controller = role == .translation ? learningModels.translation : learningModels.analysis
                LearningModelConfigurationView(controller: controller, profile: controller.profile,
                    suggestionSettings: suggestionSettings, downloads: modelDownloadManager, searchService: huggingFaceSearchService)
            } else {
                Section("Runtime") { Text(String(localized: """
                Learning model services are unavailable. Reopen Settings.
                """, table: "Learning")) }
            }
        }
        // Draft keys belong to a page's UI lifetime. Distinct identity prevents an unsaved
        // translation key from appearing in the analysis form when switching between tasks.
        .id(role)
    }
}
