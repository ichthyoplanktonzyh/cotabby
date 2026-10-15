import Foundation
import XCTest
@testable import Cotabby

/// Drives the real coordinator to pin that per-app behavior reaches the generation gate: with
/// mid-line completions off in an app, text after the caret on the same line means no request.
@MainActor
final class SuggestionCoordinatorPerAppTests: XCTestCase {
    private let app = "com.example.TestApp"

    private func requestCount(midLine: PerAppToggle, trailingText: String) async -> Int {
        let rig = makeCoordinatorRig(
            snapshot: CotabbyTestFixtures.focusedInputSnapshot(
                bundleIdentifier: app, precedingText: "Hello ", trailingText: trailingText
            ),
            settingsSnapshot: CotabbyTestFixtures.settingsSnapshot(
                debounceMilliseconds: 1,
                perAppBehaviors: [app: PerAppBehavior(midLineCompletions: midLine)]
            )
        )
        defer { rig.coordinator.stop() }
        rig.engine.resultProvider = { request in
            SuggestionResult(generation: request.generation, rawText: "there", text: "there", latency: 0.01)
        }
        rig.coordinator.schedulePrediction()
        // Give an allowed request time to arrive; a blocked one never does.
        try? await Task.sleep(nanoseconds: 200_000_000)
        return rig.engine.requests.count
    }

    func test_midLineOffSkipsRequestsWhenTextFollowsOnTheLine() async {
        let blocked = await requestCount(midLine: .off, trailingText: "world")
        XCTAssertEqual(blocked, 0)
    }

    func test_midLineOffStillSuggestsAtTheEndOfALine() async {
        let allowed = await requestCount(midLine: .off, trailingText: "")
        XCTAssertGreaterThan(allowed, 0)
    }

    func test_midLineDefaultSuggestsWithTextAfterTheCaret() async {
        let allowed = await requestCount(midLine: .useDefault, trailingText: "world")
        XCTAssertGreaterThan(allowed, 0)
    }
    func test_rebasedOffersRespectTheAppMidLinePolicy() {
        let raw = CotabbyTestFixtures.focusedInputSnapshot(
            bundleIdentifier: app, precedingText: "Hello ", trailingText: "world"
        )
        let rig = makeCoordinatorRig(snapshot: raw, settingsSnapshot: CotabbyTestFixtures.settingsSnapshot(
            perAppBehaviors: [app: PerAppBehavior(midLineCompletions: .off)]
        ))
        defer { rig.coordinator.stop() }
        XCTAssertNotNil(rig.coordinator.restartReason(forRebased: "a new sentence", raw: raw))
    }

    func test_rebasedOffersRespectTheAppsCommittedWordTypoPolicy() throws {
        let raw = CotabbyTestFixtures.focusedInputSnapshot(bundleIdentifier: app, precedingText: "Please recieve ")
        let rig = makeCoordinatorRig(snapshot: raw, settingsSnapshot: CotabbyTestFixtures.settingsSnapshot(
            suppressCompletionsOnTypo: false, offerTypoCorrections: false,
            perAppBehaviors: [app: PerAppBehavior(autocorrect: .on)]
        ))
        defer { rig.coordinator.stop() }
        guard rig.coordinator.spellChecker.isTypo("recieve") else {
            throw XCTSkip("Native spelling does not flag the English fixture in this environment")
        }
        XCTAssertNotNil(rig.coordinator.restartReason(forRebased: "the report tomorrow", raw: raw))
    }

    func test_changingInstructionsAtTheSamePrefixGeneratesAgainInsteadOfRestoringOldText() async {
        let rig = makeCoordinatorRig(
            snapshot: CotabbyTestFixtures.focusedInputSnapshot(bundleIdentifier: app, precedingText: "Hello "),
            settingsSnapshot: CotabbyTestFixtures.settingsSnapshot(
                debounceMilliseconds: 1, perAppBehaviors: [app: PerAppBehavior(instructions: "old notes")]
            )
        )
        defer { rig.coordinator.stop() }
        rig.engine.resultProvider = { request in
            let text = request.applicationInstructions == "new notes" ? "new words" : "old words"
            return SuggestionResult(generation: request.generation, rawText: text, text: text, latency: 0.01)
        }
        rig.coordinator.schedulePrediction()
        await waitUntil { rig.coordinator.overlayState.isVisible }
        XCTAssertEqual(rig.engine.requests.count, 1)

        rig.coordinator.handleSuggestionSettingsChange(CotabbyTestFixtures.settingsSnapshot(
            debounceMilliseconds: 1, perAppBehaviors: [app: PerAppBehavior(instructions: "new notes")]
        ))
        await waitUntil { rig.coordinator.overlayState.isVisible }

        XCTAssertEqual(rig.engine.requests.count, 2, "The old same-prefix cache must not bypass edited instructions")
        XCTAssertEqual(rig.engine.requests.last?.applicationInstructions, "new notes")
        XCTAssertEqual(rig.interactionState.activeSession?.remainingText, "new words")
    }

    func test_latePrefetchCannotRepopulateTheCacheAfterInstructionsChange() async {
        await checkPrefetchCache(changingSettings: true)
    }

    func test_prefetchStillPopulatesTheUnchangedCache() async {
        await checkPrefetchCache(changingSettings: false)
    }

    private func checkPrefetchCache(changingSettings: Bool) async {
        let raw = CotabbyTestFixtures.focusedInputSnapshot(bundleIdentifier: app, precedingText: "Hello ")
        let rig = makeCoordinatorRig(snapshot: raw)
        let gate = PrefetchGate()
        defer { gate.resume(); rig.coordinator.stop() }
        rig.engine.resultProvider = { request in await gate.wait(for: request) }
        let context = rig.interactionState.materializeContext(from: raw)
        let session = ActiveSuggestionSession(baseContext: context, fullText: "world ", latency: 0.01)
        rig.coordinator.prefetchContinuation(after: session, rawContext: raw)
        await waitUntil { gate.isWaiting }
        guard let request = rig.engine.requests.first else { return XCTFail("The prefetch must reach the engine") }

        if changingSettings {
            // Disabling prevents an unrelated ordinary generation: only the already suspended
            // prefetch can repopulate this cache after the app's instructions are edited.
            rig.coordinator.handleSuggestionSettingsChange(CotabbyTestFixtures.settingsSnapshot(
                isGloballyEnabled: false, perAppBehaviors: [app: PerAppBehavior(instructions: "new notes")]
            ))
        }
        gate.resume()
        await waitUntil { gate.didReturn }
        await Task.yield()
        let cached = rig.coordinator.suggestionAnchorCache.remainder(
            identityKey: request.context.focusedInputIdentityKey, precedingText: request.context.precedingText
        )
        if changingSettings {
            XCTAssertNil(cached, "A late result cannot revive a cache retired by a settings edit")
        } else {
            XCTAssertNotNil(cached, "Valid type-through prefetching must continue to work")
        }
    }

    /// Deliberately ignores cancellation so the test checks the coordinator's late-result guard,
    /// rather than relying on an engine to cancel cooperatively. The test always releases it.
    @MainActor
    private final class PrefetchGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var didReturn = false
        var isWaiting: Bool { continuation != nil }

        func wait(for request: SuggestionRequest) async -> SuggestionResult {
            await withCheckedContinuation { continuation = $0 }
            didReturn = true
            return SuggestionResult(generation: request.generation, rawText: "fresh words", text: "fresh words", latency: 0.01)
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }
}
