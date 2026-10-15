import Combine
import Foundation

/// One task owns one durable budget map. Completion and each learning profile retain their own
/// instance for the app lifetime; views borrow it. Keys describe model destinations, never secrets.
@MainActor
final class ModelContextSettings: ObservableObject {
    @Published private(set) var overrides: [String: Int]
    private let defaults: UserDefaults
    private let key: String

    init(role: String, defaults: UserDefaults) {
        self.defaults = defaults
        key = "modelContext.\(role).windows"
        overrides =
            defaults.dictionary(forKey: key)?.reduce(into: [:]) { result, pair in
                if let number = pair.value as? Int, (1_024...131_072).contains(number) { result[pair.key] = number }
            } ?? [:]
    }

    func tokens(for identity: String) -> Int? { overrides[identity] }

    func setTokens(_ tokens: Int?, for identity: String, maximum: Int) {
        var next = overrides
        if let tokens { next[identity] = min(max(tokens, 1_024), maximum) } else { next.removeValue(forKey: identity) }
        guard next != overrides else { return }
        overrides = next
        defaults.set(next, forKey: key)
    }

    func reset() {
        overrides = [:]
        defaults.removeObject(forKey: key)
    }
}
