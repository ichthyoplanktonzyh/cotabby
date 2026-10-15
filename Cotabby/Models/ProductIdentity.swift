import Foundation

/// Lingrove's immutable, user-facing identity and project destinations.
///
/// Views, coordinators, and the update service read this metadata directly; no instance or owner
/// is needed because it holds no mutable state. Keeping names and links together prevents one
/// screen from sending users to a different project's feedback or documentation. Bundle IDs and
/// storage names remain build settings: localized display copy must never move a user's data.
nonisolated enum ProductIdentity {
    // This is a fixed, checked HTTPS literal; appending path components keeps every destination
    // under the same repository without separate strings drifting across presentation files.
    static let repositoryURL = URL(string: "https://github.com/ichthyoplanktonzyh/lingrove")!
    static let issuesURL = repositoryURL.appendingPathComponent("issues")
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    static let contributorGuideURL = repositoryURL.appendingPathComponent("blob/main/CONTRIBUTING.md")
    static let helpURL = repositoryURL.appendingPathComponent("blob/main/FAQ.md")

    /// Brand copy lives in the fork-owned table. Explicit bundles also let resource tests verify
    /// each compiled localization without changing the user's app or global language preference.
    static func localizedName(bundle: Bundle = .main, locale: Locale = .current) -> String {
        String(localized: "Lingrove", table: "Learning", bundle: bundle, locale: locale)
    }

    /// Keep the development suffix visible in identity-bearing headers. This is presentation only;
    /// macOS permission guidance still uses the actual installed bundle's name to match its row.
    static var appDisplayName: String {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == "Lingrove Dev" {
            return String(localized: "Lingrove Dev", table: "Learning")
        }
        return localizedName()
    }
}
