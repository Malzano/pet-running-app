import Foundation
import XCTest
@testable import PawPace

final class WatchWorkoutRecoveryTests: XCTestCase {
    private var directoryURL: URL!
    private var defaults: UserDefaults!
    private var defaultsSuite: String!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("WatchRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defaultsSuite = "WatchRecoveryTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: defaultsSuite)
        if FileManager.default.fileExists(atPath: directoryURL.path) { try FileManager.default.removeItem(at: directoryURL) }
    }

    func testSplitLegacyMetadataMigratesWithoutChangingIdentityOrMetrics() throws {
        let record = makeRecord()
        try writeLegacy(record)
        let store = makeStore()

        XCTAssertEqual(try store.load(), record)
        XCTAssertTrue(WatchWorkoutRecoveryStore.LegacyKey.all.allSatisfy { defaults.object(forKey: $0) == nil })
        XCTAssertEqual(try makeStore().load(), record, "A fresh store must recover the same launch identity and leg metrics")
        let location = directoryURL.appendingPathComponent(WatchWorkoutRecoveryStore.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path))
        XCTAssertEqual(try directoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        // The simulator uses the Mac's filesystem and does not expose iOS
        // Data Protection attributes. This assertion is a physical-device gate;
        // backup exclusion and all migration checks still run in the simulator.
#if os(iOS) && !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
#endif
    }

    func testIncompleteLegacyMetadataKeepsHealthKitFallbackFieldsEmpty() throws {
        let configuration = WorkoutConfiguration(activity: .swimming, location: .indoor, poolLengthMeters: 50)
        defaults.set(try JSONEncoder().encode(configuration), forKey: WatchWorkoutRecoveryStore.LegacyKey.configuration)

        let recovered = try XCTUnwrap(makeStore().load())

        XCTAssertNil(recovered.workoutID)
        XCTAssertNil(recovered.startedAt)
        XCTAssertEqual(recovered.configuration, configuration)
        XCTAssertFalse(recovered.awaitingPhoneBinding)
        XCTAssertEqual(recovered.multisportLegIndex, 0)
        XCTAssertTrue(recovered.activitySegments.isEmpty)
    }

    func testFailedMigrationKeepsEveryLegacyPreference() throws {
        let record = makeRecord()
        try writeLegacy(record)
        // A regular file at the intended directory makes protected storage
        // unavailable without relying on simulator-specific permissions.
        let sentinel = Data("keep this file".utf8)
        try sentinel.write(to: directoryURL)

        XCTAssertThrowsError(try makeStore().load())
        XCTAssertTrue(WatchWorkoutRecoveryStore.LegacyKey.all.allSatisfy { defaults.object(forKey: $0) != nil })
        XCTAssertEqual(defaults.string(forKey: WatchWorkoutRecoveryStore.LegacyKey.workoutID), record.workoutID?.uuidString)
        XCTAssertEqual(try Data(contentsOf: directoryURL), sentinel)
    }

    func testMalformedLegacyMetadataCannotBeReplacedOrCleared() throws {
        try writeLegacy(makeRecord())
        let damaged = Data("unreadable segments".utf8)
        defaults.set(damaged, forKey: WatchWorkoutRecoveryStore.LegacyKey.activitySegments)
        let originalID = defaults.string(forKey: WatchWorkoutRecoveryStore.LegacyKey.workoutID)
        let store = makeStore()

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(makeRecord()))
        XCTAssertThrowsError(try store.clear())
        XCTAssertEqual(defaults.data(forKey: WatchWorkoutRecoveryStore.LegacyKey.activitySegments), damaged)
        XCTAssertEqual(defaults.string(forKey: WatchWorkoutRecoveryStore.LegacyKey.workoutID), originalID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(WatchWorkoutRecoveryStore.fileName).path))
    }

    func testCorruptPrivateRecordDoesNotDeleteLegacyOrAcceptNewIdentity() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let location = directoryURL.appendingPathComponent(WatchWorkoutRecoveryStore.fileName)
        let damaged = Data("unreadable recovery record".utf8)
        try damaged.write(to: location)
        let oldRecord = makeRecord()
        try writeLegacy(oldRecord)
        let store = makeStore()

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(makeRecord()))
        XCTAssertThrowsError(try store.clear())
        XCTAssertEqual(try Data(contentsOf: location), damaged)
        XCTAssertEqual(defaults.string(forKey: WatchWorkoutRecoveryStore.LegacyKey.workoutID), oldRecord.workoutID?.uuidString)
    }

    func testFailedEncodingPreservesThePreviousDurableRecord() throws {
        let record = makeRecord()
        let store = makeStore()
        try store.save(record)
        var invalid = record
        invalid.activitySegments[0].distanceMeters = .nan

        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try makeStore().load(), record)
    }

    func testDurableFileWinsOverStaleLegacyPreferencesAndCompletionClearsIt() throws {
        let store = makeStore()
        let record = makeRecord()
        try store.save(record)
        try writeLegacy(makeRecord())

        XCTAssertEqual(try store.load(), record)
        XCTAssertTrue(WatchWorkoutRecoveryStore.LegacyKey.all.allSatisfy { defaults.object(forKey: $0) == nil })
        try store.clear()
        XCTAssertNil(try makeStore().load())
    }

    private func makeStore() -> WatchWorkoutRecoveryStore {
        WatchWorkoutRecoveryStore(storage: PawPacePrivateStorage(directoryURL: directoryURL), legacyDefaults: defaults)
    }

    private func makeRecord() -> WatchWorkoutRecoveryRecord {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let configuration = WorkoutConfiguration(activity: .swimBikeRun, location: .outdoor)
        return WatchWorkoutRecoveryRecord(
            workoutID: UUID(), startedAt: startedAt, awaitingPhoneBinding: true,
            configuration: configuration, multisportLegIndex: 1,
            activitySegments: [
                WorkoutActivitySegment(configuration: configuration.configuration(forMultisportLeg: 0),
                                       startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600),
                                       distanceMeters: 400, activeEnergyKilocalories: 83),
                WorkoutActivitySegment(configuration: configuration.configuration(forMultisportLeg: 1),
                                       startedAt: startedAt.addingTimeInterval(600), endedAt: nil,
                                       distanceMeters: 2_650, activeEnergyKilocalories: 127)
            ]
        )
    }

    private func writeLegacy(_ record: WatchWorkoutRecoveryRecord) throws {
        typealias Key = WatchWorkoutRecoveryStore.LegacyKey
        defaults.set(record.workoutID?.uuidString, forKey: Key.workoutID)
        defaults.set(record.startedAt, forKey: Key.startedAt)
        defaults.set(record.awaitingPhoneBinding, forKey: Key.awaitingPhoneBinding)
        defaults.set(try JSONEncoder().encode(record.configuration), forKey: Key.configuration)
        defaults.set(record.multisportLegIndex, forKey: Key.multisportLegIndex)
        defaults.set(try JSONEncoder().encode(record.activitySegments), forKey: Key.activitySegments)
    }
}
