import CryptoKit
import Foundation
import Testing
@testable import Cotabby

/// Real store/vault regressions with private temporary archives and in-memory keys. The fixture
/// owns cleanup; retaining app-actor stores avoids the test host's inherited deallocation issue.
@MainActor
struct PerAppHistoryDeletionTests {
    private static var retained: [TypingHistoryStore] = []

    private func fixture(importer: (@Sendable (URL) throws -> [TypingHistoryRecord])? = nil) -> HistoryDeletionFixture {
        let fixture = HistoryDeletionFixture(importer: importer)
        Self.retained.append(fixture.store)
        return fixture
    }

    @Test
    func deletionPersistsOnlyTheOtherAppsAndKeepsPreferences() async throws {
        let fixture = fixture()
        defer { fixture.cleanup() }
        let file = try fixture.export(apps: ["com.apple.mail", "net.whatsapp.WhatsApp"])
        await fixture.store.importCotypistExport(from: file)
        fixture.store.setUsingHistory(true)
        fixture.store.setRecording(true)
        await fixture.store.deleteRecords(forBundleIdentifier: "com.apple.mail")
        #expect(fixture.store.recordCountsByApp == ["net.whatsapp.WhatsApp": 1])
        #expect(try fixture.vault.load().map(\.bundleIdentifier) == ["net.whatsapp.WhatsApp"])
        #expect(fixture.store.preferences.isUsingHistory)
        #expect(fixture.store.preferences.isRecording)
        #expect(!fixture.store.isDeletingRecords)
        #expect(fixture.store.appDeletionFailure == nil)
    }

    @Test
    func anImportStartedBeforeDeletionCannotRestoreThatAppsRecords() async throws {
        let gate = HistoryImportBarrier()
        let fixture = fixture(importer: { url in
            if url.lastPathComponent == "blocked.json" { try gate.wait() }
            return try CotypistExportImporter.records(fromExport: Data(contentsOf: url))
        })
        defer { gate.release(); fixture.cleanup() }
        await fixture.store.importCotypistExport(from: try fixture.export(apps: ["com.apple.mail", "other.app"]))
        let file = try fixture.export(apps: ["com.apple.mail"], name: "blocked.json")
        let task = Task { await fixture.store.importCotypistExport(from: file) }
        for _ in 0..<1000 {
            if gate.hasStarted { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(gate.hasStarted)
        await fixture.store.deleteRecords(forBundleIdentifier: "com.apple.mail")
        gate.release()
        await task.value
        #expect(fixture.store.recordCountsByApp == ["other.app": 1])
        #expect(try fixture.vault.load().allSatisfy { $0.bundleIdentifier == "other.app" })
    }

    @Test
    func deletedRecordsAreImmediatelyUnavailableToHistoryReaders() async throws {
        let fixture = fixture()
        defer { fixture.cleanup() }
        await fixture.store.importCotypistExport(from: try fixture.export(apps: Array(repeating: "com.apple.mail", count: 6)))
        fixture.store.setUsingHistory(true)
        let request = CotabbyTestFixtures.suggestionRequest(precedingText: "Thanks!\nBest regards, ")
        for _ in 0..<1000 {
            if fixture.store.phraseContinuation(for: request, engine: .llamaOpenSource) != nil { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(fixture.store.phraseContinuation(for: request, engine: .llamaOpenSource) != nil)
        await fixture.store.deleteRecords(forBundleIdentifier: "com.apple.mail")
        #expect(fixture.store.recordCount == 0)
        #expect(fixture.store.phraseContinuation(for: request, engine: .llamaOpenSource) == nil)
        #expect(fixture.store.historyExamples(for: request.context, engine: .llamaOpenSource).isEmpty)
    }

    @Test
    func failedWriteKeepsTheRecordsVisibleAndCanBeRetried() async throws {
        let fixture = fixture()
        defer { fixture.cleanup() }
        await fixture.store.importCotypistExport(from: try fixture.export(apps: ["com.apple.mail", "other.app"]))
        fixture.store.flush()
        fixture.keys.setReadFailure(true)
        await fixture.store.deleteRecords(forBundleIdentifier: "com.apple.mail")
        #expect(fixture.store.recordCount == 2)
        #expect(fixture.store.appDeletionFailure != nil)
        #expect(!fixture.store.isDeletingRecords)
        fixture.keys.setReadFailure(false)
        await fixture.store.deleteRecords(forBundleIdentifier: "com.apple.mail")
        #expect(fixture.store.recordCount == 1)
        #expect(fixture.store.appDeletionFailure == nil)
        #expect(try fixture.vault.load().allSatisfy { $0.bundleIdentifier == "other.app" })
    }

    @Test
    func aPartialDeleteDoesNotHideAGlobalKeyDeletionFailure() async throws {
        let fixture = fixture()
        defer { fixture.cleanup() }
        await fixture.store.importCotypistExport(from: try fixture.export(apps: ["com.apple.mail"]))
        fixture.store.flush()
        fixture.keys.setDeletionFailure(true)
        fixture.store.deleteAll()
        #expect(fixture.store.deletionError != nil)
        await fixture.store.deleteRecords(forBundleIdentifier: "com.apple.mail")
        #expect(fixture.store.recordCount == 0)
        #expect(fixture.store.deletionError != nil)
        fixture.keys.setDeletionFailure(false)
        fixture.store.deleteAll()
        #expect(fixture.store.deletionError == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.vault.fileURL.path))
    }

    @Test
    func quitFlushUsesThePendingFilteredSnapshotAndDeleteAllWaits() async throws {
        let fixture = fixture()
        defer { fixture.cleanup() }
        await fixture.store.importCotypistExport(from: try fixture.export(apps: ["com.apple.mail", "other.app"]))
        fixture.store.flush()
        let gate = HistoryImportBarrier()
        fixture.keys.blockNextRead(gate)
        let task = Task { await fixture.store.deleteRecords(forBundleIdentifier: "com.apple.mail") }
        for _ in 0..<1000 {
            if gate.hasStarted { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(gate.hasStarted)
        #expect(fixture.store.isDeletingRecords)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { gate.release() }
        fixture.store.deleteAll() // Rejected while another archive mutation is committing.
        #expect(fixture.store.recordCount == 2)
        fixture.store.flush() // The quit waits for the already prepared filtered snapshot.
        await task.value
        #expect(fixture.store.recordCountsByApp == ["other.app": 1])
        #expect(try fixture.vault.load().allSatisfy { $0.bundleIdentifier == "other.app" })
    }
}

/// Test-only ownership for a single archive, preference domain and key store.
@MainActor
private struct HistoryDeletionFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("per-app-history-\(UUID().uuidString)")
    let suite = "cotabby.test.per-app-history.\(UUID().uuidString)"
    let keys = HistoryDeletionKeys()
    let vault: TypingHistoryVault
    let store: TypingHistoryStore

    init(importer: (@Sendable (URL) throws -> [TypingHistoryRecord])?) {
        vault = TypingHistoryVault(fileURL: directory.appendingPathComponent("history.sealed"), keyStore: keys)
        let defaults = UserDefaults(suiteName: suite)!
        if let importer {
            store = TypingHistoryStore(vault: vault, userDefaults: defaults, loadsArchive: false, importRecords: importer)
        } else { store = TypingHistoryStore(vault: vault, userDefaults: defaults, loadsArchive: false) }
    }

    func export(apps: [String], name: String = "inputs.json") throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rows = apps.enumerated().map { index, app in
            ["appBundleIdentifier": app,
             "textUpToCursor": "Topic \(index): the cedar migration review is ready.\nThanks!\nBest regards, Senad"]
        }
        let url = directory.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: rows).write(to: url)
        return url
    }

    func cleanup() {
        store.deleteAll()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A controllable Keychain substitute, scoped to these tests and safe for detached archive writes.
nonisolated private final class HistoryDeletionKeys: TypingHistoryKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: SymmetricKey?
    private var fails = false
    private var deletionFails = false
    private var nextRead: HistoryImportBarrier?
    func setDeletionFailure(_ value: Bool) { lock.withLock { deletionFails = value } }
    func blockNextRead(_ gate: HistoryImportBarrier) { lock.withLock { nextRead = gate } }
    func setReadFailure(_ value: Bool) { lock.withLock { fails = value } }
    func existingKey() throws -> SymmetricKey? {
        let barrier = lock.withLock { let barrier = nextRead; nextRead = nil; return barrier }
        try barrier?.wait()
        return try lock.withLock {
            if fails { throw NSError(domain: "HistoryDeletionTest", code: 1) }
            return key
        }
    }
    func createKey() throws -> SymmetricKey {
        lock.withLock {
            let created = SymmetricKey(size: .bits256)
            key = created
            return created
        }
    }
    func deleteKey() throws {
        try lock.withLock {
            if deletionFails { throw NSError(domain: "HistoryKeyDeletionTest", code: 1) }
            key = nil
        }
    }
}

/// Holds only the detached import, so the main actor can finish an app deletion before it resumes.
nonisolated private final class HistoryImportBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var started = false
    var hasStarted: Bool { lock.withLock { started } }
    func wait() throws {
        lock.withLock { started = true }
        if gate.wait(timeout: .now() + 10) != .success { throw NSError(domain: "ImportBarrierTimeout", code: 1) }
    }
    func release() { gate.signal() }
}
