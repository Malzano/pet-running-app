import SwiftUI

struct WatchRunView: View {
    @ObservedObject var workout: WatchWorkoutManager
    @ObservedObject var connectivity: WatchPetConnectivityService
    @State private var showsFinishConfirmation = false
    @State private var showsWorkoutPicker = false

    private var isViewingPhoneWorkout: Bool {
        workout.state.phase == .idle
            && (connectivity.phoneRunState.phase == .running || connectivity.phoneRunState.phase == .paused)
    }

    private var hasActiveRun: Bool {
        run.phase == .running || run.phase == .paused
    }

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

    private var companionName: String {
        connectivity.pet.lifeStage == .egg ? "Mystery egg" : connectivity.pet.name
    }

    private var isGrowing: Bool { connectivity.pet.lifeStage != .adult }

    private var growthMinutesRemaining: Int {
        Int(ceil((connectivity.pet.lifecycle?.secondsUntilNextStage ?? 0) / 60))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                header

                if hasActiveRun {
                    metrics
                    controls
                    WatchHeartRateZoneCard(heartRate: run.heartRate)
                    companion
                } else {
                    companion
                    if workout.state.phase != .running && workout.state.phase != .paused && !isViewingPhoneWorkout {
                        workoutSelection
                    }
                    controls
                    if run.phase == .finished || (run.phase == .failed && run.elapsedSeconds > 0) {
                        metrics
                    } else {
                        companionProgress
                    }
                }

                Text(run.encouragement)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PawTheme.inkSecondary)
                    .multilineTextAlignment(.center)

                if let errorMessage = workout.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(PawTheme.energyYellow)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .containerBackground(PawTheme.background.gradient, for: .navigation)
        .sheet(isPresented: $showsWorkoutPicker) {
            WorkoutPickerView(selection: workout.selectedConfiguration.activity) { activity in
                workout.configure(WorkoutConfiguration(activity: activity))
            }
        }
        .confirmationDialog("Finish this workout?", isPresented: $showsFinishConfirmation, titleVisibility: .visible) {
            Button("Finish workout", role: .destructive) {
                workout.finish()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("End your workout and save your progress with \(companionName).")
        }
    }

    private var header: some View {
        HStack {
            Label(hasActiveRun ? (run.phase == .paused ? "PAUSED" : run.workoutConfiguration.activity.displayName.uppercased()) : "PAWPACE", systemImage: "pawprint.fill")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(PawTheme.energyYellow)
            Spacer(minLength: 4)
            Image(systemName: connectivity.isPhoneReachable ? "iphone.radiowaves.left.and.right" : "iphone")
                .font(.caption2)
                .foregroundStyle(connectivity.isPhoneReachable ? PawTheme.grassGreen : PawTheme.inkSecondary)
                .accessibilityLabel(connectivity.isPhoneReachable ? "iPhone connected" : "iPhone unavailable")
        }
    }

    private var companion: some View {
        HStack(spacing: 5) {
            AnimalPortraitView(pet: connectivity.pet)
            .frame(width: hasActiveRun ? 58 : 78, height: hasActiveRun ? 58 : 78)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(companionName)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(connectivity.pet.lifeStage == .egg
                     ? "A little surprise inside"
                     : "\(connectivity.pet.lifeStage.displayName) · \(connectivity.pet.species.displayName)")
                    .font(.caption2)
                    .foregroundStyle(PawTheme.inkSecondary)
                Text(connectivity.pet.lifeStage == .egg ? "Move together to hatch" : petMood.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PawTheme.grassGreen)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var companionProgress: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(isGrowing ? (connectivity.pet.lifeStage == .egg ? "HATCHING" : "GROWING UP") : "NEXT LEVEL")
                    .font(.caption2.weight(.bold))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: progress)
                .tint(PawTheme.energyYellow)
                .accessibilityLabel(isGrowing ? "Growth progress" : "Experience toward next level")
            Text(isGrowing
                 ? "\(growthMinutesRemaining) workout min to \(connectivity.pet.lifeStage == .egg ? "hatch" : "adulthood")"
                 : "\(max(0, connectivity.pet.experienceGoal - connectivity.pet.experience)) XP to go")
                .font(.caption2)
                .foregroundStyle(PawTheme.inkSecondary)
        }
        .padding(10)
        .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var progress: Double {
        isGrowing ? (connectivity.pet.lifecycle?.growthProgress ?? 0) : connectivity.pet.experienceProgress
    }

    private var metrics: some View {
        VStack(spacing: 6) {
            Text(run.workoutConfiguration.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(PawTheme.inkSecondary)
            HStack(spacing: 6) {
                WatchMetric(value: PawPaceFormatting.duration(seconds: run.elapsedSeconds), label: "TIME", tint: PawTheme.adventureBlue)
                WatchMetric(value: run.activeEnergyKilocalories > 0 ? "\(Int(run.activeEnergyKilocalories))" : "—", label: "ACTIVE KCAL", tint: PawTheme.coralOrange)
            }
            HStack(spacing: 6) {
                if run.workoutConfiguration.supportsDistance {
                    WatchMetric(value: PawPaceFormatting.distance(kilometers: run.distanceKilometers), label: "KM", tint: PawTheme.grassGreen)
                }
                if hasMovementMetric {
                    movementMetric
                } else {
                    WatchMetric(value: "+\(run.experienceEarned)", label: "XP", tint: PawTheme.energyYellow)
                }
            }
            if hasMovementMetric {
                Text("+\(run.experienceEarned) pet XP")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PawTheme.energyYellow)
                    .monospacedDigit()
            }
            if run.workoutConfiguration.activity == .swimBikeRun {
                Text("Stage \(run.multisportLegIndex + 1) · \(run.workoutConfiguration.configuration(forMultisportLeg: run.multisportLegIndex).activity.displayName)")
                    .font(.caption2)
                if workout.canAdvanceActivity {
                    Button("Next stage", systemImage: "forward.end") { workout.nextActivity() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var hasMovementMetric: Bool {
        switch run.workoutConfiguration.measurement {
        case .pace, .swimPace, .speed: true
        case .duration, .distance: false
        }
    }

    @ViewBuilder
    private var movementMetric: some View {
        switch run.workoutConfiguration.measurement {
        case .pace:
            WatchMetric(value: PawPaceFormatting.pace(secondsPerKilometer: run.paceSecondsPerKilometer),
                        label: "PACE / KM", tint: PawTheme.adventureBlue)
        case .swimPace:
            WatchMetric(value: PawPaceFormatting.pace(secondsPerKilometer: run.paceSecondsPerKilometer / 10),
                        label: "PACE / 100 M", tint: PawTheme.adventureBlue)
        case .speed:
            WatchMetric(value: run.elapsedSeconds > 0 && run.distanceKilometers > 0
                        ? String(format: "%.1f", run.distanceKilometers * 3600 / Double(run.elapsedSeconds)) : "—",
                        label: "KM / H", tint: PawTheme.adventureBlue)
        case .duration, .distance:
            EmptyView()
        }
    }

    private var workoutSelection: some View {
        VStack(spacing: 8) {
            Button { showsWorkoutPicker = true } label: {
                Label(workout.selectedConfiguration.displayName, systemImage: workout.selectedConfiguration.activity.symbol)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if workout.selectedConfiguration.activity == .swimming {
                Picker("Swim", selection: Binding(
                    get: { workout.selectedConfiguration.swimmingLocation },
                    set: { location in
                        var selected = workout.selectedConfiguration
                        selected.swimmingLocation = location
                        selected.location = location == .pool ? .indoor : .outdoor
                        workout.configure(selected)
                    }
                )) {
                    Text("Pool").tag(WorkoutSwimmingLocation.pool)
                    Text("Open water").tag(WorkoutSwimmingLocation.openWater)
                }
                if workout.selectedConfiguration.swimmingLocation == .pool {
                    Picker("Pool meters", selection: Binding(
                        get: { Int(workout.selectedConfiguration.poolLengthMeters ?? 25) },
                        set: { value in
                            var selected = workout.selectedConfiguration
                            selected.poolLengthMeters = Double(value)
                            workout.configure(selected)
                        }
                    )) {
                        ForEach(1...150, id: \.self) { value in Text("\(value) m").tag(value) }
                    }
                }
            } else if workout.selectedConfiguration.supportsDistance, workout.selectedConfiguration.activity.allowedLocations.count > 1 {
                Picker("Location", selection: Binding(
                    get: { workout.selectedConfiguration.location },
                    set: { location in
                        var selected = workout.selectedConfiguration
                        selected.location = location
                        workout.configure(selected)
                    }
                )) {
                    ForEach(workout.selectedConfiguration.activity.allowedLocations) { location in
                        Text(location.displayName).tag(location)
                    }
                }
            }
        }
        .disabled(workout.isStarting)
    }

    @ViewBuilder
    private var controls: some View {
        if isViewingPhoneWorkout {
            VStack(spacing: 4) {
                Label("Workout on iPhone", systemImage: "iphone")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PawTheme.adventureBlue)
                Text("Use your iPhone to pause or finish.")
                    .font(.caption2)
                    .foregroundStyle(PawTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } else {
            workoutControls
        }
    }

    @ViewBuilder
    private var workoutControls: some View {
        switch workout.state.phase {
        case .idle, .finished, .failed:
            Button {
                workout.start()
            } label: {
                Label(
                    workout.isStarting ? "Starting…" : "Start workout",
                    systemImage: workout.selectedConfiguration.activity.symbol
                )
                    .frame(maxWidth: .infinity)
            }
            .disabled(workout.isStarting)
            .buttonStyle(.borderedProminent)
            .tint(PawTheme.grassGreen)
            .accessibilityLabel(workout.isStarting ? "Starting workout" : "Start workout with \(companionName)")
        case .running, .paused:
            HStack(spacing: 7) {
                Button {
                    workout.state.phase == .running ? workout.pause() : workout.resume()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: workout.state.phase == .running ? "pause.fill" : "play.fill")
                        Text(workout.state.phase == .running ? "Pause" : "Resume")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .tint(PawTheme.adventureBlue)
                .accessibilityLabel(workout.state.phase == .running ? "Pause workout" : "Resume workout")

                Button {
                    showsFinishConfirmation = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "flag.checkered")
                        Text("Finish")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .tint(PawTheme.coralOrange)
                .accessibilityLabel("Finish workout")
                .accessibilityHint("Asks before ending your workout")
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
