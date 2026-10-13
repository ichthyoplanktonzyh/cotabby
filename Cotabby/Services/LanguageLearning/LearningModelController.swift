import Combine
import Foundation
import Logging

/// App-owned model execution for one learning role. It reuses discovery and HTTP transport, while
/// its native engine, credentials, in-flight task and status belong only to this role. Views observe
/// this controller rather than constructing runtimes during SwiftUI body evaluation.
@MainActor
final class LearningModelController: ObservableObject {
    let profile: LearningModelSettings
    @Published private(set) var status = "未加载"
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
            stop(); status = "配置的 GGUF 文件不可用，请重新选择模型。"
            missingSelectedFile = true
        } else if missingSelectedFile {
            missingSelectedFile = false
            status = "未加载"
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

    func generate(prompt: String, maxTokens: Int, userOnly: Bool = false,
                  onDelta: (@MainActor (String) throws -> Void)? = nil) async throws -> String {
        guard generationAllowed, generationEligibility() else { throw CancellationError() }
        idleRelease?.cancel(); idleRelease = nil
        let measurement = LearningRequestTrace.measurement
        measurement?.beginGeneration(prompt: prompt)
        task?.cancel()
        let id = UUID(), snapshot = profile.snapshot
        taskID = id
        status = snapshot.backend == .local ? "加载 / 生成中" : "请求中"
        let work = Task { [self] in
            switch snapshot.backend {
            case .endpoint:
                let configuration = try endpoint(snapshot)
                if let onDelta {
                    var raw = ""
                    try await client.streamInstruction(configuration: configuration, apiKey: profile.apiKey(),
                        prompt: prompt, options: .init(maxPredictionTokens: maxTokens, temperature: userOnly ? 0.7 : 0.3,
                            topP: userOnly ? 0.6 : 0.9), userOnly: userOnly) { delta in
                        guard self.profile.snapshot == snapshot else { throw CancellationError() }
                        measurement?.received(delta)
                        raw += delta
                        try onDelta(delta)
                    }
                    return raw
                }
                let raw = try await client.generateInstruction(configuration: configuration, apiKey: profile.apiKey(),
                    prompt: prompt, options: .init(maxPredictionTokens: maxTokens, temperature: userOnly ? 0.7 : 0.3,
                        topP: userOnly ? 0.6 : 0.9), userOnly: userOnly,
                    onRawText: { measurement?.received($0) })
                return raw
            case .local:
                guard !snapshot.localModel.isEmpty else { throw LearningFailure.message("请为此任务选择内置 GGUF 模型。") }
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
            status = "就绪"
            task = nil
            scheduleIdleRelease()
            return result
        } catch {
            let cancelled = work.isCancelled || Task.isCancelled || taskID != id || profile.snapshot != snapshot || error is CancellationError
            if taskID == id {
                task = nil
                status = cancelled ? "已取消" : error.localizedDescription
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
                let text = try core.generate(modelURL: model, template: snapshot.template, prompt: prompt,
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
        status = "未加载"
    }

    func prepare() async {
        let snapshot = profile.snapshot
        guard !Task.isCancelled, generationAllowed, generationEligibility(), warmupEligibility(), residency == .warm, snapshot.backend == .local,
              !snapshot.localModel.isEmpty, preparedSnapshot != snapshot, task == nil else { return }
        idleRelease?.cancel(); idleRelease = nil
        let id = UUID(); taskID = id
        let core = self.core
        core.claim(id)
        status = "加载中"
        let trace = LearningRequestContext(requestID: RequestID.generate(), operationID: RequestID.generate(),
            source: profile.role == .translation ? .translation : .analysis,
            modelName: snapshot.localModel, engine: "llama")
        lastNativeTrace = trace
        LearningRequestLog.emit(trace, phase: "warmup_started")
        do {
            let modelURL = try localModelURL(snapshot.localModel)
            nativeMayBeResident = true
            let work = Task.detached { try core.prepare(modelURL: modelURL, operationID: id, trace: trace); return "" }
            task = work
            _ = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel(); core.cancel(id) }
            guard taskID == id, profile.snapshot == snapshot else { return }
            task = nil; preparedSnapshot = snapshot; status = "就绪"
            LearningRequestLog.emit(trace, phase: "warmup_finished")
        } catch {
            guard taskID == id else { return }
            task = nil; status = error is CancellationError ? "已取消" : error.localizedDescription
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

