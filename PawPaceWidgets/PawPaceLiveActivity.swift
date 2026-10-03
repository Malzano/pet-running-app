import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct PawPaceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PawPaceActivityAttributes.self) { context in
            LiveWorkoutView(context: context)
                .activityBackgroundTint(PawTheme.surface)
                .activitySystemActionForegroundColor(PawTheme.adventureBlue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.configuration.activity.displayName, systemImage: context.state.configuration.activity.symbol)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isPaused ? "Paused" : PawPaceFormatting.duration(seconds: context.state.elapsedSeconds))
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        liveMetric(context.state.primaryValue, label: context.state.primaryLabel)
                        liveMetric(context.state.heartRate > 0 ? "\(context.state.heartRate)" : "—", label: "BPM")
                        liveMetric("+\(context.state.experienceEarned)", label: "PET XP")
                        pauseButton(paused: context.state.isPaused)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.configuration.activity.symbol)
                    .foregroundStyle(PawTheme.grassGreen)
            } compactTrailing: {
                Text(PawPaceFormatting.duration(seconds: context.state.elapsedSeconds))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.state.configuration.activity.symbol)
                    .foregroundStyle(PawTheme.grassGreen)
            }
            .keylineTint(PawTheme.adventureBlue)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

@available(iOSApplicationExtension 18.0, *)
private struct LiveWorkoutView: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<PawPaceActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(context.state.configuration.activity.displayName, systemImage: context.state.configuration.activity.symbol)
                    .font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 5)
                Text(context.state.isPaused ? "Paused" : PawPaceFormatting.duration(seconds: context.state.elapsedSeconds))
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            .foregroundStyle(PawTheme.adventureBlue)
            HStack(spacing: 12) {
                AnimalPortraitView(
                    species: context.state.petSpecies ?? .corgi,
                    lifeStage: context.state.petLifeStage ?? .adult,
                    variant: context.state.petVariant ?? .classic
                )
                    .frame(width: family == .small ? 40 : 58, height: family == .small ? 40 : 58)
                liveMetric(context.state.primaryValue, label: context.state.primaryLabel)
                liveMetric(context.state.heartRate > 0 ? "\(context.state.heartRate)" : "—", label: "BPM")
                if family != .small {
                    liveMetric("+\(context.state.experienceEarned)", label: "PET XP")
                    pauseButton(paused: context.state.isPaused)
                }
            }
        }
        .padding(14)
        .widgetURL(URL(string: "pawpace://workout"))
    }
}

private extension PawPaceActivityAttributes.ContentState {
    var configuration: WorkoutConfiguration { workoutConfiguration ?? .init() }
    var primaryLabel: String { configuration.supportsDistance ? "KM" : "ACTIVE KCAL" }
    var primaryValue: String {
        if configuration.supportsDistance { return PawPaceFormatting.distance(kilometers: distanceKilometers) }
        return (activeEnergyKilocalories ?? 0) > 0 ? "\(Int(activeEnergyKilocalories ?? 0))" : "—"
    }
}

private func liveMetric(_ value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(value).font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
        Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(PawTheme.inkSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func pauseButton(paused: Bool) -> some View {
    Button(intent: ToggleRunPauseIntent()) {
        Image(systemName: paused ? "play.fill" : "pause.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(PawTheme.buttonForeground)
            .frame(width: 36, height: 36)
            .background(PawTheme.adventureBlue, in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(paused ? "Resume workout" : "Pause workout")
}
