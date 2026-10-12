import CoreGraphics
import Testing
@testable import Cotabby

/// Exercises on-screen coexistence rather than fixed offsets: completion may arrive later, wrap
/// over several lines, flip above the caret, or live on a monitor with a negative origin.
struct LearningSentencePanelLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    @Test
    func prefersAboveWithoutCoveringTheCaret() throws {
        let caret = CGRect(x: 300, y: 350, width: 2, height: 20)
        let frame = try #require(LearningSentencePanelLayout.frame(caretRect: caret,
            contentSize: CGSize(width: 320, height: 60), visibleFrame: screen, reservedFrame: nil))
        #expect(frame.minY >= caret.maxY + LearningSentencePanelLayout.gap)
        #expect(screen.contains(frame))
    }

    @Test(arguments: [
        CGRect(x: 300, y: 310, width: 500, height: 80),
        CGRect(x: 300, y: 380, width: 500, height: 80),
        CGRect(x: 250, y: 180, width: 700, height: 400),
        CGRect(x: 0, y: 700, width: 1_000, height: 100)
    ])
    func avoidsActualCompletionBounds(_ completion: CGRect) throws {
        let caret = CGRect(x: 300, y: 350, width: 2, height: 20)
        let frame = try #require(LearningSentencePanelLayout.frame(caretRect: caret,
            contentSize: CGSize(width: 320, height: 150), visibleFrame: screen, reservedFrame: completion))
        #expect(!frame.intersects(completion.insetBy(dx: -8, dy: -8)))
        #expect(!frame.intersects(caret.insetBy(dx: -8, dy: -8)))
        #expect(screen.contains(frame))
    }

    @Test(arguments: [CGPoint(x: 950, y: 750), CGPoint(x: 2, y: 5), CGPoint(x: 500, y: 770)])
    func fitsAtScreenEdges(_ origin: CGPoint) throws {
        let caret = CGRect(origin: origin, size: CGSize(width: 2, height: 20))
        let frame = try #require(LearningSentencePanelLayout.frame(caretRect: caret,
            contentSize: CGSize(width: 480, height: 320), visibleFrame: screen, reservedFrame: nil))
        #expect(screen.contains(frame))
        #expect(!frame.intersects(caret))
    }

    @Test
    func usesTheSecondaryMonitorsCoordinateSpace() throws {
        let secondary = CGRect(x: -1_200, y: -200, width: 1_200, height: 800)
        let caret = CGRect(x: -100, y: 200, width: 2, height: 20)
        let completion = CGRect(x: -300, y: 180, width: 290, height: 50)
        let frame = try #require(LearningSentencePanelLayout.frame(caretRect: caret,
            contentSize: CGSize(width: 320, height: 60), visibleFrame: secondary, reservedFrame: completion))
        #expect(secondary.contains(frame))
        #expect(!frame.intersects(completion))
    }

    @Test
    func waitsInsteadOfCoveringCompletionWhenNoSpaceRemains() {
        #expect(LearningSentencePanelLayout.frame(caretRect: CGRect(x: 400, y: 400, width: 2, height: 20),
            contentSize: CGSize(width: 320, height: 60), visibleFrame: screen, reservedFrame: screen) == nil)
    }
}
