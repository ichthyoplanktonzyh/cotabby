import Combine
import Foundation

/// Owned once by SuggestionSettingsModel. The model persists only the sentence translation preferences; legacy vocabulary keys are intentionally left untouched and never read.
/// UI observes this object while each service request captures its immutable snapshot.
@MainActor
final class LanguageLearningSettings: ObservableObject {
    private let defaults: UserDefaults
    let translation: LearningModelSettings
    let analysis: LearningModelSettings
    @Published var analysisEnabled: Bool {
        didSet { defaults.set(analysisEnabled, forKey: "learningAnalysisEnabled") }
    }

    @Published var translationEnabled: Bool {
        didSet { defaults.set(translationEnabled, forKey: "learningTranslationEnabled") }
    }
    var model: String {
        get { translation.endpointModel }
        set {
            translation.backend = .endpoint
            translation.endpointModel = newValue
            defaults.set(newValue, forKey: "learningInstructionModel")
        }
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
    @Published var sentencePreviewEnabled: Bool {
        didSet { defaults.set(sentencePreviewEnabled, forKey: "learningSentencePreviewEnabled") }
    }
    @Published var referenceMode: LearningReferenceMode {
        didSet { defaults.set(referenceMode.rawValue, forKey: "learningReferenceMode") }
    }
    @Published var replacementKeyCode: UInt16 { didSet { saveReplacementShortcut() } }
    @Published var replacementModifiers: ShortcutModifierMask { didSet { saveReplacementShortcut() } }
    @Published var replacementKeyLabel: String { didSet { saveReplacementShortcut() } }

    /// A generation snapshots all settings that can change its prompt or eligibility. The
    /// publisher lets coordinators cancel work as soon as one of those values is edited.
    var changes: AnyPublisher<Void, Never> {
        Publishers.MergeMany([
            $translationEnabled.map { _ in () }.eraseToAnyPublisher(),
            $sourceLanguages.map { _ in () }.eraseToAnyPublisher(),
            $targetLanguage.map { _ in () }.eraseToAnyPublisher(),
            $sentencePreviewEnabled.map { _ in () }.eraseToAnyPublisher(),
                $referenceMode.map { _ in () }.eraseToAnyPublisher()
            ].map { $0.dropFirst().eraseToAnyPublisher() } + [translation.changes]).eraseToAnyPublisher()
    }

    /// Bindings affect presentation, not the meaning of a generated translation. Repaint labels
    /// without discarding the current source or cancelling a valid response.
    var shortcutChanges: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            [
                $keyCode.map { _ in () }.eraseToAnyPublisher(),
                $modifiers.map { _ in () }.eraseToAnyPublisher(),
                $keyLabel.map { _ in () }.eraseToAnyPublisher(),
                $replacementKeyCode.map { _ in () }.eraseToAnyPublisher(),
                $replacementModifiers.map { _ in () }.eraseToAnyPublisher(),
                $replacementKeyLabel.map { _ in () }.eraseToAnyPublisher()
            ].map { $0.dropFirst().eraseToAnyPublisher() }
        ).eraseToAnyPublisher()
    }

    var analysisChanges: AnyPublisher<Void, Never> {
        Publishers.Merge($analysisEnabled.dropFirst().map { _ in () }, analysis.changes).eraseToAnyPublisher()
    }

    var snapshot: LearningSettingsSnapshot {
        .init(
            translationEnabled: translationEnabled,
            model: translation.snapshot.endpointModel,
            sentencePreviewEnabled: sentencePreviewEnabled,
            sourceLanguages: sourceLanguages,
            targetLanguage: targetLanguage,
            translationModel: translation.snapshot, referenceMode: referenceMode
        )
    }

    /// App-wide reset keeps the shortcut contract while disabling both explicit language features.
    func resetToDefaults() {
        translationEnabled = false
        sentencePreviewEnabled = true
        referenceMode = .currentSentence
        replacementKeyCode = 17; replacementModifiers = [.control, .option]; replacementKeyLabel = "⌃⌥T"
        sourceLanguages = [.chinese]
        targetLanguage = .english
        model = ""
        translation.reset()
        analysisEnabled = false
        analysis.reset()
        keyCode = 17
        modifiers = [.option]
        keyLabel = "⌥T"
    }

    init(defaults: UserDefaults = .standard,
         translationCredentials: (any OpenAICompatibleCredentialStoring)? = nil,
         analysisCredentials: (any OpenAICompatibleCredentialStoring)? = nil) {
        self.defaults = defaults
        translation = LearningModelSettings(role: .translation, defaults: defaults, credentials: translationCredentials)
        analysis = LearningModelSettings(role: .analysis, defaults: defaults, credentials: analysisCredentials)
        analysisEnabled = defaults.bool(forKey: "learningAnalysisEnabled")
        translationEnabled = defaults.bool(forKey: "learningTranslationEnabled")
        sourceLanguages = defaults.stringArray(forKey: "learningSourceLanguages")?
            .compactMap(LearningLanguage.init(rawValue:)) ?? [.chinese]
        targetLanguage = LearningLanguage(rawValue: defaults.string(forKey: "learningTargetLanguage") ?? "en")
            ?? .english
        sentencePreviewEnabled = defaults.object(forKey: "learningSentencePreviewEnabled") as? Bool ?? true
        referenceMode = LearningReferenceMode(rawValue: defaults.string(forKey: "learningReferenceMode") ?? "") ?? .currentSentence
        replacementKeyCode = UInt16(clamping: defaults.object(forKey: "learningReplacementKey") as? Int ?? 17)
        replacementModifiers = ShortcutModifierMask(
            rawValue: UInt32(
                clamping:
                    defaults.object(forKey: "learningReplacementModifiers") as? Int ?? 12))
        replacementKeyLabel = defaults.string(forKey: "learningReplacementLabel") ?? "⌃⌥T"
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

    private func saveReplacementShortcut() {
        defaults.set(Int(replacementKeyCode), forKey: "learningReplacementKey")
        defaults.set(Int(replacementModifiers.rawValue), forKey: "learningReplacementModifiers")
        defaults.set(replacementKeyLabel, forKey: "learningReplacementLabel")
    }
}

/// Immutable behavior boundary retained by one generation. Equality rejects a reply after any
/// learning preference change that could make the result stale.
nonisolated struct LearningSettingsSnapshot: Equatable, Sendable {
    let translationEnabled: Bool
    let model: String
    var sentencePreviewEnabled: Bool = true
    let sourceLanguages: [LearningLanguage]
    let targetLanguage: LearningLanguage
    var translationModel: LearningModelSnapshot? = nil
    var referenceMode: LearningReferenceMode = .currentSentence
}
