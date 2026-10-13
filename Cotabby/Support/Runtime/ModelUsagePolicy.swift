import Foundation

/// Shared GGUF files can be referenced by three runtimes and their future power choices. The
/// composition root projects those values here; the download service rechecks this set at deletion
/// time as well as when rendering its button, so a stale confirmation cannot delete a new choice.
enum ModelUsagePolicy {
    static func protectedFilenames(completion: String?, completionPower: [PowerProfile], learning: [Set<String>]) -> Set<String> {
        var names = Set(learning.flatMap { $0 })
        if let completion, !completion.isEmpty { names.insert(completion) }
        for profile in completionPower {
            if case .llama(let filename) = profile, !filename.isEmpty { names.insert(filename) }
        }
        return names
    }
}
