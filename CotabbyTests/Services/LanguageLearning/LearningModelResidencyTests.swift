import Foundation
import Combine
import Testing
@testable import Cotabby

/// Resource policy tests never load a real GGUF. Empty selections and loopback-free fake endpoints
/// prove task eligibility and residency transitions independently from native model performance.
@MainActor
struct LearningModelResidencyTests {
    @Test
    func independentTasksReleaseOnGlobalPauseAndAnalysisDisable() async throws {
        let name = "cotabby.test.learningResidency.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let app = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        app.setGloballyEnabled(true)
        app.languageLearning.translationEnabled = true
        app.languageLearning.analysisEnabled = true
        let models = LearningModelCollection(settings: app.languageLearning,
            client: OpenAICompatibleAPIClient(session: URLSession(configuration: .ephemeral)), appSettings: app)
        #expect(models.translation.residency == .warm)
        #expect(models.analysis.residency == .onDemand)
        app.languageLearning.analysisEnabled = false
        models.reconcileResources()
        #expect(models.translation.residency == .warm)
        #expect(models.analysis.residency == .released)
        app.setGloballyEnabled(false)
        models.reconcileResources()
        #expect(models.translation.residency == .released)
        do { _ = try await models.translation.generate(prompt: "fixture", maxTokens: 1); Issue.record("Disabled work must cancel") }
        catch { #expect(error is CancellationError) }
        app.setGloballyEnabled(true)
        models.reconcileResources()
        #expect(models.translation.residency == .warm)
        models.shutdownSync()
    }

    @Test
    func sharedLowPowerMonitorImmediatelyChangesBothResidencies() async throws {
        let name = "cotabby.test.learningPowerMonitor.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let app = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        app.setGloballyEnabled(true)
        app.setLowPowerModeAutoDisableEnabled(true)
        app.languageLearning.translationEnabled = true
        app.languageLearning.analysisEnabled = true
        let monitor = FakePower()
        let models = LearningModelCollection(settings: app.languageLearning,
            client: OpenAICompatibleAPIClient(session: URLSession(configuration: .ephemeral)), appSettings: app, lowPower: monitor)
        #expect(models.translation.residency == .warm && models.analysis.residency == .onDemand)
        monitor.update(true)
        await waitUntil { models.translation.residency == .released && models.analysis.residency == .released }
        monitor.update(false)
        await waitUntil { models.translation.residency == .warm && models.analysis.residency == .onDemand }
        models.shutdownSync()
    }

    @Test
    func analysisIdleReleasesNativeContextAndItsNextRequestCanReload() async throws {
        let name = "cotabby.test.learningIdle.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let profile = LearningModelSettings(role: .analysis, defaults: defaults)
        let core = FakeNative()
        let controller = LearningModelController(profile: profile,
            client: OpenAICompatibleAPIClient(session: URLSession(configuration: .ephemeral)),
            core: core, localModelURL: { _ in URL(fileURLWithPath: "/fixture.gguf") })
        profile.localModel = "fixture.gguf"
        controller.idleReleaseDelay = .milliseconds(20)
        controller.applyResidency(.onDemand, generationAllowed: true)
        let observer = LearningRequestTelemetry()
        let output = try await LearningRequestTrace.$requestID.withValue("req_native_fixture") {
            try await observer.perform(source: .analysis, profile: profile.snapshot) {
                try await controller.generate(prompt: "fixture", maxTokens: 1)
            }
        }
        #expect(output == "Hello")
        #expect(core.recordedTrace?.requestID == "req_native_fixture")
        #expect(core.recordedTrace?.source == .analysis)
        #expect(controller.status == String(localized: "Ready", table: "Learning"))
        await waitUntil { core.unloadCount == 1 }
        #expect(controller.status == String(localized: "Not loaded", table: "Learning"))
        #expect(try await controller.generate(prompt: "fixture", maxTokens: 1) == "Hello")
        #expect(core.loadCount == 2)
        controller.applyResidency(.released, generationAllowed: false)
        await waitUntil { core.unloadCount == 2 }
        controller.shutdownSync()
    }

    @Test
    func cancelledLoadWithoutDeliveredReadyEventStillReleasesNativeMemory() async throws {
        let name = "cotabby.test.cancelledResident.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let profile = LearningModelSettings(role: .analysis, defaults: defaults)
        let core = FakeNative(failAfterLoad: true)
        let controller = LearningModelController(profile: profile,
            client: OpenAICompatibleAPIClient(session: URLSession(configuration: .ephemeral)),
            core: core, localModelURL: { _ in URL(fileURLWithPath: "/fixture.gguf") })
        profile.localModel = "fixture.gguf"
        controller.idleReleaseDelay = .milliseconds(20)
        controller.applyResidency(.onDemand, generationAllowed: true)
        do { _ = try await controller.generate(prompt: "fixture", maxTokens: 1); Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(core.loadCount == 1)
        await waitUntil { core.unloadCount == 1 }
        controller.shutdownSync()
    }

    @Test
    func queuedWarmupChecksLiveEligibilityBeforeStartingNativeLoad() async throws {
        let name = "cotabby.test.queuedWarmup.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let profile = LearningModelSettings(role: .translation, defaults: defaults)
        let core = FakeNative()
        let controller = LearningModelController(profile: profile,
            client: OpenAICompatibleAPIClient(session: URLSession(configuration: .ephemeral)),
            core: core, localModelURL: { _ in URL(fileURLWithPath: "/fixture.gguf") })
        profile.localModel = "fixture.gguf"
        var eligible = true
        controller.warmupEligibility = { eligible }
        controller.applyResidency(.warm, generationAllowed: true)
        eligible = false
        for _ in 0..<5 { await Task.yield() }
        #expect(core.loadCount == 0)
        controller.shutdownSync()
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Resource transition did not finish")
    }

    private final class FakePower: SuggestionLowPowerModeProviding {
        var isLowPowerModeEnabled = false
        let changes = PassthroughSubject<Bool, Never>()
        var lowPowerModeChanges: AnyPublisher<Bool, Never> { changes.eraseToAnyPublisher() }
        func update(_ value: Bool) { isLowPowerModeEnabled = value; changes.send(value) }
    }

    /// Native callbacks run on a detached queue, so even this counter fixture uses a lock. It
    /// models leases and residency only, not tokenization or the production implementation's locks.
    private nonisolated final class FakeNative: LearningLocalExecuting, @unchecked Sendable {
        let lock = NSLock()
        private var lease = UUID()
        private var resident = false
        private var loads = 0
        private var unloads = 0
        private var trace: LearningRequestContext?
        var recordedTrace: LearningRequestContext? { lock.withLock { trace } }
        private let failAfterLoad: Bool
        init(failAfterLoad: Bool = false) { self.failAfterLoad = failAfterLoad }
        var loadCount: Int { lock.withLock { loads } }
        var unloadCount: Int { lock.withLock { unloads } }
        func claim(_ id: UUID) { lock.withLock { lease = id } }
        func invalidate() -> UUID { lock.withLock { lease = UUID(); return lease } }
        func prepare(modelURL: URL, operationID: UUID, trace: LearningRequestContext?) throws {
            try lock.withLock {
                guard lease == operationID else { throw CancellationError() }
                self.trace = trace
                if !resident { resident = true; loads += 1 }
            }
        }
        func generate(modelURL: URL, template: LearningChatTemplate, prompt: String, maxTokens: Int,
            operationID: UUID, trace: LearningRequestContext?, onLoad: (@Sendable (Int) -> Void)?,
            onDelta: @Sendable (String) -> Void) throws -> String {
            try prepare(modelURL: modelURL, operationID: operationID, trace: trace)
            if failAfterLoad { throw CancellationError() }
            onLoad?(0); onDelta("Hello"); return "Hello"
        }
        func cancel(_ operation: UUID?) {}
        func unload(expectedLease: UUID?, trace: LearningRequestContext?) {
            lock.withLock {
                guard expectedLease == nil || expectedLease == lease, resident else { return }
                resident = false; unloads += 1
            }
        }
        func shutdownSync() { unload(expectedLease: nil, trace: nil) }
    }

    @Test
    func lowPowerDecisionReleasesBothNativeRolesAndRecoveryRestoresTheirPolicies() {
        for keepWarm in [false, true] {
            #expect(LocalRuntimeResidencyPolicy.residency(usesLocalModel: true, enabled: true,
                paused: true, keepWarm: keepWarm) == .released)
            #expect(LocalRuntimeResidencyPolicy.residency(usesLocalModel: true, enabled: true,
                paused: false, keepWarm: keepWarm) == (keepWarm ? .warm : .onDemand))
            #expect(LocalRuntimeResidencyPolicy.residency(usesLocalModel: false, enabled: true,
                paused: false, keepWarm: keepWarm) == .released)
        }
    }
}
