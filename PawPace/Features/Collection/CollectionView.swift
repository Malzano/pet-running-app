import SwiftUI

struct CollectionView: View {
    @ObservedObject var store: PetStore

    private let accessories = [
        AccessoryItem(name: "Trail Scarf", symbol: "wind", price: 0, unlockLevel: 1, tint: PawTheme.adventureBlue),
        AccessoryItem(name: "Runner Cap", symbol: "baseball.cap.fill", price: 180, unlockLevel: 7, tint: PawTheme.coralOrange),
        AccessoryItem(name: "Sun Chasers", symbol: "sunglasses.fill", price: 260, unlockLevel: 9, tint: PawTheme.energyYellow),
        AccessoryItem(name: "Sakura Charm", symbol: "camera.macro", price: 320, unlockLevel: 12, tint: Color.pink)
    ]

    private let decorations = [
        AccessoryItem(name: "Flower Meadow", symbol: "camera.macro", price: 0, unlockLevel: 1, tint: PawTheme.grassGreen),
        AccessoryItem(name: "Trail Flags", symbol: "flag.fill", price: 160, unlockLevel: 7, tint: PawTheme.coralOrange),
        AccessoryItem(name: "Star Lanterns", symbol: "sparkles", price: 280, unlockLevel: 12, tint: PawTheme.energyYellow),
        AccessoryItem(name: "Camp Glow", symbol: "tent.fill", price: 420, unlockLevel: 18, tint: PawTheme.adventureBlue)
    ]

    private let badges = [
        BadgeItem(name: "First Trail", symbol: "figure.run.circle.fill", color: PawTheme.grassGreen),
        BadgeItem(name: "5K Explorer", symbol: "map.fill", color: PawTheme.adventureBlue),
        BadgeItem(name: "Dawn Runner", symbol: "sunrise.fill", color: PawTheme.coralOrange),
        BadgeItem(name: "Friendship 50", symbol: "heart.circle.fill", color: Color.pink),
        BadgeItem(name: "Rain Scout", symbol: "cloud.rain.fill", color: PawTheme.teal),
        BadgeItem(name: "Night Trail", symbol: "moon.stars.fill", color: PawTheme.energyYellow)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                header
                creatureCard
                evolutionPath
                accessoriesSection
                decorationsSection
                badgesSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("CREATURE CODEX")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(PawTheme.inkSecondary)
                Text("Collection")
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
            }
            Spacer()
            Label(store.snapshot.coins.formatted(), systemImage: "circle.hexagongrid.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PawTheme.adventureBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(PawTheme.surface, in: Capsule())
        }
    }

    private var creatureCard: some View {
        HStack(spacing: 15) {
            MochiCreatureView(
                mood: .proud,
                stage: store.snapshot.stage,
                accessory: store.snapshot.equippedAccessory,
                decoration: store.snapshot.activeDecoration,
                motion: .celebrating
            )
                .frame(width: 132, height: 132)
                .padding(7)
                .background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(alignment: .leading, spacing: 7) {
                Text(store.snapshot.name)
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                Text("\(store.snapshot.stage.displayName) · Level \(store.snapshot.level)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PawTheme.adventureBlue)
                Label("\(store.snapshot.friendship)% friendship", systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.pink)
                Text("Leaf-tail trail companion. Curious, snack-motivated, and loyal to a fault.")
                    .font(.caption)
                    .foregroundStyle(PawTheme.inkSecondary)
            }
        }
        .pawCard(padding: 13)
    }

    private var evolutionPath: some View {
        VStack(spacing: 12) {
            SectionKicker(title: "Evolution path", trailing: "RUN TO EVOLVE")
            HStack(spacing: 6) {
                ForEach(EvolutionStage.allCases, id: \.rawValue) { stage in
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(stage.rawValue <= store.snapshot.stage.rawValue ? PawTheme.energyYellow.opacity(0.25) : PawTheme.line)
                            Image(systemName: stage == .sprout ? "leaf.fill" : stage == .kitsora ? "sparkles" : "flame.fill")
                                .foregroundStyle(stage.rawValue <= store.snapshot.stage.rawValue ? PawTheme.coralOrange : PawTheme.inkSecondary)
                        }
                        .frame(width: 52, height: 52)
                        Text(stage.displayName)
                            .font(.caption2.weight(.bold))
                        Text("LV \(stage.minimumLevel)")
                            .font(.caption2)
                            .foregroundStyle(PawTheme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    if stage != .volaki {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(PawTheme.inkSecondary)
                    }
                }
            }
        }
        .pawCard()
    }

    private var accessoriesSection: some View {
        VStack(spacing: 11) {
            SectionKicker(title: "Equipment", trailing: store.snapshot.equippedAccessory?.uppercased())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(accessories) { item in
                    AccessoryCard(
                        item: item,
                        isUnlocked: store.snapshot.level >= item.unlockLevel,
                        isEquipped: store.snapshot.equippedAccessory == item.name
                    ) {
                        if store.snapshot.level >= item.unlockLevel {
                            store.equip(item.name)
                        }
                    }
                }
            }
        }
    }

    private var decorationsSection: some View {
        VStack(spacing: 11) {
            SectionKicker(title: "Habitat decorations", trailing: store.snapshot.activeDecoration.uppercased())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(decorations) { item in
                    AccessoryCard(
                        item: item,
                        isUnlocked: store.snapshot.level >= item.unlockLevel,
                        isEquipped: store.snapshot.activeDecoration == item.name
                    ) {
                        if store.snapshot.level >= item.unlockLevel {
                            store.equipDecoration(item.name)
                        }
                    }
                }
            }
        }
    }

    private var badgesSection: some View {
        VStack(spacing: 11) {
            SectionKicker(title: "Trail badges", trailing: "4 / 6")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(Array(badges.enumerated()), id: \.offset) { index, badge in
                    VStack(spacing: 7) {
                        Image(systemName: badge.symbol)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(index < 4 ? badge.color : PawTheme.inkSecondary)
                            .frame(width: 54, height: 54)
                            .background((index < 4 ? badge.color : PawTheme.line).opacity(0.16), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        Text(badge.name)
                            .font(.caption2.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(index < 4 ? 1 : 0.48)
                }
            }
        }
        .pawCard()
    }
}

private struct AccessoryItem: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let price: Int
    let unlockLevel: Int
    let tint: Color
}

private struct BadgeItem: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let color: Color
}

private struct AccessoryCard: View {
    let item: AccessoryItem
    let isUnlocked: Bool
    let isEquipped: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(item.tint.opacity(0.15))
                        .frame(height: 86)
                        .overlay {
                            Image(systemName: isUnlocked ? item.symbol : "lock.fill")
                                .font(.system(size: 31, weight: .bold))
                                .foregroundStyle(isUnlocked ? item.tint : PawTheme.inkSecondary)
                        }
                    if isEquipped {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PawTheme.adventureBlue)
                            .padding(8)
                    }
                }
                Text(item.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PawTheme.ink)
                Text(isEquipped ? "Equipped" : isUnlocked ? "\(item.price) coins" : "Level \(item.unlockLevel)")
                    .font(.caption2)
                    .foregroundStyle(PawTheme.inkSecondary)
            }
            .padding(10)
            .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(isEquipped ? PawTheme.adventureBlue : PawTheme.line, lineWidth: isEquipped ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }
}
