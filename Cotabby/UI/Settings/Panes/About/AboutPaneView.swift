import AppKit
import SwiftUI

/// File overview:
/// "About" detail pane of the redesigned Settings window. Consolidates what used to live across
/// three legacy sections (header, support CTA, uninstall) plus a new Acknowledgements modal that
/// lists the third-party packages Cotabby ships with.
struct AboutPaneView: View {
    let appUpdateManager: AppUpdateManager

    @State private var isShowingAcknowledgements = false

    var body: some View {
        SettingsPaneScaffold {
            Section { aboutHeader.settingsItem(.checkForUpdates) }
            Section("Contribute") { supportRow.settingsItem(.support) }
            Section("Resources") { resourceRows }
            Section("Uninstall") { uninstallText.settingsItem(.uninstall) }
        }
        .sheet(isPresented: $isShowingAcknowledgements) {
            AcknowledgementsView { isShowingAcknowledgements = false }
        }
    }

    @ViewBuilder
    private var aboutHeader: some View {
        HStack(spacing: 12) {
            Image("LingroveLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(ProductIdentity.appDisplayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Text(String(localized: "Autocomplete and language learning", table: "Learning"))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(appVersionText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                appUpdateManager.checkForUpdates()
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var supportRow: some View {
        // Stack the support copy and the call-to-action vertically so the button sits below the
        // paragraphs instead of competing with them on the right edge of the row. `LabeledContent`
        // placed the value column next to the label, which made the wall of text visually compete
        // with a small button — the natural reading order is paragraphs first, then action.
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    String(localized: "Get inline completions, translate sentences, and learn expressions.", table: "Learning")
                )

                Text(
                    String(localized: "Help improve Lingrove by reporting issues or sharing ideas.", table: "Learning")
                )
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Link(destination: ProductIdentity.issuesURL) {
                Label("Contribute", systemImage: "person.2")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }

    /// One row per resource (rather than one stacked row) so each link is a separate form row that
    /// search can scroll to and pulse individually.
    @ViewBuilder
    private var resourceRows: some View {
        Link(destination: ProductIdentity.repositoryURL) {
            Label("GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right")
        }
        .settingsItem(.githubRepository)
        Link(destination: ProductIdentity.contributorGuideURL) {
            Label("Contributor Guide", systemImage: "book")
        }
        .settingsItem(.wiki)
        Link(destination: ProductIdentity.helpURL) {
            Label("Help", systemImage: "questionmark.circle")
        }
        Button {
            isShowingAcknowledgements = true
        } label: {
            Label("Acknowledgements", systemImage: "doc.text")
        }
        .buttonStyle(.link)
        .settingsItem(.acknowledgements)
    }

    @ViewBuilder
    private var uninstallText: some View {
        let dataDirectory = BundledRuntimeLocator.userRuntimeDirectoryURL().deletingLastPathComponent().path
        Text(String(
            localized: "Remove Lingrove from Applications. To fully clean up model data, delete \(dataDirectory).",
            table: "Learning"
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// The app bundle is the canonical source for human-facing version text.
    private var appVersionText: String {
        let shortVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildNumber) {
        case (let shortVersion?, let buildNumber?) where shortVersion != buildNumber:
            return String(localized: "Version \(shortVersion) (\(buildNumber))")
        case (let shortVersion?, _):
            return String(localized: "Version \(shortVersion)")
        case (_, let buildNumber?):
            return String(localized: "Build \(buildNumber)")
        default:
            return String(localized: "Unknown version")
        }
    }
}
