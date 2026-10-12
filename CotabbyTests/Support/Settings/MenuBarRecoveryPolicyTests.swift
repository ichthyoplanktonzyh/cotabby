import XCTest
@testable import Cotabby

/// Locks the cold-launch behavior independently of AppKit so manual launches remain visible,
/// login-item launches stay quiet, and an explicit Settings request always wins.
@MainActor
final class MenuBarRecoveryPolicyTests: XCTestCase {
    /// Direct launches open Settings; login launches stay in the background unless explicitly asked.
    func test_shouldShowSettingsOnColdLaunch_truthTable() {
        let cases: [(atLogin: Bool, requested: Bool, expected: Bool)] = [
            (false, false, true),
            (true, false, false),
            (false, true, true),
            (true, true, true)
        ]
        for testCase in cases {
            XCTAssertEqual(
                MenuBarRecoveryPolicy.shouldShowSettingsOnColdLaunch(
                    wasLaunchedAtLogin: testCase.atLogin,
                    wasSettingsExplicitlyRequested: testCase.requested
                ),
                testCase.expected,
                "login=\(testCase.atLogin) requested=\(testCase.requested)"
            )
        }
    }
}
