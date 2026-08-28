import Foundation
import HealthKit

@MainActor
final class HealthKitService: NSObject, ObservableObject {
    private struct PendingMirroredControl {
        let phase: PawPaceRunPhase
        let workoutID: UUID
    }

    enum AuthorizationState: Equatable {
        case notRequested
        case unavailable
        case authorized
        case denied
    }

    @Published private(set) var authorizationState: AuthorizationState = .notRequested

    var onMirroredWorkoutStarted: (() -> Void)?
    var onMirroredWorkoutEnded: ((UUID?) -> Void)?
    var onMirroredWorkoutFailed: ((UUID?, String) -> Void)?
    var onMirroredWorkoutStateChanged: ((PawPaceRunPhase) -> Void)?
    var onMirroredRunState: ((PawPaceRunState) -> Void)?

    private let store = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?
    private var mirroredSessionIdentifier: ObjectIdentifier?
    private var mirroredSessionWorkoutID: UUID?
    private var mirroredTerminalSessionIdentifiers: Set<ObjectIdentifier> = []
    private var supersededMirroredSessionIdentifiers: Set<ObjectIdentifier> = []
    private var activeMirroredWorkoutID: UUID?
    private var expectedLaunchedWorkoutID: UUID?
    private var expectedLaunchedStartedAt: Date?
    private var pendingMirroredControl: PendingMirroredControl?
    private var awaitingMirroredIdentity = false
    private var hasNotifiedMirroredStart = false

    override init() {
        super.init()
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.attachMirroredSession(session)
            }
        }
    }

    var hasActiveMirroredWorkout: Bool {
        mirroredSession != nil
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            return
        }

        var shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            shareTypes.insert(distance)
            readTypes.insert(distance)
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HealthKitError.authorizationDenied)
                    }
                }
            }
            authorizationState = .authorized
        } catch {
            authorizationState = .denied
        }
    }

    func latestHeartRate() async -> Int? {
        guard
            authorizationState == .authorized,
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: Int(value.rounded()))
            }
            store.execute(query)
        }
    }

    func startWatchWorkout(workoutID: UUID, startedAt: Date) async -> Bool {
        guard authorizationState == .authorized else { return false }
        guard !Task.isCancelled else { return false }
        if let mirroredSessionIdentifier {
            supersededMirroredSessionIdentifiers.insert(mirroredSessionIdentifier)
        }
        activeMirroredWorkoutID = workoutID
        expectedLaunchedWorkoutID = workoutID
        expectedLaunchedStartedAt = startedAt
        awaitingMirroredIdentity = true
        if pendingMirroredControl?.workoutID != workoutID {
            pendingMirroredControl = nil
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        do {
            try await store.startWatchApp(toHandle: configuration)
            return true
        } catch {
            if expectedLaunchedWorkoutID == workoutID {
                activeMirroredWorkoutID = nil
                expectedLaunchedWorkoutID = nil
                expectedLaunchedStartedAt = nil
                pendingMirroredControl = nil
            }
            return false
        }
    }

    func pauseMirroredWorkout(workoutID: UUID? = nil) {
        requestMirroredControl(.paused, requestedWorkoutID: workoutID)
    }

    func resumeMirroredWorkout(workoutID: UUID? = nil) {
        requestMirroredControl(.running, requestedWorkoutID: workoutID)
    }

    func endMirroredWorkout(workoutID: UUID? = nil) {
        requestMirroredControl(.finished, requestedWorkoutID: workoutID)
    }

    func observeWatchStateFromConnectivity(_ state: PawPaceRunState) {
        guard let remoteWorkoutID = state.workoutID else { return }
        if isExpectedLaunchChallenge(state) { return }
        let matchesExpectedLaunch = stateMatchesExpectedLaunch(state)
            || stateMatchesExpectedLaunchTerminal(state)
        guard activeMirroredWorkoutID == remoteWorkoutID || matchesExpectedLaunch else { return }

        if
            let pendingMirroredControl,
            pendingMirroredControl.workoutID != remoteWorkoutID,
            matchesExpectedLaunch
        {
            self.pendingMirroredControl = PendingMirroredControl(
                phase: pendingMirroredControl.phase,
                workoutID: remoteWorkoutID
            )
        }
        activeMirroredWorkoutID = remoteWorkoutID
        if shouldAssociateConnectivityStateWithMirroredSession(
            state,
            matchesExpectedLaunch: matchesExpectedLaunch
        ), let mirroredSessionIdentifier {
            mirroredSessionWorkoutID = remoteWorkoutID
            if state.phase == .finished || state.phase == .failed {
                mirroredTerminalSessionIdentifiers.insert(mirroredSessionIdentifier)
            }
        }
        if state.phase == .finished || state.phase == .failed {
            pendingMirroredControl = nil
        } else if let pendingMirroredControl,
                  pendingMirroredControl.workoutID == remoteWorkoutID {
            if pendingMirroredControl.phase == state.phase {
                self.pendingMirroredControl = nil
            } else if let mirroredSession {
                awaitingMirroredIdentity = false
                apply(pendingMirroredControl.phase, to: mirroredSession)
            }
        }
        if matchesExpectedLaunch {
            expectedLaunchedWorkoutID = nil
            expectedLaunchedStartedAt = nil
        }
    }

    func shouldSuppressRemotePhase(_ state: PawPaceRunState) -> Bool {
        guard
            state.phase != .finished,
            state.phase != .failed,
            let remoteWorkoutID = state.workoutID,
            let pendingMirroredControl,
            pendingMirroredControl.workoutID == remoteWorkoutID
        else { return false }
        return pendingMirroredControl.phase != state.phase
    }

    func sendToMirroredWorkout(_ payload: PawPaceWatchPayload) {
        guard
            let mirroredSession,
            let mirroredSessionIdentifier,
            !supersededMirroredSessionIdentifiers.contains(mirroredSessionIdentifier),
            let data = try? JSONEncoder().encode(payload)
        else { return }

        mirroredSession.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    func saveRun(_ summary: RunSummary) async throws {
        if authorizationState == .notRequested {
            await requestAuthorization()
        }
        guard authorizationState == .authorized else {
            throw HealthKitError.authorizationDenied
        }
        if try await containsSavedRun(workoutID: summary.id) {
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: summary.startedAt)
        try await builder.addMetadata([
            HKMetadataKeySyncIdentifier: PawPaceWorkoutIdentity.syncIdentifier(for: summary.id),
            HKMetadataKeySyncVersion: 1
        ])

        if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: summary.distanceMeters),
                start: summary.startedAt,
                end: summary.endedAt
            )
            try await builder.addSamples([distanceSample])
        }

        try await builder.endCollection(at: summary.endedAt)
        _ = try await builder.finishWorkout()
    }

    private func containsSavedRun(workoutID: UUID) async throws -> Bool {
        let syncIdentifier = PawPaceWorkoutIdentity.syncIdentifier(for: workoutID)
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: [syncIdentifier]
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: !(samples?.isEmpty ?? true))
                }
            }
            store.execute(query)
        }
    }

    private func attachMirroredSession(_ session: HKWorkoutSession) {
        if let previousIdentifier = mirroredSessionIdentifier {
            mirroredTerminalSessionIdentifiers.remove(previousIdentifier)
            supersededMirroredSessionIdentifiers.remove(previousIdentifier)
        }
        mirroredSession = session
        mirroredSessionIdentifier = ObjectIdentifier(session)
        mirroredSessionWorkoutID = nil
        session.delegate = self
        awaitingMirroredIdentity = true
        hasNotifiedMirroredStart = false
    }

    private func handleMirroredState(
        _ phase: PawPaceRunPhase,
        sessionIdentifier: ObjectIdentifier,
        ended: Bool
    ) {
        guard mirroredSessionIdentifier == sessionIdentifier else { return }
        // A bare HealthKit lifecycle callback carries neither the PawPace
        // workout ID nor the Watch save result. Only nonterminal lifecycle
        // changes are safe to mirror. An end without a terminal payload is
        // treated as a Watch failure by AppModel so the phone saves a fallback.
        if
            !ended,
            !supersededMirroredSessionIdentifiers.contains(sessionIdentifier),
            !awaitingMirroredIdentity
        {
            onMirroredWorkoutStateChanged?(phase)
        }
        if ended {
            completeMirroredSession(
                sessionIdentifier: sessionIdentifier,
                notifyUnresolvedEnd: !mirroredTerminalSessionIdentifiers.contains(sessionIdentifier)
            )
        }
    }

    private func completeMirroredSession(
        sessionIdentifier: ObjectIdentifier,
        notifyUnresolvedEnd: Bool
    ) {
        guard mirroredSessionIdentifier == sessionIdentifier else { return }
        let sessionWasSuperseded = supersededMirroredSessionIdentifiers.contains(sessionIdentifier)
        let completedWorkoutID = mirroredSessionWorkoutID
            ?? (sessionWasSuperseded ? nil : expectedLaunchedWorkoutID)
            ?? (sessionWasSuperseded ? nil : activeMirroredWorkoutID)
        mirroredSession = nil
        mirroredSessionIdentifier = nil
        mirroredSessionWorkoutID = nil
        mirroredTerminalSessionIdentifiers.remove(sessionIdentifier)
        supersededMirroredSessionIdentifiers.remove(sessionIdentifier)
        if activeMirroredWorkoutID == completedWorkoutID {
            activeMirroredWorkoutID = nil
        }
        if expectedLaunchedWorkoutID == completedWorkoutID {
            expectedLaunchedWorkoutID = nil
            expectedLaunchedStartedAt = nil
        }
        if pendingMirroredControl?.workoutID == completedWorkoutID {
            pendingMirroredControl = nil
        }
        awaitingMirroredIdentity = false
        hasNotifiedMirroredStart = false
        if notifyUnresolvedEnd, !(sessionWasSuperseded && completedWorkoutID == nil) {
            onMirroredWorkoutEnded?(completedWorkoutID)
        }
    }

    private func failMirroredSession(
        sessionIdentifier: ObjectIdentifier,
        message: String
    ) {
        guard mirroredSessionIdentifier == sessionIdentifier else { return }
        let sessionWasSuperseded = supersededMirroredSessionIdentifiers.contains(sessionIdentifier)
        let failedWorkoutID = mirroredSessionWorkoutID
            ?? (sessionWasSuperseded ? nil : expectedLaunchedWorkoutID)
            ?? (sessionWasSuperseded ? nil : activeMirroredWorkoutID)
        if !(sessionWasSuperseded && failedWorkoutID == nil) {
            onMirroredWorkoutFailed?(failedWorkoutID, message)
        }
        completeMirroredSession(sessionIdentifier: sessionIdentifier, notifyUnresolvedEnd: false)
    }

    private func disconnectMirroredSession(sessionIdentifier: ObjectIdentifier) {
        guard mirroredSessionIdentifier == sessionIdentifier else { return }
        mirroredSession = nil
        mirroredSessionIdentifier = nil
        mirroredSessionWorkoutID = nil
        mirroredTerminalSessionIdentifiers.remove(sessionIdentifier)
        supersededMirroredSessionIdentifiers.remove(sessionIdentifier)
        awaitingMirroredIdentity = true
        hasNotifiedMirroredStart = false
    }

    private func receiveMirroredState(_ state: PawPaceRunState, sessionIdentifier: ObjectIdentifier) {
        guard mirroredSessionIdentifier == sessionIdentifier else { return }
        guard !supersededMirroredSessionIdentifiers.contains(sessionIdentifier) else { return }
        guard let remoteWorkoutID = state.workoutID else {
            onMirroredRunState?(state)
            return
        }

        if isExpectedLaunchChallenge(state) {
            onMirroredRunState?(state)
            return
        }

        let matchesExpectedLaunch = stateMatchesExpectedLaunch(state)
            || stateMatchesExpectedLaunchTerminal(state)
        if expectedLaunchedWorkoutID != nil, !matchesExpectedLaunch {
            return
        }
        awaitingMirroredIdentity = false
        mirroredSessionWorkoutID = remoteWorkoutID

        if state.phase == .finished || state.phase == .failed {
            mirroredTerminalSessionIdentifiers.insert(sessionIdentifier)
            activeMirroredWorkoutID = remoteWorkoutID
            expectedLaunchedWorkoutID = nil
            expectedLaunchedStartedAt = nil
            pendingMirroredControl = nil
            onMirroredRunState?(state)
            return
        }

        if let pendingMirroredControl {
            if pendingMirroredControl.workoutID != remoteWorkoutID {
                if matchesExpectedLaunch {
                    self.pendingMirroredControl = PendingMirroredControl(
                        phase: pendingMirroredControl.phase,
                        workoutID: remoteWorkoutID
                    )
                    if let mirroredSession {
                        apply(pendingMirroredControl.phase, to: mirroredSession)
                        activeMirroredWorkoutID = remoteWorkoutID
                        expectedLaunchedWorkoutID = nil
                        expectedLaunchedStartedAt = nil
                        return
                    }
                } else {
                    self.pendingMirroredControl = nil
                }
            } else if pendingMirroredControl.phase == state.phase {
                self.pendingMirroredControl = nil
            } else if let mirroredSession {
                apply(pendingMirroredControl.phase, to: mirroredSession)
                activeMirroredWorkoutID = remoteWorkoutID
                expectedLaunchedWorkoutID = nil
                expectedLaunchedStartedAt = nil
                return
            }
        }

        activeMirroredWorkoutID = remoteWorkoutID
        if matchesExpectedLaunch {
            expectedLaunchedWorkoutID = nil
            expectedLaunchedStartedAt = nil
        }
        notifyMirroredStartIfNeeded(for: state.phase)
        onMirroredRunState?(state)
    }

    private func requestMirroredControl(
        _ phase: PawPaceRunPhase,
        requestedWorkoutID: UUID?
    ) {
        let targetWorkoutID = activeMirroredWorkoutID ?? requestedWorkoutID
        if let targetWorkoutID {
            activeMirroredWorkoutID = targetWorkoutID
            pendingMirroredControl = PendingMirroredControl(
                phase: phase,
                workoutID: targetWorkoutID
            )
        }

        guard
            let mirroredSession,
            let mirroredSessionIdentifier,
            !supersededMirroredSessionIdentifiers.contains(mirroredSessionIdentifier)
        else { return }
        guard !awaitingMirroredIdentity || targetWorkoutID == nil else { return }
        apply(phase, to: mirroredSession)
    }

    private func apply(_ phase: PawPaceRunPhase, to session: HKWorkoutSession) {
        switch phase {
        case .running:
            session.resume()
        case .paused:
            session.pause()
        case .finished:
            session.end()
        case .idle, .failed:
            break
        }
    }

    private func notifyMirroredStartIfNeeded(for phase: PawPaceRunPhase) {
        guard
            !hasNotifiedMirroredStart,
            phase == .running || phase == .paused
        else { return }
        hasNotifiedMirroredStart = true
        onMirroredWorkoutStarted?()
    }

    private func shouldAssociateConnectivityStateWithMirroredSession(
        _ state: PawPaceRunState,
        matchesExpectedLaunch: Bool
    ) -> Bool {
        guard
            let mirroredSessionIdentifier,
            !supersededMirroredSessionIdentifiers.contains(mirroredSessionIdentifier),
            let remoteWorkoutID = state.workoutID
        else { return false }
        if let mirroredSessionWorkoutID {
            return mirroredSessionWorkoutID == remoteWorkoutID
        }
        if expectedLaunchedWorkoutID != nil {
            return matchesExpectedLaunch
        }
        return activeMirroredWorkoutID == remoteWorkoutID
    }

    private func stateMatchesExpectedLaunch(_ state: PawPaceRunState) -> Bool {
        guard let expectedLaunchedWorkoutID else { return false }
        return state.workoutID == expectedLaunchedWorkoutID
    }

    private func stateMatchesExpectedLaunchTerminal(_ state: PawPaceRunState) -> Bool {
        guard
            state.phase == .finished || state.phase == .failed,
            let expectedLaunchedWorkoutID,
            state.workoutID != expectedLaunchedWorkoutID,
            let expectedLaunchedStartedAt
        else { return false }
        return PawPaceSyncPolicy.canAdoptPendingPhoneLaunch(
            from: state,
            localStart: expectedLaunchedStartedAt
        )
    }

    private func isExpectedLaunchChallenge(_ state: PawPaceRunState) -> Bool {
        guard
            let expectedLaunchedWorkoutID,
            state.workoutID != expectedLaunchedWorkoutID,
            let expectedLaunchedStartedAt
        else { return false }
        return PawPaceSyncPolicy.canAnswerPhoneLaunchChallenge(
            from: state,
            localStart: expectedLaunchedStartedAt
        )
    }
}

extension HealthKitService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let sessionIdentifier = ObjectIdentifier(workoutSession)
        let phase: PawPaceRunPhase
        switch toState {
        case .running:
            phase = .running
        case .paused:
            phase = .paused
        case .stopped:
            return
        case .ended:
            phase = .finished
        case .notStarted, .prepared:
            phase = .idle
        @unknown default:
            phase = .idle
        }

        let ended = toState == .ended
        Task { @MainActor [weak self] in
            self?.handleMirroredState(phase, sessionIdentifier: sessionIdentifier, ended: ended)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let sessionIdentifier = ObjectIdentifier(workoutSession)
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.failMirroredSession(sessionIdentifier: sessionIdentifier, message: message)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        let sessionIdentifier = ObjectIdentifier(workoutSession)
        let states = data.compactMap { try? JSONDecoder().decode(PawPaceRunState.self, from: $0) }
        guard !states.isEmpty else { return }
        Task { @MainActor [weak self] in
            for state in states {
                self?.receiveMirroredState(state, sessionIdentifier: sessionIdentifier)
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        let sessionIdentifier = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            self?.disconnectMirroredSession(sessionIdentifier: sessionIdentifier)
        }
    }
}

private enum HealthKitError: Error {
    case authorizationDenied
}
