import Foundation

/// Resolves the effective suggestion behavior for the app being typed in.
///
/// Every per-app choice is "follow the global setting, or force on/off" (`PerAppToggle`). Keeping
/// that rule in one pure type, like `ShortcutResolver` does for accept keys, means the request
/// factory, the typo gate, and the generation gate can never disagree about what "Default" means.
enum PerAppSettingsResolver {
    /// Whether a new suggestion may start while text follows the caret on its line. The global
    /// default is on: Cotabby already shows those suggestions as a card under the caret.
    static func allowsMidLineCompletions(bundleIdentifier: String?, settings: SuggestionSettingsSnapshot) -> Bool {
        behavior(bundleIdentifier, settings)?.midLineCompletions.resolve(default: true) ?? true
    }

    /// The typo gate's switches in this app. Turning autocorrect off disables all three, so a word
    /// that looks misspelled neither hides the completion nor gets a correction. Turning it on
    /// enables hiding and offering; automatic fixing stays the user's global choice because it
    /// edits text without asking.
    static func typoSettings(bundleIdentifier: String?, settings: SuggestionSettingsSnapshot) -> TypoGate.Settings {
        let global = TypoGate.Settings(
            suppressCompletionsOnTypo: settings.suppressCompletionsOnTypo,
            offerTypoCorrections: settings.offerTypoCorrections,
            automaticallyFixTypos: settings.automaticallyFixTypos
        )
        switch behavior(bundleIdentifier, settings)?.autocorrect ?? .useDefault {
        case .useDefault:
            return global
        case .on:
            return TypoGate.Settings(
                suppressCompletionsOnTypo: true,
                offerTypoCorrections: true,
                automaticallyFixTypos: settings.automaticallyFixTypos
            )
        case .off:
            return TypoGate.Settings(suppressCompletionsOnTypo: false, offerTypoCorrections: false, automaticallyFixTypos: false)
        }
    }

    /// Whether autocorrect is effectively on, for the "Default (on/off)" label in Settings.
    static func globalAutocorrectIsOn(_ settings: SuggestionSettingsSnapshot) -> Bool {
        settings.suppressCompletionsOnTypo && settings.offerTypoCorrections
    }

    /// App notes keep their own request field and prompt budget. Concatenating them behind global
    /// Extended Context would silently discard a valid saved instruction at the old section cap.
    static func instructions(bundleIdentifier: String?, settings: SuggestionSettingsSnapshot) -> String? {
        let notes = (behavior(bundleIdentifier, settings)?.instructions ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.isEmpty ? nil : notes
    }

    private static func behavior(_ bundleIdentifier: String?, _ settings: SuggestionSettingsSnapshot) -> PerAppBehavior? {
        guard let bundleIdentifier else { return nil }
        return settings.perAppBehaviors[bundleIdentifier]
    }
}
