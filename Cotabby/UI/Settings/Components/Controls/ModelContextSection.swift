import SwiftUI

/// Shared presentation for task-owned budgets. The parent supplies the active model's binding;
/// this view owns no settings, runtime or network client. Native controls match the existing forms.
struct ModelContextSection: View {
    @Binding var tokens: Int
    let maximum: Int
    let isEndpoint: Bool
    var isSystemManaged = false
    let reset: () -> Void

    /// The formatter commits an integer at the end of editing. Applying the model's clamp on
    /// each digit would make a larger value impossible to type ("1" would immediately become
    /// "1024"). The stepper still writes immediately through the same bounded binding.
    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    var body: some View {
        Section(String(localized: "Context budget", table: "Learning", comment: "Model-specific token budget section.")) {
            LabeledContent {
                HStack {
                    TextField("", value: $tokens, formatter: Self.tokenFormatter)
                        .textFieldStyle(.roundedBorder).frame(width: 88)
                        .accessibilityLabel(
                            String(localized: "Total context tokens", table: "Learning", comment: "Editable total token budget."))
                    Stepper("", value: $tokens, in: 1_024...maximum, step: 1_024).labelsHidden()
                }
            } label: {
                SettingsRowLabel(
                    title: String(localized: "Total context tokens", table: "Learning"),
                    description: String(
                        localized: "Counts instructions, source, references and output reserve. Saved per model.",
                        table: "Learning", comment: "Explains the total model budget and its persistence."), systemImage: "text.alignleft")
            }
            Text(
                isSystemManaged
                    ? String(
                        localized: "Apple Intelligence manages its own capacity. This setting bounds the context Lingrove supplies.",
                        table: "Learning", comment: "Apple model input budgeting does not resize the system model.")
                    : isEndpoint
                        ? String(
                            localized:
                                "Bounds the input Lingrove sends, not server capacity. Token counts are estimates with a safety margin.",
                            table: "Learning", comment: "Endpoint budget and approximate token accounting disclosure.")
                        : String(
                            localized: "Applies when the local model next runs. Larger contexts use more memory; model limits still apply.",
                            table: "Learning", comment: "Explains local runtime capacity and memory use.")
            )
            .font(.caption).foregroundStyle(.secondary)
            Button(
                String(localized: "Restore default budget", table: "Learning", comment: "Clears this model's custom token budget."),
                action: reset)
        }
    }
}
