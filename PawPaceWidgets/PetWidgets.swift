import AppIntents
import SwiftUI
import WidgetKit

struct PetWidgetEntry: TimelineEntry {
    let date: Date
    let pet: PetSnapshot
}

struct PetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetWidgetEntry {
        PetWidgetEntry(date: .now, pet: .starter)
    }

    func getSnapshot(in context: Context, completion: @escaping (PetWidgetEntry) -> Void) {
        completion(PetWidgetEntry(date: .now, pet: PawPaceShared.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetWidgetEntry>) -> Void) {
        let entry = PetWidgetEntry(date: .now, pet: PawPaceShared.loadSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct PawPaceCompactWidget: Widget {
    let kind = "PawPaceCompactWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PetTimelineProvider()) { entry in
            CompactPetWidgetView(entry: entry)
                .containerBackground(for: .widget) { PawTheme.surface }
        }
        .configurationDisplayName("Your companion")
        .description("Keep your egg’s hatching progress or your growing companion close by.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct PawPaceHabitatWidget: Widget {
    let kind = "PawPaceHabitatWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PetTimelineProvider()) { entry in
            HabitatPetWidgetView(entry: entry)
                .containerBackground(for: .widget) { PawTheme.surface }
        }
        .configurationDisplayName("Your little world")
        .description("A full companion habitat with progression, actions, and today’s movement goal.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

private struct CompactPetWidgetView: View {
    let entry: PetWidgetEntry

    private var isEgg: Bool { entry.pet.lifeStage == .egg }

    private var minutesRemaining: Int {
        Int(ceil((entry.pet.lifecycle?.secondsUntilNextStage ?? 0) / 60))
    }

    var body: some View {
        ZStack {
            PawTheme.habitatGradient

            Circle()
                .fill(PawTheme.energyYellow.opacity(0.23))
                .frame(width: 115, height: 115)
                .offset(x: -55, y: -58)

            VStack(spacing: 0) {
                HStack {
                    Text("PAWPACE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(PawTheme.adventureBlue)
                    Spacer()
                    Label(isEgg ? "\(Int((entry.pet.lifecycle?.growthProgress ?? 0) * 100))%" : "\(entry.pet.friendship)", systemImage: isEgg ? "sparkles" : "heart.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.pink)
                }

                ZStack(alignment: .topTrailing) {
                    AnimalPortraitView(pet: entry.pet)
                        .frame(width: 94, height: 94)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Link(destination: URL(string: "pawpace://home")!) {
                        Text(compactMessage)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(PawTheme.ink)
                            .lineLimit(3)
                            .frame(width: 66, alignment: .leading)
                            .padding(7)
                            .background(PawTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Text(isEgg ? "\(minutesRemaining) min to hatch" : "\(entry.pet.energy)% energy")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(PawTheme.inkSecondary)
                    Spacer()
                    if isEgg {
                        Link(destination: URL(string: "pawpace://workout")!) {
                            compactAction(symbol: "figure.mixed.cardio")
                        }
                        .accessibilityLabel("Workout to hatch your egg")
                    } else {
                        Button(intent: FeedPetIntent()) {
                            compactAction(symbol: "carrot.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Feed \(entry.pet.name)")
                    }
                }
            }
            .padding(12)
        }
    }

    private var compactMessage: String {
        if isEgg { return "Who’s inside? Move together to find out." }
        if entry.pet.lifeStage == .baby { return "\(minutesRemaining) workout min until I’m all grown up!" }
        return switch entry.pet.mood {
        case .hungry: "Snack first, then adventure?"
        case .tired, .sleepy: "Tiny nap. Big quest later."
        default: "Ready for a little movement?"
        }
    }

    private func compactAction(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(PawTheme.ink)
            .frame(width: 27, height: 27)
            .background(PawTheme.energyYellow, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct HabitatPetWidgetView: View {
    let entry: PetWidgetEntry

    private var isEgg: Bool { entry.pet.lifeStage == .egg }
    private var isGrowing: Bool { entry.pet.lifeStage != .adult }
    private var companionName: String { isEgg ? "Mystery egg" : entry.pet.name }
    private var minutesRemaining: Int {
        Int(ceil((entry.pet.lifecycle?.secondsUntilNextStage ?? 0) / 60))
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("PAWPACE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(PawTheme.adventureBlue)
                Spacer()
                Text(isEgg ? "Mystery egg" : "\(entry.pet.name) · \(entry.pet.lifeStage.displayName)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PawTheme.inkSecondary)
            }
            .frame(height: 18)

            ZStack(alignment: .topTrailing) {
                PawTheme.habitatGradient
                Ellipse()
                    .fill(PawTheme.grassGreen.opacity(0.45))
                    .frame(width: 390, height: 115)
                    .offset(y: 82)
                HStack {
                    AnimalPortraitView(pet: entry.pet)
                        .frame(width: 150, height: 150)
                    Spacer()
                }
                .padding(.leading, 10)

                Text(isEgg ? "A tiny surprise is waiting. Your workouts help it hatch!" : entry.pet.mood.shortMessage)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawTheme.ink)
                    .lineLimit(3)
                    .frame(width: 150, alignment: .leading)
                    .padding(10)
                    .background(PawTheme.surface.opacity(0.94), in: UnevenRoundedRectangle(topLeadingRadius: 15, bottomLeadingRadius: 15, bottomTrailingRadius: 5, topTrailingRadius: 15))
                    .padding(13)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))

            HStack(spacing: 6) {
                if isEgg {
                    WidgetMetric(value: "\(Int((entry.pet.lifecycle?.growthProgress ?? 0) * 100))%", label: "hatching", tint: PawTheme.adventureBlue)
                    WidgetMetric(value: "\(minutesRemaining) min", label: "workout to hatch", tint: PawTheme.coralOrange)
                    WidgetMetric(value: "A surprise", label: "companion inside", tint: PawTheme.teal)
                } else {
                    WidgetMetric(value: "\(entry.pet.energy)%", label: "energy", tint: PawTheme.adventureBlue)
                    WidgetMetric(value: entry.pet.mood.label, label: "mood", tint: PawTheme.coralOrange)
                    WidgetMetric(value: isGrowing ? "\(Int((entry.pet.lifecycle?.growthProgress ?? 0) * 100))%" : "\(entry.pet.experience) XP", label: isGrowing ? "growing up" : "next level", tint: PawTheme.teal)
                }
            }
            .frame(height: 43)

            HStack(spacing: 6) {
                if !isEgg {
                    Button(intent: FeedPetIntent()) {
                        WidgetActionLabel(title: "Feed", symbol: "carrot.fill", tint: PawTheme.energyYellow)
                    }
                }
                Link(destination: URL(string: "pawpace://workout")!) {
                    WidgetActionLabel(title: isEgg ? "Workout to hatch" : "Workout", symbol: "figure.mixed.cardio", tint: PawTheme.adventureBlue.opacity(0.15))
                }
                if !isEgg {
                    Button(intent: PlayWithPetIntent()) {
                        WidgetActionLabel(title: "Play", symbol: "tennisball.fill", tint: PawTheme.grassGreen.opacity(0.18))
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(height: 36)

            HStack(spacing: 8) {
                Image(systemName: "figure.mixed.cardio")
                    .font(.title2)
                    .foregroundStyle(PawTheme.grassGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isGrowing ? (isEgg ? "A little closer to hatching" : "Growing with every workout") : "Move 30 min with \(companionName)")
                        .font(.caption2.weight(.bold))
                    Text(isGrowing ? "\(minutesRemaining) workout min to \(isEgg ? "hatch" : "adulthood") · At your pace" : "\(max(30 - entry.pet.currentDayWorkoutMinutes, 0)) min left · Every workout counts")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(PawTheme.inkSecondary)
                }
                Spacer()
                Image(systemName: isGrowing ? "sparkles" : (entry.pet.currentDayWorkoutMinutes >= 30 ? "checkmark.circle.fill" : "flag.checkered"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PawTheme.adventureBlue)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(PawTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .padding(14)
        .background(PawTheme.surface)
    }
}

private struct WidgetMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(PawTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct WidgetActionLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(PawTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
