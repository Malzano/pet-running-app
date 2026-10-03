import XCTest
@testable import PawPace

final class DeferredWatchCompletionTests: XCTestCase {
    @MainActor
    func testResolvingAliasIsReadOnlyAndReplayableAfterRelaunch() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let summary = makeSummary()
        let state = makeTerminal(for: summary, phase: .finished)
        try fixture.storage.save([PendingRecord(summary: summary, requiresPhoneSave: false)], named: pendingFilename)
        let file = fixture.storage.directoryURL.appendingPathComponent(pendingFilename)
        let original = try Data(contentsOf: file)
        let tracker = fixture.makeTracker()

        assertFinished(tracker.resolveDeferredWatchTerminal(state), summary: summary, alias: state.workoutID)
        assertFinished(tracker.resolveDeferredWatchTerminal(state), summary: summary, alias: state.workoutID)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertNil(fixture.defaults.stringArray(forKey: handledKey))
        assertFinished(fixture.makeTracker().resolveDeferredWatchTerminal(state), summary: summary, alias: state.workoutID)

        XCTAssertTrue(tracker.acknowledgeDeferredWatchTerminal(state, summaryID: summary.id))
        XCTAssertEqual(try fixture.storage.load([PendingRecord].self, named: pendingFilename), [])
        XCTAssertEqual(fixture.defaults.stringArray(forKey: handledKey), [try XCTUnwrap(state.workoutID).uuidString])
        XCTAssertNil(fixture.makeTracker().resolveDeferredWatchTerminal(state))
    }

    @MainActor
    func testFailedWatchTerminalOnlyEnablesHealthFallbackAfterAcknowledgement() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let summary = makeSummary()
        let state = makeTerminal(for: summary, phase: .failed)
        try fixture.storage.save([PendingRecord(summary: summary, requiresPhoneSave: false)], named: pendingFilename)
        let tracker = fixture.makeTracker()
        guard case let .failed(resolved, alias)? = tracker.resolveDeferredWatchTerminal(state) else {
            return XCTFail("Expected the original canonical summary for a failed Watch alias")
        }
        XCTAssertEqual(resolved, summary)
        XCTAssertEqual(alias, state.workoutID)
        XCTAssertTrue(tracker.pendingFailedWatchSummaries().isEmpty)
        XCTAssertNil(fixture.defaults.stringArray(forKey: handledKey))

        XCTAssertTrue(tracker.acknowledgeDeferredWatchTerminal(state, summaryID: summary.id))
        XCTAssertEqual(fixture.makeTracker().pendingFailedWatchSummaries(), [summary])
        XCTAssertTrue(tracker.acknowledgeDeferredWatchTerminal(state, summaryID: summary.id))
        XCTAssertEqual(fixture.defaults.stringArray(forKey: handledKey)?.count, 1)
    }

    @MainActor
    func testFailedAcknowledgementPreservesReplayUntilStorageIsReadableAgain() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let summary = makeSummary()
        let state = makeTerminal(for: summary, phase: .finished)
        try fixture.storage.save([PendingRecord(summary: summary, requiresPhoneSave: false)], named: pendingFilename)
        let tracker = fixture.makeTracker()
        assertFinished(tracker.resolveDeferredWatchTerminal(state), summary: summary, alias: state.workoutID)
        let file = fixture.storage.directoryURL.appendingPathComponent(pendingFilename)
        let original = try Data(contentsOf: file)
        let temporarilyUnreadable = Data("unreadable pending completion".utf8)
        try temporarilyUnreadable.write(to: file)

        XCTAssertFalse(tracker.acknowledgeDeferredWatchTerminal(state, summaryID: summary.id))
        XCTAssertNil(fixture.defaults.stringArray(forKey: handledKey))
        XCTAssertEqual(try Data(contentsOf: file), temporarilyUnreadable)
        XCTAssertNotNil(tracker.recoveryStorageMessage)

        try original.write(to: file)
        assertFinished(tracker.resolveDeferredWatchTerminal(state), summary: summary, alias: state.workoutID)
        XCTAssertTrue(tracker.acknowledgeDeferredWatchTerminal(state, summaryID: summary.id))
    }

    @MainActor
    func testAcknowledgementIsIdempotentAndKeepsUnrelatedPendingWorkout() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let completed = makeSummary()
        let other = makeSummary(start: completed.startedAt.addingTimeInterval(3_600))
        let state = makeTerminal(for: completed, phase: .finished)
        try fixture.storage.save([
            PendingRecord(summary: completed, requiresPhoneSave: false),
            PendingRecord(summary: other, requiresPhoneSave: true)
        ], named: pendingFilename)
        let tracker = fixture.makeTracker()
        XCTAssertTrue(tracker.acknowledgeDeferredWatchTerminal(state, summaryID: completed.id))
        XCTAssertTrue(tracker.acknowledgeDeferredWatchTerminal(state, summaryID: completed.id))
        XCTAssertEqual(tracker.pendingFailedWatchSummaries(), [other])
        XCTAssertEqual(fixture.defaults.stringArray(forKey: handledKey)?.count, 1)
    }

    @MainActor
    func testStandaloneFailedWatchSaveReportsDurabilityAndPreservesUnreadableQueue() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let summary = makeSummary()
        let tracker = fixture.makeTracker()
        XCTAssertTrue(tracker.queueFailedWatchHealthFallback(summary))
        XCTAssertEqual(fixture.makeTracker().pendingFailedWatchSummaries(), [summary])
        let file = fixture.storage.directoryURL.appendingPathComponent(pendingFilename)
        let unreadable = Data("unreadable pending Health queue".utf8)
        try unreadable.write(to: file)
        XCTAssertFalse(tracker.queueFailedWatchHealthFallback(makeSummary()))
        XCTAssertEqual(try Data(contentsOf: file), unreadable)
    }

    private let pendingFilename = "phone-pending-health-saves-v1.json"
    private let handledKey = "pawpace.handledWatchTerminals.v1"

    private struct PendingRecord: Codable, Equatable {
        let summary: RunSummary
        let requiresPhoneSave: Bool
    }

    private struct Fixture {
        let storage: PawPacePrivateStorage
        let defaults: UserDefaults
        let suite: String

        @MainActor
        func makeTracker() -> RunTracker {
            RunTracker(healthKit: HealthKitService(), petSnapshot: { .starter },
                       watchConnectivity: PhoneWatchConnectivityService(),
                       privateStorage: storage, legacyDefaults: defaults)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: storage.directoryURL)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeFixture() throws -> Fixture {
        let identifier = UUID().uuidString
        let suite = "pawpace-deferred-test-\(identifier)"
        return Fixture(storage: PawPacePrivateStorage(directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)),
            defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    private func makeSummary(start: Date = Date().addingTimeInterval(-1_800)) -> RunSummary {
        RunSummary(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(300),
                   distanceMeters: 0, elapsedSeconds: 300, averagePaceSecondsPerKilometer: 0,
                   averageHeartRate: nil, experienceEarned: 30,
                   workoutConfiguration: WorkoutConfiguration(activity: .yoga))
    }

    private func makeTerminal(for summary: RunSummary, phase: PawPaceRunPhase) -> PawPaceRunState {
        var state = PawPaceRunState.idle
        state.workoutID = UUID()
        state.phase = phase
        state.startedAt = summary.startedAt.addingTimeInterval(2)
        state.endedAt = summary.endedAt
        state.updatedAt = summary.endedAt
        state.elapsedSeconds = summary.elapsedSeconds
        state.workoutConfiguration = summary.workoutConfiguration
        return state
    }

    @MainActor
    private func assertFinished(_ resolution: RunTracker.DeferredWatchTerminalResolution?,
                                summary: RunSummary, alias: UUID?,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard case let .finished(resolved, remoteID)? = resolution else {
            return XCTFail("Expected an unchanged canonical summary and remote alias", file: file, line: line)
        }
        XCTAssertEqual(resolved, summary, file: file, line: line)
        XCTAssertEqual(remoteID, alias, file: file, line: line)
    }
}
