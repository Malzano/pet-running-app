import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Stable portable identifiers; raw HealthKit numbers are kept at the integration boundary.
/// The catalog covers every nondeprecated public workout type, excluding the transition
/// segment and unavailable rest/group sentinels. Multisport requires real activity legs.
enum WorkoutActivity: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case americanFootball
    case archery
    case australianFootball
    case badminton
    case baseball
    case basketball
    case bowling
    case boxing
    case climbing
    case cricket
    case crossTraining
    case curling
    case cycling
    case elliptical
    case equestrianSports
    case fencing
    case fishing
    case functionalStrengthTraining
    case golf
    case gymnastics
    case handball
    case hiking
    case hockey
    case hunting
    case lacrosse
    case martialArts
    case mindAndBody
    case paddleSports
    case play
    case preparationAndRecovery
    case racquetball
    case rowing
    case rugby
    case running
    case sailing
    case skatingSports
    case snowSports
    case soccer
    case softball
    case squash
    case stairClimbing
    case surfingSports
    case swimming
    case tableTennis
    case tennis
    case trackAndField
    case traditionalStrengthTraining
    case volleyball
    case walking
    case waterFitness
    case waterPolo
    case waterSports
    case wrestling
    case yoga
    case barre
    case coreTraining
    case crossCountrySkiing
    case downhillSkiing
    case flexibility
    case highIntensityIntervalTraining
    case jumpRope
    case kickboxing
    case pilates
    case snowboarding
    case stairs
    case stepTraining
    case wheelchairWalkPace
    case wheelchairRunPace
    case taiChi
    case mixedCardio
    case handCycling
    case discSports
    case fitnessGaming
    case cardioDance
    case socialDance
    case pickleball
    case cooldown
    case swimBikeRun
    case underwaterDiving
    case other

    var id: String { rawValue }

    var healthKitRawValue: UInt {
        switch self {
        case .americanFootball: 1
        case .archery: 2
        case .australianFootball: 3
        case .badminton: 4
        case .baseball: 5
        case .basketball: 6
        case .bowling: 7
        case .boxing: 8
        case .climbing: 9
        case .cricket: 10
        case .crossTraining: 11
        case .curling: 12
        case .cycling: 13
        case .elliptical: 16
        case .equestrianSports: 17
        case .fencing: 18
        case .fishing: 19
        case .functionalStrengthTraining: 20
        case .golf: 21
        case .gymnastics: 22
        case .handball: 23
        case .hiking: 24
        case .hockey: 25
        case .hunting: 26
        case .lacrosse: 27
        case .martialArts: 28
        case .mindAndBody: 29
        case .paddleSports: 31
        case .play: 32
        case .preparationAndRecovery: 33
        case .racquetball: 34
        case .rowing: 35
        case .rugby: 36
        case .running: 37
        case .sailing: 38
        case .skatingSports: 39
        case .snowSports: 40
        case .soccer: 41
        case .softball: 42
        case .squash: 43
        case .stairClimbing: 44
        case .surfingSports: 45
        case .swimming: 46
        case .tableTennis: 47
        case .tennis: 48
        case .trackAndField: 49
        case .traditionalStrengthTraining: 50
        case .volleyball: 51
        case .walking: 52
        case .waterFitness: 53
        case .waterPolo: 54
        case .waterSports: 55
        case .wrestling: 56
        case .yoga: 57
        case .barre: 58
        case .coreTraining: 59
        case .crossCountrySkiing: 60
        case .downhillSkiing: 61
        case .flexibility: 62
        case .highIntensityIntervalTraining: 63
        case .jumpRope: 64
        case .kickboxing: 65
        case .pilates: 66
        case .snowboarding: 67
        case .stairs: 68
        case .stepTraining: 69
        case .wheelchairWalkPace: 70
        case .wheelchairRunPace: 71
        case .taiChi: 72
        case .mixedCardio: 73
        case .handCycling: 74
        case .discSports: 75
        case .fitnessGaming: 76
        case .cardioDance: 77
        case .socialDance: 78
        case .pickleball: 79
        case .cooldown: 80
        case .swimBikeRun: 82
        case .underwaterDiving: 84
        case .other: 3000
        }
    }

    init?(healthKitRawValue: UInt) {
        guard let activity = Self.allCases.first(where: { $0.healthKitRawValue == healthKitRawValue }) else { return nil }
        self = activity
    }

    var displayName: String {
        switch self {
        case .americanFootball: "American Football"
        case .archery: "Archery"
        case .australianFootball: "Australian Football"
        case .badminton: "Badminton"
        case .baseball: "Baseball"
        case .basketball: "Basketball"
        case .bowling: "Bowling"
        case .boxing: "Boxing"
        case .climbing: "Climbing"
        case .cricket: "Cricket"
        case .crossTraining: "Cross Training"
        case .curling: "Curling"
        case .cycling: "Cycling"
        case .elliptical: "Elliptical"
        case .equestrianSports: "Equestrian Sports"
        case .fencing: "Fencing"
        case .fishing: "Fishing"
        case .functionalStrengthTraining: "Functional Strength Training"
        case .golf: "Golf"
        case .gymnastics: "Gymnastics"
        case .handball: "Handball"
        case .hiking: "Hiking"
        case .hockey: "Hockey"
        case .hunting: "Hunting"
        case .lacrosse: "Lacrosse"
        case .martialArts: "Martial Arts"
        case .mindAndBody: "Mind & Body"
        case .paddleSports: "Paddling"
        case .play: "Play"
        case .preparationAndRecovery: "Rolling"
        case .racquetball: "Racquetball"
        case .rowing: "Rowing"
        case .rugby: "Rugby"
        case .running: "Running"
        case .sailing: "Sailing"
        case .skatingSports: "Skating"
        case .snowSports: "Snow Sports"
        case .soccer: "Soccer"
        case .softball: "Softball"
        case .squash: "Squash"
        case .stairClimbing: "Stair Stepper"
        case .surfingSports: "Surfing"
        case .swimming: "Swimming"
        case .tableTennis: "Table Tennis"
        case .tennis: "Tennis"
        case .trackAndField: "Track & Field"
        case .traditionalStrengthTraining: "Traditional Strength Training"
        case .volleyball: "Volleyball"
        case .walking: "Walking"
        case .waterFitness: "Water Fitness"
        case .waterPolo: "Water Polo"
        case .waterSports: "Water Sports"
        case .wrestling: "Wrestling"
        case .yoga: "Yoga"
        case .barre: "Barre"
        case .coreTraining: "Core Training"
        case .crossCountrySkiing: "Cross Country Skiing"
        case .downhillSkiing: "Downhill Skiing"
        case .flexibility: "Flexibility"
        case .highIntensityIntervalTraining: "High Intensity Interval Training"
        case .jumpRope: "Jump Rope"
        case .kickboxing: "Kickboxing"
        case .pilates: "Pilates"
        case .snowboarding: "Snowboarding"
        case .stairs: "Stairs"
        case .stepTraining: "Step Training"
        case .wheelchairWalkPace: "Wheelchair Walk Pace"
        case .wheelchairRunPace: "Wheelchair Run Pace"
        case .taiChi: "Tai Chi"
        case .mixedCardio: "Mixed Cardio"
        case .handCycling: "Hand Cycling"
        case .discSports: "Disc Sports"
        case .fitnessGaming: "Fitness Gaming"
        case .cardioDance: "Dance"
        case .socialDance: "Social Dance"
        case .pickleball: "Pickleball"
        case .cooldown: "Cooldown"
        case .swimBikeRun: "Multisport"
        case .underwaterDiving: "Underwater Diving"
        case .other: "Other"
        }
    }

    var category: WorkoutCategory {
        switch self {
        case .running, .walking, .cycling, .handCycling, .wheelchairWalkPace, .wheelchairRunPace,
             .elliptical, .stairClimbing, .stairs, .stepTraining, .mixedCardio,
             .highIntensityIntervalTraining, .jumpRope, .cardioDance, .socialDance: .cardio
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining,
             .crossTraining, .barre, .gymnastics: .strength
        case .yoga, .pilates, .mindAndBody, .taiChi, .flexibility, .cooldown,
             .preparationAndRecovery: .mindAndBody
        case .hiking, .climbing, .equestrianSports, .fishing, .hunting, .skatingSports: .outdoor
        case .swimming, .rowing, .paddleSports, .sailing, .surfingSports,
             .waterFitness, .waterPolo, .waterSports, .underwaterDiving: .water
        case .crossCountrySkiing, .downhillSkiing, .snowboarding, .snowSports, .curling: .winter
        case .swimBikeRun: .multisport
        case .other, .play, .fitnessGaming: .other
        default: .sports
        }
    }

    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling, .handCycling: "figure.outdoor.cycle"
        case .wheelchairWalkPace, .wheelchairRunPace: "figure.roll"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .hiking: "figure.hiking"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "dumbbell.fill"
        case .coreTraining: "figure.core.training"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .elliptical: "figure.elliptical"
        case .cardioDance, .socialDance: "figure.dance"
        case .swimBikeRun: "figure.mixed.cardio"
        case .climbing: "figure.climbing"
        case .soccer: "soccerball"
        case .basketball: "basketball.fill"
        case .tennis, .tableTennis, .badminton, .racquetball, .squash, .pickleball: "tennis.racket"
        case .boxing, .kickboxing, .martialArts, .wrestling: "figure.boxing"
        case .crossCountrySkiing, .downhillSkiing: "figure.skiing.downhill"
        case .snowboarding: "figure.snowboarding"
        case .underwaterDiving: "water.waves"
        default: category.symbol
        }
    }

    var distanceKind: WorkoutDistanceKind {
        switch self {
        case .running, .walking, .hiking: .walkingRunning
        case .cycling, .handCycling: .cycling
        case .swimming: .swimming
        case .wheelchairWalkPace, .wheelchairRunPace: .wheelchair
        case .downhillSkiing, .snowboarding: .downhillSnowSports
        case .crossCountrySkiing: .crossCountrySkiing
        case .rowing: .rowing
        case .paddleSports: .paddleSports
        case .skatingSports: .skatingSports
        default: .none
        }
    }

    var measurement: WorkoutMeasurement {
        switch distanceKind {
        case .walkingRunning, .wheelchair: .pace
        case .swimming: .swimPace
        case .cycling, .downhillSnowSports, .crossCountrySkiing, .rowing, .paddleSports, .skatingSports: .speed
        case .none: self == .swimBikeRun ? .distance : .duration
        }
    }

    var supportsDistance: Bool { measurement != .duration }
    var supportsPace: Bool { measurement == .pace || measurement == .swimPace }
    var supportsRoute: Bool {
        distanceKind != .none || self == .sailing || self == .equestrianSports || self == .swimBikeRun
    }
    var requiresMultisportSession: Bool { self == .swimBikeRun }

    var allowedLocations: [WorkoutLocation] {
        switch self {
        case .running, .walking, .cycling, .handCycling, .rowing, .swimming, .skatingSports,
             .soccer, .hockey, .climbing, .trackAndField: [.outdoor, .indoor]
        case .hiking, .fishing, .hunting, .equestrianSports, .paddleSports, .sailing,
             .surfingSports, .snowSports, .crossCountrySkiing, .downhillSkiing, .snowboarding,
             .wheelchairWalkPace, .wheelchairRunPace, .swimBikeRun, .underwaterDiving: [.outdoor]
        case .elliptical, .stairClimbing, .fitnessGaming: [.indoor]
        default: [.unknown, .indoor, .outdoor]
        }
    }

    var defaultLocation: WorkoutLocation {
        switch self {
        case .swimming, .rowing: .indoor
        default: allowedLocations[0]
        }
    }

    static let recommendedActivities: [Self] = [
        .running, .walking, .cycling, .traditionalStrengthTraining, .yoga,
        .highIntensityIntervalTraining, .swimming, .hiking, .rowing, .swimBikeRun
    ]
    static var selectableActivities: [Self] { allCases.sorted { $0.displayName < $1.displayName } }

    static func search(_ query: String) -> [Self] {
        let tokens = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return selectableActivities }
        return selectableActivities.filter { activity in
            let text = "\(activity.displayName) \(activity.rawValue) \(activity.category.displayName) \(activity.searchAliases)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return tokens.allSatisfy { text.contains($0) }
        }
    }

    private var searchAliases: String {
        switch self {
        case .running: "run jogging jog treadmill"
        case .walking: "walk treadmill stroll"
        case .cycling: "cycle bike bicycle spinning spin"
        case .handCycling: "hand bike adaptive cycling"
        case .highIntensityIntervalTraining: "hiit intervals"
        case .traditionalStrengthTraining: "weights lifting gym weightlifting resistance"
        case .functionalStrengthTraining: "bodyweight resistance strength"
        case .paddleSports: "kayak kayaking canoe canoeing sup paddleboard"
        case .swimming: "swim pool open water laps"
        case .swimBikeRun: "triathlon duathlon aquathlon swim bike run multisport"
        case .preparationAndRecovery: "foam rolling recovery preparation mobility"
        case .soccer: "football futsal"
        case .cardioDance: "dancing dance cardio zumba"
        case .socialDance: "dancing salsa swing ballroom"
        case .wheelchairWalkPace, .wheelchairRunPace: "wheelchair rolling adaptive"
        default: ""
        }
    }

    /// Time always earns progress, even if distance sensors return no samples.
    /// Duration-based sports ignore unrelated distance; no calories are fabricated.
    func experienceEarned(elapsedSeconds: Int, distanceKilometers: Double) -> Int {
        let minutes = Double(max(0, elapsedSeconds)) / 60
        let timeReward = minutes * (supportsDistance && !requiresMultisportSession ? 3 : 6)
        let distance = distanceKilometers.isFinite ? min(max(distanceKilometers, 0), 10_000) : 0
        let distanceReward = supportsDistance && !requiresMultisportSession ? distance * 52 : 0
        return Int(min(max(timeReward, distanceReward).rounded(), Double(Int.max / 2)))
    }
}

enum WorkoutCategory: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case cardio, strength, mindAndBody, sports, outdoor, water, winter, multisport, other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .cardio: "Cardio"
        case .strength: "Strength"
        case .mindAndBody: "Mind & Body"
        case .sports: "Sports"
        case .outdoor: "Outdoor"
        case .water: "Water"
        case .winter: "Winter"
        case .multisport: "Multisport"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .cardio: "heart.fill"
        case .strength: "dumbbell.fill"
        case .mindAndBody: "figure.mind.and.body"
        case .sports: "sportscourt.fill"
        case .outdoor: "mountain.2.fill"
        case .water: "water.waves"
        case .winter: "snowflake"
        case .multisport: "figure.triathlon"
        case .other: "figure.play"
        }
    }
}

enum WorkoutLocation: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case indoor, outdoor, unknown
    var id: String { rawValue }
    var displayName: String {
        switch self { case .indoor: "Indoor"; case .outdoor: "Outdoor"; case .unknown: "Not specified" }
    }
}

enum WorkoutSwimmingLocation: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case pool, openWater
    var id: String { rawValue }
    var displayName: String { self == .pool ? "Pool" : "Open Water" }
}

enum WorkoutMeasurement: String, Codable, Sendable, Hashable {
    case duration, pace, speed, swimPace, distance
}

enum WorkoutDistanceKind: String, Codable, Sendable, Hashable {
    case none, walkingRunning, cycling, swimming, wheelchair, downhillSnowSports
    case crossCountrySkiing, rowing, paddleSports, skatingSports
}

struct WorkoutConfiguration: Codable, Hashable, Sendable {
    var activity: WorkoutActivity
    var location: WorkoutLocation
    var swimmingLocation: WorkoutSwimmingLocation
    var poolLengthMeters: Double?
    var multisportLegs: [WorkoutActivity]

    init(
        activity: WorkoutActivity = .running,
        location: WorkoutLocation? = nil,
        swimmingLocation: WorkoutSwimmingLocation? = nil,
        poolLengthMeters: Double? = nil,
        multisportLegs: [WorkoutActivity] = [.swimming, .cycling, .running]
    ) {
        self.activity = activity
        let chosenLocation = location ?? activity.defaultLocation
        self.location = activity.allowedLocations.contains(chosenLocation) ? chosenLocation : activity.defaultLocation
        self.swimmingLocation = swimmingLocation ?? (self.location == .indoor ? .pool : .openWater)
        if self.swimmingLocation == .openWater && activity == .swimming { self.location = .outdoor }
        let pool = poolLengthMeters ?? 25
        self.poolLengthMeters = self.swimmingLocation == .pool && (activity == .swimming || activity == .swimBikeRun)
            ? (pool.isFinite && pool > 0 && pool <= 500 ? pool : 25) : nil
        let validLegs = multisportLegs.filter { [.swimming, .cycling, .running].contains($0) }
        self.multisportLegs = validLegs.count >= 2 && Set(validLegs).count >= 2 ? validLegs : [.swimming, .cycling, .running]
    }

    var normalized: Self {
        Self(activity: activity, location: location, swimmingLocation: swimmingLocation,
             poolLengthMeters: poolLengthMeters, multisportLegs: multisportLegs)
    }
    var displayName: String {
        if activity == .swimming { return "\(swimmingLocation.displayName) Swim" }
        if activity.allowedLocations.count == 2, location != .unknown {
            return "\(location.displayName) \(activity.displayName)"
        }
        return activity.displayName
    }
    var supportsDistance: Bool { activity.supportsDistance }
    var supportsPace: Bool { activity.supportsPace }
    var supportsRoute: Bool {
        location == .outdoor && activity.supportsRoute && (activity != .swimming || swimmingLocation == .openWater)
    }
    var measurement: WorkoutMeasurement { activity.measurement }

    func configuration(forMultisportLeg index: Int) -> Self {
        guard activity == .swimBikeRun, multisportLegs.indices.contains(index) else { return normalized }
        let leg = multisportLegs[index]
        return Self(activity: leg, location: .outdoor, swimmingLocation: swimmingLocation,
                    poolLengthMeters: poolLengthMeters)
    }

    private enum CodingKeys: String, CodingKey {
        case activity, location, swimmingLocation, poolLengthMeters, multisportLegs
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            activity: try container.decodeIfPresent(WorkoutActivity.self, forKey: .activity) ?? .running,
            location: try container.decodeIfPresent(WorkoutLocation.self, forKey: .location),
            swimmingLocation: try container.decodeIfPresent(WorkoutSwimmingLocation.self, forKey: .swimmingLocation),
            poolLengthMeters: try container.decodeIfPresent(Double.self, forKey: .poolLengthMeters),
            multisportLegs: try container.decodeIfPresent([WorkoutActivity].self, forKey: .multisportLegs) ?? [.swimming, .cycling, .running]
        )
    }
}

#if canImport(HealthKit)
extension WorkoutActivity {
    var healthKitActivityType: HKWorkoutActivityType { HKWorkoutActivityType(rawValue: healthKitRawValue) ?? .other }

    var distanceQuantityIdentifier: HKQuantityTypeIdentifier? {
        switch distanceKind {
        case .none: return nil
        case .walkingRunning: return .distanceWalkingRunning
        case .cycling: return .distanceCycling
        case .swimming: return .distanceSwimming
        case .wheelchair: return .distanceWheelchair
        case .downhillSnowSports: return .distanceDownhillSnowSports
        case .crossCountrySkiing:
            if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) { return .distanceCrossCountrySkiing }
        case .rowing:
            if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) { return .distanceRowing }
        case .paddleSports:
            if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) { return .distancePaddleSports }
        case .skatingSports:
            if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) { return .distanceSkatingSports }
        }
        return nil
    }
}

extension WorkoutConfiguration {
    var distanceQuantityIdentifier: HKQuantityTypeIdentifier? { activity.distanceQuantityIdentifier }

    func makeHealthKitConfiguration() -> HKWorkoutConfiguration {
        let safe = normalized
        let result = HKWorkoutConfiguration()
        result.activityType = safe.activity.healthKitActivityType
        switch safe.location {
        case .indoor: result.locationType = .indoor
        case .outdoor: result.locationType = .outdoor
        case .unknown: result.locationType = .unknown
        }
        if safe.activity == .swimming {
            result.swimmingLocationType = safe.swimmingLocation == .pool ? .pool : .openWater
            if safe.swimmingLocation == .pool, let length = safe.poolLengthMeters {
                result.lapLength = HKQuantity(unit: .meter(), doubleValue: length)
            }
        }
        return result
    }

    init(healthKit: HKWorkoutConfiguration) {
        let activity = WorkoutActivity(healthKitRawValue: healthKit.activityType.rawValue) ?? .other
        let location: WorkoutLocation = healthKit.locationType == .outdoor ? .outdoor : healthKit.locationType == .indoor ? .indoor : .unknown
        let swim: WorkoutSwimmingLocation? = healthKit.swimmingLocationType == .pool ? .pool : healthKit.swimmingLocationType == .openWater ? .openWater : nil
        self.init(activity: activity, location: location, swimmingLocation: swim,
                  poolLengthMeters: healthKit.lapLength?.doubleValue(for: .meter()))
    }
}
#endif
