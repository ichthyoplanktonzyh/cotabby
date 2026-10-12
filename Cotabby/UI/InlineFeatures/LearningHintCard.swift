import AppKit
import SwiftUI

/// Compact passive presentation: target expression is immediately visible, its definition is
/// optional. Copy writes only the clipboard; this view never receives a replacement callback.
struct LearningHintCard: View {
    let hint: LearningWordHint
    let source: String
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(source) → \(hint.expression)").font(.callout).lineLimit(2)
            DisclosureGroup("释义") { ScrollView { Text(hint.explanation).font(.caption) }.frame(maxHeight: 55) }
            HStack {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hint.expression, forType: .string)
                }
                Spacer()
                Button("关闭 · Esc", action: dismiss)
            }.font(.caption)
        }.padding(12).frame(width: 296, height: 126)
    }
}
