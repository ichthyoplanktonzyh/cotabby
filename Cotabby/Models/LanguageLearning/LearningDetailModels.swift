import Combine
import CoreGraphics
import Foundation

/// A clicked meaning unit belongs to one immutable sentence version. Display quotes may join
/// discontinuous spans; dictionary words still come from the actual target-language wording.
nonisolated struct LearningChunkDetail: Equatable, Sendable {
    let documentID: UUID
    let chunkID: Int
    let source: String
    let target: String
    let explanation: String
    let language: LearningLanguage
    let words: [String]
}

/// One screen-space snapshot keeps placement arguments coherent when the parent moves while a
/// dictionary reply is pending. The sentence panel supplies it; the child never queries focus.
nonisolated struct LearningDetailPlacement {
    let parent: CGRect
    let caret: CGRect
    let reserved: CGRect?
    let screen: CGRect
    let anchorY: CGFloat
}

/// Dictionary Services supplies plain text, not tagged senses or phonetics. Preserve real
/// paragraphs and the resolved headword without inventing semantic fields from that text.
nonisolated struct LearningDictionaryEntry: Equatable, Sendable {
    let requestedTerm: String
    let resolvedTerm: String
    let paragraphs: [String]
    let isFound: Bool
}

/// The small detail window can use a deterministic dictionary in tests while production uses the
/// local actor. No generation endpoint is part of this contract.
nonisolated protocol LearningDictionaryProviding: Sendable {
    func entry(for term: String, language: LearningLanguage) async -> LearningDictionaryEntry
}

/// Owned by LearningDetailPanel and observed by both cards. Publishing selection lets the main
/// card highlight matching colors while the child changes between phrase and dictionary pages.
@MainActor
final class LearningDetailState: ObservableObject {
    @Published var chunk: LearningChunkDetail?
    @Published var word: String?
    @Published var entry: LearningDictionaryEntry?
    @Published var isLoading = false
}
