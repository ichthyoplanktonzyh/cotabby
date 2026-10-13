import Foundation
import Testing
@testable import Cotabby

/// Fake monotonic time isolates stage accounting from model speed; temporary preferences and a
/// content-free event sink verify debug boundaries without opening the user's logs or Keychain.
@MainActor
struct LearningRequestTelemetryTests {
    private let profile = LearningModelSnapshot(backend: .endpoint, localModel: "", template: .automatic,
        baseURL: "https://test.invalid/v1", endpointModel: "test-model", credentialRevision: 0)

    @Test
    func stageAndDisplayShareRequestIdentityAndKeepContentOutOfMetrics() async throws {
        let name = "cotabby.test.telemetry.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let metrics = PerformanceMetricsStore(userDefaults: defaults)
        var time: TimeInterval = 100
        var events: [(LearningRequestContext, String, [String: String])] = []
        let observer = LearningRequestTelemetry(metrics: metrics, trackingEnabled: { true }, now: { time },
            event: { events.append(($0, $1, $2)) })
        let value = try await LearningRequestTrace.$requestID.withValue("req_fixture") {
            try await observer.perform(source: .translation, profile: profile) {
                let m = try #require(LearningRequestTrace.measurement)
                m.beginGeneration(prompt: "PRIVATE_SOURCE")
                m.loaded(milliseconds: 0)
                time += 0.1; m.received("PRIVATE_RESULT")
                time += 0.2; m.usable()
                return "validated"
            }
        }
        #expect(value == "validated")
        time += 0.01
        observer.recordDisplay(source: .translation, requestID: "req_fixture")
        time += 1
        observer.recordDisplay(source: .translation, requestID: "req_fixture")
        let row = try #require(metrics.entries.first)
        #expect(row.source == .translation && row.outcome == .completed)
        #expect(row.latencyMs == 300 && row.firstOutputMs == 100 && row.usableResultMs == 300)
        #expect(row.displayMs == 310 && row.modelLoadMs == 0)
        #expect(events.allSatisfy { $0.0.requestID == "req_fixture" })
        #expect(Set(events.map { $0.0.operationID }).count == 1)
        #expect(events.filter { $0.1 == "displayed" }.count == 1)
        let blob = try #require(defaults.data(forKey: "cotabbyPerformanceMetricEntries"))
        #expect(!String(decoding: blob, as: UTF8.self).contains("PRIVATE"))
        #expect(!String(describing: events.map { $0.2 }).contains("PRIVATE"))
    }

    @Test(arguments: [false, true])
    func failureAndCancellationAreRecordedOnlyWhenTrackingIsEnabled(_ tracking: Bool) async throws {
        let name = "cotabby.test.telemetryFailure.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let metrics = PerformanceMetricsStore(userDefaults: defaults)
        let observer = LearningRequestTelemetry(metrics: metrics, trackingEnabled: { tracking })
        for cancel in [false, true] {
            do {
                try await observer.perform(source: .analysis, profile: profile) {
                    LearningRequestTrace.measurement?.beginGeneration(prompt: "PRIVATE_SOURCE")
                    if cancel { throw CancellationError() }
                    throw LearningFailure.message("PRIVATE_FAILURE")
                }
                Issue.record("Expected terminal failure")
            } catch {}
        }
        #expect(metrics.entries.count == (tracking ? 2 : 0))
        if tracking { #expect(metrics.entries.map(\.outcome) == [.failed, .cancelled]) }
        else { #expect(defaults.data(forKey: "cotabbyPerformanceMetricEntries") == nil) }
    }

    @Test
    func rejectionBeforeGenerationDoesNotPretendAnLLMRequestOccurred() async throws {
        let name = "cotabby.test.telemetryRejection.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let metrics = PerformanceMetricsStore(userDefaults: defaults)
        let observer = LearningRequestTelemetry(metrics: metrics, trackingEnabled: { true })
        do { try await observer.perform(source: .translation, profile: profile) { throw CancellationError() } }
        catch {}
        #expect(metrics.entries.isEmpty)
    }
}
