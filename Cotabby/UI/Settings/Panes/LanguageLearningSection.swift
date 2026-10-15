import SwiftUI

/// Presents the cross-language learning controls from the app-owned settings model.
/// The shared settings object owns persistence; this section only edits language choices,
/// the two independent model profiles, and the detail shortcut.
struct LanguageLearningSection: View {
    @ObservedObject var settings: LanguageLearningSettings
    let suggestionSettings: SuggestionSettingsModel
    var configureModel: (LearningModelRole) -> Void = { _ in }
    var openShortcuts: () -> Void = {}
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
            Translation sends the target and optional draft excerpts from the same field to the chosen engine. Alignment receives \
            only the target and translation. Screens, clipboard and history are excluded.
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
            LabeledContent {
                Button(String(localized: "Manage in Shortcuts", table: "Learning"), action: openShortcuts)
            } label: {
                Text(
                    String(
                        localized: "Translation shortcuts", table: "Learning", comment: "Read-only route to the central shortcut editor."))
            }
            Text(String(localized: """
            After a pause, preview the current sentence. Use Replace to write it back, or select text to translate a larger range. \
            The details shortcut opens a preview or toggles details. Tab and Return stay with the editor; Escape dismisses.
            """,
                table: "Learning", comment: """
                Explains when automatic preview runs, how sentence boundaries are detected, and how the overlay interacts with typing.
                """))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var translationControls: some View {
        Group {
            Picker(
                String(
                    localized: "Translation reference", table: "Learning",
                    comment: "Selects extra translation context without changing the target."),
                selection: $settings.referenceMode
            ) {
                Text(String(localized: "Current sentence", table: "Learning", comment: "Translate without extra draft reference.")).tag(
                    LearningReferenceMode.currentSentence)
                Text(String(localized: "Draft context", table: "Learning", comment: "Use budgeted reference from the current draft.")).tag(
                    LearningReferenceMode.draft)
            }
            Text(
                String(
                    localized:
                        "The target remains the current sentence or your selection. Only reference text may be shortened to fit the budget.",
                    table: "Learning", comment: "Distinguishes immutable translation target from bounded reference.")
            )
            .font(.caption).foregroundStyle(.secondary)
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
