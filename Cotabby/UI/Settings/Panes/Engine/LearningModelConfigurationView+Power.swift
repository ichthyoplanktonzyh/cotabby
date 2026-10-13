import SwiftUI

/// Matches completion's Power section but binds only this learning role's battery/AC choices.
/// Endpoint profiles keep this role's server/key; local choices carry their own instruction format.
extension LearningModelConfigurationView {
    var powerSection: some View {
        Section("Power") {
            PauseInLowPowerModeRow(settings: suggestionSettings)
            Toggle(isOn: Binding(get: { profile.powerSwitchingEnabled }, set: profile.setPowerSwitchingEnabled)) {
                SettingsRowLabel(title: "Switch Based on Power Source",
                    description: "Use a different engine or model on battery vs. while plugged in for this task.",
                    systemImage: "battery.100.bolt")
            }
            if profile.powerSwitchingEnabled {
                powerPicker("On Battery", image: "battery.25", selection: $profile.batteryProfile)
                powerPicker("Plugged In", image: "powerplug", selection: $profile.pluggedInProfile)
                Text("Endpoint 使用此任务 Connection 中的地址与密钥；模型选择不会改变补全或另一个学习任务。")
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
                Text(canonical.localModel.isEmpty && canonical.endpointModel.isEmpty ? "请选择模型" : "Configured · \(powerName(canonical))")
                    .tag(canonical)
            }
            ForEach(options, id: \.self) { choice in Text(powerName(choice)).tag(choice) }
        } label: {
            SettingsRowLabel(title: title, description: "Engine and model to use while on this power source.", systemImage: image)
        }
        .pickerStyle(.menu)
        if selection.wrappedValue.backend == .endpoint {
            TextField("Endpoint model identifier", text: selection.endpointModel)
                .textFieldStyle(.roundedBorder).accessibilityLabel("\(title) Endpoint model")
        } else if !selection.wrappedValue.localModel.isEmpty {
            Picker("\(title) · 指令模板", selection: selection.template) {
                ForEach(LearningChatTemplate.allCases) { Text($0.label).tag($0) }
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
        value.backend == .local ? value.localModel :
            "Endpoint · \(value.endpointModel.isEmpty ? "Enter model identifier" : value.endpointModel)"
    }
}
