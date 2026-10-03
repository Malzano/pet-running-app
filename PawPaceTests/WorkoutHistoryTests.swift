import XCTest
@testable import PawPace

final class WorkoutHistoryTests: XCTestCase {
    @MainActor
    func testJournalPersistsExactSummaryAndDeduplicatesWorkoutIdentity() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = WorkoutHistoryStore(fileURL: file)
        let workout = summary()
        XCTAssertTrue(store.append(workout))
        XCTAssertFalse(store.append(workout))
        XCTAssertEqual(store.workouts, [workout])
        XCTAssertEqual(WorkoutHistoryStore(fileURL: file).workouts, [workout])
        XCTAssertNil(store.storageMessage)
        let directoryValues = try file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(directoryValues.isExcludedFromBackup, true)
    }

    @MainActor
    func testDelayedWatchSummaryKeepsJournalInNewestFirstOrder() {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = WorkoutHistoryStore(fileURL: file)
        let newer = summary(endedAt: Date(timeIntervalSince1970: 1_700_100_000))
        let older = summary(endedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(store.append(newer))
        XCTAssertTrue(store.append(older))
        XCTAssertEqual(store.workouts.map(\.id), [newer.id, older.id])
    }

    @MainActor
    func testDeletingJournalRemovesOnlyItsFileAndAllowsFutureWorkouts() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = WorkoutHistoryStore(fileURL: file)
        XCTAssertTrue(store.append(summary()))
        let unrelated = file.deletingLastPathComponent().appendingPathComponent("companion.json")
        let unrelatedData = Data("companion progress".utf8)
        try unrelatedData.write(to: unrelated)
        XCTAssertTrue(store.deleteAll())
        XCTAssertTrue(store.workouts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: unrelated), unrelatedData)
        let next = summary()
        XCTAssertTrue(store.append(next))
        XCTAssertEqual(WorkoutHistoryStore(fileURL: file).workouts, [next])
    }

    @MainActor
    func testUnreadableHistoryIsPreservedUntilExplicitDeletion() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = Data("unreadable saved history".utf8)
        try invalid.write(to: file)
        let store = WorkoutHistoryStore(fileURL: file)
        XCTAssertNotNil(store.storageMessage)
        XCTAssertFalse(store.append(summary()))
        XCTAssertEqual(try Data(contentsOf: file), invalid)
        XCTAssertTrue(store.deleteAll())
        XCTAssertTrue(store.append(summary()))
        XCTAssertNil(store.storageMessage)
    }

    @MainActor
    func testInvalidSummaryCannotCorruptExistingHistory() {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = WorkoutHistoryStore(fileURL: file)
        let valid = summary()
        XCTAssertTrue(store.append(valid))
        XCTAssertFalse(store.append(summary(duration: 0)))
        XCTAssertFalse(store.append(summary(distance: .nan)))
        XCTAssertFalse(store.append(summary(distance: -.infinity)))
        XCTAssertEqual(WorkoutHistoryStore(fileURL: file).workouts, [valid])
    }

    @MainActor
    func testStorageFailureDoesNotClaimWorkoutWasSaved() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let blockingFile = file.deletingLastPathComponent().appendingPathComponent("not-a-directory")
        try Data().write(to: blockingFile)
        let store = WorkoutHistoryStore(fileURL: blockingFile.appendingPathComponent("journal.json"))
        XCTAssertFalse(store.append(summary()))
        XCTAssertTrue(store.workouts.isEmpty)
        XCTAssertNotNil(store.storageMessage)
    }

    func testCompanionNameNormalizesWhitespaceAndPreservesUnicode() {
        XCTAssertEqual(PetName.normalized("  Mochi   Moon  "), "Mochi Moon")
        XCTAssertEqual(PetName.normalized("  มะลิ 🐾  "), "มะลิ 🐾")
        XCTAssertEqual(PetName.normalized(String(repeating: "🐶", count: 24)), String(repeating: "🐶", count: 24))
    }

    func testCompanionNameRejectsEmptyOverlongAndControlCharacters() {
        XCTAssertNil(PetName.normalized(" \n\t "))
        XCTAssertNil(PetName.normalized(String(repeating: "🐶", count: 25)))
        XCTAssertNil(PetName.normalized("Mochi\u{0000}"))
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pawpace-journal-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workouts.json")
    }

    private func summary(
        endedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        duration: Int = 1_800,
        distance: Double = 0
    ) -> RunSummary {
        RunSummary(
            id: UUID(), startedAt: endedAt.addingTimeInterval(-Double(duration)), endedAt: endedAt,
            distanceMeters: distance, elapsedSeconds: duration, averagePaceSecondsPerKilometer: 0,
            averageHeartRate: nil, experienceEarned: 180,
            workoutConfiguration: WorkoutConfiguration(activity: .yoga)
        )
    }
}
