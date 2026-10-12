import Foundation

/// A full-field text receipt read synchronously from AX. Unlike a prompt window, its UTF-16 range
/// is a document coordinate. Only strings/ranges survive the read; opaque markers never do.
nonisolated struct AXEditableTextSelection: Equatable {
    let value: String
    let range: NSRange
    let usesTextMarkers: Bool

    static func markerReceipt(before: String, selected: String, after: String, full: String, fieldValue: String?) -> Self? {
        guard (before + selected + after).utf16.elementsEqual(full.utf16),
              fieldValue.map({ $0.utf16.elementsEqual(full.utf16) }) != false else { return nil }
        return validated(value: full,
            range: NSRange(location: before.utf16.count, length: selected.utf16.count), usesTextMarkers: true)
    }

    static func validated(value: String, range: NSRange, usesTextMarkers: Bool) -> Self? {
        let text = value as NSString
        guard range.location >= 0, range.length >= 0, range.location <= text.length,
              range.length <= text.length - range.location,
              Range(range, in: value) != nil,
              range.location == text.length ||
                text.rangeOfComposedCharacterSequence(at: range.location).location == range.location,
              range.length == 0 || text.rangeOfComposedCharacterSequences(for: range) == range else { return nil }
        return .init(value: value, range: range, usesTextMarkers: usesTextMarkers)
    }
}
