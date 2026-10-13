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

/// Owned by LearningDetailPanel and observed by both cards. Publishing selection lets the main
/// card highlight matching colors. AppKit owns dictionary contents separately, so definitions
/// and query tasks do not become a second page of this shared presentation state.
@MainActor
final class LearningDetailState: ObservableObject {
    @Published var chunk: LearningChunkDetail?
}
