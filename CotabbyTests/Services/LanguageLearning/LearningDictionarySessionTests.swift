import Foundation
import Testing
@testable import Cotabby

@MainActor
struct LearningDictionarySessionTests {
    private func unit() -> LearningUnit {
        let text = "look forward to"
        return .init(id: 0, surface: text, query: text, kind: .expression,
            ranges: [.init(location: 0, length: text.utf16.count)],
            words: LearningUnitPolicy.words(in: text, language: .english))
    }
    private func settle(_ predicate: @escaping @MainActor () -> Bool) async {
        for _ in 0..<200 where !predicate() { await Task.yield() }
    }

    @Test
    func wholeExpressionMissAllowsWordNavigationAndReturningWithoutCombiningDefinitions() async {
        let provider = ControlledLearningDictionary()
        let session = LearningDictionarySession(provider: provider)
        let expression = unit()
        session.open(expression, documentID: UUID(), language: .english)
        await settle { session.content == .result(.notFound) }
        #expect(session.title == "look forward to")
        #expect(session.content == .result(.notFound))
        session.select(expression.words[1])
        await settle { session.content == .result(.systemEntry) }
        #expect(session.title == "forward")
        session.returnToExpression()
        #expect(session.content == .result(.notFound))
        #expect(session.selectedWord == nil)
        let calls = await provider.calls
        #expect(calls == ["expression:look forward to", "word:forward"])
        session.close()
        #expect(session.unit == nil)
    }

    @Test
    func outOfOrderQueryAndClosedSessionNeverPublishLateDefinitions() async {
        let provider = ControlledLearningDictionary(delayed: true)
        let session = LearningDictionarySession(provider: provider)
        let expression = unit()
        session.open(expression, documentID: UUID(), language: .english)
        await provider.waitFor("look forward to")
        session.select(expression.words[0])
        await provider.waitFor("look")
        await provider.finish("look", result: .systemEntry)
        await settle { session.content == .result(.systemEntry) }
        await provider.finish("look forward to", result: .notFound)
        for _ in 0..<20 { await Task.yield() }
        #expect(session.title == "look")
        #expect(session.content == .result(.systemEntry))
        session.select(expression.words[2])
        await provider.waitFor("to")
        session.close()
        await provider.finish("to", result: .systemEntry)
        for _ in 0..<20 { await Task.yield() }
        #expect(session.unit == nil && session.documentID == nil)
    }
}

private actor ControlledLearningDictionary: LearningDictionaryProviding {
    let delayed: Bool
    var calls: [String] = []
    var pending: [String: CheckedContinuation<LearningDictionaryResult, Never>] = [:]
    var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    func waitFor(_ query: String) async {
        if pending[query] != nil { return }
        await withCheckedContinuation { waiters[query] = $0 }
    }
    init(delayed: Bool = false) { self.delayed = delayed }
    func lookup(_ query: String, language: LearningLanguage, expression: Bool) async throws -> LearningDictionaryResult {
        calls.append((expression ? "expression:" : "word:") + query)
        if delayed {
            return await withCheckedContinuation {
                pending[query] = $0
                waiters.removeValue(forKey: query)?.resume()
            }
        }
        return expression ? .notFound : .systemEntry
    }
    func finish(_ query: String, result: LearningDictionaryResult) { pending.removeValue(forKey: query)?.resume(returning: result) }
}
