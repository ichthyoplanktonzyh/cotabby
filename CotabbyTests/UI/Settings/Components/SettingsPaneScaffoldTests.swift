import AppKit
import SwiftUI
import Testing
@testable import Cotabby

/// Exercises the real grouped Form and AppKit scroll viewport. Navigation-model assertions alone
/// cannot catch a search that selects the right pane while leaving its target below the fold.
@Suite(.serialized)
@MainActor
struct SettingsPaneScaffoldTests {
    @Test(arguments: [false, true], [false, true])
    func searchRevealsRowsInBothDirectionsWithOneScrollOwner(hasCallout: Bool, initialSearch: Bool) async throws {
        let host = NSHostingView(rootView: content(highlight: initialSearch ? .ghostTextSize : nil, hasCallout: hasCallout))
        let size = NSSize(width: 760, height: 480)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSPanel(contentRect: NSRect(origin: NSPoint(x: -3000, y: -3000), size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await settle(host)

        let scrollers = scrollViews(in: host)
        #expect(scrollers.count == 1, "The reader must address the Form's single visible scroll owner")
        let scroll = try #require(scrollers.first)
        let document = try #require(scroll.documentView)
        #expect(document.bounds.height > scroll.contentView.bounds.height * 2)
        if initialSearch {
            #expect(scroll.contentView.bounds.origin.y > 300, "A freshly mounted search destination must reveal its row")
        }

        host.rootView = content(highlight: .length, hasCallout: hasCallout)
        try await settle(host)
        let initial = scroll.contentView.bounds.origin.y

        host.rootView = content(highlight: .ghostTextSize, hasCallout: hasCallout)
        try await settle(host)
        let destination = scroll.contentView.bounds.origin.y
        #expect(destination > initial + 300, "Search must move the actual viewport to the distant target")

        // The same mounted pane must also respond to a later search for a row near its beginning.
        host.rootView = content(highlight: .length, hasCallout: hasCallout)
        try await settle(host)
        #expect(scroll.contentView.bounds.origin.y < destination - 300)
    }

    private func content(highlight: SettingsItem?, hasCallout: Bool) -> AnyView {
        AnyView(SettingsPaneScaffold(callout: hasCallout
            ? SettingsPaneCallout(tone: .warning, message: "Fixture warning uses the shared callout") : nil) {
            Section("Beginning") {
                Text("First searchable setting").settingsItem(.length)
            }
            Section("Other settings") {
                ForEach(0..<30) { index in
                    Text("Setting \(index)").frame(height: 36)
                }
            }
            Section("Destination") {
                Text("Last searchable setting").settingsItem(.ghostTextSize)
            }
        }.environment(\.settingsHighlightedItem, highlight))
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func settle(_ host: NSView) async throws {
        // Covers the delayed reveal and its animation; this is a behavior check, not a timer.
        for _ in 0..<50 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
