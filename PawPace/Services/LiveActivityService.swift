import ActivityKit
import Foundation

@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var activity: Activity<PawPaceActivityAttributes>?

    private init() {}

    func start(petName: String, targetKilometers: Double) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = PawPaceActivityAttributes(petName: petName, questTargetKilometers: targetKilometers)
        let state = PawPaceActivityAttributes.ContentState(
            distanceKilometers: 0,
            elapsedSeconds: 0,
            paceSecondsPerKilometer: 0,
            heartRate: 0,
            experienceEarned: 0,
            isPaused: false,
            encouragement: "Adventure started—easy paws first!"
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    func update(with state: PawPaceActivityAttributes.ContentState) async {
        let currentActivity = activity ?? Activity<PawPaceActivityAttributes>.activities.first
        await currentActivity?.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)))
    }

    func end(with state: PawPaceActivityAttributes.ContentState) async {
        let currentActivity = activity ?? Activity<PawPaceActivityAttributes>.activities.first
        await currentActivity?.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(300))
        )
        activity = nil
    }
}

