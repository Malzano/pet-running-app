import HealthKit
import SwiftUI
import WatchKit

@main
struct PawPaceWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: PawPaceWatchAppDelegate
    @StateObject private var model = PawPaceWatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRunView(
                workout: model.workout,
                connectivity: model.connectivity
            )
        }
    }
}

@MainActor
final class PawPaceWatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchWorkoutManager.shared.start(configuration: workoutConfiguration)
    }

    func handleActiveWorkoutRecovery() {
        WatchWorkoutManager.shared.recoverActiveWorkout()
    }
}

@MainActor
final class PawPaceWatchModel: ObservableObject {
    let workout = WatchWorkoutManager.shared
    let connectivity = WatchPetConnectivityService.shared

    init() {
        workout.onStateChange = { [weak connectivity] state in
            connectivity?.publish(run: state)
        }
        workout.onRemotePayload = { [weak connectivity] payload in
            connectivity?.apply(payload)
        }
        connectivity.onControl = { [weak workout] control in
            workout?.applyPhoneControl(control)
        }
    }
}
