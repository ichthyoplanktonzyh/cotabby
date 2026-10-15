import SwiftUI

/// Onboarding demonstrates the current accept gesture without owning a second shortcut editor.
/// The app-owned settings model supplies these read-only keycaps; every binding is edited in the
/// central Shortcuts pane, so onboarding and later settings cannot drift into different flows.
struct WelcomeKeybindStepView: View {
    @ObservedObject var suggestionSettings: SuggestionSettingsModel

    var body: some View {
        VStack(spacing: 24) {
            OnboardingKeycapHero(label: suggestionSettings.acceptanceKeyLabel)
                .onboardingReveal(0)

            VStack(spacing: 8) {
                Text("Learn your keys")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text("Accept suggestions without leaving the keyboard.\nYou can change these anytime in Settings.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .onboardingReveal(1)

            VStack(spacing: 10) {
                keybindRow(title: String(localized: "Accept word"), keyLabel: suggestionSettings.acceptanceKeyLabel)
                    .onboardingReveal(2)
                keybindRow(title: String(localized: "Accept entire suggestion"), keyLabel: suggestionSettings.fullAcceptanceDisplayLabel)
                    .onboardingReveal(3)
                keybindRow(title: String(localized: "Toggle Lingrove", table: "Learning"), keyLabel: suggestionSettings.globalToggleKeyLabel)
                    .onboardingReveal(4)
            }
            .frame(maxWidth: 480)
        }
    }

    private func keybindRow(title: String, keyLabel: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            KeycapView(label: keyLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .onboardingCard(cornerRadius: 12)
    }
}

/// `.task` loop; Reduce Motion holds the key at rest.
private struct OnboardingKeycapHero: View {
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        KeycapView(label: label, fontSize: 17, minWidth: 84)
            .scaleEffect(pressed ? 0.96 : 1.0)
            .offset(y: pressed ? 2 : 0)
            .shadow(
                color: CotabbyBrand.accent.opacity(pressed ? 0.1 : 0.25),
                radius: pressed ? 6 : 14,
                y: pressed ? 2 : 6
            )
            .task(id: reduceMotion) {
                guard !reduceMotion else {
                    pressed = false
                    return
                }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_300_000_000)
                    if Task.isCancelled { return }
                    withAnimation(.easeIn(duration: 0.1)) { pressed = true }
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    if Task.isCancelled { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { pressed = false }
                }
            }
            .accessibilityHidden(true)
    }
}
