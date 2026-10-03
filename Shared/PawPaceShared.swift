import Foundation

/// Species rarity describes which animal hatches, independently of its coat.
enum PetSpeciesRarity: String, Codable, CaseIterable, Sendable, Hashable {
    case common, rare, mythic

    var displayName: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .common: "pawprint.fill"
        case .rare: "sparkles"
        case .mythic: "star.circle.fill"
        }
    }
}

enum PetSpecies: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case corgi
    case bunny
    case penguin
    case redPanda = "red-panda"
    case fox
    case axolotl
    case dragon
    case unicorn
    case phoenix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .corgi: "Corgi"
        case .bunny: "Bunny"
        case .penguin: "Penguin"
        case .redPanda: "Red panda"
        case .fox: "Fox"
        case .axolotl: "Axolotl"
        case .dragon: "Dragon"
        case .unicorn: "Unicorn"
        case .phoenix: "Phoenix"
        }
    }

    var emoji: String {
        switch self {
        case .corgi: "🐶"
        case .bunny: "🐰"
        case .penguin: "🐧"
        case .redPanda: "🐾"
        case .fox: "🦊"
        case .axolotl: "🫧"
        case .dragon: "🐉"
        case .unicorn: "🦄"
        case .phoenix: "🔥"
        }
    }

    var companionDescription: String {
        switch self {
        case .corgi: "Little legs, big adventures. Always ready for a walk and one more game."
        case .bunny: "A gentle explorer with springy hops and a soft spot for your company."
        case .penguin: "A cheerful trail buddy who brings a playful waddle to every adventure."
        case .redPanda: "A fluffy forest friend with a curious nose and a tail made for leaf-filled tumbles."
        case .fox: "A bright little explorer who turns a playful pounce into a dance with fireflies."
        case .axolotl: "A smiling daydreamer with fluttery gills and a fondness for floating bubbles."
        case .dragon: "A tiny, big-hearted dragon who celebrates your adventures with a warm puff of magic."
        case .unicorn: "A gentle dreamer whose joyful leaps leave a little rainbow in the garden."
        case .phoenix: "A glowing feathered friend who greets every fresh start with a flourish of sparks."
        }
    }

    var rarity: PetSpeciesRarity {
        switch self {
        case .corgi, .bunny, .penguin: .common
        case .redPanda, .fox, .axolotl: .rare
        case .dragon, .unicorn, .phoenix: .mythic
        }
    }

    var specialMoveName: String? {
        switch self {
        case .corgi, .bunny, .penguin: nil
        case .redPanda: "Leaf tumble"
        case .fox: "Firefly pounce"
        case .axolotl: "Bubble dance"
        case .dragon: "Fire breath"
        case .unicorn: "Rainbow leap"
        case .phoenix: "Ember flourish"
        }
    }

    var specialMoveDescription: String? {
        switch self {
        case .corgi, .bunny, .penguin: nil
        case .redPanda: "A playful tumble with a swirl of falling leaves."
        case .fox: "A springy pounce followed by twinkling fireflies."
        case .axolotl: "A happy little dance surrounded by floating bubbles."
        case .dragon: "A proud stretch and a friendly puff of fire."
        case .unicorn: "A joyful leap that paints a rainbow in the air."
        case .phoenix: "A sweeping wing flourish with a trail of warm sparks."
        }
    }
}

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
    var species: PetSpecies = .corgi
    var level: Int
    var experience: Int
    var experienceGoal: Int
    var energy: Int
    var friendship: Int
    var coins: Int
    var streakDays: Int
    var mood: PetMood
    var distanceTodayKilometers: Double
    var dailyWorkoutSeconds: Int = 0
    var distanceDay: Date = .now
    var weeklyDistanceKilometers: Double
    var equippedAccessory: String?
    var equippedDecoration: String?
    var lastUpdated: Date
    // Missing lifecycle means an existing companion: preserve it as grown-up.
    var lifecycle: PetLifecycle? = nil
    var rewardedWorkoutIDs: Set<UUID> = []
    var companionID: UUID = UUID()
    var companionAdultSeconds: Double = 0
    var buddyBond = BuddyBond()
    var journey = CompanionJourney()
    var quests = DailyQuests()

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

    static func newPlayer(seed: UInt64? = nil, at date: Date = .now) -> PetSnapshot {
        let lifecycle = seed.map(PetLifecycle.init(seed:)) ?? PetLifecycle()
        return PetSnapshot(
            name: "Mochi",
            species: lifecycle.species,
            level: 1,
            experience: 0,
            experienceGoal: 600,
            energy: 100,
            friendship: 0,
            coins: 0,
            streakDays: 0,
            mood: .curious,
            distanceTodayKilometers: 0,
            dailyWorkoutSeconds: 0,
            distanceDay: date,
            weeklyDistanceKilometers: 0,
            equippedAccessory: nil,
            equippedDecoration: nil,
            lastUpdated: date,
            lifecycle: lifecycle
        )
    }

    var lifeStage: PetLifeStage { lifecycle?.stage ?? .adult }

    func hasRewardedWorkout(_ workoutID: UUID) -> Bool {
        rewardedWorkoutIDs.contains(workoutID)
    }

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

    var currentDayDistanceKilometers: Double {
        distanceKilometers(on: .now)
    }

    var currentDayWorkoutSeconds: Int { workoutSeconds(on: .now) }
    var currentDayWorkoutMinutes: Int { currentDayWorkoutSeconds / 60 }
    var currentDayMovementMinutes: Int {
        let today = journey.days[CompanionJourney.dayKey(.now)]?.creditedSeconds ?? Double(currentDayWorkoutSeconds)
        return Int(min(PetLifecycle.dailyCreditLimitSeconds, max(0, today)) / 60)
    }

    func workoutSeconds(on date: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(distanceDay, inSameDayAs: date) ? max(dailyWorkoutSeconds, 0) : 0
    }

    func distanceKilometers(on date: Date, calendar: Calendar = .current) -> Double {
        calendar.isDate(distanceDay, inSameDayAs: date) ? max(distanceTodayKilometers, 0) : 0
    }

    var evolutionProgress: Double {
        guard let nextStage else { return 1 }
        let lowerBound = stage.minimumLevel
        let span = max(nextStage.minimumLevel - lowerBound, 1)
        return min(max(Double(level - lowerBound) / Double(span), 0), 1)
    }

    mutating func awardExperience(_ amount: Int, at date: Date = .now) {
        guard amount > 0 else { return }
        experience += amount

        while experience >= experienceGoal {
            experience -= experienceGoal
            level += 1
            experienceGoal = max(600, level * 280)
            mood = .proud
        }
        lastUpdated = date
    }

    mutating func feed(at date: Date = .now) {
        quests.checkIn(at: date)
        if lifeStage != .egg { buddyBond.interact(.calm, at: date) }
        energy = min(100, energy + 14)
        friendship = min(100, friendship + 2)
        mood = .happy
        lastUpdated = date
    }

    mutating func pet(at date: Date = .now) {
        quests.checkIn(at: date)
        if lifeStage != .egg { buddyBond.interact(.calm, at: date) }
        friendship = min(100, friendship + 4)
        mood = .proud
        lastUpdated = date
    }

    mutating func play(at date: Date = .now) {
        quests.checkIn(at: date)
        if lifeStage != .egg { buddyBond.interact(.playful, at: date) }
        energy = max(0, energy - 6)
        friendship = min(100, friendship + 5)
        mood = .excited
        awardExperience(20, at: date)
    }

    mutating func selectSpecies(_ species: PetSpecies, at date: Date = .now) {
        guard lifecycle == nil else { return }
        guard self.species != species else { return }
        self.species = species
        lastUpdated = date
    }

    mutating func applyRun(
        distanceKilometers: Double,
        experienceEarned: Int,
        elapsedSeconds: Int = 0,
        activity: WorkoutActivity = .running,
        workoutID: UUID? = nil,
        at date: Date = .now,
        calendar: Calendar = .current,
        activeIntervals: [DateInterval]? = nil
    ) {
        if let workoutID {
            guard rewardedWorkoutIDs.insert(workoutID).inserted else { return }
        }
        let uniqueSeconds = activeIntervals.map { min(Double(max(0, elapsedSeconds)), journey.consumeWorkoutIntervals($0)) }
            ?? Double(max(0, elapsedSeconds))
        // A copied Health workout may have another UUID but no new active time.
        if activeIntervals != nil, uniqueSeconds <= 0 { return }
        let credited = journey.credit(workoutSeconds: uniqueSeconds,
                                       existingGrowth: lifecycle?.creditedSeconds(on: date, calendar: calendar) ?? 0,
                                       at: date, calendar: calendar)
        applyMovementGrowth(seconds: credited, activity: activity, workoutID: workoutID, at: date, calendar: calendar)
        let fraction = elapsedSeconds > 0 ? uniqueSeconds / Double(elapsedSeconds) : 1
        let elapsedSeconds = Int(uniqueSeconds)
        let experienceEarned = Int(Double(experienceEarned) * fraction)
        let distanceKilometers = distanceKilometers.isFinite ? max(distanceKilometers * fraction, 0) : 0
        distanceTodayKilometers = self.distanceKilometers(on: date, calendar: calendar)
        dailyWorkoutSeconds = workoutSeconds(on: date, calendar: calendar) + max(0, elapsedSeconds)
        distanceDay = date
        distanceTodayKilometers += max(distanceKilometers, 0)
        weeklyDistanceKilometers += max(distanceKilometers, 0)
        energy = max(0, energy - max(Int((distanceKilometers * 5).rounded()), max(0, elapsedSeconds) / 300))
        friendship = min(100, friendship + max(2, max(Int(distanceKilometers * 3), max(0, elapsedSeconds) / 300)))
        coins += max(10, max(Int(distanceKilometers * 35), max(0, elapsedSeconds) / 30))
        mood = distanceKilometers >= 3 || elapsedSeconds >= 1_800 ? .tired : .proud
        awardExperience(experienceEarned, at: date)
        lastUpdated = date
    }
}

extension PetSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        // Keep existing progress when loading snapshots from before animal selection.
        let savedSpecies = try container.decodeIfPresent(String.self, forKey: .species)
        species = savedSpecies.flatMap(PetSpecies.init(rawValue:)) ?? .corgi
        level = try container.decode(Int.self, forKey: .level)
        experience = try container.decode(Int.self, forKey: .experience)
        experienceGoal = try container.decode(Int.self, forKey: .experienceGoal)
        energy = try container.decode(Int.self, forKey: .energy)
        friendship = try container.decode(Int.self, forKey: .friendship)
        coins = try container.decode(Int.self, forKey: .coins)
        streakDays = try container.decode(Int.self, forKey: .streakDays)
        mood = try container.decode(PetMood.self, forKey: .mood)
        distanceTodayKilometers = try container.decode(Double.self, forKey: .distanceTodayKilometers)
        dailyWorkoutSeconds = try container.decodeIfPresent(Int.self, forKey: .dailyWorkoutSeconds) ?? 0
        weeklyDistanceKilometers = try container.decode(Double.self, forKey: .weeklyDistanceKilometers)
        equippedAccessory = try container.decodeIfPresent(String.self, forKey: .equippedAccessory)
        equippedDecoration = try container.decodeIfPresent(String.self, forKey: .equippedDecoration)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        // Older snapshots did not track the run day separately from pet interactions.
        distanceDay = try container.decodeIfPresent(Date.self, forKey: .distanceDay) ?? lastUpdated
        lifecycle = try container.decodeIfPresent(PetLifecycle.self, forKey: .lifecycle)
        rewardedWorkoutIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .rewardedWorkoutIDs) ?? []
        companionID = try container.decodeIfPresent(UUID.self, forKey: .companionID)
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        companionAdultSeconds = try container.decodeIfPresent(Double.self, forKey: .companionAdultSeconds) ?? 0
        buddyBond = try container.decodeIfPresent(BuddyBond.self, forKey: .buddyBond) ?? BuddyBond()
        journey = try container.decodeIfPresent(CompanionJourney.self, forKey: .journey) ?? CompanionJourney()
        quests = try container.decodeIfPresent(DailyQuests.self, forKey: .quests) ?? DailyQuests()
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

    private static let snapshotCreationLock = NSRecursiveLock()
    private static var snapshotFailure: String?
    private static var lastReadableSnapshot: PetSnapshot?

    static var snapshotStorageError: String? {
        snapshotCreationLock.lock()
        defer { snapshotCreationLock.unlock() }
        return snapshotFailure
    }

    static func loadSnapshot() -> PetSnapshot {
        snapshotCreationLock.lock()
        defer { snapshotCreationLock.unlock() }
        do {
            let snapshot = try privateSnapshotStore().loadOrCreate()
            lastReadableSnapshot = snapshot
            snapshotFailure = nil
            return snapshot
        } catch {
            recordSnapshotFailure(error)
            // This unsaved display state never replaces an unreadable save.
            return lastReadableSnapshot ?? .newPlayer(seed: 0, at: Date(timeIntervalSince1970: 0))
        }
    }

    static func loadSnapshotIfPresent() -> PetSnapshot? {
        snapshotCreationLock.lock()
        defer { snapshotCreationLock.unlock() }
        do {
            let snapshot = try privateSnapshotStore().loadIfPresent()
            if let snapshot { lastReadableSnapshot = snapshot }
            snapshotFailure = nil
            return snapshot
        } catch {
            recordSnapshotFailure(error)
            return lastReadableSnapshot
        }
    }

    @discardableResult
    static func saveSnapshot(_ snapshot: PetSnapshot) -> Bool {
        snapshotCreationLock.lock()
        defer { snapshotCreationLock.unlock() }
        do {
            try privateSnapshotStore().save(snapshot)
            lastReadableSnapshot = snapshot
            snapshotFailure = nil
            postSnapshotChanged()
            return true
        } catch {
            recordSnapshotFailure(error)
            return false
        }
    }

    /// Load and mutate under one shared-file transaction so a widget interaction
    /// cannot replace a more recent workout save from the phone.
    static func updateSnapshot(_ update: (inout PetSnapshot) -> Void) -> PetSnapshot? {
        snapshotCreationLock.lock()
        defer { snapshotCreationLock.unlock() }
        do {
            let snapshot = try privateSnapshotStore().update(update)
            lastReadableSnapshot = snapshot
            snapshotFailure = nil
            postSnapshotChanged()
            return snapshot
        } catch {
            recordSnapshotFailure(error)
            return nil
        }
    }

    private static func privateSnapshotStore() throws -> PawPaceSnapshotStore {
        PawPaceSnapshotStore(storage: try PawPacePrivateStorage.shared(), legacyDefaults: defaults)
    }

    private static func recordSnapshotFailure(_ error: Error) {
        snapshotFailure = "Your companion could not be saved or opened. Your existing data has been kept. Unlock your device and try again."
    }

    // Explicit preferences injection keeps legacy storage fixtures isolated;
    // shipping call sites use the private-file overloads above.
    static func loadSnapshot(from defaults: UserDefaults) -> PetSnapshot {
        snapshotCreationLock.lock()
        defer { snapshotCreationLock.unlock() }
        if let snapshot = loadSnapshotIfPresent(from: defaults) { return snapshot }
        let snapshot = PetSnapshot.newPlayer()
        saveSnapshot(snapshot, to: defaults)
        return snapshot
    }

    static func loadSnapshotIfPresent(
        from defaults: UserDefaults
    ) -> PetSnapshot? {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(PetSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: PetSnapshot, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    private static func postSnapshotChanged() {
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
        in defaults: UserDefaults
    ) -> Bool {
        defaults.stringArray(forKey: rewardedWorkoutIDsKey)?.contains(workoutID.uuidString) == true
    }

    static func hasRegisteredReward(for workoutID: UUID) -> Bool {
        hasRegisteredReward(for: workoutID, in: defaults)
            || loadSnapshotIfPresent()?.hasRewardedWorkout(workoutID) == true
    }
}

extension Notification.Name {
    static let pawPaceToggleRun = Notification.Name("PawPace.ToggleRun")
}
