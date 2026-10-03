import Combine
import CoreLocation
import Foundation
import OSLog

struct RunSummary: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let elapsedSeconds: Int
    let averagePaceSecondsPerKilometer: Int
    let averageHeartRate: Int?
    let experienceEarned: Int
    var workoutConfiguration = WorkoutConfiguration()
    var activeEnergyKilocalories: Double = 0
    var activitySegments: [WorkoutActivitySegment] = []
    var pauseIntervals: [DateInterval] = []

    var distanceKilometers: Double { distanceMeters / 1_000 }

    var friendshipEarned: Int { max(2, max(Int(distanceKilometers * 3), max(0, elapsedSeconds) / 300)) }
}

extension RunSummary {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        endedAt = try values.decode(Date.self, forKey: .endedAt)
        distanceMeters = try values.decode(Double.self, forKey: .distanceMeters)
        elapsedSeconds = try values.decode(Int.self, forKey: .elapsedSeconds)
        averagePaceSecondsPerKilometer = try values.decode(Int.self, forKey: .averagePaceSecondsPerKilometer)
        averageHeartRate = try values.decodeIfPresent(Int.self, forKey: .averageHeartRate)
        experienceEarned = try values.decode(Int.self, forKey: .experienceEarned)
        workoutConfiguration = try values.decodeIfPresent(WorkoutConfiguration.self, forKey: .workoutConfiguration) ?? .init()
        activeEnergyKilocalories = try values.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories) ?? 0
        activitySegments = try values.decodeIfPresent([WorkoutActivitySegment].self, forKey: .activitySegments) ?? []
        pauseIntervals = try values.decodeIfPresent([DateInterval].self, forKey: .pauseIntervals) ?? []
    }
}

@MainActor
final class RunTracker: NSObject, ObservableObject {
    private static let syncLog = Logger(subsystem: "com.pawpace.app.sync", category: "phone-run")
    private static let handledDeferredTerminalStorageKey = "pawpace.handledWatchTerminals.v1"

    enum DeferredWatchTerminalResolution {
        case finished(summary: RunSummary, remoteWorkoutID: UUID)
        case failed(summary: RunSummary, remoteWorkoutID: UUID)
    }

    enum Phase: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var configuration = WorkoutConfiguration()
    @Published private(set) var activeEnergyKilocalories: Double = 0
    @Published private(set) var multisportLegIndex = 0
    @Published private(set) var isAdvancingActivity = false
    private var pendingMultisportLegIndex: Int?
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var heartRate: Int?
    @Published private(set) var locationAuthorization: CLAuthorizationStatus

    private let locationManager = CLLocationManager()
    private let healthKit: HealthKitService
    private let petSnapshot: () -> PetSnapshot
    private let watchConnectivity: PhoneWatchConnectivityService
    private let liveActivity = LiveActivityService.shared
    private var activitySegments: [WorkoutActivitySegment] = []
    private var pauseIntervals: [DateInterval] = []
    private var pauseStartedAt: Date?
    private var lastLocation: CLLocation?
    private var startedAt: Date?
    private var segmentStartedAt: Date?
    private var accumulatedSeconds: TimeInterval = 0
    private var timer: AnyCancellable?
    private var lastLiveActivityUpdate = Date.distantPast
    private var lastHeartRateUpdate = Date.distantPast
    private var notificationToken: NSObjectProtocol?
    private var watchWorkoutParticipated = false
    private var workoutID: UUID?
    private var latestWatchState: PawPaceRunState?
    private var watchStartTask: Task<Bool, Never>?
    private var completedSummaryAwaitingWatchSave: RunSummary?
    private var pendingHealthSaveIDs: Set<UUID> = []
    private var awaitingFirstWatchIdentity = false
    private var hasPendingPhoneWatchLaunch = false
    private var pendingWatchBindingID: UUID?
    private var respondedWatchBindingIDs: Set<UUID> = []
    @Published private(set) var isFinishing = false
    @Published private(set) var interruptedWorkout: PawPaceRunState?
    @Published private(set) var recoveredWorkoutMessage: String?
    @Published private(set) var recoveryStorageMessage: String?
    private let privateStorage: PawPacePrivateStorage?
    private let legacyDefaults: UserDefaults
    private var pendingHealthReadFailed = false
    private var lastRecoveryCheckpoint = Date.distantPast
    private var savedCheckpointWorkoutID: UUID?
    private static let checkpointFilename = "phone-workout-checkpoint-v1.json"
    private static let pendingHealthFilename = "phone-pending-health-saves-v1.json"

    init(
        healthKit: HealthKitService,
        petSnapshot: @escaping () -> PetSnapshot,
        watchConnectivity: PhoneWatchConnectivityService,
        privateStorage: PawPacePrivateStorage? = nil,
        legacyDefaults: UserDefaults? = nil
    ) {
        self.privateStorage = privateStorage ?? (try? PawPacePrivateStorage.shared())
        self.legacyDefaults = legacyDefaults ?? PawPaceShared.defaults
        self.healthKit = healthKit
        self.petSnapshot = petSnapshot
        self.watchConnectivity = watchConnectivity
        self.locationAuthorization = locationManager.authorizationStatus
        super.init()

        loadInterruptedWorkout()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 3
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true

        notificationToken = NotificationCenter.default.addObserver(forName: .pawPaceToggleRun, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.togglePause()
            }
        }
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    var distanceKilometers: Double { distanceMeters / 1_000 }

    /// A route belongs only to this in-memory session. It is never added to the
    /// Codable summary, journal, recovery record, share card or Club payload.
    func recordedRoute(for summary: RunSummary) -> [CLLocationCoordinate2D] {
        guard workoutID == summary.id else { return [] }
        return route
    }

    var paceSecondsPerKilometer: Int {
        guard configuration.supportsPace, distanceMeters >= 50 else { return 0 }
        return Int(Double(elapsedSeconds) / distanceKilometers)
    }

    var experienceEarned: Int {
        configuration.activity.experienceEarned(elapsedSeconds: elapsedSeconds, distanceKilometers: distanceKilometers)
    }

    func configure(_ configuration: WorkoutConfiguration) {
        guard !isFinishing, phase == .idle || phase == .finished else { return }
        self.configuration = configuration.normalized
    }

    var canAdvanceMultisportActivity: Bool {
        phase == .running && !hasPendingPhoneWatchLaunch && !isAdvancingActivity && configuration.activity.requiresMultisportSession
            && multisportLegIndex + 1 < configuration.multisportLegs.count
    }
    var canAdvanceActivity: Bool { canAdvanceMultisportActivity }
    func nextActivity() { advanceMultisportActivity() }
    var currentActivityConfiguration: WorkoutConfiguration {
        configuration.configuration(forMultisportLeg: multisportLegIndex)
    }

    func advanceMultisportActivity() {
        guard canAdvanceMultisportActivity else { return }
        let now = Date()
        activitySegments = refreshedActivitySegments(endingAt: now)
        multisportLegIndex += 1
        if watchWorkoutParticipated || hasPendingPhoneWatchLaunch {
            pendingMultisportLegIndex = multisportLegIndex
            isAdvancingActivity = true
        }
        activitySegments.append(WorkoutActivitySegment(configuration: configuration.configuration(forMultisportLeg: multisportLegIndex), startedAt: now, endedAt: nil))
        lastLocation = nil
        if currentActivityConfiguration.supportsRoute {
            if locationAuthorization == .notDetermined { requestLocationPermission() }
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
        }
        sendWatchControl(.nextActivity)
        publishLiveActivity(force: true)
    }

    private func refreshedActivitySegments(endingAt date: Date? = nil) -> [WorkoutActivitySegment] {
        var segments = activitySegments
        guard let last = segments.indices.last, segments[last].endedAt == nil else { return segments }
        segments[last].distanceMeters = max(0, distanceMeters - segments.dropLast().reduce(0) { $0 + $1.distanceMeters })
        segments[last].activeEnergyKilocalories = max(0, activeEnergyKilocalories - segments.dropLast().reduce(0) { $0 + $1.activeEnergyKilocalories })
        segments[last].endedAt = date
        return segments
    }

    private func closePause(at date: Date) {
        guard let pauseStartedAt else { return }
        pauseIntervals.append(DateInterval(start: pauseStartedAt, end: max(pauseStartedAt, date)))
        self.pauseStartedAt = nil
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func start(syncToWatch: Bool = true) {
        guard !isFinishing, phase == .idle || phase == .finished else { return }
        guard !syncToWatch || interruptedWorkout == nil else { return }
        recoveredWorkoutMessage = nil

        if currentActivityConfiguration.supportsRoute, locationAuthorization == .notDetermined {
            requestLocationPermission()
        }

        phase = .running
        distanceMeters = 0
        activeEnergyKilocalories = 0
        multisportLegIndex = 0
        pendingMultisportLegIndex = nil
        isAdvancingActivity = false
        elapsedSeconds = 0
        route = []
        heartRate = nil
        accumulatedSeconds = 0
        lastLocation = nil
        startedAt = .now
        segmentStartedAt = startedAt
        pauseIntervals = []
        pauseStartedAt = nil
        activitySegments = configuration.activity.requiresMultisportSession
            ? [WorkoutActivitySegment(configuration: configuration.configuration(forMultisportLeg: 0), startedAt: startedAt!, endedAt: nil)] : []
        workoutID = UUID()
        latestWatchState = nil
        completedSummaryAwaitingWatchSave = nil
        pendingWatchBindingID = nil
        respondedWatchBindingIDs.removeAll()
        watchStartTask?.cancel()
        watchStartTask = nil
        if syncToWatch {
            watchWorkoutParticipated = false
            awaitingFirstWatchIdentity = true
            hasPendingPhoneWatchLaunch = true
        } else {
            awaitingFirstWatchIdentity = false
            hasPendingPhoneWatchLaunch = false
        }
        PawPaceShared.defaults.set(false, forKey: PawPaceShared.runPausedKey)
        if currentActivityConfiguration.supportsRoute { locationManager.startUpdatingLocation() }
        startTimer()
        let pet = petSnapshot()
        liveActivity.start(pet: pet, targetKilometers: 3, configuration: configuration)
        publishLiveActivity(force: true)
        if syncToWatch {
            sendWatchControl(.start, pet: pet)
            let launchedWorkoutID = workoutID ?? UUID()
            let launchedStartedAt = startedAt ?? .now
            let launchedConfiguration = configuration
            watchStartTask = Task { [weak self, healthKit] in
                let succeeded = await healthKit.startWatchWorkout(
                    workoutID: launchedWorkoutID,
                    startedAt: launchedStartedAt,
                    configuration: launchedConfiguration
                )
                if !succeeded {
                    self?.awaitingFirstWatchIdentity = false
                    self?.hasPendingPhoneWatchLaunch = false
                    self?.pendingMultisportLegIndex = nil
                    self?.isAdvancingActivity = false
                    self?.checkpointInterruptedWorkout()
                }
                return succeeded
            }
        }
    }

    func pause(syncToWatch: Bool = true) {
        guard phase == .running else { return }
        if let segmentStartedAt {
            accumulatedSeconds += Date().timeIntervalSince(segmentStartedAt)
        }
        segmentStartedAt = nil
        phase = .paused
        pauseStartedAt = .now
        locationManager.stopUpdatingLocation()
        lastLocation = nil
        PawPaceShared.defaults.set(true, forKey: PawPaceShared.runPausedKey)
        if syncToWatch {
            if pendingMultisportLegIndex == nil {
                healthKit.pauseMirroredWorkout(workoutID: workoutID)
            }
            sendWatchControl(.pause)
        }
        tick()
        publishLiveActivity(force: true)
    }

    func resume(syncToWatch: Bool = true) {
        guard phase == .paused else { return }
        phase = .running
        closePause(at: .now)
        segmentStartedAt = .now
        PawPaceShared.defaults.set(false, forKey: PawPaceShared.runPausedKey)
        if currentActivityConfiguration.supportsRoute { locationManager.startUpdatingLocation() }
        if syncToWatch {
            if pendingMultisportLegIndex == nil {
                healthKit.resumeMirroredWorkout(workoutID: workoutID)
            }
            sendWatchControl(.resume)
        }
        publishLiveActivity(force: true)
        checkpointInterruptedWorkout()
    }

    func togglePause() {
        phase == .running ? pause() : resume()
    }

    func finish(syncToWatch: Bool = true) async -> RunSummary? {
        guard phase == .running || phase == .paused, let startedAt else { return nil }
        isFinishing = true
        defer { isFinishing = false }

        if phase == .running, let segmentStartedAt {
            accumulatedSeconds += Date().timeIntervalSince(segmentStartedAt)
        }

        phase = .finished
        locationManager.stopUpdatingLocation()
        timer?.cancel()
        timer = nil
        elapsedSeconds = max(Int(accumulatedSeconds.rounded()), 1)
        let endedAt = Date()
        closePause(at: endedAt)
        let shouldAwaitWatchFinalState = watchWorkoutParticipated || watchStartTask != nil

        if let watchStartTask {
            _ = await watchStartTask.value
            self.watchStartTask = nil
        }

        if syncToWatch {
            // The explicit command reconciles its pending leg before changing
            // phase. A bare HealthKit end could otherwise overtake that command.
            if pendingMultisportLegIndex == nil {
                healthKit.endMirroredWorkout(workoutID: workoutID)
            }
            sendWatchControl(.finish)
        }

        if shouldAwaitWatchFinalState {
            await waitForFinalWatchState()
        }

        let summary = RunSummary(
            id: workoutID ?? UUID(),
            startedAt: self.startedAt ?? startedAt,
            endedAt: latestWatchState?.endedAt ?? endedAt,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            averagePaceSecondsPerKilometer: paceSecondsPerKilometer,
            averageHeartRate: heartRate,
            experienceEarned: experienceEarned,
            workoutConfiguration: configuration,
            activeEnergyKilocalories: activeEnergyKilocalories,
            activitySegments: refreshedActivitySegments(endingAt: latestWatchState?.endedAt ?? endedAt),
            pauseIntervals: pauseIntervals
        )

        let finalState = activityState(encouragement: "Quest complete! \(petSnapshot().name) earned \(experienceEarned) XP.")
        await liveActivity.end(with: finalState)
        // Starting the Watch app is not proof that it created a Health workout.
        // Only let the Watch own the record after it acknowledges a mirrored or
        // connectivity state; otherwise the phone saves the run as a fallback.
        let watchOwnsHealthRecord = watchWorkoutParticipated
        if watchOwnsHealthRecord {
            if latestWatchState?.phase == .finished {
                completedSummaryAwaitingWatchSave = nil
                removePendingWatchRecord(summaryID: summary.id)
            } else {
                completedSummaryAwaitingWatchSave = summary
                storePendingWatchRecord(summary)
            }
        } else {
            completedSummaryAwaitingWatchSave = nil
            do {
                try await healthKit.saveRun(summary)
            } catch {
                queueFailedWatchHealthFallback(summary)
            }
        }
        watchConnectivity.sync(pet: petSnapshot(), run: currentRunState)
        return summary
    }

    func reset() {
        timer?.cancel()
        timer = nil
        locationManager.stopUpdatingLocation()
        phase = .idle
        distanceMeters = 0
        activeEnergyKilocalories = 0
        multisportLegIndex = 0
        pendingMultisportLegIndex = nil
        isAdvancingActivity = false
        elapsedSeconds = 0
        route = []
        heartRate = nil
        accumulatedSeconds = 0
        startedAt = nil
        activitySegments = []
        pauseIntervals = []
        pauseStartedAt = nil
        segmentStartedAt = nil
        lastLocation = nil
        workoutID = nil
        watchWorkoutParticipated = false
        completedSummaryAwaitingWatchSave = nil
        awaitingFirstWatchIdentity = false
        hasPendingPhoneWatchLaunch = false
        pendingWatchBindingID = nil
        respondedWatchBindingIDs.removeAll()
        latestWatchState = nil
        watchStartTask?.cancel()
        watchStartTask = nil
        isFinishing = false
        recoveredWorkoutMessage = nil
        watchConnectivity.sync(pet: petSnapshot(), run: .idle)
    }

    func markWatchWorkoutActive() {
        watchWorkoutParticipated = true
        // Wait for a concrete Watch UUID before superseding a phone checkpoint.
    }

    func matchesCurrentWatchWorkout(_ remoteWorkoutID: UUID) -> Bool {
        remoteWorkoutID == workoutID || remoteWorkoutID == pendingWatchBindingID
    }

    func markPendingWatchRecordForPhoneSave(remoteWorkoutID: UUID) -> RunSummary? {
        var records = loadPendingWatchRecords()
        guard let index = records.firstIndex(where: { $0.summary.id == remoteWorkoutID }) else {
            return nil
        }
        records[index].requiresPhoneSave = true
        let summary = records[index].summary
        savePendingWatchRecords(records)
        return summary
    }

    @discardableResult
    func markWatchWorkoutFailed() -> RunSummary? {
        let fallbackSummary = completedSummaryAwaitingWatchSave
        if let fallbackSummary {
            markPendingWatchRecordForPhoneSave(summaryID: fallbackSummary.id)
        }
        watchWorkoutParticipated = false
        pendingMultisportLegIndex = nil
        isAdvancingActivity = false
        awaitingFirstWatchIdentity = false
        hasPendingPhoneWatchLaunch = false
        pendingWatchBindingID = nil
        respondedWatchBindingIDs.removeAll()
        // Keep the authoritative end for fallback saves after delayed failures.
        if latestWatchState?.phase != .failed && latestWatchState?.phase != .finished {
            latestWatchState = nil
        }
        watchStartTask?.cancel()
        watchStartTask = nil
        return fallbackSummary
    }

    func pendingFailedWatchSummaries() -> [RunSummary] {
        loadPendingWatchRecords()
            .filter(\.requiresPhoneSave)
            .map(\.summary)
    }

    @discardableResult
    func queueFailedWatchHealthFallback(_ summary: RunSummary) -> Bool {
        var records = loadPendingWatchRecords()
        guard !pendingHealthReadFailed else { return false }
        records.removeAll { $0.summary.id == summary.id }
        records.append(PendingWatchHealthRecord(summary: summary, requiresPhoneSave: true))
        return savePendingWatchRecords(records)
    }

    func beginPendingWatchHealthSave(summaryID: UUID) -> Bool {
        pendingHealthSaveIDs.insert(summaryID).inserted
    }

    func completePendingWatchHealthSave(summaryID: UUID, succeeded: Bool) {
        pendingHealthSaveIDs.remove(summaryID)
        guard succeeded else { return }
        removePendingWatchRecord(summaryID: summaryID)
        if completedSummaryAwaitingWatchSave?.id == summaryID {
            completedSummaryAwaitingWatchSave = nil
        }
    }

    /// Resolves a Watch identity without consuming its durable pending record.
    /// The app must persist canonical and alias identities before acknowledging.
    func resolveDeferredWatchTerminal(
        _ state: PawPaceRunState
    ) -> DeferredWatchTerminalResolution? {
        guard
            state.phase == .finished || state.phase == .failed,
            let remoteWorkoutID = state.workoutID,
            let remoteStartedAt = state.startedAt,
            !handledDeferredTerminalIDs().contains(remoteWorkoutID)
        else { return nil }

        let records = loadPendingWatchRecords()
        let matchingIndex: Int?
        if let exactIndex = records.firstIndex(where: { $0.summary.id == remoteWorkoutID }) {
            matchingIndex = exactIndex
        } else if PawPaceShared.hasRegisteredReward(for: remoteWorkoutID) {
            // A duplicate terminal from a previously completed run must never
            // fuzzy-match a newer back-to-back run that happens to start nearby.
            return nil
        } else {
            matchingIndex = records.indices.min {
                abs(records[$0].summary.startedAt.timeIntervalSince(remoteStartedAt))
                    < abs(records[$1].summary.startedAt.timeIntervalSince(remoteStartedAt))
            }.flatMap { index in
                abs(records[index].summary.startedAt.timeIntervalSince(remoteStartedAt)) <= 60
                    ? index
                    : nil
            }
        }
        guard let matchingIndex else { return nil }
        let summary = records[matchingIndex].summary
        return state.phase == .finished
            ? .finished(summary: summary, remoteWorkoutID: remoteWorkoutID)
            : .failed(summary: summary, remoteWorkoutID: remoteWorkoutID)
    }

    /// Called only after the app's completion outbox and canonical/alias reward
    /// transaction are durable. A failed queue write leaves this replayable.
    @discardableResult
    func acknowledgeDeferredWatchTerminal(
        _ state: PawPaceRunState,
        summaryID: UUID
    ) -> Bool {
        guard state.phase == .finished || state.phase == .failed,
              let remoteWorkoutID = state.workoutID else { return false }
        var records = loadPendingWatchRecords()
        guard !pendingHealthReadFailed else { return false }
        if let index = records.firstIndex(where: { $0.summary.id == summaryID }) {
            if state.phase == .finished {
                records.remove(at: index)
            } else {
                records[index].requiresPhoneSave = true
            }
            guard savePendingWatchRecords(records) else { return false }
        }
        if state.phase == .finished, completedSummaryAwaitingWatchSave?.id == summaryID {
            completedSummaryAwaitingWatchSave = nil
        }
        markDeferredTerminalHandled(remoteWorkoutID)
        return true
    }

    func consumePreviouslyRewardedWatchTerminal(_ state: PawPaceRunState) -> Bool {
        guard let remoteWorkoutID = state.workoutID else { return false }
        // An exact pending record still needs its Watch save result resolved.
        // Only consume an unmatched duplicate before it can be adopted as a
        // newer back-to-back run or alter HealthKit's mirrored identity.
        let hasExactPendingRecord = loadPendingWatchRecords().contains {
            $0.summary.id == remoteWorkoutID
        }
        guard PawPaceSyncPolicy.shouldConsumePreviouslyRewardedTerminal(
            state,
            wasTerminalHandled: handledDeferredTerminalIDs().contains(remoteWorkoutID),
            hasRegisteredReward: PawPaceShared.hasRegisteredReward(for: remoteWorkoutID),
            hasExactPendingRecord: hasExactPendingRecord
        ) else { return false }
        markDeferredTerminalHandled(remoteWorkoutID)
        return true
    }

    @discardableResult
    func applyWatchState(
        _ state: PawPaceRunState,
        allowWorkoutAdoption: Bool = false
    ) -> Bool {
        guard state.phase != .idle else { return false }
        guard PawPaceSyncPolicy.shouldAcceptRun(
            state,
            currentWorkoutID: workoutID,
            latestUpdate: latestWatchState?.updatedAt,
            allowWorkoutAdoption: allowWorkoutAdoption
        ), let remoteWorkoutID = state.workoutID else { return false }
        let confirmsPhoneIdentity = awaitingFirstWatchIdentity && workoutID == remoteWorkoutID
        if workoutID == nil || workoutID != remoteWorkoutID {
            workoutID = remoteWorkoutID
        }
        if allowWorkoutAdoption || confirmsPhoneIdentity {
            if confirmsPhoneIdentity {
                Self.syncLog.notice(
                    "confirmed phone identity workout=\(remoteWorkoutID.uuidString, privacy: .private) phase=\(state.phase.rawValue, privacy: .private)"
                )
            }
            awaitingFirstWatchIdentity = false
            hasPendingPhoneWatchLaunch = false
            pendingWatchBindingID = nil
            respondedWatchBindingIDs.removeAll()
        }

        watchWorkoutParticipated = true
        clearCheckpoint(matching: remoteWorkoutID)
        recoveredWorkoutMessage = nil
        latestWatchState = state
        if state.phase == .finished {
            completedSummaryAwaitingWatchSave = nil
        }
        if let remoteStartedAt = state.startedAt {
            self.startedAt = remoteStartedAt
        }
        if state.heartRate > 0 {
            heartRate = state.heartRate
        }
        configuration = state.workoutConfiguration
        activeEnergyKilocalories = max(0, state.activeEnergyKilocalories)
        multisportLegIndex = max(0, state.multisportLegIndex)
        if let pendingMultisportLegIndex, state.multisportLegIndex >= pendingMultisportLegIndex {
            self.pendingMultisportLegIndex = nil
            isAdvancingActivity = false
        }
        activitySegments = state.activitySegments
        pauseIntervals = state.pauseIntervals
        pauseStartedAt = state.pauseStartedAt
        if !currentActivityConfiguration.supportsRoute {
            locationManager.stopUpdatingLocation()
            route = []
        }
        distanceMeters = configuration.supportsDistance ? max(0, state.distanceKilometers * 1_000) : 0
        elapsedSeconds = max(0, state.elapsedSeconds)
        accumulatedSeconds = Double(elapsedSeconds)
        if state.phase == .running {
            segmentStartedAt = state.updatedAt
        } else {
            segmentStartedAt = nil
        }
        publishLiveActivity(force: true)
        return true
    }

    func canAdoptConnectivityState(_ state: PawPaceRunState) -> Bool {
        guard
            awaitingFirstWatchIdentity,
            state.workoutConfiguration == configuration,
            hasPendingPhoneWatchLaunch,
            phase == .running || phase == .paused || phase == .finished,
            let localStart = startedAt
        else { return false }
        return PawPaceSyncPolicy.canAdoptPendingPhoneLaunch(
            from: state,
            localStart: localStart
        )
    }

    func handleWatchLaunchChallenge(_ state: PawPaceRunState) -> Bool {
        guard
            awaitingFirstWatchIdentity,
            state.workoutConfiguration.activity == configuration.activity,
            hasPendingPhoneWatchLaunch,
            phase == .running || phase == .paused || phase == .finished,
            state.phase == .running || state.phase == .paused || state.isAwaitingPhoneConfiguration,
            let phoneWorkoutID = workoutID,
            let provisionalWatchWorkoutID = state.workoutID,
            provisionalWatchWorkoutID != phoneWorkoutID,
            let localStart = startedAt,
            PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(from: state, localStart: localStart)
        else { return false }

        pendingWatchBindingID = provisionalWatchWorkoutID
        guard respondedWatchBindingIDs.insert(provisionalWatchWorkoutID).inserted else {
            return true
        }

        Self.syncLog.notice(
            "answer challenge phone=\(phoneWorkoutID.uuidString, privacy: .private) watch=\(provisionalWatchWorkoutID.uuidString, privacy: .private) watchPhase=\(state.phase.rawValue, privacy: .private)"
        )

        let action: PawPaceWatchControlAction
        switch phase {
        case .running: action = .start
        case .paused: action = .pause
        case .finished: action = .finish
        case .idle: return false
        }
        sendWatchControl(action, replyToWatchWorkoutID: provisionalWatchWorkoutID)
        return true
    }

    private func sendWatchControl(
        _ action: PawPaceWatchControlAction,
        pet: PetSnapshot? = nil,
        replyToWatchWorkoutID: UUID? = nil
    ) {
        let replyID = replyToWatchWorkoutID ?? pendingWatchBindingID
        guard let payload = watchConnectivity.sendControl(
            pet: pet ?? petSnapshot(),
            run: currentRunState,
            action: action,
            replyToWatchWorkoutID: replyID
        ) else { return }
        healthKit.sendToMirroredWorkout(payload)
    }

    private func waitForFinalWatchState() async {
        var pendingIdentityChecks = 0
        for _ in 0..<300 {
            if
                let latestWatchState,
                latestWatchState.phase == .finished,
                latestWatchState.workoutID == workoutID
            {
                return
            }
            if !watchWorkoutParticipated {
                guard hasPendingPhoneWatchLaunch else { return }
                pendingIdentityChecks += 1
                // Give a successfully launched Watch a brief chance to send
                // its nonce/terminal state before the phone saves a fallback.
                if pendingIdentityChecks >= 50 { return }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func storePendingWatchRecord(_ summary: RunSummary) {
        var records = loadPendingWatchRecords()
        records.removeAll { $0.summary.id == summary.id }
        records.append(PendingWatchHealthRecord(summary: summary, requiresPhoneSave: false))
        savePendingWatchRecords(records)
    }

    private func removePendingWatchRecord(summaryID: UUID) {
        var records = loadPendingWatchRecords()
        records.removeAll { $0.summary.id == summaryID }
        savePendingWatchRecords(records)
    }

    private func markPendingWatchRecordForPhoneSave(summaryID: UUID) {
        var records = loadPendingWatchRecords()
        guard let index = records.firstIndex(where: { $0.summary.id == summaryID }) else { return }
        records[index].requiresPhoneSave = true
        savePendingWatchRecords(records)
    }

    private func loadPendingWatchRecords() -> [PendingWatchHealthRecord] {
        pendingHealthReadFailed = false
        guard let privateStorage else {
            pendingHealthReadFailed = true
            recoveryStorageMessage = "Protected workout storage is unavailable. Please reopen PawPace after unlocking your iPhone."
            return []
        }
        do {
            return try privateStorage.load(
                [PendingWatchHealthRecord].self,
                named: Self.pendingHealthFilename,
                legacyDefaults: legacyDefaults,
                legacyKey: PendingWatchHealthRecord.storageKey
            ) ?? []
        } catch {
            pendingHealthReadFailed = true
            recoveryStorageMessage = "Pending Health saves couldn’t be read. The saved data has been kept."
            return []
        }
    }

    @discardableResult
    private func savePendingWatchRecords(_ records: [PendingWatchHealthRecord]) -> Bool {
        guard let privateStorage else { return false }
        do {
            try privateStorage.save(
                records,
                named: Self.pendingHealthFilename,
                legacyDefaults: legacyDefaults,
                legacyKey: PendingWatchHealthRecord.storageKey
            )
            return true
        } catch {
            recoveryStorageMessage = "A pending Health save couldn’t be stored. Your recorded workout can still be saved to your companion and journal."
            return false
        }
    }

    /// Force a checkpoint when the app leaves the foreground. Only confirmed
    /// phone-only sessions qualify; a Watch remains the authority for its run.
    func checkpointInterruptedWorkout() {
        if phase == .running, let segmentStartedAt {
            elapsedSeconds = max(0, Int((accumulatedSeconds + Date().timeIntervalSince(segmentStartedAt)).rounded()))
        }
        saveCheckpoint(force: true)
    }

    @discardableResult
    func restoreInterruptedWorkout() -> Bool {
        guard !isFinishing, phase == .idle || phase == .finished,
              !healthKit.hasActiveMirroredWorkout,
              !(watchWorkoutParticipated && (latestWatchState?.phase == .running || latestWatchState?.phase == .paused)),
              let interruptedWorkout,
              let checkpoint = PhoneWorkoutCheckpoint(state: interruptedWorkout),
              let restored = checkpoint.pausedState()
        else { return false }
        guard let identifier = restored.workoutID,
              !PawPaceShared.hasRegisteredReward(for: identifier)
        else {
            clearCheckpoint(matching: interruptedWorkout.workoutID)
            return false
        }

        configuration = restored.workoutConfiguration
        phase = .paused
        workoutID = restored.workoutID
        startedAt = restored.startedAt
        elapsedSeconds = restored.elapsedSeconds
        accumulatedSeconds = Double(restored.elapsedSeconds)
        segmentStartedAt = nil
        distanceMeters = restored.distanceKilometers * 1_000
        activeEnergyKilocalories = restored.activeEnergyKilocalories
        heartRate = restored.heartRate > 0 ? restored.heartRate : nil
        multisportLegIndex = restored.multisportLegIndex
        activitySegments = restored.activitySegments
        pauseIntervals = restored.pauseIntervals
        pauseStartedAt = restored.pauseStartedAt
        route = []
        lastLocation = nil
        latestWatchState = nil
        watchWorkoutParticipated = false
        awaitingFirstWatchIdentity = false
        hasPendingPhoneWatchLaunch = false
        pendingWatchBindingID = nil
        pendingMultisportLegIndex = nil
        isAdvancingActivity = false
        completedSummaryAwaitingWatchSave = nil
        respondedWatchBindingIDs.removeAll()
        watchStartTask?.cancel()
        watchStartTask = nil
        self.interruptedWorkout = nil
        recoveredWorkoutMessage = "Your recorded workout is paused. Time while PawPace was closed hasn’t been counted. Resume when you’re ready, or finish to save it."
        PawPaceShared.defaults.set(true, forKey: PawPaceShared.runPausedKey)
        locationManager.stopUpdatingLocation()
        startTimer()
        liveActivity.start(pet: petSnapshot(), targetKilometers: 3, configuration: configuration)
        publishLiveActivity(force: true)
        saveCheckpoint(force: true)
        return true
    }

    /// The app calls this only after its local completion transaction succeeds.
    func acknowledgeWorkoutSaved(_ identifier: UUID) {
        clearCheckpoint(matching: identifier)
        recoveredWorkoutMessage = nil
    }

    @discardableResult
    func discardInterruptedWorkout() -> Bool {
        guard let identifier = interruptedWorkout?.workoutID else { return true }
        return clearCheckpoint(matching: identifier)
    }

    private func loadInterruptedWorkout() {
        guard let privateStorage else {
            recoveryStorageMessage = "Protected workout storage is unavailable. Please reopen PawPace after unlocking your iPhone."
            return
        }
        do {
            guard let checkpoint = try privateStorage.load(PhoneWorkoutCheckpoint.self, named: Self.checkpointFilename),
                  let restored = checkpoint.pausedState(), let identifier = restored.workoutID
            else { return }
            savedCheckpointWorkoutID = identifier
            if PawPaceShared.hasRegisteredReward(for: identifier) {
                try privateStorage.remove(named: Self.checkpointFilename)
                savedCheckpointWorkoutID = nil
            } else {
                interruptedWorkout = checkpoint.state
            }
        } catch {
            recoveryStorageMessage = "Your interrupted workout couldn’t be read. The saved file has been kept."
        }
    }

    private func saveCheckpoint(force: Bool) {
        guard phase == .running || phase == .paused,
              !watchWorkoutParticipated, !hasPendingPhoneWatchLaunch,
              interruptedWorkout == nil || interruptedWorkout?.workoutID == workoutID,
              force || Date().timeIntervalSince(lastRecoveryCheckpoint) >= 5,
              let checkpoint = PhoneWorkoutCheckpoint(state: currentRunState)
        else { return }
        guard let privateStorage else { return }
        do {
            try privateStorage.save(checkpoint, named: Self.checkpointFilename)
            savedCheckpointWorkoutID = checkpoint.state.workoutID
            lastRecoveryCheckpoint = .now
        } catch {
            recoveryStorageMessage = "The interrupted-workout checkpoint couldn’t be saved. Keep PawPace open until you finish this workout."
        }
    }

    @discardableResult
    private func clearCheckpoint(matching identifier: UUID?) -> Bool {
        guard let identifier else { return false }
        guard savedCheckpointWorkoutID == identifier || interruptedWorkout?.workoutID == identifier else { return true }
        guard let privateStorage else { return false }
        do {
            let saved = try privateStorage.load(PhoneWorkoutCheckpoint.self, named: Self.checkpointFilename)
            if saved?.state.workoutID == identifier {
                try privateStorage.remove(named: Self.checkpointFilename)
            }
            if savedCheckpointWorkoutID == identifier { savedCheckpointWorkoutID = nil }
            if interruptedWorkout?.workoutID == identifier { interruptedWorkout = nil }
            return true
        } catch {
            recoveryStorageMessage = "The interrupted-workout checkpoint couldn’t be removed. It has been kept for your next visit."
            return false
        }
    }

    private func handledDeferredTerminalIDs() -> [UUID] {
        (legacyDefaults.stringArray(forKey: Self.handledDeferredTerminalStorageKey) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    private func markDeferredTerminalHandled(_ workoutID: UUID) {
        var identifiers = handledDeferredTerminalIDs()
        identifiers.removeAll { $0 == workoutID }
        identifiers.append(workoutID)
        if identifiers.count > 128 {
            identifiers.removeFirst(identifiers.count - 128)
        }
        legacyDefaults.set(
            identifiers.map(\.uuidString),
            forKey: Self.handledDeferredTerminalStorageKey
        )
    }

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        if phase == .running, let segmentStartedAt {
            elapsedSeconds = Int((accumulatedSeconds + Date().timeIntervalSince(segmentStartedAt)).rounded())
        } else {
            elapsedSeconds = Int(accumulatedSeconds.rounded())
        }

        if !watchWorkoutParticipated, Date().timeIntervalSince(lastHeartRateUpdate) >= 10 {
            lastHeartRateUpdate = .now
            let queriedWorkoutID = workoutID
            let queriedConfiguration = configuration
            let queriedStartedAt = startedAt
            let intervals = startedAt.map {
                WorkoutTiming.activeIntervals(startedAt: $0, endedAt: .now, pauseIntervals: pauseIntervals, pauseStartedAt: pauseStartedAt)
            } ?? []
            Task { [weak self] in
                guard let self else { return }
                let latest = await healthKit.latestHeartRate(since: queriedStartedAt)
                let measuredEnergy = await healthKit.activeEnergy(during: intervals)
                var measuredDistance: Double?
                if queriedConfiguration.supportsDistance, !queriedConfiguration.supportsRoute {
                    measuredDistance = await healthKit.distance(during: intervals, configuration: queriedConfiguration)
                }
                guard workoutID == queriedWorkoutID, !watchWorkoutParticipated else { return }
                if let latest {
                    heartRate = latest
                }
                if let measuredEnergy { activeEnergyKilocalories = measuredEnergy }
                if let measuredDistance { distanceMeters = measuredDistance }
            }
        }
        publishLiveActivity(force: false)
        saveCheckpoint(force: false)
    }

    private func publishLiveActivity(force: Bool) {
        guard force || Date().timeIntervalSince(lastLiveActivityUpdate) >= 5 else { return }
        lastLiveActivityUpdate = .now
        let state = activityState(encouragement: encouragement)
        let pet = petSnapshot()
        let payload = PawPaceWatchPayload(pet: pet, run: currentRunState)
        watchConnectivity.sync(pet: pet, run: payload.run)
        healthKit.sendToMirroredWorkout(payload)
        Task { await liveActivity.update(with: state) }
    }

    private var encouragement: String {
        if !configuration.supportsDistance { return "Every minute together counts." }
        return switch distanceKilometers {
        case ..<0.5: "Easy paws first—find your rhythm."
        case ..<1.5: "Great pace! The trail is opening up."
        case ..<2.5: "I can smell quest rewards ahead!"
        default: "Final stretch—maximum zoomies!"
        }
    }

    private func activityState(encouragement: String) -> PawPaceActivityAttributes.ContentState {
        let pet = petSnapshot()
        return PawPaceActivityAttributes.ContentState(
            distanceKilometers: distanceKilometers,
            elapsedSeconds: elapsedSeconds,
            paceSecondsPerKilometer: paceSecondsPerKilometer,
            heartRate: heartRate ?? 0,
            experienceEarned: experienceEarned,
            isPaused: phase == .paused,
            encouragement: encouragement,
            petMood: pet.mood,
            petStage: pet.stage,
            petEnergy: pet.energy,
            petAccessory: pet.equippedAccessory,
            petSpecies: pet.lifeStage == .egg ? nil : pet.species,
            workoutConfiguration: configuration,
            activeEnergyKilocalories: activeEnergyKilocalories,
            petLifeStage: pet.lifeStage,
            petVariant: pet.lifeStage == .egg ? nil : pet.lifecycle?.variant
        )
    }

    var currentRunState: PawPaceRunState {
        PawPaceRunState(
            workoutID: workoutID,
            phase: phase.watchPhase,
            distanceKilometers: distanceKilometers,
            elapsedSeconds: elapsedSeconds,
            paceSecondsPerKilometer: paceSecondsPerKilometer,
            heartRate: heartRate ?? 0,
            experienceEarned: experienceEarned,
            encouragement: encouragement,
            startedAt: startedAt,
            updatedAt: .now,
            workoutConfiguration: configuration,
            activeEnergyKilocalories: activeEnergyKilocalories,
            multisportLegIndex: max(multisportLegIndex, pendingMultisportLegIndex ?? 0),
            activitySegments: refreshedActivitySegments(endingAt: phase == .finished ? .now : nil),
            pauseIntervals: pauseIntervals,
            pauseStartedAt: pauseStartedAt
        )
    }
}

private struct PendingWatchHealthRecord: Codable {
    static let storageKey = "pawpace.pendingWatchHealthRecords.v1"
    let summary: RunSummary
    var requiresPhoneSave: Bool

    init(summary: RunSummary, requiresPhoneSave: Bool) {
        self.summary = summary
        self.requiresPhoneSave = requiresPhoneSave
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(RunSummary.self, forKey: .summary)
        requiresPhoneSave = try container.decodeIfPresent(Bool.self, forKey: .requiresPhoneSave) ?? false
    }
}

private extension RunTracker.Phase {
    var watchPhase: PawPaceRunPhase {
        switch self {
        case .idle: .idle
        case .running: .running
        case .paused: .paused
        case .finished: .finished
        }
    }
}

extension RunTracker: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorization = manager.authorizationStatus
        if currentActivityConfiguration.supportsRoute, phase == .running, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .running, currentActivityConfiguration.supportsRoute else { return }

        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 30 {
            guard abs(location.timestamp.timeIntervalSinceNow) < 15 else { continue }

            if configuration.supportsDistance, !watchWorkoutParticipated, let lastLocation {
                let delta = location.distance(from: lastLocation)
                if delta >= 1, delta <= 100 {
                    distanceMeters += delta
                }
            }

            lastLocation = location
            route.append(location.coordinate)
        }
    }
}
