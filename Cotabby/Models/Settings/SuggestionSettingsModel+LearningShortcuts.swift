import CoreGraphics
import Foundation

/// One conflict policy serves the two learning rows and the existing event-tap arbiter. A settings
/// recorder checks every configured app; dispatch checks only the currently focused app's bindings.
extension SuggestionSettingsModel {
    func learningShortcutConflict(
        keyCode: CGKeyCode, modifiers: ShortcutModifierMask, replacement: Bool,
        bundleIdentifier: String? = nil
    ) -> String? {
        guard keyCode != Self.disabledKeyCode else { return nil }
        if [36, 76, 53].contains(keyCode) || modifiers.isEmpty {
            return String(localized: "Use a shortcut with a modifier key; Enter and Escape are reserved.", table: "Learning")
        }
        let otherCode = replacement ? languageLearning.keyCode : languageLearning.replacementKeyCode
        let otherModifiers = replacement ? languageLearning.modifiers : languageLearning.replacementModifiers
        if keyCode == otherCode, modifiers == otherModifiers {
            return String(localized: "Translation shortcut", table: "Learning", comment: "Conflicting translation action name.")
        }
        let apps = bundleIdentifier.map { [$0] } ?? ([""] + perAppShortcutOverrides.map(\.bundleIdentifier))
        for app in apps {
            if let conflict = conflictingPerAppShortcutName(
                forBundleIdentifier: app, keyCode: keyCode, modifiers: modifiers,
                excluding: .toggleTabby, includingLearningShortcut: false) {
                return conflict
            }
        }
        return nil
    }
}
