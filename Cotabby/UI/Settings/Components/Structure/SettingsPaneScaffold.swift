import SwiftUI

/// File overview:
/// Shared chrome for every settings detail pane. Pulls the form styling, scrolling, and
/// optional top-of-pane callout into one place so individual panes stay focused on their rows
/// rather than repeating layout boilerplate.
///
/// Why a callout slot:
/// The legacy settings window puts a single attention banner at the top of the form. The redesign
/// surfaces attention per pane: when a pane is in a degraded state (missing permission, runtime
/// unavailable) we render an inline callout above the form so the actionable surface lives next to
/// the controls that fix it.
///
/// Search arrival:
/// When search reveals a specific setting, the scaffold scrolls to the row carrying the matching
/// `.settingsItem(_:)` anchor. The row's own modifier renders the pulse; the scaffold only owns
/// the scroll, so panes stay declarative.
struct SettingsPaneScaffold<Content: View>: View {
    let callout: SettingsPaneCallout?
    @ViewBuilder let content: () -> Content

    @Environment(\.settingsHighlightedItem) private var highlightedItem

    init(
        callout: SettingsPaneCallout? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.callout = callout
        self.content = content
    }

    var body: some View {
        ScrollViewReader { proxy in
            // Grouped Form already supplies its native scroll container. An outer ScrollView
            // gives the reader a second scroll owner, so revealing a Form row can leave the
            // visible viewport at the top. One owner lets the proxy reach the row's actual scroller.
            Form {
                if let callout {
                    Section {
                        SettingsCalloutView(callout: callout)
                    }
                }
                content()
            }
            .formStyle(.grouped)
            // Header-less first sections need the same clearance below the title bar. The shared
            // callout is a section of this document, so it continues scrolling with the controls.
            .padding(.top, 12)
            .task(id: highlightedItem) {
                // The first reveal can precede row layout after `.id(selection)` rebuilds the
                // pane. SwiftUI cancels this task when a new target arrives or the pane disappears.
                // Reveal once, rather than issuing a delayed repair that can pull the viewport
                // back after the user starts scrolling. Same-pane searches use the same path.
                guard let item = highlightedItem else { return }
                do {
                    try await Task.sleep(for: .milliseconds(80))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(item, anchor: .center)
                }
            }
        }
    }
}

struct SettingsPaneCallout: Equatable {
    enum Tone {
        case warning
        case info
    }

    let tone: Tone
    let message: String
}

/// Renders a single callout (warning/info) with a tinted background and matching icon. Used both by
/// the scaffold's top-of-pane slot and inline inside a pane section when an attention message belongs
/// next to a specific control (e.g. the Extended Context cost warning in the Advanced pane).
struct SettingsCalloutView: View {
    let callout: SettingsPaneCallout

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .imageScale(.medium)

            Text(callout.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch callout.tone {
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch callout.tone {
        case .warning: return .orange
        case .info: return .accentColor
        }
    }
}
