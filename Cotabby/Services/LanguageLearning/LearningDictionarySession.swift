import Combine
import Foundation

/// One nonactivating dictionary panel owns one session. The unit remains its home page while
/// words change only the active query. A revision prevents an older lookup replacing a newer
/// word, a returned expression, or a dismissed sentence. Definitions live only in this session.
@MainActor
final class LearningDictionarySession: ObservableObject {
    enum Content: Equatable {
        case loading
        case result(LearningDictionaryResult)
        case failed(String)
    }
    @Published private(set) var unit: LearningUnit?
    @Published private(set) var documentID: UUID?
    @Published private(set) var selectedWord: LearningDictionaryWord?
    @Published private(set) var content: Content = .loading
    private let provider: any LearningDictionaryProviding
    private var language: LearningLanguage = .english
    private var revision = UUID()
    private var work: Task<Void, Never>?
    private var cache: [String: LearningDictionaryResult] = [:]

    init(provider: any LearningDictionaryProviding) { self.provider = provider }

    var title: String { selectedWord?.text ?? unit?.surface ?? "" }
    var query: String { selectedWord?.text ?? unit?.query ?? "" }

    func open(_ unit: LearningUnit, documentID: UUID, language: LearningLanguage) {
        close()
        self.unit = unit
        self.documentID = documentID
        self.language = language
        request()
    }

    func select(_ word: LearningDictionaryWord) {
        guard let unit, unit.words.contains(word) else { return }
        selectedWord = word
        request()
    }

    func returnToExpression() {
        guard unit != nil else { return }
        selectedWord = nil
        request()
    }

    func close() {
        revision = UUID()
        work?.cancel(); work = nil
        unit = nil; documentID = nil; selectedWord = nil
        content = .loading
        cache.removeAll()
    }

    private func request() {
        revision = UUID()
        work?.cancel(); work = nil
        guard let unit else { return }
        let id = revision, text = query, language = language
        let expression = selectedWord == nil && unit.kind != .word
        let key = String(expression) + ":" + text
        if let cached = cache[key] { content = .result(cached); return }
        content = .loading
        work = Task { [weak self, provider] in
            do {
                let result = try await provider.lookup(text, language: language, expression: expression)
                guard let self, !Task.isCancelled, self.revision == id, self.unit != nil else { return }
                self.cache[key] = result
                self.content = .result(result)
                self.work = nil
            } catch {
                guard let self, !Task.isCancelled, self.revision == id, self.unit != nil else { return }
                self.content = .failed(error.localizedDescription)
                self.work = nil
            }
        }
    }
}
