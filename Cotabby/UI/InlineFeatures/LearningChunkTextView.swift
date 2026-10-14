import SwiftUI

/// Displays exact text fragments as quiet meaning-unit chips. The same ID chooses the same color
/// on both sides; selected borders disambiguate repeated colors and discontinuous expressions.
/// This view only emits a meaning ID. Its owner opens the scoped detail window.
struct LearningChunkTextView: View {
    let text: String
    let chunks: [LearningMeaningChunk]
    let source: Bool
    let selectedChunk: Int?
    let select: (Int) -> Void
    var rightToLeft = false

    var body: some View {
        LearningTextFlowLayout(spacing: source ? 2 : 3, rowSpacing: 5, rightToLeft: rightToLeft) {
            ForEach(displayFragments) { fragment in
                if let identifier = fragment.chunkID {
                    Button { select(identifier) } label: {
                        Text(fragment.text).font(.system(size: source ? 16 : 18))
                            .foregroundStyle(.primary).padding(.horizontal, 4).padding(.vertical, 3)
                            .background(LearningChunkPalette.color(identifier).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(
                                LearningChunkPalette.color(identifier).opacity(selectedChunk == identifier ? 0.9 : 0.2),
                                lineWidth: selectedChunk == identifier ? 2 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Phrase match \(identifier + 1): \(fragment.text)", table: "Learning",
                        comment: "VoiceOver label for an aligned phrase; the number and phrase text describe this specific result."))
                    .accessibilityHint(String(localized: "Inspect the phrase match and look up its words", table: "Learning",
                        comment: "VoiceOver hint describing actions available on an aligned phrase."))
                } else if fragment.text.allSatisfy(\.isNewline) {
                    Color.clear.frame(width: 0, height: 0).layoutValue(key: LearningLineBreakKey.self, value: true)
                } else {
                    Text(fragment.text).font(.system(size: source ? 16 : 18))
                }
            }
        }
        // This layout mirrors coordinates from the content language. Keep SwiftUI's inherited
        // interface direction out of the same subtree so Arabic chips are not mirrored twice.
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayFragments: [LearningTextFragment] {
        let fragments = LearningChunkDisplay.fragments(text: text, chunks: chunks, source: source)
        return fragments.enumerated().compactMap { index, fragment in
            // Between target chips the small flow gap represents the original word space, rather
            // than adding two extra gaps around a whitespace-only Text. Copy still uses raw text.
            if !source, fragment.chunkID == nil, fragment.text.allSatisfy(\.isWhitespace),
               !fragment.text.contains(where: \.isNewline), index > 0, index + 1 < fragments.count,
               fragments[index - 1].chunkID != nil, fragments[index + 1].chunkID != nil { return nil }
            return fragment
        }
    }
}

/// Shared by the sentence pair and the small detail window. Palette reuse is intentional: the
/// selected border identifies the exact meaning when a sentence has more units than colors.
enum LearningChunkPalette {
    private static let colors: [Color] = [.blue, .orange, .teal, .purple, .pink, .green, .indigo, .brown,
                                        .cyan, .mint, .red, .yellow]
    static func color(_ identifier: Int) -> Color { colors[max(identifier, 0) % colors.count] }
}

/// Unlike tag-editor chips, a meaning unit can be wider than the card. Measure it again with the
/// available width so its text wraps inside the chip rather than overflowing the window. Callers
/// pin this layout to left-to-right coordinates; `rightToLeft` describes the content and is the
/// only direction that should mirror the manually placed frames.
struct LearningTextFlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat
    var rightToLeft = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            let originX = rightToLeft ? bounds.maxX - frame.maxX : bounds.minX + frame.minX
            subview.place(at: CGPoint(x: originX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width proposedWidth: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let idealWidth = subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width + spacing }
        let width = max((proposedWidth?.isFinite == true ? proposedWidth : nil) ?? idealWidth, 1)
        var frames: [CGRect] = []
        var rowStart = 0
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        var rowHeight: CGFloat = 0
        func finishRow() {
            for index in rowStart..<frames.count { frames[index].origin.y += (rowHeight - frames[index].height) / 2 }
            rowStart = frames.count
            offsetX = 0
            offsetY += max(rowHeight, 22) + rowSpacing
            rowHeight = 0
        }
        for subview in subviews {
            if subview[LearningLineBreakKey.self] {
                finishRow()
                frames.append(CGRect(x: 0, y: offsetY, width: 0, height: 0))
                rowStart = frames.count
                continue
            }
            let ideal = subview.sizeThatFits(.unspecified)
            let size = subview.sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
            if offsetX > 0, offsetX + spacing + size.width > width { finishRow() }
            if offsetX > 0 { offsetX += spacing }
            frames.append(CGRect(origin: CGPoint(x: offsetX, y: offsetY), size: size))
            offsetX += size.width
            rowHeight = max(rowHeight, size.height)
        }
        for index in rowStart..<frames.count { frames[index].origin.y += (rowHeight - frames[index].height) / 2 }
        return (CGSize(width: width, height: offsetY + rowHeight), frames)
    }
}

private nonisolated struct LearningLineBreakKey: LayoutValueKey {
    static var defaultValue: Bool { false }
}

/// Separate keys keep unbounded scroll content distinct from the bounded card rectangle. Zero
/// is an initial layout sentinel, never a replacement for an already usable viewport height.
nonisolated struct LearningCardSizePreference: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

nonisolated struct LearningScrollHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
