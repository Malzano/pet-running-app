import Combine
import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case planner
    case club
    case run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Buddy"
        case .planner: "Planner"
        case .club: "Club"
        case .run: "Workout"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .planner: "calendar"
        case .club: "person.2"
        case .run: "figure.mixed.cardio"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var completedRun: RunSummary?

    let everydayActivity = EverydayActivityService()
    let petStore: PetStore
    let planner: PlannerStore
    let club = ClubStore()
    let workoutHistory: WorkoutHistoryStore
    let workoutCompletions: WorkoutCompletionStore
    let healthKit: HealthKitService
    let runTracker: RunTracker
    let watchConnectivity: PhoneWatchConnectivityService
    private var historyObservation: AnyCancellable?

    init(workoutHistory: WorkoutHistoryStore? = nil, workoutCompletions: WorkoutCompletionStore? = nil) {
        self.workoutHistory = workoutHistory ?? WorkoutHistoryStore()
        self.workoutCompletions = workoutCompletions ?? WorkoutCompletionStore()
        self.planner = PlannerStore()
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

        historyObservation = self.workoutHistory.$workouts.sink { [weak self] workouts in
            self?.planner.reconcile(workouts)
        }
        if let reminders = planner.reminders as? PlannerReminders {
            reminders.onOpenPlanner = { [weak self] in self?.selectedTab = .planner }
            reminders.installDelegate()
        }

        petStore.onSnapshotChange = { [weak watchConnectivity, weak runTracker, weak club] pet in
            club?.observeActivity(pet)
            guard let runTracker else { return }
            watchConnectivity?.sync(pet: pet, run: runTracker.currentRunState)
        }
        watchConnectivity.onRunState = { [weak self] state in
            guard let self else { return }
            if runTracker.handleWatchLaunchChallenge(state) { return }
            if handlePendingCompletionTerminal(state) { return }
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
                runTracker.configure(state.workoutConfiguration)
                applyMirroredPhase(state.phase)
            }
            let previousWorkoutID = runTracker.currentRunState.workoutID
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
                if let summary = completedRun, summary.id == previousWorkoutID {
                    recordCompletedWorkout(summary, rewardAliases: [workoutID])
                }
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
                if let configuration = healthKit.mirroredWorkoutConfiguration {
                    runTracker.configure(configuration)
                }
                runTracker.markWatchWorkoutActive()
                runTracker.start(syncToWatch: false)
            } else {
                runTracker.markWatchWorkoutActive()
            }
        }
        healthKit.onMirroredRunState = { [weak self] state in
            guard let self else { return }
            if runTracker.handleWatchLaunchChallenge(state) { return }
            if handlePendingCompletionTerminal(state) { return }
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
        case "planner": selectedTab = .planner
        case "club":
            selectedTab = .club
            if let token = ClubStore.invitationToken(url.absoluteString) { club.incomingInvitation = token }
        case "run", "workout", "workouts": selectedTab = .run
        default: selectedTab = .home
        }
    }

    func startPlannedWorkout(_ plan: PlannedActivity) async {
        guard !plan.isRestDay, plan.completion == nil,
              !runTracker.isFinishing, runTracker.interruptedWorkout == nil,
              runTracker.phase == .idle || runTracker.phase == .finished else { return }
        runTracker.configure(WorkoutConfiguration(activity: plan.activity))
        completedRun = nil
        selectedTab = .run
        await healthKit.requestAuthorization()
        guard !Task.isCancelled, selectedTab == .run, !runTracker.isFinishing,
              runTracker.interruptedWorkout == nil,
              runTracker.phase == .idle || runTracker.phase == .finished else { return }
        runTracker.start()
    }

    func refreshPetFromSharedStorage() {
        petStore.reloadFromSharedStorage()
        petStore.refreshQuests()
    }

    func retryPendingWatchHealthSaves() async {
        if workoutCompletions.reload() {
            for entry in workoutCompletions.pending { processCompletion(entry) }
        }
        for summary in workoutHistory.workouts where !PawPaceShared.hasRegisteredReward(for: summary.id) {
            recordCompletedWorkout(summary)
        }
        for summary in runTracker.pendingFailedWatchSummaries() {
            await savePendingWatchHealthFallback(summary)
        }
    }

    func syncEverydayActivity() async {
        guard runTracker.phase == .idle || runTracker.phase == .finished else { return }
        await everydayActivity.refresh(store: petStore, history: workoutHistory) { summary in
            self.recordCompletedWorkout(summary)
        }
    }

    @discardableResult
    func deleteWorkoutJournal() -> Bool {
        guard workoutCompletions.stopPendingJournalWrites() else { return false }
        return workoutHistory.deleteAll()
    }

    func finishRun(syncToWatch: Bool = true) async {
        guard let summary = await runTracker.finish(syncToWatch: syncToWatch) else { return }
        recordCompletedWorkout(summary)
        if runTracker.phase == .idle || runTracker.phase == .finished {
            completedRun = summary
        }
    }

    private func applyStandaloneWatchTerminal(_ state: PawPaceRunState) {
        guard
            state.phase == .finished || state.phase == .failed,
            let workoutID = state.workoutID,
            state.elapsedSeconds > 0,
            !PawPaceShared.hasRegisteredReward(for: workoutID)
        else { return }

        let endedAt = state.endedAt ?? state.updatedAt
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
            experienceEarned: state.experienceEarned,
            workoutConfiguration: state.workoutConfiguration,
            activeEnergyKilocalories: state.activeEnergyKilocalories,
            activitySegments: state.activitySegments,
            pauseIntervals: state.pauseIntervals
        )
        recordCompletedWorkout(summary, deferredTerminal: state)
        completedRun = summary
    }

    private func handleDeferredWatchTerminal(_ state: PawPaceRunState) -> Bool {
        guard let resolution = runTracker.resolveDeferredWatchTerminal(state) else { return false }

        let summary: RunSummary
        let remoteWorkoutID: UUID
        switch resolution {
        case let .finished(resolvedSummary, resolvedRemoteWorkoutID):
            summary = resolvedSummary
            remoteWorkoutID = resolvedRemoteWorkoutID
        case let .failed(resolvedSummary, resolvedRemoteWorkoutID):
            summary = resolvedSummary
            remoteWorkoutID = resolvedRemoteWorkoutID
        }

        recordCompletedWorkout(summary, rewardAliases: [remoteWorkoutID], deferredTerminal: state)
        if runTracker.phase == .idle || runTracker.phase == .finished {
            completedRun = summary
        }
        return true
    }

    private func handlePendingCompletionTerminal(_ state: PawPaceRunState) -> Bool {
        guard state.phase == .finished || state.phase == .failed,
              let identifier = state.workoutID,
              let entry = workoutCompletions.pending.first(where: { $0.rewardIDs.contains(identifier) })
        else { return false }
        recordCompletedWorkout(entry.summary, rewardAliases: entry.rewardIDs, deferredTerminal: state)
        return true
    }

    /// Persist the summary and known phone/Watch aliases before changing any
    /// destination. A retry can finish the journal without awarding XP again.
    @discardableResult
    private func recordCompletedWorkout(
        _ summary: RunSummary,
        rewardAliases: Set<UUID> = [],
        deferredTerminal: PawPaceRunState? = nil
    ) -> Bool {
        let identities = rewardAliases.union([summary.id])
        let alreadyRewarded = identities.contains { PawPaceShared.hasRegisteredReward(for: $0) }
        guard let entry = workoutCompletions.enqueue(
            summary, aliases: rewardAliases, journalRequested: !alreadyRewarded,
            deferredTerminal: deferredTerminal
        ) else { return false }
        return processCompletion(entry)
    }

    @discardableResult
    private func processCompletion(_ entry: WorkoutCompletionStore.Entry) -> Bool {
        let completed = workoutCompletions.process(entry, persistPet: {
            let alreadyRewarded = entry.rewardIDs.contains { PawPaceShared.hasRegisteredReward(for: $0) }
            guard petStore.applyRun(entry.summary, rewardAliases: entry.rewardIDs,
                                   awardIfUnrecorded: !alreadyRewarded) else { return false }
            for identifier in entry.rewardIDs { _ = PawPaceShared.registerReward(for: identifier) }
            return true
        }, persistJournal: {
            workoutHistory.workouts.contains(where: { $0.id == entry.summary.id })
                || workoutHistory.append(entry.summary)
        }, acknowledge: {
            if entry.deferredTerminal?.phase == .failed,
               !runTracker.queueFailedWatchHealthFallback(entry.summary) { return false }
            if let terminal = entry.deferredTerminal {
                return runTracker.acknowledgeDeferredWatchTerminal(terminal, summaryID: entry.summary.id)
            }
            return true
        })
        guard completed else { return false }
        runTracker.acknowledgeWorkoutSaved(entry.summary.id)
        if entry.deferredTerminal?.phase == .failed {
            Task { await savePendingWatchHealthFallback(entry.summary) }
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
