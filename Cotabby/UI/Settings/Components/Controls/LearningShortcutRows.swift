import CoreGraphics
import SwiftUI

/// Translation's two independent commands borrow the existing recorder and conflict policy.
/// This editor appears only in Shortcuts; other panes show a summary/navigation action.
struct LearningShortcutRows: View {
    @ObservedObject var settings: LanguageLearningSettings
    @ObservedObject var suggestionSettings: SuggestionSettingsModel
    @ObservedObject var recording: ShortcutRecordingState

    var body: some View {
        Section(String(localized: "Translation", table: "Learning", comment: "Translation shortcuts section.")) {
            row(replacement: true)
            row(replacement: false)
        }
    }

    @ViewBuilder private func row(replacement: Bool) -> some View {
        LabeledContent {
            KeybindRow(
                label: replacement ? settings.replacementKeyLabel : settings.keyLabel,
                keyCode: CGKeyCode(replacement ? settings.replacementKeyCode : settings.keyCode),
                isRecording: recording.binding(for: replacement ? "translation.replace" : "translation.details"),
                onRecord: { code, modifiers, label in set(replacement, code, modifiers, label) },
                onReset: { set(replacement, 17, replacement ? [.control, .option] : [.option], replacement ? "⌃⌥T" : "⌥T") },
                resetLabel: String(localized: "Reset"), shouldShowReset: true,
                onClear: { set(replacement, UInt16.max, [], SuggestionSettingsModel.disabledKeyLabel) },
                clearLabel: String(localized: "Clear"),
                clearHelp: String(
                    localized: "Disable this shortcut", table: "Learning",
                    comment: "Unbinds a translation command."),
                conflictChecker: { code, modifiers in
                    suggestionSettings.learningShortcutConflict(keyCode: code, modifiers: modifiers, replacement: replacement)
                })
        } label: {
            SettingsRowLabel(
                title: replacement
                    ? String(
                        localized: "Replace preview translation", table: "Learning", comment: "Shortcut replacing the exact preview source."
                    )
                    : String(
                        localized: "Expand / collapse translation details", table: "Learning",
                        comment: "Shortcut toggling details or requesting an explicit preview."),
                description: replacement
                    ? String(
                        localized: "Writes a valid preview back to its saved sentence or selection. Never sends the message.",
                        table: "Learning",
                        comment: "Explains the scoped replacement command.")
                    : String(
                        localized: "Shows or hides details. Without a preview, requests the selected text or current sentence.",
                        table: "Learning",
                        comment: "Explains the explicit preview and detail command."),
                systemImage: replacement ? "arrow.triangle.2.circlepath" : "text.magnifyingglass")
        }
        if settings.translationEnabled,
           let reason = suggestionSettings.learningShortcutConflict(
            keyCode: replacement ? settings.replacementKeyCode : settings.keyCode,
            modifiers: replacement ? settings.replacementModifiers : settings.modifiers, replacement: replacement) {
            Text(String(localized: "This shortcut conflicts with \(reason). Choose a different key combination.", table: "Learning"))
                .font(.caption).foregroundStyle(.red)
        }
    }

    private func set(_ replacement: Bool, _ code: CGKeyCode, _ modifiers: ShortcutModifierMask, _ label: String) {
        if replacement {
            settings.replacementKeyCode = UInt16(clamping: code)
            settings.replacementModifiers = modifiers
            settings.replacementKeyLabel = label
        } else {
            settings.keyCode = UInt16(clamping: code)
            settings.modifiers = modifiers
            settings.keyLabel = label
        }
    }
}
