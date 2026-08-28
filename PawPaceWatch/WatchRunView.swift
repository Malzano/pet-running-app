import SwiftUI

struct WatchRunView: View {
    @ObservedObject var workout: WatchWorkoutManager
    @ObservedObject var connectivity: WatchPetConnectivityService

    private var run: PawPaceRunState {
        if workout.state.phase == .idle, connectivity.phoneRunState.phase != .idle {
            return connectivity.phoneRunState
        }
        return workout.state
    }

    private var petMood: PetMood {
        switch run.phase {
        case .running: .excited
        case .paused: .curious
        case .finished: .proud
        case .failed: .tired
        case .idle: connectivity.pet.mood
        }
    }

    private var petMotion: PetMotion {
        switch run.phase {
        case .running: .running
        case .finished: .celebrating
        case .idle, .paused, .failed: .idle
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                HStack {
                    Label("PAWPACE", systemImage: "pawprint.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(PawTheme.energyYellow)
                    Spacer()
                    Circle()
                        .fill(connectivity.isPhoneReachable ? PawTheme.grassGreen : PawTheme.inkSecondary)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(connectivity.isPhoneReachable ? "iPhone connected" : "iPhone unavailable")
                }

                HStack(spacing: 5) {
                    MochiCreatureView(
                        mood: petMood,
                        stage: connectivity.pet.stage,
                        accessory: connectivity.pet.equippedAccessory,
                        decoration: connectivity.pet.activeDecoration,
                        motion: petMotion
                    )
                    .frame(width: 78, height: 78)

                    WatchHeartRateZoneCard(heartRate: run.heartRate)
                }

                Text(run.encouragement)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    WatchMetric(
                        value: PawPaceFormatting.distance(kilometers: run.distanceKilometers),
                        label: "KM",
                        tint: PawTheme.grassGreen
                    )
                    WatchMetric(
                        value: PawPaceFormatting.duration(seconds: run.elapsedSeconds),
                        label: "TIME",
                        tint: PawTheme.adventureBlue
                    )
                }

                HStack(spacing: 6) {
                    WatchMetric(
                        value: PawPaceFormatting.pace(secondsPerKilometer: run.paceSecondsPerKilometer),
                        label: "PACE",
                        tint: PawTheme.teal
                    )
                    WatchMetric(
                        value: "+\(run.experienceEarned)",
                        label: "XP",
                        tint: PawTheme.energyYellow
                    )
                }

                controls

                if let errorMessage = workout.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(PawTheme.energyYellow)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .containerBackground(PawTheme.background.gradient, for: .navigation)
    }

    @ViewBuilder
    private var controls: some View {
        switch workout.state.phase {
        case .idle, .finished, .failed:
            Button {
                workout.start()
            } label: {
                Label(
                    workout.isStarting ? "Starting…" : "Start with \(connectivity.pet.name)",
                    systemImage: "figure.run"
                )
                    .frame(maxWidth: .infinity)
            }
            .disabled(workout.isStarting)
            .buttonStyle(.borderedProminent)
            .tint(PawTheme.grassGreen)
        case .running, .paused:
            HStack(spacing: 7) {
                Button {
                    workout.state.phase == .running ? workout.pause() : workout.resume()
                } label: {
                    Image(systemName: workout.state.phase == .running ? "pause.fill" : "play.fill")
                }
                .tint(PawTheme.adventureBlue)

                Button(role: .destructive) {
                    workout.finish()
                } label: {
                    Image(systemName: "flag.checkered")
                }
                .tint(PawTheme.coralOrange)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct WatchHeartRateZoneCard: View {
    let heartRate: Int

    private var zone: PawPaceHeartRateZone? {
        PawPaceHeartRateZone.zone(for: heartRate)
    }

    private var tint: Color {
        zone?.tint ?? PawTheme.inkSecondary
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(heartRate > 0 ? "\(heartRate) BPM" : "— BPM")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text(zone.map { "ZONE \($0.rawValue) · \($0.label.uppercased())" } ?? "WAITING FOR SENSOR")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 3) {
                ForEach(PawPaceHeartRateZone.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(
                            item.rawValue <= (zone?.rawValue ?? 0)
                                ? item.tint
                                : PawTheme.line.opacity(0.7)
                        )
                        .frame(height: 5)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            heartRate > 0
                ? "\(heartRate) beats per minute, \(zone?.accessibilityLabel ?? "heart rate zone unavailable")"
                : "Waiting for heart rate sensor"
        )
    }
}

private struct WatchMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
