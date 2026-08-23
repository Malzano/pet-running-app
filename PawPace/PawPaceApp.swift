import SwiftUI

@main
struct PawPaceApp: App {
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model)
                .preferredColorScheme(nil)
                .onOpenURL { model.handle(url: $0) }
                .task {
                    await model.healthKit.requestAuthorization()
                    model.runTracker.requestLocationPermission()
                }
        }
    }
}

