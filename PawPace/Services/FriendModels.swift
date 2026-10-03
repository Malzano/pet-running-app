import Foundation

struct FriendConnection: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case incoming, outgoing, accepted }
    var id: String
    var alias: String
    var status: Status
    var since: Date
}

struct FriendPost: Codable, Equatable, Identifiable {
    var id: String
    var authorID: String
    var alias: String
    var workoutID: String
    var activity: WorkoutActivity
    var endedAt: Date
    var elapsedSeconds: Int
    var distanceMeters: Double?
    var createdAt: Date
    var cheerCount: Int
    var cheeredByMe: Bool
    var isValid: Bool {
        UUID(uuidString: id) != nil && UUID(uuidString: authorID) != nil && UUID(uuidString: workoutID) != nil
            && (1...86_400).contains(elapsedSeconds) && (distanceMeters.map { $0.isFinite && (0...1_000_000).contains($0) } ?? true)
            && alias.count <= 60 && cheerCount >= 0
    }
}

struct FriendSnapshot: Codable, Equatable {
    var friendCode: String
    var connections: [FriendConnection]
    var posts: [FriendPost]
    var blocks: [ClubAccount]
    var isValid: Bool {
        friendCode.count == 16 && friendCode.allSatisfy(\.isHexDigit)
            && connections.count <= 100 && Set(connections.map(\.id)).count == connections.count
            && connections.allSatisfy { UUID(uuidString: $0.id) != nil && $0.alias.count <= 60 }
            && posts.count <= 100 && posts.allSatisfy(\.isValid) && Set(posts.map(\.id)).count == posts.count
    }
}

extension ClubCommand {
    static func share(_ summary: RunSummary, includeDistance: Bool) -> ClubCommand {
        ClubCommand(action: "friendPost", data: Payload(earnedAt: summary.endedAt,
            activity: summary.workoutConfiguration.activity, workoutID: summary.id.uuidString,
            elapsedSeconds: summary.elapsedSeconds,
            distanceMeters: includeDistance && summary.workoutConfiguration.activity.supportsDistance ? summary.distanceMeters : nil))
    }
}
