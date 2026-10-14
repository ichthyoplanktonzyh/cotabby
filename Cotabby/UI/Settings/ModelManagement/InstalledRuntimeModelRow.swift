import SwiftUI

/// Shared installed-file presentation. Selection stays with the page's task, while the download
/// manager answers whether any task or future power profile protects the shared file from deletion.
struct InstalledRuntimeModelRow: View {
    let model: RuntimeModelOption
    let selected: Bool
    @ObservedObject var downloads: ModelDownloadManager
    var select: (() -> Void)? = nil
    let delete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                if model.displayName != model.actualModelName {
                    Text(model.actualModelName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            } else {
                if let select {
                    Button(String(localized: "Select", table: "Learning"), action: select)
                        .buttonStyle(.borderless)
                }
                if downloads.isModelInUse(filename: model.filename) {
                    Text(String(localized: "In Use", table: "Learning"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(String(
                            localized: "This file is used by autocomplete, translation, chunk alignment, or a power profile.",
                            table: "Learning"
                        ))
                } else if downloads.canDeleteModel(filename: model.filename) {
                    Button(action: delete) { Image(systemName: "trash").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Delete \(model.filename)", table: "Learning"))
                }
            }
        }
    }
}
