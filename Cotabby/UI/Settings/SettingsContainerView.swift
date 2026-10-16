import SwiftUI

/// File overview:
/// Root of the redesigned Settings window. A `NavigationSplitView` with a sidebar of clustered
/// category rows sits on the left and a switching detail pane fills the right side. The detail body
/// is built from `SettingsCategory`, so adding a new pane is a matter of adding an enum case and a
/// `case` in the switch below.
///
/// Navigation flows through `SettingsNavigationModel` so the sidebar, the Home pane's search and
/// quick links, and the window-level Cmd-F shortcut all drive one source of truth. Selection is
/// persisted via `@AppStorage` so reopening Settings lands on the last-used pane. `.id(selection)`
/// on the detail body is the documented workaround for the macOS 14 split-view selection bug where
/// the first sidebar pick doesn't always re-render the detail column.
struct SettingsContainerView: View {
    var learningModels: LearningModelCollection?
    var renderDiagnostics: SettingsRenderDiagnostics? = .process
    @ObservedObject var attentionModel: SettingsAttentionModel
    let appUpdateManager: AppUpdateManager

    // These references are dependencies, not this view's state. Their destination panes observe
    // them locally; only a changed warning set or navigation should invalidate the split view.
    let permissionManager: PermissionManager
    let permissionGuidanceController: PermissionGuidanceController
    let suggestionSettings: SuggestionSettingsModel
    let interfaceLanguageSettings: InterfaceLanguageSettingsModel
    let openAICompatibleConnectionModel: OpenAICompatibleConnectionModel
    let foundationModelAvailabilityService: FoundationModelAvailabilityService
    let runtimeModel: RuntimeBootstrapModel
    let modelDownloadManager: ModelDownloadManager
    let huggingFaceSearchService: HuggingFaceSearchService
    let performanceMetricsStore: PerformanceMetricsStore
    let qualityMetricsStore: SuggestionQualityMetricsStore
    let systemMetricsStore: SystemMetricsStore

    let onShowWelcome: () -> Void
    let onRestart: () throws -> Void
    let clearEmojiHistory: () -> Void
    /// Owned by `CotabbyAppEnvironment`; the Context pane observes it for the Typing History section.
    let typingHistoryStore: TypingHistoryStore
    let onQuit: () -> Void

    @AppStorage("cotabbySettingsSelectedCategoryV2")
    private var storedCategoryRawValue: String = SettingsCategory.home.rawValue

    @StateObject private var navigation = SettingsNavigationModel()
    // Settings should behave like a traditional two-column preferences window: the sidebar is
    // always visible, but SwiftUI can still manage the native navigation/split-view chrome.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        _ = renderDiagnostics?.body("container", category: navigation.selection)
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebarView(
                navigation: navigation,
                attentionCategories: attentionCategories,
                onQuit: onQuit
            )
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailPane
                .background {
                    if let renderDiagnostics, let generation = renderDiagnostics.token(for: navigation.selection) {
                        SettingsLayoutProbe(category: navigation.selection, generation: generation, diagnostics: renderDiagnostics)
                    }
                }
                .id(navigation.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(removing: .sidebarToggle)
                // SwiftUI owns the hosting window's title once a navigation stack is involved, so
                // the title must be declared here rather than written to `NSWindow.title` (any
                // AppKit-side write gets stomped on the next navigation update). Home is the
                // landing surface rather than a pane of controls, so it titles the window with
                // the app-wide name instead of the literal "Home".
                .navigationTitle(navigation.selection == .home ? String(
                    localized: "Lingrove Settings",
                    table: "Learning"
                ) : navigation.selection.label)
        }
        .environment(\.settingsHighlightedItem, navigation.highlightedItem)
        // Window-level Cmd-F: jump to the search surface from any pane. The button renders
        // nothing; it exists to host the keyboard shortcut inside this window's responder chain.
        .background(
            Button("") { navigation.requestSearchFocus() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        // Keep the native split view, but pin the outer Settings window to a practical minimum.
        // The sidebar itself provides a width range, so the default opens readable without forcing
        // an exact column size forever.
        .frame(maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .onAppear {
            navigation.renderDiagnostics = renderDiagnostics
            // Migration: the previous sidebar had two engine sub-rows (`appleIntelligence`,
            // `openSource`). Users whose persisted selection still points to either should land on
            // the unified Engine & Model pane rather than fall back to General.
            navigation.selection = Self.restoreSelection(from: storedCategoryRawValue)
            permissionManager.refresh()
        }
        .onChange(of: navigation.selection) { _, newValue in
            storedCategoryRawValue = newValue.rawValue
        }
        .onChange(of: columnVisibility) { _, newValue in
            if newValue != .all {
                columnVisibility = .all
            }
        }
    }

    /// The window-owned projection publishes only when warning categories actually change.
    private var attentionCategories: Set<SettingsCategory> {
        attentionModel.categories
    }

    @ViewBuilder
    private var detailPane: some View {
        switch navigation.selection {
        case .home:
            HomePaneView(
                navigation: navigation,
                suggestionSettings: suggestionSettings,
                permissionManager: permissionManager,
                foundationModelAvailabilityService: foundationModelAvailabilityService,
                runtimeModel: runtimeModel,
                openAICompatibleConnectionModel: openAICompatibleConnectionModel,
                attentionCategories: attentionCategories
            )
        case .general:
            GeneralPaneView(
                suggestionSettings: suggestionSettings,
                permissionManager: permissionManager,
                interfaceLanguageSettings: interfaceLanguageSettings,
                onShowWelcome: onShowWelcome,
                onRestart: onRestart
            )
        case .appearance:
            AppearancePaneView(suggestionSettings: suggestionSettings)
        case .emoji:
            EmojiPaneView(
                suggestionSettings: suggestionSettings,
                clearEmojiHistory: clearEmojiHistory
            )
        case .engineAndModel:
            EngineAndModelPaneView(
                navigation: navigation,
                learningModels: learningModels,
                suggestionSettings: suggestionSettings,
                openAICompatibleConnectionModel: openAICompatibleConnectionModel,
                foundationModelAvailabilityService: foundationModelAvailabilityService,
                runtimeModel: runtimeModel,
                modelDownloadManager: modelDownloadManager,
                huggingFaceSearchService: huggingFaceSearchService
            )
        case .writing:
            WritingPaneView(
                suggestionSettings: suggestionSettings, configureLearningModel: navigation.openLearningModel,
                openShortcuts: { navigation.openShortcuts() }, renderDiagnostics: renderDiagnostics)
        case .context:
            ContextPaneView(suggestionSettings: suggestionSettings, typingHistory: typingHistoryStore)
        case .shortcuts:
            ShortcutsPaneView(suggestionSettings: suggestionSettings, selectedApp: navigation.shortcutAppBundleIdentifier)
        case .apps:
            AppsPaneView(
                suggestionSettings: suggestionSettings, typingHistory: typingHistoryStore,
                openShortcuts: { navigation.openShortcuts(for: $0) })
        case .permissions:
            PermissionsPaneView(
                permissionManager: permissionManager,
                permissionGuidanceController: permissionGuidanceController
            )
        case .performance:
            PerformancePaneView(
                suggestionSettings: suggestionSettings,
                performanceMetricsStore: performanceMetricsStore,
                qualityMetricsStore: qualityMetricsStore,
                systemMetricsStore: systemMetricsStore, renderDiagnostics: renderDiagnostics
            )
        case .about:
            AboutPaneView(appUpdateManager: appUpdateManager)
        }
    }

    private static func restoreSelection(from rawValue: String) -> SettingsCategory {
        if let category = SettingsCategory(rawValue: rawValue) {
            return category
        }
        // Legacy sub-row raw values from the prior nested layout.
        if rawValue == "appleIntelligence" || rawValue == "openSource" {
            return .engineAndModel
        }
        // The Advanced pane was renamed to Context; keep returning users on the same pane.
        if rawValue == "advanced" {
            return .context
        }
        return .general
    }
}
