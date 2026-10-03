import SwiftUI

struct DailyQuestsView: View {
    @ObservedObject var store: PetStore
    var onWorkout: () -> Void = {}
    var onPlay: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var revealed: QuestGift?
    private var pet: PetSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        streakCard(at: context.date)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Little things for today").font(.title2.bold())
                            Text("One hello or five movement minutes keeps your streak glowing and earns a daily surprise.")
                                .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                            quest("Say a little hello", detail: pet.lifeStage == .egg ? "Keep your mystery egg company" : "Check in or care for your buddy",
                                  symbol: "hand.wave", done: pet.quests.checkIns[CompanionJourney.dayKey(context.date)] != nil,
                                  action: { store.checkIn() })
                            let seconds = pet.journey.days[CompanionJourney.dayKey(context.date)]?.creditedSeconds ?? 0
                            quest("Move for five minutes", detail: "\(min(5, Int(seconds / 60))) / 5 minutes · any pace",
                                  symbol: "figure.walk", done: seconds >= 300, action: onWorkout)
                            if pet.lifeStage != .egg {
                                quest("Make time for play", detail: "An optional little game together", symbol: "tennisball",
                                      done: pet.quests.playDays.contains(CompanionJourney.dayKey(context.date)), action: onPlay)
                            }
                        }
                        weeklyCard(at: context.date)
                        gifts
                        if let message = store.storageMessage { Text(message).font(.footnote).foregroundStyle(PawTheme.inkSecondary) }
                        Text("Daily gifts: 85% an unowned garden decoration, 15% a mystery egg. Weekly gifts: 65% decoration, 35% egg. When every decoration is yours, gifts contain eggs. Earned gifts wait for you; missing a day never takes away your buddy or belongings.")
                            .font(.footnote).foregroundStyle(PawTheme.inkSecondary)
                    }.padding(22)
                }
                .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, _ in store.refreshQuests() }
            }
            .background(PawTheme.background).foregroundStyle(PawTheme.ink)
            .navigationTitle("Daily adventures").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PawTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { store.refreshQuests() }
            .sheet(item: $revealed) { gift in reward(gift).presentationDetents([.medium]) }
        }.tint(PawTheme.adventureBlue)
    }

    private func streakCard(at date: Date) -> some View {
        let streak = pet.quests.currentStreak(journey: pet.journey, at: date)
        let days = pet.quests.qualifyingDays(journey: pet.journey, at: date)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill").font(.system(size: 40)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(streak) day\(streak == 1 ? "" : "s") together").font(.system(.title, design: .rounded, weight: .bold))
                    Text("Best streak · \(pet.quests.bestStreak(journey: pet.journey, at: date)) days").font(.caption).foregroundStyle(PawTheme.inkSecondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<7) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: offset, to: CompanionJourney.weekStart(date)) ?? date
                    let completed = days.contains(day)
                    VStack(spacing: 8) {
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption)
                        Image(systemName: completed ? "checkmark" : "circle")
                            .font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).frame(height: 30)
                            .foregroundStyle(completed ? PawTheme.buttonForeground : PawTheme.inkSecondary)
                            .background(completed ? PawTheme.adventureBlue : PawTheme.surfaceRaised, in: Circle())
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))): \(completed ? "complete" : "not completed")")
                }
            }
            Text(days.contains(Calendar.current.startOfDay(for: date)) ? "Today’s little moment is saved. See you tomorrow." : "Your buddy is happy you’re here.")
                .font(.subheadline)
            if let gift = pet.quests.gifts.last(where: { $0.openedAt == nil }) {
                Button { revealed = store.openQuestGift(gift.id) } label: {
                    Label("Your surprise is ready · Open", systemImage: "gift.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground)
            }
        }.pawCard()
    }

    @ViewBuilder
    private func quest(_ title: String, detail: String, symbol: String, done: Bool, action: @escaping () -> Void) -> some View {
        let row = HStack(spacing: 13) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol).font(.title2)
                .foregroundStyle(PawTheme.adventureBlue).frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(done ? "Done for today" : detail).font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
            Spacer(minLength: 0)
            if !done { Image(systemName: "chevron.right").font(.caption) }
        }.frame(minHeight: 52).pawCard()
        if done { row.accessibilityElement(children: .combine) }
        else { Button(action: action) { row }.buttonStyle(.plain) }
    }

    private func weeklyCard(at date: Date) -> some View {
        let count = pet.journey.activeDays(inWeekOf: date), target = pet.journey.target(inWeekOf: date)
        let streak = DailyQuests.streak(pet.quests.qualifyingWeeks(journey: pet.journey, at: date), endingAt: CompanionJourney.weekStart(date), step: 7)
        return VStack(alignment: .leading, spacing: 12) {
            Label("A week of little adventures", systemImage: "leaf.fill").font(.headline)
            Text("\(count) of \(target) movement days").font(.title3.bold())
            ProgressView(value: Double(min(count, target)), total: Double(target))
            Text("Five minutes makes a movement day. Finish your weekly goal for another surprise. Choose next week’s goal in Adventures.")
                .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            Label("\(streak) week\(streak == 1 ? "" : "s") in a row", systemImage: "sparkles").font(.subheadline.bold())
        }.pawCard()
    }

    private var gifts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A surprise for showing up").font(.title2.bold())
            let pending = pet.quests.gifts.filter { $0.openedAt == nil }
            if pending.isEmpty {
                Text("Your next surprise starts with a little hello. Opened gifts stay below.").font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
            }
            ForEach(pending.sorted { $0.earnedAt > $1.earnedAt }) { gift in
                Button { revealed = store.openQuestGift(gift.id) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "gift.fill").font(.title)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(gift.kind == .daily ? "Your daily surprise" : "Your weekly surprise").font(.headline)
                            Text(gift.earnedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                        }
                        Spacer(); Text("Open").font(.subheadline.bold())
                    }.padding(18).background(PawTheme.adventureBlue, in: RoundedRectangle(cornerRadius: 22))
                        .foregroundStyle(PawTheme.buttonForeground)
                }.buttonStyle(.plain)
            }
            ForEach(pet.quests.gifts.filter { $0.openedAt != nil }.sorted { $0.openedAt! > $1.openedAt! }.prefix(5)) { gift in
                Label(gift.title, systemImage: gift.decoration?.symbol ?? "oval.portrait.fill")
                    .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
            }
            NavigationLink { HabitatArrangeView(store: store) } label: {
                Label("Arrange your garden", systemImage: "leaf.circle").frame(minHeight: 44)
            }
        }
    }

    private func reward(_ gift: QuestGift) -> some View {
        VStack(spacing: 20) {
            Image(systemName: gift.decoration?.symbol ?? "oval.portrait.fill").font(.system(size: 58)).foregroundStyle(PawTheme.adventureBlue)
            Text(gift.title).font(.system(.title, design: .rounded, weight: .bold))
            Text(gift.isEgg ? "Someone new is waiting inside. Your egg is safe in Adventures until there’s room for a new little one." : "A little something for your buddy’s home. Find it in Arrange your garden.")
                .multilineTextAlignment(.center).foregroundStyle(PawTheme.inkSecondary)
            Button("Lovely!") { revealed = nil }.buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PawTheme.background).foregroundStyle(PawTheme.ink)
    }
}
