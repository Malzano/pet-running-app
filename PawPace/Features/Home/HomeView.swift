import SwiftUI

struct HomeView: View {
    @ObservedObject var store: PetStore
    @Binding var selectedTab: AppTab

    private var pet: PetSnapshot { store.snapshot }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                header
                habitat
                experience
                petActions
                dailyQuest
                evolutionCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            if let reaction = store.latestReaction {
                Text(reaction)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(PawTheme.ink, in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: reaction) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { store.clearReaction() }
                    }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("GOOD MORNING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(PawTheme.inkSecondary)
                Text("Sam")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(PawTheme.energyYellow)
                Text(pet.coins.formatted())
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(PawTheme.surface, in: Capsule())
            .shadow(color: PawTheme.ink.opacity(0.08), radius: 10, y: 5)
        }
    }

    private var habitat: some View {
        ZStack {
            PawTheme.habitatGradient

            Circle()
                .fill(PawTheme.energyYellow.opacity(0.22))
                .frame(width: 190, height: 190)
                .offset(x: -105, y: -105)

            Ellipse()
                .fill(PawTheme.grassGreen.opacity(0.45))
                .frame(width: 420, height: 150)
                .offset(y: 145)

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STAGE \(pet.stage.rawValue) · \(pet.stage.displayName.uppercased())")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                        Text("LV \(pet.level)")
                            .font(.system(.title3, design: .rounded, weight: .heavy))
                    }
                    .foregroundStyle(PawTheme.ink)
                    Spacer()
                    Text(pet.mood.label)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(PawTheme.surface.opacity(0.88), in: Capsule())
                }

                ZStack(alignment: .topTrailing) {
                    MochiCreatureView(
                        mood: pet.mood,
                        stage: pet.stage,
                        accessory: pet.equippedAccessory,
                        decoration: pet.activeDecoration
                    )
                        .frame(maxWidth: 240)
                    Text(store.latestReaction ?? pet.mood.shortMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PawTheme.ink)
                        .lineLimit(3)
                        .frame(width: 142, alignment: .leading)
                        .padding(11)
                        .background(PawTheme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 5, topTrailingRadius: 16))
                        .shadow(color: PawTheme.ink.opacity(0.1), radius: 8, y: 4)
                        .offset(x: 2, y: 14)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(17)
        }
        .frame(height: 342)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: PawTheme.ink.opacity(0.09), radius: 16, y: 8)
    }

    private var experience: some View {
        VStack(spacing: 8) {
            HStack {
                Text("EXPERIENCE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                Spacer()
                Text("\(pet.experience) / \(pet.experienceGoal)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PawTheme.inkSecondary)
            }
            ProgressView(value: pet.experienceProgress)
                .tint(PawTheme.adventureBlue)
                .scaleEffect(x: 1, y: 1.5)
        }
        .padding(.horizontal, 3)
    }

    private var petActions: some View {
        HStack(spacing: 9) {
            PetActionButton(title: "Feed", symbol: "carrot.fill", tint: PawTheme.energyYellow, action: store.feed)
            PetActionButton(title: "Pet", symbol: "hand.tap.fill", tint: PawTheme.coralOrange, action: store.pet)
            PetActionButton(title: "Talk", symbol: "message.fill", tint: PawTheme.adventureBlue) { selectedTab = .chat }
            PetActionButton(title: "Play", symbol: "tennisball.fill", tint: PawTheme.grassGreen, action: store.play)
        }
    }

    private var dailyQuest: some View {
        VStack(spacing: 11) {
            SectionKicker(title: "Daily quest", trailing: "1.2 KM LEFT")
            HStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(PawTheme.grassGreen)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Run 3.0 km with \(pet.name)")
                        .font(.subheadline.weight(.bold))
                    ProgressView(value: min(pet.distanceTodayKilometers / 3, 1))
                        .tint(PawTheme.grassGreen)
                    Text("\(pet.distanceTodayKilometers, specifier: "%.1f") / 3.0 km")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PawTheme.inkSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("+120 XP")
                    Text("+2 ITEMS")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(PawTheme.adventureBlue)
            }
            Button {
                selectedTab = .run
            } label: {
                Label("Start run", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(PawTheme.adventureBlue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .pawCard()
    }

    private var evolutionCard: some View {
        VStack(spacing: 10) {
            SectionKicker(title: "Next evolution")
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(PawTheme.energyYellow.opacity(0.2))
                    Image(systemName: pet.nextStage == nil ? "sparkles" : "leaf.fill")
                        .font(.title2.bold())
                        .foregroundStyle(PawTheme.energyYellow)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pet.nextStage.map { "\($0.displayName) — locked" } ?? "Final form reached")
                        .font(.subheadline.weight(.bold))
                    Text(evolutionSubtitle)
                        .font(.caption)
                        .foregroundStyle(PawTheme.inkSecondary)
                    ProgressView(value: pet.evolutionProgress)
                        .tint(PawTheme.energyYellow)
                }
            }
        }
        .pawCard()
    }

    private var evolutionSubtitle: String {
        guard let next = pet.nextStage else { return "Friendship can still grow" }
        return "Reaches stage \(next.rawValue) at level \(next.minimumLevel) · \(max(next.minimumLevel - pet.level, 0)) to go"
    }
}

private struct PetActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PawTheme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: PawTheme.ink.opacity(0.07), radius: 9, y: 4)
        }
        .buttonStyle(.plain)
    }
}
