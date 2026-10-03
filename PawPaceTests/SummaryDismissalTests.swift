import XCTest
@testable import PawPace

final class SummaryDismissalTests: XCTestCase {
    func testOldSummaryNeverResetsActiveOrFinishingWorkout() {
        let identifier = UUID()
        for phase in [RunTracker.Phase.running, .paused] {
            XCTAssertFalse(SummaryDismissalPolicy.canResetTracker(
                phase: phase, isFinishing: false, currentWorkoutID: identifier,
                summaryID: identifier, matchesKnownIdentity: true
            ))
        }
        XCTAssertFalse(SummaryDismissalPolicy.canResetTracker(
            phase: .finished, isFinishing: true, currentWorkoutID: identifier,
            summaryID: identifier, matchesKnownIdentity: true
        ))
    }

    func testSummaryDismissalRequiresItsOwnCompletedIdentity() {
        let completed = UUID()
        let other = UUID()
        XCTAssertTrue(SummaryDismissalPolicy.canResetTracker(
            phase: .finished, isFinishing: false, currentWorkoutID: completed, summaryID: completed
        ))
        XCTAssertFalse(SummaryDismissalPolicy.canResetTracker(
            phase: .finished, isFinishing: false, currentWorkoutID: other, summaryID: completed
        ))
        XCTAssertTrue(SummaryDismissalPolicy.canResetTracker(
            phase: .finished, isFinishing: false, currentWorkoutID: other,
            summaryID: completed, matchesKnownIdentity: true
        ))
        XCTAssertTrue(SummaryDismissalPolicy.canResetTracker(
            phase: .idle, isFinishing: false, currentWorkoutID: nil, summaryID: completed
        ))
    }
}
