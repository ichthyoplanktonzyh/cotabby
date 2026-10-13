import Combine
import Foundation
import Logging

/// File overview:
/// In-memory + UserDefaults-backed ring buffer of the most recent LLM generation latencies.
/// Capped at `maximumEntries` so the persisted blob stays small and the Performance settings pane
/// renders a bounded list without virtualization. Records flow in from autocomplete and the learning telemetry boundary
/// only when the user has enabled performance tracking in Settings, so the default user pays no
/// storage or write cost.

@MainActor
final class PerformanceMetricsStore: ObservableObject {
    /// Hard cap on retained entries. The UI assumes the entire list is renderable without
    /// virtualization, so growing this past a few hundred would require revisiting the pane.
    static let maximumEntries = 100

    @Published private(set) var entries: [PerformanceMetricEntry]

    private let userDefaults: UserDefaults
    private static let entriesDefaultsKey = "cotabbyPerformanceMetricEntries"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        entries = Self.loadEntries(from: userDefaults)
    }

    nonisolated deinit {}

    /// Append a new metric and drop the oldest entries above the cap. Persists after every record
    /// because the cap keeps the JSON blob small (bounded by the fixed entry cap) and the write happens at most
    /// once per LLM request — far below any debouncing threshold.
    @discardableResult
    func record(modelName: String, latencyMs: Int, timestamp: Date = Date(),
                source: ModelRequestSource = .completion, outcome: ModelRequestOutcome = .completed,
                requestID: String? = nil, modelLoadMs: Int? = nil, firstOutputMs: Int? = nil,
                usableResultMs: Int? = nil, displayMs: Int? = nil) -> UUID {
        let entry = PerformanceMetricEntry(
            timestamp: timestamp,
            modelName: modelName,
            latencyMs: latencyMs, source: source, outcome: outcome, requestID: requestID,
            modelLoadMs: modelLoadMs, firstOutputMs: firstOutputMs, usableResultMs: usableResultMs, displayMs: displayMs
        )
        var updated = entries
        updated.append(entry)
        if updated.count > Self.maximumEntries {
            updated.removeFirst(updated.count - Self.maximumEntries)
        }
        entries = updated
        persist(updated)
        return entry.id
    }

    /// Display follows model completion on a later main-actor turn. Patch only that entry, once;
    /// clearing history or evicting it must never resurrect a row when a late panel callback arrives.
    func recordDisplay(entryID: UUID, elapsedMs: Int) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }), entries[index].displayMs == nil else { return }
        var updated = entries
        updated[index].displayMs = max(0, elapsedMs)
        entries = updated
        persist(updated)
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries = []
        userDefaults.removeObject(forKey: Self.entriesDefaultsKey)
    }

    private func persist(_ entries: [PerformanceMetricEntry]) {
        // Encoding `[PerformanceMetricEntry]` (UUID/Date/String/Int) shouldn't fail in practice, but
        // a silent return here would make "metrics vanish between sessions" undiagnosable. Log the
        // underlying error so the cause shows up in the standard JSONL stream when it does happen.
        do {
            let data = try JSONEncoder().encode(entries)
            userDefaults.set(data, forKey: Self.entriesDefaultsKey)
        } catch {
            CotabbyLogger.app.error(
                "Failed to persist performance metrics: \(error.localizedDescription)",
                metadata: ["entry_count": .stringConvertible(entries.count)]
            )
        }
    }

    private static func loadEntries(from userDefaults: UserDefaults) -> [PerformanceMetricEntry] {
        guard let data = userDefaults.data(forKey: Self.entriesDefaultsKey),
              let decoded = try? JSONDecoder().decode([PerformanceMetricEntry].self, from: data)
        else {
            return []
        }
        if decoded.count > maximumEntries {
            return Array(decoded.suffix(maximumEntries))
        }
        return decoded
    }
}
