import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct PawPaceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PawPaceActivityAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
                .activityBackgroundTint(PawTheme.surface)
                .activitySystemActionForegroundColor(PawTheme.adventureBlue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        MochiCreatureView(mood: context.state.isPaused ? .curious : .excited, stage: .sprout)
                            .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.petName)
                                .font(.caption.weight(.bold))
                            Text(context.state.isPaused ? "Waiting" : "Running")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(context.state.heartRate > 0 ? context.state.heartRate : 142)")
                            .font(.headline.monospacedDigit().bold())
                        Label("BPM", systemImage: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.pink)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.encouragement)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        LiveMetric(value: PawPaceFormatting.distance(kilometers: context.state.distanceKilometers), label: "KM")
                        LiveMetric(value: PawPaceFormatting.pace(secondsPerKilometer: context.state.paceSecondsPerKilometer), label: "PACE")
                        LiveMetric(value: "+\(context.state.experienceEarned)", label: "XP")

                        Button(intent: ToggleRunPauseIntent()) {
                            Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                                .font(.caption.bold())
                                .frame(width: 34, height: 34)
                                .background(PawTheme.adventureBlue, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } compactLeading: {
                Image(systemName: "pawprint.fill")
                    .foregroundStyle(PawTheme.energyYellow)
            } compactTrailing: {
                Text("\(context.state.distanceKilometers, specifier: "%.1f") km")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(PawTheme.grassGreen)
            } minimal: {
                Image(systemName: "figure.run")
                    .foregroundStyle(PawTheme.energyYellow)
            }
            .keylineTint(PawTheme.adventureBlue)
        }
    }
}

private struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<PawPaceActivityAttributes>

    var body: some View {
        VStack(spacing: 11) {
            HStack {
                Label("PAWPACE · MORNING RUN", systemImage: "pawprint.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(PawTheme.adventureBlue)
                Spacer()
                Text(PawPaceFormatting.duration(seconds: context.state.elapsedSeconds))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(PawTheme.inkSecondary)
            }

            HStack(spacing: 12) {
                MochiCreatureView(mood: context.state.isPaused ? .curious : .excited, stage: .sprout)
                    .frame(width: 62, height: 62)
                    .padding(5)
                    .background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.encouragement)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    ProgressView(value: min(context.state.distanceKilometers / context.attributes.questTargetKilometers, 1))
                        .tint(PawTheme.grassGreen)
                    Text("\(context.state.distanceKilometers, specifier: "%.2f") / \(context.attributes.questTargetKilometers, specifier: "%.1f") km quest")
                        .font(.caption2)
                        .foregroundStyle(PawTheme.inkSecondary)
                }
            }

            HStack(spacing: 8) {
                LiveMetric(value: PawPaceFormatting.distance(kilometers: context.state.distanceKilometers), label: "KILOMETERS")
                LiveMetric(value: PawPaceFormatting.pace(secondsPerKilometer: context.state.paceSecondsPerKilometer), label: "AVG PACE")
                LiveMetric(value: "+\(context.state.experienceEarned)", label: "PET XP")

                Button(intent: ToggleRunPauseIntent()) {
                    Label(context.state.isPaused ? "Resume" : "Pause", systemImage: context.state.isPaused ? "play.fill" : "pause.fill")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .foregroundStyle(.white)
                        .background(PawTheme.adventureBlue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }
}

private struct LiveMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(PawTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

