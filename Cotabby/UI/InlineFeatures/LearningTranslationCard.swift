import AppKit
import SwiftUI

/// Shows the exact source scope and its target-language expression from the coordinator.
/// Confirmation remains an explicit click; the coordinator consumes Return while this card is
/// visible, so opening a preview never makes the keyboard's normal confirm key edit the field.
struct LearningTranslationCard: View {
    let source: String
    let english: String
    let message: String
    let sourceLanguage: LearningLanguage?
    let targetLanguage: LearningLanguage
    let isSentence: Bool
    let accept: (() -> Void)?
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sourceLanguage.map { "\($0.label) → \(targetLanguage.label)" } ??
                 "表达预览 · 目标：\(targetLanguage.label)").font(.headline)
            Text(isSentence ? "范围：光标所在句子" : "范围：当前选区").font(.caption).foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sourceLanguage.map { "原文（\($0.label)）" } ?? "原文")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(source).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("目标表达（\(targetLanguage.label)）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(english)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if let accept { Button(isSentence ? "替换原句" : "替换选区", action: accept) }
                if !english.isEmpty { Button("复制目标表达") { copy(english) } }
                if !source.isEmpty { Button("复制原文") { copy(source) } }
                Button("取消 · Esc", action: cancel)
            }
        }.padding(16).frame(width: 388, height: 298)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
