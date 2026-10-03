import SwiftUI

enum PetMotion: Sendable {
    case idle
    case walking
    case running
    case jumping
    case playing
    case feeding
    case celebrating
    case special
}

struct MochiCreatureView: View {
    let mood: PetMood
    let stage: EvolutionStage
    var accessory: String? = nil
    var decoration: String? = nil
    var motion: PetMotion = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: motion == .running ? 1.0 / 15.0 : 1.0 / 4.0,
                paused: reduceMotion
            )
        ) { timeline in
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let speed = motion == .running ? 10.0 : 3.0
                let phase = reduceMotion ? 0 : sin(timeline.date.timeIntervalSinceReferenceDate * speed)
                let bounce = verticalBounce(size: size, phase: phase)

                ZStack {
                    PetHabitatDecoration(
                        name: decoration ?? "Flower Meadow",
                        size: size,
                        phase: phase
                    )

                    if motion == .running {
                        PetSpeedLines(size: size, phase: phase)
                    }

                    Ellipse()
                        .fill(PawTheme.ink.opacity(0.14))
                        .frame(
                            width: size * (motion == .running ? 0.66 : 0.58),
                            height: size * 0.12
                        )
                        .scaleEffect(x: 1 - abs(bounce / max(size, 1)) * 2.2)
                        .offset(y: size * 0.37)
                        .blur(radius: size * 0.018)

                    creature(size: size, phase: phase)
                        .offset(x: motion == .running ? size * 0.025 : 0, y: bounce)
                        .rotationEffect(.degrees(motion == .running ? phase * 2.8 : phase * 0.8))
                        .rotation3DEffect(
                            .degrees(motion == .running ? phase * 3.5 : phase * 1.2),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.32
                        )
                }
                .frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func verticalBounce(size: CGFloat, phase: Double) -> CGFloat {
        switch motion {
        case .idle: CGFloat(phase) * size * 0.008
        case .walking: -abs(CGFloat(phase)) * size * 0.018
        case .running: -abs(CGFloat(phase)) * size * 0.045
        case .jumping, .playing, .feeding, .celebrating, .special: -abs(CGFloat(phase)) * size * 0.035
        }
    }

    private var accessibilityDescription: String {
        let action = switch motion {
        case .idle: "resting"
        case .walking: "walking"
        case .running: "running"
        case .jumping: "jumping"
        case .playing: "playing"
        case .feeding: "having a snack"
        case .celebrating: "celebrating"
        case .special: "showing a special move"
        }
        return "\(stage.displayName) \(mood.label.lowercased()) companion \(action) in \(decoration ?? "Flower Meadow")"
    }

    private func creature(size: CGFloat, phase: Double) -> some View {
        let stride = motion == .running ? phase : 0
        let coralLight = PawTheme.coralOrange.opacity(0.82)
        let coralShadow = Color(hex: 0xE95049)

        return ZStack {
            LeafTailShape()
                .fill(
                    LinearGradient(
                        colors: [PawTheme.grassGreen, PawTheme.teal, Color(hex: 0x178B8C)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    LeafTailShape()
                        .stroke(Color.white.opacity(0.2), lineWidth: max(1, size * 0.008))
                        .padding(size * 0.025)
                }
                .frame(width: size * 0.42, height: size * 0.28)
                .rotationEffect(.degrees((stage == .volaki ? -18 : 10) + stride * 16))
                .offset(x: size * 0.28, y: size * 0.12)
                .shadow(color: PawTheme.teal.opacity(0.25), radius: size * 0.025, y: size * 0.018)

            petLeg(size: size, isLeft: true, stride: stride, color: coralShadow)
            petLeg(size: size, isLeft: false, stride: stride, color: coralLight)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [coralLight, PawTheme.coralOrange, coralShadow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.47, height: size * 0.48)
                .offset(y: size * 0.16)
                .shadow(color: coralShadow.opacity(0.28), radius: size * 0.035, y: size * 0.025)

            petArm(size: size, isLeft: true, stride: stride, color: coralLight)
            petArm(size: size, isLeft: false, stride: stride, color: coralShadow)

            PetEarShape(flipped: false)
                .fill(
                    LinearGradient(
                        colors: [PawTheme.teal, Color(hex: 0x168B91)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.3, height: size * 0.32)
                .rotationEffect(.degrees(stride * 4), anchor: .bottomTrailing)
                .offset(x: -size * 0.19, y: -size * 0.2)

            PetEarShape(flipped: true)
                .fill(
                    LinearGradient(
                        colors: [PawTheme.teal, Color(hex: 0x168B91)],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .frame(width: size * 0.3, height: size * 0.32)
                .rotationEffect(.degrees(-stride * 4), anchor: .bottomLeading)
                .offset(x: size * 0.19, y: -size * 0.2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [coralLight, PawTheme.coralOrange, coralShadow],
                        center: UnitPoint(x: 0.36, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.43
                    )
                )
                .frame(width: size * 0.64, height: size * 0.64)
                .offset(y: -size * 0.03)
                .shadow(color: coralShadow.opacity(0.24), radius: size * 0.035, y: size * 0.025)

            Ellipse()
                .fill(Color.white.opacity(0.2))
                .frame(width: size * 0.18, height: size * 0.3)
                .rotationEffect(.degrees(28))
                .offset(x: -size * 0.15, y: -size * 0.13)
                .blur(radius: size * 0.012)

            PetForeheadMark(stage: stage)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), PawTheme.energyYellow],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.19, height: size * 0.2)
                .offset(y: -size * 0.24)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.white, PawTheme.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.34, height: size * 0.25)
                .offset(y: size * 0.08)
                .shadow(color: PawTheme.ink.opacity(0.08), radius: size * 0.012, y: size * 0.008)

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
                .stroke(
                    PawTheme.ink,
                    style: StrokeStyle(lineWidth: max(2, size * 0.018), lineCap: .round)
                )
                .frame(width: size * 0.18, height: size * 0.12)
                .offset(y: size * 0.11)

            HStack(spacing: size * 0.29) {
                Ellipse().fill(Color.pink.opacity(0.55))
                Ellipse().fill(Color.pink.opacity(0.55))
            }
            .frame(width: size * 0.48, height: size * 0.06)
            .offset(y: size * 0.08)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x5D86F5), PawTheme.adventureBlue, Color(hex: 0x214BB0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.48, height: size * 0.065)
                .offset(y: size * 0.19)

            FriendshipGem()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.5), PawTheme.energyYellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(y: size * 0.22)
                .shadow(color: PawTheme.energyYellow.opacity(0.4), radius: size * 0.02)

            PetAccessoryLayer(name: accessory, size: size)

            if stage != .sprout {
                Image(systemName: stage == .volaki ? "sparkles" : "leaf.fill")
                    .font(.system(size: size * 0.1, weight: .bold))
                    .foregroundStyle(stage == .volaki ? PawTheme.energyYellow : PawTheme.grassGreen)
                    .offset(x: -size * 0.34, y: -size * 0.25)
                    .shadow(color: Color.white.opacity(0.45), radius: size * 0.015)
            }
        }
    }

    private func petLeg(
        size: CGFloat,
        isLeft: Bool,
        stride: Double,
        color: Color
    ) -> some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: size * 0.15, height: size * 0.22)
            .rotationEffect(
                .degrees((isLeft ? stride : -stride) * 20),
                anchor: .top
            )
            .offset(
                x: (isLeft ? -1 : 1) * size * 0.11,
                y: size * 0.32 + CGFloat(isLeft ? stride : -stride) * size * 0.018
            )
    }

    private func petArm(
        size: CGFloat,
        isLeft: Bool,
        stride: Double,
        color: Color
    ) -> some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: size * 0.11, height: size * 0.25)
            .rotationEffect(
                .degrees((isLeft ? -1 : 1) * (18 + stride * 18)),
                anchor: .top
            )
            .offset(x: (isLeft ? -1 : 1) * size * 0.22, y: size * 0.15)
    }
}

private struct PetSpeedLines: View {
    let size: CGFloat
    let phase: Double

    var body: some View {
        VStack(alignment: .trailing, spacing: size * 0.055) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(PawTheme.adventureBlue.opacity(0.2 + Double(index) * 0.1))
                    .frame(
                        width: size * (0.22 + CGFloat(index) * 0.06),
                        height: max(2, size * 0.018)
                    )
                    .offset(x: CGFloat(phase) * size * 0.025)
            }
        }
        .offset(x: -size * 0.29, y: size * 0.04)
    }
}

private struct PetHabitatDecoration: View {
    let name: String
    let size: CGFloat
    let phase: Double

    var body: some View {
        ZStack {
            if name == "Flower Meadow" {
                PetFlower(size: size * 0.1, tint: .pink)
                    .offset(x: -size * 0.34, y: size * 0.3)
                PetFlower(size: size * 0.075, tint: PawTheme.energyYellow)
                    .offset(x: size * 0.35, y: size * 0.32)
                PetFlower(size: size * 0.055, tint: PawTheme.adventureBlue)
                    .offset(x: -size * 0.23, y: size * 0.37)
            } else if name == "Trail Flags" {
                TrailFlag(tint: PawTheme.coralOrange)
                    .frame(width: size * 0.17, height: size * 0.35)
                    .offset(x: -size * 0.37, y: size * 0.18)
                TrailFlag(tint: PawTheme.adventureBlue, flipped: true)
                    .frame(width: size * 0.14, height: size * 0.3)
                    .offset(x: size * 0.39, y: size * 0.23)
            } else if name == "Star Lanterns" {
                HStack(spacing: size * 0.18) {
                    Image(systemName: "star.fill")
                    Image(systemName: "sparkles")
                    Image(systemName: "star.fill")
                }
                .font(.system(size: size * 0.075, weight: .bold))
                .foregroundStyle(PawTheme.energyYellow)
                .shadow(color: PawTheme.energyYellow.opacity(0.7), radius: size * 0.025)
                .offset(y: -size * 0.39 + CGFloat(phase) * size * 0.008)
            } else if name == "Camp Glow" {
                Circle()
                    .fill(PawTheme.energyYellow.opacity(0.22))
                    .frame(width: size * 0.28, height: size * 0.28)
                    .blur(radius: size * 0.035)
                    .offset(x: -size * 0.34, y: size * 0.25)
                Image(systemName: "tent.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(PawTheme.adventureBlue)
                    .offset(x: -size * 0.35, y: size * 0.29)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: size * 0.11, weight: .bold))
                    .foregroundStyle(PawTheme.energyYellow)
                    .offset(x: size * 0.34, y: -size * 0.31)
            }
        }
    }
}

private struct PetFlower: View {
    let size: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: size * 0.38, height: size * 0.72)
                    .offset(y: -size * 0.28)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
            Circle()
                .fill(PawTheme.energyYellow)
                .frame(width: size * 0.28, height: size * 0.28)
        }
        .frame(width: size, height: size)
    }
}

private struct TrailFlag: View {
    let tint: Color
    var flipped = false

    var body: some View {
        ZStack(alignment: flipped ? .topTrailing : .topLeading) {
            Capsule()
                .fill(PawTheme.inkSecondary.opacity(0.7))
                .frame(width: 2)
            Image(systemName: "flag.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .frame(width: 18, height: 14)
                .scaleEffect(x: flipped ? -1 : 1)
        }
    }
}

private struct PetAccessoryLayer: View {
    let name: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            if name == "Trail Scarf" {
                ScarfShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x5D86F5), PawTheme.adventureBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.32, height: size * 0.18)
                    .offset(x: size * 0.18, y: size * 0.25)
                    .shadow(color: PawTheme.adventureBlue.opacity(0.25), radius: size * 0.018)
            } else if name == "Runner Cap" {
                Capsule(style: .continuous)
                    .fill(PawTheme.adventureBlue)
                    .frame(width: size * 0.39, height: size * 0.16)
                    .rotationEffect(.degrees(-5))
                    .offset(y: -size * 0.29)
                Capsule()
                    .fill(Color(hex: 0x214BB0))
                    .frame(width: size * 0.2, height: size * 0.045)
                    .offset(x: size * 0.18, y: -size * 0.24)
            } else if name == "Sun Chasers" {
                HStack(spacing: size * 0.035) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
                            .fill(PawTheme.ink.opacity(0.9))
                            .overlay {
                                LinearGradient(
                                    colors: [Color.white.opacity(0.38), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }
                    }
                }
                .frame(width: size * 0.38, height: size * 0.12)
                .offset(y: -size * 0.035)
            } else if name == "Sakura Charm" {
                Image(systemName: "camera.macro")
                    .font(.system(size: size * 0.12, weight: .bold))
                    .foregroundStyle(.pink)
                    .offset(x: size * 0.2, y: size * 0.2)
                    .shadow(color: Color.pink.opacity(0.35), radius: size * 0.018)
            }
        }
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
