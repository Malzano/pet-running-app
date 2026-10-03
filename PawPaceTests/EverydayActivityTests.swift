import XCTest
@testable import PawPace

@MainActor
final class EverydayActivityTests: XCTestCase {
    func testOptInAndRepeatedImportsCreditOnceAndPersist() async throws {
        let (service, reader, defaults) = fixture()
        defer { defaults.removePersistentDomain(forName: reader.suite) }
        let store = PetStore(snapshot: .newPlayer(seed: 42))
        let history = WorkoutHistoryStore(fileURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        defer { _ = history.deleteAll() }
        let workout = summary()
        reader.batch = EverydayActivityBatch(workouts: [workout], steps: [(workout.endedAt, 1_000)])
        await service.refresh(store: store, history: history, acceptWorkout: { _ in XCTFail("Off by default"); return false })
        XCTAssertEqual(reader.readCount, 0)
        await service.setEnabled(true)
        for _ in 0..<2 {
            await service.refresh(store: store, history: history, acceptWorkout: { store.applyRun($0) })
        }
        XCTAssertEqual(store.snapshot.lifecycle?.creditedSeconds, 600)
        XCTAssertEqual(reader.readCount, 2)
        XCTAssertNotNil(service.lastSynced)
        XCTAssertTrue(EverydayActivityService(defaults: defaults, reader: reader).isEnabled)
        await service.setEnabled(false)
        let progress = store.snapshot
        await service.refresh(store: store, history: history, acceptWorkout: { store.applyRun($0) })
        XCTAssertEqual(store.snapshot, progress)
        XCTAssertEqual(reader.readCount, 2)
    }

    func testFailedPermissionDoesNotEnableImport() async {
        let (service, reader, defaults) = fixture()
        defer { defaults.removePersistentDomain(forName: reader.suite) }
        reader.failAccess = true
        await service.setEnabled(true)
        XCTAssertFalse(service.isEnabled)
        XCTAssertNotNil(service.message)
        XCTAssertFalse(service.isSyncing)
    }

    func testFailedStorageCanRetryWithoutLosingActivity() async {
        let (service, reader, defaults) = fixture()
        defer { defaults.removePersistentDomain(forName: reader.suite) }
        let store = PetStore(snapshot: .newPlayer(seed: 42))
        let history = WorkoutHistoryStore(fileURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        reader.batch = EverydayActivityBatch(workouts: [summary()], steps: [])
        await service.setEnabled(true)
        await service.refresh(store: store, history: history, acceptWorkout: { _ in false })
        XCTAssertNil(service.lastSynced)
        XCTAssertEqual(store.snapshot.lifecycle?.creditedSeconds, 0)
        await service.refresh(store: store, history: history, acceptWorkout: { store.applyRun($0) })
        XCTAssertNotNil(service.lastSynced)
        XCTAssertEqual(store.snapshot.lifecycle?.creditedSeconds, 600)
    }

    func testDisablingDuringReadDiscardsInFlightResults() async {
        let (service, reader, defaults) = fixture()
        defer { defaults.removePersistentDomain(forName: reader.suite) }
        let store = PetStore(snapshot: .newPlayer(seed: 42))
        let history = WorkoutHistoryStore(fileURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        reader.batch = EverydayActivityBatch(workouts: [summary()], steps: [])
        reader.suspendRead = true
        await service.setEnabled(true)
        let task = Task { await service.refresh(store: store, history: history, acceptWorkout: { store.applyRun($0) }) }
        while reader.continuation == nil { await Task.yield() }
        await service.setEnabled(false)
        reader.continuation?.resume()
        await task.value
        XCTAssertEqual(store.snapshot.lifecycle?.creditedSeconds, 0)
        XCTAssertNil(service.lastSynced)
    }

    private func fixture() -> (EverydayActivityService, FakeReader, UserDefaults) {
        let reader = FakeReader()
        let defaults = UserDefaults(suiteName: reader.suite)!
        return (EverydayActivityService(defaults: defaults, reader: reader), reader, defaults)
    }

    private func summary() -> RunSummary {
        let end = Date()
        return RunSummary(id: UUID(), startedAt: end.addingTimeInterval(-600), endedAt: end,
                          distanceMeters: 0, elapsedSeconds: 600, averagePaceSecondsPerKilometer: 0,
                          averageHeartRate: nil, experienceEarned: 60, workoutConfiguration: WorkoutConfiguration(activity: .walking))
    }

    final class FakeReader: EverydayActivityReading {
        let suite = "pawpace.everyday.test.\(UUID())"
        var failAccess = false
        var readCount = 0
        var batch = EverydayActivityBatch(workouts: [], steps: [])
        var suspendRead = false
        var continuation: CheckedContinuation<Void, Never>?
        func requestAccess() async throws { if failAccess { throw EverydayActivityError.authorization } }
        func read(since: Date, until: Date) async throws -> EverydayActivityBatch {
            readCount += 1
            if suspendRead { await withCheckedContinuation { continuation = $0 } }
            return batch
        }
    }
}
