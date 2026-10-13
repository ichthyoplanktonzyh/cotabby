import CoreServices
import Foundation

/// The composition root owns one offline store shared by recognition and dictionary sessions.
/// This actor serializes lazy JSON/index loading and Dictionary Services access away from UI.
/// There is no HTTP client: expression queries use bundled data; system word queries use the
/// user's configured Dictionary Services rather than an app-managed hosted lookup.
actor LearningLexiconService: LearningUnitRecognizing, LearningDictionaryProviding {
    private let resourceURL: URL?
    private var resource: LearningLexiconResource?
    private var indices: [String: LearningUnitRecognizer] = [:]

    init(resourceURL: URL?) { self.resourceURL = resourceURL }

    func recognize(_ translation: String, language: LearningLanguage) async throws -> [LearningUnit] {
        try Task.checkCancellation()
        let index = try index(for: language)
        let units = index.recognize(translation, language: language)
        try Task.checkCancellation()
        return units
    }

    func lookup(_ query: String, language: LearningLanguage, expression: Bool) async throws -> LearningDictionaryResult {
        try Task.checkCancellation()
        guard !query.isEmpty, query.utf8.count <= 256, InsertionSafetyGate.isSafeToInsert(query) else {
            throw LearningFailure.message(String(localized: "This lookup text is unavailable.",
                table: "Learning", comment: "Error shown when dictionary lookup receives empty, oversized, or unsafe text."))
        }
        do {
            let entries = try index(for: language).lookup(query).filter {
                expression || LearningUnitPolicy.key($0.headword) == LearningUnitPolicy.key(query)
            }
            if !entries.isEmpty { return .entries(entries) }
        } catch {
            // A broken expression resource is an unavailable state, not a dictionary miss.
            // Ordinary word lookup can still use the user's installed system dictionaries.
            if expression { throw error }
        }
        let value = query as CFString
        let detected = DCSGetTermRangeInString(nil, value, 0)
        let whole = CFRange(location: 0, length: query.utf16.count)
        guard detected.location == 0, detected.length == whole.length else { return .notFound }
        // Copy follows the Core Foundation ownership rule; transfer its retained string once.
        // The full-range check prevents a constituent word definition posing as a phrase result.
        guard let copied = DCSCopyTextDefinition(nil, value, whole) else { return .notFound }
        let text = copied.takeRetainedValue() as String
        try Task.checkCancellation()
        guard !text.isEmpty, text.utf8.count <= 64_000 else { return .notFound }
        return .systemDefinition(text)
    }

    private func index(for language: LearningLanguage) throws -> LearningUnitRecognizer {
        let code = language == .chinese || language == .traditionalChinese ? "zh" : language.rawValue
        if let index = indices[code] { return index }
        if resource == nil {
            guard let resourceURL else {
                throw LearningFailure.message(String(localized: """
                The local expression dictionary is unavailable. You can still look up individual words.
                """,
                    table: "Learning", comment: "Error shown when the bundled expression dictionary resource is missing."))
            }
            do {
                let data = try Data(contentsOf: resourceURL)
                guard data.count <= 64_000_000 else {
                    throw LearningFailure.message(String(localized: "The expression dictionary exceeds the supported size.",
                        table: "Learning", comment: """
                        Error shown when the bundled expression dictionary is larger than the supported load limit.
                        """))
                }
                resource = try JSONDecoder().decode(LearningLexiconResource.self, from: data)
            } catch {
                throw LearningFailure.message(String(localized: """
                The local expression dictionary could not be read. You can still look up individual words.
                """,
                    table: "Learning", comment: "Error shown when the bundled expression dictionary cannot be read or decoded."))
            }
        }
        let index = LearningUnitRecognizer(entries: resource!.entries.filter { $0.language == code })
        indices[code] = index
        return index
    }
}
