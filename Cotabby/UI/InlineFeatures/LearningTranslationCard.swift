import AppKit
import SwiftUI

/// Shows the exact source scope and its target-language expression from the coordinator.
/// Confirmation remains an explicit click; the coordinator consumes Return while this card is
/// visible, so opening a preview never makes the keyboard's normal confirm key edit the field.
struct LearningTranslationCard: View {
    let source: String
    let english: String
    let message: String
    let sourceLanguage: LearningLanguage?
    let targetLanguage: LearningLanguage
    let isSentence: Bool
    let accept: (() -> Void)?
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sourceLanguage.map {
                String(localized: "\($0.label) → \(targetLanguage.label)", table: "Learning",
                    comment: "Language direction shown at the top of a translation preview.")
            } ?? String(localized: "Expression preview · target: \(targetLanguage.label)", table: "Learning",
                comment: "Preview header when the source language is unavailable; the target language name is inserted."))
                .font(.headline)
            Text(isSentence
                ? String(localized: "Scope: sentence at the caret", table: "Learning",
                    comment: "Identifies that the preview covers the sentence containing the caret.")
                : String(localized: "Scope: current selection", table: "Learning",
                    comment: "Identifies that the preview covers the selected source text."))
                .font(.caption).foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sourceLanguage.map {
                            String(localized: "Source (\($0.label))", table: "Learning",
                                comment: "Label above the source text, with its detected language.")
                        } ?? String(localized: "Source", table: "Learning", comment: "Label above the original source text."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(source).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Target expression (\(targetLanguage.label))", table: "Learning",
                            comment: "Label above the target-language translation."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(english)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if let accept {
                    Button(isSentence
                        ? String(localized: "Replace sentence", table: "Learning",
                            comment: "Confirms replacing the original sentence with its translation.")
                        : String(localized: "Replace selection", table: "Learning",
                            comment: "Confirms replacing the selected source text with its translation."),
                        action: accept)
                }
                if !english.isEmpty {
                    Button(String(localized: "Copy target expression", table: "Learning",
                        comment: "Copies the translated target expression to the clipboard.")) { copy(english) }
                }
                if !source.isEmpty {
                    Button(String(localized: "Copy source text", table: "Learning",
                        comment: "Copies the original source text to the clipboard.")) { copy(source) }
                }
                Button(String(localized: "Cancel · Esc", table: "Learning",
                    comment: "Closes the translation preview; Escape also cancels it."), action: cancel)
            }
        }.padding(16).frame(width: 388, height: 298)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
