import Foundation
import XCTest
@testable import Cotabby

/// Fake native operations let tests hold load/decode at exact boundaries without a model or GPU.
/// These checks exercise admission, cancellation identity and draining rather than lock internals.
final class NativeRuntimeWorkGateTests: XCTestCase {
    func testCancellationOnlyReachesMatchingLiveOperation() throws {
        let gate = NativeRuntimeWorkGate(), first = UUID(), second = UUID()
        var cancelled: [Int32] = []
        try gate.withOperation {
            gate.publishTarget(operationID: first, sequenceID: 7) { cancelled.append($0) }
            gate.cancel(operationID: second) { cancelled.append($0) }
            XCTAssertTrue(cancelled.isEmpty)
            gate.cancel(operationID: first) { cancelled.append($0) }
            XCTAssertEqual(cancelled, [7])
            gate.clearTarget()
            gate.publishTarget(operationID: second, sequenceID: 7) { cancelled.append($0) }
            gate.cancel(operationID: first) { cancelled.append($0) }
            XCTAssertEqual(cancelled, [7], "A recycled sequence must not inherit an old request's abort")
        }
        gate.cancel { cancelled.append($0) }
        XCTAssertEqual(cancelled, [7], "Leaving an operation clears its cancellation target")
    }

    func testSupersededLeaseCannotEnterOrUnloadNewOwner() throws {
        let gate = NativeRuntimeWorkGate(), old = UUID(), new = UUID()
        gate.claim(old)
        let invalidated = gate.invalidate { _ in }
        gate.claim(new)
        XCTAssertThrowsError(try gate.withOperation(expectedLease: old) { XCTFail("Obsolete work entered") })
        var released = false
        XCTAssertFalse(gate.release(expectedLease: invalidated, cancelSequence: { _ in }) { released = true })
        XCTAssertFalse(released)
        try gate.withOperation(expectedLease: new) { }
    }

    func testReleaseClosesAdmissionAndDrainsBeforeUnloadEvenAfterTimeout() async throws {
        let gate = NativeRuntimeWorkGate(), operation = UUID()
        let entered = DispatchSemaphore(value: 0), finish = DispatchSemaphore(value: 0)
        let cancellation = DispatchSemaphore(value: 0), unloaded = DispatchSemaphore(value: 0)
        let worker = Task.detached {
            try gate.withOperation {
                gate.publishTarget(operationID: operation, sequenceID: 1) { _ in }
                entered.signal()
                _ = finish.wait(timeout: .now() + 5)
            }
        }
        let entryStatus = await wait(entered)
        XCTAssertEqual(entryStatus, .success)
        let release = Task.detached {
            gate.release(timeoutSeconds: 0, cancelSequence: { _ in cancellation.signal() }) { unloaded.signal() }
        }
        let cancelStatus = await wait(cancellation)
        XCTAssertEqual(cancelStatus, .success)
        XCTAssertThrowsError(try gate.withOperation { XCTFail("Release must close admission") })
        XCTAssertEqual(unloaded.wait(timeout: .now()), .timedOut,
            "Expired timeout must never free native state under the live worker")
        finish.signal()
        try await worker.value
        let didRelease = await release.value
        XCTAssertTrue(didRelease)
        let unloadStatus = await wait(unloaded)
        XCTAssertEqual(unloadStatus, .success)
        try gate.withOperation { }
    }

    func testNewClaimDuringDrainProtectsModelFromOldIdleRelease() async throws {
        let gate = NativeRuntimeWorkGate(), old = UUID(), new = UUID()
        gate.claim(old)
        let entered = DispatchSemaphore(value: 0), finish = DispatchSemaphore(value: 0)
        let cancellation = DispatchSemaphore(value: 0)
        let worker = Task.detached {
            try gate.withOperation(expectedLease: old) {
                gate.publishTarget(operationID: old, sequenceID: 2, expectedLease: old) { _ in }
                entered.signal()
                _ = finish.wait(timeout: .now() + 5)
            }
        }
        let entryStatus = await wait(entered)
        XCTAssertEqual(entryStatus, .success)
        let release = Task.detached {
            gate.release(expectedLease: old, cancelSequence: { _ in cancellation.signal() }) { }
        }
        let cancelStatus = await wait(cancellation)
        XCTAssertEqual(cancelStatus, .success)
        gate.claim(new)
        finish.signal()
        try await worker.value
        let didRelease = await release.value
        XCTAssertFalse(didRelease)
        try gate.withOperation(expectedLease: new) { }
    }

    func testPermanentShutdownRejectsFutureClaims() throws {
        let gate = NativeRuntimeWorkGate()
        gate.release(permanently: true, cancelSequence: { _ in }) { }
        let next = UUID()
        gate.claim(next)
        XCTAssertThrowsError(try gate.withOperation(expectedLease: next) { })
        XCTAssertThrowsError(try gate.withOperation { })
    }

    func testNewClaimAfterIdleUnloadCommitsWaitsAndCanReload() async throws {
        let gate = NativeRuntimeWorkGate(), old = UUID(), new = UUID()
        gate.claim(old)
        let unloading = DispatchSemaphore(value: 0), finishUnload = DispatchSemaphore(value: 0)
        let attempting = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let release = Task.detached {
            gate.release(expectedLease: old, cancelSequence: { _ in }) {
                unloading.signal()
                _ = finishUnload.wait(timeout: .now() + 5)
            }
        }
        let unloadStatus = await wait(unloading)
        XCTAssertEqual(unloadStatus, .success)
        gate.claim(new)
        let worker = Task.detached {
            attempting.signal()
            try gate.withOperation(expectedLease: new) { entered.signal() }
        }
        let attemptStatus = await wait(attempting)
        XCTAssertEqual(attemptStatus, .success)
        XCTAssertEqual(entered.wait(timeout: .now()), .timedOut)
        finishUnload.signal()
        let didRelease = await release.value
        XCTAssertTrue(didRelease)
        try await worker.value
        let entryStatus = await wait(entered)
        XCTAssertEqual(entryStatus, .success, "A new request must reload after committed idle teardown")
    }

    func testOperationFailureDoesNotKeepTheSessionBusy() throws {
        let gate = NativeRuntimeWorkGate()
        XCTAssertThrowsError(try gate.withOperation { throw NativeLlamaSessionError.loadFailed })
        try gate.withOperation { }
        XCTAssertTrue(gate.release(cancelSequence: { _ in }) { })
    }

    func testCancelledQueuedTaskExitsWhileTheCurrentOperationStaysBusy() async throws {
        let parked = DispatchSemaphore(value: 0)
        let gate = NativeRuntimeWorkGate(willWait: { parked.signal() }), currentID = UUID(), waitingID = UUID()
        let held = DispatchSemaphore(value: 0), finish = DispatchSemaphore(value: 0)
        let cancelled = DispatchSemaphore(value: 0)
        let holder = Task.detached {
            try gate.withOperation {
                gate.publishTarget(operationID: currentID, sequenceID: 9) { _ in }
                held.signal()
                _ = finish.wait(timeout: .now() + 5)
            }
        }
        let heldStatus = await wait(held)
        XCTAssertEqual(heldStatus, .success)
        let waiter = Task.detached {
            do { try gate.withOperation { XCTFail("The queued cancelled task must not enter") } }
            catch is CancellationError { cancelled.signal() }
        }
        let parkStatus = await wait(parked)
        XCTAssertEqual(parkStatus, .success)
        // The probe fires with the condition locked. cancel below acquires that same lock only
        // after condition.wait atomically parks this waiter, eliminating scheduling guesses.
        waiter.cancel()
        gate.cancel(operationID: waitingID) { _ in XCTFail("Cancellation must not abort the current holder") }
        let cancelStatus = await wait(cancelled)
        XCTAssertEqual(cancelStatus, .success, "Cancellation should wake a waiter before its holder completes")
        finish.signal()
        try await holder.value
        try await waiter.value
    }

    private func wait(_ semaphore: DispatchSemaphore) async -> DispatchTimeoutResult {
        await Task.detached { semaphore.wait(timeout: .now() + 5) }.value
    }
}
