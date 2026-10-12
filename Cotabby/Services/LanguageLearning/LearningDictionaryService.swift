import CoreServices
import Foundation
import NaturalLanguage

/// One panel-owned actor serializes local Dictionary Services lookups away from MainActor.
/// Its bounded cache contains only clicked terms; no model or network participates in word details.
actor LearningDictionaryService: LearningDictionaryProviding {
    private var cache: [String: LearningDictionaryEntry] = [:]

    func entry(for word: String, language: LearningLanguage) -> LearningDictionaryEntry {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.utf8.count <= 256 else {
            return .init(requestedTerm: word, resolvedTerm: word, paragraphs: ["请选择一个单词或短语。"], isFound: false)
        }
        let key = language.rawValue + ":" + word
        if let cached = cache[key] { return cached }
        var result = lookup(word)
        var resolved = word
        if result == nil {
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = word
            tagger.setLanguage(language.naturalLanguage, range: word.startIndex..<word.endIndex)
            let lemma = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0?.rawValue
            if let lemma, lemma != word { result = lookup(lemma); if result != nil { resolved = lemma } }
        }
        let entry = LearningDictionaryEntry(requestedTerm: word, resolvedTerm: resolved,
            paragraphs: result.map(LearningDictionaryText.paragraphs) ??
                ["系统词典暂无此词的释义。", "可在“词典”应用中启用对应语言的词典，再点击此词查询。"], isFound: result != nil)
        // A missing dictionary may be enabled while Cotabby is running. Cache only successful
        // entries so reopening that word can see newly available content without restarting.
        if entry.isFound {
            if cache.count >= 128 { cache.removeAll() }
            cache[key] = entry
        }
        return entry
    }

    private func lookup(_ text: String) -> String? {
        // Copy follows the CF ownership rule: consume the retained result once, while the source
        // CFString remains alive for the synchronous call. Offsets are UTF-16, not Swift Characters.
        let range = CFRange(location: 0, length: text.utf16.count)
        return DCSCopyTextDefinition(nil, text as CFString, range)?.takeRetainedValue() as String?
    }
}
