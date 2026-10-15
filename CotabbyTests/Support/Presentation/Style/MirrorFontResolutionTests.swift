import AppKit
import Testing
@testable import Cotabby

/// Exercises popup font evidence without an AX observer or a live panel. A fallback field rectangle
/// must never become a font-size signal, while a measured host width must survive the mode switch.
@MainActor
struct MirrorFontResolutionTests {
    @Test(arguments: [CGFloat(0), 6, 14, 96, 1000, .nan, .infinity])
    func ignoresUnreliableCaretHeight(reportedSize: CGFloat) {
        let input = GhostFontResolver.Input(
            style: ResolvedFieldStyle(fontName: "Menlo-Regular", fontPointSize: reportedSize, colorHex: nil),
            hostMetrics: nil, caretBoxHeight: 500, renderer: .textKit
        )
        let resolution = GhostFontResolver.resolveForMirror(input)
        let expected = reportedSize.isFinite && (6...96).contains(reportedSize) ? reportedSize : 13
        #expect(resolution.font.pointSize == expected)
    }

    @Test
    func retainsHostWidthEvidenceInsteadOfRawReportedSize() throws {
        let host = try #require(NSFont(name: "Menlo-Regular", size: 15.4))
        let sample = "Measured text at browser zoom"
        let resolution = GhostFontResolver.resolveForMirror(.init(
            style: ResolvedFieldStyle(fontName: "Menlo-Regular", fontPointSize: 14, colorHex: nil),
            hostMetrics: HostTextMetrics(sampleText: sample, sampleWidth: GhostFontResolver.width(of: sample, font: host)),
            caretBoxHeight: 500, renderer: .webEngine
        ))
        #expect(abs(resolution.font.pointSize - 15.4) < 0.01)
        #expect(resolution.provenance == .hostFaceScaled)
    }

    @Test
    func boldCardReservesTheHeavyAcceptancePrefix() {
        let text = "extraordinary geometry"
        let layout = MirrorOverlayLayout.make(
            suggestion: text, geometry: CotabbyTestFixtures.overlayGeometry(),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            showsAcceptanceHint: false, isBold: true, isItalic: true, reason: .userPreference
        )
        let body = GhostFontStyler.styled(NSFont.systemFont(ofSize: 13), bold: true, italic: true)
        let prefix = GhostFontStyler.styled(NSFont.systemFont(ofSize: 13, weight: .heavy), bold: false, italic: true)
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: body])
        attributed.addAttribute(.font, value: prefix, range: NSRange(location: 0, length: layout.highlightedPrefix.utf16.count))
        #expect(layout.panelFrame.width >= attributed.size().width + 20)
    }
}
