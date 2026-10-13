import AppKit
import SwiftUI
import Testing
@testable import Cotabby

/// Pixel centroids check the actual order of colored units, including a right-to-left target.
/// The production wrapping layout is exercised, not a duplicated frame calculation.
@Suite(.serialized)
@MainActor
struct LearningChunkTextViewTests {
    @Test(arguments: [false, true])
    func rightToLeftTargetsKeepTheFirstMeaningOnTheRight(_ rightToLeft: Bool) async throws {
        let chunks = [
            LearningMeaningChunk(id: 0, sourceRanges: [], targetRanges: [.init(location: 0, length: 3)]),
            LearningMeaningChunk(id: 1, sourceRanges: [], targetRanges: [.init(location: 4, length: 6)])
        ]
        let view = LearningChunkTextView(text: "أنا أستطيع", chunks: chunks, source: false, selectedChunk: nil,
            select: { _ in }, rightToLeft: rightToLeft).frame(width: 300).background(Color.white)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        defer { window.close() }
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.fittingSize)
            try? await Task.sleep(for: .milliseconds(10))
        }
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        var blue: [Int] = []
        var orange: [Int] = []
        for column in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            for row in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { continue }
                if color.blueComponent > color.redComponent + 0.03, color.blueComponent > color.greenComponent + 0.02 {
                    blue.append(column)
                }
                if color.redComponent > color.blueComponent + 0.04, color.redComponent > color.greenComponent + 0.02 {
                    orange.append(column)
                }
            }
        }
        #expect(blue.count > 20)
        #expect(orange.count > 20)
        let blueCenter = blue.reduce(0, +) / max(blue.count, 1)
        let orangeCenter = orange.reduce(0, +) / max(orange.count, 1)
        #expect(rightToLeft ? blueCenter > orangeCenter : blueCenter < orangeCenter)
    }
}
