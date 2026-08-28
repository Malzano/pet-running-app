import XCTest
@testable import PawPace

final class WatchSyncTests: XCTestCase {
    func testFirstPhonePetReplacesNewerStarterFallback() {
        var incoming = PetSnapshot.starter
        incoming.name = "Real Mochi"
        incoming.lastUpdated = Date(timeIntervalSince1970: 100)
        var fallback = PetSnapshot.starter
        fallback.lastUpdated = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(
            PawPaceSyncPolicy.shouldAcceptPet(
                incoming,
                current: fallback,
                hasAuthoritativePet: false
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.shouldAcceptPet(
                incoming,
                current: fallback,
                hasAuthoritativePet: true
            )
        )
    }

    func testRunPolicyRejectsOutOfOrderAndMismatchedPayloads() {
        let activeID = UUID()
        let otherID = UUID()
        let latestUpdate = Date(timeIntervalSince1970: 200)

        XCTAssertFalse(
            PawPaceSyncPolicy.shouldAcceptRun(
                makeRun(id: activeID, updatedAt: Date(timeIntervalSince1970: 199)),
                currentWorkoutID: activeID,
                latestUpdate: latestUpdate,
                allowWorkoutAdoption: false
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.shouldAcceptRun(
                makeRun(id: otherID, updatedAt: Date(timeIntervalSince1970: 201)),
                currentWorkoutID: activeID,
                latestUpdate: latestUpdate,
                allowWorkoutAdoption: false
            )
        )
        XCTAssertTrue(
            PawPaceSyncPolicy.shouldAcceptRun(
                makeRun(id: otherID, updatedAt: Date(timeIntervalSince1970: 201)),
                currentWorkoutID: activeID,
                latestUpdate: latestUpdate,
                allowWorkoutAdoption: true
            )
        )
    }

    func testConnectivityFallbackOnlyStartsForRecentActiveState() {
        let now = Date(timeIntervalSince1970: 500)
        let workoutID = UUID()

        XCTAssertTrue(
            PawPaceSyncPolicy.canStartConnectivityFallback(
                from: makeRun(id: workoutID, phase: .running, updatedAt: now),
                now: now
            )
        )
        XCTAssertTrue(
            PawPaceSyncPolicy.canStartConnectivityFallback(
                from: makeRun(id: workoutID, phase: .paused, updatedAt: now),
                now: now
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.canStartConnectivityFallback(
                from: makeRun(id: workoutID, phase: .finished, updatedAt: now),
                now: now
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.canStartConnectivityFallback(
                from: makeRun(id: workoutID, updatedAt: now.addingTimeInterval(-31)),
                now: now
            )
        )
    }

    func testPendingPhoneLaunchCanAdoptItsFirstTerminalPayload() {
        let localStart = Date(timeIntervalSince1970: 500)

        XCTAssertTrue(
            PawPaceSyncPolicy.canAdoptPendingPhoneLaunch(
                from: makeRun(
                    id: UUID(),
                    phase: .finished,
                    startedAt: localStart.addingTimeInterval(3),
                    updatedAt: localStart.addingTimeInterval(120)
                ),
                localStart: localStart
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.canAdoptPendingPhoneLaunch(
                from: makeRun(
                    id: UUID(),
                    phase: .finished,
                    startedAt: localStart.addingTimeInterval(61),
                    updatedAt: localStart.addingTimeInterval(120)
                ),
                localStart: localStart
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.canAdoptPendingPhoneLaunch(
                from: makeRun(
                    id: UUID(),
                    phase: .finished,
                    startedAt: localStart.addingTimeInterval(-30),
                    updatedAt: localStart.addingTimeInterval(-1)
                ),
                localStart: localStart
            )
        )
    }

    func testLaunchChallengeAllowsDelayedAuthorizationButRejectsOldState() {
        let localStart = Date(timeIntervalSince1970: 500)
        let now = localStart.addingTimeInterval(600)

        XCTAssertTrue(
            PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(
                from: makeRun(
                    id: UUID(),
                    phase: .running,
                    startedAt: localStart.addingTimeInterval(1),
                    updatedAt: now
                ),
                localStart: localStart,
                now: now
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(
                from: makeRun(
                    id: UUID(),
                    phase: .running,
                    startedAt: localStart.addingTimeInterval(-61),
                    updatedAt: now
                ),
                localStart: localStart,
                now: now
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(
                from: makeRun(
                    id: UUID(),
                    phase: .finished,
                    startedAt: localStart.addingTimeInterval(-30),
                    updatedAt: localStart.addingTimeInterval(-1)
                ),
                localStart: localStart,
                now: now
            )
        )
    }

    func testRecoveredStatePreservesIdentityStartAndElapsedTime() {
        let workoutID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let state = PawPaceSyncPolicy.recoveredRunState(
            workoutID: workoutID,
            persistedStart: startedAt,
            sessionStart: Date(timeIntervalSince1970: 1_100),
            elapsedSeconds: 321.6,
            updatedAt: Date(timeIntervalSince1970: 1_500)
        )

        XCTAssertEqual(state.workoutID, workoutID)
        XCTAssertEqual(state.startedAt, startedAt)
        XCTAssertEqual(state.elapsedSeconds, 322)
        XCTAssertEqual(state.phase, .idle)
    }

    func testHeartRateZoneBoundaries() {
        XCTAssertNil(PawPaceHeartRateZone.zone(for: 0))
        XCTAssertEqual(PawPaceHeartRateZone.zone(for: 119), .recovery)
        XCTAssertEqual(PawPaceHeartRateZone.zone(for: 120), .endurance)
        XCTAssertEqual(PawPaceHeartRateZone.zone(for: 140), .tempo)
        XCTAssertEqual(PawPaceHeartRateZone.zone(for: 160), .threshold)
        XCTAssertEqual(PawPaceHeartRateZone.zone(for: 180), .peak)
    }

    func testWatchPayloadRoundTripsWithoutLosingPetOrRunState() throws {
        let workoutID = UUID()
        var pet = PetSnapshot.starter
        pet.name = "Mochi Test"
        pet.level = 25
        pet.mood = .excited
        pet.energy = 61
        pet.equippedDecoration = "Star Lanterns"

        let run = PawPaceRunState(
            workoutID: workoutID,
            phase: .running,
            distanceKilometers: 2.75,
            elapsedSeconds: 1_101,
            paceSecondsPerKilometer: 400,
            heartRate: 151,
            experienceEarned: 138,
            encouragement: "Maximum zoomies!",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_001_101)
        )

        let control = PawPaceWatchControl(
            id: UUID(),
            workoutID: workoutID,
            action: .pause,
            startedAt: try XCTUnwrap(run.startedAt),
            issuedAt: run.updatedAt.addingTimeInterval(1),
            replyToWatchWorkoutID: UUID()
        )
        let encoded = try JSONEncoder().encode(
            PawPaceWatchPayload(pet: pet, run: run, control: control)
        )
        let decoded = try JSONDecoder().decode(PawPaceWatchPayload.self, from: encoded)

        XCTAssertEqual(decoded.pet, pet)
        XCTAssertEqual(decoded.run, run)
        XCTAssertEqual(decoded.control, control)
    }

    func testOnlyAControlReplyingToTheProvisionalWatchIDCanBindALaunch() {
        let provisionalWatchID = UUID()
        let phoneWorkoutID = UUID()
        let bindingControl = PawPaceWatchControl(
            id: UUID(),
            workoutID: phoneWorkoutID,
            action: .finish,
            startedAt: Date(timeIntervalSince1970: 2_000),
            issuedAt: Date(timeIntervalSince1970: 2_010),
            replyToWatchWorkoutID: provisionalWatchID
        )
        let delayedFinish = PawPaceWatchControl(
            id: UUID(),
            workoutID: UUID(),
            action: .finish,
            startedAt: Date(timeIntervalSince1970: 1_950),
            issuedAt: Date(timeIntervalSince1970: 2_011)
        )

        XCTAssertTrue(
            PawPaceSyncPolicy.canBindPhoneControl(
                bindingControl,
                provisionalWatchWorkoutID: provisionalWatchID
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.canBindPhoneControl(
                delayedFinish,
                provisionalWatchWorkoutID: provisionalWatchID
            )
        )
    }

    func testRewardedTerminalDuplicateIsConsumedUnlessItsExactRecordIsPending() {
        let terminal = makeRun(
            id: UUID(),
            phase: .finished,
            updatedAt: Date(timeIntervalSince1970: 2_500)
        )

        XCTAssertTrue(
            PawPaceSyncPolicy.shouldConsumePreviouslyRewardedTerminal(
                terminal,
                wasTerminalHandled: false,
                hasRegisteredReward: true,
                hasExactPendingRecord: false
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.shouldConsumePreviouslyRewardedTerminal(
                terminal,
                wasTerminalHandled: false,
                hasRegisteredReward: true,
                hasExactPendingRecord: true
            )
        )
        XCTAssertTrue(
            PawPaceSyncPolicy.shouldConsumePreviouslyRewardedTerminal(
                terminal,
                wasTerminalHandled: true,
                hasRegisteredReward: true,
                hasExactPendingRecord: true
            )
        )
        XCTAssertFalse(
            PawPaceSyncPolicy.shouldConsumePreviouslyRewardedTerminal(
                makeRun(
                    id: terminal.workoutID ?? UUID(),
                    phase: .running,
                    updatedAt: terminal.updatedAt
                ),
                wasTerminalHandled: true,
                hasRegisteredReward: true,
                hasExactPendingRecord: false
            )
        )
    }

    func testLegacyPhaseOnlyControlStillDecodes() throws {
        struct LegacyControl: Codable {
            let id: UUID
            let workoutID: UUID
            let phase: PawPaceRunPhase
            let startedAt: Date
            let issuedAt: Date
        }

        let legacy = LegacyControl(
            id: UUID(),
            workoutID: UUID(),
            phase: .paused,
            startedAt: Date(timeIntervalSince1970: 3_000),
            issuedAt: Date(timeIntervalSince1970: 3_010)
        )
        let decoded = try JSONDecoder().decode(
            PawPaceWatchControl.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(decoded.id, legacy.id)
        XCTAssertEqual(decoded.workoutID, legacy.workoutID)
        XCTAssertEqual(decoded.action, .pause)
        XCTAssertNil(decoded.replyToWatchWorkoutID)
    }

    func testWorkoutRewardIsRegisteredOnlyOnce() throws {
        let suiteName = "WatchSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workoutID = UUID()

        XCTAssertTrue(PawPaceShared.registerReward(for: workoutID, in: defaults))
        XCTAssertFalse(PawPaceShared.registerReward(for: workoutID, in: defaults))
        XCTAssertTrue(PawPaceShared.hasRegisteredReward(for: workoutID, in: defaults))
        XCTAssertFalse(PawPaceShared.hasRegisteredReward(for: UUID(), in: defaults))
        XCTAssertEqual(
            defaults.stringArray(forKey: PawPaceShared.rewardedWorkoutIDsKey),
            [workoutID.uuidString]
        )
    }

    func testRewardHistoryRetainsEveryHandledWorkoutID() throws {
        let suiteName = "WatchSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workoutIDs = (0..<25).map { _ in UUID() }

        workoutIDs.forEach { PawPaceShared.registerReward(for: $0, in: defaults) }

        let recorded = try XCTUnwrap(
            defaults.stringArray(forKey: PawPaceShared.rewardedWorkoutIDsKey)
        )
        XCTAssertEqual(recorded, workoutIDs.map(\.uuidString))
    }

    private func makeRun(
        id: UUID,
        phase: PawPaceRunPhase = .running,
        startedAt: Date? = nil,
        updatedAt: Date
    ) -> PawPaceRunState {
        PawPaceRunState(
            workoutID: id,
            phase: phase,
            distanceKilometers: 1,
            elapsedSeconds: 300,
            paceSecondsPerKilometer: 300,
            heartRate: 140,
            experienceEarned: 52,
            encouragement: "Keep going!",
            startedAt: startedAt ?? updatedAt.addingTimeInterval(-300),
            updatedAt: updatedAt
        )
    }
}
