import Foundation

struct QuestGift: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case daily, weekly }
    let id: String
    let kind: Kind
    let earnedAt: Date
    var openedAt: Date?
    var decoration: HabitatDecoration?
    var isEgg = false
    var title: String { openedAt == nil ? "A little surprise" : decoration?.rawValue ?? "A mystery egg" }
}

/// Family-wide evidence and rewards; never reset when switching companions.
struct DailyQuests: Codable, Equatable, Sendable {
    var beganAt: Date = .now
    var checkIns: [String: Date] = [:]
    var playDays: Set<String> = []
    var gifts: [QuestGift] = []

    mutating func checkIn(at date: Date, calendar: Calendar = .current) {
        checkIns[CompanionJourney.dayKey(date, calendar: calendar)] = calendar.startOfDay(for: date)
    }

    func qualifyingDays(journey: CompanionJourney, at date: Date, calendar: Calendar = .current) -> Set<Date> {
        let start = calendar.startOfDay(for: beganAt), end = calendar.startOfDay(for: date)
        return Set((Array(checkIns.values) + journey.days.values.filter { $0.creditedSeconds >= 300 }.map(\.date))
            .map { calendar.startOfDay(for: $0) }.filter { $0 >= start && $0 <= end })
    }

    func qualifyingWeeks(journey: CompanionJourney, at date: Date, calendar: Calendar = .current) -> Set<Date> {
        let start = CompanionJourney.weekStart(beganAt, calendar: calendar)
        let weeks = Set(journey.days.values.filter { $0.date <= date }.map { CompanionJourney.weekStart($0.date, calendar: calendar) })
        return Set(weeks.filter { $0 >= start && journey.activeDays(inWeekOf: $0, calendar: calendar) >= journey.target(inWeekOf: $0, calendar: calendar) })
    }

    static func streak(_ dates: Set<Date>, endingAt date: Date, step: Int = 1, calendar: Calendar = .current) -> Int {
        var cursor = date
        if !dates.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -step, to: cursor) ?? cursor }
        var count = 0
        while dates.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -step, to: cursor), previous < cursor else { break }
            cursor = previous
        }
        return count
    }

    func currentStreak(journey: CompanionJourney, at date: Date, calendar: Calendar = .current) -> Int {
        Self.streak(qualifyingDays(journey: journey, at: date, calendar: calendar), endingAt: calendar.startOfDay(for: date), calendar: calendar)
    }
    func bestStreak(journey: CompanionJourney, at date: Date, calendar: Calendar = .current) -> Int {
        let dates = qualifyingDays(journey: journey, at: date, calendar: calendar).sorted()
        var best = 0, length = 0, previous: Date?
        for day in dates {
            length = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day ? length + 1 : 1
            best = max(best, length); previous = day
        }
        return best
    }

    mutating func prepareGifts(journey: CompanionJourney, at date: Date, calendar: Calendar = .current) {
        for (kind, dates) in [(QuestGift.Kind.daily, qualifyingDays(journey: journey, at: date, calendar: calendar)),
                              (.weekly, qualifyingWeeks(journey: journey, at: date, calendar: calendar))] {
            for earnedAt in dates.sorted() {
                let id = "\(kind.rawValue)-\(CompanionJourney.dayKey(earnedAt, calendar: calendar))"
                if !gifts.contains(where: { $0.id == id }) { gifts.append(QuestGift(id: id, kind: kind, earnedAt: earnedAt)) }
            }
        }
    }
}

extension PetSnapshot {
    /// Randomness is consumed inside the same durable snapshot mutation as the
    /// unlock. An opened gift retains its result and can never award twice.
    @discardableResult
    mutating func openQuestGift(_ id: String, at date: Date = .now, roll: Int = Int.random(in: 0..<100),
                               selection: UInt64 = UInt64.random(in: .min ... .max)) -> QuestGift? {
        quests.prepareGifts(journey: journey, at: date)
        guard let index = quests.gifts.firstIndex(where: { $0.id == id }) else { return nil }
        if quests.gifts[index].openedAt != nil { return quests.gifts[index] }
        let available = HabitatDecoration.allCases.filter { !journey.unlockedDecorations.contains($0.rawValue) }
        let eggChance = quests.gifts[index].kind == .daily ? 15 : 35
        if roll < eggChance || available.isEmpty {
            journey.waitingEggs.append(PetLifecycle(seed: selection))
            quests.gifts[index].isEgg = true
        } else {
            let decoration = available[Int(selection % UInt64(available.count))]
            journey.unlockedDecorations.insert(decoration.rawValue)
            quests.gifts[index].decoration = decoration
        }
        quests.gifts[index].openedAt = date
        return quests.gifts[index]
    }
}
