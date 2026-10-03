import XCTest
@testable import PawPace

final class CompanionJourneyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
    }
    private func workout(_ pet: inout PetSnapshot, minutes: Int, day: Int, id: UUID = UUID()) {
        pet.applyRun(distanceKilometers: 0, experienceEarned: minutes * 10, elapsedSeconds: minutes * 60,
                     activity: .walking, workoutID: id, at: self.day(day), calendar: calendar)
    }

    func testAdultEarnsPersistentEggAndKeepsExactResident() throws {
        var pet = PetSnapshot.starter
        for date in 21...23 { workout(&pet, minutes: 60, day: date) }
        XCTAssertEqual(pet.journey.waitingEggs.count, 1)
        XCTAssertEqual(pet.journey.eggProgressSeconds, 0)
        let original = CompanionResident(pet)
        let earnedEgg = pet.journey.waitingEggs[0]
        let coins = pet.coins
        let rewards = pet.rewardedWorkoutIDs
        pet = try roundTrip(pet)
        pet.beginNextEgg(at: day(24))
        XCTAssertEqual(pet.lifecycle, earnedEgg, "Opening an earned egg must not reroll it")
        XCTAssertEqual(pet.journey.residents, [original])
        XCTAssertEqual(pet.coins, coins)
        XCTAssertEqual(pet.rewardedWorkoutIDs, rewards)
        let eggID = pet.companionID
        pet.visitCompanion(original.id)
        XCTAssertEqual(CompanionResident(pet), original)
        pet.visitCompanion(eggID)
        XCTAssertEqual(pet.lifecycle, earnedEgg)
        XCTAssertEqual(try roundTrip(pet), pet)
    }

    func testRepeatedDiscoveriesNeverReplaceOlderFriends() {
        var pet = PetSnapshot.starter
        for date in 1...6 { workout(&pet, minutes: 60, day: date) }
        XCTAssertEqual(pet.journey.waitingEggs.count, 2)
        pet.beginNextEgg()
        let firstEggID = pet.companionID
        pet.beginNextEgg()
        XCTAssertEqual(pet.companionID, firstEggID, "Only one young companion at a time")
        for date in 7...10 { workout(&pet, minutes: 60, day: date) }
        XCTAssertEqual(pet.lifeStage, .adult)
        pet.beginNextEgg()
        XCTAssertEqual(pet.journey.residents.count, 2)
        XCTAssertNotEqual(pet.companionID, firstEggID)
    }

    func testSwitchingToEggCannotResetFamilyDailyCap() {
        var pet = PetSnapshot.starter
        pet.journey.waitingEggs = [PetLifecycle(seed: 42)]
        workout(&pet, minutes: 60, day: 21)
        pet.beginNextEgg()
        workout(&pet, minutes: 60, day: 21)
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 0)
        workout(&pet, minutes: 30, day: 22)
        XCTAssertEqual(pet.lifeStage, .baby)
    }

    func testMaturitySpillsOnlyRemainingCreditIntoAdultAdventures() {
        var pet = PetSnapshot.newPlayer(seed: 42)
        for date in 21...24 { workout(&pet, minutes: 60, day: date) }
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 12_600)
        XCTAssertEqual(pet.companionAdultSeconds, 1_800)
        XCTAssertEqual(pet.journey.eggProgressSeconds, 1_800)
        XCTAssertEqual(pet.lifecycle?.geneSeconds(for: .endurance), 12_600)
    }

    func testExpeditionCompletesOnceAndKeepsDecorationsAndMemories() throws {
        var pet = PetSnapshot.starter
        pet.journey.activeTrail = .meadow
        let id = UUID()
        workout(&pet, minutes: 60, day: 21, id: id)
        XCTAssertNil(pet.journey.activeTrail)
        XCTAssertTrue(pet.journey.unlockedDecorations.contains("Trail Flags"))
        XCTAssertEqual(pet.journey.memories.count, 1)
        pet = try roundTrip(pet)
        workout(&pet, minutes: 60, day: 22, id: id)
        XCTAssertEqual(pet.journey.memories.count, 1)
        XCTAssertEqual(pet.companionAdultSeconds, 3_600)
    }

    func testStepsAndWorkoutsUseHigherTotalInEitherOrder() throws {
        for stepsFirst in [true, false] {
            var pet = PetSnapshot.newPlayer(seed: 42)
            if stepsFirst { pet.applyDailySteps(3_000, at: day(21), calendar: calendar) }
            workout(&pet, minutes: 20, day: 21)
            if !stepsFirst { pet.applyDailySteps(3_000, at: day(21), calendar: calendar) }
            XCTAssertEqual(pet.lifecycle?.creditedSeconds, 1_800)
            pet = try roundTrip(pet)
            pet.applyDailySteps(3_000, at: day(21), calendar: calendar)
            XCTAssertEqual(pet.lifecycle?.creditedSeconds, 1_800)
            workout(&pet, minutes: 20, day: 21)
            XCTAssertEqual(pet.lifecycle?.creditedSeconds, 2_400)
            pet.applyDailySteps(10_000, at: day(21), calendar: calendar)
            XCTAssertEqual(pet.lifecycle?.creditedSeconds, 3_600)
        }
    }

    func testStepsNeverLoseProgressWhenDataDecreasesOrArrivesLate() {
        var pet = PetSnapshot.newPlayer(seed: 42)
        pet.applyDailySteps(6_000, at: day(21), calendar: calendar)
        pet.applyDailySteps(2_000, at: day(22), calendar: calendar)
        pet.applyDailySteps(1_000, at: day(21), calendar: calendar)
        pet.applyDailySteps(50_000, at: day(21), calendar: calendar)
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 4_800)
        let before = pet
        pet.applyDailySteps(.nan, at: day(23), calendar: calendar)
        pet.applyDailySteps(-500, at: day(23), calendar: calendar)
        XCTAssertEqual(pet, before)
    }

    func testReenablingStepsCountsNewWindowWithoutReplayingOldWindow() throws {
        var pet = PetSnapshot.newPlayer(seed: 42)
        pet.applyDailySteps(500, at: day(21), calendar: calendar, epoch: "first-enable")
        pet = try roundTrip(pet)
        pet.applyDailySteps(500, at: day(21), calendar: calendar, epoch: "second-enable")
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 600)
        pet.applyDailySteps(500, at: day(21), calendar: calendar, epoch: "second-enable")
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 600)
        pet.applyDailySteps(1_000, at: day(21), calendar: calendar, epoch: "second-enable")
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 900)
    }

    @MainActor
    func testDelayedMovementPublishesANewerSnapshotForWatch() {
        let store = PetStore(snapshot: .starter)
        let original = store.snapshot
        XCTAssertTrue(store.applyDailySteps([(date: Date().addingTimeInterval(-86_400), steps: 500)]))
        XCTAssertGreaterThan(store.snapshot.lastUpdated, original.lastUpdated)
        XCTAssertTrue(PawPaceSyncPolicy.shouldAcceptPet(store.snapshot, current: original, hasAuthoritativePet: true))
    }

    func testMigrationPreservesExistingDayCreditWithoutLosingNextWorkout() {
        var pet = PetSnapshot.newPlayer(seed: 42)
        pet.lifecycle?.creditWorkout(activity: .yoga, activeSeconds: 1_800, at: day(21), calendar: calendar)
        workout(&pet, minutes: 10, day: 21)
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 2_400)
        pet.applyDailySteps(4_000, at: day(21), calendar: calendar)
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 2_400)
    }

    func testCopiedAndOverlappingWorkoutsDoNotDuplicateGrowthXPOrCoins() throws {
        var pet = PetSnapshot.newPlayer(seed: 42)
        let end = day(21)
        func apply(start: Date, end: Date, to pet: inout PetSnapshot) {
            pet.applyRun(distanceKilometers: 1, experienceEarned: 100, elapsedSeconds: Int(end.timeIntervalSince(start)),
                         workoutID: UUID(), at: end, calendar: calendar, activeIntervals: [DateInterval(start: start, end: end)])
        }
        apply(start: end.addingTimeInterval(-600), end: end, to: &pet)
        let xp = pet.experience
        let coins = pet.coins
        pet = try roundTrip(pet)
        apply(start: end.addingTimeInterval(-600), end: end, to: &pet)
        XCTAssertEqual(pet.experience, xp)
        XCTAssertEqual(pet.coins, coins)
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 600)
        apply(start: end.addingTimeInterval(-300), end: end.addingTimeInterval(300), to: &pet)
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 900)
        XCTAssertEqual(pet.experience, xp + 50)
    }

    func testIntervalUnionRespectsPausesAndDisjointWorkouts() {
        var journey = CompanionJourney()
        let start = day(21)
        XCTAssertEqual(journey.consumeWorkoutIntervals([
            DateInterval(start: start, duration: 60), DateInterval(start: start.addingTimeInterval(120), duration: 60)
        ]), 120)
        XCTAssertEqual(journey.consumeWorkoutIntervals([DateInterval(start: start, duration: 180)]), 60)
        XCTAssertEqual(journey.workoutIntervals.count, 1)
    }

    func testWeeklyGoalsNeedFiveMinutesAndAllowRestDays() throws {
        var pet = PetSnapshot.newPlayer(seed: 42)
        workout(&pet, minutes: 4, day: 21)
        XCTAssertEqual(pet.journey.activeDays(inWeekOf: day(21), calendar: calendar), 0)
        workout(&pet, minutes: 1, day: 21)
        workout(&pet, minutes: 5, day: 23)
        workout(&pet, minutes: 5, day: 26)
        XCTAssertEqual(pet.journey.activeDays(inWeekOf: day(26), calendar: calendar), 3)
        XCTAssertEqual(pet.journey.weeklyKeepsakes, 1)
        pet = try roundTrip(pet)
        workout(&pet, minutes: 5, day: 27)
        XCTAssertEqual(pet.journey.weeklyKeepsakes, 1)
        XCTAssertEqual(pet.journey.activeDays(inWeekOf: day(28), calendar: calendar), 0)
        XCTAssertEqual(pet.journey.weeklyKeepsakes, 1)
    }

    func testChangingWeeklyTargetAppliesNextWeekAfterProgressStarts() {
        var pet = PetSnapshot.newPlayer(seed: 42)
        pet.journey.chooseWeeklyTarget(2, at: day(21), calendar: calendar)
        workout(&pet, minutes: 5, day: 21)
        pet.journey.chooseWeeklyTarget(5, at: day(22), calendar: calendar)
        XCTAssertEqual(pet.journey.target(inWeekOf: day(22), calendar: calendar), 2)
        XCTAssertEqual(pet.journey.target(inWeekOf: day(28), calendar: calendar), 5)
    }

    func testOldSnapshotsDecodeWithoutJourneyAndDoNotInventProgress() throws {
        let pet = PetSnapshot.starter
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pet)) as? [String: Any])
        for key in ["journey", "companionID", "companionAdultSeconds"] { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(PetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.journey, CompanionJourney())
        XCTAssertEqual(decoded.name, pet.name)
        XCTAssertEqual(decoded.coins, pet.coins)
        XCTAssertEqual(decoded.lifeStage, .adult)
        XCTAssertEqual(try roundTrip(decoded), decoded)
    }

    func testShareContentConcealsEggAndSpeciesUntilExplicitReveal() {
        var pet = PetSnapshot.newPlayer(seed: 0)
        let egg = CompanionShareContent(pet: pet, revealsCompanion: true)
        XCTAssertTrue(egg.concealsCompanion)
        workout(&pet, minutes: 30, day: 21)
        let hidden = CompanionShareContent(pet: pet, revealsCompanion: false)
        XCTAssertFalse(hidden.companionCaption.contains(pet.species.displayName))
        XCTAssertFalse(hidden.companionCaption.contains(pet.name))
        let revealed = CompanionShareContent(pet: pet, revealsCompanion: true)
        XCTAssertFalse(revealed.concealsCompanion)
        XCTAssertTrue(revealed.companionCaption.contains(pet.species.displayName))
    }

    private func roundTrip(_ pet: PetSnapshot) throws -> PetSnapshot {
        try JSONDecoder().decode(PetSnapshot.self, from: JSONEncoder().encode(pet))
    }
}
