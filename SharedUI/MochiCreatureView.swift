import SwiftUI

struct MochiCreatureView: View {
    let mood: PetMood
    let stage: EvolutionStage
    var accessory: String?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                Ellipse()
                    .fill(PawTheme.ink.opacity(0.12))
                    .frame(width: size * 0.58, height: size * 0.12)
                    .offset(y: size * 0.36)
                    .blur(radius: size * 0.015)

                LeafTailShape()
                    .fill(
                        LinearGradient(
                            colors: [PawTheme.grassGreen, PawTheme.teal],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
                    .frame(width: size * 0.42, height: size * 0.28)
                    .rotationEffect(.degrees(stage == .volaki ? -18 : 10))
                    .offset(x: size * 0.28, y: size * 0.12)

                Capsule(style: .continuous)
                    .fill(PawTheme.coralOrange)
                    .frame(width: size * 0.47, height: size * 0.48)
                    .offset(y: size * 0.16)

                HStack(spacing: size * 0.07) {
                    Capsule(style: .continuous)
                        .fill(PawTheme.coralOrange)
                        .frame(width: size * 0.15, height: size * 0.22)
                    Capsule(style: .continuous)
                        .fill(PawTheme.coralOrange)
                        .frame(width: size * 0.15, height: size * 0.22)
                }
                .offset(y: size * 0.32)

                PetEarShape(flipped: false)
                    .fill(PawTheme.teal)
                    .frame(width: size * 0.3, height: size * 0.32)
                    .offset(x: -size * 0.19, y: -size * 0.2)

                PetEarShape(flipped: true)
                    .fill(PawTheme.teal)
                    .frame(width: size * 0.3, height: size * 0.32)
                    .offset(x: size * 0.19, y: -size * 0.2)

                Circle()
                    .fill(PawTheme.coralOrange)
                    .frame(width: size * 0.64, height: size * 0.64)
                    .offset(y: -size * 0.03)

                PetForeheadMark(stage: stage)
                    .fill(PawTheme.energyYellow)
                    .frame(width: size * 0.19, height: size * 0.2)
                    .offset(y: -size * 0.24)

                Ellipse()
                    .fill(PawTheme.background)
                    .frame(width: size * 0.34, height: size * 0.25)
                    .offset(y: size * 0.08)

                HStack(spacing: size * 0.19) {
                    PetEye(mood: mood)
                    PetEye(mood: mood)
                }
                .offset(y: -size * 0.05)

                RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                    .fill(PawTheme.ink)
                    .frame(width: size * 0.08, height: size * 0.055)
                    .rotationEffect(.degrees(45))
                    .offset(y: size * 0.045)

                PetMouthShape(mood: mood)
                    .stroke(PawTheme.ink, style: StrokeStyle(lineWidth: max(2, size * 0.018), lineCap: .round))
                    .frame(width: size * 0.18, height: size * 0.12)
                    .offset(y: size * 0.11)

                HStack(spacing: size * 0.29) {
                    Ellipse().fill(Color.pink.opacity(0.55))
                    Ellipse().fill(Color.pink.opacity(0.55))
                }
                .frame(width: size * 0.48, height: size * 0.06)
                .offset(y: size * 0.08)

                Capsule(style: .continuous)
                    .fill(PawTheme.adventureBlue)
                    .frame(width: size * 0.48, height: size * 0.065)
                    .offset(y: size * 0.19)

                FriendshipGem()
                    .fill(PawTheme.energyYellow)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .offset(y: size * 0.22)

                if accessory == "Trail Scarf" {
                    ScarfShape()
                        .fill(PawTheme.adventureBlue)
                        .frame(width: size * 0.32, height: size * 0.18)
                        .offset(x: size * 0.18, y: size * 0.25)
                }

                if stage != .sprout {
                    Image(systemName: stage == .volaki ? "sparkles" : "leaf.fill")
                        .font(.system(size: size * 0.1, weight: .bold))
                        .foregroundStyle(stage == .volaki ? PawTheme.energyYellow : PawTheme.grassGreen)
                        .offset(x: -size * 0.34, y: -size * 0.25)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stage.displayName) \(mood.label.lowercased()) companion")
    }
}

private struct PetEye: View {
    let mood: PetMood

    var body: some View {
        Group {
            if mood == .sleepy || mood == .tired {
                Capsule()
                    .fill(PawTheme.ink)
                    .frame(width: 17, height: 4)
            } else {
                Circle()
                    .fill(PawTheme.ink)
                    .overlay(alignment: .topLeading) {
                        Circle().fill(.white).frame(width: 4, height: 4).padding(3)
                    }
            }
        }
        .frame(width: 17, height: 17)
    }
}

private struct PetEarShape: Shape {
    let flipped: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if flipped {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control1: CGPoint(x: rect.width * 0.45, y: rect.height * 0.75), control2: CGPoint(x: rect.width * 0.7, y: rect.height * 0.12))
            path.addLine(to: CGPoint(x: rect.maxX * 0.82, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY), control1: CGPoint(x: rect.width * 0.55, y: rect.height * 0.75), control2: CGPoint(x: rect.width * 0.3, y: rect.height * 0.12))
            path.addLine(to: CGPoint(x: rect.width * 0.18, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

private struct LeafTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control1: CGPoint(x: rect.width * 0.35, y: rect.minY), control2: CGPoint(x: rect.width * 0.8, y: rect.height * 0.02))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY), control1: CGPoint(x: rect.width * 0.95, y: rect.height * 0.8), control2: CGPoint(x: rect.width * 0.35, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PetForeheadMark: Shape {
    let stage: EvolutionStage

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control1: CGPoint(x: rect.maxX, y: rect.height * 0.1), control2: CGPoint(x: rect.maxX, y: rect.height * 0.35))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control1: CGPoint(x: rect.maxX, y: rect.height * 0.75), control2: CGPoint(x: rect.width * 0.7, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY), control1: CGPoint(x: rect.width * 0.3, y: rect.maxY), control2: CGPoint(x: rect.minX, y: rect.height * 0.72))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY), control1: CGPoint(x: rect.minX, y: rect.height * 0.28), control2: CGPoint(x: rect.width * 0.25, y: rect.height * 0.12))
        return path
    }
}

private struct PetMouthShape: Shape {
    let mood: PetMood

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch mood {
        case .happy, .excited, .proud, .curious:
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.25))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.25), control: CGPoint(x: rect.midX, y: rect.maxY))
        case .hungry:
            path.addEllipse(in: rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.12))
        case .tired, .sleepy:
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.65))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.65), control: CGPoint(x: rect.midX, y: rect.height * 0.3))
        }
        return path
    }
}

private struct FriendshipGem: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.42))
        path.closeSubpath()
        return path
    }
}

private struct ScarfShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.2), control1: CGPoint(x: rect.width * 0.35, y: rect.height * 0.3), control2: CGPoint(x: rect.width * 0.65, y: rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.72))
        path.closeSubpath()
        return path
    }
}

