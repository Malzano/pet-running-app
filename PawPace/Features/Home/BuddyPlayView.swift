import SwiftUI

struct BuddyPlayView: View {
    @ObservedObject var store: PetStore
    @State private var selectedGame: BuddyGame?
    private var pet: PetSnapshot { store.snapshot }

    var body: some View {
        ScrollView {
            if pet.lifeStage == .egg {
                ContentUnavailableView("A little surprise is waiting", systemImage: "sparkles",
                    description: Text("Games and personality appear after your egg hatches. Until then, a little movement brings you closer."))
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    AnimalCompanionView(species: pet.species,
                                        lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic)
                        .frame(height: 215)
                        .background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 28))
                    VStack(alignment: .leading, spacing: 10) {
                        Label("A \(pet.temperament.title.lowercased()) little soul", systemImage: pet.temperament.symbol)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(pet.temperament.detail).foregroundStyle(PawTheme.inkSecondary)
                        Label("Favorite game: \(pet.favoriteGame.title)", systemImage: pet.favoriteGame.symbol).font(.subheadline.weight(.medium))
                        Text("Little preferences grow through the time you spend together.").font(.caption).foregroundStyle(PawTheme.inkSecondary)
                    }.pawCard()
                    Text("Make a little memory").font(.title3.weight(.semibold))
                    ForEach(BuddyGame.allCases) { game in
                        Button { selectedGame = game } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: game.symbol).font(.title2).frame(width: 32)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(game.title).font(.headline)
                                    Text(game.detail).font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                                    if let count = pet.buddyBond.favoriteGameCounts[game.rawValue], count > 0 {
                                        Text("\(count) happy \(count == 1 ? "game" : "games") together").font(.caption).foregroundStyle(PawTheme.adventureBlue)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading).pawCard()
                        }.buttonStyle(.plain)
                    }
                    if let routine = pet.buddyBond.learnedRoutine {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Our little routine", systemImage: "heart.fill").font(.headline)
                            Text("The last sequence you learned together, ready to practice again.")
                                .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                            ForEach(Array(routine.enumerated()), id: \.offset) { index, trick in
                                Label("\(index + 1). \(trick.title)", systemImage: trick.symbol).font(.subheadline)
                            }
                            NavigationLink { BuddyRoutineView(pet: pet) } label: {
                                Label("Practice together", systemImage: "play.circle").frame(minHeight: 44)
                            }
                        }.pawCard()
                    }
                    if let move = pet.species.specialMoveName {
                        NavigationLink { BuddyRoutineView(pet: pet, signatureOnly: true) }
                            label: { Label(move, systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(.bordered)
                    }
                    if pet.lifeStage == .adult {
                        NavigationLink { CompanionTricksView(pet: pet) } label: {
                            Label("Adventure gestures", systemImage: "heart.circle").frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                    Text("No timer, no lost lives. Games build friendship; movement still shapes growth. Rare species stay a surprise.")
                        .font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                }.padding(20)
            }
        }
        .background(PawTheme.background)
        .foregroundStyle(PawTheme.ink)
        .navigationTitle(pet.lifeStage == .egg ? "Play together" : "Time with \(pet.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PawTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $selectedGame) { game in BuddyGameView(store: store, game: game) }
    }
}

struct BuddyRoutineView: View {
    let pet: PetSnapshot
    var signatureOnly = false
    @State private var motion: PetMotion = .idle
    @State private var interaction = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AnimalCompanionView(species: pet.species, motion: motion, interaction: interaction,
                                    lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic)
                    .frame(height: 230).background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 28))
                if signatureOnly, pet.lifeStage != .egg, let move = pet.species.specialMoveName {
                    Text("A little magic, just like you.").font(.title2.weight(.bold))
                    Button { motion = .special; interaction += 1 } label: {
                        Label(move, systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered)
                } else if pet.lifeStage != .egg, let routine = pet.buddyBond.learnedRoutine {
                    Text("Our little routine").font(.title2.weight(.bold))
                    Text("Tap each step and watch your friend practice with you.").foregroundStyle(PawTheme.inkSecondary)
                    ForEach(Array(routine.enumerated()), id: \.offset) { index, trick in
                        Button {
                            motion = trick == .hop ? .jumping : trick == .bow ? .playing : .celebrating
                            interaction += 1
                        } label: { Label("\(index + 1). \(trick.title)", systemImage: trick.symbol).frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.bordered)
                    }
                }
            }.padding(20)
        }
        .background(PawTheme.background).foregroundStyle(PawTheme.ink)
        .navigationTitle(pet.lifeStage == .egg ? "A little surprise" : pet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PawTheme.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .task(id: interaction) {
            guard interaction > 0 else { return }
            do { try await Task.sleep(for: .seconds(signatureOnly ? 4.5 : 2)) } catch { return }
            motion = .idle
        }
    }
}

struct BuddyGameView: View {
    @ObservedObject var store: PetStore
    @State private var session: BuddyPlaySession
    @State private var feedback = ""
    @State private var motion: PetMotion = .idle
    @State private var interaction = 0
    @State private var fetchPoint = CGPoint(x: 0.5, y: 0.84)
    @State private var companionPoint = CGPoint(x: 0.5, y: 0.84)
    @State private var fetchAnimation = 0
    @State private var isFetching = false
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var pet: PetSnapshot { store.snapshot }
    private var matchesCompanion: Bool { pet.companionID == session.companionID && pet.lifeStage != .egg }

    init(store: PetStore, game: BuddyGame, session: BuddyPlaySession? = nil) {
        self.store = store
        _session = State(initialValue: session ?? BuddyPlaySession(game: game, companionID: store.snapshot.companionID))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !matchesCompanion {
                        ContentUnavailableView("Your friend is elsewhere", systemImage: "house",
                                               description: Text("Close this game and choose the friend you’d like to play with."))
                    } else if session.phase == .finished {
                        finished
                    } else {
                        HStack {
                            Text("A LITTLE TIME TOGETHER").font(.caption.weight(.bold)).tracking(1)
                            Spacer()
                            Text("\(session.round) / 3").font(.headline.monospacedDigit())
                        }.foregroundStyle(PawTheme.adventureBlue)
                        Text(instruction).font(.system(.title2, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        switch session.game {
                        case .fetch: fetchBoard
                        case .hideAndSeek: hidingBoard
                        case .trickTrail: trickBoard
                        }
                        if !feedback.isEmpty {
                            Text(feedback).font(.headline).foregroundStyle(PawTheme.adventureBlue)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                        if session.phase == .celebrating {
                            primaryButton("One more little round", symbol: "arrow.right") {
                                session.continuePlaying(); feedback = ""
                            }.disabled(isFetching)
                        }
                        if session.phase == .memorizing {
                            primaryButton(session.game == .hideAndSeek ? "Ready to find you" : "Let’s practice", symbol: "play.fill") {
                                session.ready(); feedback = ""
                            }
                        } else if session.phase == .playing, session.game != .fetch {
                            Button("Show me again") { session.lookAgain(); feedback = "" }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        Text("Take all the time you need. You can leave and start a new game whenever you like.")
                            .font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                    }
                }.padding(20)
            }
            .background(PawTheme.background)
            .navigationTitle(session.game.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .toolbarBackground(PawTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .foregroundStyle(PawTheme.ink).tint(PawTheme.adventureBlue)
        .onChange(of: session.phase) { _, phase in
            if phase == .finished { saved = store.completeBuddyGame(session) }
        }
        .onAppear { if session.phase == .finished { saved = store.completeBuddyGame(session) } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { fetchAnimation += 1; resetFetch(); motion = .idle }
        }
        .task(id: interaction) {
            guard interaction > 0 else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            motion = .idle
        }
        .task(id: fetchAnimation) {
            guard isFetching, scenePhase == .active else { return }
            if reduceMotion { resetFetch(); return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            withAnimation(.easeInOut(duration: 0.5)) { companionPoint = fetchPoint }
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            withAnimation(.easeInOut(duration: 0.5)) { fetchPoint = CGPoint(x: 0.5, y: 0.84); companionPoint = fetchPoint }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            isFetching = false
        }
    }

    private var instruction: String {
        if session.phase == .celebrating { return "We did that together." }
        switch session.game {
        case .fetch: return "Tap inside the circle to throw."
        case .hideAndSeek: return session.phase == .memorizing ? "Remember where I’m hiding." : "Where did your friend go?"
        case .trickTrail: return session.phase == .memorizing ? "A little sequence to learn." : "Your turn. One trick at a time."
        }
    }

    private var fetchBoard: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 28).fill(PawTheme.habitatGradient)
                    Circle().fill(PawTheme.grassGreen.opacity(0.16))
                        .overlay(Circle().stroke(PawTheme.grassGreen, style: StrokeStyle(lineWidth: 2, dash: [5, 5])))
                        .frame(width: geometry.size.width * 0.32, height: geometry.size.height * 0.32)
                        .position(x: geometry.size.width * session.target.x, y: geometry.size.height * session.target.y)
                    Image(systemName: "leaf.fill").font(.title).foregroundStyle(PawTheme.grassGreen.opacity(0.4))
                        .position(x: geometry.size.width * 0.12, y: geometry.size.height * 0.65)
                    AnimalPortraitView(species: pet.species, lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic)
                        .frame(width: 76, height: 76)
                        .position(x: geometry.size.width * companionPoint.x, y: geometry.size.height * companionPoint.y)
                    Image(systemName: "tennisball.fill").font(.system(size: 26)).foregroundStyle(PawTheme.energyYellow)
                        .position(x: geometry.size.width * fetchPoint.x + 24, y: geometry.size.height * fetchPoint.y + 12)
                }
                .contentShape(RoundedRectangle(cornerRadius: 28))
                .gesture(SpatialTapGesture().onEnded { value in
                    throwBall(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height)
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Fetch field. Target circle in the \(session.target.x < 0.5 ? "left" : "right") side of the garden.")
                .accessibilityAction(named: "Throw to the target") { throwBall(x: session.target.x, y: session.target.y) }
            }.frame(height: 310)
            Button("Throw to the target", systemImage: "scope") { throwBall(x: session.target.x, y: session.target.y) }
                .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                .disabled(session.phase != .playing || isFetching)
        }
    }

    private var hidingBoard: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(0..<4, id: \.self) { spot in
                let revealed = spot == session.hidingSpot && session.phase != .playing
                Group {
                    if session.phase == .playing {
                        Button { respond(session.search(spot)) } label: { hidingPlace(spot, revealed: false) }
                            .buttonStyle(.plain).disabled(session.checkedSpots.contains(spot))
                    } else {
                        hidingPlace(spot, revealed: revealed)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Fern \(spot + 1), \(revealed ? "your friend is here" : session.checkedSpots.contains(spot) ? "already checked, empty" : "hiding place")")
            }
        }
    }

    private func hidingPlace(_ spot: Int, revealed: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Image(systemName: "leaf.fill").font(.system(size: 65)).foregroundStyle(PawTheme.grassGreen.opacity(0.65))
                if revealed {
                    AnimalPortraitView(species: pet.species, lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic)
                        .frame(width: 65, height: 75)
                } else if session.checkedSpots.contains(spot) {
                    Image(systemName: "wind").font(.title).foregroundStyle(PawTheme.surface)
                }
            }.frame(height: 100)
            Text("Fern \(spot + 1)").font(.headline)
            Text(revealed ? "Peekaboo!" : session.checkedSpots.contains(spot) ? "Just leaves" : " ")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
        }.frame(maxWidth: .infinity, minHeight: 150).pawCard(padding: 10)
    }

    private var trickBoard: some View {
        VStack(spacing: 20) {
            AnimalCompanionView(species: pet.species, motion: motion, interaction: interaction,
                                lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic)
                .frame(height: 210).background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 28))
            if session.phase == .memorizing || session.phase == .celebrating {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(session.sequence.enumerated()), id: \.offset) { index, trick in
                        Label("\(index + 1). \(trick.title)", systemImage: trick.symbol).font(.headline)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).pawCard()
            } else {
                Text("\(session.sequenceIndex) of 3 steps remembered").font(.subheadline)
                ForEach(BuddyTrick.allCases, id: \.self) { trick in
                    Button {
                        let result = session.perform(trick)
                        if result == .progress || result == .found {
                            motion = trick == .hop ? .jumping : trick == .bow ? .playing : .celebrating
                            interaction += 1
                        }
                        respond(result)
                    } label: { Label(trick.title, systemImage: trick.symbol).font(.headline).frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(.bordered).disabled(session.phase != .playing)
                }
            }
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 20) {
            AnimalCompanionView(species: pet.species, motion: .celebrating, interaction: 1,
                                lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic)
                .frame(height: 240).background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 28))
            Text("A happy little memory.").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Three rounds of \(session.game.title.lowercased()), together. \(pet.name) loved spending time with you.")
                .foregroundStyle(PawTheme.inkSecondary)
            Label(saved ? "Friendship saved" : "Your game is waiting to be saved", systemImage: saved ? "heart.fill" : "exclamationmark.circle")
                .font(.headline).foregroundStyle(PawTheme.adventureBlue)
            if !saved {
                Text(store.storageMessage ?? "Your companion changed while you were playing. Close the game and visit them again.")
                    .font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                primaryButton("Try saving again", symbol: "arrow.clockwise") { saved = store.completeBuddyGame(session) }
            }
            primaryButton("Back to our day", symbol: "house") { dismiss() }
            Text("Games build friendship. They don’t add workout minutes or change what’s inside an egg.")
                .font(.footnote).foregroundStyle(PawTheme.inkSecondary)
        }
    }

    private func primaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
        }.buttonStyle(.plain).foregroundStyle(PawTheme.buttonForeground)
            .background(PawTheme.adventureBlue, in: RoundedRectangle(cornerRadius: 20))
    }

    private func throwBall(x: Double, y: Double) {
        guard !isFetching, matchesCompanion else { return }
        let result = session.throwBall(x: x, y: y)
        guard result != .ignored else { return }
        respond(result)
        isFetching = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { fetchPoint = CGPoint(x: x, y: y) }
        fetchAnimation += 1
    }

    private func respond(_ result: BuddyPlaySession.Feedback) {
        switch result {
        case .ignored: break
        case .tryAgain: feedback = session.game == .fetch ? "A little closer to the circle. Try again!" : session.game == .hideAndSeek ? "Just a little breeze here. Try another fern." : "Let’s start the sequence again. No hurry."
        case .progress: feedback = "That’s it. What comes next?"
        case .found: feedback = session.game == .hideAndSeek ? "There you are!" : "A little victory, together."
        }
    }

    private func resetFetch() {
        isFetching = false; fetchPoint = CGPoint(x: 0.5, y: 0.84); companionPoint = fetchPoint
    }
}
