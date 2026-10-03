import Foundation

enum PetLifeStage: String, Codable, CaseIterable, Sendable, Hashable {
    case egg, baby, adult

    var displayName: String {
        switch self {
        case .egg: "Egg"
        case .baby: "Baby"
        case .adult: "Grown-up"
        }
    }
}

enum PetColorVariant: String, Codable, CaseIterable, Sendable, Hashable {
    case classic, mint, peach, lavender, sky, moonlight, aurora

    var displayName: String { rawValue.capitalized }
    var isRare: Bool { self == .moonlight || self == .aurora }
}

enum PetGeneticTrait: String, Codable, CaseIterable, Sendable, Hashable {
    case endurance, power, calm, explorer

    var displayName: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .endurance: "heart.fill"
        case .power: "bolt.fill"
        case .calm: "leaf.fill"
        case .explorer: "sparkles"
        }
    }

    var colorVariant: PetColorVariant {
        switch self {
        case .endurance: .mint
        case .power: .peach
        case .calm: .lavender
        case .explorer: .sky
        }
    }
}

/// A companion's inheritance is rolled once. Only completed active workout time
/// shapes growth and genes; XP, speed, calories, feeding and play do not.
struct PetLifecycle: Codable, Equatable, Sendable {
    static let hatchSeconds: Double = 30 * 60
    static let babyGrowthSeconds: Double = 180 * 60
    static let adultSeconds = hatchSeconds + babyGrowthSeconds
    static let dailyCreditLimitSeconds: Double = 60 * 60
    static let speciesRollCount = 3_000

    let seed: UInt64
    let species: PetSpecies
    let inheritedVariant: PetColorVariant?
    private(set) var creditedSeconds: Double = 0
    private(set) var hatchedAt: Date?
    private(set) var maturedAt: Date?
    private var genes: [PetGeneticTrait: Double] = [:]
    // Retain all growth days so delayed Watch delivery cannot reopen an old cap.
    private var creditedSecondsByDay: [String: Double] = [:]
    private var processedWorkoutIDs: Set<UUID> = []

    init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        self.seed = seed
        var random = InheritanceRandom(seed: seed)
        // Only a newly created egg uses today's catalogue. Decoding restores
        // the saved species directly, so older eggs never change their animal.
        species = Self.species(for: Int(random.next() % UInt64(Self.speciesRollCount))) ?? .corgi
        inheritedVariant = Self.rareVariant(for: Int(random.next() % 100))
    }

    var stage: PetLifeStage {
        if creditedSeconds >= Self.adultSeconds { return .adult }
        if creditedSeconds >= Self.hatchSeconds { return .baby }
        return .egg
    }

    /// Progress through the current stage; the hatch resets the baby bar to zero.
    var growthProgress: Double {
        switch stage {
        case .egg: min(max(creditedSeconds / Self.hatchSeconds, 0), 1)
        case .baby: min(max((creditedSeconds - Self.hatchSeconds) / Self.babyGrowthSeconds, 0), 1)
        case .adult: 1
        }
    }

    var secondsUntilNextStage: Double {
        switch stage {
        case .egg: max(0, Self.hatchSeconds - creditedSeconds)
        case .baby: max(0, Self.adultSeconds - creditedSeconds)
        case .adult: 0
        }
    }

    var dominantTrait: PetGeneticTrait? {
        // A stable order makes ties deterministic across reloads and devices.
        var dominant: PetGeneticTrait?
        var mostSeconds: Double = 0
        for trait in PetGeneticTrait.allCases where geneSeconds(for: trait) > mostSeconds {
            mostSeconds = geneSeconds(for: trait)
            dominant = trait
        }
        return dominant
    }

    /// UI conceals inheritance until hatching. Normal colors can change while
    /// growing; creditWorkout stops at adulthood, fixing the final phenotype.
    var variant: PetColorVariant { inheritedVariant ?? dominantTrait?.colorVariant ?? .classic }
    var isRare: Bool { variant.isRare }

    func geneSeconds(for trait: PetGeneticTrait) -> Double { genes[trait, default: 0] }

    func creditedSeconds(on date: Date, calendar: Calendar = .current) -> Double {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return 0 }
        return creditedSecondsByDay[Self.dayKey(for: date, calendar: calendar), default: 0]
    }

    func hasCreditedWorkout(_ id: UUID) -> Bool { processedWorkoutIDs.contains(id) }

    /// Returns the actual seconds credited after deduplication, the daily cap,
    /// and the remaining growth allowance. Workouts belong to their finish day.
    @discardableResult
    mutating func creditWorkout(
        activity: WorkoutActivity,
        activeSeconds: Double,
        workoutID: UUID? = nil,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> Double {
        guard activeSeconds.isFinite, activeSeconds > 0,
              date.timeIntervalSinceReferenceDate.isFinite, stage != .adult else { return 0 }
        if let workoutID {
            guard !processedWorkoutIDs.contains(workoutID) else { return 0 }
            // Even a capped workout is consumed: retrying it tomorrow must not
            // award growth that it could not earn on its original finish day.
            processedWorkoutIDs.insert(workoutID)
        }
        let dayKey = Self.dayKey(for: date, calendar: calendar)
        let today = creditedSecondsByDay[dayKey, default: 0]
        let seconds = min(activeSeconds, max(0, Self.dailyCreditLimitSeconds - today), Self.adultSeconds - creditedSeconds)
        guard seconds > 0 else { return 0 }
        let previousStage = stage
        creditedSeconds += seconds
        creditedSecondsByDay[dayKey] = today + seconds
        genes[activity.geneticTrait, default: 0] += seconds
        if previousStage == .egg, stage != .egg { hatchedAt = date }
        if stage == .adult { maturedAt = date }
        return seconds
    }

    /// One shared roll: 1% Aurora, 5% Moonlight, and 94% workout-shaped color.
    static func rareVariant(for roll: Int) -> PetColorVariant? {
        switch roll {
        case 0: .aurora
        case 1 ... 5: .moonlight
        default: nil
        }
    }

    /// 84% Common, 15% Rare, 1% Mythic, split evenly within each tier.
    /// Explicit ranges keep odds independent of enum order or future cases.
    /// The separate coat roll remains unchanged by the species catalogue.
    static func species(for roll: Int) -> PetSpecies? {
        switch roll {
        case 0 ..< 840: .corgi
        case 840 ..< 1_680: .bunny
        case 1_680 ..< 2_520: .penguin
        case 2_520 ..< 2_670: .redPanda
        case 2_670 ..< 2_820: .fox
        case 2_820 ..< 2_970: .axolotl
        case 2_970 ..< 2_980: .dragon
        case 2_980 ..< 2_990: .unicorn
        case 2_990 ..< 3_000: .phoenix
        default: nil
        }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(components.era ?? 0)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

extension WorkoutActivity {
    /// Every supported activity has equal growth credit per active minute. Its
    /// family changes the genetic profile and coat, never the speed of maturation.
    var geneticTrait: PetGeneticTrait {
        switch self {
        case .cycling, .elliptical, .handCycling, .running, .walking,
             .wheelchairWalkPace, .wheelchairRunPace, .swimming, .rowing,
             .stairClimbing, .stairs, .stepTraining, .mixedCardio,
             .crossCountrySkiing, .jumpRope, .swimBikeRun,
             .trackAndField, .waterFitness:
            .endurance
        case .boxing, .crossTraining, .functionalStrengthTraining,
             .traditionalStrengthTraining, .coreTraining, .gymnastics,
             .highIntensityIntervalTraining, .kickboxing, .martialArts,
             .wrestling, .barre:
            .power
        case .mindAndBody, .preparationAndRecovery, .yoga, .flexibility,
             .pilates, .taiChi, .cooldown:
            .calm
        case .americanFootball, .archery, .australianFootball, .badminton,
             .baseball, .basketball, .bowling, .climbing, .cricket, .curling,
             .equestrianSports, .fencing, .fishing, .golf, .handball, .hiking,
             .hockey, .hunting, .lacrosse, .paddleSports, .play, .racquetball,
             .rugby, .sailing, .skatingSports, .snowSports, .soccer, .softball,
             .squash, .surfingSports, .tableTennis, .tennis, .volleyball,
             .waterPolo, .waterSports, .downhillSkiing, .snowboarding,
             .discSports, .fitnessGaming, .cardioDance, .socialDance, .pickleball,
             .underwaterDiving, .other:
            .explorer
        }
    }
}

/// SplitMix64 gives a repeatable inheritance roll without relying on Swift's
/// randomized Hasher or changing the system random generator's global state.
private struct InheritanceRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
