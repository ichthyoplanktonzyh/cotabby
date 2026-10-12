import Foundation
import Testing
@testable import Cotabby

/// Verifies the durable settings boundary without reading or mutating the developer's real
/// preferences. Legacy vocabulary keys are seeded separately to prove the reduced model ignores
/// them while preserving their stored values.
@Suite
@MainActor
struct LanguageLearningSettingsTests {
    @Test
    func oldDefaultShortcutMigratesButCustomShortcutIsPreserved() throws {
        let (suiteName, defaults) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(17, forKey: "learningTranslationKey")
        defaults.set(Int(ShortcutModifierMask([.command, .control]).rawValue), forKey: "learningTranslationModifiers")
        defaults.set("⌃⌘T", forKey: "learningTranslationLabel")
        let migrated = LanguageLearningSettings(defaults: defaults)
        #expect(migrated.modifiers == [.option])
        #expect(migrated.keyLabel == "⌥T")
        migrated.modifiers = [.command, .option]
        migrated.keyLabel = "⌥⌘T"
        migrated.sentencePreviewEnabled = false
        let restored = LanguageLearningSettings(defaults: defaults)
        #expect(restored.modifiers == [.command, .option])
        #expect(restored.keyLabel == "⌥⌘T")
        #expect(!restored.sentencePreviewEnabled)
    }

    @Test
    func remainingLearningPreferencesAreOffByDefault() async throws {
        let (suiteName, defaults) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = LanguageLearningSettings(defaults: defaults)

        #expect(!settings.translationEnabled)
        #expect(!settings.hintsEnabled)
        #expect(settings.model.isEmpty)
        #expect(settings.sourceLanguages == [.chinese])
        #expect(settings.targetLanguage == .english)
        #expect(settings.keyCode == 17)
        #expect(settings.modifiers == [.option])
        #expect(settings.keyLabel == "⌥T")
        #expect(settings.sentencePreviewEnabled)
    }

    @Test
    func oldVocabularyPreferencesAreIgnoredWithoutDeletingTheirValues() async throws {
        let (suiteName, defaults) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyProfile = Data(#"[{"language":"en","completionEnabled":true,"text":"old words"}]"#.utf8)
        defaults.set(true, forKey: "learningVocabularyEnabled")
        defaults.set(true, forKey: "learningTranslationVocabularyEnabled")
        defaults.set("old words", forKey: "learningVocabulary")
        defaults.set(legacyProfile, forKey: "learningVocabularyProfiles")

        let settings = LanguageLearningSettings(defaults: defaults)

        #expect(!settings.translationEnabled)
        #expect(!settings.hintsEnabled)
        #expect(settings.model.isEmpty)
        #expect(defaults.bool(forKey: "learningVocabularyEnabled"))
        #expect(defaults.bool(forKey: "learningTranslationVocabularyEnabled"))
        #expect(defaults.string(forKey: "learningVocabulary") == "old words")
        #expect(defaults.data(forKey: "learningVocabularyProfiles") == legacyProfile)
    }

    @Test(arguments: [[false, false], [false, true], [true, false], [true, true]])
    func persistsTranslationAndHintSwitchesIndependently(_ switches: [Bool]) async throws {
        let (suiteName, defaults) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = LanguageLearningSettings(defaults: defaults)
        settings.translationEnabled = switches[0]
        settings.hintsEnabled = switches[1]

        let restored = LanguageLearningSettings(defaults: defaults)

        #expect(restored.translationEnabled == switches[0])
        #expect(restored.hintsEnabled == switches[1])
        #expect(defaults.bool(forKey: "learningTranslationEnabled") == switches[0])
        #expect(defaults.bool(forKey: "learningHintsEnabled") == switches[1])
    }

    @Test
    func persistsLanguagesModelAndShortcutAcrossRelaunch() async throws {
        let (suiteName, defaults) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = LanguageLearningSettings(defaults: defaults)
        settings.translationEnabled = true
        settings.hintsEnabled = true
        settings.sourceLanguages = [.spanish, .chinese, .arabic]
        settings.targetLanguage = .japanese
        settings.model = "learning-instruction-model"
        settings.keyCode = 42
        settings.modifiers = [.command, .option]
        settings.keyLabel = "⌥⌘L"

        let restored = LanguageLearningSettings(defaults: defaults)

        #expect(restored.translationEnabled)
        #expect(restored.hintsEnabled)
        #expect(restored.sourceLanguages == [.spanish, .chinese, .arabic])
        #expect(restored.targetLanguage == .japanese)
        #expect(restored.model == "learning-instruction-model")
        #expect(restored.keyCode == 42)
        #expect(restored.modifiers == [.command, .option])
        #expect(restored.keyLabel == "⌥⌘L")
        #expect(defaults.stringArray(forKey: "learningSourceLanguages") == ["es", "zh-Hans", "ar"])
        #expect(defaults.string(forKey: "learningTargetLanguage") == "ja")
    }

    @Test
    func appWideResetDisablesLearningAndPersistsTheRemainingDefaults() async throws {
        let (suiteName, defaults) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let owner = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        owner.languageLearning.translationEnabled = true
        owner.languageLearning.hintsEnabled = true
        owner.languageLearning.sourceLanguages = [.spanish, .arabic]
        owner.languageLearning.targetLanguage = .japanese
        owner.languageLearning.model = "test-instruction-model"
        owner.languageLearning.keyCode = 3
        owner.languageLearning.modifiers = [.shift]
        owner.languageLearning.keyLabel = "⇧C"

        owner.resetToDefaults()
        let restored = LanguageLearningSettings(defaults: defaults)

        #expect(!restored.translationEnabled)
        #expect(!restored.hintsEnabled)
        #expect(restored.sourceLanguages == [.chinese])
        #expect(restored.targetLanguage == .english)
        #expect(restored.model.isEmpty)
        #expect(restored.keyCode == 17)
        #expect(restored.modifiers == [.option])
        #expect(restored.keyLabel == "⌥T")
    }

    @Test
    func oneDefaultsSuiteCannotEnableAnotherSuitesFeatures() async throws {
        let (firstName, firstDefaults) = try makeIsolatedDefaults()
        let (secondName, secondDefaults) = try makeIsolatedDefaults()
        defer {
            firstDefaults.removePersistentDomain(forName: firstName)
            secondDefaults.removePersistentDomain(forName: secondName)
        }

        let first = LanguageLearningSettings(defaults: firstDefaults)
        first.translationEnabled = true
        first.hintsEnabled = true

        let second = LanguageLearningSettings(defaults: secondDefaults)
        let restoredFirst = LanguageLearningSettings(defaults: firstDefaults)

        #expect(!second.translationEnabled)
        #expect(!second.hintsEnabled)
        #expect(restoredFirst.translationEnabled)
        #expect(restoredFirst.hintsEnabled)
    }

    @MainActor
    private func makeIsolatedDefaults() throws -> (name: String, defaults: UserDefaults) {
        let name = "io.cotabby.tests.LanguageLearningSettings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return (name, defaults)
    }
}
