import XCTest
@testable import PawPace

final class PhoneWorkoutRecoveryTests: XCTestCase {
    func testCheckpointResumesPausedAndExcludesAllClosedTime() throws {
        let state = makeState()
        let checkpoint = try XCTUnwrap(PhoneWorkoutCheckpoint(state: state))
        let persisted = try JSONDecoder().decode(PhoneWorkoutCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        let returnedAt = state.updatedAt.addingTimeInterval(7_200)
        let paused = try XCTUnwrap(persisted.pausedState(at: returnedAt))
        XCTAssertEqual(paused.phase, .paused)
        XCTAssertEqual(paused.elapsedSeconds, 300)
        XCTAssertEqual(paused.workoutID, state.workoutID)
        XCTAssertEqual(paused.pauseStartedAt, state.updatedAt)
        XCTAssertEqual(paused.workoutConfiguration, state.workoutConfiguration)
        let active = WorkoutTiming.activeIntervals(
            startedAt: try XCTUnwrap(paused.startedAt), endedAt: returnedAt,
            pauseIntervals: paused.pauseIntervals, pauseStartedAt: paused.pauseStartedAt
        ).reduce(0) { $0 + $1.duration }
        XCTAssertEqual(active, 300)
    }

    func testAlreadyPausedCheckpointPreservesPauseBeginningAcrossRepeatedRelaunches() throws {
        var state = makeState()
        state.phase = .paused
        state.pauseStartedAt = state.updatedAt
        state.updatedAt = state.updatedAt.addingTimeInterval(600)
        let first = try XCTUnwrap(PhoneWorkoutCheckpoint(state: state)?.pausedState(at: state.updatedAt.addingTimeInterval(500)))
        let second = try XCTUnwrap(PhoneWorkoutCheckpoint(state: first)?.pausedState(at: first.updatedAt.addingTimeInterval(1_000)))
        XCTAssertEqual(second.elapsedSeconds, 300)
        XCTAssertEqual(second.pauseStartedAt, state.pauseStartedAt)
        XCTAssertEqual(second.pauseIntervals, state.pauseIntervals)
    }

    func testInvalidAndTerminalStatesCannotBecomePhoneCheckpoints() {
        for phase in [PawPaceRunPhase.idle, .finished, .failed] {
            var state = makeState()
            state.phase = phase
            XCTAssertNil(PhoneWorkoutCheckpoint(state: state))
        }
        var state = makeState()
        state.workoutID = nil
        XCTAssertNil(PhoneWorkoutCheckpoint(state: state))
        state = makeState()
        state.distanceKilometers = .nan
        XCTAssertNil(PhoneWorkoutCheckpoint(state: state))
        state = makeState()
        state.elapsedSeconds = 0
        XCTAssertNil(PhoneWorkoutCheckpoint(state: state))
        state = makeState()
        state.isAwaitingPhoneConfiguration = true
        XCTAssertNil(PhoneWorkoutCheckpoint(state: state))
    }

    @MainActor
    func testRelaunchOffersWorkoutWithoutStartingThenExplicitRestoreKeepsRecordedTime() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let state = makeState()
        try storage.save(try XCTUnwrap(PhoneWorkoutCheckpoint(state: state)), named: checkpointName)
        let tracker = makeTracker(storage: storage)
        defer { tracker.reset() }
        XCTAssertEqual(tracker.phase, .idle)
        XCTAssertEqual(tracker.interruptedWorkout?.workoutID, state.workoutID)
        XCTAssertTrue(tracker.restoreInterruptedWorkout())
        XCTAssertEqual(tracker.phase, .paused)
        XCTAssertEqual(tracker.elapsedSeconds, 300)
        XCTAssertEqual(tracker.currentRunState.workoutID, state.workoutID)
        XCTAssertEqual(tracker.currentRunState.pauseStartedAt, state.updatedAt)
        XCTAssertNil(tracker.interruptedWorkout)
        XCTAssertNotNil(tracker.recoveredWorkoutMessage)
        let afterRelaunch = makeTracker(storage: storage)
        XCTAssertEqual(afterRelaunch.interruptedWorkout?.elapsedSeconds, 300)
        XCTAssertEqual(afterRelaunch.interruptedWorkout?.pauseStartedAt, state.updatedAt)
    }

    @MainActor
    func testNewPhoneWorkoutWaitsForPendingRecoveryDecision() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let state = makeState()
        try storage.save(try XCTUnwrap(PhoneWorkoutCheckpoint(state: state)), named: checkpointName)
        let tracker = makeTracker(storage: storage)
        tracker.start()
        XCTAssertEqual(tracker.phase, .idle)
        XCTAssertEqual(tracker.interruptedWorkout?.workoutID, state.workoutID)
        XCTAssertTrue(tracker.discardInterruptedWorkout())
        XCTAssertNil(tracker.interruptedWorkout)
        XCTAssertNil(try storage.load(PhoneWorkoutCheckpoint.self, named: checkpointName))
    }

    @MainActor
    func testSameWatchIdentitySupersedesCheckpointWithoutDuplicateRecovery() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        var state = makeState()
        try storage.save(try XCTUnwrap(PhoneWorkoutCheckpoint(state: state)), named: checkpointName)
        let tracker = makeTracker(storage: storage)
        state.updatedAt = .now
        XCTAssertTrue(tracker.applyWatchState(state, allowWorkoutAdoption: true))
        XCTAssertNil(tracker.interruptedWorkout)
        XCTAssertNil(try storage.load(PhoneWorkoutCheckpoint.self, named: checkpointName))
    }

    @MainActor
    func testDifferentWatchWorkoutKeepsEarlierInterruptedPhoneWorkout() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let interrupted = makeState()
        try storage.save(try XCTUnwrap(PhoneWorkoutCheckpoint(state: interrupted)), named: checkpointName)
        let tracker = makeTracker(storage: storage)
        var liveWatch = makeState()
        liveWatch.updatedAt = .now
        XCTAssertTrue(tracker.applyWatchState(liveWatch, allowWorkoutAdoption: true))
        XCTAssertFalse(tracker.restoreInterruptedWorkout(), "An active Watch session gets priority over an older phone checkpoint")
        tracker.acknowledgeWorkoutSaved(try XCTUnwrap(liveWatch.workoutID))
        XCTAssertEqual(tracker.interruptedWorkout?.workoutID, interrupted.workoutID)
        XCTAssertEqual(try storage.load(PhoneWorkoutCheckpoint.self, named: checkpointName)?.state.workoutID, interrupted.workoutID)
    }

    @MainActor
    func testFailedRecoveryReadPreservesSavedFileAndSurfacesError() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        try FileManager.default.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
        let corrupt = Data("corrupt checkpoint".utf8)
        let file = storage.directoryURL.appendingPathComponent(checkpointName)
        try corrupt.write(to: file)
        let tracker = makeTracker(storage: storage)
        XCTAssertNil(tracker.interruptedWorkout)
        XCTAssertNotNil(tracker.recoveryStorageMessage)
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    @MainActor
    func testAcknowledgementRemovesOnlyMatchingCompletedCheckpoint() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let state = makeState()
        try storage.save(try XCTUnwrap(PhoneWorkoutCheckpoint(state: state)), named: checkpointName)
        let tracker = makeTracker(storage: storage)
        tracker.acknowledgeWorkoutSaved(UUID())
        XCTAssertNotNil(try storage.load(PhoneWorkoutCheckpoint.self, named: checkpointName))
        tracker.acknowledgeWorkoutSaved(try XCTUnwrap(state.workoutID))
        XCTAssertNil(try storage.load(PhoneWorkoutCheckpoint.self, named: checkpointName))
        XCTAssertNil(tracker.interruptedWorkout)
    }

    @MainActor
    func testLegacyPendingHealthSavesMigrateOnlyAfterProtectedWrite() throws {
        let storage = temporaryStorage()
        let suite = "pawpace-migration-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: storage.directoryURL)
            defaults.removePersistentDomain(forName: suite)
        }
        let summary = RunSummary(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_300), distanceMeters: 0, elapsedSeconds: 300,
            averagePaceSecondsPerKilometer: 0, averageHeartRate: nil, experienceEarned: 30)
        let data = try JSONEncoder().encode([LegacyPendingRecord(summary: summary, requiresPhoneSave: true)])
        defaults.set(data, forKey: "pawpace.pendingWatchHealthRecords.v1")
        let tracker = makeTracker(storage: storage, defaults: defaults)
        XCTAssertEqual(tracker.pendingFailedWatchSummaries(), [summary])
        XCTAssertNil(defaults.object(forKey: "pawpace.pendingWatchHealthRecords.v1"))
        let restored = makeTracker(storage: storage, defaults: defaults)
        XCTAssertEqual(restored.pendingFailedWatchSummaries(), [summary])
        let values = try storage.directoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    @MainActor
    func testFailedPendingHealthMigrationKeepsLegacyRecord() throws {
        let storage = temporaryStorage()
        let suite = "pawpace-migration-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: storage.directoryURL)
            defaults.removePersistentDomain(forName: suite)
        }
        let corrupt = Data("unreadable legacy save".utf8)
        defaults.set(corrupt, forKey: "pawpace.pendingWatchHealthRecords.v1")
        let tracker = makeTracker(storage: storage, defaults: defaults)
        XCTAssertTrue(tracker.pendingFailedWatchSummaries().isEmpty)
        XCTAssertEqual(defaults.data(forKey: "pawpace.pendingWatchHealthRecords.v1"), corrupt)
        XCTAssertNotNil(tracker.recoveryStorageMessage)
    }

    private struct LegacyPendingRecord: Codable {
        let summary: RunSummary
        let requiresPhoneSave: Bool
    }

    private let checkpointName = "phone-workout-checkpoint-v1.json"

    private func makeState() -> PawPaceRunState {
        let start = Date().addingTimeInterval(-3_600)
        var state = PawPaceRunState.idle
        state.workoutID = UUID()
        state.phase = .running
        state.startedAt = start
        state.updatedAt = start.addingTimeInterval(300)
        state.elapsedSeconds = 300
        state.workoutConfiguration = WorkoutConfiguration(activity: .yoga)
        return state
    }

    private func temporaryStorage() -> PawPacePrivateStorage {
        PawPacePrivateStorage(directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("pawpace-recovery-test-\(UUID().uuidString)", isDirectory: true))
    }

    @MainActor
    private func makeTracker(storage: PawPacePrivateStorage, defaults: UserDefaults? = nil) -> RunTracker {
        RunTracker(healthKit: HealthKitService(), petSnapshot: { .starter },
                   watchConnectivity: PhoneWatchConnectivityService(), privateStorage: storage, legacyDefaults: defaults)
    }
}
