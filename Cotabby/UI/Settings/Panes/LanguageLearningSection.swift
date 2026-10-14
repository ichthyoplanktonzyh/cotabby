import SwiftUI

/// Presents the cross-language learning controls from the app-owned settings model.
/// The shared settings object owns persistence; this section only edits language choices,
/// the two independent model profiles, and the detail shortcut.
struct LanguageLearningSection: View {
    @ObservedObject var settings: LanguageLearningSettings
    let suggestionSettings: SuggestionSettingsModel
    var configureModel: (LearningModelRole) -> Void = { _ in }
    @State private var recording = false
    @State private var sourceLanguagesExpanded = false

    var body: some View {
        Section(String(localized: "Language Learning", table: "Learning",
            comment: "Settings section for language translation and sentence-learning controls.")) {
            Toggle(String(localized: "Enable expression translation", table: "Learning",
                comment: "Turns explicit translation previews on or off."),
                isOn: $settings.translationEnabled)
            Toggle(String(localized: "Show sentence expressions after a pause", table: "Learning",
                comment: "Automatically translates newly typed complete sentences after a brief pause."),
                isOn: $settings.sentencePreviewEnabled)
                .disabled(!settings.translationEnabled)
            translationControls
            Text(String(localized: """
            Type as usual and confirm text with your input method. After a pause, the target expression appears beside the field. When \
            chunk alignment is enabled, aligned meaning appears shortly afterward. Use the shortcut to expand the source and \
            translation. Click a highlighted match to inspect both sides, or double-click an expression to open its dictionary entry. \
            No specific input method or ABC keyboard is required. Translation and chunk alignment use separate models, each with a \
            local GGUF or its own endpoint.
            """,
                table: "Learning",
                comment: """
                Overview of automatic sentence translation, chunk alignment, dictionary lookup, input-method compatibility, and the \
                separate model choices.
                """))
                .font(.caption).foregroundStyle(.secondary)
            Text(String(localized: """
            Learning requests contain the current source text and language direction. Chunk-alignment requests also include the \
            displayed translation. They never include screen content, clipboard content, or typing history.
            """,
                table: "Learning", comment: """
                Privacy disclosure describing the data sent for learning requests and context that is never included.
                """))
                .font(.caption).foregroundStyle(.secondary)
            LearningModelSummaryRow(title: String(localized: "Translation model", table: "Learning",
                comment: "Name of the model profile used for translation."), profile: settings.translation) {
                configureModel(.translation)
            }
            Toggle(String(localized: "Enable chunk alignment", table: "Learning",
                comment: "Turns source-to-translation phrase alignment on or off."),
                isOn: $settings.analysisEnabled)
                .disabled(!settings.translationEnabled)
            Text(String(localized: """
            You can still read the translation, compare it with the source, and look up words when chunk alignment is off. Matching \
            only identifies corresponding excerpts; it does not translate again or generate explanations.
            """,
                table: "Learning", comment: "Explains the independent chunk-alignment setting and what its model does."))
                .font(.caption).foregroundStyle(.secondary)
            LearningModelSummaryRow(title: String(localized: "Chunk alignment model", table: "Learning",
                comment: "Name of the model profile used to align source and target phrases."), profile: settings.analysis) {
                configureModel(.analysis)
            }
            HStack {
                Text(String(localized: "Expand learning details: \(settings.keyLabel)", table: "Learning",
                    comment: "Shows the configured keyboard shortcut that expands the sentence-learning card."))
                if recording {
                    KeyRecorderView(onKeyRecorded: { code, modifiers, label in
                        settings.keyCode = code
                        settings.modifiers = modifiers
                        settings.keyLabel = label
                        recording = false
                    }, onCancelled: { recording = false }, conflictChecker: conflict)
                } else {
                    Button(String(localized: "Change", table: "Learning",
                        comment: "Starts recording a new shortcut for the learning detail card.")) { recording = true }
                }
            }
            if settings.translationEnabled,
               let reason = conflict(settings.keyCode, settings.modifiers) {
                Text(String(localized: "This shortcut conflicts with \(reason). Choose a different key combination.", table: "Learning",
                    comment: "Explains why the learning shortcut cannot be used; the conflicting command name is inserted."))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text(String(localized: """
            Automatic preview processes only new text typed in the focused field after you enable it; moving to existing text never \
            sends it automatically. A pause starts the preview. Sentence-ending punctuation and line breaks define sentence \
            boundaries, and adding to the same sentence updates its preview. The learning overlay never edits source text; Tab and \
            Return still go to the editor, and Escape dismisses the overlay. When automatic preview is off, use the shortcut to \
            preview the current selection or sentence.
            """,
                table: "Learning", comment: """
                Explains when automatic preview runs, how sentence boundaries are detected, and how the overlay interacts with typing.
                """))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var translationControls: some View {
        Group {
            Picker(String(localized: "Target language", table: "Learning",
                comment: "Picker label for the language to translate into."),
                selection: $settings.targetLanguage) {
                ForEach(LearningLanguage.allCases) { Text($0.label).tag($0) }
            }
            DisclosureGroup(String(localized: "Source languages (optional; \(settings.sourceLanguages.count) selected)", table: "Learning",
                comment: "Disclosure label for source-language choices; the selected language count is inserted."),
                            isExpanded: sourceExpansionBinding) {
                ForEach(LearningLanguage.allCases) { language in
                    Toggle(language.label, isOn: Binding(
                        get: { settings.sourceLanguages.contains(language) },
                        set: { enabled in
                            settings.sourceLanguages.removeAll { $0 == language }
                            if enabled { settings.sourceLanguages.append(language) }
                        }
                    )).disabled(language == settings.targetLanguage)
                }
                Text(String(localized: """
                With one source language selected, translations follow that direction. With several selected, Lingrove detects the \
                language of each source; if it is uncertain, adjust the settings or select more text.
                """, table: "Learning", comment: "Explains fixed-direction translation versus automatic source-language detection."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
    }

    /// Expansion is presentation state, not a persisted language preference. Its height change
    /// reaches the grouped Form and outer ScrollView; animating that change can repeatedly alter
    /// the scroller's document proportions. Apply the transaction at the binding write so the
    /// parent layout receives it too, without changing animations in other settings controls.
    private var sourceExpansionBinding: Binding<Bool> {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return $sourceLanguagesExpanded.transaction(transaction)
    }

    private func conflict(_ code: UInt16, _ modifiers: ShortcutModifierMask) -> String? {
        if code == 36 || code == 76 || code == 53 || modifiers.isEmpty {
            return String(localized: "Use a shortcut with a modifier key; Enter and Escape are reserved.",
                table: "Learning", comment: "Validation message shown when a shortcut uses a reserved key or has no modifier.")
        }
        for action in ShortcutAction.allCases {
            if let conflict = suggestionSettings.conflictingShortcutName(
                keyCode: code, modifiers: modifiers, excluding: action, includingLearningShortcut: false
            ) {
                return conflict
            }
        }
        for override in suggestionSettings.perAppShortcutOverrides {
            if let conflict = suggestionSettings.conflictingPerAppShortcutName(
                forBundleIdentifier: override.bundleIdentifier, keyCode: code, modifiers: modifiers,
                excluding: .toggleTabby, includingLearningShortcut: false
            ) { return conflict }
        }
        return nil
    }
}

/// Writing shows the role's current selection and a route into Engine & Model. It observes the
/// app-owned profile, while the navigation owner performs the jump. No model services or editable
/// server/key fields live in this summary, so there is one configuration surface per task.
private struct LearningModelSummaryRow: View {
    let title: String
    @ObservedObject var profile: LearningModelSettings
    let configure: () -> Void

    var body: some View {
        LabeledContent {
            Button(String(localized: "Configure model", table: "Learning",
                comment: "Opens Engine & Model settings for this learning model profile."), action: configure)
                .help(String(localized: "Configure \(title) in Engine & Model", table: "Learning",
                    comment: "Tooltip for opening this learning model profile's configuration."))
                .accessibilityLabel(String(localized: "Configure \(title)", table: "Learning",
                    comment: "VoiceOver label for opening this learning model profile's configuration."))
        } label: {
            SettingsRowLabel(title: title, description: summary, systemImage: "shippingbox")
        }
    }

    private var summary: String {
        switch profile.backend {
        case .local:
            profile.localModel.isEmpty
                ? String(localized: "Local GGUF · no model selected", table: "Learning",
                    comment: "Summary shown when the local backend is selected but this task has no GGUF model.")
                : String(localized: "Local GGUF · \(profile.localModel)", table: "Learning",
                    comment: "Summary of the local GGUF backend and selected model filename.")
        case .endpoint:
            profile.endpointModel.isEmpty
                ? String(localized: "Endpoint · no model entered", table: "Learning",
                    comment: "Summary shown when the endpoint backend is selected but its model identifier is empty.")
                : String(localized: "Endpoint · \(profile.endpointModel)", table: "Learning",
                    comment: "Summary of the endpoint backend and user-configured model identifier.")
        }
    }
}
