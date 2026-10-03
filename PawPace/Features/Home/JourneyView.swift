import SwiftUI

struct JourneyView: View {
    @ObservedObject var store: PetStore
    var canChangeCompanion = true
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    private var pet: PetSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A world to discover")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Little journeys. Familiar faces. A surprise around the bend.")
                            .foregroundStyle(PawTheme.inkSecondary)
                    }
                    if !pet.journey.waitingEggs.isEmpty { nextEgg }
                    weeklyAdventure
                    if pet.journey.waitingEggs.isEmpty { nextEgg }
                    expedition
                    NavigationLink {
                        HabitatArrangeView(store: store)
                    } label: {
                        Label("Arrange your garden", systemImage: "leaf.circle")
                            .frame(maxWidth: .infinity, alignment: .leading).pawCard()
                    }
                    NavigationLink {
                        BuddyMemoryBookView(store: store)
                    } label: {
                        Label("Memory book", systemImage: "book.closed")
                            .frame(maxWidth: .infinity, alignment: .leading).pawCard()
                    }
                    if pet.lifeStage != .egg {
                        NavigationLink {
                            BuddyPlayView(store: store)
                        } label: {
                            Label("Play together", systemImage: "heart.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                    if !pet.journey.residents.isEmpty { atHome }
                    if !pet.journey.memories.isEmpty { memories }
                    if pet.lifeStage != .egg {
                        Button { sharing = true } label: {
                            Label("Share a discovery", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let message = store.storageMessage {
                        Text(message).font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                    }
                }
                .padding(22)
            }
            .background(PawTheme.background)
            .navigationTitle("Adventures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PawTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $sharing) { CompanionShareView(pet: pet) }
        }
        .foregroundStyle(PawTheme.ink)
        .tint(PawTheme.adventureBlue)
    }

    private var weeklyAdventure: some View {
        let target = pet.journey.target(inWeekOf: .now)
        let days = pet.journey.activeDays(inWeekOf: .now)
        return VStack(alignment: .leading, spacing: 14) {
            Label("This week, together", systemImage: "leaf")
                .font(.headline)
            Text(days >= target ? "A little keepsake, earned together." : "Find five minutes for movement on \(target) days.")
                .font(.subheadline)
            ProgressView(value: Double(min(days, target)), total: Double(target)).tint(PawTheme.grassGreen)
            HStack {
                Text("\(min(days, target)) / \(target) days")
                Spacer()
                Label("\(pet.journey.weeklyKeepsakes) \(pet.journey.weeklyKeepsakes == 1 ? "keepsake" : "keepsakes")", systemImage: "seal")
            }
            .font(.caption.weight(.medium))
            Picker("Your weekly rhythm", selection: Binding(get: { pet.journey.weeklyTargetDays }, set: store.chooseWeeklyTarget)) {
                ForEach(2...5, id: \.self) { Text("\($0) days").tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Choose a rhythm for the next week. If this week hasn’t started, it applies now. Weeks begin on Monday; rest days never erase your growth, adventures, or keepsakes.")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }
        .pawCard()
    }

    private var nextEgg: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Another little beginning", systemImage: "oval.portrait")
                .font(.headline)
            if !pet.journey.waitingEggs.isEmpty {
                Text("A mystery egg found its way home.")
                Button("Welcome the egg") { store.beginNextEgg() }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(PawTheme.buttonForeground)
                    .disabled(pet.hasYoungCompanion || !canChangeCompanion)
                if pet.hasYoungCompanion {
                    Text("Help your little one grow up first. Your new egg is safe here.")
                        .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                }
            } else {
                ProgressView(value: pet.journey.eggProgressSeconds, total: CompanionJourney.eggSeconds)
                Text("\(Int(pet.journey.eggProgressSeconds / 60)) / 180 minutes exploring with grown friends")
                    .font(.subheadline)
                Text("Once grown, your companion helps you find new eggs through movement. Everyone you meet keeps a place at home. Who’s inside stays a secret until hatching.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
            if !canChangeCompanion {
                Text("Finish your current workout before changing companions.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
        }
        .pawCard()
    }

    private var expedition: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Beyond the garden", systemImage: "map")
                .font(.headline)
            if let trail = pet.journey.activeTrail {
                Text(trail.title).font(.title3.weight(.semibold))
                ProgressView(value: pet.journey.trailSeconds, total: trail.seconds)
                Text("\(Int(pet.journey.trailSeconds / 60)) / \(Int(trail.seconds / 60)) minutes")
                    .font(.subheadline)
                Text(pet.lifeStage == .adult ? "Every credited minute with a grown friend brings you closer. There’s no deadline." : "Your expedition will wait. Visit a grown friend to continue, or let your little one grow first.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                if let expedition = pet.journey.expedition {
                    if let branch = expedition.branch {
                        Label(branch.title, systemImage: "arrow.triangle.branch").font(.subheadline)
                    } else if pet.journey.trailSeconds >= trail.seconds / 2 {
                        Text("Two paths, one little adventure").font(.headline)
                        Text("Which way shall we go? Your movement keeps counting while you decide.")
                            .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                        ForEach(AdventureBranch.allCases.filter { $0.trail == trail }) { branch in
                            Button { store.chooseBranch(branch, expeditionID: expedition.id) } label: {
                                Text(branch.title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                            }.buttonStyle(.bordered).disabled(pet.lifeStage != .adult)
                        }
                    } else {
                        Text("A choice awaits halfway along the path. What you bring home is a surprise.")
                            .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                    }
                }
            } else {
                Text(pet.lifeStage == .adult ? "Choose somewhere to wander together." : "New paths open when your companion grows up.")
                    .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                ForEach(AdventureTrail.allCases) { trail in
                    Button { store.chooseTrail(trail) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: trail.symbol).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trail.title).font(.subheadline.weight(.semibold))
                                Text("\(Int(trail.seconds / 60)) minutes · a memory and a decoration")
                                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                        }
                        .frame(minHeight: 48)
                    }
                    .disabled(pet.lifeStage != .adult)
                }
            }
        }
        .pawCard()
    }

    private var atHome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("At home", systemImage: "house")
                .font(.headline)
            Text("Only the friends you’ve already welcomed live here.")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            ForEach(pet.journey.residents) { resident in
                Button { store.visitCompanion(resident.id) } label: {
                    HStack(spacing: 14) {
                        AnimalPortraitView(species: resident.species, lifeStage: resident.stage,
                                           variant: resident.lifecycle?.variant ?? .classic)
                            .frame(width: 58, height: 66)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(resident.stage == .egg ? "Your mystery egg" : resident.name)
                                .font(.headline)
                            Text(resident.stage == .egg ? "Waiting for a little warmth" : "\(resident.stage.displayName) · \(resident.species.displayName)")
                                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                        }
                        Spacer()
                        Text("Visit").font(.subheadline.weight(.semibold))
                    }
                }
                .disabled(!canChangeCompanion)
            }
        }
        .pawCard()
    }

    private var memories: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Things we found together", systemImage: "book.closed")
                .font(.headline)
            ForEach(pet.journey.memories.reversed()) { memory in
                VStack(alignment: .leading, spacing: 7) {
                    Text(memory.trail.title).font(.subheadline.weight(.semibold))
                    Text(memory.story).font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                    Text("With \(memory.companionName) · \(memory.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                    NavigationLink("Place \(memory.decoration)") { HabitatArrangeView(store: store) }
                        .font(.subheadline).frame(minHeight: 44)
                }
            }
        }
        .pawCard()
    }
}

struct CompanionTricksView: View {
    let pet: PetSnapshot
    @State private var motion: PetMotion = .idle
    @State private var interaction = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AnimalCompanionView(species: pet.species, motion: motion, interaction: interaction,
                                    lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic)
                    .frame(height: 290)
                    .background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 28))
                Text("A friendship that keeps growing")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("\(Int(pet.companionAdultSeconds / 60)) minutes of grown-up adventures together")
                    .foregroundStyle(PawTheme.inkSecondary)
                trick("Happy hop", detail: "A joyful greeting after 60 minutes of adventures.", motion: .jumping, minutes: 60)
                trick("Victory dance", detail: "Your own little celebration after 180 minutes together.", motion: .celebrating, minutes: 180)
                if pet.companionAdultSeconds >= 3_600 {
                    Label(pet.companionAdultSeconds >= 10_800 ? "Trusted friend" : "Trail partner", systemImage: "heart.fill")
                        .foregroundStyle(PawTheme.coralOrange)
                }
                Text("Your companion’s appearance is settled, but there are still new memories to make. Rest never takes these milestones away.")
                    .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
            }
            .padding(22)
        }
        .background(PawTheme.background)
        .navigationTitle(pet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PawTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .foregroundStyle(PawTheme.ink)
        .tint(PawTheme.adventureBlue)
        .task(id: interaction) {
            guard interaction > 0 else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            motion = .idle
        }
    }

    private func trick(_ title: String, detail: String, motion: PetMotion, minutes: Int) -> some View {
        Button {
            self.motion = motion
            interaction += 1
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: pet.companionAdultSeconds >= Double(minutes * 60) ? "play.circle" : "lock")
                    .font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(PawTheme.inkSecondary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pawCard()
        }
        .disabled(pet.lifeStage != .adult || pet.companionAdultSeconds < Double(minutes * 60))
    }
}
