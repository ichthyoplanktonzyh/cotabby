import Foundation

/// Decides whether a cold launch should open Settings as Cotabby's user-facing entry point.
///
/// This pure policy lives in `Support/` so AppKit launch details stay in `AppDelegate`, while the
/// product rule remains deterministic and unit-testable. Direct launches show Settings, login-item
/// launches remain background-only, and the explicit development override always wins.
enum MenuBarRecoveryPolicy {
    static func shouldShowSettingsOnColdLaunch(
        wasLaunchedAtLogin: Bool,
        wasSettingsExplicitlyRequested: Bool
    ) -> Bool {
        wasSettingsExplicitlyRequested
            || !wasLaunchedAtLogin
    }
}
