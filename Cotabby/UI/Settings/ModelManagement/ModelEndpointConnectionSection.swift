import SwiftUI

/// The existing completion connection layout, parameterized by one task's bindings and owner.
/// Discovery state is separate from native/generation status; callbacks own credential persistence.
struct ModelEndpointConnectionSection: View {
    @Binding var baseURL: String
    @Binding var keyDraft: String
    @ObservedObject var connection: OpenAICompatibleConnectionModel
    var credentialError: String?
    var privacyWarning: String?
    var transmissionNote: String? = nil
    let connect: () -> Void
    let reset: () -> Void
    let clearKey: () -> Void

    var body: some View {
        Section(String(localized: "Connection")) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRowLabel(
                    title: String(localized: "Server URL"),
                    description: String(localized: """
                    The OpenAI-compatible server address. Lingrove adds /v1 when the address has no path; Ollama uses \
                    http://127.0.0.1:11434 by default.
                    """, table: "Learning"),
                    systemImage: "network"
                )
                HStack(spacing: 8) {
                    TextField("", text: $baseURL, prompt: Text(OpenAICompatibleEndpointConfiguration.defaultBaseURLString))
                        .labelsHidden().textFieldStyle(.roundedBorder).onSubmit(connect)
                    Button(connectTitle, action: connect)
                        .buttonStyle(.borderedProminent).disabled(connection.state == .connecting)
                }
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Group {
                            if connection.state == .connecting { ProgressView().controlSize(.small) }
                            else { Image(systemName: symbol).foregroundStyle(color) }
                        }.frame(width: 14)
                        Text(connection.state.summary).font(.caption.weight(.medium))
                            .foregroundStyle(color).lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Server status"))
                    .accessibilityValue(String(localized: "\(connection.state.summary), \(displayURL)"))
                    .settingsItem(.endpointStatus)
                    Spacer(minLength: 8)
                    Button(String(localized: "Use Ollama Default"), systemImage: "arrow.counterclockwise", action: reset)
                        .disabled(baseURL == OpenAICompatibleEndpointConfiguration.defaultBaseURLString)
                }
            }
            .settingsItem(.endpointBaseURL)
            LabeledContent {
                HStack(spacing: 8) {
                    SecureField("", text: $keyDraft, prompt: Text(String(localized: "Paste API key")))
                        .labelsHidden().textFieldStyle(.roundedBorder)
                        .frame(minWidth: 200, idealWidth: 260, maxWidth: 300)
                    if !keyDraft.isEmpty { Button(String(localized: "Clear"), action: clearKey) }
                }
            } label: {
                SettingsRowLabel(
                    title: String(localized: "API Key"),
                    description: String(
                        localized: "Optional bearer token stored in Keychain. Connect saves this task's key.",
                        table: "Learning"
                    ),
                    systemImage: "key"
                )
            }
            .settingsItem(.endpointAPIKey)
            if let transmissionNote { Text(transmissionNote).font(.caption).foregroundStyle(.secondary) }
            if let privacyWarning { SettingsCalloutView(callout: .init(tone: .warning, message: privacyWarning)) }
            if let credentialError { SettingsCalloutView(callout: .init(tone: .warning, message: credentialError)) }
        }
    }
    private var connectTitle: String {
        if case .ready = connection.state { return String(localized: "Refresh") }
        return String(localized: "Connect")
    }
    private var displayURL: String {
        (try? OpenAICompatibleEndpointConfiguration(baseURLString: baseURL, modelName: "", apiMode: .chatCompletions))?
            .baseURL.absoluteString ?? baseURL
    }
    private var symbol: String {
        switch connection.state {
        case .idle, .connecting: "circle.dashed"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
    private var color: Color {
        switch connection.state {
        case .idle, .connecting: .secondary
        case .ready: .green
        case .failed: .orange
        }
    }
}
