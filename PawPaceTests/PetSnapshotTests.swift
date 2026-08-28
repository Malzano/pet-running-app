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

        pet.applyRun(distanceKilometers: 3, experienceEarned: 150)

        XCTAssertEqual(pet.distanceTodayKilometers, previousDistance + 3, accuracy: 0.001)
        XCTAssertGreaterThan(pet.coins, previousCoins)
        XCTAssertGreaterThanOrEqual(pet.friendship, PetSnapshot.starter.friendship)
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

        let pet = PetSnapshot.starter
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

        let decoded = try JSONDecoder().decode(
            PetSnapshot.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertNil(decoded.equippedDecoration)
        XCTAssertEqual(decoded.activeDecoration, "Flower Meadow")
    }
}
