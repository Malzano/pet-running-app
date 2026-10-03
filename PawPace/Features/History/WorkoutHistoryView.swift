import SwiftUI

struct WorkoutHistoryView: View {
    @ObservedObject var history: WorkoutHistoryStore

    var body: some View {
        Group {
            if history.workouts.isEmpty {
                ContentUnavailableView {
                    Label("A story in every workout", systemImage: "book.closed")
                } description: {
                    Text(history.storageMessage ?? "Workouts you save from now on appear here. A few minutes of movement is a lovely place to start.")
                }
            } else {
                List {
                    if let message = history.storageMessage {
                        Text(message).font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                    }
                    Section {
                        ForEach(history.workouts) { workout in
                            NavigationLink {
                                WorkoutDetailView(summary: workout)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: workout.workoutConfiguration.activity.symbol)
                                        .font(.title2)
                                        .foregroundStyle(PawTheme.adventureBlue)
                                        .frame(width: 34)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(workout.workoutConfiguration.displayName).font(.headline)
                                        Text(workout.endedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                            .font(.caption)
                                            .foregroundStyle(PawTheme.inkSecondary)
                                        Text("\(PawPaceFormatting.duration(seconds: workout.elapsedSeconds)) active · \(workout.experienceEarned) XP")
                                            .font(.subheadline)
                                            .foregroundStyle(PawTheme.inkSecondary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(PawTheme.surface)
                        }
                    } footer: {
                        Text("This journal is saved on this iPhone and isn’t included in cloud backups. If Everyday activity is enabled, new shared Health workouts can also appear here.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(PawTheme.background.ignoresSafeArea())
        .foregroundStyle(PawTheme.ink)
        .navigationTitle("Workout journal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkoutDetailView: View {
    let summary: RunSummary

    var body: some View {
        List {
            Section {
                LabeledContent("Activity", value: summary.workoutConfiguration.displayName)
                LabeledContent("Started") { Text(summary.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute()) }
                LabeledContent("Active time", value: PawPaceFormatting.duration(seconds: summary.elapsedSeconds))
                if summary.workoutConfiguration.activity.supportsDistance {
                    LabeledContent("Distance", value: "\(PawPaceFormatting.distance(kilometers: summary.distanceKilometers)) km")
                }
                if summary.workoutConfiguration.supportsPace {
                    LabeledContent("Average pace", value: "\(PawPaceFormatting.pace(secondsPerKilometer: summary.averagePaceSecondsPerKilometer)) /km")
                }
                if let heartRate = summary.averageHeartRate {
                    LabeledContent("Heart rate reading", value: "\(heartRate) bpm")
                }
                if summary.activeEnergyKilocalories > 0 {
                    LabeledContent("Active energy", value: "\(summary.activeEnergyKilocalories.formatted(.number.precision(.fractionLength(0)))) kcal")
                }
                LabeledContent("Companion XP", value: "\(summary.experienceEarned)")
            } header: {
                Label(summary.workoutConfiguration.activity.displayName, systemImage: summary.workoutConfiguration.activity.symbol)
            } footer: {
                Text("Metrics reflect the readings available during this workout. This journal doesn’t confirm whether a separate copy was saved to Apple Health.")
            }
            .listRowBackground(PawTheme.surface)
            if !summary.activitySegments.isEmpty {
                Section("Activities") {
                    ForEach(Array(summary.activitySegments.enumerated()), id: \.offset) { _, segment in
                        LabeledContent(segment.configuration.activity.displayName, value: PawPaceFormatting.duration(seconds: activeSeconds(in: segment)))
                    }
                }
                .listRowBackground(PawTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PawTheme.background.ignoresSafeArea())
        .foregroundStyle(PawTheme.ink)
        .navigationTitle("Workout details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func activeSeconds(in segment: WorkoutActivitySegment) -> Int {
        Int(WorkoutTiming.activeIntervals(
            startedAt: segment.startedAt,
            endedAt: min(segment.endedAt ?? summary.endedAt, summary.endedAt),
            pauseIntervals: summary.pauseIntervals
        ).reduce(0) { $0 + $1.duration })
    }

}
