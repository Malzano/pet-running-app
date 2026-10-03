import SwiftUI

struct InterruptedWorkoutView: View {
    @ObservedObject var tracker: RunTracker
    let onReview: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDiscard = false
    @State private var reviewMessage: String?

    private var hasCurrentWorkout: Bool {
        tracker.phase == .running || tracker.phase == .paused || tracker.isFinishing
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(PawTheme.adventureBlue)
                    Text("Pick up where you left off")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    if let workout = tracker.interruptedWorkout {
                        Text("\(workout.workoutConfiguration.activity.displayName) · \(PawPaceFormatting.duration(seconds: workout.elapsedSeconds)) recorded")
                            .font(.headline)
                        Text("The app closed before this workout was finished. Review the saved time, then resume or finish. Time while the app was closed won’t count toward your workout or growth.")
                            .foregroundStyle(PawTheme.inkSecondary)
                        Button {
                            if tracker.restoreInterruptedWorkout() {
                                onReview()
                            } else {
                                reviewMessage = "The current workout is still being updated. Finish it first, then return to this recorded workout."
                            }
                        } label: {
                            Text("Review workout")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .foregroundStyle(PawTheme.buttonForeground)
                                .background(PawTheme.adventureBlue, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(hasCurrentWorkout)
                        if hasCurrentWorkout {
                            Text("Finish the current workout first. Your interrupted workout will stay here for later.")
                                .font(.subheadline)
                                .foregroundStyle(PawTheme.inkSecondary)
                        } else if let reviewMessage {
                            Text(reviewMessage).font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                        }
                        Button("Discard recorded workout", role: .destructive) { confirmsDiscard = true }
                            .font(.subheadline).frame(minHeight: 44)
                    } else {
                        Text("There’s no interrupted workout waiting to be reviewed.")
                            .foregroundStyle(PawTheme.inkSecondary)
                    }
                    if let message = tracker.recoveryStorageMessage {
                        Text(message).font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                    }
                }
                .padding(24)
            }
            .background(PawTheme.background.ignoresSafeArea())
            .navigationTitle("Welcome back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Later") { dismiss() } }
            }
            .confirmationDialog("Discard this recorded workout?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) {
                    if tracker.discardInterruptedWorkout() { dismiss() }
                }
            } message: {
                Text("Its recorded time won’t be saved or added to your companion’s growth. Your earlier workouts stay in place.")
            }
        }
        .tint(PawTheme.adventureBlue)
        .foregroundStyle(PawTheme.ink)
    }
}
