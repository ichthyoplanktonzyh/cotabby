import Combine
import Foundation

/// The settings window's small projection of the app graph: only which categories need attention.
/// SettingsCoordinator owns it alongside the window. Each pane still observes its own services;
/// the container no longer subscribes to every download, diagnostic or per-request counter update.
/// Combine carries incoming property values, rather than rereading an object during willSet.
@MainActor
final class SettingsAttentionModel: ObservableObject {
    @Published private(set) var categories: Set<SettingsCategory> = []
    private var subscription: AnyCancellable?

    nonisolated deinit {}

    init(inputs: AnyPublisher<SettingsAttentionEvaluator.Inputs, Never>) {
        subscription = inputs
            .map(SettingsAttentionEvaluator.categoriesNeedingAttention)
            .removeDuplicates()
            .sink { [weak self] categories in
                guard let self, self.categories != categories else { return }
                self.categories = categories
            }
    }

    convenience init(
        permissionManager: PermissionManager,
        suggestionSettings: SuggestionSettingsModel,
        foundationAvailability: FoundationModelAvailabilityService,
        runtimeModel: RuntimeBootstrapModel,
        connectionModel: OpenAICompatibleConnectionModel
    ) {
        let permissions = permissionManager.$accessibilityGranted
            .combineLatest(permissionManager.$inputMonitoringGranted)
            .map { $0 && $1 }.removeDuplicates()
        let engine = Publishers.CombineLatest4(
            suggestionSettings.$selectedEngine, suggestionSettings.$openAICompatibleBaseURL,
            suggestionSettings.$openAICompatibleModelName, suggestionSettings.$openAICompatibleAPIMode
        ).map(Self.endpointStatus).removeDuplicates()
        let foundation = foundationAvailability.$state.map(\.isAvailable).removeDuplicates()
        let runtimeFailure = runtimeModel.$state.map(\.failureDetail).removeDuplicates()
        let connectionFailure = connectionModel.$state.map(\.failureDetail).removeDuplicates()
        let inputs = Publishers.CombineLatest3(
            Publishers.CombineLatest(permissions, engine),
            Publishers.CombineLatest(foundation, runtimeFailure), connectionFailure
        ).map { first, second, endpointFailure in
            SettingsAttentionEvaluator.Inputs(
                permissionsGranted: first.0, selectedEngine: first.1.engine,
                foundationModelAvailable: second.0, llamaRuntimeFailedReason: second.1,
                endpointConfigurationError: first.1.error, endpointConnectionFailedReason: endpointFailure)
        }.eraseToAnyPublisher()
        self.init(inputs: inputs)
    }

    /// Only endpoint selection needs URL validation. Changes among valid destinations keep the
    /// warning set stable, while Home/Engine continue updating directly from their source models.
    private struct EngineAttention: Equatable {
        let engine: SuggestionEngineKind
        let error: String?
    }

    private static func endpointStatus(
        engine: SuggestionEngineKind, url: String, model: String, mode: OpenAICompatibleAPIMode
    ) -> EngineAttention {
        guard engine == .openAICompatible else { return EngineAttention(engine: engine, error: nil) }
        do {
            let configuration = try OpenAICompatibleEndpointConfiguration(baseURLString: url, modelName: model, apiMode: mode)
            return EngineAttention(engine: engine, error: configuration.modelName.isEmpty
                ? OpenAICompatibleEndpointError.emptyModelName.localizedDescription : nil)
        } catch {
            return EngineAttention(engine: engine, error: error.localizedDescription)
        }
    }
}
