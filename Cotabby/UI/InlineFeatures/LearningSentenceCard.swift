import AppKit
import SwiftUI

/// Shows the sentence pair without dictionary text or duplicate mapping rows. The shared detail
/// state supplies selection borders; the app-owned panel receives clicks and owns lookup I/O.
struct LearningSentenceCard: View {
    let presentation: LearningSentencePresentation
    @ObservedObject var detailState: LearningDetailState
    let inspect: (Int) -> Void
    let expand: () -> Void
    let dismiss: () -> Void
    var lookup: (String, NSButton) -> Void = { _, _ in }
    var lookupText: (LearningDictionaryTextAnchor, NSTextView) -> Void = { _, _ in }
    var lookupUnit: ((LearningUnitTextAnchor, NSTextView) -> Void)? = nil
    let sizeChanged: (CGSize) -> Void
    // Begin with the sentence pair's short layout; longer content measures itself below.
    // The former instruction-sized fallback leaves a blank block after the guide text is removed.
    @State private var detailsHeight: CGFloat = 100
    @State private var compactTranslationHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if presentation.isExpanded {
                details
            } else {
                if let previous = presentation.previousTranslation {
                    Text(previous).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if !presentation.translation.isEmpty, !presentation.isStale {
                    compactTranslation
                } else {
                    Text(presentation.translation.isEmpty
                        ? (presentation.isStale
                            ? String(localized: "Waiting for a pause to update the expression…", table: "Learning",
                                comment: """
                                Compact card placeholder when the source text changed and a new translation will start after typing \
                                pauses.
                                """)
                            : String(localized: "Generating expression…", table: "Learning",
                                comment: "Compact card placeholder while the target-language translation is being generated."))
                        : presentation.translation)
                    .font(.system(size: 16)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(presentation.isStale ? Color.secondary : Color.primary)
                }
                if !presentation.isGenerating, !presentation.message.isEmpty {
                    Text(presentation.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(width: presentation.isExpanded ? 480 : 320, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: LearningCardSizePreference.self, value: geometry.size)
        })
        .onPreferenceChange(LearningCardSizePreference.self, perform: sizeChanged)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Compact describes the viewport, not a shortened translation. TextKit lays out the entire
    /// sentence; short content fits naturally and longer content scrolls without growing over the
    /// editor. Direct geometry observation also shrinks a reused host after a long sentence.
    private var compactTranslation: some View {
        ScrollView {
            LearningSentenceDictionaryText(text: presentation.translation, language: presentation.targetLanguage,
                lookup: lookupText, units: presentation.units, maximumLines: 0, lookupUnit: lookupUnit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if height.isFinite, height > 0 { compactTranslationHeight = height }
                }
        }
        .frame(height: min(max(compactTranslationHeight, 1), 180))
        .id(presentation.id)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(presentation.isStale && !presentation.translation.isEmpty
                ? String(localized: "Previous expression · updates after a pause", table: "Learning",
                    comment: "Header shown when the card retains the previous translation while the user edits the source sentence.")
                : presentation.isExpanded
                    ? String(localized: "\(presentation.sourceLanguage.label) → \(presentation.targetLanguage.label)",
                        table: "Learning", comment: "Source-to-target language direction in the expanded sentence card.")
                    : String(localized: "Target expression · \(presentation.targetLanguage.label)", table: "Learning",
                        comment: "Compact card header naming the target language."))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Button(presentation.isExpanded
                ? String(localized: "Collapse", table: "Learning", comment: "Button that collapses the expanded sentence-learning card.")
                : String(localized: "Expand · \(presentation.shortcutLabel)", table: "Learning",
                    comment: """
                    Button that expands the sentence-learning card; the shortcut label is the user's configured key combination.
                    """),
                action: expand)
                .buttonStyle(.plain).font(.caption).fixedSize()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
                .help(String(localized: "Dismiss · Esc", table: "Learning", comment: """
                Tooltip for dismissing the sentence-learning card with Escape.
                """))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Source text", table: "Learning",
                        comment: "Label above the original sentence in the expanded learning card."))
                        .font(.caption).foregroundStyle(.secondary)
                    sentence(presentation.source, source: true)
                    Text(String(localized: "Target expression", table: "Learning",
                        comment: "Label above the translated sentence in the expanded learning card."))
                        .font(.caption).foregroundStyle(.secondary)
                    sentence(presentation.translation, source: false)
                    if alignedChunks.isEmpty {
                        Text(presentation.isGenerating
                            ? String(localized: "The translation appears first; chunk alignments are loading…", table: "Learning",
                                comment: "Status shown while the translation is available but phrase-alignment analysis is still running.")
                            : presentation.message)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let selected = detailState.chunk, selected.documentID == presentation.id,
                       alignedChunks.contains(where: { $0.id == selected.chunkID }) {
                        Text(verbatim: "\(selected.source) → \(selected.target)")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if presentation.unitStage == .failed {
                        Text(String(localized: "Expression highlights are unavailable; you can still double-click words to look them up.",
                            table: "Learning", comment: """
                            Status when expression recognition failed but dictionary lookup remains available.
                            """))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if presentation.unitStage == .pending {
                        Text(String(localized: "Recognizing expressions… You can still double-click words to look them up.",
                            table: "Learning", comment: """
                            Status while expression recognition runs; dictionary lookup is already available.
                            """))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if presentation.unitStage != .pending, alignedChunks.count < presentation.chunks.count {
                        Text(String(localized: "Some matches are not highlighted; complete expressions remain available for lookup.",
                            table: "Learning", comment: """
                            Status when some chunk alignments cannot be highlighted, while dictionary lookup still works.
                            """))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !presentation.message.isEmpty, !presentation.isGenerating, !presentation.chunks.isEmpty {
                        Text(presentation.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Observe the content itself: a preference routed across ScrollView can
                    // retain its old value after the sentence gains lines. Intrinsic vertical
                    // sizing keeps this measurement independent of the bounded viewport.
                    if height.isFinite, height > 0 { detailsHeight = height }
                }
            }
            .frame(height: min(max(detailsHeight, 1), 320))
            HStack {
                if !presentation.translation.isEmpty {
                    Button(String(localized: "Copy translation", table: "Learning",
                        comment: "Copies the target-language sentence to the clipboard.")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(presentation.translation, forType: .string)
                    }
                }
                Spacer()
            }
        }
    }

    private func sentence(_ text: String, source: Bool) -> some View {
        LearningSentenceDictionaryText(text: text, language: source ? presentation.sourceLanguage : presentation.targetLanguage,
            lookup: lookupText, units: source ? [] : presentation.units, chunks: alignedChunks,
            selectedChunk: detailState.chunk?.documentID == presentation.id ? detailState.chunk?.chunkID : nil,
            source: source, maximumLines: 0, fontSize: source ? 16 : 18,
            lookupUnit: source ? nil : lookupUnit, inspect: inspect)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var alignedChunks: [LearningMeaningChunk] {
        guard presentation.unitStage != .pending else { return [] }
        let units = presentation.units.isEmpty ?
            LearningUnitPolicy.fallback(in: presentation.translation, language: presentation.targetLanguage) : presentation.units
        return LearningUnitPolicy.correspondence(presentation.chunks, respecting: units)
    }
}
