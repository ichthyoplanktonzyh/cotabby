import Combine
import XCTest
@testable import Cotabby

/// Tests the projection's publication contract separately from the existing pure warning policy:
/// irrelevant status changes stay local to panes, but a changed warning set reaches the sidebar.
@MainActor
final class SettingsAttentionModelTests: XCTestCase {
    private static var retained: [SettingsAttentionModel] = []

    func test_onlyChangedWarningCategoriesPublish() {
        let inputs = PassthroughSubject<SettingsAttentionEvaluator.Inputs, Never>()
        let model = SettingsAttentionModel(inputs: inputs.eraseToAnyPublisher())
        Self.retained.append(model)
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        func send(permissions: Bool = true, engine: SuggestionEngineKind = .llamaOpenSource,
                  failure: String? = nil, endpointError: String? = nil) {
            inputs.send(.init(permissionsGranted: permissions, selectedEngine: engine,
                              foundationModelAvailable: true, llamaRuntimeFailedReason: failure,
                              endpointConfigurationError: endpointError, endpointConnectionFailedReason: nil))
        }
        send()
        send(endpointError: "Unused endpoint is invalid")
        XCTAssertEqual(publications, 0)
        send(failure: "Model unavailable")
        XCTAssertEqual(model.categories, [.engineAndModel])
        XCTAssertEqual(publications, 1)
        send(failure: "A different runtime error")
        XCTAssertEqual(publications, 1, "The dot has not changed")
        send()
        XCTAssertTrue(model.categories.isEmpty)
        XCTAssertEqual(publications, 2)
        send(permissions: false)
        XCTAssertEqual(model.categories, [.permissions])
        send(permissions: false)
        XCTAssertEqual(publications, 3)
        send(engine: .openAICompatible, endpointError: "Missing model")
        XCTAssertEqual(model.categories, [.engineAndModel])
        XCTAssertEqual(publications, 4)
    }

    func test_renderMeasurementDoesNotCompleteAnObsoleteDestination() {
        var uptime: UInt64 = 1_000_000
        var events: [SettingsRenderDiagnostics.Event] = []
        let diagnostics = SettingsRenderDiagnostics(uptime: { uptime }) { events.append($0) }
        let first = diagnostics.begin(.writing)
        uptime += 1_000_000
        let second = diagnostics.begin(.general)
        diagnostics.firstLayout(.writing, generation: first)
        XCTAssertFalse(events.contains { $0.phase == "first-layout" })
        uptime += 2_000_000
        diagnostics.firstLayout(.general, generation: second)
        diagnostics.firstLayout(.general, generation: second)
        XCTAssertEqual(events.filter { $0.phase == "first-layout" }.count, 1)
        XCTAssertEqual(events.last?.milliseconds, 2)
    }

    func test_oldLayoutCannotFinishASecondVisitToTheSameCategory() {
        var events: [SettingsRenderDiagnostics.Event] = []
        let diagnostics = SettingsRenderDiagnostics { events.append($0) }
        let first = diagnostics.begin(.writing)
        diagnostics.begin(.general)
        let latest = diagnostics.begin(.writing)
        diagnostics.firstLayout(.writing, generation: first)
        XCTAssertFalse(events.contains { $0.phase == "first-layout" })
        diagnostics.firstLayout(.writing, generation: latest)
        XCTAssertEqual(events.last?.generation, latest)
        XCTAssertEqual(events.filter { $0.phase == "first-layout" }.count, 1)
    }
}
