import AppKit
import CryptoKit
import SwiftUI
import Testing
@testable import Cotabby

/// Renders the real shared Form/row/shortcut components with isolated stores, so visual acceptance
/// never changes the user's preferences or requires a live AX field. Export is opt-in during QA.
@Suite(.serialized)
@MainActor
struct AppSettingsRenderingTests {
    private static var retained: [AnyObject] = []

    @Test(arguments: [false, true])
    func unifiedListAndDetailUseTheExistingSettingsChrome(dark: Bool) async throws {
        guard let output = ProcessInfo.processInfo.environment["LINGROVE_SETTINGS_RENDER_OUTPUT"] else { return }
        let suite = "cotabby.test.app-settings-render.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        model.addPerAppShortcutApp(bundleIdentifier: "com.apple.mail", displayName: "Mail")
        model.addPerAppShortcutApp(bundleIdentifier: "md.obsidian", displayName: "Obsidian")
        model.disableApplication(bundleIdentifier: "com.example.disabled", displayName: "Disabled Example")
        model.setDoubleTapFullAcceptance()
        model.setPerAppAcceptKey(bundleIdentifier: "com.apple.mail", displayName: "Mail", keyCode: 15, modifiers: .option, label: "⌥R")
        model.updatePerAppBehavior(bundleIdentifier: "com.apple.mail", displayName: "Mail") {
            $0.midLineCompletions = .off
            $0.instructions = "Keep replies concise and preserve product terminology."
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("app-settings-render-\(UUID().uuidString)")
        let history = TypingHistoryStore(
            vault: TypingHistoryVault(fileURL: directory.appendingPathComponent("history.sealed"), keyStore: RenderHistoryKeys()),
            userDefaults: defaults, loadsArchive: false
        )
        Self.retained.append(model)
        Self.retained.append(history)
        let destination = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let suffix = "\(language)-\(dark ? "dark" : "light")"
        try await paint(
            AppsPaneView(suggestionSettings: model, typingHistory: history), dark: dark,
            destination: destination.appendingPathComponent("apps-list-\(suffix).png")
        )
        try await paint(
            SettingsPaneScaffold {
                AppSettingsDetailView(
                    suggestionSettings: model, typingHistory: history,
                    bundleIdentifier: "com.apple.mail", displayName: "Mail", onBack: {}
                )
            }, dark: dark, destination: destination.appendingPathComponent("app-detail-\(suffix).png")
        )
        #expect(model.snapshot.perAppBehaviors["com.apple.mail"]?.midLineCompletions == .off)
        #expect(model.inheritedFullAcceptanceDisplayLabel(forBundleIdentifier: "com.apple.mail").contains("⌥R"))
    }

    private func paint<Content: View>(_ content: Content, dark: Bool, destination: URL) async throws {
        let host = NSHostingView(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 1200)
        let window = NSPanel(contentRect: CGRect(x: -3000, y: -3000, width: 800, height: 1200),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        defer { window.close() }
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(15))
        }
        #expect(host.bounds.width == 800)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: destination)
        #expect(png.count > 1000)
    }
}

/// This renderer never writes an archive; an in-memory key boundary keeps even accidental test
/// persistence away from the login Keychain.
nonisolated private struct RenderHistoryKeys: TypingHistoryKeyStore {
    private let key = SymmetricKey(size: .bits256)
    func existingKey() throws -> SymmetricKey? { key }
    func createKey() throws -> SymmetricKey { key }
    func deleteKey() throws {}
}
