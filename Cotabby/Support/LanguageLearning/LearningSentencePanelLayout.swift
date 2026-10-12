import CoreGraphics

/// Pure placement for the learning card, which shares the caret with inline completion. The panel
/// supplies the actual completion window's rectangle; this policy never moves or hides completion.
/// All values use AppKit screen coordinates. No free on-screen rectangle means learning waits
/// for space rather than covering the caret or the completion's acceptance hint.
nonisolated enum LearningSentencePanelLayout {
    static let gap: CGFloat = 8

    static func frame(
        caretRect: CGRect, contentSize: CGSize, visibleFrame: CGRect, reservedFrame: CGRect?
    ) -> CGRect? {
        guard finite(caretRect), finite(visibleFrame), contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0,
              contentSize.width <= visibleFrame.width, contentSize.height <= visibleFrame.height else { return nil }
        let obstacle = reservedFrame.flatMap { finite($0) && !$0.isEmpty ? $0.insetBy(dx: -gap, dy: -gap) : nil }
        let caret = caretRect.insetBy(dx: -gap, dy: -gap)
        let width = contentSize.width
        let height = contentSize.height
        let anchorX = min(max(caretRect.minX, visibleFrame.minX), visibleFrame.maxX - width)
        // Learning prefers above; inline ghost text starts at the caret and usually extends down.
        var origins = [CGPoint(x: anchorX, y: caretRect.maxY + gap),
                       CGPoint(x: anchorX, y: caretRect.minY - gap - height)]
        if let obstacle {
            origins += [CGPoint(x: anchorX, y: obstacle.maxY), CGPoint(x: anchorX, y: obstacle.minY - height),
                        CGPoint(x: obstacle.maxX, y: caretRect.maxY + gap),
                        CGPoint(x: obstacle.minX - width, y: caretRect.maxY + gap)]
        }
        // Check screen edges and obstacle edges together: near a corner, a lateral position may
        // be the only free slot. Clamping a colliding rectangle alone would keep the collision.
        let xs = [anchorX, visibleFrame.minX, visibleFrame.maxX - width,
                  obstacle?.maxX ?? anchorX, (obstacle?.minX ?? anchorX + width) - width]
        let ys = [caretRect.maxY + gap, caretRect.minY - gap - height,
                  obstacle?.maxY ?? visibleFrame.maxY - height,
                  (obstacle?.minY ?? visibleFrame.minY + height) - height,
                  visibleFrame.maxY - height, visibleFrame.minY]
        for originX in xs {
            for originY in ys { origins.append(CGPoint(x: originX, y: originY)) }
        }
        return origins.lazy.map { CGRect(origin: $0, size: contentSize) }.first { candidate in
            visibleFrame.contains(candidate) && !candidate.intersects(caret) &&
                !(obstacle?.intersects(candidate) ?? false)
        }
    }

    private static func finite(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
    }
}
