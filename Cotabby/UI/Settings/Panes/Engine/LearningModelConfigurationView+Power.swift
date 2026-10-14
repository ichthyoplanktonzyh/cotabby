import SwiftUI

/// Matches completion's Power section but binds only this learning role's battery/AC choices.
/// Endpoint profiles keep this role's server/key; local choices carry their own instruction format.
extension LearningModelConfigurationView {
    var powerSection: some View {
        Section(String(localized: "Power", table: "Learning",
            comment: "Settings section for choosing this task's model based on power source.")) {
            PauseInLowPowerModeRow(settings: suggestionSettings)
            Toggle(isOn: Binding(get: { profile.powerSwitchingEnabled }, set: profile.setPowerSwitchingEnabled)) {
                SettingsRowLabel(title: String(localized: "Switch based on power source", table: "Learning",
                    comment: "Enables separate model choices for battery and plugged-in power."),
                    description: String(localized: "Use a different engine or model on battery and while plugged in for this task.",
                        table: "Learning", comment: """
                        Explains that this learning task can select different model profiles based on power source.
                        """),
                    systemImage: "battery.100.bolt")
            }
            if profile.powerSwitchingEnabled {
                powerPicker(String(localized: "On battery", table: "Learning",
                    comment: "Label for the model profile used while the Mac is on battery power."),
                    image: "battery.25", selection: $profile.batteryProfile)
                powerPicker(String(localized: "Plugged in", table: "Learning",
                    comment: "Label for the model profile used while the Mac is connected to power."),
                    image: "powerplug", selection: $profile.pluggedInProfile)
                Text(String(localized: """
                Endpoint profiles use this task's connection address and credential. Model choices do not change autocomplete or the \
                other learning task.
                """,
                    table: "Learning", comment: """
                    Clarifies that power-based endpoint choices use this task's own connection and do not affect other features.
                    """))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func powerPicker(_ title: String, image: String, selection: Binding<LearningPowerProfile>) -> some View {
        let canonical = selection.wrappedValue.backend == .local
            ? LearningPowerProfile.local(selection.wrappedValue.localModel)
            : LearningPowerProfile.endpoint(selection.wrappedValue.endpointModel)
        let options = powerChoices
        Picker(selection: Binding(get: { canonical }, set: { new in
            var value = new
            if new.backend == .local, new.localModel == selection.wrappedValue.localModel {
                value.template = selection.wrappedValue.template
            }
            selection.wrappedValue = value
        })) {
            if !options.contains(canonical) {
                Text(canonical.localModel.isEmpty && canonical.endpointModel.isEmpty
                    ? String(localized: "Choose a model", table: "Learning",
                        comment: "Picker entry shown when the power profile has no model selected.")
                    : String(localized: "Configured · \(powerName(canonical))", table: "Learning",
                        comment: "Picker entry showing the current engine and model for this power profile."))
                    .tag(canonical)
            }
            ForEach(options, id: \.self) { choice in Text(powerName(choice)).tag(choice) }
        } label: {
            SettingsRowLabel(title: title,
                description: String(localized: "Engine and model to use while on this power source.", table: "Learning",
                    comment: "Description of the engine and model selected for this power profile."),
                systemImage: image)
        }
        .pickerStyle(.menu)
        if selection.wrappedValue.backend == .endpoint {
            TextField(String(localized: "Endpoint model identifier", table: "Learning",
                comment: "Placeholder for a manually entered endpoint model identifier in a power profile."),
                text: selection.endpointModel)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(String(localized: "\(title) endpoint model", table: "Learning",
                    comment: "VoiceOver label for the endpoint model field under the selected power source."))
        } else if !selection.wrappedValue.localModel.isEmpty {
            Picker(String(localized: "\(title) · Instruction template", table: "Learning",
                comment: "Picker label for the local model's instruction template under this power source."),
                selection: selection.template) {
                ForEach(LearningChatTemplate.available(for: profile.role)) { Text($0.label).tag($0) }
            }.pickerStyle(.menu)
        }
    }

    private var powerChoices: [LearningPowerProfile] {
        let local = controller.availableModels.map { LearningPowerProfile.local($0.filename) }
        var names = Set(controller.endpointConnection.models.map(\.id))
        for name in [profile.endpointModel, profile.batteryProfile.endpointModel, profile.pluggedInProfile.endpointModel] where !name.isEmpty {
            names.insert(name)
        }
        // A server may not expose /models. Keep a manual Endpoint choice reachable even before
        // discovery, so enabling power switching cannot trap the user in local-only selections.
        return local + [.endpoint("")] + names.sorted().map { LearningPowerProfile.endpoint($0) }
    }
    private func powerName(_ value: LearningPowerProfile) -> String {
        switch value.backend {
        case .local:
            value.localModel
        case .endpoint:
            value.endpointModel.isEmpty
                ? String(localized: "Endpoint · enter model identifier", table: "Learning",
                    comment: "Value shown when the endpoint model identifier has not been entered for this power profile.")
                : String(localized: "Endpoint · \(value.endpointModel)", table: "Learning",
                    comment: "Endpoint model identifier shown for the selected power profile.")
        }
    }
}
