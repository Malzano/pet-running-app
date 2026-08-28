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
                    if newPhase == .active {
                        model.refreshPetFromSharedStorage()
                        Task { await model.retryPendingWatchHealthSaves() }
                    }
                }
                .task {
                    await model.healthKit.requestAuthorization()
                    await model.retryPendingWatchHealthSaves()
                    model.runTracker.requestLocationPermission()
                }
        }
    }
}
