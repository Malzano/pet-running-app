import SwiftUI

struct PetGrowthCard: View {
    let pet: PetSnapshot
    var showsGenes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(PetLifeStage.allCases, id: \.self) { stage in
                    HStack(spacing: 5) {
                        Image(systemName: stage == .egg ? "oval.portrait.fill" : stage == .baby ? "leaf.fill" : "pawprint.fill")
                        Text(stage.displayName)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pet.lifeStage == stage ? PawTheme.adventureBlue : PawTheme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(pet.lifeStage == stage ? PawTheme.surfaceRaised : .clear, in: Capsule())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Life stage: \(pet.lifeStage.displayName)")

            if let lifecycle = pet.lifecycle, pet.lifeStage != .adult {
                HStack(alignment: .firstTextBaseline) {
                    Text(pet.lifeStage == .egg ? "A little closer to hello" : "Growing into their own")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text("\(Int(ceil(lifecycle.secondsUntilNextStage / 60))) min left")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(PawTheme.adventureBlue)
                }
                ProgressView(value: lifecycle.growthProgress)
                    .tint(PawTheme.adventureBlue)
                    .accessibilityLabel(pet.lifeStage == .egg ? "Progress toward hatching" : "Progress toward adulthood")
                Text(pet.lifeStage == .egg
                     ? "Workouts and optional everyday activity warm your egg. Your new friend hatches after \(Int(PetLifecycle.hatchSeconds / 60)) progress minutes."
                     : "\(Int(PetLifecycle.babyGrowthSeconds / 60)) more progress minutes after hatching. Your mix of workouts shapes their adult traits and coat.")
                    .font(.caption)
                    .foregroundStyle(PawTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Up to \(Int(PetLifecycle.dailyCreditLimitSeconds / 60)) minutes a day count toward growth. Rest days keep all your progress.")
                    .font(.caption2)
                    .foregroundStyle(PawTheme.inkSecondary)
            } else {
                Text("All grown up, always your little friend.")
                    .font(.subheadline.weight(.semibold))
                Text(pet.lifecycle == nil ? "Your existing companion and all earned progress are safe."
                     : "Their genes are settled. Keep moving together for XP, friendship, and adventures.")
                    .font(.caption)
                    .foregroundStyle(PawTheme.inkSecondary)
            }

            if showsGenes, let lifecycle = pet.lifecycle {
                Divider().overlay(PawTheme.line)
                Text(pet.lifeStage == .adult ? "Their genetic signature" : "Genes taking shape")
                    .font(.subheadline.weight(.semibold))
                ForEach(PetGeneticTrait.allCases, id: \.self) { trait in
                    HStack(spacing: 10) {
                        Image(systemName: trait.symbol)
                            .frame(width: 20)
                            .foregroundStyle(trait.gardenTint)
                        Text(trait.displayName)
                            .font(.caption.weight(.medium))
                            .frame(width: 76, alignment: .leading)
                        ProgressView(value: lifecycle.creditedSeconds > 0 ? lifecycle.geneSeconds(for: trait) / lifecycle.creditedSeconds : 0)
                            .tint(trait.gardenTint)
                        Text(geneDuration(lifecycle.geneSeconds(for: trait)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(PawTheme.inkSecondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(trait.displayName): \(Int(lifecycle.geneSeconds(for: trait))) credited seconds")
                }
                if pet.lifeStage != .egg {
                    Label(lifecycle.variant.displayName + (lifecycle.isRare ? " · rare coat" : " coat"),
                          systemImage: lifecycle.isRare ? "sparkles" : "paintpalette")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PawTheme.adventureBlue)
                }
            }

            if showsGenes, pet.lifeStage != .egg {
                Divider().overlay(PawTheme.line)
                Label("\(pet.species.rarity.displayName) species · \(pet.species.displayName)", systemImage: pet.species.rarity.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PawTheme.adventureBlue)
                if let name = pet.species.specialMoveName, let detail = pet.species.specialMoveDescription {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name).font(.subheadline.weight(.semibold))
                        Text(detail).font(.caption).foregroundStyle(PawTheme.inkSecondary)
                    }
                }
            }
        }
        .padding(18)
        .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func geneDuration(_ seconds: Double) -> String {
        if seconds > 0, seconds < 60 { return "<1m" }
        return "\(Int(seconds / 60))m"
    }
}

extension PetGeneticTrait {
    var gardenTint: Color {
        switch self {
        case .endurance: PawTheme.grassGreen
        case .power: PawTheme.coralOrange
        case .calm: Color(hex: 0x9A82B8)
        case .explorer: PawTheme.teal
        }
    }

    var workoutExamples: String {
        switch self {
        case .endurance: "Walk, run, cycle, swim, or roll → mint"
        case .power: "Strength, core, or combat workouts → peach"
        case .calm: "Yoga, flexibility, or recovery → lavender"
        case .explorer: "Hikes, dance, and playful sports → sky"
        }
    }
}
