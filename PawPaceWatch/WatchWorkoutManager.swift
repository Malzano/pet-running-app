import Combine
import Foundation
import HealthKit
import OSLog

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()
    private static let syncLog = Logger(subsystem: "com.pawpace.app.sync", category: "watch-workout")

    @Published private(set) var selectedConfiguration = WorkoutConfiguration()
    @Published private(set) var state: PawPaceRunState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var isStarting = false

    var onStateChange: ((PawPaceRunState) -> Void)?
    var onRemotePayload: ((PawPaceWatchPayload) -> Void)?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var sessionIdentifier: ObjectIdentifier?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: AnyCancellable?
    private var segmentStartedAt: Date?
    private var accumulatedSeconds: TimeInterval = 0
    private var lastPublishedAt = Date.distantPast
    private var isCompleting = false
    private var isRecovering = false
    private var pendingPhoneControl: PawPaceRunPhase?
    private var latestPhoneControlUpdateByWorkout: [UUID: Date] = [:]
    private var handledPhoneControlIDs: [UUID: Date] = [:]
    private var queuedPhoneControls: [UUID: PawPaceWatchControl] = [:]
    private var awaitingPhoneBinding = false
    private var recoveryMetadataReadFailed = false
    private var recoveryMetadataNeedsRetry = false

    private override init() {
        super.init()
    }

    func configure(_ configuration: WorkoutConfiguration) {
        guard !isStarting, !isCompleting, state.phase == .idle || state.phase == .finished || state.phase == .failed else { return }
        selectedConfiguration = configuration.normalized
    }

    func start(configuration: HKWorkoutConfiguration? = nil) {
        guard
            !isStarting,
            !isCompleting,
            !isRecovering,
            state.phase == .idle || state.phase == .finished || state.phase == .failed
        else { return }
        isStarting = true
        let now = Date()
        let attemptedStart = now
        awaitingPhoneBinding = configuration != nil
        if let configuration { selectedConfiguration = WorkoutConfiguration(healthKit: configuration) }
        errorMessage = nil
        state = PawPaceRunState(
            workoutID: UUID(),
            phase: .idle,
            distanceKilometers: 0,
            elapsedSeconds: 0,
            paceSecondsPerKilometer: 0,
            heartRate: 0,
            experienceEarned: 0,
            encouragement: "Adventure starting…",
            startedAt: attemptedStart,
            updatedAt: attemptedStart,
            workoutConfiguration: selectedConfiguration
        )
        if selectedConfiguration.activity.requiresMultisportSession {
            state.activitySegments = [WorkoutActivitySegment(configuration: selectedConfiguration.configuration(forMultisportLeg: 0), startedAt: attemptedStart, endedAt: nil)]
        }
        pendingPhoneControl = nil
        replayQueuedPhoneControlIfMatching()
        Task { [weak self] in
            guard let self else { return }
            await beginWorkout(configuration: configuration)
            isStarting = false
        }
    }

    func pause() {
        guard state.phase == .running else { return }
        session?.pause()
    }

    func resume() {
        guard state.phase == .paused else { return }
        session?.resume()
    }

    func finish() {
        guard state.phase == .running || state.phase == .paused else { return }
        session?.stopActivity(with: .now)
    }

    func recoverActiveWorkout() {
        guard !isStarting, !isCompleting, !isRecovering, session == nil else { return }
        isRecovering = true
        healthStore.recoverActiveWorkoutSession { [weak self] session, error in
            Task { @MainActor in
                guard let self else { return }
                defer { self.isRecovering = false }
                guard !self.isStarting, !self.isCompleting, self.session == nil else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let session else {
                    self.clearRecoveryMetadata()
                    return
                }
                self.attachRecoveredSession(session)
            }
        }
    }

    func applyPhoneControl(_ control: PawPaceWatchControl) {
        Self.syncLog.notice(
            "control action=\(control.action.rawValue, privacy: .private) incoming=\(control.workoutID.uuidString, privacy: .private) local=\(self.state.workoutID?.uuidString ?? "-", privacy: .private) reply=\(control.replyToWatchWorkoutID?.uuidString ?? "-", privacy: .private) awaiting=\(self.awaitingPhoneBinding)"
        )
        guard handledPhoneControlIDs[control.id] == nil else { return }
        handledPhoneControlIDs[control.id] = control.issuedAt
        if handledPhoneControlIDs.count > 128,
           let oldest = handledPhoneControlIDs.min(by: { $0.value < $1.value })?.key {
            handledPhoneControlIDs.removeValue(forKey: oldest)
        }
        guard control.issuedAt > latestPhoneControlUpdateByWorkout[control.workoutID, default: .distantPast] else {
            return
        }
        latestPhoneControlUpdateByWorkout[control.workoutID] = control.issuedAt

        guard let localWorkoutID = state.workoutID else {
            queuePhoneControl(control)
            return
        }
        let matchingIdentity = localWorkoutID == control.workoutID
        // The phone can bind a manually started Watch run too, provided it
        // echoes this exact run's nonce. That remains explicit and cannot bind
        // an unrelated or stale Watch workout.
        let canRebindCurrentState = state.phase == .idle
            || state.phase == .running
            || state.phase == .paused
        let matchingBinding = canRebindCurrentState
            && state.workoutConfiguration.activity == control.workoutConfiguration.activity
            && PawPaceSyncPolicy.canBindPhoneControl(
                control,
                provisionalWatchWorkoutID: localWorkoutID
            )
        guard matchingIdentity || matchingBinding else {
            Self.syncLog.notice("queue unmatched action=\(control.action.rawValue, privacy: .private)")
            queuePhoneControl(control)
            return
        }

        if matchingBinding {
            Self.syncLog.notice(
                "bind phone=\(control.workoutID.uuidString, privacy: .private) watch=\(localWorkoutID.uuidString, privacy: .private)"
            )
            state.workoutID = control.workoutID
            awaitingPhoneBinding = false
            if session != nil {
                persistRecoveryMetadata()
            }
        }
        queuedPhoneControls.removeValue(forKey: control.workoutID)
        applyAcceptedPhoneControl(control)
        if matchingBinding {
            publish(force: true)
        }
    }

    private func applyAcceptedPhoneControl(_ control: PawPaceWatchControl) {
        if isStarting, session == nil {
            selectedConfiguration = control.workoutConfiguration.normalized
            state.workoutConfiguration = selectedConfiguration
            state.isAwaitingPhoneConfiguration = false
            if selectedConfiguration.activity.requiresMultisportSession {
                state.activitySegments = [WorkoutActivitySegment(configuration: selectedConfiguration.configuration(forMultisportLeg: 0), startedAt: state.startedAt ?? control.startedAt, endedAt: nil)]
            } else {
                state.activitySegments = []
            }
        }
        // Every control carries the desired leg, so a later pause/finish can
        // safely supersede a next-leg message that arrived out of order.
        while control.multisportLegIndex > state.multisportLegIndex,
              state.workoutConfiguration.activity.requiresMultisportSession,
              state.multisportLegIndex + 1 < state.workoutConfiguration.multisportLegs.count,
              state.phase == .running || state.phase == .paused,
              session != nil {
            advanceMultisportActivity(to: state.multisportLegIndex + 1)
        }
        if control.action == .nextActivity { return }
        if state.phase == control.phase, pendingPhoneControl == nil {
            Self.syncLog.notice("already phase=\(self.state.phase.rawValue, privacy: .private)")
            return
        }
        Self.syncLog.notice(
            "pending phase=\(control.phase.rawValue, privacy: .private) current=\(self.state.phase.rawValue, privacy: .private)"
        )
        pendingPhoneControl = control.phase
        applyPendingPhoneControlIfPossible()
    }

    private func queuePhoneControl(_ control: PawPaceWatchControl) {
        let current = queuedPhoneControls[control.workoutID]
        if control.issuedAt > (current?.issuedAt ?? .distantPast) {
            queuedPhoneControls[control.workoutID] = control
        }
        if queuedPhoneControls.count > 32,
           let oldest = queuedPhoneControls.min(by: { $0.value.issuedAt < $1.value.issuedAt })?.key {
            queuedPhoneControls.removeValue(forKey: oldest)
        }
    }

    private func replayQueuedPhoneControlIfMatching() {
        guard let localWorkoutID = state.workoutID else { return }
        if let exact = queuedPhoneControls.removeValue(forKey: localWorkoutID) {
            applyAcceptedPhoneControl(exact)
            return
        }
        guard
            state.phase == .idle || state.phase == .running || state.phase == .paused
        else { return }
        guard let control = queuedPhoneControls.values
            .filter({
                PawPaceSyncPolicy.canBindPhoneControl(
                    $0,
                    provisionalWatchWorkoutID: localWorkoutID
                )
            })
            .max(by: { $0.issuedAt < $1.issuedAt })
        else { return }
        queuedPhoneControls.removeValue(forKey: control.workoutID)
        state.workoutID = control.workoutID
        awaitingPhoneBinding = false
        if session != nil {
            persistRecoveryMetadata()
        }
        applyAcceptedPhoneControl(control)
        publish(force: true)
    }

    private func beginWorkout(configuration: HKWorkoutConfiguration?) async {
        guard await requestAuthorization() else {
            state.phase = .failed
            state.encouragement = "Health access is required to start this workout."
            state.updatedAt = .now
            onStateChange?(state)
            return
        }

        if awaitingPhoneBinding {
            state.isAwaitingPhoneConfiguration = true
            publish(force: true)
            // The HealthKit launch omits our pool/leg settings. Resolve the exact
            // nonce-bound command before recording any activity or sensor data.
            for _ in 0..<80 {
                guard awaitingPhoneBinding else { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !awaitingPhoneBinding else {
                state.isAwaitingPhoneConfiguration = false
                state.phase = .failed
                state.endedAt = .now
                state.encouragement = "The phone could not send the workout settings. Start again from your Watch."
                errorMessage = state.encouragement
                publish(force: true)
                return
            }
        }
        let workoutConfiguration = selectedConfiguration.makeHealthKitConfiguration()
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: workoutConfiguration)
            let createdSessionIdentifier = ObjectIdentifier(session)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: workoutConfiguration
            )
            session.delegate = self
            builder.delegate = self

            self.session = session
            sessionIdentifier = createdSessionIdentifier
            self.builder = builder
            accumulatedSeconds = 0
            segmentStartedAt = nil
            isCompleting = false
            errorMessage = nil

            session.prepare()
            do {
                try await session.startMirroringToCompanionDevice()
            } catch {
                errorMessage = "Phone sync unavailable. The Watch workout will continue."
            }
            guard
                sessionIdentifier == createdSessionIdentifier,
                self.session === session,
                self.builder === builder,
                !isCompleting
            else { return }

            // state.startedAt remains the launch identity, including when a
            // permission sheet stays open. Active time starts only now, once
            // authorization, configuration binding and mirroring are ready.
            let activeStartedAt = Date()
            state.startedAt = state.startedAt ?? activeStartedAt
            state.excludeSetupTime(until: activeStartedAt)
            segmentStartedAt = activeStartedAt
            persistRecoveryMetadata()
            session.startActivity(with: activeStartedAt)
            if selectedConfiguration.activity.requiresMultisportSession {
                session.beginNewActivity(configuration: selectedConfiguration.configuration(forMultisportLeg: 0).makeHealthKitConfiguration(), date: activeStartedAt, metadata: nil)
            }
            do {
                try await builder.beginCollection(at: activeStartedAt)
            } catch {
                guard
                    sessionIdentifier == createdSessionIdentifier,
                    self.session === session,
                    self.builder === builder,
                    !isCompleting
                else { return }
                throw error
            }
            guard
                sessionIdentifier == createdSessionIdentifier,
                self.session === session,
                self.builder === builder,
                !isCompleting
            else { return }
            let currentPhase = Self.phase(for: session.state)
            guard currentPhase == .running || currentPhase == .paused else { return }
            accumulatedSeconds = max(0, builder.elapsedTime)
            segmentStartedAt = nil
            applySessionPhase(currentPhase, at: .now)
            startTimer()
            publish(force: true)
            applyPendingPhoneControlIfPossible()
        } catch {
            errorMessage = error.localizedDescription
            await abortCurrentSession()
        }
    }

    private func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data is unavailable on this Watch."
            return false
        }

        let workout = HKObjectType.workoutType()
        var shareTypes: Set<HKSampleType> = [workout]
        var readTypes: Set<HKObjectType> = [workout]
        let identifiers = Set(WorkoutActivity.allCases.compactMap(\.distanceQuantityIdentifier))
            .union([.heartRate, .activeEnergyBurned])
        for identifier in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                readTypes.insert(type)
                if identifier != .heartRate {
                    shareTypes.insert(type)
                }
            }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: WatchWorkoutError.authorizationDenied)
                    }
                }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func attachRecoveredSession(_ session: HKWorkoutSession) {
        isStarting = false
        errorMessage = nil
        let recovery = loadRecoveryMetadata()
        selectedConfiguration = recovery?.configuration ?? WorkoutConfiguration(healthKit: session.workoutConfiguration)
        awaitingPhoneBinding = recovery?.awaitingPhoneBinding ?? false
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: session.workoutConfiguration
        )
        session.delegate = self
        builder.delegate = self
        self.session = session
        let recoveredSessionIdentifier = ObjectIdentifier(session)
        sessionIdentifier = recoveredSessionIdentifier
        self.builder = builder
        let restoredWorkoutID = recovery?.workoutID ?? UUID()
        let restoredStartDate = recovery?.startedAt ?? session.startDate ?? .now
        accumulatedSeconds = max(0, builder.elapsedTime)
        segmentStartedAt = nil
        state = PawPaceSyncPolicy.recoveredRunState(
            workoutID: restoredWorkoutID,
            persistedStart: restoredStartDate,
            sessionStart: session.startDate,
            elapsedSeconds: accumulatedSeconds
        )
        state.workoutConfiguration = selectedConfiguration
        state.multisportLegIndex = recovery?.multisportLegIndex ?? 0
        state.activitySegments = recovery?.activitySegments ?? []
        restorePauseIntervals(from: builder.workoutEvents)
        if let activeStartedAt = session.startDate {
            state.excludeSetupTime(until: activeStartedAt)
        }
        if session.state == .stopped {
            let endedAt = session.endDate ?? .now
            restoreCurrentStatistics(from: builder, publishUpdates: false)
            applySessionPhase(.finished, at: endedAt, publishChange: false)
            replayQueuedPhoneControlIfMatching()
            persistRecoveryMetadata()
            Task { [weak self] in
                await self?.completeWorkout(
                    at: endedAt,
                    sessionIdentifier: recoveredSessionIdentifier
                )
            }
            return
        }
        replayQueuedPhoneControlIfMatching()
        persistRecoveryMetadata()
        applySessionPhase(Self.phase(for: session.state), at: .now)
        restoreCurrentStatistics(from: builder)
        startTimer()
        publish(force: true)
    }

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick(publishUpdates: Bool = true) {
        let elapsed = accumulatedSeconds + (segmentStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
        state.elapsedSeconds = max(Int(elapsed.rounded()), 0)
        state.paceSecondsPerKilometer = state.workoutConfiguration.supportsPace && state.distanceKilometers >= 0.05
            ? Int(Double(state.elapsedSeconds) / state.distanceKilometers)
            : 0
        state.experienceEarned = state.workoutConfiguration.activity.experienceEarned(elapsedSeconds: state.elapsedSeconds, distanceKilometers: state.distanceKilometers)
        state.encouragement = encouragement(for: state.distanceKilometers)
        state.updatedAt = .now
        if publishUpdates {
            publish(force: false)
        }
    }

    private func applySessionPhase(
        _ phase: PawPaceRunPhase,
        at date: Date,
        publishChange: Bool = true
    ) {
        switch phase {
        case .running:
            if let pauseStartedAt = state.pauseStartedAt {
                state.pauseIntervals.append(DateInterval(start: pauseStartedAt, end: max(date, pauseStartedAt)))
                state.pauseStartedAt = nil
            }
            if segmentStartedAt == nil {
                segmentStartedAt = date
            }
        case .paused, .finished, .failed:
            if phase == .paused, state.pauseStartedAt == nil {
                state.pauseStartedAt = date
            } else if phase != .paused, let pauseStartedAt = state.pauseStartedAt {
                state.pauseIntervals.append(DateInterval(start: pauseStartedAt, end: max(date, pauseStartedAt)))
                state.pauseStartedAt = nil
            }
            if let segmentStartedAt {
                accumulatedSeconds += max(0, date.timeIntervalSince(segmentStartedAt))
            }
            segmentStartedAt = nil
        case .idle:
            break
        }
        state.phase = phase
        if phase == .finished || phase == .failed { state.endedAt = date }
        refreshActivitySegments(endingAt: phase == .finished || phase == .failed ? date : nil)
        Self.syncLog.notice(
            "session phase=\(phase.rawValue, privacy: .private) pending=\(self.pendingPhoneControl?.rawValue ?? "-", privacy: .private)"
        )
        state.updatedAt = .now
        tick(publishUpdates: false)
        if publishChange {
            publish(force: true)
        }
        if pendingPhoneControl == phase {
            pendingPhoneControl = nil
        } else {
            applyPendingPhoneControlIfPossible()
        }
    }

    private func applyStatistics(
        heartRate: Int?,
        distanceMeters: Double?,
        activeEnergyKilocalories: Double? = nil,
        publishUpdates: Bool = true
    ) {
        if let heartRate, heartRate > 0 {
            state.heartRate = heartRate
        }
        if let activeEnergyKilocalories, activeEnergyKilocalories >= 0 {
            state.activeEnergyKilocalories = activeEnergyKilocalories
        }
        if state.workoutConfiguration.supportsDistance, let distanceMeters, distanceMeters >= 0 {
            state.distanceKilometers = distanceMeters / 1_000
        }
        refreshActivitySegments()
        tick(publishUpdates: publishUpdates)
    }

    private func publish(force: Bool) {
        guard force || Date().timeIntervalSince(lastPublishedAt) >= 5 else { return }
        lastPublishedAt = .now
        state.updatedAt = .now
        let currentState = state
        onStateChange?(currentState)

        guard let session, let data = try? JSONEncoder().encode(currentState) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    private func handleSessionPhase(
        _ phase: PawPaceRunPhase,
        at date: Date,
        sessionIdentifier: ObjectIdentifier,
        shouldComplete: Bool
    ) async {
        guard self.sessionIdentifier == sessionIdentifier else { return }
        if isCompleting, !shouldComplete { return }
        if shouldComplete {
            await completeWorkout(at: date, sessionIdentifier: sessionIdentifier)
        } else {
            applySessionPhase(phase, at: date)
        }
    }

    private func completeWorkout(at date: Date, sessionIdentifier: ObjectIdentifier) async {
        guard
            self.sessionIdentifier == sessionIdentifier,
            let completingSession = session,
            let completingBuilder = builder,
            !isCompleting
        else { return }
        isCompleting = true
        timer?.cancel()
        timer = nil
        restoreCurrentStatistics(from: completingBuilder, publishUpdates: false)
        applySessionPhase(.finished, at: date, publishChange: false)

        do {
            if let workoutID = state.workoutID {
                try await completingBuilder.addMetadata([
                    HKMetadataKeySyncIdentifier: PawPaceWorkoutIdentity.syncIdentifier(for: workoutID),
                    HKMetadataKeySyncVersion: 1
                ])
                guard self.sessionIdentifier == sessionIdentifier else { return }
            }
            if completingBuilder.endDate == nil {
                try await completingBuilder.endCollection(at: date)
                guard self.sessionIdentifier == sessionIdentifier else { return }
            }
            _ = try await completingBuilder.finishWorkout()
            guard self.sessionIdentifier == sessionIdentifier else { return }
        } catch {
            guard self.sessionIdentifier == sessionIdentifier else { return }
            errorMessage = error.localizedDescription
            state.phase = .failed
            state.encouragement = "Workout recorded locally, but Apple Health could not save it."
            state.updatedAt = .now
            await publishTerminalState(sessionIdentifier: sessionIdentifier)
            guard self.sessionIdentifier == sessionIdentifier else { return }
            completingSession.end()
            completingSession.stopMirroringToCompanionDevice { _, _ in }
            cleanupSession(keepState: true, sessionIdentifier: sessionIdentifier)
            return
        }
        await publishTerminalState(sessionIdentifier: sessionIdentifier)
        guard self.sessionIdentifier == sessionIdentifier else { return }
        completingSession.end()
        completingSession.stopMirroringToCompanionDevice { _, _ in }
        cleanupSession(keepState: true, sessionIdentifier: sessionIdentifier)
    }

    private func abortCurrentSession() async {
        let abortingSession = session
        let abortingSessionIdentifier = sessionIdentifier
        isCompleting = true
        let shouldPublishFailure = state.workoutID != nil
        if shouldPublishFailure {
            state.phase = .failed
            state.encouragement = "Workout could not continue."
            state.updatedAt = .now
            await publishTerminalState(sessionIdentifier: abortingSessionIdentifier)
        }
        if let abortingSessionIdentifier {
            guard sessionIdentifier == abortingSessionIdentifier else { return }
            abortingSession?.end()
            abortingSession?.stopMirroringToCompanionDevice { _, _ in }
            cleanupSession(
                keepState: shouldPublishFailure,
                sessionIdentifier: abortingSessionIdentifier
            )
        } else {
            abortingSession?.end()
            abortingSession?.stopMirroringToCompanionDevice { _, _ in }
            cleanupSession(keepState: shouldPublishFailure)
        }
    }

    private func publishTerminalState(sessionIdentifier expectedIdentifier: ObjectIdentifier? = nil) async {
        if let expectedIdentifier, sessionIdentifier != expectedIdentifier { return }
        lastPublishedAt = .now
        state.updatedAt = .now
        let currentState = state
        onStateChange?(currentState)

        guard let session, let data = try? JSONEncoder().encode(currentState) else { return }
        try? await session.sendToRemoteWorkoutSession(data: data)
    }

    private func applyPendingPhoneControlIfPossible() {
        guard let pendingPhoneControl, let session else { return }
        Self.syncLog.notice(
            "apply pending=\(pendingPhoneControl.rawValue, privacy: .private) current=\(self.state.phase.rawValue, privacy: .private) session=\(session.state.rawValue)"
        )
        switch pendingPhoneControl {
        case .running where state.phase == .paused:
            session.resume()
        case .paused where state.phase == .running:
            session.pause()
        case .finished where state.phase == .running || state.phase == .paused:
            session.stopActivity(with: .now)
        default:
            break
        }
    }

    private func cleanupSession(
        keepState: Bool = false,
        sessionIdentifier expectedIdentifier: ObjectIdentifier? = nil
    ) {
        if let expectedIdentifier, sessionIdentifier != expectedIdentifier { return }
        timer?.cancel()
        timer = nil
        session = nil
        sessionIdentifier = nil
        builder = nil
        segmentStartedAt = nil
        accumulatedSeconds = 0
        isCompleting = false
        isRecovering = false
        pendingPhoneControl = nil
        if !keepState {
            awaitingPhoneBinding = false
        }
        clearRecoveryMetadata()
        if !keepState {
            state = .idle
        }
    }

    private func recoveryStore() throws -> WatchWorkoutRecoveryStore {
        WatchWorkoutRecoveryStore(storage: try .shared(), legacyDefaults: PawPaceShared.defaults)
    }

    private func loadRecoveryMetadata() -> WatchWorkoutRecoveryRecord? {
        do {
            let record = try recoveryStore().load()
            recoveryMetadataReadFailed = false
            return record
        } catch {
            // Continue controlling HealthKit's recovered session, but never
            // replace an unreadable identity with the fallback ID from memory.
            recoveryMetadataReadFailed = true
            errorMessage = "Your saved workout recovery data could not be read. It has been kept on this Watch."
            Self.syncLog.error("Recovery load failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func persistRecoveryMetadata() {
        guard !recoveryMetadataReadFailed else {
            errorMessage = "Your saved workout recovery data could not be read. It has been kept on this Watch."
            return
        }
        guard let workoutID = state.workoutID, let startedAt = state.startedAt else { return }
        let record = WatchWorkoutRecoveryRecord(
            workoutID: workoutID, startedAt: startedAt,
            awaitingPhoneBinding: awaitingPhoneBinding,
            configuration: state.workoutConfiguration,
            multisportLegIndex: state.multisportLegIndex,
            activitySegments: state.activitySegments
        )
        do {
            try recoveryStore().save(record)
            recoveryMetadataNeedsRetry = false
        } catch {
            recoveryMetadataNeedsRetry = true
            errorMessage = "Workout recovery could not be saved. Existing recovery data has been kept."
            Self.syncLog.error("Recovery save failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func clearRecoveryMetadata() {
        guard !recoveryMetadataReadFailed, !recoveryMetadataNeedsRetry else { return }
        do {
            try recoveryStore().clear()
        } catch {
            recoveryMetadataNeedsRetry = true
            errorMessage = "Workout recovery data could not be cleared. It has been kept on this Watch."
            Self.syncLog.error("Recovery cleanup failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func restoreCurrentStatistics(
        from builder: HKLiveWorkoutBuilder,
        publishUpdates: Bool = true
    ) {
        var heartRate: Int?
        var distanceMeters: Double?
        if let type = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let quantity = builder.statistics(for: type)?.mostRecentQuantity() {
            let unit = HKUnit.count().unitDivided(by: .minute())
            heartRate = Int(quantity.doubleValue(for: unit).rounded())
        }
        let distanceIdentifiers: [HKQuantityTypeIdentifier]
        if state.workoutConfiguration.activity.requiresMultisportSession {
            distanceIdentifiers = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        } else {
            distanceIdentifiers = state.workoutConfiguration.distanceQuantityIdentifier.map { [$0] } ?? []
        }
        let distances = distanceIdentifiers.compactMap { identifier -> Double? in
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
            return builder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter())
        }
        if !distances.isEmpty { distanceMeters = distances.reduce(0, +) }
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        let energy = energyType.flatMap { builder.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .kilocalorie()) }
        applyStatistics(
            heartRate: heartRate,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: energy,
            publishUpdates: publishUpdates
        )
    }

    private func receive(_ payload: PawPaceWatchPayload) {
        onRemotePayload?(payload)
    }

    private func encouragement(for distance: Double) -> String {
        if !state.workoutConfiguration.supportsDistance { return "Every minute together counts." }
        return switch distance {
        case ..<0.5: "Easy paws first—find your rhythm."
        case ..<1.5: "Great pace! The trail is opening up."
        case ..<2.5: "I can smell quest rewards ahead!"
        default: "Final stretch—maximum zoomies!"
        }
    }

    var canAdvanceMultisportActivity: Bool {
        state.phase == .running && state.workoutConfiguration.activity.requiresMultisportSession
            && state.multisportLegIndex + 1 < state.workoutConfiguration.multisportLegs.count
    }

    var canAdvanceActivity: Bool { canAdvanceMultisportActivity }
    func nextActivity() { advanceMultisportActivity() }

    func advanceMultisportActivity() {
        guard canAdvanceMultisportActivity else { return }
        advanceMultisportActivity(to: state.multisportLegIndex + 1)
    }

    private func advanceMultisportActivity(to index: Int) {
        guard state.phase == .running || state.phase == .paused,
              state.workoutConfiguration.activity.requiresMultisportSession,
              state.workoutConfiguration.multisportLegs.indices.contains(index),
              index == state.multisportLegIndex + 1,
              let session else { return }
        let configuration = state.workoutConfiguration.configuration(forMultisportLeg: index)
        let now = Date()
        refreshActivitySegments(endingAt: now)
        state.activitySegments.append(WorkoutActivitySegment(configuration: configuration, startedAt: now, endedAt: nil))
        session.beginNewActivity(configuration: configuration.makeHealthKitConfiguration(), date: now, metadata: nil)
        state.multisportLegIndex = index
        persistRecoveryMetadata()
        publish(force: true)
    }

    private func refreshActivitySegments(endingAt date: Date? = nil) {
        guard let last = state.activitySegments.indices.last, state.activitySegments[last].endedAt == nil else { return }
        state.activitySegments[last].distanceMeters = max(0, state.distanceKilometers * 1_000 - state.activitySegments.dropLast().reduce(0) { $0 + $1.distanceMeters })
        state.activitySegments[last].activeEnergyKilocalories = max(0, state.activeEnergyKilocalories - state.activitySegments.dropLast().reduce(0) { $0 + $1.activeEnergyKilocalories })
        state.activitySegments[last].endedAt = date
    }

    private func restorePauseIntervals(from events: [HKWorkoutEvent]) {
        state.pauseIntervals = []
        state.pauseStartedAt = nil
        for event in events.sorted(by: { $0.dateInterval.start < $1.dateInterval.start }) {
            if event.type == .pause || event.type == .motionPaused {
                state.pauseStartedAt = event.dateInterval.start
            } else if event.type == .resume || event.type == .motionResumed,
                      let pausedAt = state.pauseStartedAt {
                state.pauseIntervals.append(DateInterval(start: pausedAt, end: max(pausedAt, event.dateInterval.start)))
                state.pauseStartedAt = nil
            }
        }
    }

    private nonisolated static func phase(for state: HKWorkoutSessionState) -> PawPaceRunPhase {
        switch state {
        case .running: .running
        case .paused: .paused
        case .stopped, .ended: .finished
        case .notStarted, .prepared: .idle
        @unknown default: .idle
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let sessionIdentifier = ObjectIdentifier(workoutSession)
        let phase = Self.phase(for: toState)
        let shouldComplete = toState == .stopped || toState == .ended
        Task { @MainActor [weak self] in
            guard let self else { return }
            await handleSessionPhase(
                phase,
                at: date,
                sessionIdentifier: sessionIdentifier,
                shouldComplete: shouldComplete
            )
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let sessionIdentifier = ObjectIdentifier(workoutSession)
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard self?.sessionIdentifier == sessionIdentifier else { return }
            guard let self else { return }
            self.errorMessage = message
            self.applySessionPhase(.failed, at: .now, publishChange: false)
            self.state.encouragement = "Workout ended unexpectedly."
            self.state.updatedAt = .now
            self.cleanupSession(keepState: true)
            self.onStateChange?(self.state)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        let sessionIdentifier = ObjectIdentifier(workoutSession)
        let payloads = data.compactMap { try? JSONDecoder().decode(PawPaceWatchPayload.self, from: $0) }
        guard !payloads.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard self?.sessionIdentifier == sessionIdentifier else { return }
            payloads.forEach { self?.receive($0) }
        }
    }

}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.builder === workoutBuilder else { return }
            self.restoreCurrentStatistics(from: workoutBuilder, publishUpdates: !self.isCompleting)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

private enum WatchWorkoutError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Health access is required to record a workout."
        }
    }
}
