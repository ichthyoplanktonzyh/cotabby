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
    let sizeChanged: (CGSize) -> Void
    @State private var detailsHeight: CGFloat = 180

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
                    LearningSentenceDictionaryText(text: presentation.translation, language: presentation.targetLanguage,
                        lookup: lookupText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(presentation.translation.isEmpty ?
                     (presentation.isStale ? "输入停止后生成目标表达…" : "正在生成目标表达…") : presentation.translation)
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

    private var header: some View {
        HStack(spacing: 8) {
            Text(presentation.isStale && !presentation.translation.isEmpty ? "上一版表达 · 输入停止后更新" :
                 presentation.isExpanded ? "\(presentation.sourceLanguage.label) → \(presentation.targetLanguage.label)" :
                 "目标表达 · \(presentation.targetLanguage.label)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Button(presentation.isExpanded ? "收起" : "展开 · \(presentation.shortcutLabel)", action: expand)
                .buttonStyle(.plain).font(.caption).fixedSize()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).help("收起 · Esc")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("原意").font(.caption).foregroundStyle(.secondary)
                    sentence(presentation.source, source: true)
                    Text("目标表达").font(.caption).foregroundStyle(.secondary)
                    sentence(presentation.translation, source: false)
                    if presentation.chunks.isEmpty {
                        let words = LearningChunkDisplay.words(in: presentation.translation, language: presentation.targetLanguage)
                        if !words.isEmpty {
                            Text("点击单词查词").font(.caption).foregroundStyle(.secondary)
                            LearningTextFlowLayout(spacing: 5, rowSpacing: 6, rightToLeft: presentation.targetLanguage == .arabic) {
                                ForEach(words, id: \.self) { word in LearningDictionaryButton(word: word, lookup: lookup) }
                            }
                        }
                        Text(presentation.isGenerating ? "译文先显示，语块对应正在准备…" : presentation.message)
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("同色语块显示表达对应。点击语块查看两侧表达，再选择单词查词。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !presentation.message.isEmpty, !presentation.isGenerating, !presentation.chunks.isEmpty {
                        Text(presentation.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: LearningScrollHeightPreference.self, value: geometry.size.height)
                })
            }
            .frame(height: min(max(detailsHeight, 1), 320))
            .onPreferenceChange(LearningScrollHeightPreference.self) { height in
                // Root replacement emits zero before real scroll content has been measured.
                // Keep the last usable height so the expanded viewport cannot collapse.
                if height.isFinite, height > 0 { detailsHeight = height }
            }
            HStack {
                if !presentation.translation.isEmpty {
                    Button("复制译文") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(presentation.translation, forType: .string)
                    }
                }
                Spacer()
                Text("继续输入即可收起详情").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sentence(_ text: String, source: Bool) -> some View {
        LearningChunkTextView(text: text, chunks: presentation.chunks, source: source,
            selectedChunk: detailState.chunk?.documentID == presentation.id ? detailState.chunk?.chunkID : nil,
            select: inspect, rightToLeft: (source ? presentation.sourceLanguage : presentation.targetLanguage) == .arabic)
    }
}
