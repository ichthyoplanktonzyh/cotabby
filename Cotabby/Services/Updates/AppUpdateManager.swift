import AppKit
import Logging
import Sparkle

/// File overview:
/// Owns Lingrove's Sparkle integration and keeps updater lifecycle out of SwiftUI views.
/// This is a classic service-layer boundary in the app's architecture: Sparkle is a side-effectful
/// framework that talks to the network, persists updater preferences, and may present system UI.
///
/// We keep it in `Services/` so the rest of the app only depends on a tiny, explicit surface:
/// `start()` for lifecycle wiring and `checkForUpdates()` for a future settings screen.
@MainActor
final class AppUpdateManager {
    /// The updater is created once and retained for the lifetime of the process, just like the
    /// runtime manager and the focus tracker. Sparkle expects its controller to stay alive.
    private let updaterController: SPUStandardUpdaterController

    private var isStarted = false

    /// Sparkle persists this setting in user defaults, which take precedence over the value in
    /// `CotabbyInfo.plist`. Reapplying the product policy repairs older installs that may have saved
    /// a shorter development interval while the plist still gives fresh installs the same default.
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private static let debugCheckForUpdatesOnLaunchArgument = "-Cotabby-check-for-updates-on-launch"
    private static let publicKeyPlaceholder = "REPLACE_WITH_GENERATED_SPARKLE_PUBLIC_ED_KEY"

    init() {
        // `startingUpdater: false` keeps lifecycle explicit. The app delegate decides when the
        // updater starts instead of Sparkle implicitly doing work during dependency construction.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Starts Sparkle exactly once after app launch.
    /// We validate the minimal required Info.plist settings first so a development build with the
    /// placeholder public key does not trigger Sparkle's "app is misconfigured" alert.
    func start() {
        guard !isStarted else {
            return
        }

        guard Self.isUpdaterEnabledForThisBuild else {
            // An explicit product switch protects both configurations while the independent feed
            // is being prepared. Clearing default check preferences alone is insufficient: Sparkle
            // can persist a user's earlier choice, whereas this guard prevents starting it at all.
            log("Sparkle disabled for this build; updates are installed from Lingrove releases.")
            return
        }

        guard hasUsableConfiguration else {
            log("Sparkle not started because updater configuration is incomplete.")
            return
        }

        // Configure the interval before starting so Sparkle's first scheduling decision uses the
        // daily cadence together with its persisted last-check date.
        let updater = updaterController.updater
        updater.updateCheckInterval = Self.automaticCheckInterval
        updaterController.startUpdater()
        isStarted = true
        log("Sparkle updater started.")

        // Catch up immediately when the app returns after the daily interval. Recent launches leave
        // the check to Sparkle's scheduler, so reopening Cotabby cannot bypass the daily cadence.
        let shouldCatchUp = updater.lastUpdateCheckDate
            .map { Date().timeIntervalSince($0) >= Self.automaticCheckInterval } ?? true
        if shouldCatchUp {
            updater.checkForUpdatesInBackground()
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(Self.debugCheckForUpdatesOnLaunchArgument) {
            log("Debug launch argument requested an immediate update check.")
            checkForUpdates()
        }
        #endif
    }

    /// Future UI surfaces, such as Settings, should call this method instead of touching Sparkle
    /// directly. That keeps the rest of the codebase decoupled from Sparkle APIs.
    func checkForUpdates() {
        guard isStarted else {
            // Until independent automatic updates are configured, the existing settings action
            // takes the user to this project's releases instead of becoming a silent no-op.
            NSWorkspace.shared.open(ProductIdentity.releasesURL)
            return
        }

        updaterController.checkForUpdates(nil)
    }

    /// Dev builds never update into production. A released Lingrove build also requires an
    /// explicit opt-in in its bundled configuration; missing metadata keeps updates disabled.
    private static var isUpdaterEnabledForThisBuild: Bool {
        #if COTABBY_DEV
        false
        #else
        Bundle.main.object(forInfoDictionaryKey: "LingroveUpdatesEnabled") as? Bool == true
        #endif
    }

    private var hasUsableConfiguration: Bool {
        guard let feedURLString = configuredString(forInfoDictionaryKey: "SUFeedURL"),
              URL(string: feedURLString) != nil
        else {
            log("Missing or invalid SUFeedURL.")
            return false
        }

        guard let publicKey = configuredString(forInfoDictionaryKey: "SUPublicEDKey"),
              publicKey != Self.publicKeyPlaceholder
        else {
            log("SUPublicEDKey is missing or still using the placeholder value.")
            return false
        }

        return true
    }

    private func configuredString(forInfoDictionaryKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func log(_ message: String) {
        CotabbyLogger.updates.info("\(message)")
    }
}
