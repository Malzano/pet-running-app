import SwiftUI

struct CompanionProgressView: View {
    @ObservedObject var store: PetStore
    @Environment(\.dismiss) private var dismiss

    private let habitats: [(name: String, symbol: String, level: Int)] = [
        ("Flower Meadow", "camera.macro", 1),
        ("Trail Flags", "flag", 7),
        ("Star Lanterns", "sparkles", 12),
        ("Camp Glow", "tent", 18)
    ]

    private var pet: PetSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    AnimalPortraitView(pet: pet)
                        .frame(width: 104, height: 118)
                    PetGrowthCard(pet: pet, showsGenes: true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A little movement, together").font(.headline)
                        ProgressView(value: min(Double(pet.currentDayMovementMinutes) / 30, 1))
                            .tint(PawTheme.adventureBlue)
                        Text("\(pet.currentDayMovementMinutes) / 30 progress minutes today")
                            .font(.subheadline)
                        Text("Your daily goal is a gentle invitation. Rest days keep all your growth.")
                            .font(.caption)
                            .foregroundStyle(PawTheme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pawCard()
                    habitatPicker
                }
                .padding(22)
            }
            .background(PawTheme.background)
            .navigationTitle(pet.lifeStage == .egg ? "A little beginning" : "\(pet.name)’s story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(PawTheme.adventureBlue)
        .foregroundStyle(PawTheme.ink)
    }

    private var habitatPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Make a little home").font(.headline)
            ForEach(habitats, id: \.name) { habitat in
                let unlocked = pet.level >= habitat.level || pet.journey.unlockedDecorations.contains(habitat.name)
                Button {
                    guard unlocked else { return }
                    store.equipDecoration(habitat.name)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: habitat.symbol)
                            .frame(width: 30)
                        Text(habitat.name).font(.subheadline.weight(.medium))
                        Spacer()
                        if !unlocked {
                            Text("Level \(habitat.level)").font(.caption)
                        } else if pet.activeDecoration == habitat.name {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .foregroundStyle(unlocked ? PawTheme.adventureBlue : PawTheme.inkSecondary)
                    .padding(16)
                    .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(!unlocked)
            }
        }
    }
}
