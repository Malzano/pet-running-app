import XCTest
import simd
@testable import PawPace

final class BuddyPlayTests: XCTestCase {
    func testFetchNeedsThreeHitsAndIgnoresInputBetweenRounds() {
        var game = BuddyPlaySession(game: .fetch, companionID: UUID())
        XCTAssertEqual(game.throwBall(x: .nan, y: 0.5), .ignored)
        XCTAssertEqual(game.throwBall(x: 0.0, y: 1.0), .tryAgain)
        XCTAssertEqual(game.round, 0)
        for round in 0..<3 {
            let target = game.target
            XCTAssertEqual(game.throwBall(x: target.x, y: target.y), .found)
            XCTAssertEqual(game.round, round + 1)
            XCTAssertEqual(game.target.x, target.x)
            XCTAssertEqual(game.throwBall(x: target.x, y: target.y), .ignored)
            if round < 2 { XCTAssertEqual(game.phase, .celebrating); game.continuePlaying() }
        }
        XCTAssertEqual(game.phase, .finished)
        game.continuePlaying()
        XCTAssertEqual(game.phase, .finished)
    }

    func testHideAndSeekRehearsalWrongSpotsAndRepeatedTaps() {
        var game = BuddyPlaySession(game: .hideAndSeek, companionID: UUID())
        XCTAssertEqual(game.search(game.hidingSpot), .ignored)
        game.ready()
        let wrong = (game.hidingSpot + 1) % 4
        XCTAssertEqual(game.search(wrong), .tryAgain)
        XCTAssertEqual(game.search(wrong), .ignored)
        XCTAssertEqual(game.search(-1), .ignored)
        game.lookAgain()
        XCTAssertTrue(game.checkedSpots.isEmpty)
        XCTAssertEqual(game.phase, .memorizing)
        game.ready()
        let spot = game.hidingSpot
        XCTAssertEqual(game.search(spot), .found)
        XCTAssertEqual(game.hidingSpot, spot, "The found portrait must remain in the successful hiding place")
        game.continuePlaying()
        XCTAssertEqual(game.phase, .memorizing)
        XCTAssertNotEqual(game.hidingSpot, spot)
    }

    func testTrickSequenceMistakeResetsAndPracticeDoesNotAwardEarly() {
        var game = BuddyPlaySession(game: .trickTrail, companionID: UUID())
        XCTAssertEqual(game.perform(game.sequence[0]), .ignored)
        game.ready()
        XCTAssertEqual(game.perform(game.sequence[0]), .progress)
        XCTAssertEqual(game.sequenceIndex, 1)
        let wrong = BuddyTrick.allCases.first { $0 != game.sequence[1] }!
        XCTAssertEqual(game.perform(wrong), .tryAgain)
        XCTAssertEqual(game.sequenceIndex, 0)
        XCTAssertEqual(game.round, 0)
        for trick in game.sequence { _ = game.perform(trick) }
        XCTAssertEqual(game.phase, .celebrating)
        XCTAssertEqual(game.round, 1)
    }

    func testThreeGamesFinishWithUnlimitedRetriesAndNoDeadlines() {
        for type in BuddyGame.allCases {
            let game = Self.finishedGame(type, id: UUID())
            XCTAssertEqual(game.phase, .finished)
            XCTAssertEqual(game.round, 3)
            XCTAssertGreaterThanOrEqual(game.attempts, 3)
        }
    }

    func testEggUnfinishedAndOtherCompanionCannotReceiveGameReward() {
        var egg = PetSnapshot.newPlayer()
        XCTAssertFalse(egg.completeBuddyGame(Self.finishedGame(.fetch, id: egg.companionID)))
        XCTAssertTrue(egg.buddyBond.completedSessions.isEmpty)
        var pet = PetSnapshot.starter
        XCTAssertFalse(pet.completeBuddyGame(BuddyPlaySession(game: .fetch, companionID: pet.companionID)))
        XCTAssertFalse(pet.completeBuddyGame(Self.finishedGame(.fetch, id: UUID())))
        XCTAssertTrue(pet.buddyBond.completedSessions.isEmpty)
    }

    func testCompletedGameOnlyRewardsFriendshipOnceAndPreservesGrowth() throws {
        var pet = PetSnapshot.newPlayer(seed: 77)
        pet.applyMovementGrowth(seconds: 1_800, activity: .walking, at: .now)
        XCTAssertEqual(pet.lifeStage, .baby)
        let before = pet
        let game = Self.finishedGame(.trickTrail, id: pet.companionID)
        XCTAssertTrue(pet.completeBuddyGame(game))
        XCTAssertEqual(pet.friendship, min(100, before.friendship + 3))
        XCTAssertEqual(pet.buddyBond.learnedSequences, 1)
        XCTAssertEqual(pet.buddyBond.learnedRoutine, game.sequence)
        XCTAssertEqual(pet.buddyBond.favoriteGame(for: pet.companionID), .trickTrail)
        XCTAssertEqual(pet.lifecycle, before.lifecycle)
        XCTAssertEqual(pet.journey, before.journey)
        XCTAssertEqual(pet.experience, before.experience)
        XCTAssertEqual(pet.coins, before.coins)
        let restored = try JSONDecoder().decode(PetSnapshot.self, from: JSONEncoder().encode(pet))
        pet = restored
        XCTAssertEqual(pet.buddyBond.learnedRoutine, game.sequence)
        XCTAssertFalse(pet.completeBuddyGame(game))
        XCTAssertEqual(pet.friendship, restored.friendship)
        XCTAssertEqual(pet.buddyBond.learnedSequences, 1)
        XCTAssertEqual(pet.buddyBond.firstGameDates.count, 1)
    }

    func testPreferencesStayWithResidentAndNewEggStartsFresh() throws {
        var pet = PetSnapshot.starter
        let originalID = pet.companionID
        let game = Self.finishedGame(.hideAndSeek, id: originalID)
        XCTAssertTrue(pet.completeBuddyGame(game))
        let bond = pet.buddyBond
        pet.journey.waitingEggs = [PetLifecycle(seed: 3)]
        pet.beginNextEgg()
        XCTAssertEqual(pet.buddyBond, BuddyBond())
        XCTAssertNotEqual(pet.companionID, originalID)
        pet = try JSONDecoder().decode(PetSnapshot.self, from: JSONEncoder().encode(pet))
        pet.visitCompanion(originalID)
        XCTAssertEqual(pet.buddyBond, bond)
        XCTAssertFalse(pet.completeBuddyGame(game))
    }

    func testOldSnapshotAndResidentsDecodeWithoutInventingGameHistory() throws {
        var pet = PetSnapshot.starter
        pet.journey.residents = [CompanionResident(PetSnapshot.starter)]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pet)) as? [String: Any])
        json.removeValue(forKey: "buddyBond")
        var journey = try XCTUnwrap(json["journey"] as? [String: Any])
        var residents = try XCTUnwrap(journey["residents"] as? [[String: Any]])
        residents[0].removeValue(forKey: "buddyBond")
        journey["residents"] = residents; json["journey"] = journey
        let restored = try JSONDecoder().decode(PetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.buddyBond, BuddyBond())
        XCTAssertNil(restored.journey.residents.first?.buddyBond)
    }

    func testSameSpeciesCanDifferAndPersonalityAdaptsWithoutTapFarming() {
        let ids = (0..<30).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        let bond = BuddyBond()
        XCTAssertGreaterThan(Set(ids.map { bond.temperament(for: $0) }).count, 1)
        var evolving = bond
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0..<100 { evolving.interact(.calm, at: date) }
        XCTAssertEqual(evolving.calmness, 1)
        for offset in 1...20 { evolving.interact(.calm, at: date.addingTimeInterval(Double(offset * 60))) }
        XCTAssertEqual(evolving.temperament(for: ids[0]), .calm)
        XCTAssertEqual(BuddyBond.seed(for: ids[0]), BuddyBond.seed(for: ids[0]))
    }

    func testTemperamentChangesActualRoamingButKeepsMovementBounded() {
        for species in PetSpecies.allCases {
            var calm = CompanionRoaming(species: species, seed: 99)
            var playful = calm
            calm.temperament = .calm; playful.temperament = .playful
            for _ in 0..<3_600 {
                let calmPose = calm.step(deltaTime: 1 / 60)
                let playfulPose = playful.step(deltaTime: 1 / 60)
                for pose in [calmPose, playfulPose] {
                    XCTAssertLessThanOrEqual(simd_length(pose.position / CompanionRoaming.fieldRadii), 1.001)
                    XCTAssertTrue(pose.speed.isFinite)
                }
            }
            XCTAssertGreaterThan(playful.pose.gaitDistance, calm.pose.gaitDistance)
            XCTAssertGreaterThan(simd_distance(playful.pose.position, calm.pose.position), 0.001)
        }
    }

    @MainActor
    func testStoreCannotSaveGameToNewlyVisitedCompanion() {
        var pet = PetSnapshot.starter
        let original = pet.companionID
        let game = Self.finishedGame(.fetch, id: original)
        var other = pet; other.companionID = UUID(); other.name = "Pip"
        pet.journey.residents = [CompanionResident(other)]
        let store = PetStore(snapshot: pet)
        store.visitCompanion(other.companionID)
        XCTAssertFalse(store.completeBuddyGame(game))
        XCTAssertTrue(store.snapshot.buddyBond.completedSessions.isEmpty)
        store.visitCompanion(original)
        XCTAssertTrue(store.completeBuddyGame(game))
        XCTAssertTrue(store.completeBuddyGame(game), "A save retry is successful without a second reward")
        XCTAssertEqual(store.snapshot.buddyBond.favoriteGameCounts[BuddyGame.fetch.rawValue], 1)
    }

    static func finishedGame(_ type: BuddyGame, id: UUID) -> BuddyPlaySession {
        var game = BuddyPlaySession(game: type, companionID: id)
        for _ in 0..<3 {
            game.ready()
            switch type {
            case .fetch: _ = game.throwBall(x: game.target.x, y: game.target.y)
            case .hideAndSeek: _ = game.search(game.hidingSpot)
            case .trickTrail: for trick in game.sequence { _ = game.perform(trick) }
            }
            game.continuePlaying()
        }
        return game
    }
}
