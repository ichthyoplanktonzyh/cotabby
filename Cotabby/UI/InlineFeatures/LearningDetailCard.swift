import AppKit
import SwiftUI

/// Routes the sentence panel's shared dictionary session to its expression/word card. The legacy
/// meaning card remains for compatibility fixtures; AppKit owns the nonactivating window lifetime.
struct LearningDetailCard: View {
    @ObservedObject var state: LearningDetailState
    let selectWord: (String, NSButton) -> Void
    let close: () -> Void
    let sizeChanged: (CGSize) -> Void
    var session: LearningDictionarySession? = nil
    // Start close to the short quote/word layout; measured content can grow up to the scroll cap.
    // Keeping the former explanation-sized fallback would leave a large blank area on first paint.
    @State private var contentHeight: CGFloat = 140

    var body: some View {
        if let session {
            LearningDictionaryCard(session: session, close: close, sizeChanged: sizeChanged)
        } else {
            legacyCorrespondence
        }
    }

    private var legacyCorrespondence: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Phrase correspondence", table: "Learning",
                    comment: "Title of the legacy phrase-correspondence detail card."))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain)
                    .help(String(localized: "Close window · Esc", table: "Learning",
                        comment: "Tooltip for closing the detail window with Escape."))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let chunk = state.chunk {
                        meaning(chunk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: LearningScrollHeightPreference.self, value: geometry.size.height)
                })
            }
            .frame(height: min(max(contentHeight, 80), 260))
            .onPreferenceChange(LearningScrollHeightPreference.self) { height in
                if height.isFinite, height > 0 { contentHeight = height }
            }
            Text(String(localized: "Double-click a word to open Dictionary · closes as you type", table: "Learning",
                comment: "Hint for the legacy detail card; dictionary lookup opens the macOS Dictionary panel."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(width: 320, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: LearningCardSizePreference.self, value: geometry.size)
        })
        .onPreferenceChange(LearningCardSizePreference.self, perform: sizeChanged)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func meaning(_ chunk: LearningChunkDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chunk.target.isEmpty
                ? String(localized: "Naturally omitted", table: "Learning",
                    comment: "Placeholder when the target expression naturally omits a source phrase.")
                : chunk.target)
                .font(.title3.weight(.semibold)).padding(6)
                .background(LearningChunkPalette.color(chunk.chunkID).opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            Text(chunk.source.isEmpty
                ? String(localized: "Grammar supplied by context", table: "Learning",
                    comment: "Placeholder when grammar in the target expression is supplied by context.")
                : chunk.source)
                .font(.callout).foregroundStyle(.secondary)
            if !chunk.words.isEmpty {
                Text(String(localized: "Words", table: "Learning",
                    comment: "Label above words available for dictionary lookup."))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LearningTextFlowLayout(spacing: 5, rowSpacing: 6, rightToLeft: chunk.language == .arabic) {
                    ForEach(chunk.words, id: \.self) { word in
                        LearningDictionaryButton(word: word, lookup: selectWord)
                    }
                }
            }
        }
    }

}
