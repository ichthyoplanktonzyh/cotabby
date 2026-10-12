import SwiftUI

/// Reads controller-owned state and emits word/back/close actions. Lookup work never starts in
/// this view, and dictionary paragraphs stay out of the sentence pair's layout. One child window
/// switches pages instead of stacking another popup for each word.
struct LearningDetailCard: View {
    @ObservedObject var state: LearningDetailState
    let selectWord: (String) -> Void
    let back: () -> Void
    let close: () -> Void
    let sizeChanged: (CGSize) -> Void
    @State private var contentHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if state.word != nil {
                    Button(action: back) { Label("语块", systemImage: "chevron.left") }.buttonStyle(.plain)
                }
                Text(state.word == nil ? "语块说明" : "系统词典").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭小窗 · Esc")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let chunk = state.chunk {
                        if let word = state.word { dictionary(word, chunk: chunk) } else { meaning(chunk) }
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
            Text(state.word == nil ? "继续输入时一起收起" : "滚动查看释义 · 继续输入时收起")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(width: 320, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: LearningCardSizePreference.self, value: geometry.size)
        })
        .onPreferenceChange(LearningCardSizePreference.self, perform: sizeChanged)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: state.word) { _, word in contentHeight = word == nil ? 200 : 140 }
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
                        Button(word) { selectWord(word) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }

    private func dictionary(_ word: String, chunk: LearningChunkDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(word).font(.title2.weight(.semibold))
            Text("所在语块：\(chunk.target)").font(.caption).foregroundStyle(.secondary)
            Divider()
            if state.isLoading {
                Text("正在查词…").font(.callout).foregroundStyle(.secondary)
            } else if let entry = state.entry {
                if entry.resolvedTerm != entry.requestedTerm {
                    Text("查询原形：\(entry.resolvedTerm)").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(entry.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph).font(.callout).lineSpacing(5)
                        .foregroundStyle(entry.isFound ? Color.primary : Color.secondary)
                }
            }
        }
    }
}
