import Foundation

enum PetMood: String, Codable, CaseIterable, Sendable, Hashable {
    case happy
    case excited
    case hungry
    case tired
    case proud
    case curious
    case sleepy

    var label: String {
        rawValue.capitalized
    }

    var shortMessage: String {
        switch self {
        case .happy: "Morning! I already stretched. Twice."
        case .excited: "My tail is charged. Adventure time!"
        case .hungry: "A tiny snack would unlock maximum zoomies."
        case .tired: "That was a legendary run. Nap formation!"
        case .proud: "Look at us—another quest complete."
        case .curious: "Do you think the next trail has treasure?"
        case .sleepy: "Five more minutes, then we explore."
        }
    }
}

enum EvolutionStage: Int, Codable, CaseIterable, Sendable, Hashable {
    case sprout = 1
    case kitsora = 2
    case volaki = 3

    var displayName: String {
        switch self {
        case .sprout: "Sprout"
        case .kitsora: "Kitsora"
        case .volaki: "Volaki"
        }
    }

    var minimumLevel: Int {
        switch self {
        case .sprout: 1
        case .kitsora: 10
        case .volaki: 25
        }
    }
}

struct PetSnapshot: Codable, Equatable, Sendable {
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
    var equippedDecoration: String?
    var lastUpdated: Date

    static let starter = PetSnapshot(
        name: "Mochi",
        level: 9,
        experience: 1_840,
        experienceGoal: 2_400,
        energy: 82,
        friendship: 68,
        coins: 1_240,
        streakDays: 12,
        mood: .happy,
        distanceTodayKilometers: 1.8,
        weeklyDistanceKilometers: 6.8,
        equippedAccessory: "Trail Scarf",
        equippedDecoration: "Flower Meadow",
        lastUpdated: .now
    )

    var activeDecoration: String {
        equippedDecoration ?? "Flower Meadow"
    }

    var stage: EvolutionStage {
        if level >= EvolutionStage.volaki.minimumLevel { return .volaki }
        if level >= EvolutionStage.kitsora.minimumLevel { return .kitsora }
        return .sprout
    }

    var nextStage: EvolutionStage? {
        switch stage {
        case .sprout: .kitsora
        case .kitsora: .volaki
        case .volaki: nil
        }
    }

    var experienceProgress: Double {
        guard experienceGoal > 0 else { return 0 }
        return min(max(Double(experience) / Double(experienceGoal), 0), 1)
    }

    var evolutionProgress: Double {
        guard let nextStage else { return 1 }
        let lowerBound = stage.minimumLevel
        let span = max(nextStage.minimumLevel - lowerBound, 1)
        return min(max(Double(level - lowerBound) / Double(span), 0), 1)
    }

    mutating func awardExperience(_ amount: Int) {
        guard amount > 0 else { return }
        experience += amount

        while experience >= experienceGoal {
            experience -= experienceGoal
            level += 1
            experienceGoal = max(600, level * 280)
            mood = .proud
        }
        lastUpdated = .now
    }

    mutating func feed() {
        energy = min(100, energy + 14)
        friendship = min(100, friendship + 2)
        mood = .happy
        lastUpdated = .now
    }

    mutating func pet() {
        friendship = min(100, friendship + 4)
        mood = .proud
        lastUpdated = .now
    }

    mutating func play() {
        energy = max(0, energy - 6)
        friendship = min(100, friendship + 5)
        mood = .excited
        awardExperience(20)
    }

    mutating func applyRun(distanceKilometers: Double, experienceEarned: Int) {
        distanceTodayKilometers += max(distanceKilometers, 0)
        weeklyDistanceKilometers += max(distanceKilometers, 0)
        energy = max(0, energy - Int((distanceKilometers * 5).rounded()))
        friendship = min(100, friendship + max(2, Int(distanceKilometers * 3)))
        coins += max(10, Int(distanceKilometers * 35))
        mood = distanceKilometers >= 3 ? .tired : .proud
        awardExperience(experienceEarned)
    }
}

enum PawPaceShared {
    static let suiteName = "group.com.pawpace.shared"
    static let snapshotKey = "pawpace.pet.snapshot.v1"
    static let runPausedKey = "pawpace.run.isPaused"
    static let rewardedWorkoutIDsKey = "pawpace.run.rewardedWorkoutIDs"
    static let snapshotChangedDarwinName = "com.pawpace.pet-snapshot-changed"

    static var defaults: UserDefaults {
#if os(watchOS)
        .standard
#else
        UserDefaults(suiteName: suiteName) ?? .standard
#endif
    }

    static func loadSnapshot() -> PetSnapshot {
        loadSnapshotIfPresent() ?? .starter
    }

    static func loadSnapshotIfPresent(
        from defaults: UserDefaults = PawPaceShared.defaults
    ) -> PetSnapshot? {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(PetSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: PetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
#if !os(watchOS)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(snapshotChangedDarwinName as CFString),
            nil,
            nil,
            true
        )
#endif
    }

    @discardableResult
    static func registerReward(
        for workoutID: UUID,
        in defaults: UserDefaults = PawPaceShared.defaults
    ) -> Bool {
        var rewardedIDs = defaults.stringArray(forKey: rewardedWorkoutIDsKey) ?? []
        let identifier = workoutID.uuidString
        guard !rewardedIDs.contains(identifier) else { return false }

        rewardedIDs.append(identifier)
        defaults.set(rewardedIDs, forKey: rewardedWorkoutIDsKey)
        return true
    }

    static func hasRegisteredReward(
        for workoutID: UUID,
        in defaults: UserDefaults = PawPaceShared.defaults
    ) -> Bool {
        defaults.stringArray(forKey: rewardedWorkoutIDsKey)?.contains(workoutID.uuidString) == true
    }
}

extension Notification.Name {
    static let pawPaceToggleRun = Notification.Name("PawPace.ToggleRun")
}
