import SwiftUI

/// All task pages edit the same device-wide pause policy, already consumed by their availability
/// gates. Per-power-source model choices are separate, role-owned settings.
struct PauseInLowPowerModeRow: View {
    @ObservedObject var settings: SuggestionSettingsModel
    var body: some View {
        Toggle(isOn: Binding(get: { settings.isLowPowerModeAutoDisableEnabled },
            set: { settings.setLowPowerModeAutoDisableEnabled($0) })) {
            SettingsRowLabel(
                title: String(localized: "Pause in Low Power Mode"),
                description: String(
                    localized: "Pause completion and language learning while Low Power Mode is on to reduce battery use.",
                    table: "Learning"
                ),
                systemImage: "bolt.slash.circle"
            )
        }
        .settingsItem(.lowPowerModeAutoDisable)
    }
}
