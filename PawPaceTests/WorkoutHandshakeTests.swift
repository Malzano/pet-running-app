import XCTest
@testable import PawPace

final class WorkoutHandshakeTests: XCTestCase {
    func testOnlyExplicitPreSessionIdleChallengeCanReceivePhoneConfiguration() {
        let now = Date(timeIntervalSince1970: 10_000)
        var challenge = makeChallenge(startedAt: now, updatedAt: now)
        challenge.isAwaitingPhoneConfiguration = true

        XCTAssertTrue(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: challenge, localStart: now, now: now))
        challenge.isAwaitingPhoneConfiguration = false
        XCTAssertFalse(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: challenge, localStart: now, now: now))
        XCTAssertFalse(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: .idle, localStart: now, now: now))
    }

    func testConfigurationChallengeCannotBeAdoptedAsActiveWorkoutTelemetry() {
        let now = Date(timeIntervalSince1970: 10_000)
        var challenge = makeChallenge(startedAt: now, updatedAt: now)
        challenge.isAwaitingPhoneConfiguration = true

        XCTAssertFalse(PawPaceSyncPolicy.shouldAcceptRun(challenge, currentWorkoutID: nil, latestUpdate: nil, allowWorkoutAdoption: true))
        XCTAssertFalse(PawPaceSyncPolicy.canStartConnectivityFallback(from: challenge, now: now))
        XCTAssertFalse(PawPaceSyncPolicy.canAdoptPendingPhoneLaunch(from: challenge, localStart: now))
    }

    func testConfigurationHandshakeStillRequiresAWatchNonceAndMatchingLaunchTime() {
        let start = Date(timeIntervalSince1970: 10_000)
        var challenge = makeChallenge(startedAt: start, updatedAt: start)
        challenge.isAwaitingPhoneConfiguration = true

        challenge.workoutID = nil
        XCTAssertFalse(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: challenge, localStart: start, now: start))
        challenge.workoutID = UUID()
        challenge.startedAt = nil
        XCTAssertFalse(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: challenge, localStart: start, now: start))
        challenge.startedAt = start.addingTimeInterval(-61)
        XCTAssertFalse(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: challenge, localStart: start, now: start))
        challenge.startedAt = start
        challenge.updatedAt = start.addingTimeInterval(-1)
        XCTAssertFalse(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: challenge, localStart: start, now: start))
        challenge.updatedAt = start.addingTimeInterval(6)
        XCTAssertFalse(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: challenge, localStart: start, now: start))
    }

    func testDelayedAuthorizationCanStillAnswerTheExactPendingLaunchChallenge() {
        let start = Date(timeIntervalSince1970: 10_000)
        let now = start.addingTimeInterval(180)
        var challenge = makeChallenge(startedAt: start, updatedAt: now)
        challenge.isAwaitingPhoneConfiguration = true
        XCTAssertTrue(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: challenge, localStart: start, now: now))
    }

    func testLongSetupCannotHatchEggAndDoesNotBreakWorkoutIdentity() {
        let launchedAt = Date(timeIntervalSince1970: 10_000)
        let activeStartedAt = launchedAt.addingTimeInterval(35 * 60)
        let endedAt = activeStartedAt.addingTimeInterval(5 * 60)
        var state = makeChallenge(startedAt: launchedAt, updatedAt: activeStartedAt)
        let workoutID = state.workoutID
        state.activitySegments = [WorkoutActivitySegment(
            configuration: state.workoutConfiguration.configuration(forMultisportLeg: 0),
            startedAt: launchedAt,
            endedAt: nil
        )]
        state.excludeSetupTime(until: activeStartedAt)

        // A phone fallback built from wall-clock dates must save only the five
        // active minutes, even after thirty-five minutes in first-run setup.
        let activeSeconds = WorkoutTiming.activeIntervals(
            startedAt: launchedAt, endedAt: endedAt, pauseIntervals: state.pauseIntervals
        ).reduce(0) { $0 + $1.duration }
        var lifecycle = PetLifecycle(seed: 42)
        lifecycle.creditWorkout(activity: .swimBikeRun, activeSeconds: activeSeconds, workoutID: workoutID, at: endedAt)

        XCTAssertEqual(activeSeconds, 300)
        XCTAssertEqual(lifecycle.stage, .egg)
        XCTAssertEqual(lifecycle.creditedSeconds, 300)
        XCTAssertEqual(state.startedAt, launchedAt)
        XCTAssertEqual(state.workoutID, workoutID)
        XCTAssertEqual(state.activitySegments.first?.startedAt, activeStartedAt)
        state.phase = .running
        XCTAssertTrue(PawPaceSyncPolicy.canAdoptPendingPhoneLaunch(from: state, localStart: launchedAt))
    }

    func testRecoveryKeepsSetupExcludedAlongsideRealPauseAndResumeIntervals() throws {
        let launchedAt = Date(timeIntervalSince1970: 10_000)
        let activeStartedAt = launchedAt.addingTimeInterval(180)
        let pauseAt = activeStartedAt.addingTimeInterval(300)
        let resumedAt = pauseAt.addingTimeInterval(600)
        let endedAt = resumedAt.addingTimeInterval(300)
        let workoutID = UUID()
        var state = PawPaceSyncPolicy.recoveredRunState(
            workoutID: workoutID,
            persistedStart: launchedAt,
            sessionStart: activeStartedAt,
            elapsedSeconds: 600,
            updatedAt: endedAt
        )
        state.pauseIntervals = [DateInterval(start: pauseAt, end: resumedAt)]
        state.excludeSetupTime(until: activeStartedAt)
        state = try JSONDecoder().decode(PawPaceRunState.self, from: JSONEncoder().encode(state))
        state.excludeSetupTime(until: activeStartedAt)

        let activeSeconds = WorkoutTiming.activeIntervals(
            startedAt: launchedAt, endedAt: endedAt, pauseIntervals: state.pauseIntervals
        ).reduce(0) { $0 + $1.duration }
        XCTAssertEqual(activeSeconds, 600)
        XCTAssertEqual(state.elapsedSeconds, 600, "The HealthKit builder's active time is preserved")
        XCTAssertEqual(state.pauseIntervals.count, 2, "Repeated restoration must not duplicate setup time")
        XCTAssertEqual(state.startedAt, launchedAt)
        XCTAssertEqual(state.workoutID, workoutID)
    }

    func testConfigurationFlagNeverTurnsTerminalStatesIntoLaunchChallenges() {
        let now = Date(timeIntervalSince1970: 10_000)
        for phase in [PawPaceRunPhase.finished, .failed] {
            var challenge = makeChallenge(startedAt: now, updatedAt: now)
            challenge.phase = phase
            challenge.isAwaitingPhoneConfiguration = true
            XCTAssertFalse(PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: challenge, localStart: now, now: now))
        }
    }

    private func makeChallenge(startedAt: Date, updatedAt: Date) -> PawPaceRunState {
        PawPaceRunState(
            workoutID: UUID(), phase: .idle, distanceKilometers: 0,
            elapsedSeconds: 0, paceSecondsPerKilometer: 0, heartRate: 0,
            experienceEarned: 0, encouragement: "Waiting for workout settings",
            startedAt: startedAt, updatedAt: updatedAt,
            workoutConfiguration: WorkoutConfiguration(activity: .swimBikeRun)
        )
    }
}
