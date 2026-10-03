import XCTest
@testable import PawPace

@MainActor
final class WorkoutCompletionTests: XCTestCase {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PawPaceCompletionTests-\(UUID().uuidString)")
    }

    private func summary(id: UUID = UUID()) -> RunSummary {
        RunSummary(id: id, startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 700),
                   distanceMeters: 0, elapsedSeconds: 600, averagePaceSecondsPerKilometer: 0,
                   averageHeartRate: nil, experienceEarned: 60,
                   workoutConfiguration: WorkoutConfiguration(activity: .yoga))
    }

    func testCompletionSurvivesRelaunchWithItsCanonicalAndWatchIdentities() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = PawPacePrivateStorage(directoryURL: directory)
        let outbox = WorkoutCompletionStore(storage: storage)
        let workout = summary()
        let alias = UUID()
        let queued = try XCTUnwrap(outbox.enqueue(workout, aliases: [alias]))
        XCTAssertEqual(queued.rewardIDs, [workout.id, alias])
        XCTAssertEqual(WorkoutCompletionStore(storage: storage).pending, [queued])
    }

    func testJournalFailureRetainsOutboxAndRetryDoesNotAwardPetTwice() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = PawPacePrivateStorage(directoryURL: directory)
        let outbox = WorkoutCompletionStore(storage: storage)
        let entry = try XCTUnwrap(outbox.enqueue(summary(), aliases: [UUID()]))
        let pet = PetStore(snapshot: .newPlayer(seed: 42))
        var acknowledgments = 0
        XCTAssertFalse(outbox.process(entry, persistPet: {
            pet.applyRun(entry.summary, rewardAliases: entry.rewardIDs)
        }, persistJournal: { false }, acknowledge: { acknowledgments += 1; return true }))
        let alreadySavedPet = pet.snapshot
        XCTAssertEqual(acknowledgments, 0)
        XCTAssertEqual(outbox.pending, [entry])

        let relaunched = WorkoutCompletionStore(storage: storage)
        let restoredEntry = try XCTUnwrap(relaunched.pending.first)
        let restoredPet = PetStore(snapshot: alreadySavedPet)
        let journal = WorkoutHistoryStore(fileURL: directory.appendingPathComponent("journal/workouts.json"))
        XCTAssertTrue(relaunched.process(restoredEntry, persistPet: {
            restoredPet.applyRun(restoredEntry.summary, rewardAliases: restoredEntry.rewardIDs)
        }, persistJournal: { journal.append(restoredEntry.summary) }, acknowledge: { acknowledgments += 1; return true }))
        XCTAssertEqual(restoredPet.snapshot, alreadySavedPet)
        XCTAssertEqual(journal.workouts, [entry.summary])
        XCTAssertEqual(acknowledgments, 1)
        XCTAssertTrue(WorkoutCompletionStore(storage: storage).pending.isEmpty)
    }

    func testFailedPetWriteDoesNotAdvanceJournalOrAcknowledgeCompletion() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = WorkoutCompletionStore(storage: PawPacePrivateStorage(directoryURL: directory))
        let entry = try XCTUnwrap(outbox.enqueue(summary()))
        XCTAssertFalse(outbox.process(entry, persistPet: { false },
                                     persistJournal: { XCTFail("Pet save failed"); return true },
                                     acknowledge: { XCTFail("Pet save failed"); return true }))
        XCTAssertEqual(outbox.pending, [entry])
    }

    func testFailedTerminalAcknowledgmentKeepsCompletionReplayable() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = WorkoutCompletionStore(storage: PawPacePrivateStorage(directoryURL: directory))
        let entry = try XCTUnwrap(outbox.enqueue(summary()))
        XCTAssertFalse(outbox.process(entry, persistPet: { true }, persistJournal: { true }, acknowledge: { false }))
        XCTAssertEqual(outbox.pending, [entry])
    }

    func testDeleteDecisionSurvivesRelaunchAndAliasRetryWithoutRepopulatingJournal() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = PawPacePrivateStorage(directoryURL: directory)
        let outbox = WorkoutCompletionStore(storage: storage)
        let workout = summary()
        _ = try XCTUnwrap(outbox.enqueue(workout))
        XCTAssertTrue(outbox.stopPendingJournalWrites())
        let relaunched = WorkoutCompletionStore(storage: storage)
        let retry = try XCTUnwrap(relaunched.enqueue(workout, aliases: [UUID()], journalRequested: true))
        XCTAssertFalse(retry.journalRequested)
        XCTAssertTrue(relaunched.process(retry, persistPet: { true },
                                        persistJournal: { XCTFail("Deleted journal must stay deleted"); return false },
                                        acknowledge: { true }))
    }

    func testKnownAliasesConsolidatePendingRecordsBeforeTheyCanAwardSeparately() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = WorkoutCompletionStore(storage: PawPacePrivateStorage(directoryURL: directory))
        let phone = summary()
        let watch = summary()
        _ = outbox.enqueue(phone)
        _ = outbox.enqueue(watch)
        let merged = try XCTUnwrap(outbox.enqueue(phone, aliases: [watch.id]))
        XCTAssertEqual(outbox.pending, [merged])
        XCTAssertEqual(merged.summary.id, phone.id)
        XCTAssertEqual(merged.rewardIDs, [phone.id, watch.id])
    }

    func testAliasReplayAndLegacyRewardMigrationDoNotAddXPAgain() {
        let canonical = summary()
        let alias = UUID()
        let pet = PetStore(snapshot: .starter)
        XCTAssertTrue(pet.applyRun(canonical, rewardAliases: [alias]))
        let after = pet.snapshot
        XCTAssertTrue(pet.applyRun(summary(id: alias), rewardAliases: [canonical.id]))
        XCTAssertEqual(pet.snapshot, after)

        let legacy = PetStore(snapshot: .starter)
        let before = legacy.snapshot
        XCTAssertTrue(legacy.applyRun(canonical, rewardAliases: [alias], awardIfUnrecorded: false))
        XCTAssertEqual(legacy.snapshot.experience, before.experience)
        XCTAssertEqual(legacy.snapshot.coins, before.coins)
        XCTAssertTrue(legacy.snapshot.hasRewardedWorkout(canonical.id))
        XCTAssertTrue(legacy.snapshot.hasRewardedWorkout(alias))
    }

    func testUnreadableOutboxIsPreservedAndDeletionCannotBypassItsJournalDecision() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("workout-completions-v1.json")
        let original = Data("unreadable outbox".utf8)
        try original.write(to: file)
        let outbox = WorkoutCompletionStore(storage: PawPacePrivateStorage(directoryURL: directory))
        XCTAssertNotNil(outbox.storageMessage)
        XCTAssertNil(outbox.enqueue(summary()))
        XCTAssertFalse(outbox.stopPendingJournalWrites())
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testRetryKeepsAnUnsavedSummaryInMemoryUntilStorageBecomesAvailable() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = directory.appendingPathComponent("blocked")
        try Data("blocking file".utf8).write(to: blocked)
        let storage = PawPacePrivateStorage(directoryURL: blocked.appendingPathComponent("private"))
        let outbox = WorkoutCompletionStore(storage: storage)
        let workout = summary()
        let alias = UUID()
        XCTAssertNil(outbox.enqueue(workout, aliases: [alias]))
        XCTAssertNotNil(outbox.storageMessage)
        try FileManager.default.removeItem(at: blocked)
        let laterAlias = UUID()
        XCTAssertNotNil(outbox.enqueue(workout, aliases: [laterAlias]))
        XCTAssertTrue(outbox.reload())
        XCTAssertEqual(outbox.pending.first?.summary, workout)
        XCTAssertEqual(outbox.pending.first?.rewardIDs, [workout.id, alias, laterAlias])
        XCTAssertEqual(WorkoutCompletionStore(storage: storage).pending, outbox.pending)
    }
}
