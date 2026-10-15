import AppKit
import UniformTypeIdentifiers

/// A single standard application picker shared by App settings and per-app shortcuts. It returns
/// metadata only; the caller's existing settings model decides what to persist and where to navigate.
@MainActor
enum ApplicationBundlePicker {
    static func choose() -> ApplicationBundleMetadata? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return ApplicationBundleMetadata(appURL: url)
    }
}
