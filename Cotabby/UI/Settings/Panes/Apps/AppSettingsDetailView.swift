import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A presentation-only editor for one app. It observes the long-lived model and history store
/// supplied by AppsPaneView, and owns only confirmation state. Each row uses the same settings
/// labels, native pickers and shortcut controls as the rest of Settings.
struct AppSettingsDetailView: View {
    @ObservedObject var suggestionSettings: SuggestionSettingsModel
    @ObservedObject var typingHistory: TypingHistoryStore
    let bundleIdentifier: String
    let displayName: String
    let onBack: () -> Void
    @State private var isConfirmingDelete = false

    var body: some View {
        Section {
            Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
            HStack(spacing: 12) {
                Image(nsImage: AppIconCache.icon(for: bundleIdentifier))
                    .resizable().frame(width: 36, height: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName).font(.title3.weight(.semibold))
                    Text(bundleIdentifier).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        Section(String(localized: "Completions", table: "Learning")) {
            Picker(selection: completionsBinding) {
                defaultAndOffChoices
            } label: {
                SettingsRowLabel(
                    title: String(localized: "Enable Completions", table: "Learning"),
                    description: String(localized: "Turn suggestions off in this app.", table: "Learning"),
                    systemImage: "text.cursor"
                )
            }
            Picker(selection: behaviorBinding(\.midLineCompletions)) {
                defaultAndOffChoices
                Text("On", tableName: "Learning").tag(PerAppToggle.on)
            } label: {
                SettingsRowLabel(
                    title: String(localized: "Mid-Line Completions", table: "Learning"),
                    description: String(
                        localized: "Allow new suggestions when text follows the caret on the same line.", table: "Learning"
                    ),
                    systemImage: "text.insert"
                )
            }
            Picker(selection: behaviorBinding(\.autocorrect)) {
                defaultAndOffChoices
                Text("On", tableName: "Learning").tag(PerAppToggle.on)
            } label: {
                SettingsRowLabel(
                    title: String(localized: "Autocorrect"),
                    description: String(localized: """
                    On keeps the global auto-fix choice; Off disables typo checks in this app.
                    """, table: "Learning"), systemImage: "textformat.abc.dottedunderline"
                )
            }
        }
        Section("Keys") {
            PerAppShortcutRowsView(
                suggestionSettings: suggestionSettings, bundleIdentifier: bundleIdentifier, displayName: displayName
            )
        }
        Section {
            SettingsRowLabel(
                title: String(localized: "Instructions for This App", table: "Learning"),
                description: String(localized: """
                Language, tone, or terminology for suggestions in this app. Sent to the selected engine.
                """, table: "Learning"), systemImage: "text.alignleft"
            )
            TextEditor(text: instructionsBinding)
                .font(.body)
                .frame(minHeight: 100)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                .accessibilityLabel(String(localized: "Instructions for This App", table: "Learning"))
            Text(verbatim: "\(behavior.instructions.count) / \(PerAppBehavior.maximumInstructionCharacters)")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        Section("Typing History") {
            Picker(selection: collectBinding) { defaultAndOffChoices } label: {
                SettingsRowLabel(
                    title: String(localized: "Collect Inputs", table: "Learning"),
                    description: String(localized: "Follow global history collection, or stop recording in this app.", table: "Learning"),
                    systemImage: "clock.arrow.circlepath"
                )
            }
            .disabled(typingHistory.isDeletingRecords)
            LabeledContent {
                Button(String(localized: "Delete"), role: .destructive) { isConfirmingDelete = true }
                    .disabled(inputCount == 0 || typingHistory.isDeletingRecords)
            } label: { Text("\(inputCount) entries stored") }
            if typingHistory.isDeletingRecords {
                ProgressView().controlSize(.small)
            }
            if let failure = typingHistory.appDeletionFailure, failure.bundleIdentifier == bundleIdentifier {
                SettingsCalloutView(callout: .init(tone: .warning, message: failure.message))
            }
        }
        .confirmationDialog(
            String(localized: "Delete History for This App?", table: "Learning"), isPresented: $isConfirmingDelete
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                Task { await typingHistory.deleteRecords(forBundleIdentifier: bundleIdentifier) }
            }
        } message: {
            Text("Other apps’ history is kept.", tableName: "Learning")
        }
        Section {
            Button(String(localized: "Reset App Settings", table: "Learning"), action: resetToDefaults)
                .disabled(typingHistory.isDeletingRecords)
        }
    }

    @ViewBuilder private var defaultAndOffChoices: some View {
        Text("Use Global").tag(PerAppToggle.useDefault)
        Text("Off", tableName: "Learning").tag(PerAppToggle.off)
    }

    private var behavior: PerAppBehavior { suggestionSettings.perAppBehavior(forBundleIdentifier: bundleIdentifier) }
    private var inputCount: Int { typingHistory.recordCountsByApp[bundleIdentifier] ?? 0 }

    private var completionsBinding: Binding<PerAppToggle> {
        Binding(
            get: { suggestionSettings.isApplicationDisabled(bundleIdentifier: bundleIdentifier) ? .off : .useDefault },
            set: { choice in
                if choice == .off {
                    suggestionSettings.disableApplication(bundleIdentifier: bundleIdentifier, displayName: displayName)
                } else { suggestionSettings.removeDisabledApplication(bundleIdentifier: bundleIdentifier) }
            }
        )
    }

    private func behaviorBinding(_ keyPath: WritableKeyPath<PerAppBehavior, PerAppToggle>) -> Binding<PerAppToggle> {
        Binding(get: { behavior[keyPath: keyPath] }, set: { value in
            suggestionSettings.updatePerAppBehavior(bundleIdentifier: bundleIdentifier, displayName: displayName) {
                $0[keyPath: keyPath] = value
            }
        })
    }

    private var instructionsBinding: Binding<String> {
        Binding(get: { behavior.instructions }, set: { text in
            suggestionSettings.updatePerAppBehavior(bundleIdentifier: bundleIdentifier, displayName: displayName) {
                $0.instructions = text
            }
        })
    }

    private var collectBinding: Binding<PerAppToggle> {
        Binding(
            get: { typingHistory.preferences.excludedBundleIdentifiers.contains(bundleIdentifier) ? .off : .useDefault },
            set: { typingHistory.setExcluded(bundleIdentifier, excluded: $0 == .off) }
        )
    }

    private func resetToDefaults() {
        suggestionSettings.removeDisabledApplication(bundleIdentifier: bundleIdentifier)
        suggestionSettings.removePerAppOverride(bundleIdentifier: bundleIdentifier)
        typingHistory.setExcluded(bundleIdentifier, excluded: false)
    }
}

/// App icons and names looked up once per bundle identifier. `NSWorkspace` lookups hit Launch
/// Services; caching keeps a long app list from repeating them on every redraw.
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func icon(for bundleIdentifier: String) -> NSImage {
        if let cached = icons[bundleIdentifier] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        icons[bundleIdentifier] = icon
        return icon
    }

    static func displayName(for bundleIdentifier: String) -> String {
        if let cached = names[bundleIdentifier] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleIdentifier
        names[bundleIdentifier] = name
        return name
    }
}
