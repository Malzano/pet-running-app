import SwiftUI

struct AppRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var petStore: PetStore
    @ObservedObject private var runTracker: RunTracker
    @ObservedObject private var workoutHistory: WorkoutHistoryStore
    @ObservedObject private var workoutCompletions: WorkoutCompletionStore
    @AppStorage("pawpace.onboarding.completed.v1") private var hasCompletedWelcome = false
    @State private var showsWelcome = false
    @State private var presentedSheet: RootSheet?
    private let enablesWelcome: Bool

    init(model: AppModel, enablesWelcome: Bool = true) {
        self.model = model
        self.petStore = model.petStore
        self.runTracker = model.runTracker
        self.workoutHistory = model.workoutHistory
        self.workoutCompletions = model.workoutCompletions
        self.enablesWelcome = enablesWelcome
    }

    var body: some View {
        TabView(selection: $model.selectedTab) {
            HomeView(store: petStore, selectedTab: $model.selectedTab,
                     onOpenSettings: { presentedSheet = .settings },
                     onOpenProgress: { presentedSheet = .growth },
                     onOpenJourney: { presentedSheet = .journey },
                     onOpenPlay: { presentedSheet = .play },
                     onOpenQuests: { presentedSheet = .quests },
                     onReviewInterrupted: runTracker.interruptedWorkout == nil ? nil : { presentedSheet = .recovery },
                     completionMessage: workoutCompletions.storageMessage ?? workoutHistory.storageMessage,
                     onRetrySave: { Task { await model.retryPendingWatchHealthSaves() } })
            .tabItem { Label("Buddy", systemImage: "pawprint") }
            .tag(AppTab.home)

            PlannerView(planner: model.planner, history: workoutHistory, petStore: petStore,
                        canStartWorkout: !runTracker.isFinishing && runTracker.interruptedWorkout == nil
                            && (runTracker.phase == .idle || runTracker.phase == .finished),
                        onStart: { await model.startPlannedWorkout($0) })
            .tabItem { Label("Planner", systemImage: "calendar") }
            .tag(AppTab.planner)

            ClubView(store: model.club, planner: model.planner, petStore: petStore, history: workoutHistory)
                .tabItem { Label("Club", systemImage: "person.2") }
                .tag(AppTab.club)

            RunView(tracker: model.runTracker, pet: petStore.snapshot,
                    onChooseActivity: { presentedSheet = .workoutPicker }, onStart: {
                if runTracker.interruptedWorkout != nil {
                    presentedSheet = .recovery
                    return
                }
                await model.healthKit.requestAuthorization()
                guard !Task.isCancelled, model.selectedTab == .run else { return }
                model.runTracker.start()
            }) {
                await model.finishRun()
            }
            .tabItem { Label("Workout", systemImage: "figure.mixed.cardio") }
            .tag(AppTab.run)
        }
        .tint(PawTheme.adventureBlue)
        .foregroundStyle(PawTheme.ink)
        .sheet(item: sheetBinding) { sheet in
            switch sheet {
            case .settings:
                SettingsView(store: petStore, healthKit: model.healthKit, history: workoutHistory,
                             onDeleteJournal: { model.deleteWorkoutJournal() },
                             completionMessage: workoutCompletions.storageMessage,
                             onRetrySave: { Task { await model.retryPendingWatchHealthSaves() } },
                             everydayActivity: model.everydayActivity,
                             onSyncActivity: { await model.syncEverydayActivity() })
            case .journey:
                JourneyView(store: petStore, canChangeCompanion: !runTracker.isFinishing && runTracker.interruptedWorkout == nil && (runTracker.phase == .idle || runTracker.phase == .finished))
            case .play:
                NavigationStack {
                    BuddyPlayView(store: petStore)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presentedSheet = nil } } }
                }
            case .quests:
                DailyQuestsView(store: petStore,
                    onWorkout: { presentedSheet = nil; model.selectedTab = .run },
                    onPlay: { presentedSheet = .play })
            case .growth:
                CompanionProgressView(store: petStore)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .workoutPicker:
                WorkoutPickerView(selection: runTracker.configuration.activity) { activity in
                    runTracker.configure(WorkoutConfiguration(activity: activity))
                }
            case .recovery:
                InterruptedWorkoutView(tracker: runTracker) {
                    presentedSheet = nil
                    model.selectedTab = .run
                }
                .presentationDetents([.medium, .large])
            case let .summary(summary):
                RunSummaryView(summary: summary, pet: petStore.snapshot,
                               route: runTracker.recordedRoute(for: summary),
                               friendStore: model.club,
                               saveMessage: petStore.storageMessage ?? workoutCompletions.storageMessage ?? workoutHistory.storageMessage,
                               rewardsPending: !petStore.snapshot.hasRewardedWorkout(summary.id)
                                   && !PawPaceShared.hasRegisteredReward(for: summary.id)) {
                    dismissSummary(summary, returnHome: true)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $showsWelcome, onDismiss: {
            if let summary = model.completedRun { presentedSheet = .summary(summary) }
        }) {
            WelcomeView {
                hasCompletedWelcome = true
                showsWelcome = false
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            if let summary = model.completedRun {
                presentedSheet = .summary(summary)
                return
            }
            if runTracker.interruptedWorkout != nil, runTracker.phase == .idle {
                presentedSheet = .recovery
                return
            }
            guard enablesWelcome, !hasCompletedWelcome else { return }
            // Existing companions continue straight into their familiar home.
            guard petStore.snapshot.lifecycle != nil else {
                hasCompletedWelcome = true
                return
            }
            if model.runTracker.phase == .idle, model.completedRun == nil {
                showsWelcome = true
            }
        }
        .onChange(of: runTracker.interruptedWorkout?.workoutID) { _, identifier in
            if identifier != nil, runTracker.phase == .idle, !showsWelcome {
                presentedSheet = .recovery
            }
        }
        .onChange(of: model.completedRun) { _, summary in
            if let summary {
                if showsWelcome {
                    // Present after the full-screen welcome has actually closed.
                    showsWelcome = false
                } else {
                    presentedSheet = .summary(summary)
                }
            } else if case .summary = presentedSheet {
                presentedSheet = nil
            }
        }
    }

    private var sheetBinding: Binding<RootSheet?> {
        Binding(get: { presentedSheet }, set: { newValue in
            if newValue == nil, case let .summary(summary) = presentedSheet {
                dismissSummary(summary, returnHome: false)
            }
            presentedSheet = newValue
        })
    }

    private func dismissSummary(_ summary: RunSummary, returnHome: Bool) {
        let canReset = SummaryDismissalPolicy.canResetTracker(
            phase: runTracker.phase,
            isFinishing: runTracker.isFinishing,
            currentWorkoutID: runTracker.currentRunState.workoutID,
            summaryID: summary.id,
            matchesKnownIdentity: runTracker.matchesCurrentWatchWorkout(summary.id)
        )
        if model.completedRun?.id == summary.id { model.completedRun = nil }
        if canReset { runTracker.reset() }
        if case let .summary(presented) = presentedSheet, presented.id == summary.id {
            presentedSheet = nil
        }
        if returnHome, !runTracker.isFinishing,
           runTracker.phase == .idle || runTracker.phase == .finished {
            model.selectedTab = .home
        }
    }

    private enum RootSheet: Identifiable {
        case quests
        case settings
        case growth
        case journey
        case play
        case workoutPicker
        case recovery
        case summary(RunSummary)

        var id: String {
            switch self {
            case .quests: "quests"
            case .settings: "settings"
            case .growth: "growth"
            case .journey: "journey"
            case .play: "play"
            case .workoutPicker: "workout-picker"
            case .recovery: "recovery"
            case let .summary(summary): "summary-\(summary.id.uuidString)"
            }
        }
    }
}

/// An old result sheet must never tear down a newer live or finishing workout.
enum SummaryDismissalPolicy {
    static func canResetTracker(
        phase: RunTracker.Phase,
        isFinishing: Bool,
        currentWorkoutID: UUID?,
        summaryID: UUID,
        matchesKnownIdentity: Bool = false
    ) -> Bool {
        guard !isFinishing, phase == .idle || phase == .finished else { return false }
        return currentWorkoutID == nil || currentWorkoutID == summaryID || matchesKnownIdentity
    }
}
