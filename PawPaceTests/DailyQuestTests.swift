import XCTest
@testable import PawPace

final class DailyQuestTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func pet(at date: Date) -> PetSnapshot {
        var pet = PetSnapshot.newPlayer(seed: 42); pet.quests.beganAt = date; return pet
    }

    func testCareOrMovementKeepsOneStreakAndOneGiftPerDay() throws {
        let first = date("2026-09-21T12:00:00Z"), second = date("2026-09-22T12:00:00Z")
        var pet = pet(at: first)
        pet.quests.checkIn(at: first, calendar: calendar)
        pet.quests.checkIn(at: first, calendar: calendar)
        _ = pet.journey.credit(workoutSeconds: 600, at: first, calendar: calendar)
        _ = pet.journey.credit(workoutSeconds: 300, at: second, calendar: calendar)
        pet.quests.prepareGifts(journey: pet.journey, at: second, calendar: calendar)
        pet.quests.prepareGifts(journey: pet.journey, at: second, calendar: calendar)
        XCTAssertEqual(pet.quests.gifts.count, 2)
        XCTAssertEqual(pet.quests.currentStreak(journey: pet.journey, at: second, calendar: calendar), 2)
        XCTAssertEqual(pet.quests.currentStreak(journey: pet.journey, at: date("2026-09-23T12:00:00Z"), calendar: calendar), 2)
        XCTAssertEqual(pet.quests.currentStreak(journey: pet.journey, at: date("2026-09-24T12:00:00Z"), calendar: calendar), 0)
        XCTAssertEqual(pet.quests.bestStreak(journey: pet.journey, at: second, calendar: calendar), 2)
        XCTAssertEqual(pet.lifecycle?.creditedSeconds, 0, "A hello awards no growth")
    }

    func testFiveMinuteThresholdAndNoInventedPreUpgradeRewards() {
        let today = date("2026-09-27T12:00:00Z")
        var pet = pet(at: today)
        _ = pet.journey.credit(workoutSeconds: 600, at: today.addingTimeInterval(-86_400), calendar: calendar)
        _ = pet.journey.credit(workoutSeconds: 299, at: today, calendar: calendar)
        pet.quests.prepareGifts(journey: pet.journey, at: today, calendar: calendar)
        XCTAssertTrue(pet.quests.gifts.isEmpty)
        _ = pet.journey.credit(workoutSeconds: 1, at: today, calendar: calendar)
        pet.quests.prepareGifts(journey: pet.journey, at: today, calendar: calendar)
        XCTAssertEqual(pet.quests.gifts.count, 1)
    }

    func testWeeklyGiftAndStreakUseActualChosenMovementTarget() {
        let monday = date("2026-09-14T12:00:00Z")
        var pet = pet(at: monday)
        pet.journey.chooseWeeklyTarget(2, at: monday, calendar: calendar)
        for offset in [0,1,7,8] {
            _ = pet.journey.credit(workoutSeconds: 300, at: monday.addingTimeInterval(Double(offset) * 86_400), calendar: calendar)
        }
        let end = monday.addingTimeInterval(9 * 86_400)
        pet.quests.prepareGifts(journey: pet.journey, at: end, calendar: calendar)
        XCTAssertEqual(pet.quests.gifts.filter { $0.kind == .weekly }.count, 2)
        let weeks = pet.quests.qualifyingWeeks(journey: pet.journey, at: end, calendar: calendar)
        XCTAssertEqual(DailyQuests.streak(weeks, endingAt: CompanionJourney.weekStart(end, calendar: calendar), step: 7, calendar: calendar), 2)
        pet.journey.chooseWeeklyTarget(5, at: end, calendar: calendar)
        pet.quests.prepareGifts(journey: pet.journey, at: end, calendar: calendar)
        XCTAssertEqual(pet.quests.gifts.filter { $0.kind == .weekly }.count, 2)
    }

    func testStreakUsesCalendarDaysAcrossDaylightSavingAndYearBoundary() {
        var calendar = self.calendar; calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = date("2026-03-07T17:00:00Z"), end = date("2026-03-09T16:00:00Z")
        var pet = pet(at: start)
        for day in [start, date("2026-03-08T16:00:00Z"), end] { pet.quests.checkIn(at: day, calendar: calendar) }
        XCTAssertEqual(pet.quests.currentStreak(journey: pet.journey, at: end, calendar: calendar), 3)
        pet.quests.checkIn(at: date("2026-12-31T17:00:00Z"), calendar: calendar)
        pet.quests.checkIn(at: date("2027-01-01T17:00:00Z"), calendar: calendar)
        XCTAssertEqual(pet.quests.currentStreak(journey: pet.journey, at: date("2027-01-01T17:00:00Z"), calendar: calendar), 2)
        XCTAssertEqual(pet.quests.bestStreak(journey: pet.journey, at: date("2027-01-01T17:00:00Z"), calendar: calendar), 3)
    }

    func testGiftRewardPersistsAndCannotRerollOrAwardTwice() throws {
        let today = Date()
        var pet = pet(at: today)
        pet.quests.checkIn(at: today)
        pet.quests.prepareGifts(journey: pet.journey, at: today)
        let id = try XCTUnwrap(pet.quests.gifts.first?.id)
        let result = try XCTUnwrap(pet.openQuestGift(id, at: today, roll: 99, selection: 0))
        XCTAssertNotNil(result.decoration)
        XCTAssertEqual(pet.availableDecorations.count, 1)
        var restored = try JSONDecoder().decode(PetSnapshot.self, from: JSONEncoder().encode(pet))
        XCTAssertEqual(restored.openQuestGift(id, roll: 0, selection: 42), result)
        XCTAssertTrue(restored.journey.waitingEggs.isEmpty)
        XCTAssertEqual(restored.availableDecorations.count, 1)
        XCTAssertNil(restored.openQuestGift("unearned", roll: 0))
    }

    func testMysteryEggIsBankedWithoutReplacingYoungBuddyAndAllOwnedDecorationsFallBackToEgg() throws {
        let today = Date()
        var pet = pet(at: today)
        pet.quests.checkIn(at: today)
        pet.quests.prepareGifts(journey: pet.journey, at: today)
        let original = pet.companionID, id = try XCTUnwrap(pet.quests.gifts.first?.id)
        pet.journey.unlockedDecorations = Set(HabitatDecoration.allCases.map(\.rawValue))
        let result = try XCTUnwrap(pet.openQuestGift(id, roll: 99, selection: 123))
        XCTAssertTrue(result.isEgg)
        XCTAssertEqual(result.title, "A mystery egg")
        XCTAssertEqual(pet.journey.waitingEggs.map(\.seed), [123])
        pet.beginNextEgg()
        XCTAssertEqual(pet.companionID, original)
        XCTAssertEqual(pet.journey.waitingEggs.count, 1)
    }

    func testOldSnapshotDecodesWithoutFictionalCheckInsAndQuestsSurviveCompanionChange() throws {
        var pet = PetSnapshot.starter
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pet)) as? [String: Any])
        json.removeValue(forKey: "quests")
        let restored = try JSONDecoder().decode(PetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(restored.quests.checkIns.isEmpty)
        XCTAssertTrue(restored.quests.gifts.isEmpty)
        pet.quests.checkIn(at: .now)
        let before = pet.quests
        pet.journey.waitingEggs.append(PetLifecycle(seed: 12))
        pet.beginNextEgg()
        XCTAssertEqual(pet.quests, before)
    }

    func testRewardThresholdsAndNoDuplicateDecorations() throws {
        var pet = PetSnapshot.starter
        for index in 0..<HabitatDecoration.allCases.count {
            let id = "daily-test-\(index)"
            pet.quests.gifts.append(QuestGift(id: id, kind: .daily, earnedAt: .now))
            let reward = try XCTUnwrap(pet.openQuestGift(id, roll: 15, selection: 0))
            XCTAssertNotNil(reward.decoration)
        }
        XCTAssertEqual(pet.availableDecorations.count, HabitatDecoration.allCases.count)
        var eggPet = PetSnapshot.starter
        eggPet.quests.gifts = [QuestGift(id: "daily", kind: .daily, earnedAt: .now), QuestGift(id: "weekly", kind: .weekly, earnedAt: .now)]
        XCTAssertTrue(try XCTUnwrap(eggPet.openQuestGift("daily", roll: 14, selection: 7)).isEgg)
        XCTAssertTrue(try XCTUnwrap(eggPet.openQuestGift("weekly", roll: 34, selection: 8)).isEgg)
        XCTAssertEqual(eggPet.journey.waitingEggs.count, 2)
    }
}
