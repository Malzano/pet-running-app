import SwiftUI

struct HabitatArrangeView: View {
    @ObservedObject var store: PetStore
    @State private var spot = HabitatSpot.left
    @State private var visiting: HabitatSpot?
    @State private var visit = 0
    @State private var reaction: String?

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AnimalCompanionView(species: store.snapshot.species, showsObjects: true, roams: true,
                    decoration: store.snapshot.activeDecoration, lifeStage: store.snapshot.lifeStage,
                    variant: store.snapshot.lifecycle?.variant ?? .classic,
                    companionSeed: BuddyBond.seed(for: store.snapshot.companionID), temperament: store.snapshot.temperament,
                    placements: store.snapshot.habitatPlacements, visitingSpot: visiting, decorationVisit: visit)
                    .frame(height: 310)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .id("garden-preview")
                Text("Make room for your memories")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("Choose a nook, then place a keepsake. Moving it keeps everything you’ve earned.")
                    .foregroundStyle(PawTheme.inkSecondary)
                Picker("Garden nook", selection: $spot) {
                    ForEach(HabitatSpot.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                if let placed = store.snapshot.habitatPlacements.first(where: { $0.spot == spot }) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(placed.decoration.rawValue, systemImage: placed.decoration.symbol).font(.headline)
                        Button("Visit this keepsake") {
                            proxy.scrollTo("garden-preview", anchor: .top)
                            visiting = spot; visit += 1; reaction = placed.decoration.reaction
                        }.buttonStyle(.borderedProminent).foregroundStyle(PawTheme.buttonForeground)
                            .disabled(store.snapshot.lifeStage == .egg)
                        Button("Put away") { store.placeDecoration(nil, at: spot); reaction = nil }
                            .frame(minHeight: 44)
                    }.frame(maxWidth: .infinity, alignment: .leading).pawCard()
                } else {
                    Label("\(spot.title) is ready for a keepsake", systemImage: "leaf")
                        .font(.subheadline).foregroundStyle(PawTheme.inkSecondary)
                }
                if let reaction { Text(reaction).font(.subheadline).accessibilityAddTraits(.updatesFrequently) }
                if store.snapshot.availableDecorations.isEmpty {
                    ContentUnavailableView("A little room to grow", systemImage: "leaf",
                        description: Text("Finish an expedition with a grown friend to bring your first keepsake home."))
                }
                ForEach(store.snapshot.availableDecorations) { item in
                    Button { store.placeDecoration(item, at: spot); reaction = nil } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.symbol).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.rawValue).font(.headline)
                                Text(store.snapshot.habitatPlacements.first(where: { $0.decoration == item })?.spot.title ?? "Ready to place")
                                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle")
                        }.frame(minHeight: 48).pawCard()
                    }.buttonStyle(.plain)
                    .accessibilityLabel("Place \(item.rawValue) in \(spot.title)")
                }
                if let message = store.storageMessage { Text(message).font(.footnote).foregroundStyle(PawTheme.inkSecondary) }
            }.padding(22)
        }
        .background(PawTheme.background).foregroundStyle(PawTheme.ink).tint(PawTheme.adventureBlue)
        .navigationTitle("Your garden").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PawTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
