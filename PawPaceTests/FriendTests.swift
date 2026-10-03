import XCTest
@testable import PawPace

@MainActor final class FriendTests: XCTestCase {
    func testSharingIsAnExplicitReducedPayloadWithoutSensitiveMetrics() throws {
        var summary = RunSummary(id: UUID(), startedAt: .now.addingTimeInterval(-600), endedAt: .now, distanceMeters: 1450,
            elapsedSeconds: 600, averagePaceSecondsPerKilometer: 420, averageHeartRate: 145, experienceEarned: 60)
        summary.activeEnergyKilocalories = 400
        let withoutDistance = ClubCommand.share(summary, includeDistance: false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: ClubJSON.encoder().encode(withoutDistance)) as? [String: Any])
        let payload = try XCTUnwrap(json["data"] as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["earnedAt", "activity", "workoutID", "elapsedSeconds"])
        XCTAssertEqual(withoutDistance.data.workoutID, summary.id.uuidString)
        XCTAssertEqual(ClubCommand.share(summary, includeDistance: true).data.distanceMeters, 1450)
        summary.workoutConfiguration = WorkoutConfiguration(activity: .yoga)
        XCTAssertNil(ClubCommand.share(summary, includeDistance: true).data.distanceMeters)
    }

    func testOlderClubCachesDecodeAndInvalidSocialPayloadIsRejected() throws {
        let old = try ClubJSON.decoder().decode(ClubSnapshot.self, from: ClubJSON.encoder().encode(ClubFixtures.snapshot))
        XCTAssertNil(old.social)
        var fresh = old
        fresh.social = FriendSnapshot(friendCode: "ABCDEF1234567890", connections: [], posts: [], blocks: [])
        XCTAssertTrue(fresh.isValid)
        fresh.social?.friendCode = "bad"
        XCTAssertFalse(fresh.isValid)
    }

    func testFriendPostOutboxSurvivesRelaunchWithSameCommandIdentity() async throws {
        let storage = PawPacePrivateStorage(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: storage.directoryURL) }
        let api = ClubTestAPI(), credentials = ClubTestCredentials()
        api.sendError = ClubAPIError(status: 0, message: "offline")
        let store = ClubStore(identity: ClubTestIdentity(), api: api, credentials: credentials, storage: storage)
        let summary = RunSummary(id: UUID(), startedAt: .now.addingTimeInterval(-600), endedAt: .now, distanceMeters: 1000,
            elapsedSeconds: 600, averagePaceSecondsPerKilometer: 600, averageHeartRate: nil, experienceEarned: 60)
        let command = ClubCommand.share(summary, includeDistance: false)
        XCTAssertTrue(store.enqueue(command)); await store.refresh()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(store.isWorkoutSharedOrQueued(summary.id))
        let restored = ClubStore(identity: ClubTestIdentity(), api: api, credentials: credentials, storage: storage)
        XCTAssertEqual(restored.pending.map(\.command), [command])
        api.sendError = nil
        await restored.refresh()
        XCTAssertTrue(restored.pending.isEmpty)
        XCTAssertTrue(api.sent.allSatisfy { $0.id == command.id })
        XCTAssertNil(command.data.distanceMeters)
    }
}
