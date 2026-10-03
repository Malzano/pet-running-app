import Foundation

enum AdventureBranch: String, Codable, CaseIterable, Identifiable, Sendable {
    case ribbons, stream, stars, fireflies, campfire, clouds
    var id: String { rawValue }
    var trail: AdventureTrail {
        switch self { case .ribbons, .stream: .meadow; case .stars, .fireflies: .lantern; case .campfire, .clouds: .camp }
    }
    var title: String {
        switch self {
        case .ribbons: "Follow the fluttering ribbons"
        case .stream: "Listen for the little stream"
        case .stars: "Climb toward the open sky"
        case .fireflies: "Follow the lights in the grass"
        case .campfire: "Gather around the warm glow"
        case .clouds: "Rest where the clouds drift by"
        }
    }
    var story: String {
        switch self {
        case .ribbons: "A breeze carried a ribbon around the bend. Your friend followed it home, and little flags now remember the way."
        case .stream: "You followed the sound of water to a quiet stream. Your friend chose a few smooth pebbles for a tiny garden at home."
        case .stars: "At the top of the hill, the whole sky opened up. You made a little lantern to remember the stars you watched together."
        case .fireflies: "Tiny lights danced above the grass. You left the fireflies free and made a glowing jar to remember their dance."
        case .campfire: "In a sheltered clearing, you shared a warm, quiet evening. A little camp light brings that cozy feeling home."
        case .clouds: "You lay in the grass and watched clouds become a hundred different shapes. A soft cushion is now your friend’s favorite place to daydream."
        }
    }
    var decoration: HabitatDecoration {
        switch self { case .ribbons: .flags; case .stream: .pebbles; case .stars: .lanterns; case .fireflies: .glowJar; case .campfire: .campGlow; case .clouds: .cushion }
    }
}

struct ExpeditionProgress: Codable, Equatable, Sendable {
    var id = UUID()
    var branch: AdventureBranch?
}

enum HabitatDecoration: String, Codable, CaseIterable, Identifiable, Sendable {
    case flags = "Trail Flags", pebbles = "Pebble Garden", lanterns = "Star Lanterns"
    case glowJar = "Glow Jar", campGlow = "Camp Glow", cushion = "Cloud Cushion"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .flags: "flag.fill"; case .pebbles: "circle.grid.2x2.fill"; case .lanterns: "star.fill"; case .glowJar: "lightbulb.fill"; case .campGlow: "flame.fill"; case .cushion: "cloud.fill" }
    }
    var reaction: String {
        switch self {
        case .flags: "A happy hop for the fluttering flags."
        case .pebbles: "A quiet moment beside the pebble garden."
        case .lanterns: "A little hop beneath the stars."
        case .glowJar: "Watching the gentle glow together."
        case .campGlow: "Settling beside the cozy camp light."
        case .cushion: "A soft spot for a little daydream."
        }
    }
    var isPlayful: Bool { self == .flags || self == .lanterns }
}

enum HabitatSpot: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, right, back
    var id: String { rawValue }
    var title: String { switch self { case .left: "Left nook"; case .right: "Right nook"; case .back: "Back nook" } }
    // Objects stay outside the walkable ellipse. Companions approach its edge.
    var x: Float { switch self { case .left: -1.65; case .right: 1.65; case .back: 0 } }
    var z: Float { switch self { case .left, .right: -0.20; case .back: -1.30 } }
}

struct HabitatPlacement: Codable, Equatable, Identifiable, Sendable {
    var spot: HabitatSpot
    var decoration: HabitatDecoration
    var id: String { spot.id }
}

extension PetSnapshot {
    var availableDecorations: [HabitatDecoration] {
        HabitatDecoration.allCases.filter { journey.unlockedDecorations.contains($0.rawValue) }
    }
    var habitatPlacements: [HabitatPlacement] {
        if let saved = journey.habitatPlacements {
            var seenSpots = Set<HabitatSpot>(), seenItems = Set<HabitatDecoration>()
            return saved.filter {
                availableDecorations.contains($0.decoration) && seenSpots.insert($0.spot).inserted && seenItems.insert($0.decoration).inserted
            }
        }
        // Keep an old equipped keepsake visible without inventing an unlock.
        if let item = HabitatDecoration(rawValue: activeDecoration), availableDecorations.contains(item) {
            return [HabitatPlacement(spot: .back, decoration: item)]
        }
        return []
    }

    @discardableResult
    mutating func placeDecoration(_ item: HabitatDecoration?, at spot: HabitatSpot) -> Bool {
        guard item.map({ availableDecorations.contains($0) }) ?? true else { return false }
        var layout = habitatPlacements.filter { $0.spot != spot && $0.decoration != item }
        if let item { layout.append(HabitatPlacement(spot: spot, decoration: item)) }
        journey.habitatPlacements = layout
        return true
    }

    mutating func startExpedition(_ trail: AdventureTrail) {
        guard lifeStage == .adult, journey.activeTrail == nil else { return }
        journey.activeTrail = trail
        journey.trailSeconds = 0
        journey.expedition = ExpeditionProgress()
    }

    @discardableResult
    mutating func chooseExpeditionBranch(_ branch: AdventureBranch, expeditionID: UUID, at date: Date = .now) -> Bool {
        guard lifeStage == .adult, let trail = journey.activeTrail, trail == branch.trail,
              journey.expedition?.id == expeditionID, journey.expedition?.branch == nil,
              journey.trailSeconds >= trail.seconds / 2 else { return false }
        journey.expedition?.branch = branch
        journey.finishExpeditionIfReady(name: name, companionID: companionID, at: date)
        return true
    }
}

struct BuddyMemory: Identifiable, Equatable {
    let id: String
    let companionID: UUID?
    let companionName: String
    let date: Date
    let title: String
    let detail: String
    let symbol: String
}

extension PetSnapshot {
    /// Derive known milestones from saved evidence. Missing old dates stay missing.
    var buddyMemories: [BuddyMemory] {
        let friends = ([CompanionResident(self)] + journey.residents).filter { $0.stage != .egg }
        let discoveredIDs = Set(friends.map(\.id))
        var entries: [BuddyMemory] = []
        for friend in friends {
            func add(_ date: Date?, key: String, title: String, detail: String, symbol: String) {
                guard let date else { return }
                entries.append(BuddyMemory(id: "\(friend.id.uuidString)-\(key)", companionID: friend.id,
                    companionName: friend.name, date: date, title: title, detail: detail, symbol: symbol))
            }
            add(friend.lifecycle?.hatchedAt, key: "hatch", title: "Hello, little one", detail: "The day you met your baby \(friend.species.displayName.lowercased()).", symbol: "sparkles")
            add(friend.lifecycle?.maturedAt, key: "grown", title: "All grown up", detail: "A new chapter of adventures together.", symbol: "leaf")
            add(friend.buddyBond?.firstOutingAt, key: "outing", title: "First outing together", detail: "Your first recorded movement together after hatching.", symbol: "figure.walk")
            add(friend.buddyBond?.firstHopAt, key: "hop", title: "A happy hop", detail: "Learned after an hour of grown-up adventures.", symbol: "figure.play")
            add(friend.buddyBond?.firstDanceAt, key: "dance", title: "Our victory dance", detail: "Learned after three hours of grown-up adventures.", symbol: "music.note")
            add(friend.buddyBond?.firstGameDates[BuddyGame.trickTrail.rawValue], key: "routine", title: "Our first trick trail", detail: "Three little gestures, learned together.", symbol: "pawprint")
        }
        for memory in journey.memories {
            // Legacy stories have a name but no identity; keep them as earlier memories.
            guard memory.companionID.map({ discoveredIDs.contains($0) }) ?? true else { continue }
            entries.append(BuddyMemory(id: memory.id.uuidString, companionID: memory.companionID,
                companionName: memory.companionName, date: memory.date, title: memory.trail.title,
                detail: memory.story, symbol: memory.trail.symbol))
        }
        return entries.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
