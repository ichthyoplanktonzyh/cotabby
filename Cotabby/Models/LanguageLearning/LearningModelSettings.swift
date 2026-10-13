import Combine
import Foundation

/// One role owns its selection and credentials for the app lifetime. Translation and analysis
/// share download/storage infrastructure, but never inherit each other's server or API key.
nonisolated enum LearningModelRole: String, Sendable { case translation, analysis }
nonisolated enum LearningModelBackend: String, CaseIterable, Identifiable, Codable, Sendable {
    case local, endpoint
    var id: String { rawValue }
    var label: String { self == .local ? "内置开源模型（GGUF）" : "Endpoint" }
}

/// Known text-only instruction formats. Automatic selection reads the GGUF architecture; manual
/// formats support renamed models. This is separate from autocomplete's base continuation prompt.
nonisolated enum LearningChatTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic, hyMT, hyMT7, chatML, qwen3, gemma4, gemma4Large, gemma3, translateGemma, llama3
    var id: String { rawValue }
    /// Translation specialists have no alignment instruction contract. Keep their manual
    /// template on the translation page; this does not rewrite previously saved selections.
    static func available(for role: LearningModelRole) -> [Self] {
        allCases.filter { role == .translation || $0 != .translateGemma }
    }
    var label: String {
        switch self {
        case .automatic: "自动识别"
        case .hyMT: "Hy-MT / Hy-MT2 1.8B"
        case .hyMT7: "Hy-MT2 7B"
        case .chatML: "ChatML / Qwen2.5"
        case .qwen3: "Qwen3 / Qwen3.5（关闭思考）"
        case .gemma4: "Gemma 4 E2B / E4B（关闭思考）"
        case .gemma4Large: "Gemma 4 12B / 26B / 31B（关闭思考）"
        case .gemma3: "Gemma 3"
        case .translateGemma: "TranslateGemma（翻译专用）"
        case .llama3: "Llama 3"
        }
    }
}

/// Retained by one request. Credential revision participates in identity without copying a secret
/// into logs, UserDefaults or a cache key. Each role has its own immutable snapshot.
nonisolated struct LearningModelSnapshot: Equatable, Hashable, Sendable {
    let backend: LearningModelBackend
    let localModel: String
    let template: LearningChatTemplate
    let baseURL: String
    let endpointModel: String
    let credentialRevision: Int
}

/// A learning task's battery/AC choice. Server address and key remain owned by its role; a power
/// choice selects a model and local template without changing autocomplete's global profile.
nonisolated struct LearningPowerProfile: Codable, Equatable, Hashable, Sendable {
    var backend: LearningModelBackend
    var localModel: String
    var endpointModel: String
    var template: LearningChatTemplate
    static func local(_ filename: String) -> Self {
        .init(backend: .local, localModel: filename, endpointModel: "", template: .automatic)
    }
    static func endpoint(_ name: String) -> Self {
        .init(backend: .endpoint, localModel: "", endpointModel: name, template: .automatic)
    }
}

@MainActor
final class LearningModelSettings: ObservableObject {
    let role: LearningModelRole
    private let defaults: UserDefaults
    private let credentials: any OpenAICompatibleCredentialStoring
    private var prefix: String { "learning.\(role.rawValue)." }

    @Published var backend: LearningModelBackend { didSet { save(backend.rawValue, "backend"); publishEffectiveChange() } }
    @Published var localModel: String { didSet { save(localModel, "localModel"); publishEffectiveChange() } }
    @Published var template: LearningChatTemplate { didSet { save(template.rawValue, "template"); publishEffectiveChange() } }
    @Published var baseURL: String { didSet { save(baseURL, "baseURL"); publishEffectiveChange() } }
    @Published var endpointModel: String { didSet { save(endpointModel, "endpointModel"); publishEffectiveChange() } }
    @Published private(set) var credentialRevision = 0 { didSet { publishEffectiveChange() } }
    @Published private(set) var credentialMessage = ""
    @Published var powerSwitchingEnabled: Bool {
        didSet { defaults.set(powerSwitchingEnabled, forKey: prefix + "powerSwitchingEnabled"); publishEffectiveChange() }
    }
    @Published var batteryProfile: LearningPowerProfile { didSet { saveProfile(batteryProfile, "batteryProfile"); publishEffectiveChange() } }
    @Published var pluggedInProfile: LearningPowerProfile { didSet { saveProfile(pluggedInProfile, "pluggedInProfile"); publishEffectiveChange() } }
    @Published private(set) var isPluggedIn = true { didSet { publishEffectiveChange() } }
    private let effectiveChanges = PassthroughSubject<Void, Never>()
    private var lastPublishedSnapshot: LearningModelSnapshot?

    init(role: LearningModelRole, defaults: UserDefaults,
         credentials: (any OpenAICompatibleCredentialStoring)? = nil) {
        self.role = role
        self.defaults = defaults
        self.credentials = credentials ?? (defaults === UserDefaults.standard &&
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            ? KeychainOpenAICompatibleCredentialStore(namespace: "learning-\(role.rawValue)")
            : InMemoryOpenAICompatibleCredentialStore())
        let key = "learning.\(role.rawValue)."
        let legacy = role == .translation ? defaults.string(forKey: "learningInstructionModel") ?? "" : ""
        backend = LearningModelBackend(rawValue: defaults.string(forKey: key + "backend") ?? "")
            ?? (legacy.isEmpty ? .local : .endpoint)
        localModel = defaults.string(forKey: key + "localModel") ?? ""
        template = LearningChatTemplate(rawValue: defaults.string(forKey: key + "template") ?? "") ?? .automatic
        baseURL = defaults.string(forKey: key + "baseURL")
            ?? (legacy.isEmpty ? nil : defaults.string(forKey: "cotabbyOpenAICompatibleBaseURL"))
            ?? OpenAICompatibleEndpointConfiguration.defaultBaseURLString
        endpointModel = defaults.string(forKey: key + "endpointModel") ?? legacy
        let initialBackend = LearningModelBackend(rawValue: defaults.string(forKey: key + "backend") ?? "")
            ?? (legacy.isEmpty ? .local : .endpoint)
        let initial = LearningPowerProfile(backend: initialBackend,
            localModel: initialBackend == .local ? defaults.string(forKey: key + "localModel") ?? "" : "",
            endpointModel: initialBackend == .endpoint ? defaults.string(forKey: key + "endpointModel") ?? legacy : "",
            template: initialBackend == .local ? LearningChatTemplate(rawValue: defaults.string(forKey: key + "template") ?? "") ?? .automatic : .automatic)
        powerSwitchingEnabled = defaults.bool(forKey: key + "powerSwitchingEnabled")
        batteryProfile = defaults.data(forKey: key + "batteryProfile")
            .flatMap { try? JSONDecoder().decode(LearningPowerProfile.self, from: $0) } ?? initial
        pluggedInProfile = defaults.data(forKey: key + "pluggedInProfile")
            .flatMap { try? JSONDecoder().decode(LearningPowerProfile.self, from: $0) } ?? initial
        // Freeze the old selection once. Later completion endpoint changes cannot redirect learning.
        if defaults.object(forKey: key + "backend") == nil {
            save(backend.rawValue, "backend"); save(baseURL, "baseURL"); save(endpointModel, "endpointModel")
        }
        lastPublishedSnapshot = snapshot
    }

    var snapshot: LearningModelSnapshot {
        let selection = activeSelection
        // Dormant endpoint credentials and the other power source are not request identity. This
        // avoids unloading a local model while the user prepares an endpoint for future use.
        return .init(backend: selection.backend,
            localModel: selection.backend == .local ? selection.localModel : "",
            template: selection.backend == .local ? selection.template : .automatic,
            baseURL: selection.backend == .endpoint ? baseURL : "",
            endpointModel: selection.backend == .endpoint ? selection.endpointModel : "",
            credentialRevision: selection.backend == .endpoint ? credentialRevision : 0)
    }

    var activeSelection: LearningPowerProfile {
        powerSwitchingEnabled ? (isPluggedIn ? pluggedInProfile : batteryProfile) : manualSelection
    }
    private var manualSelection: LearningPowerProfile {
        .init(backend: backend, localModel: backend == .local ? localModel : "",
              endpointModel: backend == .endpoint ? endpointModel : "", template: backend == .local ? template : .automatic)
    }
    var referencedLocalModels: Set<String> {
        Set([localModel, batteryProfile.localModel, pluggedInProfile.localModel].filter { !$0.isEmpty })
    }
    func updatePowerSource(isPluggedIn: Bool) {
        if self.isPluggedIn != isPluggedIn { self.isPluggedIn = isPluggedIn }
    }
    func setPowerSwitchingEnabled(_ enabled: Bool) {
        if enabled, defaults.object(forKey: prefix + "batteryProfile") == nil {
            batteryProfile = manualSelection; pluggedInProfile = manualSelection
        }
        powerSwitchingEnabled = enabled
    }

    var changes: AnyPublisher<Void, Never> { effectiveChanges.eraseToAnyPublisher() }

    private func publishEffectiveChange() {
        let current = snapshot
        guard let previous = lastPublishedSnapshot, previous != current else { return }
        lastPublishedSnapshot = current
        // @Published emits before assignment. Request invalidation deliberately happens in
        // didSet so every subscriber captures the new, fully committed effective selection.
        effectiveChanges.send(())
    }

    func apiKey() throws -> String? { try credentials.readAPIKey() }
    func migrateLegacyCredential(from store: any OpenAICompatibleCredentialStoring) {
        guard role == .translation, defaults.object(forKey: prefix + "credentialMigrated") == nil else { return }
        do {
            if !endpointModel.isEmpty, try credentials.readAPIKey() == nil,
               let key = try store.readAPIKey() { try credentials.saveAPIKey(key) }
            defaults.set(true, forKey: prefix + "credentialMigrated")
        } catch { credentialMessage = error.localizedDescription }
    }
    @discardableResult func saveAPIKey(_ value: String?) -> Bool {
        do {
            let previous = try credentials.readAPIKey()
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed?.isEmpty == false ? trimmed : nil
            try credentials.saveAPIKey(value)
            if previous != normalized { credentialRevision += 1 }
            credentialMessage = (value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                ? "密钥已清除" : "密钥已保存到钥匙串"
            return true
        } catch { credentialMessage = error.localizedDescription; return false }
    }

    func reset() {
        powerSwitchingEnabled = false
        backend = .local; localModel = ""; template = .automatic
        baseURL = OpenAICompatibleEndpointConfiguration.defaultBaseURLString; endpointModel = ""
        batteryProfile = manualSelection; pluggedInProfile = manualSelection
        saveAPIKey(nil)
    }

    private func save(_ value: String, _ key: String) { defaults.set(value, forKey: prefix + key) }
    private func saveProfile(_ profile: LearningPowerProfile, _ key: String) {
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: prefix + key) }
    }
}
