import SwiftUI

/// A lightweight portrait of the selected companion for system surfaces.
struct AnimalPortraitView: View {
    let species: PetSpecies
    var lifeStage: PetLifeStage = .adult
    var variant: PetColorVariant = .classic

    init(species: PetSpecies, lifeStage: PetLifeStage = .adult, variant: PetColorVariant = .classic) {
        self.species = species
        self.lifeStage = lifeStage
        self.variant = variant
    }

    init(pet: PetSnapshot) {
        self.init(species: pet.species, lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic)
    }

    var body: some View {
        Group {
            if lifeStage == .egg {
                PetEggPortrait()
            } else {
                Image("pet-\(species.rawValue)")
                    .resizable()
                    .scaledToFit()
                    .saturation(variant == .classic ? 1 : 0)
                    .colorMultiply(phenotypeColor)
                    .scaleEffect(lifeStage == .baby ? 0.76 : 1, anchor: .bottom)
                    .overlay {
                        if variant.isRare {
                            GeometryReader { geometry in
                                Image(systemName: "sparkles")
                                    .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.20))
                                    .foregroundStyle(variant == .moonlight ? Color(red: 0.70, green: 0.79, blue: 0.97) : Color(red: 0.68, green: 0.79, blue: 0.64))
                                    .position(x: geometry.size.width * 0.81, y: geometry.size.height * 0.21)
                            }
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lifeStage == .egg
            ? "Mystery egg, growing with your workouts"
            : "\(species.rarity.displayName) \(lifeStage.displayName) \(variant == .classic ? "" : variant.displayName + " coat ")\(species.displayName) companion")
    }

    private var phenotypeColor: Color {
        switch variant {
        case .classic: return .white
        case .mint: return Color(red: 0.61, green: 0.94, blue: 0.78)
        case .peach: return Color(red: 1, green: 0.70, blue: 0.61)
        case .lavender: return Color(red: 0.79, green: 0.66, blue: 1)
        case .sky: return Color(red: 0.63, green: 0.83, blue: 1)
        case .moonlight: return Color(red: 0.81, green: 0.89, blue: 1)
        case .aurora: return Color(red: 0.78, green: 0.95, blue: 0.83)
        }
    }
}

/// Vector artwork stays crisp on the Watch, widgets, and Live Activities and
/// never falls back to the still-secret animal's portrait before hatching.
private struct PetEggPortrait: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Ellipse()
                    .fill(Color(red: 0.78, green: 0.87, blue: 0.65))
                    .frame(width: side * 0.84, height: side * 0.19)
                    .offset(y: side * 0.34)
                Ellipse()
                    .stroke(Color(red: 0.79, green: 0.70, blue: 0.47), lineWidth: side * 0.04)
                    .frame(width: side * 0.64, height: side * 0.13)
                    .offset(y: side * 0.33)
                PetEggShell()
                    .fill(LinearGradient(
                        colors: [Color(red: 1, green: 0.98, blue: 0.89), Color(red: 0.96, green: 0.88, blue: 0.71)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay {
                        GeometryReader { egg in
                            Circle()
                                .fill(Color(red: 0.77, green: 0.71, blue: 0.93))
                                .frame(width: egg.size.width * 0.21)
                                .position(x: egg.size.width * 0.28, y: egg.size.height * 0.41)
                            Ellipse()
                                .fill(Color(red: 0.65, green: 0.83, blue: 0.74))
                                .frame(width: egg.size.width * 0.26, height: egg.size.height * 0.17)
                                .rotationEffect(.degrees(-25))
                                .position(x: egg.size.width * 0.70, y: egg.size.height * 0.65)
                            Circle()
                                .fill(Color(red: 0.96, green: 0.73, blue: 0.69))
                                .frame(width: egg.size.width * 0.17)
                                .position(x: egg.size.width * 0.36, y: egg.size.height * 0.79)
                            Circle()
                                .fill(Color.white.opacity(0.62))
                                .frame(width: egg.size.width * 0.12)
                                .position(x: egg.size.width * 0.39, y: egg.size.height * 0.23)
                        }
                        .clipShape(PetEggShell())
                    }
                    .overlay(PetEggShell().stroke(Color(red: 0.84, green: 0.76, blue: 0.60).opacity(0.45), lineWidth: max(0.6, side * 0.007)))
                    .frame(width: side * 0.61, height: side * 0.80)
                    .offset(y: -side * 0.015)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PetEggShell: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.width * 0.91 + rect.minX, y: rect.height * 0.01 + rect.minY),
            control2: CGPoint(x: rect.width * 1.31 + rect.minX, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.width * -0.31 + rect.minX, y: rect.maxY),
            control2: CGPoint(x: rect.width * 0.09 + rect.minX, y: rect.height * 0.01 + rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
