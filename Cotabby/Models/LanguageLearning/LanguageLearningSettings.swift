import Combine
import Foundation

/// Owned once by SuggestionSettingsModel. The model persists only the remaining translation and
/// hint preferences; legacy vocabulary keys are intentionally left untouched and never read.
/// UI observes this object while each service request captures its immutable snapshot.
@MainActor
final class LanguageLearningSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var translationEnabled: Bool {
        didSet { defaults.set(translationEnabled, forKey: "learningTranslationEnabled") }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: "learningInstructionModel") }
    }
    @Published var keyCode: UInt16 {
        didSet { defaults.set(Int(keyCode), forKey: "learningTranslationKey") }
    }
    @Published var modifiers: ShortcutModifierMask {
        didSet { defaults.set(Int(modifiers.rawValue), forKey: "learningTranslationModifiers") }
    }
    @Published var keyLabel: String {
        didSet { defaults.set(keyLabel, forKey: "learningTranslationLabel") }
    }
    @Published var sourceLanguages: [LearningLanguage] {
        didSet { defaults.set(sourceLanguages.map(\.rawValue), forKey: "learningSourceLanguages") }
    }
    @Published var targetLanguage: LearningLanguage {
        didSet { defaults.set(targetLanguage.rawValue, forKey: "learningTargetLanguage") }
    }
    @Published var hintsEnabled: Bool {
        didSet { defaults.set(hintsEnabled, forKey: "learningHintsEnabled") }
    }
    @Published var sentencePreviewEnabled: Bool {
        didSet { defaults.set(sentencePreviewEnabled, forKey: "learningSentencePreviewEnabled") }
    }

    /// A generation snapshots all settings that can change its prompt or eligibility. The
    /// publisher lets coordinators cancel work as soon as one of those values is edited.
    var changes: AnyPublisher<Void, Never> {
        Publishers.MergeMany([
            $translationEnabled.map { _ in () }.eraseToAnyPublisher(),
            $sourceLanguages.map { _ in () }.eraseToAnyPublisher(),
            $targetLanguage.map { _ in () }.eraseToAnyPublisher(),
            $hintsEnabled.map { _ in () }.eraseToAnyPublisher(),
            $sentencePreviewEnabled.map { _ in () }.eraseToAnyPublisher(),
            $model.map { _ in () }.eraseToAnyPublisher()
        ].map { $0.dropFirst().eraseToAnyPublisher() }).eraseToAnyPublisher()
    }

    var snapshot: LearningSettingsSnapshot {
        .init(
            translationEnabled: translationEnabled,
            hintsEnabled: hintsEnabled,
            model: model,
            sentencePreviewEnabled: sentencePreviewEnabled,
            sourceLanguages: sourceLanguages,
            targetLanguage: targetLanguage
        )
    }

    /// App-wide reset keeps the shortcut contract while disabling both explicit language features.
    func resetToDefaults() {
        translationEnabled = false
        hintsEnabled = false
        sentencePreviewEnabled = true
        sourceLanguages = [.chinese]
        targetLanguage = .english
        model = ""
        keyCode = 17
        modifiers = [.option]
        keyLabel = "⌥T"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        translationEnabled = defaults.bool(forKey: "learningTranslationEnabled")
        model = defaults.string(forKey: "learningInstructionModel") ?? ""
        sourceLanguages = defaults.stringArray(forKey: "learningSourceLanguages")?
            .compactMap(LearningLanguage.init(rawValue:)) ?? [.chinese]
        targetLanguage = LearningLanguage(rawValue: defaults.string(forKey: "learningTargetLanguage") ?? "en")
            ?? .english
        hintsEnabled = defaults.bool(forKey: "learningHintsEnabled")
        sentencePreviewEnabled = defaults.object(forKey: "learningSentencePreviewEnabled") as? Bool ?? true
        keyCode = UInt16(clamping: defaults.object(forKey: "learningTranslationKey") as? Int ?? 17)
        modifiers = ShortcutModifierMask(
            rawValue: UInt32(clamping: defaults.object(forKey: "learningTranslationModifiers") as? Int ?? 9)
        )
        keyLabel = defaults.string(forKey: "learningTranslationLabel") ?? "⌃⌘T"
        // Migrate only our old default; custom bindings remain the user's choice.
        if keyCode == 17, modifiers == [.command, .control], keyLabel == "⌃⌘T" {
            modifiers = [.option]
            keyLabel = "⌥T"
            defaults.set(Int(modifiers.rawValue), forKey: "learningTranslationModifiers")
            defaults.set(keyLabel, forKey: "learningTranslationLabel")
        }
    }
}

/// Immutable behavior boundary retained by one generation. Equality rejects a reply after any
/// learning preference change that could make the result stale.
nonisolated struct LearningSettingsSnapshot: Equatable, Sendable {
    let translationEnabled: Bool
    let hintsEnabled: Bool
    let model: String
    var sentencePreviewEnabled: Bool = true
    let sourceLanguages: [LearningLanguage]
    let targetLanguage: LearningLanguage
}
