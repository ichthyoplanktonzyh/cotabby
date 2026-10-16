import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import Cotabby

/// Opt-in Release measurements of the real settings tree, with private preferences and no running
/// inference, AX tracker, network request or history archive. The same fixture is used before/after
/// optimization; native installed-app tracing separately includes the live input pipeline.
@MainActor
final class SettingsPerformanceTests: XCTestCase {
    private static var retained: [SettingsPerformanceFixture] = []

    func test_warningProjectionReadsIncomingEndpointValuesAndRecovers() throws {
        let fixture = try SettingsPerformanceFixture()
        Self.retained.append(fixture)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let model = fixture.attention
        let baseline: Set<SettingsCategory> = fixture.permissions.requiredPermissionsGranted ? [] : [.permissions]
        fixture.settings.selectEngine(.llamaOpenSource)
        XCTAssertEqual(model.categories, baseline)
        fixture.settings.setOpenAICompatibleBaseURL("http://127.0.0.1:11434/v1")
        fixture.settings.setOpenAICompatibleModelName("")
        fixture.settings.selectEngine(.openAICompatible)
        XCTAssertEqual(model.categories, baseline.union([.engineAndModel]))
        fixture.settings.setOpenAICompatibleModelName("fixture-model")
        XCTAssertEqual(model.categories, baseline, "Use the new published model name, not its willSet-era value")
        fixture.settings.setOpenAICompatibleBaseURL("invalid endpoint")
        XCTAssertEqual(model.categories, baseline.union([.engineAndModel]))
        fixture.settings.setOpenAICompatibleBaseURL("https://example.invalid/v1")
        XCTAssertEqual(model.categories, baseline)
        fixture.settings.setOpenAICompatibleModelName("")
        XCTAssertEqual(model.categories, baseline.union([.engineAndModel]))
        fixture.settings.selectEngine(.appleIntelligence)
        XCTAssertEqual(model.categories, baseline, "An unused endpoint must not keep the engine warning active")
    }

    func test_backgroundActivityDoesNotRebuildWritingAndVisiblePanesStillUpdate() async throws {
        let fixture = try SettingsPerformanceFixture()
        Self.retained.append(fixture)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.defaults.set(SettingsCategory.writing.rawValue, forKey: "cotabbySettingsSelectedCategoryV2")
        let window = fixture.window()
        defer { window.contentView = nil; window.close() }
        try await settle(window)
        XCTAssertTrue(fixture.events.contains { $0.scope == "writing" })
        fixture.events.removeAll()
        fixture.quality.recordGenerated()
        fixture.performance.record(modelName: "fixture", latencyMs: 1)
        fixture.downloads.objectWillChange.send()
        fixture.search.searchQuery = "no network request"
        fixture.runtime.objectWillChange.send()
        try await settle(window)
        XCTAssertFalse(fixture.events.contains { $0.phase == "body" },
                       "Unrelated services must not invalidate the settings container or Writing")

        fixture.settings.setAddSpaceAfterAccept(!fixture.settings.addSpaceAfterAccept)
        try await settle(window)
        XCTAssertTrue(fixture.events.contains { $0.scope == "writing" },
                      "Writing must still observe its own live settings")
        window.contentView = nil
        window.close()

        fixture.defaults.set(SettingsCategory.performance.rawValue, forKey: "cotabbySettingsSelectedCategoryV2")
        let performanceWindow = fixture.window()
        defer { performanceWindow.contentView = nil; performanceWindow.close() }
        try await settle(performanceWindow)
        fixture.events.removeAll()
        fixture.quality.recordGenerated()
        fixture.performance.record(modelName: "live fixture", latencyMs: 2)
        try await settle(performanceWindow)
        XCTAssertTrue(fixture.events.contains { $0.scope == "performance" },
                      "The visible performance pane must retain its direct store subscriptions")
        XCTAssertFalse(fixture.events.contains { $0.scope == "container" })
    }

    func test_reportSettingsRenderAndBackgroundUpdateCost() async throws {
        guard let output = ProcessInfo.processInfo.environment["LINGROVE_SETTINGS_PERFORMANCE_OUTPUT"] else {
            throw XCTSkip("Set LINGROVE_SETTINGS_PERFORMANCE_OUTPUT for the local Release benchmark")
        }
        let fixture = try SettingsPerformanceFixture()
        Self.retained.append(fixture)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        var report: [String: Any] = [:]
        for category in [SettingsCategory.general, .appearance, .writing] {
            fixture.defaults.set(category.rawValue, forKey: "cotabbySettingsSelectedCategoryV2")
            var mounts: [Double] = [], layouts: [Double] = []
            for _ in 0..<8 {
                fixture.events.removeAll()
                let start = DispatchTime.now().uptimeNanoseconds
                let window = fixture.window()
                try await settle(window)
                mounts.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                layouts += fixture.events.filter { $0.phase == "first-layout" && $0.category == category }.compactMap(\.milliseconds)
                window.contentView = nil
                window.close()
            }
            report[category.rawValue] = ["cold_mount_ms": mounts, "selection_to_first_layout_ms": layouts]
        }

        fixture.defaults.set(SettingsCategory.writing.rawValue, forKey: "cotabbySettingsSelectedCategoryV2")
        let window = fixture.window()
        defer { window.contentView = nil; window.close() }
        try await settle(window)
        var updates: [String: Any] = [:]
        let sources: [(String, () -> Void)] = [
            ("quality", { fixture.quality.recordGenerated() }),
            ("performance", { fixture.performance.record(modelName: "fixture", latencyMs: 1) }),
            ("download-notification", { fixture.downloads.objectWillChange.send() }),
            ("search-query", { fixture.search.searchQuery += "x" })
        ]
        for (name, update) in sources {
            fixture.events.removeAll()
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<8 { update(); try await settle(window, turns: 2) }
            updates[name] = [
                "container_bodies": fixture.events.filter { $0.phase == "body" && $0.scope == "container" }.count,
                "writing_bodies": fixture.events.filter { $0.phase == "body" && $0.scope == "writing" }.count,
                "wall_ms": Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            ]
        }
        report["background_updates"] = updates
        let destination = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent("settings-performance.json"))
        XCTAssertTrue(report.keys.contains("writing"))
    }

    private func settle(_ window: NSWindow, turns: Int = 8) async throws {
        for _ in 0..<turns {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(4))
        }
    }
}

/// Owns every collaborator for one benchmark, mirroring the app graph without starting services.
/// Keeping stores alive until the test process exits also avoids the known back-deployed isolated
/// deinit runtime issue; windows themselves are detached and closed between samples.
@MainActor
private final class SettingsPerformanceFixture {
    let suite = "cotabby.test.settings-performance.\(UUID().uuidString)"
    let defaults: UserDefaults
    let settings: SuggestionSettingsModel
    let permissions = PermissionManager()
    let downloads: ModelDownloadManager
    let search = HuggingFaceSearchService()
    let performance: PerformanceMetricsStore
    let quality: SuggestionQualityMetricsStore
    let system = SystemMetricsStore()
    let runtime: RuntimeBootstrapModel
    let history: TypingHistoryStore
    let language: InterfaceLanguageSettingsModel
    let availability = FoundationModelAvailabilityService(provider: SettingsBenchmarkAvailability())
    let connection = OpenAICompatibleConnectionModel(client: OpenAICompatibleAPIClient())
    let updater = AppUpdateManager()
    var events: [SettingsRenderDiagnostics.Event] = []
    lazy var diagnostics = SettingsRenderDiagnostics { [weak self] in self?.events.append($0) }
    lazy var attention = SettingsAttentionModel(
        permissionManager: permissions, suggestionSettings: settings,
        foundationAvailability: availability, runtimeModel: runtime, connectionModel: connection)

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        settings.languageLearning.translationEnabled = true
        settings.languageLearning.translation.localModel = "translategemma-4b-it-Q4_K_M.gguf"
        performance = PerformanceMetricsStore(userDefaults: defaults)
        quality = SuggestionQualityMetricsStore(userDefaults: defaults)
        language = InterfaceLanguageSettingsModel(store: InterfaceLanguageSettingsStore(userDefaults: defaults, bundleIdentifier: suite))
        runtime = RuntimeBootstrapModel(runtimeManager: LlamaRuntimeManager(), userDefaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        downloads = ModelDownloadManager(runtimeDirectoryURL: directory)
        history = TypingHistoryStore(vault: TypingHistoryVault(fileURL: directory.appendingPathComponent("history"),
                                    keyStore: SettingsBenchmarkHistoryKeys()), userDefaults: defaults, loadsArchive: false)
    }

    func window() -> NSWindow {
        let view = SettingsContainerView(
            renderDiagnostics: diagnostics, attentionModel: attention, appUpdateManager: updater, permissionManager: permissions,
            permissionGuidanceController: PermissionGuidanceController(permissionManager: permissions),
            suggestionSettings: settings, interfaceLanguageSettings: language,
            openAICompatibleConnectionModel: connection, foundationModelAvailabilityService: availability,
            runtimeModel: runtime, modelDownloadManager: downloads, huggingFaceSearchService: search,
            performanceMetricsStore: performance, qualityMetricsStore: quality, systemMetricsStore: system,
            onShowWelcome: {}, onRestart: {}, clearEmojiHistory: {}, typingHistoryStore: history, onQuit: {})
            .defaultAppStorage(defaults)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 1060, height: 720)
        let window = NSPanel(contentRect: CGRect(x: -3000, y: -3000, width: 1060, height: 720),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }
}

@MainActor
private final class SettingsBenchmarkAvailability: FoundationModelAvailabilityProviding {
    var currentState: FoundationModelAvailabilityState { .available }
    func refresh() -> FoundationModelAvailabilityState { .available }
    func observe(onChange: @escaping @MainActor (FoundationModelAvailabilityState) -> Void) -> Task<Void, Never>? { nil }
}

nonisolated private struct SettingsBenchmarkHistoryKeys: TypingHistoryKeyStore {
    private let key = SymmetricKey(size: .bits256)
    func existingKey() throws -> SymmetricKey? { key }
    func createKey() throws -> SymmetricKey { key }
    func deleteKey() throws {}
}
