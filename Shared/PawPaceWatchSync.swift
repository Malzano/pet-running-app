import Foundation

enum PawPaceRunPhase: String, Codable, CaseIterable, Sendable, Hashable {
    case idle
    case running
    case paused
    case finished
    case failed
}

enum PawPaceHeartRateZone: Int, CaseIterable, Sendable, Hashable {
    case recovery = 1
    case endurance
    case tempo
    case threshold
    case peak

    static func zone(for heartRate: Int) -> PawPaceHeartRateZone? {
        guard heartRate > 0 else { return nil }
        return switch heartRate {
        case ..<120: .recovery
        case 120..<140: .endurance
        case 140..<160: .tempo
        case 160..<180: .threshold
        default: .peak
        }
    }

    var label: String {
        switch self {
        case .recovery: "Recovery"
        case .endurance: "Endurance"
        case .tempo: "Tempo"
        case .threshold: "Threshold"
        case .peak: "Peak"
        }
    }

    var accessibilityLabel: String {
        "Heart rate zone \(rawValue), \(label)"
    }
}

struct PawPaceRunState: Codable, Sendable, Hashable {
    var workoutID: UUID?
    var phase: PawPaceRunPhase
    var distanceKilometers: Double
    var elapsedSeconds: Int
    var paceSecondsPerKilometer: Int
    var heartRate: Int
    var experienceEarned: Int
    var encouragement: String
    var startedAt: Date?
    var updatedAt: Date

    static let idle = PawPaceRunState(
        workoutID: nil,
        phase: .idle,
        distanceKilometers: 0,
        elapsedSeconds: 0,
        paceSecondsPerKilometer: 0,
        heartRate: 0,
        experienceEarned: 0,
        encouragement: "Ready for an adventure!",
        startedAt: nil,
        updatedAt: .now
    )
}

struct PawPaceWatchPayload: Codable, Sendable {
    var pet: PetSnapshot
    var run: PawPaceRunState
    var control: PawPaceWatchControl? = nil
}

enum PawPaceWatchControlAction: String, Codable, Sendable, Hashable {
    case start
    case pause
    case resume
    case finish

    var phase: PawPaceRunPhase {
        switch self {
        case .start, .resume: .running
        case .pause: .paused
        case .finish: .finished
        }
    }
}

struct PawPaceWatchControl: Codable, Sendable, Hashable {
    var id: UUID
    var workoutID: UUID
    var action: PawPaceWatchControlAction
    var startedAt: Date
    var issuedAt: Date
    var replyToWatchWorkoutID: UUID?

    var phase: PawPaceRunPhase { action.phase }

    init(
        id: UUID,
        workoutID: UUID,
        action: PawPaceWatchControlAction,
        startedAt: Date,
        issuedAt: Date,
        replyToWatchWorkoutID: UUID? = nil
    ) {
        self.id = id
        self.workoutID = workoutID
        self.action = action
        self.startedAt = startedAt
        self.issuedAt = issuedAt
        self.replyToWatchWorkoutID = replyToWatchWorkoutID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case workoutID
        case action
        case phase
        case startedAt
        case issuedAt
        case replyToWatchWorkoutID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workoutID = try container.decode(UUID.self, forKey: .workoutID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        issuedAt = try container.decode(Date.self, forKey: .issuedAt)
        replyToWatchWorkoutID = try container.decodeIfPresent(UUID.self, forKey: .replyToWatchWorkoutID)
        if let decodedAction = try container.decodeIfPresent(PawPaceWatchControlAction.self, forKey: .action) {
            action = decodedAction
        } else {
            let legacyPhase = try container.decode(PawPaceRunPhase.self, forKey: .phase)
            switch legacyPhase {
            case .running: action = .resume
            case .paused: action = .pause
            case .finished: action = .finish
            case .idle, .failed: action = .finish
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(workoutID, forKey: .workoutID)
        try container.encode(action, forKey: .action)
        try container.encode(phase, forKey: .phase)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(issuedAt, forKey: .issuedAt)
        try container.encodeIfPresent(replyToWatchWorkoutID, forKey: .replyToWatchWorkoutID)
    }
}

enum PawPaceSyncPolicy {
    static func shouldAcceptPet(
        _ incoming: PetSnapshot,
        current: PetSnapshot,
        hasAuthoritativePet: Bool
    ) -> Bool {
        !hasAuthoritativePet || incoming.lastUpdated >= current.lastUpdated
    }

    static func shouldAcceptRun(
        _ incoming: PawPaceRunState,
        currentWorkoutID: UUID?,
        latestUpdate: Date?,
        allowWorkoutAdoption: Bool
    ) -> Bool {
        guard incoming.phase != .idle, let remoteWorkoutID = incoming.workoutID else { return false }
        if let latestUpdate, incoming.updatedAt < latestUpdate { return false }
        if let currentWorkoutID {
            return currentWorkoutID == remoteWorkoutID || allowWorkoutAdoption
        }
        return allowWorkoutAdoption
    }

    static func canStartConnectivityFallback(
        from state: PawPaceRunState,
        now: Date = .now,
        maximumAge: TimeInterval = 30
    ) -> Bool {
        guard
            state.workoutID != nil,
            state.phase == .running || state.phase == .paused
        else { return false }
        return state.updatedAt <= now.addingTimeInterval(5)
            && state.updatedAt >= now.addingTimeInterval(-maximumAge)
    }

    static func canAdoptPendingPhoneLaunch(
        from state: PawPaceRunState,
        localStart: Date,
        maximumStartDifference: TimeInterval = 60
    ) -> Bool {
        guard
            state.workoutID != nil,
            state.phase != .idle,
            let remoteStart = state.startedAt,
            state.updatedAt >= localStart
        else { return false }
        return abs(remoteStart.timeIntervalSince(localStart)) <= maximumStartDifference
    }

    static func canAnswerPhoneLaunchChallenge(
        from state: PawPaceRunState,
        localStart: Date,
        now: Date = .now,
        maximumStartDifference: TimeInterval = 60
    ) -> Bool {
        guard
            state.phase == .running || state.phase == .paused,
            state.workoutID != nil,
            let remoteStart = state.startedAt
        else { return false }
        return abs(remoteStart.timeIntervalSince(localStart)) <= maximumStartDifference
            && state.updatedAt >= localStart
            && state.updatedAt <= now.addingTimeInterval(5)
    }

    static func canBindPhoneControl(
        _ control: PawPaceWatchControl,
        provisionalWatchWorkoutID: UUID
    ) -> Bool {
        control.replyToWatchWorkoutID == provisionalWatchWorkoutID
    }

    static func shouldConsumePreviouslyRewardedTerminal(
        _ state: PawPaceRunState,
        wasTerminalHandled: Bool,
        hasRegisteredReward: Bool,
        hasExactPendingRecord: Bool
    ) -> Bool {
        guard state.phase == .finished || state.phase == .failed else { return false }
        return state.workoutID != nil
            && (wasTerminalHandled || (hasRegisteredReward && !hasExactPendingRecord))
    }

    static func recoveredRunState(
        workoutID: UUID,
        persistedStart: Date?,
        sessionStart: Date?,
        elapsedSeconds: TimeInterval,
        updatedAt: Date = .now
    ) -> PawPaceRunState {
        PawPaceRunState(
            workoutID: workoutID,
            phase: .idle,
            distanceKilometers: 0,
            elapsedSeconds: max(0, Int(elapsedSeconds.rounded())),
            paceSecondsPerKilometer: 0,
            heartRate: 0,
            experienceEarned: 0,
            encouragement: "Workout recovered—keep going!",
            startedAt: persistedStart ?? sessionStart ?? updatedAt,
            updatedAt: updatedAt
        )
    }
}

enum PawPaceWatchMessageKey {
    static let payload = "pawpace.payload.v1"
}

enum PawPaceWorkoutIdentity {
    static func syncIdentifier(for workoutID: UUID) -> String {
        "com.pawpace.run.\(workoutID.uuidString.lowercased())"
    }
}
