import AppKit
import SwiftUI

/// The unified shortcut destination reuses the existing per-app rows and app-list projection.
/// Selection is temporary UI state; durable overrides remain owned by SuggestionSettingsModel.
struct AppShortcutSection: View {
    @ObservedObject var settings: SuggestionSettingsModel
    @ObservedObject var recording: ShortcutRecordingState
    @State private var selected = ""
    @State private var running: [String] = []

    init(settings: SuggestionSettingsModel, recording: ShortcutRecordingState, selectedApp: String? = nil) {
        self.settings = settings
        self.recording = recording
        _selected = State(initialValue: selectedApp ?? "")
    }

    private var apps: [AppSettingsEntry] {
        AppSettingsList.entries(
            inputCounts: [:], disabledRules: settings.disabledAppRules,
            overrides: settings.perAppShortcutOverrides, excludedFromHistory: [],
            addedBundleIdentifiers: running + (selected.isEmpty ? [] : [selected]),
            displayName: AppIconCache.displayName)
    }

    var body: some View {
        Section(String(localized: "Per-App Shortcuts")) {
            HStack {
                Picker(
                    String(localized: "App", table: "Learning", comment: "Application whose shortcut overrides are edited."),
                    selection: $selected
                ) {
                    Text(String(localized: "Choose an app", table: "Learning", comment: "Empty app shortcut selection.")).tag("")
                    ForEach(apps) { Text($0.displayName).tag($0.bundleIdentifier) }
                }
                Button(String(localized: "Add App…")) {
                    guard let app = ApplicationBundlePicker.choose() else { return }
                    settings.addPerAppShortcutApp(bundleIdentifier: app.bundleIdentifier, displayName: app.displayName)
                    selected = app.bundleIdentifier
                }
            }
            if let app = apps.first(where: { $0.bundleIdentifier == selected }) {
                PerAppShortcutRowsView(suggestionSettings: settings, recording: recording, bundleIdentifier: app.bundleIdentifier, displayName: app.displayName)
            }
        }
        .onChange(of: selected) { _, _ in recording.stop() }
        .onAppear {
            running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier).filter { $0 != Bundle.main.bundleIdentifier }
        }
    }
}
