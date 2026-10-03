import SwiftUI

struct HomeView: View {
    @ObservedObject var store: PetStore
    @Binding var selectedTab: AppTab
    var onOpenSettings: () -> Void = {}
    var onOpenProgress: (() -> Void)?
    var onOpenJourney: () -> Void = {}
    var onOpenPlay: () -> Void = {}
    var onOpenQuests: () -> Void = {}
    var onReviewInterrupted: (() -> Void)?
    var completionMessage: String?
    var onRetrySave: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var companionMotion: PetMotion = .idle
    @State private var interaction = 0
    @State private var isCompanionResting = false
    @State private var habitatCameraReset = 0
    @State private var habitatZoom = 1.0

    private var pet: PetSnapshot { store.snapshot }
    private let dailyGoal = 30.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        VStack(spacing: 22) {
                            header
                            Color.clear.frame(height: 220)
                            bottomDock
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    VStack(spacing: 0) {
                        header
                        Spacer(minLength: 12)
                        bottomDock
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }

                HStack {
                    Spacer()
                    cameraControls
                }
                .padding(.trailing, 16)
                .offset(y: geometry.size.height < 700 ? -92 : -36)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                CompanionHabitatView(
                    pet: pet,
                    motion: companionMotion,
                    interaction: interaction,
                    showsEquipment: false,
                    isResting: isCompanionResting,
                    cameraReset: habitatCameraReset,
                    cameraZoom: $habitatZoom,
                    immersive: true,
                    onPlay: play,
                    onFeed: feed,
                    onPet: petCompanion,
                    onRoam: { isCompanionResting = false; store.exploreWithBuddy() }
                )
                .overlay { Color.black.opacity(colorScheme == .dark ? 0.52 : 0).allowsHitTesting(false) }
                .ignoresSafeArea()
            }
        }
        .background(PawTheme.habitatGradient.ignoresSafeArea())
        .onChange(of: pet.companionID) { _, _ in
            companionMotion = .idle
            isCompanionResting = false
            interaction += 1
        }
        .task(id: interaction) {
            guard companionMotion == .jumping || companionMotion == .playing || companionMotion == .feeding || companionMotion == .special else { return }
            do { try await Task.sleep(for: .seconds(companionMotion == .special ? 4.5 : 3)) } catch { return }
            companionMotion = .idle
        }
        .task(id: store.latestReaction) {
            guard store.latestReaction != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            store.clearReaction()
        }
        .sensoryFeedback(.selection, trigger: pet.lifeStage)
        .sensoryFeedback(.impact(weight: .light), trigger: interaction)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("PAWPACE")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(PawTheme.adventureBlue)
                Text(pet.lifeStage == .egg ? "A little beginning" : "You & \(pet.name)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(pet.lifeStage == .egg ? "Your mystery egg" : "\(pet.lifeStage.displayName) · \(pet.species.displayName)")
                    .font(.caption)
                    .foregroundStyle(PawTheme.ink.opacity(0.85))
            }
            .padding(.vertical, 8)
            Spacer(minLength: 0)
            circleButton("Adventures and your home", symbol: "map", action: onOpenJourney)
            circleButton("Settings and help", symbol: "gearshape", action: onOpenSettings)
        }
    }

    private var cameraControls: some View {
        VStack(spacing: 4) {
            Button {
                habitatZoom = min(CompanionCameraZoom.maximum, habitatZoom * 1.2)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .disabled(habitatZoom >= CompanionCameraZoom.maximum - 0.001)
            .accessibilityLabel("Zoom in on your companion")
            .accessibilityValue("\(Int(habitatZoom * 100)) percent")

            Button {
                habitatZoom = max(CompanionCameraZoom.minimum, habitatZoom / 1.2)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .disabled(habitatZoom <= CompanionCameraZoom.minimum + 0.001)
            .accessibilityLabel("Zoom out to see the garden")

            Divider().frame(width: 20)
            Button {
                habitatZoom = 1
                habitatCameraReset += 1
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Reset garden view and zoom")
        }
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(PawTheme.adventureBlue)
        .buttonStyle(.plain)
        .padding(3)
        .background(PawTheme.surface.opacity(0.9), in: Capsule())
        .overlay { Capsule().strokeBorder(PawTheme.line.opacity(0.6), lineWidth: 1) }
    }

    private var bottomDock: some View {
        VStack(spacing: 12) {
            if let message = store.storageMessage ?? completionMessage {
                VStack(spacing: 6) {
                    Text(message).font(.caption).multilineTextAlignment(.center)
                    Button("Try again") { store.reloadFromSharedStorage(); onRetrySave?() }
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
                .padding(12)
                .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            }
            if let onReviewInterrupted {
                Button(action: onReviewInterrupted) {
                    Label("Review interrupted workout", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(PawTheme.surface.opacity(0.95), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if let reaction = store.latestReaction {
                Text(reaction)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PawTheme.surface.opacity(0.95), in: Capsule())
                    .accessibilityAddTraits(.updatesFrequently)
                    .allowsHitTesting(false)
            }

            HStack {
                Text("Drag to turn · Pinch to zoom")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(PawTheme.ink.opacity(0.85))
                Spacer(minLength: 8)
                if pet.lifeStage != .egg {
                    Button {
                        isCompanionResting.toggle()
                    } label: {
                        Label(isCompanionResting ? "Explore" : "Rest", systemImage: isCompanionResting ? "figure.walk" : "pause")
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                            .padding(.horizontal, 12)
                            .background(PawTheme.surface.opacity(0.9), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCompanionResting ? "Let your companion explore" : "Let your companion rest")
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 15) {
                Button(action: onOpenQuests) {
                    HStack(spacing: 9) {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text("\(pet.quests.currentStreak(journey: pet.journey, at: .now)) day streak").font(.subheadline.bold())
                        Spacer()
                        Text(pet.quests.gifts.contains { $0.openedAt == nil } ? "Open a surprise" : "Daily quests")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption2)
                    }.frame(minHeight: 36).foregroundStyle(PawTheme.adventureBlue)
                }.buttonStyle(.plain)
                Divider()
                progressButton
                HStack(spacing: 10) {
                    if pet.lifeStage != .egg {
                        careButton("Snack", symbol: "carrot", action: feed)
                        careButton("Play", symbol: "tennisball", action: onOpenPlay)
                            .accessibilityLabel("Play together")
                            .accessibilityHint("Open games, personality, and your companion’s favorite things")
                    }
                    Button { selectedTab = .run } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.mixed.cardio")
                            Text(pet.lifeStage == .egg ? "Workout to hatch" : "Workout")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if pet.lifeStage == .egg {
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PawTheme.buttonForeground)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(PawTheme.adventureBlue, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(PawTheme.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(PawTheme.line.opacity(0.55), lineWidth: 1)
            }
        }
    }

    private var progressButton: some View {
        Button { onOpenProgress?() } label: {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: pet.lifeStage == .egg ? "sparkles" : "leaf")
                        .font(.title3)
                        .foregroundStyle(PawTheme.adventureBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pet.lifeStage == .egg ? "A little closer to hello" : pet.lifeStage == .baby ? "Growing together" : "Today, together")
                            .font(.subheadline.weight(.semibold))
                        Text(progressDescription)
                            .font(.caption)
                            .foregroundStyle(PawTheme.inkSecondary)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PawTheme.inkSecondary)
                }
                ProgressView(value: pet.lifeStage == .adult
                             ? min(Double(pet.currentDayMovementMinutes) / dailyGoal, 1)
                             : pet.lifecycle?.growthProgress ?? 0)
                    .tint(PawTheme.adventureBlue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progressDescription). View growth, genes, daily progress, and habitat choices")
    }

    private var progressDescription: String {
        if let lifecycle = pet.lifecycle, pet.lifeStage != .adult {
            let minutes = Int(ceil(lifecycle.secondsUntilNextStage / 60))
            return pet.lifeStage == .egg ? "\(minutes) progress min until hatching" : "\(minutes) progress min until grown-up"
        }
        return "\(pet.currentDayMovementMinutes) of 30 progress minutes today"
    }

    private func circleButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(PawTheme.adventureBlue)
                .frame(width: 46, height: 46)
                .background(PawTheme.surface.opacity(0.92), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func careButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 18))
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(PawTheme.adventureBlue)
            .frame(width: 52, height: 52)
            .background(PawTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func animateCompanion(_ motion: PetMotion) {
        isCompanionResting = false
        companionMotion = motion
        interaction += 1
    }

    private func feed() { store.feed(); animateCompanion(.feeding) }
    private func play() { store.play(); animateCompanion(pet.species.specialMoveName == nil ? .playing : .special) }
    private func petCompanion() { store.pet(); animateCompanion(.jumping) }
}
