import Foundation
import XCTest
@testable import Cotabby

/// Tests the pure receipt boundary for editable text reads. Marker fragments are trusted only when
/// their exact UTF-16 sequence agrees with the full value, and replacement ranges must cover whole
/// extended graphemes before the Accessibility layer can mutate an editor.
final class AXEditableTextSelectionTests: XCTestCase {
    func testValidatedSelectionAcceptsWholeEmojiAndCombiningGraphemes() {
        let value = "A👩🏽‍💻e\u{301}中文"
        let emoji = (value as NSString).range(of: "👩🏽‍💻")
        let accented = (value as NSString).range(of: "e\u{301}")

        XCTAssertEqual(AXEditableTextSelection.validated(value: value, range: emoji, usesTextMarkers: false)?.range, emoji)
        XCTAssertEqual(AXEditableTextSelection.validated(value: value, range: accented, usesTextMarkers: false)?.range, accented)
    }

    func testValidatedSelectionRejectsOverflowingAndOutOfBoundsRanges() {
        let value = "Editable text"
        let length = (value as NSString).length

        XCTAssertNil(AXEditableTextSelection.validated(
            value: value, range: NSRange(location: Int.max, length: 1), usesTextMarkers: false
        ))
        XCTAssertNil(AXEditableTextSelection.validated(
            value: value, range: NSRange(location: length, length: 1), usesTextMarkers: false
        ))
        XCTAssertNil(AXEditableTextSelection.validated(
            value: value, range: NSRange(location: -1, length: 0), usesTextMarkers: false
        ))
    }

    func testValidatedSelectionRejectsBoundariesInsideComposedGraphemes() {
        let value = "A👩🏽‍💻e\u{301}中文"
        let emoji = (value as NSString).range(of: "👩🏽‍💻")
        let accent = (value as NSString).range(of: "e\u{301}")

        XCTAssertNil(AXEditableTextSelection.validated(
            value: value,
            range: NSRange(location: emoji.location + 1, length: emoji.length - 1),
            usesTextMarkers: false
        ))
        XCTAssertNil(AXEditableTextSelection.validated(
            value: value,
            range: NSRange(location: accent.location + 1, length: 0),
            usesTextMarkers: false
        ))
    }

    func testMarkerReceiptAcceptsExactFragmentsWithoutASeparateFieldValue() {
        let before = "前👩🏽‍💻"
        let selected = "猫"
        let after = "後"
        let full = before + selected + after

        let receipt = AXEditableTextSelection.markerReceipt(
            before: before,
            selected: selected,
            after: after,
            full: full,
            fieldValue: nil
        )
        let receiptWithMatchingFieldValue = AXEditableTextSelection.markerReceipt(
            before: before,
            selected: selected,
            after: after,
            full: full,
            fieldValue: full
        )

        XCTAssertEqual(receipt?.value, full)
        XCTAssertEqual(receipt?.range, NSRange(location: (before as NSString).length, length: 1))
        XCTAssertEqual(receipt?.usesTextMarkers, true)
        XCTAssertEqual(receiptWithMatchingFieldValue, receipt)
    }

    func testMarkerReceiptRejectsFragmentsThatDoNotExactlyReconstructFullValue() {
        XCTAssertNil(AXEditableTextSelection.markerReceipt(
            before: "before ", selected: "selected", after: " after",
            full: "before selected but different", fieldValue: nil
        ))
    }

    func testMarkerReceiptRejectsAConflictingAccessibilityFieldValue() {
        XCTAssertNil(AXEditableTextSelection.markerReceipt(
            before: "before ", selected: "selected", after: " after",
            full: "before selected after", fieldValue: "stale value"
        ))
    }

    func testMarkerReceiptComparesCanonicalEquivalentTextByExactUtf16Units() {
        let decomposed = "cafe\u{301}"
        let precomposed = "café"

        XCTAssertEqual(decomposed, precomposed, "Swift strings compare canonically equivalent text as equal.")
        XCTAssertNotEqual(Array(decomposed.utf16), Array(precomposed.utf16))
        XCTAssertNil(AXEditableTextSelection.markerReceipt(
            before: "", selected: decomposed, after: "", full: precomposed, fieldValue: nil
        ))
    }
}
