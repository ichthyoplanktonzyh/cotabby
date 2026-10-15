import Combine
import SwiftUI

/// One Shortcuts pane owns this transient state and shares it with all of its recorder rows.
/// A single identity replaces per-section booleans, so starting another recorder removes the
/// previous KeyRecorderView and its local event monitor. Nothing is persisted or globally tapped.
@MainActor
final class ShortcutRecordingState: ObservableObject {
    /// Publishing the owner makes every row retire its old recorder in the same view update.
    @Published private(set) var active: String?

    func binding(for identity: String) -> Binding<Bool> {
        Binding(get: { self.active == identity }, set: { recording in
            if recording { self.active = identity } else if self.active == identity { self.active = nil }
        })
    }

    func stop() { active = nil }
}
