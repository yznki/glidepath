import XCTest
@testable import Glidepath

final class WindowRouterTests: XCTestCase {
    /// A failed first sweep reopens onboarding when the window opens without a section (the popover's setup, launch).
    func testFailedSweepOpensOnboardingWithoutASection() {
        XCTAssertTrue(WindowRouter.opensOnboarding(configured: true, failedSweep: true, forSection: false))
    }

    /// A section opened from elsewhere, such as Reviews, is not sent to onboarding by a failed sweep.
    func testFailedSweepDoesNotOpenOnboardingForASection() {
        XCTAssertFalse(WindowRouter.opensOnboarding(configured: true, failedSweep: true, forSection: true))
    }

    func testNoConfigOpensOnboardingForEveryPath() {
        XCTAssertTrue(WindowRouter.opensOnboarding(configured: false, failedSweep: false, forSection: true))
        XCTAssertTrue(WindowRouter.opensOnboarding(configured: false, failedSweep: false, forSection: false))
    }

    func testConfigWithoutAFailureOpensNoOnboarding() {
        XCTAssertFalse(WindowRouter.opensOnboarding(configured: true, failedSweep: false, forSection: false))
    }
}
