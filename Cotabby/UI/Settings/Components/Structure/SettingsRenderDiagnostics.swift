import AppKit
import Logging
import SwiftUI

/// Optional, window-scoped measurements for settings performance investigations. The navigation
/// model supplies the start and the detail's AppKit layout supplies the end. This measures handled
/// selection-to-first-layout latency, not mouse delivery or the time pixels reach the display.
/// It is deliberately not ObservableObject: recording a render must never trigger another render.
/// Tests can supply a private sink; normal launches allocate no probe and retain no measurements.
@MainActor
final class SettingsRenderDiagnostics {
    struct Event {
        let phase: String
        let scope: String
        let category: SettingsCategory
        var milliseconds: Double?
        var generation: UInt64?
    }

    static let process: SettingsRenderDiagnostics? = {
        guard ProcessInfo.processInfo.arguments.contains("-cotabby-settings-performance") else { return nil }
        return SettingsRenderDiagnostics { event in
            var metadata: Logger.Metadata = [
                "settings_event": .string(event.phase), "scope": .string(event.scope),
                "pane": .string(event.category.rawValue)
            ]
            if let milliseconds = event.milliseconds {
                metadata["duration_ms"] = .string(String(format: "%.3f", milliseconds))
            }
            if let generation = event.generation { metadata["transition_id"] = .stringConvertible(generation) }
            CotabbyLogger.app.debug("Settings render measurement", metadata: metadata)
        }
    }()

    private let sink: (Event) -> Void
    private let uptime: () -> UInt64
    private var generation: UInt64 = 0
    /// One short-lived navigation identity and its clock anchor, retained until layout or supersession.
    private struct Transition {
        let category: SettingsCategory
        let start: UInt64
        let generation: UInt64
    }
    private var pending: Transition?

    init(uptime: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }, sink: @escaping (Event) -> Void) {
        self.uptime = uptime
        self.sink = sink
    }

    @discardableResult
    func begin(_ category: SettingsCategory) -> UInt64 {
        generation &+= 1
        pending = Transition(category: category, start: uptime(), generation: generation)
        sink(Event(phase: "selection", scope: "detail", category: category, generation: generation))
        return generation
    }

    func token(for category: SettingsCategory) -> UInt64? {
        pending?.category == category ? pending?.generation : nil
    }

    func body(_ scope: String, category: SettingsCategory) {
        sink(Event(phase: "body", scope: scope, category: category))
    }

    func firstLayout(_ category: SettingsCategory, generation: UInt64) {
        // A -> B -> A can leave the first A's AppKit view awaiting layout. Category alone would
        // let that obsolete view finish the second A's measurement with the wrong start time.
        guard let pending, pending.category == category, pending.generation == generation else { return }
        self.pending = nil
        let elapsed = Double(uptime() &- pending.start) / 1_000_000
        sink(Event(phase: "first-layout", scope: "detail", category: category,
                   milliseconds: elapsed, generation: generation))
    }
}

/// An invisible background in the actual detail subtree, mounted only for explicit profiling.
/// Waiting for AppKit layout avoids mistaking SwiftUI onAppear for a laid-out destination.
struct SettingsLayoutProbe: NSViewRepresentable {
    let category: SettingsCategory
    let generation: UInt64
    let diagnostics: SettingsRenderDiagnostics

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        guard view.generation != generation else { return }
        view.generation = generation
        view.didLayout = { diagnostics.firstLayout(category, generation: generation) }
        // One initial request per probe; unrelated body evaluations must not manufacture extra
        // layout passes during the very work being measured.
        view.needsLayout = true
    }

    final class Probe: NSView {
        var didLayout: (() -> Void)?
        var generation: UInt64?

        override func layout() {
            super.layout()
            guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
            didLayout?()
        }
    }
}
