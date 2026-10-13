import Foundation

/// Serializes one native owner's work and drains it before model release. Autocomplete, translation
/// and analysis each own a gate through their session; this shares safety rules, never native state.
/// A condition lets release close admission before waiting, while cancellation can reach the live
/// sequence without waiting behind its decode. No C++ pointer is stored in this helper.
nonisolated final class NativeRuntimeWorkGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var busy = false
    private var releasesPending = 0
    private var terminated = false
    private var lease = UUID()
    private var target: (operationID: UUID, sequenceID: Int32)?
    private let willWait: (@Sendable () -> Void)?

    /// A nonblocking probe lets concurrency tests observe the exact park boundary. Production
    /// sessions leave it nil. It runs under the control lock and must never reenter the gate.
    init(willWait: (@Sendable () -> Void)? = nil) {
        self.willWait = willWait
    }

    func claim(_ operationID: UUID) {
        condition.lock()
        defer { condition.broadcast(); condition.unlock() }
        if !terminated { lease = operationID }
    }

    func invalidate(cancelSequence: (Int32) -> Void) -> UUID {
        condition.lock()
        defer { condition.broadcast(); condition.unlock() }
        lease = UUID()
        if let target { cancelSequence(target.sequenceID) }
        return lease
    }

    func validate(expectedLease: UUID) throws {
        try Task.checkCancellation()
        condition.lock()
        defer { condition.unlock() }
        guard !terminated, releasesPending == 0, lease == expectedLease else { throw CancellationError() }
    }

    /// All vocabulary/cache/load/decode access occurs inside this scope. Queued work rechecks its
    /// lease and task cancellation after waking, so it cannot enter after a stop or model switch.
    func withOperation<T>(expectedLease: UUID? = nil, checkCancellation: Bool = true,
                          _ body: () throws -> T) throws -> T {
        condition.lock()
        while (busy || releasesPending > 0) && eligible(expectedLease: expectedLease, checkCancellation: checkCancellation) {
            // A fresh learning claim may arrive after idle release has committed to unloading.
            // It waits, then reloads normally. Autocomplete has no lease and rejects admission
            // during stop; permanent shutdown and obsolete leases are always rejected.
            if releasesPending > 0 && expectedLease == nil { break }
            willWait?()
            condition.wait()
        }
        guard admits(expectedLease: expectedLease, checkCancellation: checkCancellation) else {
            condition.unlock()
            throw CancellationError()
        }
        busy = true
        condition.unlock()
        defer { finishOperation() }
        return try body()
    }

    func publishTarget(operationID: UUID, sequenceID: Int32, expectedLease: UUID? = nil,
                       cancelSequence: (Int32) -> Void) {
        condition.lock()
        defer { condition.unlock() }
        target = (operationID, sequenceID)
        // A stop can arrive while tokenization has no sequence to cancel. Publishing closes that
        // gap before prefill begins, including cancellation that landed in a queued operation.
        if !admits(expectedLease: expectedLease, checkCancellation: true) { cancelSequence(sequenceID) }
    }

    func clearTarget() {
        condition.lock()
        target = nil
        condition.unlock()
    }

    func cancel(operationID: UUID? = nil, cancelSequence: (Int32) -> Void) {
        condition.lock()
        // A cancelled queued task has no live sequence. Wake it anyway so it can observe task
        // cancellation without waiting for somebody else's model load or decode to finish.
        defer { condition.broadcast(); condition.unlock() }
        guard let target, operationID == nil || target.operationID == operationID else { return }
        // Hold the small control lock through native cancellation: a target cannot be cleared and
        // its sequence destroyed/recycled between identity validation and setting the abort flag.
        cancelSequence(target.sequenceID)
    }

    /// Returns false for an obsolete idle-release lease. Release closes admission, cancels decode,
    /// and always waits for native work before freeing it. Loading is not safely interruptible.
    /// A timeout is a grace period, not permission to free a model that is still in use.
    @discardableResult
    func release(expectedLease: UUID? = nil, permanently: Bool = false,
                 timeoutSeconds: TimeInterval? = nil, cancelSequence: (Int32) -> Void,
                 _ body: () -> Void) -> Bool {
        condition.lock()
        guard expectedLease == nil || lease == expectedLease else { condition.unlock(); return false }
        releasesPending += 1
        if permanently { terminated = true; lease = UUID() }
        if let target { cancelSequence(target.sequenceID) }
        condition.broadcast()
        if let timeoutSeconds {
            let deadline = Date(timeIntervalSinceNow: max(0, timeoutSeconds))
            while busy && condition.wait(until: deadline) { }
        }
        while busy { condition.wait() }
        // A new claim during the drain owns the model now. An older idle timer must not unload it.
        guard expectedLease == nil || lease == expectedLease else {
            releasesPending -= 1
            condition.broadcast()
            condition.unlock()
            return false
        }
        busy = true
        target = nil
        condition.unlock()
        body()
        condition.lock()
        busy = false
        releasesPending -= 1
        condition.broadcast()
        condition.unlock()
        return true
    }

    private func admits(expectedLease: UUID?, checkCancellation: Bool) -> Bool {
        releasesPending == 0 && eligible(expectedLease: expectedLease, checkCancellation: checkCancellation)
    }

    private func eligible(expectedLease: UUID?, checkCancellation: Bool) -> Bool {
        !terminated && (expectedLease == nil || lease == expectedLease)
            && (!checkCancellation || !Task.isCancelled)
    }

    private func finishOperation() {
        condition.lock()
        target = nil
        busy = false
        condition.broadcast()
        condition.unlock()
    }
}
