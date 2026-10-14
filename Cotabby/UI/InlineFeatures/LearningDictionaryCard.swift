import SwiftUI

/// The single dictionary window keeps the expression as its home page. Switching a word changes
/// this session's content, not its window. Structured senses and raw system definitions have
/// separate layouts, so missing fields are never invented by parsing arbitrary dictionary text.
struct LearningDictionaryCard: View {
    @ObservedObject var session: LearningDictionarySession
    let close: () -> Void
    let sizeChanged: (CGSize) -> Void
    @State private var definitionHeight: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.unit?.kind == .word
                    ? String(localized: "Word", table: "Learning", comment: "Header for an individual word's dictionary entry.")
                    : String(localized: "Expression dictionary", table: "Learning",
                        comment: "Header for the dictionary page for a complete expression."))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain)
                    .help(String(localized: "Close dictionary · Esc", table: "Learning",
                        comment: "Tooltip for closing the learning dictionary panel with Escape."))
            }
            if session.selectedWord != nil {
                Button(String(localized: "← Back to the full expression", table: "Learning",
                    comment: "Returns from a word entry to the dictionary page for the whole expression."),
                    action: session.returnToExpression).buttonStyle(.plain).font(.caption)
            }
            Text(session.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if session.query != session.title {
                Text(String(localized: "Dictionary form: \(session.query)", table: "Learning",
                    comment: "Shows the normalized dictionary lookup form; the term is supplied by the learning content."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                definition.frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: LearningScrollHeightPreference.self, value: geometry.size.height)
                    })
            }
            .frame(height: min(max(definitionHeight, 24), 210))
            .onPreferenceChange(LearningScrollHeightPreference.self) { height in
                // Short entries should not inherit a full dictionary viewport's blank space.
                // Keep a bounded scroll area for long entries, ignoring transient zero measures.
                if height.isFinite, height > 0 { definitionHeight = height }
            }
            if case .result(.entries) = session.content,
               let url = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/") {
                // Attribution stays outside the scroll viewport, including for long entries.
                Link(String(localized: "Wiktionary contributors / Kaikki · CC BY-SA 4.0", table: "Learning",
                    comment: "Attribution and license for the bundled Wiktionary-derived expression dictionary entries."),
                    destination: url)
                    .font(.caption2).fixedSize(horizontal: false, vertical: true)
            }
            if let unit = session.unit, unit.kind != .word {
                Text(String(localized: "Words in this expression", table: "Learning",
                    comment: "Label above component words that can be opened from an expression dictionary entry."))
                    .font(.caption).foregroundStyle(.secondary)
                LearningTextFlowLayout(spacing: 5, rowSpacing: 5, rightToLeft: session.contentLanguage == .arabic) {
                    ForEach(Array(unit.words.enumerated()), id: \.offset) { _, word in
                        Button(word.text) { session.select(word) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                // Dictionary terms keep their stored order; only their positions follow the
                // captured lookup language, independent of the interface's own direction.
                .environment(\.layoutDirection, .leftToRight)
            }
            Text(String(localized: "Closes as you type", table: "Learning",
                comment: "Hint that typing in the host editor dismisses the dictionary panel."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(width: 340, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: LearningCardSizePreference.self, value: geometry.size)
        })
        .onPreferenceChange(LearningCardSizePreference.self, perform: sizeChanged)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var definition: some View {
        switch session.content {
        case .loading:
            ProgressView(String(localized: "Looking up…", table: "Learning",
                comment: "Progress label while a dictionary lookup is running.")).font(.caption)
        case .failed(let message):
            Text(message).font(.callout).foregroundStyle(.secondary)
        case .result(.notFound):
            Text(session.selectedWord == nil && session.unit?.kind != .word
                ? String(localized: "No dictionary entry was found for this expression. Select a word below to look it up.",
                    table: "Learning", comment: "Empty state when the complete expression has no dictionary entry.")
                : String(localized: "No definition for this word was found in the available dictionaries.",
                    table: "Learning", comment: "Empty state when the configured dictionaries have no entry for a word."))
                .font(.callout).foregroundStyle(.secondary)
        case .result(.systemDefinition(let text)):
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "System Dictionary · enabled sources", table: "Learning",
                    comment: "Label indicating that the definition below came from the user's enabled macOS dictionaries."))
                    .font(.caption).foregroundStyle(.secondary)
                // Display one query's result, preserving its paragraph structure. No word
                // definitions are concatenated and no POS/pronunciation fields are fabricated.
                ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .result(.entries(let entries)):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(entries, id: \.id) { entry in
                    if entry.headword != session.query { Text(entry.headword).font(.headline) }
                    ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(sense.partOfSpeech + (sense.labels.isEmpty ? "" : " · " + sense.labels.joined(separator: ", ")))
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(sense.definitions.enumerated()), id: \.offset) { index, text in
                                Text(verbatim: "\(index + 1). \(text)").font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let url = URL(string: entry.sourceURL) {
                        Link(String(localized: "Source: Wiktionary · English definitions", table: "Learning",
                            comment: "Source label for the bundled expression definition link."),
                            destination: url).font(.caption2)
                    }
                }
            }
        }
    }
}
