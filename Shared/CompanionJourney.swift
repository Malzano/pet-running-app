import Foundation

enum AdventureTrail: String, Codable, CaseIterable, Identifiable, Sendable {
    case meadow, lantern, camp
    var id: String { rawValue }
    var title: String {
        switch self { case .meadow: "The winding trail"; case .lantern: "An evening of lights"; case .camp: "A cozy clearing" }
    }
    var symbol: String {
        switch self { case .meadow: "flag"; case .lantern: "sparkles"; case .camp: "tent" }
    }
    var seconds: Double {
        switch self { case .meadow: 3_600; case .lantern: 7_200; case .camp: 10_800 }
    }
    var decoration: String {
        switch self { case .meadow: "Trail Flags"; case .lantern: "Star Lanterns"; case .camp: "Camp Glow" }
    }
    var story: String {
        switch self {
        case .meadow: "Your friend followed a fluttering ribbon all the way home. Little flags now mark the adventures you share."
        case .lantern: "As the sky grew quiet, your friend found a trail of tiny lights. You brought their warm glow home together."
        case .camp: "Past the last bend was a clearing made for resting. Your friend curled up beside you, happy just to be together."
        }
    }
}

struct CompanionResident: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var species: PetSpecies
    var lifecycle: PetLifecycle?
    var friendship: Int
    var energy: Int
    var mood: PetMood
    var accessory: String?
    var adultSeconds: Double
    var buddyBond: BuddyBond?
    var stage: PetLifeStage { lifecycle?.stage ?? .adult }

    init(_ pet: PetSnapshot) {
        id = pet.companionID; name = pet.name; species = pet.species; lifecycle = pet.lifecycle
        friendship = pet.friendship; energy = pet.energy; mood = pet.mood
        accessory = pet.equippedAccessory; adultSeconds = pet.companionAdultSeconds
        buddyBond = pet.buddyBond
    }
}

struct AdventureMemory: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let trail: AdventureTrail
    let companionName: String
    let date: Date
    var companionID: UUID? = nil
    var branch: AdventureBranch? = nil
    var story: String { branch?.story ?? trail.story }
    var decoration: String { branch?.decoration.rawValue ?? trail.decoration }
}

struct JourneyDay: Codable, Equatable, Sendable {
    var date: Date
    var workoutSeconds: Double = 0
    var steps: Double = 0
    var creditedSeconds: Double = 0
    var stepContributions: [String: Double]?
}

/// Family-wide, durable reward accounting. Steps use a game conversion, not a
/// physiological estimate: 100 steps = one progress minute. The larger daily
/// total wins, so step samples never add a second reward for recorded workouts.
struct CompanionJourney: Codable, Equatable, Sendable {
    static let eggSeconds: Double = 180 * 60
    var residents: [CompanionResident] = []
    var waitingEggs: [PetLifecycle] = []
    var eggProgressSeconds: Double = 0
    var activeTrail: AdventureTrail?
    var trailSeconds: Double = 0
    var expedition: ExpeditionProgress?
    var habitatPlacements: [HabitatPlacement]?
    var memories: [AdventureMemory] = []
    var unlockedDecorations: Set<String> = []
    var weeklyTargetDays: Int = 3
    // Targets already begun cannot be lowered to claim another reward.
    var weekTargets: [String: Int] = [:]
    var celebratedWeeks: Set<String> = []
    var weeklyKeepsakes: Int = 0
    var days: [String: JourneyDay] = [:]
    var workoutIntervals: [DateInterval] = []

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    static func weekStart(_ date: Date, calendar: Calendar = .current) -> Date {
        var monday = calendar
        monday.firstWeekday = 2
        monday.minimumDaysInFirstWeek = 4
        return monday.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    func activeDays(inWeekOf date: Date, calendar: Calendar = .current) -> Int {
        let start = Self.weekStart(date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return days.values.filter { $0.date >= start && $0.date < end && $0.creditedSeconds >= 300 }.count
    }

    func target(inWeekOf date: Date, calendar: Calendar = .current) -> Int {
        weekTargets[Self.dayKey(Self.weekStart(date, calendar: calendar), calendar: calendar)] ?? weeklyTargetDays
    }

    mutating func chooseWeeklyTarget(_ target: Int, at date: Date, calendar: Calendar = .current) {
        guard (2...5).contains(target) else { return }
        weeklyTargetDays = target
        let key = Self.dayKey(Self.weekStart(date, calendar: calendar), calendar: calendar)
        if activeDays(inWeekOf: date, calendar: calendar) == 0 && !celebratedWeeks.contains(key) {
            weekTargets[key] = target
        }
    }

    /// Both newly delivered and overlapping imported workouts use this union.
    /// UUID deduplication remains in PetSnapshot; time overlap covers copies
    /// saved by different apps under different UUIDs.
    mutating func consumeWorkoutIntervals(_ incoming: [DateInterval]) -> Double {
        let previous = Self.union(workoutIntervals)
        let combined = Self.union(previous + incoming)
        let additional = max(0, combined.reduce(0) { $0 + $1.duration } - previous.reduce(0) { $0 + $1.duration })
        workoutIntervals = combined
        return additional
    }

    static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter {
            $0.start.timeIntervalSinceReferenceDate.isFinite && $0.end.timeIntervalSinceReferenceDate.isFinite && $0.duration > 0
        }.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else { result.append(interval) }
        }
        return result
    }

    mutating func credit(workoutSeconds: Double = 0, steps: Double? = nil, stepEpoch: String? = nil, existingGrowth: Double = 0,
                         at date: Date, calendar: Calendar = .current) -> Double {
        guard date.timeIntervalSinceReferenceDate.isFinite, workoutSeconds.isFinite, workoutSeconds >= 0,
              steps.map({ $0.isFinite && $0 >= 0 }) ?? true else { return 0 }
        let key = Self.dayKey(date, calendar: calendar)
        var day = days[key] ?? JourneyDay(date: calendar.startOfDay(for: date), workoutSeconds: existingGrowth, creditedSeconds: existingGrowth)
        // Migration preserves already-earned growth on the day of the update.
        day.creditedSeconds = max(day.creditedSeconds, existingGrowth)
        day.workoutSeconds += workoutSeconds
        if let steps {
            if let stepEpoch {
                var contributions = day.stepContributions ?? (day.steps > 0 ? ["legacy": day.steps] : [:])
                contributions[stepEpoch] = max(contributions[stepEpoch, default: 0], steps)
                day.stepContributions = contributions
                day.steps = contributions.values.reduce(0, +)
            } else { day.steps = max(day.steps, steps) }
        }
        let entitled = min(PetLifecycle.dailyCreditLimitSeconds, max(day.workoutSeconds, day.steps * 0.6))
        let added = max(0, entitled - day.creditedSeconds)
        day.creditedSeconds += added
        days[key] = day
        if day.creditedSeconds >= 300 {
            let weekKey = Self.dayKey(Self.weekStart(date, calendar: calendar), calendar: calendar)
            if weekTargets[weekKey] == nil { weekTargets[weekKey] = weeklyTargetDays }
            if activeDays(inWeekOf: date, calendar: calendar) >= target(inWeekOf: date, calendar: calendar),
               celebratedWeeks.insert(weekKey).inserted { weeklyKeepsakes += 1 }
        }
        return added
    }

    mutating func explore(seconds: Double, name: String, companionID: UUID? = nil, at date: Date) {
        guard seconds.isFinite, seconds > 0 else { return }
        eggProgressSeconds += seconds
        while eggProgressSeconds >= Self.eggSeconds {
            waitingEggs.append(PetLifecycle())
            eggProgressSeconds -= Self.eggSeconds
        }
        if let trail = activeTrail {
            trailSeconds = min(trail.seconds, trailSeconds + seconds)
            finishExpeditionIfReady(name: name, companionID: companionID, at: date)
        }
    }

    mutating func finishExpeditionIfReady(name: String, companionID: UUID?, at date: Date) {
        guard let trail = activeTrail, trailSeconds >= trail.seconds,
              expedition == nil || expedition?.branch != nil else { return }
        let memory = AdventureMemory(id: expedition?.id ?? UUID(), trail: trail, companionName: name,
                                     date: date, companionID: companionID, branch: expedition?.branch)
        if !memories.contains(where: { $0.id == memory.id }) { memories.append(memory) }
        unlockedDecorations.insert(memory.decoration)
        activeTrail = nil
        trailSeconds = 0
        expedition = nil
    }
}

extension PetSnapshot {
    var hasYoungCompanion: Bool { lifeStage != .adult || journey.residents.contains { $0.stage != .adult } }

    mutating func beginNextEgg(at date: Date = .now) {
        guard !hasYoungCompanion, !journey.waitingEggs.isEmpty else { return }
        journey.residents.append(CompanionResident(self))
        let egg = journey.waitingEggs.removeFirst()
        companionID = UUID(); name = "Little one"; species = egg.species; lifecycle = egg
        friendship = 0; energy = 100; mood = .curious; equippedAccessory = nil; companionAdultSeconds = 0
        buddyBond = BuddyBond()
        lastUpdated = date
    }

    mutating func visitCompanion(_ id: UUID, at date: Date = .now) {
        guard let index = journey.residents.firstIndex(where: { $0.id == id }) else { return }
        let resident = journey.residents[index]
        journey.residents[index] = CompanionResident(self)
        companionID = resident.id; name = resident.name; species = resident.species; lifecycle = resident.lifecycle
        friendship = resident.friendship; energy = resident.energy; mood = resident.mood
        equippedAccessory = resident.accessory; companionAdultSeconds = resident.adultSeconds
        buddyBond = resident.buddyBond ?? BuddyBond()
        lastUpdated = date
    }

    mutating func applyMovementGrowth(seconds: Double, activity: WorkoutActivity, workoutID: UUID? = nil,
                                      at date: Date, calendar: Calendar = .current) {
        guard seconds > 0 else { return }
        if lifeStage != .egg, date >= (lifecycle?.hatchedAt ?? .distantPast) {
            buddyBond.firstOutingAt = min(buddyBond.firstOutingAt ?? date, date)
        }
        let grown = lifecycle?.creditWorkout(activity: activity, activeSeconds: seconds, workoutID: workoutID,
                                             at: date, calendar: calendar) ?? 0
        if lifeStage == .adult {
            let adultSeconds = max(0, seconds - grown)
            let previous = companionAdultSeconds
            companionAdultSeconds += adultSeconds
            if previous < 3_600, companionAdultSeconds >= 3_600 { buddyBond.firstHopAt = date }
            if previous < 10_800, companionAdultSeconds >= 10_800 { buddyBond.firstDanceAt = date }
            journey.explore(seconds: adultSeconds, name: name, companionID: companionID, at: date)
        }
        lastUpdated = date
    }

    mutating func applyDailySteps(_ steps: Double, at date: Date, calendar: Calendar = .current, epoch: String? = nil) {
        let credit = journey.credit(steps: steps, stepEpoch: epoch, existingGrowth: lifecycle?.creditedSeconds(on: date, calendar: calendar) ?? 0,
                                    at: date, calendar: calendar)
        applyMovementGrowth(seconds: credit, activity: .walking, at: date, calendar: calendar)
    }
}
