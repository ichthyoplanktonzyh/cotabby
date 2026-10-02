import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The unified App settings pane owns only navigation/search state. Its environment-owned settings
/// and history stores remain the single sources of truth; list entries are a pure projection.
/// The existing grouped scaffold, native rows and application picker are reused on both screens.
struct AppsPaneView: View {
    @ObservedObject var suggestionSettings: SuggestionSettingsModel
    @ObservedObject var typingHistory: TypingHistoryStore
    @Environment(\.settingsHighlightedItem) private var highlightedItem
    @State private var runningApps: [RunningAppSuggestion] = []
    @State private var selectedApp: AppSettingsEntry?
    @State private var searchText = ""

    var body: some View {
        SettingsPaneScaffold {
            if let selectedApp {
                AppSettingsDetailView(
                    suggestionSettings: suggestionSettings, typingHistory: typingHistory,
                    bundleIdentifier: selectedApp.bundleIdentifier, displayName: selectedApp.displayName,
                    onBack: { self.selectedApp = nil }
                )
            } else {
                appListSection
                integratedTerminalsSection
            }
        }
        // Reusing the scaffold's search-arrival behavior also resets scroll position between screens.
        .id(selectedApp?.bundleIdentifier ?? "app-list")
        .onAppear { runningApps = RunningAppSuggestion.collect() }
        .onChange(of: highlightedItem) { _, item in
            if item == .disabledApps || item == .suggestInIntegratedTerminals { selectedApp = nil }
        }
    }

    private var entries: [AppSettingsEntry] {
        AppSettingsList.entries(
            inputCounts: typingHistory.recordCountsByApp,
            disabledRules: suggestionSettings.disabledAppRules,
            overrides: suggestionSettings.perAppShortcutOverrides,
            excludedFromHistory: typingHistory.preferences.excludedBundleIdentifiers,
            addedBundleIdentifiers: runningApps.map(\.bundleIdentifier),
            displayName: { identifier in
                runningApps.first { $0.bundleIdentifier == identifier }?.displayName
                    ?? AppIconCache.displayName(for: identifier)
            }
        )
    }

    private var appListSection: some View {
        Section("Apps") {
            Text("Choose an app to customize its completions, shortcuts, and typing history.", tableName: "Learning")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .settingsItem(.disabledApps)
            HStack(spacing: 8) {
                TextField(String(localized: "Search apps", table: "Learning"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button("Add App…", action: presentAppPicker)
            }
            let visible = AppSettingsList.filter(entries, query: searchText)
            if visible.isEmpty {
                Text(searchText.isEmpty
                     ? String(localized: "No apps yet. Add one to customize its settings.", table: "Learning")
                     : String(localized: "No apps match this search.", table: "Learning"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visible) { entry in
                    Button { selectedApp = entry } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: AppIconCache.icon(for: entry.bundleIdentifier))
                                .resizable().frame(width: 24, height: 24).accessibilityHidden(true)
                            Text(entry.displayName)
                            if entry.isDisabled {
                                Text("Off", tableName: "Learning").foregroundStyle(.secondary)
                            } else if entry.hasOverrides {
                                Text("Customized", tableName: "Learning").foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if entry.inputCount > 0 {
                                Text("\(entry.inputCount) entries stored")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var integratedTerminalsSection: some View {
        Section("Integrated Terminals") {
            Toggle(isOn: Binding(
                get: { suggestionSettings.suggestInIntegratedTerminals },
                set: { suggestionSettings.setSuggestInIntegratedTerminals($0) }
            )) {
                SettingsRowLabel(
                    title: String(localized: "Suggest in Integrated Terminals"),
                    description: String(localized: """
                    Show ghost text in VS Code and Cursor integrated terminals. Off by default so suggestions stay out of shell \
                    prompts; the editor and chat in the same window keep suggesting either way.
                    """), systemImage: "terminal"
                )
            }
            .settingsItem(.suggestInIntegratedTerminals)
        }
    }

    private func presentAppPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK, let url = panel.url,
              let metadata = ApplicationBundleMetadata(appURL: url) else { return }
        // Keep a newly added app across launches even if every choice still inherits its default.
        suggestionSettings.addPerAppShortcutApp(bundleIdentifier: metadata.bundleIdentifier, displayName: metadata.displayName)
        selectedApp = entries.first { $0.bundleIdentifier == metadata.bundleIdentifier }
    }
}

/// One app surfaced from the running-process list. Captures the icon up front so the
/// row doesn't have to hit NSWorkspace again on every redraw.
private struct RunningAppSuggestion: Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let icon: NSImage

    var id: String { bundleIdentifier }

    /// Snapshot the user-launched apps (`activationPolicy == .regular`) excluding Lingrove itself,
    /// sorted alphabetically for the unified application list.
    static func collect() -> [RunningAppSuggestion] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let candidates = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != ownBundleIdentifier }

        var seen = Set<String>()
        let suggestions: [RunningAppSuggestion] = candidates.compactMap { app in
            guard let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty else {
                return nil
            }
            guard seen.insert(bundleIdentifier).inserted else { return nil }
            let displayName = app.localizedName ?? bundleIdentifier
            let icon = app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            return RunningAppSuggestion(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                icon: icon
            )
        }
        return suggestions
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

    }
}
