import SwiftUI

/// Keeps the selected habitat and equipment visible around the 3D companion.
struct CompanionHabitatView: View {
    let pet: PetSnapshot
    var motion: PetMotion = .idle
    var interaction: Int = 0
    var showsEquipment = true
    var isResting = false
    var cameraReset = 0
    var cameraZoom: Binding<Double>? = nil
    var immersive = true
    var onPlay: (() -> Void)?
    var onFeed: (() -> Void)?
    var onPet: (() -> Void)?
    var onRoam: (() -> Void)?

    var body: some View {
        ZStack {
            AnimalCompanionView(
                species: pet.species,
                motion: motion,
                interaction: interaction,
                showsObjects: true,
                roams: true,
                isResting: isResting,
                decoration: pet.activeDecoration,
                cameraReset: cameraReset,
                cameraZoom: cameraZoom,
                immersive: immersive,
                lifeStage: pet.lifeStage,
                variant: pet.lifecycle?.variant ?? .classic,
                companionSeed: BuddyBond.seed(for: pet.companionID),
                temperament: pet.lifeStage == .egg ? nil : pet.temperament,
                placements: pet.habitatPlacements,
                onPlay: pet.lifeStage == .egg ? nil : onPlay,
                onFeed: pet.lifeStage == .egg ? nil : onFeed,
                onPet: pet.lifeStage == .egg ? nil : onPet,
                onRoam: pet.lifeStage == .egg ? nil : onRoam
            )
        }
        .overlay(alignment: .topLeading) {
            if showsEquipment, let accessory = pet.equippedAccessory {
                Label(accessory, systemImage: accessorySymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PawTheme.adventureBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PawTheme.surface.opacity(0.9), in: Capsule())
                    .padding(.top, 6)
                    .accessibilityLabel("Equipped: \(accessory)")
                    .allowsHitTesting(false)
            }
        }
    }

    private var accessorySymbol: String {
        switch pet.equippedAccessory {
        case "Runner Cap": "baseball.cap.fill"
        case "Sun Chasers": "sunglasses.fill"
        case "Sakura Charm": "camera.macro"
        default: "wind"
        }
    }
}
