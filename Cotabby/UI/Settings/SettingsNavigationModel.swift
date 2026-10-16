import Combine
import SwiftUI

/// The fixed Engine & Model tabs select which task's settings are visible. This is window
/// navigation state, independent of the engine/model values that control actual generation.
enum SettingsEngineTask: String, CaseIterable, Identifiable {
    case completion, translation, analysis
    var id: String { rawValue }
    var label: String {
        switch self {
        case .completion: String(localized: "Autocomplete")
        case .translation: String(localized: "Translation", table: "Learning")
        case .analysis: String(localized: "Chunk alignment", table: "Learning")
        }
    }
    init(role: LearningModelRole) { self = role == .translation ? .translation : .analysis }
}

/// File overview:
/// Navigation state for the Settings window: which pane is selected, which individual setting
/// (if any) search wants revealed, and a pending request to focus the Home search field. Owned by
/// `SettingsContainerView` and shared with the sidebar and Home so a search hit anywhere can land
/// on the exact row: select the pane, scroll to the row, and pulse it briefly.
///
/// The highlight is deliberately transient. It exists to answer "where did search drop me?",
/// not to become persistent selection state, so `reveal` schedules its own clear and any manual
/// pane switch cancels it immediately.
@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var shortcutAppBundleIdentifier: String?

    func openShortcuts(for bundleIdentifier: String? = nil) {
        shortcutAppBundleIdentifier = bundleIdentifier
        open(.shortcuts)
    }
    /// Plain reference, assigned by the window, so tracing cannot invalidate SwiftUI itself.
    var renderDiagnostics: SettingsRenderDiagnostics?
    @Published var selection: SettingsCategory = .home {
        didSet {
            if selection != oldValue { renderDiagnostics?.begin(selection) }
        }
    }
    @Published var engineTask: SettingsEngineTask = .completion
    /// The setting search navigated to, while its arrival pulse is active. Distributed to rows
    /// through the `settingsHighlightedItem` environment value.
    @Published private(set) var highlightedItem: SettingsItem?
    /// True while Home owes the hero search field focus (set by the window-level Cmd-F shortcut).
    /// Home consumes and clears it, so a later visit to Home does not steal focus again.
    @Published private(set) var pendingSearchFocus = false

    private var highlightClearTask: Task<Void, Never>?

    /// How long the arrival pulse stays before fading. Long enough to catch the eye after the
    /// pane switch and scroll settle, short enough to never read as a stuck selection.
    private static let highlightDuration: Duration = .seconds(2.4)

    /// Plain pane navigation (sidebar click, Home quick link). Cancels any in-flight highlight so
    /// a stale pulse cannot replay when the user later returns to that pane.
    func open(_ category: SettingsCategory) {
        cancelHighlight()
        selectCategory(category)
    }

    /// Writing's model links choose both the category and the task before SwiftUI renders the
    /// destination. Keeping this here lets sidebar/search and cross-pane links share one owner.
    func openLearningModel(_ role: LearningModelRole) {
        openEngineTask(SettingsEngineTask(role: role))
    }

    /// Task-specific links (including Home's completion engine card) land on the matching page
    /// even if the user last inspected a different task. Plain sidebar navigation keeps the tab.
    func openEngineTask(_ task: SettingsEngineTask) {
        engineTask = task
        open(.engineAndModel)
    }

    /// Search navigation: selects the item's pane and pulses the row. The pane's scaffold watches
    /// `highlightedItem` to perform the scroll.
    func reveal(_ item: SettingsItem) {
        // Existing engine search anchors belong to the original completion page. A prior visit
        // to translation must not leave those search hits scrolling an unrelated learning form.
        if item.category == .engineAndModel { engineTask = .completion }
        selectCategory(item.category)
        highlightedItem = item

        highlightClearTask?.cancel()
        highlightClearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.highlightDuration)
            guard !Task.isCancelled else { return }
            self?.highlightedItem = nil
        }
    }

    /// Cmd-F: bring the user to the search surface. Switching to Home first means the shortcut
    /// works from any pane.
    func requestSearchFocus() {
        if selection != .home {
            open(.home)
        }
        pendingSearchFocus = true
    }

    func consumeSearchFocusRequest() {
        pendingSearchFocus = false
    }

    private func cancelHighlight() {
        highlightClearTask?.cancel()
        highlightClearTask = nil
        highlightedItem = nil
    }

    /// Re-selecting a category can still clear a search pulse or retarget its app/task, but it
    /// should not publish a second, identical category mutation and rebuild the detail needlessly.
    private func selectCategory(_ category: SettingsCategory) {
        guard selection != category else { return }
        selection = category
    }
}

// MARK: - Highlight environment

/// The item whose arrival pulse is active, distributed as a plain environment value (rather than
/// the model object) so rows re-render only when the value actually changes.
private struct SettingsHighlightedItemKey: EnvironmentKey {
    static let defaultValue: SettingsItem? = nil
}

extension EnvironmentValues {
    var settingsHighlightedItem: SettingsItem? {
        get { self[SettingsHighlightedItemKey.self] }
        set { self[SettingsHighlightedItemKey.self] = newValue }
    }
}

// MARK: - Row anchor

extension View {
    /// Marks a settings row as the home of `item` so search can scroll to it (`.id`) and pulse it
    /// on arrival. Apply to the outermost row view inside a Form section (the `Toggle`, `Picker`,
    /// or `LabeledContent` itself).
    func settingsItem(_ item: SettingsItem) -> some View {
        modifier(SettingsItemAnchorModifier(item: item))
    }
}

private struct SettingsItemAnchorModifier: ViewModifier {
    let item: SettingsItem
    @Environment(\.settingsHighlightedItem) private var highlightedItem

    func body(content: Content) -> some View {
        let isHighlighted = highlightedItem == item
        content
            .id(item)
            // The wash draws behind the row content rather than via `listRowBackground`, which
            // macOS grouped forms ignore. An always-present background whose opacity animates to
            // zero keeps the idle row untouched (opacity 0 renders nothing) while letting the
            // pulse fade smoothly instead of vanishing when the highlight clears. The negative
            // padding spreads the wash a little past the content so it reads as a row highlight,
            // not a text box; backgrounds never affect layout, so rows cannot shift.
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(isHighlighted ? 0.16 : 0))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -5)
                    .animation(.easeInOut(duration: 0.6), value: isHighlighted)
            )
    }
}
