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

struct WorkoutActivitySegment: Codable, Sendable, Hashable {
    var configuration: WorkoutConfiguration
    var startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double = 0
    var activeEnergyKilocalories: Double = 0
}

enum WorkoutTiming {
    static func activeIntervals(
        startedAt: Date,
        endedAt: Date,
        pauseIntervals: [DateInterval],
        pauseStartedAt: Date? = nil
    ) -> [DateInterval] {
        guard endedAt > startedAt else { return [] }
        var pauses = pauseIntervals
        if let pauseStartedAt, pauseStartedAt < endedAt {
            pauses.append(DateInterval(start: pauseStartedAt, end: endedAt))
        }
        var cursor = startedAt
        var active: [DateInterval] = []
        for pause in pauses.sorted(by: { $0.start < $1.start }) {
            let pauseStart = max(startedAt, pause.start)
            let pauseEnd = min(endedAt, pause.end)
            guard pauseEnd > cursor, pauseStart < endedAt else { continue }
            if pauseStart > cursor { active.append(DateInterval(start: cursor, end: pauseStart)) }
            cursor = max(cursor, pauseEnd)
        }
        if cursor < endedAt { active.append(DateInterval(start: cursor, end: endedAt)) }
        return active
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
    var workoutConfiguration = WorkoutConfiguration()
    var activeEnergyKilocalories: Double = 0
    var multisportLegIndex: Int = 0
    var activitySegments: [WorkoutActivitySegment] = []
    var pauseIntervals: [DateInterval] = []
    var pauseStartedAt: Date? = nil
    var endedAt: Date? = nil
    var isAwaitingPhoneConfiguration = false

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

extension PawPaceRunState {
    /// Keep the launch timestamp for phone/Watch identity matching, but exclude
    /// authorization and connection setup from fallback records and activity legs.
    /// The same operation restores this exclusion after recovering an HK session.
    mutating func excludeSetupTime(until activeStartedAt: Date) {
        guard let startedAt,
              startedAt.timeIntervalSinceReferenceDate.isFinite,
              activeStartedAt.timeIntervalSinceReferenceDate.isFinite,
              activeStartedAt > startedAt else { return }
        let setup = DateInterval(start: startedAt, end: activeStartedAt)
        if !pauseIntervals.contains(setup) { pauseIntervals.append(setup) }
        if let first = activitySegments.indices.first,
           activitySegments[first].startedAt < activeStartedAt,
           activitySegments[first].endedAt.map({ $0 >= activeStartedAt }) ?? true {
            activitySegments[first].startedAt = activeStartedAt
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workoutID = try values.decodeIfPresent(UUID.self, forKey: .workoutID)
        phase = try values.decode(PawPaceRunPhase.self, forKey: .phase)
        distanceKilometers = try values.decode(Double.self, forKey: .distanceKilometers)
        elapsedSeconds = try values.decode(Int.self, forKey: .elapsedSeconds)
        paceSecondsPerKilometer = try values.decode(Int.self, forKey: .paceSecondsPerKilometer)
        heartRate = try values.decode(Int.self, forKey: .heartRate)
        experienceEarned = try values.decode(Int.self, forKey: .experienceEarned)
        encouragement = try values.decode(String.self, forKey: .encouragement)
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        workoutConfiguration = try values.decodeIfPresent(WorkoutConfiguration.self, forKey: .workoutConfiguration) ?? .init()
        activeEnergyKilocalories = try values.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories) ?? 0
        multisportLegIndex = try values.decodeIfPresent(Int.self, forKey: .multisportLegIndex) ?? 0
        activitySegments = try values.decodeIfPresent([WorkoutActivitySegment].self, forKey: .activitySegments) ?? []
        pauseIntervals = try values.decodeIfPresent([DateInterval].self, forKey: .pauseIntervals) ?? []
        pauseStartedAt = try values.decodeIfPresent(Date.self, forKey: .pauseStartedAt)
        endedAt = try values.decodeIfPresent(Date.self, forKey: .endedAt)
        isAwaitingPhoneConfiguration = try values.decodeIfPresent(Bool.self, forKey: .isAwaitingPhoneConfiguration) ?? false
    }
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
    case nextActivity

    var phase: PawPaceRunPhase {
        switch self {
        case .start, .resume, .nextActivity: .running
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
    var workoutConfiguration: WorkoutConfiguration
    var multisportLegIndex: Int

    var phase: PawPaceRunPhase { action.phase }

    init(
        id: UUID,
        workoutID: UUID,
        action: PawPaceWatchControlAction,
        startedAt: Date,
        issuedAt: Date,
        replyToWatchWorkoutID: UUID? = nil,
        workoutConfiguration: WorkoutConfiguration = .init(),
        multisportLegIndex: Int = 0
    ) {
        self.id = id
        self.workoutID = workoutID
        self.action = action
        self.startedAt = startedAt
        self.issuedAt = issuedAt
        self.replyToWatchWorkoutID = replyToWatchWorkoutID
        self.workoutConfiguration = workoutConfiguration
        self.multisportLegIndex = multisportLegIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case workoutID
        case action
        case phase
        case startedAt
        case issuedAt
        case replyToWatchWorkoutID
        case workoutConfiguration
        case multisportLegIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workoutID = try container.decode(UUID.self, forKey: .workoutID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        issuedAt = try container.decode(Date.self, forKey: .issuedAt)
        replyToWatchWorkoutID = try container.decodeIfPresent(UUID.self, forKey: .replyToWatchWorkoutID)
        workoutConfiguration = try container.decodeIfPresent(WorkoutConfiguration.self, forKey: .workoutConfiguration) ?? .init()
        multisportLegIndex = try container.decodeIfPresent(Int.self, forKey: .multisportLegIndex) ?? 0
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
        try container.encode(workoutConfiguration, forKey: .workoutConfiguration)
        try container.encode(multisportLegIndex, forKey: .multisportLegIndex)
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
            state.phase == .running || state.phase == .paused || (state.phase == .idle && state.isAwaitingPhoneConfiguration),
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
