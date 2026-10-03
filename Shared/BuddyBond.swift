import Foundation

enum BuddyTemperament: String, Codable, CaseIterable, Sendable {
    case curious, playful, calm
    var title: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .curious: "Always looking for one more little thing to investigate."
        case .playful: "A spring in every step, especially when a toy is nearby."
        case .calm: "Happiest taking things slowly and spending quiet time with you."
        }
    }
    var symbol: String {
        switch self { case .curious: "leaf"; case .playful: "tennisball"; case .calm: "moon.stars" }
    }
}

enum BuddyGame: String, Codable, CaseIterable, Identifiable, Sendable {
    case fetch, hideAndSeek, trickTrail
    var id: String { rawValue }
    var title: String {
        switch self { case .fetch: "Little fetch"; case .hideAndSeek: "Hide & seek"; case .trickTrail: "Trick trail" }
    }
    var symbol: String {
        switch self { case .fetch: "tennisball"; case .hideAndSeek: "leaf"; case .trickTrail: "sparkles" }
    }
    var detail: String {
        switch self {
        case .fetch: "Aim for the soft circles. Your friend will bring the ball back."
        case .hideAndSeek: "Look for your friend, then remember their hiding place."
        case .trickTrail: "Learn a little sequence and practice it together."
        }
    }
    var affinity: BuddyTemperament {
        switch self { case .fetch: .playful; case .hideAndSeek: .curious; case .trickTrail: .calm }
    }
}

enum BuddyTrick: String, Codable, CaseIterable, Sendable {
    case hop, bow, wiggle
    var title: String { switch self { case .hop: "Hop"; case .bow: "Play bow"; case .wiggle: "Wiggle" } }
    var symbol: String { switch self { case .hop: "arrow.up"; case .bow: "heart"; case .wiggle: "sparkles" } }
}

/// Per-companion attachment, deliberately independent from movement and rarity.
/// Defaults make existing companions compatible without inventing a history.
struct BuddyBond: Codable, Equatable, Sendable {
    var firstOutingAt: Date?
    var firstHopAt: Date?
    var firstDanceAt: Date?
    var curiosity = 0
    var playfulness = 0
    var calmness = 0
    var favoriteGameCounts: [String: Int] = [:]
    var completedSessions: Set<UUID> = []
    var learnedSequences = 0
    var learnedRoutine: [BuddyTrick]?
    var lastInteractionAt: Date?
    var firstGameDates: [String: Date] = [:]

    static func seed(for id: UUID) -> UInt64 {
        id.uuidString.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    func temperament(for id: UUID) -> BuddyTemperament {
        let seed = Self.seed(for: id)
        let scores: [(BuddyTemperament, Int)] = [
            (.curious, Int(seed % 5) + curiosity),
            (.playful, Int((seed >> 8) % 5) + playfulness),
            (.calm, Int((seed >> 16) % 5) + calmness)
        ]
        return scores.max { $0.1 < $1.1 }!.0
    }

    func favoriteGame(for id: UUID) -> BuddyGame {
        let mostPlayed = BuddyGame.allCases.max { favoriteGameCounts[$0.rawValue, default: 0] < favoriteGameCounts[$1.rawValue, default: 0] }
        if let mostPlayed, favoriteGameCounts[mostPlayed.rawValue, default: 0] > 0 { return mostPlayed }
        return BuddyGame.allCases[Int(Self.seed(for: id) % UInt64(BuddyGame.allCases.count))]
    }

    mutating func interact(_ trait: BuddyTemperament, at date: Date) {
        // Repeated tapping never rapidly rewrites a companion's personality.
        guard lastInteractionAt.map({ date.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastInteractionAt = date
        add(trait)
    }

    @discardableResult
    mutating func complete(_ session: BuddyPlaySession, at date: Date) -> Bool {
        guard session.phase == .finished, session.round == 3, completedSessions.insert(session.id).inserted else { return false }
        favoriteGameCounts[session.game.rawValue] = min(10_000, favoriteGameCounts[session.game.rawValue, default: 0] + 1)
        if firstGameDates[session.game.rawValue] == nil { firstGameDates[session.game.rawValue] = date }
        if session.game == .trickTrail {
            learnedSequences = min(10_000, learnedSequences + 1)
            learnedRoutine = session.sequence
        }
        add(session.game.affinity)
        return true
    }

    private mutating func add(_ trait: BuddyTemperament) {
        // Gentle adaptation retains room for preferences to change over time.
        if max(curiosity, playfulness, calmness) >= 24 {
            curiosity /= 2; playfulness /= 2; calmness /= 2
        }
        switch trait { case .curious: curiosity += 1; case .playful: playfulness += 1; case .calm: calmness += 1 }
    }
}

/// Testable input rules. No wall-clock deadlines, fitness rewards or lost lives.
struct BuddyPlaySession: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case memorizing, playing, celebrating, finished }
    enum Feedback: Equatable, Sendable { case ignored, tryAgain, progress, found }
    let id: UUID
    let companionID: UUID
    let game: BuddyGame
    private(set) var phase: Phase
    private(set) var round = 0
    private(set) var sequenceIndex = 0
    private(set) var checkedSpots: Set<Int> = []
    private(set) var attempts = 0
    private let seed: UInt64

    init(game: BuddyGame, companionID: UUID, id: UUID = UUID()) {
        self.game = game; self.companionID = companionID; self.id = id
        seed = BuddyBond.seed(for: id)
        phase = game == .fetch ? .playing : .memorizing
    }

    var target: (x: Double, y: Double) {
        let value = seed &+ UInt64(displayRound) &* 17
        return (0.22 + Double(value % 57) / 100, 0.20 + Double((value >> 8) % 31) / 100)
    }
    private var displayRound: Int { phase == .celebrating || phase == .finished ? max(0, round - 1) : round }
    var hidingSpot: Int { Int((seed &+ UInt64(displayRound)) % 4) }
    var sequence: [BuddyTrick] {
        (0..<3).map { BuddyTrick.allCases[Int((seed &+ UInt64($0 + displayRound)) % 3)] }
    }

    mutating func ready() {
        guard phase == .memorizing else { return }
        sequenceIndex = 0; checkedSpots = []; phase = .playing
    }

    mutating func lookAgain() {
        guard phase == .playing, game != .fetch else { return }
        sequenceIndex = 0; checkedSpots = []; phase = .memorizing
    }

    @discardableResult mutating func throwBall(x: Double, y: Double) -> Feedback {
        guard game == .fetch, phase == .playing, x.isFinite, y.isFinite,
              (0...1).contains(x), (0...1).contains(y) else { return .ignored }
        attempts += 1
        guard hypot(x - target.x, y - target.y) <= 0.16 else { return .tryAgain }
        return finishRound()
    }

    @discardableResult mutating func search(_ spot: Int) -> Feedback {
        guard game == .hideAndSeek, phase == .playing, (0..<4).contains(spot),
              checkedSpots.insert(spot).inserted else { return .ignored }
        attempts += 1
        guard spot == hidingSpot else { return .tryAgain }
        return finishRound()
    }

    @discardableResult mutating func perform(_ trick: BuddyTrick) -> Feedback {
        guard game == .trickTrail, phase == .playing else { return .ignored }
        attempts += 1
        guard sequence[sequenceIndex] == trick else { sequenceIndex = 0; return .tryAgain }
        sequenceIndex += 1
        return sequenceIndex == sequence.count ? finishRound() : .progress
    }

    mutating func continuePlaying() {
        guard phase == .celebrating else { return }
        sequenceIndex = 0; checkedSpots = []
        phase = game == .fetch ? .playing : .memorizing
    }

    private mutating func finishRound() -> Feedback {
        round += 1
        phase = round == 3 ? .finished : .celebrating
        return .found
    }
}

extension PetSnapshot {
    var temperament: BuddyTemperament { buddyBond.temperament(for: companionID) }
    var favoriteGame: BuddyGame { buddyBond.favoriteGame(for: companionID) }

    @discardableResult mutating func completeBuddyGame(_ session: BuddyPlaySession, at date: Date = .now) -> Bool {
        guard lifeStage != .egg, session.companionID == companionID, buddyBond.complete(session, at: date) else { return false }
        quests.checkIn(at: date)
        quests.playDays.insert(CompanionJourney.dayKey(date))
        friendship = min(100, friendship + 3)
        mood = .happy
        lastUpdated = date
        return true
    }
}
