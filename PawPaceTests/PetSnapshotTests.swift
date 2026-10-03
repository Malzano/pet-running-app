import XCTest
@testable import PawPace

final class PetSnapshotTests: XCTestCase {
    func testFeedingCapsEnergyAndIncreasesFriendship() {
        var pet = PetSnapshot.starter
        pet.energy = 95
        pet.friendship = 50

        pet.feed()

        XCTAssertEqual(pet.energy, 100)
        XCTAssertEqual(pet.friendship, 52)
        XCTAssertEqual(pet.mood, .happy)
    }

    func testExperienceCarriesIntoNextLevel() {
        var pet = PetSnapshot.starter
        pet.experience = 2_350
        pet.experienceGoal = 2_400

        pet.awardExperience(100)

        XCTAssertEqual(pet.level, 10)
        XCTAssertEqual(pet.experience, 50)
        XCTAssertEqual(pet.experienceGoal, 2_800)
        XCTAssertEqual(pet.stage, .kitsora)
    }

    func testRunUpdatesProgressionAndResources() {
        var pet = PetSnapshot.starter
        let previousCoins = pet.coins
        let previousDistance = pet.distanceTodayKilometers

        pet.applyRun(distanceKilometers: 3, experienceEarned: 150, at: pet.distanceDay)

        XCTAssertEqual(pet.distanceTodayKilometers, previousDistance + 3, accuracy: 0.001)
        XCTAssertGreaterThan(pet.coins, previousCoins)
        XCTAssertGreaterThanOrEqual(pet.friendship, PetSnapshot.starter.friendship)
    }

    func testRunsAccumulateWithinTheSameLocalDay() {
        var pet = PetSnapshot.starter
        pet.distanceTodayKilometers = 0
        let morning = date(day: 23, hour: 1)
        let evening = date(day: 23, hour: 23)

        pet.applyRun(distanceKilometers: 1.5, experienceEarned: 0, at: morning, calendar: calendar)
        pet.applyRun(distanceKilometers: 2, experienceEarned: 0, at: evening, calendar: calendar)

        XCTAssertEqual(pet.distanceKilometers(on: evening, calendar: calendar), 3.5, accuracy: 0.001)
        XCTAssertEqual(pet.lastUpdated, evening)
    }

    func testMidnightResetsDailyDistanceWithoutChangingWeeklyProgress() {
        var pet = PetSnapshot.starter
        let previousDay = date(day: 23, hour: 23, minute: 50)
        let nextDay = date(day: 24, hour: 0, minute: 10)
        pet.distanceDay = previousDay
        pet.distanceTodayKilometers = 2.5
        pet.weeklyDistanceKilometers = 8

        XCTAssertEqual(pet.distanceKilometers(on: nextDay, calendar: calendar), 0)

        pet.applyRun(distanceKilometers: 1, experienceEarned: 0, at: nextDay, calendar: calendar)

        XCTAssertEqual(pet.distanceTodayKilometers, 1, accuracy: 0.001)
        XCTAssertEqual(pet.distanceKilometers(on: nextDay, calendar: calendar), 1, accuracy: 0.001)
        XCTAssertEqual(pet.weeklyDistanceKilometers, 9, accuracy: 0.001)
    }

    func testPetInteractionsDoNotCarryPreviousDaysDistanceForward() throws {
        var pet = PetSnapshot.starter
        let previousDay = date(day: 23, hour: 23)
        let nextDay = date(day: 24, hour: 8)
        pet.distanceDay = previousDay
        pet.distanceTodayKilometers = 2.5
        pet.lastUpdated = previousDay

        pet.feed(at: nextDay)
        pet.pet(at: nextDay)
        pet.play(at: nextDay)

        // Save/load must preserve the run day even though interaction time changed.
        pet = try JSONDecoder().decode(PetSnapshot.self, from: JSONEncoder().encode(pet))
        XCTAssertEqual(pet.lastUpdated, nextDay)
        XCTAssertEqual(pet.distanceDay, previousDay)
        XCTAssertEqual(pet.distanceKilometers(on: nextDay, calendar: calendar), 0)

        pet.applyRun(distanceKilometers: 1, experienceEarned: 0, at: nextDay, calendar: calendar)
        XCTAssertEqual(pet.distanceTodayKilometers, 1, accuracy: 0.001)
    }

    func testEvolutionProgressUsesCurrentStageFloor() {
        var pet = PetSnapshot.starter
        pet.level = 10

        XCTAssertEqual(pet.stage, .kitsora)
        XCTAssertEqual(pet.evolutionProgress, 0, accuracy: 0.001)

        pet.level = 20
        XCTAssertEqual(pet.evolutionProgress, 10.0 / 15.0, accuracy: 0.001)
    }

    func testSnapshotWithoutDecorationStillDecodesWithDefaultHabitat() throws {
        struct LegacySnapshot: Codable {
            var name: String
            var level: Int
            var experience: Int
            var experienceGoal: Int
            var energy: Int
            var friendship: Int
            var coins: Int
            var streakDays: Int
            var mood: PetMood
            var distanceTodayKilometers: Double
            var weeklyDistanceKilometers: Double
            var equippedAccessory: String?
            var lastUpdated: Date
        }

        var pet = PetSnapshot.starter
        pet.lastUpdated = date(day: 23, hour: 23)
        let legacy = LegacySnapshot(
            name: pet.name,
            level: pet.level,
            experience: pet.experience,
            experienceGoal: pet.experienceGoal,
            energy: pet.energy,
            friendship: pet.friendship,
            coins: pet.coins,
            streakDays: pet.streakDays,
            mood: pet.mood,
            distanceTodayKilometers: pet.distanceTodayKilometers,
            weeklyDistanceKilometers: pet.weeklyDistanceKilometers,
            equippedAccessory: pet.equippedAccessory,
            lastUpdated: pet.lastUpdated
        )

        var decoded = try JSONDecoder().decode(
            PetSnapshot.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertNil(decoded.equippedDecoration)
        XCTAssertEqual(decoded.species, .corgi)
        XCTAssertEqual(decoded.activeDecoration, "Flower Meadow")
        XCTAssertEqual(decoded.distanceDay, pet.lastUpdated)
        XCTAssertEqual(
            decoded.distanceKilometers(on: pet.lastUpdated, calendar: calendar),
            pet.distanceTodayKilometers,
            accuracy: 0.001
        )
        let nextDay = date(day: 24, hour: 8)
        decoded.feed(at: nextDay)
        XCTAssertEqual(decoded.distanceKilometers(on: nextDay, calendar: calendar), 0)
        decoded.applyRun(distanceKilometers: 1, experienceEarned: 0, at: nextDay, calendar: calendar)
        XCTAssertEqual(decoded.distanceTodayKilometers, 1, accuracy: 0.001)
    }

    func testEveryCompanionSurvivesSnapshotRoundTrip() throws {
        for species in PetSpecies.allCases {
            var pet = PetSnapshot.starter
            pet.selectSpecies(species, at: date(day: 23, hour: 10))

            let decoded = try JSONDecoder().decode(
                PetSnapshot.self,
                from: JSONEncoder().encode(pet)
            )

            XCTAssertEqual(decoded, pet)
            XCTAssertEqual(decoded.species, species)
        }
    }

    func testExpandedCataloguePreservesEveryOriginalAdultCompanion() throws {
        for species in [PetSpecies.corgi, .bunny, .penguin] {
            var pet = PetSnapshot.starter
            pet.species = species
            pet.level = 27
            pet.coins = 3_250
            pet.equippedDecoration = "Camp Glow"
            let decoded = try JSONDecoder().decode(PetSnapshot.self, from: JSONEncoder().encode(pet))
            XCTAssertEqual(decoded, pet)
            XCTAssertEqual(decoded.lifeStage, .adult)
            XCTAssertNil(decoded.lifecycle)
        }
    }

    func testSpeciesRarityAndSpecialMovesAreIndependentFromCoatVariants() {
        XCTAssertEqual(PetSpecies.allCases.filter { $0.rarity == .common }, [.corgi, .bunny, .penguin])
        XCTAssertEqual(PetSpecies.allCases.filter { $0.rarity == .rare }, [.redPanda, .fox, .axolotl])
        XCTAssertEqual(PetSpecies.allCases.filter { $0.rarity == .mythic }, [.dragon, .unicorn, .phoenix])
        for species in PetSpecies.allCases {
            XCTAssertEqual(species.specialMoveName == nil, species.rarity == .common)
            XCTAssertEqual(species.specialMoveDescription == nil, species.rarity == .common)
        }
        XCTAssertTrue(PetColorVariant.moonlight.isRare)
        XCTAssertTrue(PetColorVariant.aurora.isRare)
        XCTAssertFalse(PetColorVariant.classic.isRare)
        XCTAssertEqual(PetSpecies.redPanda.rawValue, "red-panda")
    }

    func testChangingCompanionPreservesEarnedProgressAndEquipment() {
        let original = PetSnapshot.starter
        var pet = original
        let selectedAt = date(day: 23, hour: 10)

        pet.selectSpecies(.penguin, at: selectedAt)

        XCTAssertEqual(pet.species, .penguin)
        XCTAssertEqual(pet.lastUpdated, selectedAt)
        var expected = original
        expected.species = .penguin
        expected.lastUpdated = selectedAt
        XCTAssertEqual(pet, expected)
    }

    func testUnknownCompanionFallsBackWithoutDiscardingSavedProgress() throws {
        var pet = PetSnapshot.starter
        pet.level = 19
        let data = try JSONEncoder().encode(pet)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload["species"] = "future-companion"

        let decoded = try JSONDecoder().decode(
            PetSnapshot.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertEqual(decoded.species, .corgi)
        XCTAssertEqual(decoded.level, 19)
        XCTAssertEqual(decoded.experience, pet.experience)
        XCTAssertEqual(decoded.coins, pet.coins)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 60 * 60)!
        return calendar
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
}
