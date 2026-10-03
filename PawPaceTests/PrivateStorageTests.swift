import XCTest
@testable import PawPace

final class PrivateStorageTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PawPacePrivateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "PawPacePrivateTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try FileManager.default.removeItem(at: root)
    }

    private var directory: URL { root.appendingPathComponent("Private", isDirectory: true) }
    private var file: URL { directory.appendingPathComponent(PawPaceSnapshotStore.fileName) }
    private var store: PawPaceSnapshotStore {
        PawPaceSnapshotStore(directoryURL: directory, legacyDefaults: defaults)
    }

    func testMigrationPreservesPetGenesAndMovementThenRemovesLegacyCopy() throws {
        var pet = PetSnapshot.newPlayer(seed: 42, at: Date(timeIntervalSince1970: 100))
        pet.name = "Clover"
        pet.applyRun(distanceKilometers: 2.5, experienceEarned: 200, elapsedSeconds: 1_900,
                     activity: .yoga, workoutID: UUID(), at: Date(timeIntervalSince1970: 2_000))
        pet.equippedDecoration = "Picnic Corner"
        defaults.set(try JSONEncoder().encode(pet), forKey: PawPaceShared.snapshotKey)

        XCTAssertEqual(try store.loadOrCreate(), pet)
        XCTAssertEqual(try store.loadIfPresent(), pet)
        XCTAssertNil(defaults.object(forKey: PawPaceShared.snapshotKey))
        XCTAssertEqual(try JSONDecoder().decode(PetSnapshot.self, from: Data(contentsOf: file)), pet)
    }

    func testFreshEggIsCreatedOnceAcrossStoreInstances() throws {
        let first = try store.loadOrCreate { .newPlayer(seed: 42, at: Date(timeIntervalSince1970: 100)) }
        let second = try store.loadOrCreate { XCTFail("A saved egg must not reroll"); return .starter }
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.lifeStage, .egg)
        XCTAssertNil(defaults.object(forKey: PawPaceShared.snapshotKey))
    }

    func testCorruptLegacySaveIsKeptAndDoesNotBecomeAFreshEgg() throws {
        let original = Data("broken legacy JSON".utf8)
        defaults.set(original, forKey: PawPaceShared.snapshotKey)
        XCTAssertThrowsError(try store.loadOrCreate())
        XCTAssertThrowsError(try store.save(.newPlayer(seed: 7)))
        XCTAssertEqual(defaults.data(forKey: PawPaceShared.snapshotKey), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCorruptPrivateSaveIsNeverOverwrittenByFallbackOrLegacyData() throws {
        _ = try store.loadOrCreate()
        let original = Data("broken private JSON".utf8)
        try original.write(to: file, options: .atomic)
        let legacy = try JSONEncoder().encode(PetSnapshot.starter)
        defaults.set(legacy, forKey: PawPaceShared.snapshotKey)

        XCTAssertThrowsError(try store.loadOrCreate())
        XCTAssertThrowsError(try store.save(.newPlayer(seed: 7)))
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(defaults.data(forKey: PawPaceShared.snapshotKey), legacy)
    }

    func testFailedMigrationDoesNotDeleteLegacyData() throws {
        let original = try JSONEncoder().encode(PetSnapshot.starter)
        defaults.set(original, forKey: PawPaceShared.snapshotKey)
        let blocked = root.appendingPathComponent("blocked")
        try Data("This is a file, not a directory".utf8).write(to: blocked)
        let blockedStore = PawPaceSnapshotStore(directoryURL: blocked.appendingPathComponent("Private"), legacyDefaults: defaults)

        XCTAssertThrowsError(try blockedStore.loadOrCreate())
        XCTAssertEqual(defaults.data(forKey: PawPaceShared.snapshotKey), original)
    }

    func testValidPrivateSaveTakesPrecedenceOverStaleLegacyCopy() throws {
        let pet = PetSnapshot.newPlayer(seed: 42)
        try store.save(pet)
        defaults.set(try JSONEncoder().encode(PetSnapshot.starter), forKey: PawPaceShared.snapshotKey)
        XCTAssertEqual(try store.loadIfPresent(), pet)
        XCTAssertNil(defaults.object(forKey: PawPaceShared.snapshotKey))
    }

    func testPrivateDirectoryExcludesBackupsAndReplacedFilesStayProtected() throws {
        var pet = try store.loadOrCreate()
        pet.name = "Cloud"
        try store.save(pet)

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
#if (os(iOS) || os(watchOS)) && !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let protection = (attributes[.protectionKey] as? FileProtectionType)?.rawValue
            ?? attributes[.protectionKey] as? String
        XCTAssertEqual(protection, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
#endif
        XCTAssertEqual(try store.loadIfPresent()?.name, "Cloud")
    }

    func testCompletedAdultWorkoutCannotAwardTwiceAfterPrivateSaveReload() throws {
        var pet = PetSnapshot.starter
        let workoutID = UUID()
        let endedAt = Date(timeIntervalSince1970: 2_000)
        pet.applyRun(distanceKilometers: 3, experienceEarned: 500, elapsedSeconds: 1_800,
                     activity: .running, workoutID: workoutID, at: endedAt)
        try store.save(pet)
        var restored = try XCTUnwrap(store.loadIfPresent())
        XCTAssertTrue(restored.hasRewardedWorkout(workoutID))
        restored.applyRun(distanceKilometers: 3, experienceEarned: 500, elapsedSeconds: 1_800,
                          activity: .running, workoutID: workoutID, at: endedAt.addingTimeInterval(1_000))
        XCTAssertEqual(restored, pet, "XP, coins, friendship and totals are part of the same deduplicated save")
    }

    func testOldSnapshotsDecodeWithEmptyRewardLedger() throws {
        let encoded = try JSONEncoder().encode(PetSnapshot.starter)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "rewardedWorkoutIDs")
        let restored = try JSONDecoder().decode(PetSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(restored.rewardedWorkoutIDs.isEmpty)
        XCTAssertEqual(restored.level, PetSnapshot.starter.level)
    }

    func testGenericQueueMigratesAtomicallyAndCanBeRemovedIntentionally() throws {
        let storage = PawPacePrivateStorage(directoryURL: directory)
        let key = "pending.records"
        defaults.set(try JSONEncoder().encode(["first"]), forKey: key)
        XCTAssertEqual(try storage.load([String].self, named: "queue.json", legacyDefaults: defaults, legacyKey: key), ["first"])
        XCTAssertNil(defaults.object(forKey: key))
        try storage.save(["first", "second"], named: "queue.json")
        XCTAssertEqual(try storage.load([String].self, named: "queue.json"), ["first", "second"])
        try storage.remove(named: "queue.json")
        XCTAssertNil(try storage.load([String].self, named: "queue.json"))
    }

    func testPetInteractionTransactionKeepsAWorkoutsNewerRewards() throws {
        let initial = PetSnapshot.starter
        try store.save(initial)
        let widgetStore = PawPaceSnapshotStore(directoryURL: directory, legacyDefaults: defaults)
        _ = try widgetStore.loadIfPresent()
        let id = UUID()
        let afterWorkout = try store.update {
            $0.applyRun(distanceKilometers: 3, experienceEarned: 200, elapsedSeconds: 1_800,
                        workoutID: id, at: Date(timeIntervalSince1970: 2_000))
        }
        let afterInteraction = try widgetStore.update { $0.pet(at: Date(timeIntervalSince1970: 2_001)) }
        XCTAssertEqual(afterInteraction.coins, afterWorkout.coins)
        XCTAssertEqual(afterInteraction.experience, afterWorkout.experience)
        XCTAssertTrue(afterInteraction.hasRewardedWorkout(id))
        XCTAssertEqual(afterInteraction.dailyWorkoutSeconds, afterWorkout.dailyWorkoutSeconds)
        XCTAssertEqual(afterInteraction.friendship, min(100, afterWorkout.friendship + 4))
    }
}
