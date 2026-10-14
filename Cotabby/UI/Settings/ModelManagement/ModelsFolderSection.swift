import SwiftUI

/// One folder/source editor is reused by all task pages. The global LM Studio preference matches
/// the existing locator. The download manager notifies all app-owned runtimes when sources change;
/// the page callback also keeps previews and isolated settings fixtures current.
struct ModelsFolderSection: View {
    @ObservedObject var downloads: ModelDownloadManager
    let refresh: () -> Void
    @State private var lmStudioModelsURL: URL?
    @AppStorage(BundledRuntimeLocator.lmStudioSourceEnabledKey) private var lmStudioEnabled = false

    var body: some View {
        Section(String(localized: "Folder")) {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 8) {
                    Text(downloads.modelsDirectoryPath).font(.callout.monospaced())
                        .textSelection(.enabled).multilineTextAlignment(.trailing)
                    HStack(spacing: 8) {
                        Button(String(localized: "Open Folder")) { downloads.openModelsDirectory() }
                        Button(String(localized: "Refresh")) { downloads.refreshSearchDirectories(); refresh() }
                    }
                }
            } label: {
                SettingsRowLabel(
                    title: String(localized: "Models Folder"),
                    description: String(localized: "Where downloaded model files are stored on this Mac."),
                    systemImage: "folder"
                )
            }
            .settingsItem(.modelsFolder)
            Toggle(isOn: $lmStudioEnabled) {
                SettingsRowLabel(
                    title: String(localized: "Also Use LM Studio Models"),
                    description: lmStudioModelsURL == nil
                        ? String(localized: "Install LM Studio to load models from its library here.")
                        : String(localized: """
                        Add models from your LM Studio library (~/.lmstudio/models) to the picker above. Downloads still save to \
                        Lingrove's own folder.
                        """, table: "Learning"),
                    systemImage: "square.stack.3d.up"
                )
            }
            .disabled(lmStudioModelsURL == nil)
            .onChange(of: lmStudioEnabled) { _, _ in downloads.refreshSearchDirectories(); refresh() }
            .settingsItem(.lmStudio)
        }
        .onAppear {
            lmStudioModelsURL = BundledRuntimeLocator.lmStudioModelsDirectoryIfAvailable()
            if lmStudioModelsURL == nil, lmStudioEnabled { lmStudioEnabled = false }
        }
    }
}
