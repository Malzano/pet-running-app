import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case chat
    case run
    case collection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .chat: "Chat"
        case .run: "Run"
        case .collection: "Collect"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .chat: "message.fill"
        case .run: "figure.run"
        case .collection: "square.grid.2x2.fill"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var completedRun: RunSummary?

    let petStore: PetStore
    let healthKit: HealthKitService
    let runTracker: RunTracker
    let watchConnectivity: PhoneWatchConnectivityService

    init() {
        let petStore = PetStore()
        let healthKit = HealthKitService()
        let watchConnectivity = PhoneWatchConnectivityService()
        let runTracker = RunTracker(
            healthKit: healthKit,
            petSnapshot: { petStore.snapshot },
            watchConnectivity: watchConnectivity
        )
        self.petStore = petStore
        self.healthKit = healthKit
        self.watchConnectivity = watchConnectivity
        self.runTracker = runTracker

        petStore.onSnapshotChange = { [weak watchConnectivity, weak runTracker] pet in
            guard let runTracker else { return }
            watchConnectivity?.sync(pet: pet, run: runTracker.currentRunState)
        }
        watchConnectivity.onRunState = { [weak self] state in
            guard let self else { return }
            if runTracker.handleWatchLaunchChallenge(state) { return }
            if runTracker.consumePreviouslyRewardedWatchTerminal(state) { return }
            healthKit.observeWatchStateFromConnectivity(state)
            if handleDeferredWatchTerminal(state) { return }
            let canAdoptPendingPhoneLaunch = runTracker.canAdoptConnectivityState(state)
            if
                state.phase == .finished || state.phase == .failed,
                !runTracker.isFinishing,
                runTracker.phase == .idle || runTracker.phase == .finished,
                !canAdoptPendingPhoneLaunch
            {
                applyStandaloneWatchTerminal(state)
                return
            }
            let shouldSuppressPhase = healthKit.shouldSuppressRemotePhase(state)
            let canStartFallback = (runTracker.phase == .idle || runTracker.phase == .finished)
                && PawPaceSyncPolicy.canStartConnectivityFallback(from: state)
            if canStartFallback, !shouldSuppressPhase {
                applyMirroredPhase(state.phase)
            }
            guard runTracker.applyWatchState(
                state,
                allowWorkoutAdoption: canStartFallback || canAdoptPendingPhoneLaunch
            ) else { return }
            if
                canAdoptPendingPhoneLaunch,
                !runTracker.isFinishing,
                runTracker.phase == .finished,
                state.phase == .finished,
                let workoutID = state.workoutID
            {
                _ = PawPaceShared.registerReward(for: workoutID)
                return
            }
            if
                !shouldSuppressPhase,
                !canStartFallback,
                !canAdoptPendingPhoneLaunch || state.phase == .finished || state.phase == .failed
            {
                applyMirroredPhase(state.phase)
            }
        }
        healthKit.onMirroredWorkoutStarted = { [weak self] in
            guard let self else { return }
            if runTracker.isFinishing {
                self.healthKit.endMirroredWorkout()
            } else if runTracker.phase == .idle || runTracker.phase == .finished {
                self.completedRun = nil
                self.selectedTab = .run
                runTracker.markWatchWorkoutActive()
                runTracker.start(syncToWatch: false)
            } else {
                runTracker.markWatchWorkoutActive()
            }
        }
        healthKit.onMirroredRunState = { [weak self] state in
            guard let self else { return }
            if runTracker.handleWatchLaunchChallenge(state) { return }
            if runTracker.consumePreviouslyRewardedWatchTerminal(state) { return }
            if handleDeferredWatchTerminal(state) { return }
            if
                state.phase == .finished || state.phase == .failed,
                !runTracker.isFinishing,
                runTracker.phase == .idle || runTracker.phase == .finished
            {
                applyStandaloneWatchTerminal(state)
                return
            }
            guard runTracker.applyWatchState(
                state,
                allowWorkoutAdoption: true
            ) else { return }
            if state.phase != .idle, !healthKit.shouldSuppressRemotePhase(state) {
                applyMirroredPhase(state.phase)
            }
        }
        healthKit.onMirroredWorkoutStateChanged = { [weak self] phase in
            self?.applyMirroredPhase(phase)
        }
        healthKit.onMirroredWorkoutFailed = { [weak self] workoutID, _ in
            guard let self else { return }
            handleWatchWorkoutFailure(workoutID: workoutID)
        }
        healthKit.onMirroredWorkoutEnded = { [weak self] workoutID in
            guard let self else { return }
            // HealthKit ended without the Watch's terminal PawPace payload, so
            // the Watch save result is unknown. Preserve the run on the phone.
            handleWatchWorkoutFailure(workoutID: workoutID)
        }

        watchConnectivity.sync(pet: petStore.snapshot, run: runTracker.currentRunState)
    }

    func handle(url: URL) {
        guard url.scheme == "pawpace" else { return }
        switch url.host {
        case "chat": selectedTab = .chat
        case "run": selectedTab = .run
        case "collection": selectedTab = .collection
        default: selectedTab = .home
        }
    }

    func refreshPetFromSharedStorage() {
        petStore.reloadFromSharedStorage()
    }

    func retryPendingWatchHealthSaves() async {
        for summary in runTracker.pendingFailedWatchSummaries() {
            await savePendingWatchHealthFallback(summary)
        }
    }

    func finishRun(syncToWatch: Bool = true) async {
        guard let summary = await runTracker.finish(syncToWatch: syncToWatch) else { return }
        guard PawPaceShared.registerReward(for: summary.id) else { return }
        petStore.applyRun(summary)
        if runTracker.phase == .idle || runTracker.phase == .finished {
            completedRun = summary
        }
    }

    private func applyStandaloneWatchTerminal(_ state: PawPaceRunState) {
        guard
            state.phase == .finished || state.phase == .failed,
            let workoutID = state.workoutID,
            state.elapsedSeconds > 0,
            PawPaceShared.registerReward(for: workoutID)
        else { return }

        let endedAt = state.updatedAt
        let startedAt = state.startedAt
            ?? endedAt.addingTimeInterval(-Double(state.elapsedSeconds))
        let summary = RunSummary(
            id: workoutID,
            startedAt: startedAt,
            endedAt: max(startedAt, endedAt),
            distanceMeters: max(0, state.distanceKilometers * 1_000),
            elapsedSeconds: state.elapsedSeconds,
            averagePaceSecondsPerKilometer: state.paceSecondsPerKilometer,
            averageHeartRate: state.heartRate > 0 ? state.heartRate : nil,
            experienceEarned: state.experienceEarned
        )
        petStore.applyRun(summary)
        completedRun = summary
        if state.phase == .failed {
            runTracker.queueFailedWatchHealthFallback(summary)
            Task { await savePendingWatchHealthFallback(summary) }
        }
    }

    private func handleDeferredWatchTerminal(_ state: PawPaceRunState) -> Bool {
        guard let resolution = runTracker.resolveDeferredWatchTerminal(state) else { return false }

        let summary: RunSummary
        let remoteWorkoutID: UUID
        let needsPhoneHealthSave: Bool
        switch resolution {
        case let .finished(resolvedSummary, resolvedRemoteWorkoutID):
            summary = resolvedSummary
            remoteWorkoutID = resolvedRemoteWorkoutID
            needsPhoneHealthSave = false
        case let .failed(resolvedSummary, resolvedRemoteWorkoutID):
            summary = resolvedSummary
            remoteWorkoutID = resolvedRemoteWorkoutID
            needsPhoneHealthSave = true
        }

        if PawPaceShared.registerReward(for: summary.id) {
            petStore.applyRun(summary)
        }
        if remoteWorkoutID != summary.id {
            _ = PawPaceShared.registerReward(for: remoteWorkoutID)
        }
        if runTracker.phase == .idle || runTracker.phase == .finished {
            completedRun = summary
        }
        if needsPhoneHealthSave {
            Task { await savePendingWatchHealthFallback(summary) }
        }
        return true
    }

    private func applyMirroredPhase(_ phase: PawPaceRunPhase) {
        switch phase {
        case .idle:
            break
        case .running:
            runTracker.markWatchWorkoutActive()
            if runTracker.phase == .idle || runTracker.phase == .finished {
                completedRun = nil
                selectedTab = .run
                runTracker.start(syncToWatch: false)
            } else if runTracker.phase == .paused {
                runTracker.resume(syncToWatch: false)
            }
        case .paused:
            runTracker.markWatchWorkoutActive()
            if runTracker.phase == .idle || runTracker.phase == .finished {
                completedRun = nil
                selectedTab = .run
                runTracker.start(syncToWatch: false)
            }
            runTracker.pause(syncToWatch: false)
        case .finished:
            runTracker.markWatchWorkoutActive()
            Task { await finishRun(syncToWatch: false) }
        case .failed:
            handleWatchWorkoutFailure()
        }
    }

    private func handleWatchWorkoutFailure(workoutID remoteWorkoutID: UUID? = nil) {
        if
            let remoteWorkoutID,
            !runTracker.matchesCurrentWatchWorkout(remoteWorkoutID)
        {
            if let summary = runTracker.markPendingWatchRecordForPhoneSave(
                remoteWorkoutID: remoteWorkoutID
            ) {
                Task { await savePendingWatchHealthFallback(summary) }
            }
            return
        }
        let fallbackSummary = runTracker.markWatchWorkoutFailed()
        if let fallbackSummary {
            Task { await savePendingWatchHealthFallback(fallbackSummary) }
        } else if runTracker.phase == .running || runTracker.phase == .paused {
            Task { await finishRun(syncToWatch: false) }
        }
    }

    private func savePendingWatchHealthFallback(_ summary: RunSummary) async {
        guard runTracker.beginPendingWatchHealthSave(summaryID: summary.id) else { return }
        do {
            try await healthKit.saveRun(summary)
            runTracker.completePendingWatchHealthSave(summaryID: summary.id, succeeded: true)
        } catch {
            runTracker.completePendingWatchHealthSave(summaryID: summary.id, succeeded: false)
        }
    }
}
