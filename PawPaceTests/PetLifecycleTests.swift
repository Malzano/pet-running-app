import XCTest
@testable import PawPace

final class PetLifecycleTests: XCTestCase {
    func testNewPlayerStartsWithAnUnhatchedEggAndNoEarnedResources() throws {
        let pet = PetSnapshot.newPlayer(seed: 42, at: day(1))
        let lifecycle = try XCTUnwrap(pet.lifecycle)

        XCTAssertEqual(pet.lifeStage, .egg)
        XCTAssertEqual(lifecycle.creditedSeconds, 0)
        XCTAssertEqual(lifecycle.growthProgress, 0)
        XCTAssertEqual(lifecycle.secondsUntilNextStage, 1_800)
        XCTAssertNil(lifecycle.dominantTrait)
        XCTAssertEqual(pet.species, lifecycle.species)
        XCTAssertEqual(pet.level, 1)
        XCTAssertEqual(pet.experience, 0)
        XCTAssertEqual(pet.coins, 0)
        XCTAssertEqual(pet.streakDays, 0)
        XCTAssertEqual(pet.weeklyDistanceKilometers, 0)
        XCTAssertEqual(pet.distanceTodayKilometers, 0)
        XCTAssertEqual(pet.dailyWorkoutSeconds, 0)
    }

    func testHatchBoundaryAndSpilloverMinutes() {
        var lifecycle = PetLifecycle(seed: 42)
        credit(&lifecycle, seconds: 1_799, on: 1)
        XCTAssertEqual(lifecycle.stage, .egg)
        XCTAssertEqual(lifecycle.secondsUntilNextStage, 1)
        XCTAssertNil(lifecycle.hatchedAt)

        credit(&lifecycle, seconds: 1, on: 1)
        XCTAssertEqual(lifecycle.stage, .baby)
        XCTAssertEqual(lifecycle.growthProgress, 0)
        XCTAssertEqual(lifecycle.secondsUntilNextStage, 10_800)
        XCTAssertEqual(lifecycle.hatchedAt, day(1))
        XCTAssertNil(lifecycle.maturedAt)

        credit(&lifecycle, seconds: 600, on: 1)
        XCTAssertEqual(lifecycle.creditedSeconds, 2_400)
        XCTAssertEqual(lifecycle.growthProgress, 600.0 / 10_800, accuracy: 0.0001)
        XCTAssertEqual(lifecycle.secondsUntilNextStage, 10_200)
    }

    func testSingleWorkoutCarriesHatchExcessIntoBabyGrowth() {
        var lifecycle = PetLifecycle(seed: 42)
        credit(&lifecycle, seconds: 2_400, on: 1)
        XCTAssertEqual(lifecycle.stage, .baby)
        XCTAssertEqual(lifecycle.growthProgress, 600.0 / 10_800, accuracy: 0.0001)
        XCTAssertEqual(lifecycle.geneSeconds(for: .endurance), 2_400)
    }

    func testDailyCapAppliesToBothGrowthAndGeneticsAndResetsAtMidnight() {
        var lifecycle = PetLifecycle(seed: 42)
        credit(&lifecycle, seconds: 5_400, on: 1)
        XCTAssertEqual(lifecycle.creditedSeconds, 3_600)
        XCTAssertEqual(lifecycle.geneSeconds(for: .endurance), 3_600)

        credit(&lifecycle, seconds: 600, activity: .yoga, on: 1)
        XCTAssertEqual(lifecycle.creditedSeconds, 3_600)
        XCTAssertEqual(lifecycle.geneSeconds(for: .calm), 0)

        credit(&lifecycle, seconds: 600, activity: .yoga, on: 2)
        XCTAssertEqual(lifecycle.creditedSeconds, 4_200)
        XCTAssertEqual(lifecycle.geneSeconds(for: .calm), 600)
        XCTAssertEqual(lifecycle.creditedSeconds(on: day(1), calendar: calendar), 3_600)
        XCTAssertEqual(lifecycle.creditedSeconds(on: day(2), calendar: calendar), 600)
    }

    func testDelayedWorkoutCannotReopenAnOldDaysCap() {
        var lifecycle = PetLifecycle(seed: 42)
        credit(&lifecycle, seconds: 3_600, on: 1)
        credit(&lifecycle, seconds: 600, on: 2)
        credit(&lifecycle, seconds: 600, activity: .yoga, on: 1)
        XCTAssertEqual(lifecycle.creditedSeconds, 4_200)
        XCTAssertEqual(lifecycle.geneSeconds(for: .calm), 0)
    }

    func testAdultBoundaryAndGenotypeFreeze() {
        var lifecycle = PetLifecycle(seed: nonRareSeed)
        for date in 1 ... 3 { credit(&lifecycle, seconds: 3_600, on: date) }
        credit(&lifecycle, seconds: 1_799, on: 4)
        XCTAssertEqual(lifecycle.stage, .baby)
        XCTAssertEqual(lifecycle.secondsUntilNextStage, 1)

        credit(&lifecycle, seconds: 3_600, on: 4)
        XCTAssertEqual(lifecycle.stage, .adult)
        XCTAssertEqual(lifecycle.creditedSeconds, 12_600)
        XCTAssertEqual(lifecycle.growthProgress, 1)
        XCTAssertEqual(lifecycle.secondsUntilNextStage, 0)
        XCTAssertEqual(lifecycle.geneSeconds(for: .endurance), 12_600)
        XCTAssertEqual(lifecycle.hatchedAt, day(1))
        XCTAssertEqual(lifecycle.maturedAt, day(4))
        let grown = lifecycle

        credit(&lifecycle, seconds: 50_000, activity: .yoga, on: 5)
        XCTAssertEqual(lifecycle, grown, "A grown companion's genes and color stay fixed")
    }

    func testWorkoutIdentifierDeduplicatesIndependentlyOfRewardLedger() throws {
        var lifecycle = PetLifecycle(seed: 42)
        let workoutID = UUID()
        lifecycle.creditWorkout(activity: .running, activeSeconds: 600, workoutID: workoutID, at: day(1), calendar: calendar)
        lifecycle = try JSONDecoder().decode(PetLifecycle.self, from: JSONEncoder().encode(lifecycle))
        let before = lifecycle

        let credited = lifecycle.creditWorkout(activity: .running, activeSeconds: 600, workoutID: workoutID, at: day(2), calendar: calendar)
        XCTAssertEqual(credited, 0)
        XCTAssertEqual(lifecycle, before)
        XCTAssertTrue(lifecycle.hasCreditedWorkout(workoutID))
    }

    func testCappedWorkoutIsConsumedAndCannotBeReplayedTomorrow() {
        var lifecycle = PetLifecycle(seed: 42)
        credit(&lifecycle, seconds: 3_600, on: 1)
        let cappedID = UUID()
        lifecycle.creditWorkout(activity: .yoga, activeSeconds: 1_800, workoutID: cappedID, at: day(1), calendar: calendar)
        lifecycle.creditWorkout(activity: .yoga, activeSeconds: 1_800, workoutID: cappedID, at: day(2), calendar: calendar)
        XCTAssertEqual(lifecycle.creditedSeconds, 3_600)
        XCTAssertEqual(lifecycle.geneSeconds(for: .calm), 0)
    }

    func testInvalidDurationsDoNotAffectGrowthOrGenes() {
        for seconds in [Double.nan, .infinity, -.infinity, -60, 0] {
            var lifecycle = PetLifecycle(seed: 42)
            let before = lifecycle
            let result = lifecycle.creditWorkout(activity: .running, activeSeconds: seconds, workoutID: UUID(), at: day(1), calendar: calendar)
            XCTAssertEqual(result, 0)
            XCTAssertEqual(lifecycle, before)
        }
        var lifecycle = PetLifecycle(seed: 42)
        credit(&lifecycle, seconds: .greatestFiniteMagnitude, on: 1)
        XCTAssertEqual(lifecycle.creditedSeconds, 3_600, "Finite input is always bounded by the daily allowance")
    }

    func testFractionalActiveSecondsRetainPrecision() {
        var lifecycle = PetLifecycle(seed: 42)
        credit(&lifecycle, seconds: 12.5, on: 1)
        credit(&lifecycle, seconds: 7.25, on: 1)
        XCTAssertEqual(lifecycle.creditedSeconds, 19.75)
        XCTAssertEqual(lifecycle.geneSeconds(for: .endurance), 19.75)
    }

    func testWorkoutFamiliesShapeDifferentGenesWithEqualGrowthCredit() {
        let examples: [(WorkoutActivity, PetGeneticTrait, PetColorVariant)] = [
            (.running, .endurance, .mint), (.walking, .endurance, .mint),
            (.wheelchairRunPace, .endurance, .mint), (.handCycling, .endurance, .mint),
            (.traditionalStrengthTraining, .power, .peach), (.yoga, .calm, .lavender),
            (.preparationAndRecovery, .calm, .lavender), (.hiking, .explorer, .sky),
            (.play, .explorer, .sky)
        ]
        for (activity, trait, variant) in examples {
            var lifecycle = PetLifecycle(seed: nonRareSeed)
            credit(&lifecycle, seconds: 1_800, activity: activity, on: 1)
            XCTAssertEqual(lifecycle.dominantTrait, trait, activity.displayName)
            XCTAssertEqual(lifecycle.geneSeconds(for: trait), 1_800)
            XCTAssertEqual(lifecycle.variant, variant)
            XCTAssertEqual(lifecycle.creditedSeconds, 1_800)
        }
    }

    func testEverySupportedActivityCreditsExactlyOneGeneFamily() {
        for activity in WorkoutActivity.allCases {
            var lifecycle = PetLifecycle(seed: nonRareSeed)
            credit(&lifecycle, seconds: 60, activity: activity, on: 1)
            XCTAssertEqual(PetGeneticTrait.allCases.reduce(0) { $0 + lifecycle.geneSeconds(for: $1) }, 60)
            XCTAssertEqual(lifecycle.dominantTrait, activity.geneticTrait)
        }
    }

    func testDominantColorUsesDurationAndStableTieBreaking() {
        var lifecycle = PetLifecycle(seed: nonRareSeed)
        credit(&lifecycle, seconds: 600, activity: .yoga, on: 1)
        XCTAssertEqual(lifecycle.variant, .lavender)
        credit(&lifecycle, seconds: 300, activity: .running, on: 1)
        XCTAssertEqual(lifecycle.dominantTrait, .calm)
        credit(&lifecycle, seconds: 300, activity: .running, on: 1)
        XCTAssertEqual(lifecycle.dominantTrait, .endurance, "Tie order is stable, independent of activity order")
        credit(&lifecycle, seconds: 601, activity: .hiking, on: 1)
        XCTAssertEqual(lifecycle.variant, .sky)
    }

    func testRareRollIsMutuallyExclusiveWithExactConfiguredWeights() {
        let variants = (0 ..< 100).map(PetLifecycle.rareVariant(for:))
        XCTAssertEqual(variants.filter { $0 == .aurora }.count, 1)
        XCTAssertEqual(variants.filter { $0 == .moonlight }.count, 5)
        XCTAssertEqual(variants.filter { $0 == nil }.count, 94)
        XCTAssertNil(PetLifecycle.rareVariant(for: -1))
        XCTAssertNil(PetLifecycle.rareVariant(for: 100))
    }

    func testSpeciesOddsAreExactAndSplitEvenlyWithinEachTier() throws {
        let species = try (0 ..< PetLifecycle.speciesRollCount).map {
            try XCTUnwrap(PetLifecycle.species(for: $0))
        }
        XCTAssertEqual(species.count, 3_000)
        XCTAssertEqual(species.filter { $0.rarity == .common }.count, 2_520)
        XCTAssertEqual(species.filter { $0.rarity == .rare }.count, 450)
        XCTAssertEqual(species.filter { $0.rarity == .mythic }.count, 30)
        for companion in [PetSpecies.corgi, .bunny, .penguin] {
            XCTAssertEqual(species.filter { $0 == companion }.count, 840)
        }
        for companion in [PetSpecies.redPanda, .fox, .axolotl] {
            XCTAssertEqual(species.filter { $0 == companion }.count, 150)
        }
        for companion in [PetSpecies.dragon, .unicorn, .phoenix] {
            XCTAssertEqual(species.filter { $0 == companion }.count, 10)
        }
        XCTAssertNil(PetLifecycle.species(for: -1))
        XCTAssertNil(PetLifecycle.species(for: PetLifecycle.speciesRollCount))
    }

    func testPreviouslySavedEggKeepsItsAnimalGenesAndCreditedWorkouts() throws {
        // This is the original catalogue's seed-42 egg, saved before Rare and
        // Mythic species existed. Today's new seed-42 egg rolls a penguin.
        let data = Data(#"""
        {
          "seed": 42,
          "species": "bunny",
          "creditedSeconds": 41,
          "genes": ["calm", 41],
          "creditedSecondsByDay": {"1-2026-9-25": 41},
          "processedWorkoutIDs": ["3480612D-EF28-4AB2-8428-E0A18771D31A"]
        }
        """#.utf8)
        var saved = try JSONDecoder().decode(PetLifecycle.self, from: data)
        XCTAssertNotEqual(PetLifecycle(seed: 42).species, .bunny)
        XCTAssertEqual(saved.species, .bunny)
        XCTAssertEqual(saved.seed, 42)
        XCTAssertEqual(saved.creditedSeconds, 41)
        XCTAssertEqual(saved.geneSeconds(for: .calm), 41)
        XCTAssertEqual(saved.creditedSeconds(on: day(25), calendar: calendar), 41)
        XCTAssertEqual(saved.variant, .lavender)
        let workoutID = try XCTUnwrap(UUID(uuidString: "3480612D-EF28-4AB2-8428-E0A18771D31A"))
        XCTAssertTrue(saved.hasCreditedWorkout(workoutID))
        XCTAssertEqual(saved.creditWorkout(activity: .yoga, activeSeconds: 41, workoutID: workoutID, at: day(25), calendar: calendar), 0)
        XCTAssertEqual(try JSONDecoder().decode(PetLifecycle.self, from: JSONEncoder().encode(saved)), saved)
    }

    func testExpandedSpeciesCatalogueKeepsTheOriginalCoatDraw() {
        // Known original inheritance outcomes from the second SplitMix64 draw.
        XCTAssertEqual(PetLifecycle(seed: 0).inheritedVariant, .aurora)
        for seed in [UInt64(1), 2, 42, 99, 281] {
            XCTAssertNil(PetLifecycle(seed: seed).inheritedVariant)
        }
    }

    func testEveryRarityHasTheSameGrowthCreditAndKeepsItsSpecies() throws {
        for species in PetSpecies.allCases {
            let seed = try XCTUnwrap((UInt64(0) ..< 10_000).first { PetLifecycle(seed: $0).species == species })
            var lifecycle = PetLifecycle(seed: seed)
            credit(&lifecycle, seconds: 1_800, activity: .yoga, on: 1)
            XCTAssertEqual(lifecycle.species, species)
            XCTAssertEqual(lifecycle.stage, .baby)
            XCTAssertEqual(lifecycle.geneSeconds(for: .calm), 1_800)
            credit(&lifecycle, seconds: 1_800, activity: .running, on: 1)
            XCTAssertEqual(lifecycle.creditedSeconds, 3_600)
            credit(&lifecycle, seconds: 600, activity: .running, on: 1)
            XCTAssertEqual(lifecycle.creditedSeconds, 3_600)
            XCTAssertEqual(lifecycle.species, species)
        }
    }

    func testSeedIsRepeatableAndSpeciesAndRaritySurvivePersistence() throws {
        var species: Set<PetSpecies> = []
        var rareVariants: Set<PetColorVariant> = []
        for seed in UInt64(0) ..< 1_000 {
            let original = PetLifecycle(seed: seed)
            XCTAssertEqual(original, PetLifecycle(seed: seed))
            let decoded = try JSONDecoder().decode(PetLifecycle.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(decoded, original)
            species.insert(original.species)
            if let variant = original.inheritedVariant { rareVariants.insert(variant) }
        }
        XCTAssertEqual(species, Set(PetSpecies.allCases))
        XCTAssertEqual(rareVariants, [.moonlight, .aurora])
    }

    func testRareInheritanceOverridesWorkoutColorWithoutChangingGrowthSpeed() throws {
        let seed = try XCTUnwrap((UInt64(0) ..< 1_000).first { PetLifecycle(seed: $0).inheritedVariant == .aurora })
        var lifecycle = PetLifecycle(seed: seed)
        credit(&lifecycle, seconds: 1_800, activity: .yoga, on: 1)
        XCTAssertEqual(lifecycle.stage, .baby)
        XCTAssertEqual(lifecycle.dominantTrait, .calm)
        XCTAssertEqual(lifecycle.variant, .aurora)
        XCTAssertTrue(lifecycle.isRare)
    }

    func testFeedingPlayingAndXPDoNotGrowOrChangeTheEgg() {
        var pet = PetSnapshot.newPlayer(seed: 42, at: day(1))
        let originalLifecycle = pet.lifecycle
        pet.feed(at: day(1))
        pet.play(at: day(1))
        pet.pet(at: day(1))
        pet.awardExperience(10_000, at: day(1))
        XCTAssertEqual(pet.lifecycle, originalLifecycle)
        XCTAssertEqual(pet.lifeStage, .egg)
    }

    func testLifecycleSpeciesCannotBeChangedByLegacySelection() {
        var pet = PetSnapshot.newPlayer(seed: 42, at: day(1))
        let original = pet
        for species in PetSpecies.allCases { pet.selectSpecies(species, at: day(2)) }
        XCTAssertEqual(pet, original)
    }

    func testApplyRunForwardsActivityTimeAndWorkoutIdentity() throws {
        var pet = PetSnapshot.newPlayer(seed: nonRareSeed, at: day(1))
        let id = UUID()
        pet.applyRun(distanceKilometers: 0, experienceEarned: 60, elapsedSeconds: 1_800, activity: .yoga, workoutID: id, at: day(1), calendar: calendar)
        XCTAssertEqual(pet.lifeStage, .baby)
        XCTAssertEqual(pet.lifecycle?.variant, .lavender)
        let originalLifecycle = try XCTUnwrap(pet.lifecycle)
        pet.applyRun(distanceKilometers: 0, experienceEarned: 60, elapsedSeconds: 1_800, activity: .yoga, workoutID: id, at: day(2), calendar: calendar)
        XCTAssertEqual(pet.lifecycle, originalLifecycle)
    }

    func testLegacyDecodePreservesEarnedStatsAndTreatsCompanionAsGrown() throws {
        var original = PetSnapshot.starter
        original.level = 1
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "lifecycle")
        let decoded = try JSONDecoder().decode(PetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.lifecycle)
        XCTAssertEqual(decoded.lifeStage, .adult)
        XCTAssertEqual(decoded.coins, original.coins)
        XCTAssertEqual(decoded.weeklyDistanceKilometers, original.weeklyDistanceKilometers)
        XCTAssertEqual(decoded.equippedAccessory, original.equippedAccessory)
    }

    func testFirstLoadPersistsExactlyTheSameEggOnSubsequentLoads() throws {
        let suiteName = "PawPaceTests.PetLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertNil(PawPaceShared.loadSnapshotIfPresent(from: defaults))
        let first = PawPaceShared.loadSnapshot(from: defaults)
        XCTAssertEqual(first.lifeStage, .egg)
        XCTAssertEqual(PawPaceShared.loadSnapshot(from: defaults), first)
        XCTAssertEqual(PawPaceShared.loadSnapshotIfPresent(from: defaults), first)
    }

    private var nonRareSeed: UInt64 {
        (UInt64(0) ..< 1_000).first { PetLifecycle(seed: $0).inheritedVariant == nil }!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ number: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: number))!
    }

    private func credit(_ lifecycle: inout PetLifecycle, seconds: Double, activity: WorkoutActivity = .running, on number: Int) {
        lifecycle.creditWorkout(activity: activity, activeSeconds: seconds, workoutID: UUID(), at: day(number), calendar: calendar)
    }
}
