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

    var distanceKilometers: Double { distanceMeters / 1_000 }
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

    init(
        healthKit: HealthKitService,
        petSnapshot: @escaping () -> PetSnapshot,
        watchConnectivity: PhoneWatchConnectivityService
    ) {
        self.healthKit = healthKit
        self.petSnapshot = petSnapshot
        self.watchConnectivity = watchConnectivity
        self.locationAuthorization = locationManager.authorizationStatus
        super.init()

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

    var paceSecondsPerKilometer: Int {
        guard distanceMeters >= 50 else { return 0 }
        return Int(Double(elapsedSeconds) / distanceKilometers)
    }

    var experienceEarned: Int {
        max(0, Int((distanceKilometers * 52).rounded()))
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func start(syncToWatch: Bool = true) {
        guard !isFinishing, phase == .idle || phase == .finished else { return }

        if locationAuthorization == .notDetermined {
            requestLocationPermission()
        }

        phase = .running
        distanceMeters = 0
        elapsedSeconds = 0
        route = []
        heartRate = nil
        accumulatedSeconds = 0
        lastLocation = nil
        startedAt = .now
        segmentStartedAt = .now
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
        locationManager.startUpdatingLocation()
        startTimer()
        let pet = petSnapshot()
        liveActivity.start(pet: pet, targetKilometers: 3)
        publishLiveActivity(force: true)
        if syncToWatch {
            sendWatchControl(.start, pet: pet)
            let launchedWorkoutID = workoutID ?? UUID()
            let launchedStartedAt = startedAt ?? .now
            watchStartTask = Task { [weak self, healthKit] in
                let succeeded = await healthKit.startWatchWorkout(
                    workoutID: launchedWorkoutID,
                    startedAt: launchedStartedAt
                )
                if !succeeded {
                    self?.awaitingFirstWatchIdentity = false
                    self?.hasPendingPhoneWatchLaunch = false
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
        locationManager.stopUpdatingLocation()
        lastLocation = nil
        PawPaceShared.defaults.set(true, forKey: PawPaceShared.runPausedKey)
        if syncToWatch {
            healthKit.pauseMirroredWorkout(workoutID: workoutID)
            sendWatchControl(.pause)
        }
        tick()
        publishLiveActivity(force: true)
    }

    func resume(syncToWatch: Bool = true) {
        guard phase == .paused else { return }
        phase = .running
        segmentStartedAt = .now
        PawPaceShared.defaults.set(false, forKey: PawPaceShared.runPausedKey)
        locationManager.startUpdatingLocation()
        if syncToWatch {
            healthKit.resumeMirroredWorkout(workoutID: workoutID)
            sendWatchControl(.resume)
        }
        publishLiveActivity(force: true)
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
        let shouldAwaitWatchFinalState = watchWorkoutParticipated || watchStartTask != nil

        if let watchStartTask {
            _ = await watchStartTask.value
            self.watchStartTask = nil
        }

        if syncToWatch {
            healthKit.endMirroredWorkout(workoutID: workoutID)
            sendWatchControl(.finish)
        }

        if shouldAwaitWatchFinalState {
            await waitForFinalWatchState()
        }

        let summary = RunSummary(
            id: workoutID ?? UUID(),
            startedAt: self.startedAt ?? startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            averagePaceSecondsPerKilometer: paceSecondsPerKilometer,
            averageHeartRate: heartRate,
            experienceEarned: experienceEarned
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
        phase = .idle
        distanceMeters = 0
        elapsedSeconds = 0
        route = []
        heartRate = nil
        accumulatedSeconds = 0
        startedAt = nil
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
        watchConnectivity.sync(pet: petSnapshot(), run: .idle)
    }

    func markWatchWorkoutActive() {
        watchWorkoutParticipated = true
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
        awaitingFirstWatchIdentity = false
        hasPendingPhoneWatchLaunch = false
        pendingWatchBindingID = nil
        respondedWatchBindingIDs.removeAll()
        latestWatchState = nil
        watchStartTask?.cancel()
        watchStartTask = nil
        return fallbackSummary
    }

    func pendingFailedWatchSummaries() -> [RunSummary] {
        loadPendingWatchRecords()
            .filter(\.requiresPhoneSave)
            .map(\.summary)
    }

    func queueFailedWatchHealthFallback(_ summary: RunSummary) {
        var records = loadPendingWatchRecords()
        records.removeAll { $0.summary.id == summary.id }
        records.append(PendingWatchHealthRecord(summary: summary, requiresPhoneSave: true))
        savePendingWatchRecords(records)
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

    func resolveDeferredWatchTerminal(
        _ state: PawPaceRunState
    ) -> DeferredWatchTerminalResolution? {
        guard
            state.phase == .finished || state.phase == .failed,
            let remoteWorkoutID = state.workoutID,
            let remoteStartedAt = state.startedAt,
            !handledDeferredTerminalIDs().contains(remoteWorkoutID)
        else { return nil }

        var records = loadPendingWatchRecords()
        let matchingIndex: Int?
        if let exactIndex = records.firstIndex(where: { $0.summary.id == remoteWorkoutID }) {
            matchingIndex = exactIndex
        } else if PawPaceShared.hasRegisteredReward(for: remoteWorkoutID) {
            // A duplicate terminal from a previously completed run must never
            // fuzzy-match a newer back-to-back run that happens to start nearby.
            markDeferredTerminalHandled(remoteWorkoutID)
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

        var record = records[matchingIndex]
        if state.phase == .finished {
            records.remove(at: matchingIndex)
            savePendingWatchRecords(records)
            if completedSummaryAwaitingWatchSave?.id == record.summary.id {
                completedSummaryAwaitingWatchSave = nil
            }
            markDeferredTerminalHandled(remoteWorkoutID)
            return .finished(summary: record.summary, remoteWorkoutID: remoteWorkoutID)
        }
        record.requiresPhoneSave = true
        records[matchingIndex] = record
        savePendingWatchRecords(records)
        markDeferredTerminalHandled(remoteWorkoutID)
        return .failed(summary: record.summary, remoteWorkoutID: remoteWorkoutID)
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
                    "confirmed phone identity workout=\(remoteWorkoutID.uuidString, privacy: .public) phase=\(state.phase.rawValue, privacy: .public)"
                )
            }
            awaitingFirstWatchIdentity = false
            hasPendingPhoneWatchLaunch = false
            pendingWatchBindingID = nil
            respondedWatchBindingIDs.removeAll()
        }

        watchWorkoutParticipated = true
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
        distanceMeters = max(0, state.distanceKilometers * 1_000)
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
            hasPendingPhoneWatchLaunch,
            phase == .running || phase == .paused || phase == .finished,
            state.phase == .running || state.phase == .paused,
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
            "answer challenge phone=\(phoneWorkoutID.uuidString, privacy: .public) watch=\(provisionalWatchWorkoutID.uuidString, privacy: .public) watchPhase=\(state.phase.rawValue, privacy: .public)"
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
        guard
            let data = PawPaceShared.defaults.data(forKey: PendingWatchHealthRecord.storageKey),
            let records = try? JSONDecoder().decode([PendingWatchHealthRecord].self, from: data)
        else { return [] }
        return records
    }

    private func savePendingWatchRecords(_ records: [PendingWatchHealthRecord]) {
        if records.isEmpty {
            PawPaceShared.defaults.removeObject(forKey: PendingWatchHealthRecord.storageKey)
        } else if let data = try? JSONEncoder().encode(records) {
            PawPaceShared.defaults.set(data, forKey: PendingWatchHealthRecord.storageKey)
        }
    }

    private func handledDeferredTerminalIDs() -> [UUID] {
        (PawPaceShared.defaults.stringArray(forKey: Self.handledDeferredTerminalStorageKey) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    private func markDeferredTerminalHandled(_ workoutID: UUID) {
        var identifiers = handledDeferredTerminalIDs()
        identifiers.removeAll { $0 == workoutID }
        identifiers.append(workoutID)
        if identifiers.count > 128 {
            identifiers.removeFirst(identifiers.count - 128)
        }
        PawPaceShared.defaults.set(
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
            Task { [weak self] in
                guard let self else { return }
                if let latest = await healthKit.latestHeartRate() {
                    heartRate = latest
                }
            }
        }
        publishLiveActivity(force: false)
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
        switch distanceKilometers {
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
            petAccessory: pet.equippedAccessory
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
            updatedAt: .now
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
        if phase == .running, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .running else { return }

        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 30 {
            guard abs(location.timestamp.timeIntervalSinceNow) < 15 else { continue }

            if !watchWorkoutParticipated, let lastLocation {
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
