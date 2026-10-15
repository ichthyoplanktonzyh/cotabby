import Testing
@testable import Cotabby

/// Shared ownership must remain exclusive across sections, including late cleanup from a row
/// SwiftUI just removed. These checks need no event monitors or writes to real shortcut settings.
@MainActor
struct ShortcutRecordingStateTests {
    @Test
    func startingAnotherSectionRetiresTheOldRecorderWithoutLettingOldCleanupStopTheNewOne() {
        let state = ShortcutRecordingState()
        let global = state.binding(for: "global"), translation = state.binding(for: "translation")
        let app = state.binding(for: "app")
        global.wrappedValue = true
        #expect(global.wrappedValue && !translation.wrappedValue && !app.wrappedValue)
        translation.wrappedValue = true
        #expect(!global.wrappedValue && translation.wrappedValue && !app.wrappedValue)
        global.wrappedValue = false
        #expect(translation.wrappedValue)
        app.wrappedValue = true
        #expect(!global.wrappedValue && !translation.wrappedValue && app.wrappedValue)
        translation.wrappedValue = false
        #expect(app.wrappedValue)
        state.stop()
        #expect(!global.wrappedValue && !translation.wrappedValue && !app.wrappedValue)
    }
}
