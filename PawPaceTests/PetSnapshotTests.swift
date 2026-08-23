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
}

