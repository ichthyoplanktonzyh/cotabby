import XCTest
@testable import Cotabby

@MainActor
final class ContextBufferNavigationTests: XCTestCase {
    // Match the existing ContextBuffer tests' workaround for the app-hosted isolated-deinit shim.
    private static var retainedBuffers: [ContextBuffer] = []

    private func makeBuffer() -> ContextBuffer {
        let buffer = ContextBuffer()
        Self.retainedBuffers.append(buffer)
        return buffer
    }

    func test_identicalDraftInAnotherSessionAdvancesGenerationAndPredictionCacheKey() {
        let buffer = makeBuffer()
        let first = buffer.materialize(from: CotabbyTestFixtures.focusedInputSnapshot())
        let navigated = buffer.materialize(from: CotabbyTestFixtures.focusedInputSnapshot(focusChangeSequence: 2))
        XCTAssertGreaterThan(navigated.generation, first.generation)
        XCTAssertNotEqual(first.suggestionSessionIdentityKey, navigated.suggestionSessionIdentityKey)
        XCTAssertEqual(first.focusedInputIdentityKey, navigated.focusedInputIdentityKey, "Font geometry remains stable")
    }

    func test_surfaceChangeRejectsStaleGenerationEvenBeforeSequenceChanges() {
        let buffer = makeBuffer()
        let first = buffer.materialize(from: CotabbyTestFixtures.focusedInputSnapshot(windowTitle: "This chat"))
        let navigated = buffer.materialize(from: CotabbyTestFixtures.focusedInputSnapshot(windowTitle: "Other chat"))
        XCTAssertGreaterThan(navigated.generation, first.generation)
    }

    /// Retaining a visible tail and authorizing a late async result have different evidence needs.
    /// A missing title retires the old request even while the tail can survive that unreadable poll.
    func test_unreadableSurfaceFactRetiresInFlightGeneration() {
        let buffer = makeBuffer()
        let first = buffer.materialize(from: CotabbyTestFixtures.focusedInputSnapshot(windowTitle: "This chat"))
        let blankRead = buffer.materialize(from: CotabbyTestFixtures.focusedInputSnapshot())
        let readable = buffer.materialize(from: CotabbyTestFixtures.focusedInputSnapshot(windowTitle: "This chat"))
        XCTAssertGreaterThan(blankRead.generation, first.generation)
        XCTAssertGreaterThan(readable.generation, blankRead.generation)
    }

    func test_wrapperChurnAloneKeepsGeneration() {
        let buffer = makeBuffer()
        let first = buffer.materialize(from: CotabbyTestFixtures.focusedInputSnapshot())
        let refreshed = buffer.materialize(from: CotabbyTestFixtures.focusedInputSnapshot(elementIdentifier: "new-wrapper"))
        XCTAssertEqual(first.generation, refreshed.generation)
    }
}
