import Foundation

struct ClubAccount: Codable, Equatable, Identifiable {
    var id: String
    var alias: String
}

struct ClubSession: Codable, Equatable {
    var token: String
    var account: ClubAccount
    var appleUserID: String
    var expiresAt: Date
}

struct ClubMember: Codable, Equatable, Identifiable {
    var id: String
    var alias: String
    var joinedAt: Date
    var sharesActivity: Bool
}

struct ClubActivityDay: Codable, Equatable, Identifiable {
    var id: String
    var memberID: String
    var day: String
    var earnedAt: Date
}

struct ClubEvent: Codable, Equatable, Identifiable {
    var id: String
    var clubID: String
    var activity: WorkoutActivity
    var scheduledAt: Date
    var durationMinutes: Int
    var cancelled: Bool
    var plannerID: String { "club-\(clubID)-\(id)" }
    var plan: PlannedActivity {
        PlannedActivity(title: "Club \(activity.displayName.lowercased())", activity: activity,
                        scheduledAt: scheduledAt, durationMinutes: durationMinutes, clubEventID: plannerID)
    }
    static let supportedActivities: [WorkoutActivity] = [.walking, .running, .cycling, .hiking, .swimming, .yoga,
        .functionalStrengthTraining, .traditionalStrengthTraining, .cardioDance, .mindAndBody]
}

enum ClubCheerKind: String, Codable, CaseIterable, Identifiable {
    case wellDone, withYou, welcome, restWell
    var id: String { rawValue }
    var title: String {
        switch self { case .wellDone: "Lovely effort!"; case .withYou: "We’re in this together"; case .welcome: "Glad you’re here"; case .restWell: "Enjoy a little rest" }
    }
    var symbol: String { switch self { case .wellDone: "hands.clap"; case .withYou: "heart"; case .welcome: "hand.wave"; case .restWell: "leaf" } }
}

struct ClubCheer: Codable, Equatable, Identifiable {
    var id: String
    var senderID: String
    var recipientID: String
    var kind: ClubCheerKind
    var createdAt: Date
}

struct RunningClub: Codable, Equatable, Identifiable {
    var id: String
    var ownerID: String
    var name: String
    var timeZone: String
    var weeklyTarget: Int
    var createdAt: Date
    var weekStart: String
    var weekEnd: String
    var totalDays: Int
    var members: [ClubMember]
    var days: [ClubActivityDay]
    var events: [ClubEvent]
    var cheers: [ClubCheer]
    var weeklyDays: Int { Set(days.map { "\($0.memberID):\($0.day)" }).count }
    var campLevel: Int { totalDays >= 50 ? 3 : totalDays >= 20 ? 2 : totalDays >= 5 ? 1 : 0 }
    var campTitle: String { ["A clearing for friends", "The first little blooms", "A place to gather", "A campsite full of memories"][campLevel] }
    var isValid: Bool {
        UUID(uuidString: id) != nil && UUID(uuidString: ownerID) != nil && (2...70).contains(weeklyTarget)
            && TimeZone(identifier: timeZone) != nil && totalDays >= 0 && name.count <= 40
            && members.count <= 30 && Set(members.map(\.id)).count == members.count
            && members.contains(where: { $0.id == ownerID })
            && events.allSatisfy { (5...240).contains($0.durationMinutes) && $0.clubID == id }
            && days.allSatisfy { day in members.contains { $0.id == day.memberID } }
    }
}

struct ClubSnapshot: Codable, Equatable {
    var account: ClubAccount
    var clubs: [RunningClub]
    var fetchedAt: Date
    var social: FriendSnapshot? = nil
    var isValid: Bool { clubs.allSatisfy(\.isValid) && Set(clubs.map(\.id)).count == clubs.count && (social?.isValid ?? true) }
}

struct ClubCommand: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var action: String
    var clubID: String?
    var data = Payload()
    struct Payload: Codable, Equatable {
        var name: String?
        var timeZone: String?
        var weeklyTarget: Int?
        var token: String?
        var enabled: Bool?
        var earnedAt: Date?
        var activity: WorkoutActivity?
        var scheduledAt: Date?
        var durationMinutes: Int?
        var eventID: String?
        var recipientID: String?
        var kind: ClubCheerKind?
        var memberID: String?
        var workoutID: String?
        var elapsedSeconds: Int?
        var distanceMeters: Double?
        var postID: String?
    }
    var description: String {
        switch action {
        case "friendCode": "Replace friend code"
        case "friendRequest": "Send friend request"
        case "friendAccept": "Accept friend request"
        case "friendRemove": "Remove friend or request"
        case "friendBlock": "Block friend"
        case "friendUnblock": "Unblock friend"
        case "friendPost": "Share workout with friends"
        case "friendDeletePost": "Remove shared workout"
        case "friendCheer": "Cheer a friend’s workout"
        case "create": "Create club"
        case "join": "Join club"
        case "sharing": data.enabled == true ? "Turn on activity sharing" : "Turn off activity sharing"
        case "day": "Share an activity day"
        case "event": "Schedule a group activity"
        case "cancelEvent": "Cancel a group activity"
        case "cheer": "Send encouragement"
        case "leave": "Leave club"
        case "deleteClub": "Close club"
        case "removeMember": "Remove member"
        case "eraseDays": "Remove shared activity days"
        default: "Update club"
        }
    }
}

struct ClubCommandResult: Codable {
    var clubID: String?
    var invitationURL: URL?
    var expiresAt: Date?
}

struct ClubOutboxItem: Codable, Equatable, Identifiable {
    var command: ClubCommand
    var failure: String?
    var id: String { command.id }
}

struct ClubArchive: Codable, Equatable {
    var accountID: String
    var snapshot: ClubSnapshot?
    var pending: [ClubOutboxItem] = []
    // Per account, club and local day. Retain after syncing/removing history.
    var submittedDays: Set<String> = []
    // Local opt-out takes effect even while its server update is queued.
    var sharingPaused: Set<String> = []
}

enum ClubPrivacy {
    /// No pet identity is ever uploaded. Also conceal accidental species/move
    /// names in custom club titles according to this viewer's actual discoveries.
    static func title(_ text: String, pet: PetSnapshot) -> String {
        let discovered = Set(([CompanionResident(pet)] + pet.journey.residents).filter { $0.stage != .egg }.map(\.species))
        var result = text
        for species in PetSpecies.allCases where !discovered.contains(species) {
            for name in [species.displayName, species.rawValue, species.specialMoveName].compactMap({ $0 }) {
                result = result.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: name), with: "mystery friend", options: [.regularExpression, .caseInsensitive])
            }
        }
        return result
    }
}

enum ClubJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .sortedKeys
        return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let text = try value.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: value.codingPath, debugDescription: "Invalid date"))
            }
            return date
        }
        return decoder
    }
}
