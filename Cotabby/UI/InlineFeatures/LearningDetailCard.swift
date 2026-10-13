import AppKit
import SwiftUI

/// Displays one meaning unit and emits native word-button actions. AppKit presents definitions
/// separately; the explanation and its selected color remain visible while a word is inspected.
struct LearningDetailCard: View {
    @ObservedObject var state: LearningDetailState
    let selectWord: (String, NSButton) -> Void
    let close: () -> Void
    let sizeChanged: (CGSize) -> Void
    @State private var contentHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("语块说明").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭小窗 · Esc")
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
            Text("点击单词查看系统词典 · 继续输入时收起")
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
            Text(chunk.target.isEmpty ? "自然省略" : chunk.target)
                .font(.title3.weight(.semibold)).padding(6)
                .background(LearningChunkPalette.color(chunk.chunkID).opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            Text(chunk.source.isEmpty ? "语法补充" : chunk.source).font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("本句中的表达方式").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(chunk.explanation).font(.callout).lineSpacing(4)
            if !chunk.words.isEmpty {
                Text("查看单词").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LearningTextFlowLayout(spacing: 5, rowSpacing: 6, rightToLeft: chunk.language == .arabic) {
                    ForEach(chunk.words, id: \.self) { word in
                        LearningDictionaryButton(word: word, lookup: selectWord)
                    }
                }
            }
        }
    }

}
