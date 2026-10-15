import Combine
import Foundation
import Logging

/// App-owned model execution for one learning role. It reuses discovery and HTTP transport, while
/// its native engine, credentials, in-flight task and status belong only to this role. Views observe
/// this controller rather than constructing runtimes during SwiftUI body evaluation.
@MainActor
final class LearningModelController: ObservableObject {
    let profile: LearningModelSettings
    @Published private(set) var status = String(localized: "Not loaded", table: "Learning",
        comment: "Initial status shown in settings when this learning model is not resident.")
    @Published private(set) var availableModels: [RuntimeModelOption] = []
    let endpointConnection: OpenAICompatibleConnectionModel
    var endpointModels: [OpenAICompatibleModelOption] { endpointConnection.models }
    private let core: any LearningLocalExecuting
    private let localModelURL: (String) throws -> URL
    private let client: OpenAICompatibleAPIClient
    private var task: Task<String, Error>?
    private var taskID = UUID()
    private var subscriptions = Set<AnyCancellable>()
    private var missingSelectedFile = false
    private var preparedSnapshot: LearningModelSnapshot?
    private var nativeMayBeResident = false
    private var lastNativeTrace: LearningRequestContext?
    private var warmupWork: Task<Void, Never>?
    private var warmupID = UUID()
    /// Live policy reads close the gap between a @Published edit and the coalesced UI update.
    var generationEligibility: () -> Bool = { true }
    var warmupEligibility: () -> Bool = { true }
    private var idleRelease: Task<Void, Never>?
    private var generationAllowed = true
    private(set) var residency: LocalRuntimeResidency = .onDemand
    /// Analysis answers are cached by the coordinator; its native weights can be released between
    /// sessions. Tests inject a short deadline without touching the user's settings or model files.
    var idleReleaseDelay: Duration = .seconds(60)

    init(profile: LearningModelSettings, client: OpenAICompatibleAPIClient,
         core: any LearningLocalExecuting = LearningLocalRuntime(),
         localModelURL: @escaping (String) throws -> URL = {
             try BundledRuntimeLocator().resolve(configuration: .default, selectedModelFilename: $0).modelFileURL
         }) {
        self.core = core; self.localModelURL = localModelURL
        self.profile = profile
        self.client = client
        endpointConnection = OpenAICompatibleConnectionModel(client: client)
        refreshModels()
        profile.changes.sink { [weak self] in self?.stop() }.store(in: &subscriptions)
        endpointConnection.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        Publishers.Merge(profile.$baseURL.dropFirst().map { _ in () },
            profile.$credentialRevision.dropFirst().map { _ in () })
            .sink { [weak self] in self?.endpointConnection.invalidate() }.store(in: &subscriptions)
    }

    func refreshModels() {
        availableModels = BundledRuntimeLocator().availableModels(configuration: .default)
        let selection = profile.snapshot
        if selection.backend == .local, !selection.localModel.isEmpty,
           !availableModels.contains(where: { $0.filename == selection.localModel }) {
            stop()
            status = String(localized: "The configured GGUF file is unavailable. Choose a model again.",
                table: "Learning", comment: "Status shown when a selected local model file can no longer be found.")
            missingSelectedFile = true
        } else if missingSelectedFile {
            missingSelectedFile = false
            status = String(localized: "Not loaded", table: "Learning",
                comment: "Status shown in settings when this learning model is not resident.")
        }
    }

    func discoverEndpoint() async {
        do {
            // Discovery remains available when this task runs locally. Use the durable endpoint
            // fields rather than the canonical generation snapshot, which omits dormant values.
            let configuration = try OpenAICompatibleEndpointConfiguration(baseURLString: profile.baseURL,
                modelName: profile.endpointModel, apiMode: .chatCompletions)
            await endpointConnection.refresh(configuration: configuration, apiKey: try profile.apiKey())
        } catch {
            endpointConnection.setFailure(error.localizedDescription)
        }
    }

    /// Connect has the same explicit draft-submit behavior as completion. A failed Keychain
    /// write never falls through to a request authenticated by an older saved credential.
    func connect(using draft: String?) async {
        guard profile.saveAPIKey(draft) else { endpointConnection.setFailure(profile.credentialMessage); return }
        await discoverEndpoint()
    }
    func resetEndpointBaseURL() { profile.baseURL = OpenAICompatibleEndpointConfiguration.defaultBaseURLString }

    /// Freeze a complete translation request before transport. Native planning borrows this role's
    /// serialized vocabulary off MainActor; endpoints use the disclosed estimate. A profile edit
    /// invalidates the lease, preventing preparation from handing text to a newly selected server.
    func translationPlan(
        input: LearningTranslationInput, sourceLanguage: LearningLanguage,
        targetLanguage: LearningLanguage, output: Int
    ) async throws -> LearningTranslationPrompt.Request {
        guard generationAllowed, generationEligibility() else { throw CancellationError() }
        let snapshot = profile.snapshot
        if snapshot.backend == .endpoint {
            let work = Task.detached(priority: .userInitiated) {
                try LearningTranslationBudget.prompt(
                    input: input, sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage, family: .init(endpointModel: snapshot.endpointModel),
                    total: snapshot.contextWindowTokens, output: output, estimated: true
                ) { text in
                    try Task.checkCancellation()
                    return ModelContextBudget.estimatedTokens(text)
                }
            }
            let result = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            try Task.checkCancellation()
            guard profile.snapshot == snapshot, generationAllowed, generationEligibility() else { throw CancellationError() }
            return result
        }
        guard !snapshot.localModel.isEmpty else {
            throw LearningFailure.message(String(localized: "Choose a local GGUF model for this task.", table: "Learning"))
        }
        idleRelease?.cancel(); idleRelease = nil
        task?.cancel(); task = nil
        let id = UUID(), core = core, url = try localModelURL(snapshot.localModel)
        taskID = id
        core.claim(id)
        nativeMayBeResident = true
        let trace = LearningRequestTrace.measurement?.context
        lastNativeTrace = trace
        let work = Task.detached(priority: .userInitiated) {
            try core.translationPlan(
                configuration: .init(modelURL: url, template: snapshot.template, contextWindowTokens: snapshot.contextWindowTokens),
                input: input, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
                output: output, operationID: id, trace: trace)
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel(); core.cancel(id)
            }
            try Task.checkCancellation()
            guard taskID == id, profile.snapshot == snapshot, generationAllowed, generationEligibility() else { throw CancellationError() }
            return result
        } catch {
            // Planning can load a vocabulary and then reject an oversized target. That failure
            // must still retire an on-demand native allocation, just like decode failures do.
            if taskID == id { scheduleIdleRelease() }
            throw error
        }
    }

    func generate(prompt: String, maxTokens: Int, userOnly: Bool = false,
                  sampling: LearningInstructionSampling? = nil,
                  onDelta: (@MainActor (String) throws -> Void)? = nil) async throws -> String {
        guard generationAllowed, generationEligibility() else { throw CancellationError() }
        idleRelease?.cancel(); idleRelease = nil
        let measurement = LearningRequestTrace.measurement
        measurement?.beginGeneration(prompt: prompt)
        task?.cancel()
        let id = UUID(), snapshot = profile.snapshot
        let sampling = sampling ?? (userOnly ? .hyMT : .standard)
        taskID = id
        status = snapshot.backend == .local
            ? String(localized: "Loading / generating", table: "Learning",
                comment: "Model status while a local learning model loads or generates a result.")
            : String(localized: "Requesting", table: "Learning",
                comment: "Model status while a learning request is being sent to its configured endpoint.")
        let work = Task { [self] in
            switch snapshot.backend {
            case .endpoint:
                let configuration = try endpoint(snapshot)
                if let onDelta {
                    var raw = ""
                    try await client.streamInstruction(configuration: configuration, apiKey: profile.apiKey(),
                        prompt: prompt, options: .init(maxPredictionTokens: maxTokens, temperature: sampling.temperature,
                            topP: sampling.topP), userOnly: userOnly) { delta in
                        guard self.profile.snapshot == snapshot else { throw CancellationError() }
                        measurement?.received(delta)
                        try onDelta(delta)
                        // Role-specific byte/eligibility checks run before this retained buffer grows.
                        // Invalid output must not be accumulated first and rejected afterwards.
                        raw += delta
                    }
                    return raw
                }
                let raw = try await client.generateInstruction(configuration: configuration, apiKey: profile.apiKey(),
                    prompt: prompt, options: .init(maxPredictionTokens: maxTokens, temperature: sampling.temperature,
                        topP: sampling.topP), userOnly: userOnly,
                    onRawText: { measurement?.received($0) })
                return raw
            case .local:
                guard !snapshot.localModel.isEmpty else {
                    throw LearningFailure.message(String(localized: "Choose a local GGUF model for this task.",
                        table: "Learning", comment: "Error shown when local generation starts without a selected model."))
                }
                let modelURL = try localModelURL(snapshot.localModel)
                return try await runLocal(model: modelURL, snapshot: snapshot, prompt: prompt,
                                          maxTokens: maxTokens, id: id, onDelta: onDelta)
            }
        }
        task = work
        do {
            let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            guard taskID == id, profile.snapshot == snapshot else { throw CancellationError() }
            status = String(localized: "Ready", table: "Learning",
                comment: "Model status after the learning request completes successfully.")
            task = nil
            scheduleIdleRelease()
            return result
        } catch {
            let cancelled = work.isCancelled || Task.isCancelled || taskID != id || profile.snapshot != snapshot || error is CancellationError
            if taskID == id {
                task = nil
                status = cancelled
                    ? String(localized: "Canceled", table: "Learning",
                        comment: "Model status after a learning request is canceled.")
                    : error.localizedDescription
                scheduleIdleRelease()
            }
            if cancelled { throw CancellationError() }
            throw error
        }
    }

    private func runLocal(model: URL, snapshot: LearningModelSnapshot, prompt: String, maxTokens: Int,
                          id: UUID, onDelta: (@MainActor (String) throws -> Void)?) async throws -> String {
        let core = self.core
        try Task.checkCancellation()
        core.claim(id)
        let measurement = LearningRequestTrace.measurement
        let trace = measurement?.context
        nativeMayBeResident = true
        lastNativeTrace = trace
        let pair = AsyncThrowingStream<NativeEvent, Error>.makeStream()
        let nativeTask = Task.detached(priority: profile.role == .translation ? .userInitiated : .utility) {
            do {
                let text = try core.generate(configuration: .init(modelURL: model, template: snapshot.template,
                    contextWindowTokens: snapshot.contextWindowTokens), prompt: prompt,
                    maxTokens: maxTokens, operationID: id, trace: trace,
                    onLoad: { pair.continuation.yield(.loaded($0)) }) { pair.continuation.yield(.text($0)) }
                pair.continuation.finish()
                return text
            } catch {
                pair.continuation.finish(throwing: error)
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            do {
                for try await event in pair.stream {
                    try Task.checkCancellation()
                    guard profile.snapshot == snapshot else { throw CancellationError() }
                    switch event {
                    case .loaded(let milliseconds):
                        preparedSnapshot = snapshot
                        measurement?.loaded(milliseconds: milliseconds)
                    case .text(let delta): measurement?.received(delta); try onDelta?(delta)
                    }
                }
                return try await nativeTask.value
            } catch { nativeTask.cancel(); core.cancel(id); throw error }
        } onCancel: { nativeTask.cancel(); core.cancel(id) }
    }

    private enum NativeEvent: Sendable { case loaded(Int), text(String) }

    private func endpoint(_ snapshot: LearningModelSnapshot) throws -> OpenAICompatibleEndpointConfiguration {
        try .init(baseURLString: snapshot.baseURL, modelName: snapshot.endpointModel, apiMode: .chatCompletions)
    }

    func stop() {
        warmupID = UUID(); warmupWork?.cancel(); warmupWork = nil
        idleRelease?.cancel(); idleRelease = nil
        let trace = lastNativeTrace
        if nativeMayBeResident, let trace { LearningRequestLog.emit(trace, phase: "runtime_release_requested") }
        nativeMayBeResident = false; lastNativeTrace = nil; preparedSnapshot = nil
        taskID = UUID()
        task?.cancel(); task = nil
        let lease = core.invalidate()
        Task.detached { [core] in core.unload(expectedLease: lease, trace: trace) }
        status = String(localized: "Not loaded", table: "Learning",
            comment: "Model status after the local learning model is unloaded.")
    }

    func prepare() async {
        let snapshot = profile.snapshot
        guard !Task.isCancelled, generationAllowed, generationEligibility(), warmupEligibility(), residency == .warm, snapshot.backend == .local,
              !snapshot.localModel.isEmpty, preparedSnapshot != snapshot, task == nil else { return }
        idleRelease?.cancel(); idleRelease = nil
        let id = UUID(); taskID = id
        let core = self.core
        core.claim(id)
        status = String(localized: "Loading", table: "Learning",
            comment: "Model status while preparing the local learning model.")
        let trace = LearningRequestContext(requestID: RequestID.generate(), operationID: RequestID.generate(),
            source: profile.role == .translation ? .translation : .analysis,
            modelName: snapshot.localModel, engine: "llama")
        lastNativeTrace = trace
        LearningRequestLog.emit(trace, phase: "warmup_started")
        do {
            let modelURL = try localModelURL(snapshot.localModel)
            nativeMayBeResident = true
            let work = Task.detached {
                try core.prepare(modelURL: modelURL, contextWindowTokens: snapshot.contextWindowTokens, operationID: id, trace: trace)
                return ""
            }
            task = work
            _ = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel(); core.cancel(id) }
            guard taskID == id, profile.snapshot == snapshot else { return }
            task = nil; preparedSnapshot = snapshot
            status = String(localized: "Ready", table: "Learning",
                comment: "Model status after the local learning model is prepared.")
            LearningRequestLog.emit(trace, phase: "warmup_finished")
        } catch {
            guard taskID == id else { return }
            task = nil
            status = error is CancellationError
                ? String(localized: "Canceled", table: "Learning",
                    comment: "Model status after local model preparation is canceled.")
                : error.localizedDescription
            LearningRequestLog.emit(trace, phase: error is CancellationError ? "warmup_cancelled" : "warmup_failed",
                details: ["error_type": String(reflecting: type(of: error))])
        }
    }

    /// The collection is the policy owner; the controller applies decisions without sharing a
    /// native context with another role. Repeated identical decisions do not reload the model.
    func applyResidency(_ decision: LocalRuntimeResidency, generationAllowed: Bool) {
        self.generationAllowed = generationAllowed
        let changed = residency != decision
        residency = decision
        if decision == .released {
            if !generationAllowed {
                if changed || task != nil || nativeMayBeResident || warmupWork != nil { stop() }
            } else if nativeMayBeResident {
                // Endpoint eligibility and native residency are separate. Releasing leftover
                // local memory must not cancel an eligible HTTP request during another role's edit.
                preparedSnapshot = nil; nativeMayBeResident = false
                let trace = lastNativeTrace; lastNativeTrace = nil
                let lease = core.invalidate()
                Task.detached { [core] in core.unload(expectedLease: lease, trace: trace) }
            }
        } else if decision == .warm {
            idleRelease?.cancel(); idleRelease = nil
            guard warmupWork == nil else { return }
            let id = UUID(); warmupID = id
            warmupWork = Task { [weak self] in
                guard let self, self.warmupID == id, !Task.isCancelled else { return }
                await self.prepare()
                if self.warmupID == id { self.warmupWork = nil }
            }
        } else {
            warmupID = UUID(); warmupWork?.cancel(); warmupWork = nil
            if task == nil { scheduleIdleRelease() }
        }
    }

    private func scheduleIdleRelease() {
        idleRelease?.cancel(); idleRelease = nil
        guard residency == .onDemand, nativeMayBeResident, task == nil else { return }
        idleRelease = Task { [weak self, idleReleaseDelay] in
            do { try await Task.sleep(for: idleReleaseDelay) } catch { return }
            guard let self, self.residency == .onDemand, self.task == nil else { return }
            self.stop()
        }
    }

    func shutdownSync() {
        warmupID = UUID(); warmupWork?.cancel(); warmupWork = nil
        idleRelease?.cancel(); idleRelease = nil
        task?.cancel(); task = nil
        core.shutdownSync()
    }
}

