import SwiftUI

@main
struct PawPaceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model)
                .preferredColorScheme(nil)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        model.runTracker.checkpointInterruptedWorkout()
                    }
                    if newPhase == .active {
                        model.refreshPetFromSharedStorage()
                        model.planner.refreshReminders()
                        Task {
                            await model.retryPendingWatchHealthSaves()
                            await model.syncEverydayActivity()
                            model.club.observeActivity(model.petStore.snapshot)
                            await model.club.refresh()
                        }
                    }
                }
                .task {
                    model.petStore.refreshQuests()
                    model.planner.refreshReminders()
                    await model.retryPendingWatchHealthSaves()
                    await model.syncEverydayActivity()
                    model.club.observeActivity(model.petStore.snapshot)
                    await model.club.refresh()
                }
        }
    }
}
