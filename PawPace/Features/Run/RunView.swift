import SwiftUI

/// The tracker keeps its storage identity for existing workouts; the screen is
/// activity-driven, including workouts with no distance or GPS component.
struct RunView: View {
    @ObservedObject var tracker: RunTracker
    let pet: PetSnapshot
    var onChooseActivity: (() -> Void)?
    let onStart: () async -> Void
    let onFinish: () async -> Void
    @State private var isPreparingRun = false
    @State private var showingFinishConfirmation = false

    private var activity: WorkoutActivity { tracker.configuration.activity }
    private var isActive: Bool { tracker.phase == .running || tracker.phase == .paused }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 48.0
    private let popular: [WorkoutActivity] = [.walking, .running, .cycling, .traditionalStrengthTraining, .yoga, .swimming]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isActive ? 18 : 24) {
                header
                if let message = tracker.recoveredWorkoutMessage {
                    Label(message, systemImage: "clock.arrow.circlepath")
                        .font(.subheadline).foregroundStyle(PawTheme.inkSecondary).pawCard()
                }
                if let message = tracker.recoveryStorageMessage {
                    Label(message, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.caption).foregroundStyle(PawTheme.inkSecondary).pawCard()
                }
                if isActive {
                    companion
                    session
                } else {
                    selection
                    settings
                    suggestions
                    Label(pet.lifeStage == .egg ? "Every workout brings your egg closer to hatching." : "Every workout builds your friendship.", systemImage: "pawprint")
                        .font(.caption)
                        .foregroundStyle(PawTheme.inkSecondary)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(PawTheme.background.ignoresSafeArea())
        .foregroundStyle(PawTheme.ink)
        .safeAreaInset(edge: .bottom) {
            controls
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(PawTheme.background)
        }
        .task(id: isPreparingRun) {
            guard isPreparingRun else { return }
            await onStart()
            guard !Task.isCancelled else { return }
            isPreparingRun = false
        }
        .onDisappear { isPreparingRun = false }
        .confirmationDialog("Finish this workout?", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
            Button("Finish and save") { Task { await onFinish() } }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your \(activity.displayName.lowercased()) workout and earned XP will be saved.")
        }
    }

    @ViewBuilder private var header: some View {
        if isActive {
            HStack(spacing: 12) {
                Image(systemName: tracker.currentActivityConfiguration.activity.symbol)
                    .font(.title3).foregroundStyle(PawTheme.adventureBlue)
                    .frame(width: 44, height: 44)
                    .background(PawTheme.surface, in: Circle())
                Text(activity.displayName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Spacer(minLength: 8)
                Text(tracker.phase == .paused ? "Paused" : "In progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PawTheme.adventureBlue)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(PawTheme.surfaceRaised, in: Capsule())
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text("Move your way")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("A little movement. A happier companion.")
                    .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
            }
        }
    }

    private var selection: some View {
        Button { onChooseActivity?() } label: {
            HStack(spacing: 16) {
                Image(systemName: activity.symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(PawTheme.adventureBlue)
                    .frame(width: 64, height: 64)
                    .background(PawTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 5) {
                    Text(activity.displayName).font(.headline).foregroundStyle(PawTheme.ink)
                    Text("Change workout")
                        .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(PawTheme.inkSecondary)
            }
            .padding(18)
            .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workoutPicker")
        .disabled(isPreparingRun)
    }

    @ViewBuilder
    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            if activity == .swimming {
                Picker("Swim location", selection: Binding(
                    get: { tracker.configuration.swimmingLocation },
                    set: { location in
                        var configuration = tracker.configuration
                        configuration.swimmingLocation = location
                        configuration.location = location == .pool ? .indoor : .outdoor
                        tracker.configure(configuration)
                    }
                )) {
                    Text("Pool").tag(WorkoutSwimmingLocation.pool)
                    Text("Open water").tag(WorkoutSwimmingLocation.openWater)
                }
                .pickerStyle(.segmented)
                if tracker.configuration.swimmingLocation == .pool {
                    Stepper(value: Binding(
                        get: { tracker.configuration.poolLengthMeters ?? 25 },
                        set: { meters in
                            var configuration = tracker.configuration
                            configuration.poolLengthMeters = meters
                            tracker.configure(configuration)
                        }
                    ), in: 1...150, step: 1) {
                        Text("Pool length · \(Int(tracker.configuration.poolLengthMeters ?? 25)) m")
                            .font(.subheadline)
                    }
                }
            } else if activity.supportsDistance, activity.allowedLocations.count > 1 {
                Picker("Location", selection: Binding(
                    get: { tracker.configuration.location },
                    set: { location in
                        var configuration = tracker.configuration
                        configuration.location = location
                        tracker.configure(configuration)
                    }
                )) {
                    ForEach(activity.allowedLocations, id: \.self) { location in
                        Text(location.displayName).tag(location)
                    }
                }
                .pickerStyle(.segmented)
            }
            if activity.requiresMultisportSession {
                Label("Swim → Cycle → Run", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.medium))
                Text("Switch stages manually here or on your Apple Watch.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            } else {
                Text(activity.supportsDistance ? "Time, distance and workout effort." : "Time and workout effort. No distance goal needed.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
            Text("Apple Watch adds live heart rate and active calories.")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }
        .disabled(isPreparingRun)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Find your movement").font(.headline)
                Spacer()
                Button("See all") { onChooseActivity?() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PawTheme.adventureBlue)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(popular) { option in
                    Button {
                        tracker.configure(WorkoutConfiguration(activity: option))
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: option.symbol).font(.title2)
                            Text(option == .traditionalStrengthTraining ? "Strength training" : option.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(height: 32, alignment: .topLeading)
                        }
                        .foregroundStyle(activity == option ? PawTheme.adventureBlue : PawTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(activity == option ? PawTheme.surfaceRaised : PawTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(activity == option ? PawTheme.adventureBlue.opacity(0.5) : .clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(activity == option ? .isSelected : [])
                }
            }
        }
        .disabled(isPreparingRun)
    }

    private var session: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                if activity.supportsDistance {
                    HStack(spacing: 16) {
                        metric(value: PawPaceFormatting.distance(kilometers: tracker.distanceKilometers), label: "kilometers", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                        if activity.supportsPace {
                            metric(value: PawPaceFormatting.pace(secondsPerKilometer: activity.measurement == .swimPace ? tracker.paceSecondsPerKilometer / 10 : tracker.paceSecondsPerKilometer), label: activity.measurement == .swimPace ? "pace / 100 m" : "pace / km", symbol: "speedometer")
                        } else if activity.measurement == .speed {
                            metric(value: tracker.elapsedSeconds > 0 ? String(format: "%.1f", tracker.distanceKilometers * 3600 / Double(tracker.elapsedSeconds)) : "—", label: "km / h", symbol: "speedometer")
                        }
                    }
                    Divider()
                }
                let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3)
                LazyVGrid(columns: columns, spacing: 12) {
                    compactMetric(value: tracker.heartRate.map(String.init) ?? "—", label: "bpm", symbol: "heart")
                    compactMetric(value: tracker.activeEnergyKilocalories > 0 ? String(Int(tracker.activeEnergyKilocalories)) : "—", label: "kcal", symbol: "flame")
                    compactMetric(value: "+\(tracker.experienceEarned)", label: "XP", symbol: "leaf")
                }
            }.pawCard(padding: 18)

            if activity.requiresMultisportSession {
                HStack(spacing: 12) {
                    Label("Stage \(tracker.multisportLegIndex + 1) · \(tracker.currentActivityConfiguration.activity.displayName)", systemImage: tracker.currentActivityConfiguration.activity.symbol)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if tracker.canAdvanceActivity {
                        Button("Next stage") { tracker.nextActivity() }
                            .font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
                    }
                }.tint(PawTheme.adventureBlue)
            }
            if tracker.currentActivityConfiguration.supportsRoute,
               tracker.locationAuthorization == .denied || tracker.locationAuthorization == .restricted {
                Label("Location is off. Your time still counts.", systemImage: "location.slash")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
        }
    }

    private func metric(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Label(label, systemImage: symbol).font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func compactMetric(value: String, label: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(PawTheme.adventureBlue)
            Text(value).fontWeight(.semibold).monospacedDigit()
            Text(label).foregroundStyle(PawTheme.inkSecondary)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var companion: some View {
        VStack(spacing: 0) {
            Text(tracker.phase == .paused ? "A little breather, together." : pet.lifeStage == .egg ? "A little closer to hello." : "One step at a time, together.")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18).padding(.top, 20)
            AnimalCompanionView(species: pet.species, motion: companionMotion, facesViewer: true,
                                lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic,
                                companionSeed: pet.lifecycle?.seed ?? 0x5EED)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 185 : 215)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(pet.lifeStage == .egg ? "Your mystery egg" : "\(pet.name), \(companionMotion == .idle ? "standing with you" : "moving with you")")
            VStack(spacing: 5) {
                Text(PawPaceFormatting.duration(seconds: tracker.elapsedSeconds))
                    .font(.system(size: timerSize, weight: .semibold, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText())
                    .accessibilityLabel("Workout time, \(PawPaceFormatting.duration(seconds: tracker.elapsedSeconds))")
                Text(tracker.phase == .paused ? "Take your time. We’re right here." : pet.lifeStage == .egg ? "Every little effort helps your egg grow." : "\(pet.name) is right here with you.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18).padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 32))
        .accessibilityIdentifier("workoutBuddy")
    }

    private var companionMotion: PetMotion {
        guard tracker.phase == .running, pet.lifeStage != .egg else { return .idle }
        switch tracker.currentActivityConfiguration.activity {
        case .running: return .running
        case .walking, .hiking: return .walking
        default: return .idle
        }
    }

    @ViewBuilder
    private var controls: some View {
        if tracker.isFinishing {
            HStack { ProgressView(); Text("Saving workout…") }
                .font(.subheadline).frame(maxWidth: .infinity).padding()
        } else if isActive {
            HStack(spacing: 12) {
                Button { tracker.togglePause() } label: {
                    Label(tracker.phase == .paused ? "Resume" : "Pause", systemImage: tracker.phase == .paused ? "play.fill" : "pause.fill")
                        .workoutControlStyle(primary: true)
                }
                Button { showingFinishConfirmation = true } label: {
                    Label("Finish", systemImage: "stop.fill").workoutControlStyle(primary: false)
                }
            }
        } else {
            Button { isPreparingRun = true } label: {
                HStack(spacing: 9) {
                    if isPreparingRun { ProgressView().tint(PawTheme.buttonForeground) }
                    Label(isPreparingRun ? "Preparing workout…" : "Start workout", systemImage: "play.fill")
                }
                .workoutControlStyle(primary: true)
            }
            .disabled(isPreparingRun)
        }
    }
}

private extension View {
    func workoutControlStyle(primary: Bool) -> some View {
        self.font(.subheadline.weight(.semibold))
            .foregroundStyle(primary ? PawTheme.buttonForeground : PawTheme.ink)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(primary ? PawTheme.adventureBlue : PawTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))
    }
}
