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
        .configurationDisplayName("Mochi Companion")
        .description("A compact living companion with mood, energy, and a quick feed action.")
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
        .configurationDisplayName("Mochi Habitat")
        .description("A full companion habitat with progression, actions, and today’s running quest.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

private struct CompactPetWidgetView: View {
    let entry: PetWidgetEntry

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
                    Label("\(entry.pet.friendship)", systemImage: "heart.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.pink)
                }

                ZStack(alignment: .topTrailing) {
                    MochiCreatureView(
                        mood: entry.pet.mood,
                        stage: entry.pet.stage,
                        accessory: entry.pet.equippedAccessory,
                        decoration: entry.pet.activeDecoration
                    )
                        .frame(width: 94, height: 94)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Link(destination: URL(string: "pawpace://chat")!) {
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
                    Text("\(entry.pet.energy)% energy")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(PawTheme.inkSecondary)
                    Spacer()
                    Button(intent: FeedPetIntent()) {
                        Image(systemName: "carrot.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(PawTheme.ink)
                            .frame(width: 27, height: 27)
                            .background(PawTheme.energyYellow, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Feed \(entry.pet.name)")
                }
            }
            .padding(12)
        }
    }

    private var compactMessage: String {
        switch entry.pet.mood {
        case .hungry: "Snack first, then adventure?"
        case .tired, .sleepy: "Tiny nap. Big quest later."
        default: "Ready for our 3 km quest?"
        }
    }
}

private struct HabitatPetWidgetView: View {
    let entry: PetWidgetEntry

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("PAWPACE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(PawTheme.adventureBlue)
                Spacer()
                Text("\(entry.pet.name) · Level \(entry.pet.level)")
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
                    MochiCreatureView(
                        mood: entry.pet.mood,
                        stage: entry.pet.stage,
                        accessory: entry.pet.equippedAccessory,
                        decoration: entry.pet.activeDecoration
                    )
                        .frame(width: 150, height: 150)
                    Spacer()
                }
                .padding(.leading, 10)

                Text(entry.pet.mood.shortMessage)
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
                WidgetMetric(value: "\(entry.pet.energy)%", label: "energy", tint: PawTheme.adventureBlue)
                WidgetMetric(value: entry.pet.mood.label, label: "mood", tint: PawTheme.coralOrange)
                WidgetMetric(value: "\(entry.pet.experience) XP", label: "next level", tint: PawTheme.teal)
            }
            .frame(height: 43)

            HStack(spacing: 6) {
                Button(intent: FeedPetIntent()) {
                    WidgetActionLabel(title: "Feed", symbol: "carrot.fill", tint: PawTheme.energyYellow)
                }
                Link(destination: URL(string: "pawpace://chat")!) {
                    WidgetActionLabel(title: "Talk", symbol: "message.fill", tint: PawTheme.adventureBlue.opacity(0.15))
                }
                Button(intent: PlayWithPetIntent()) {
                    WidgetActionLabel(title: "Play", symbol: "tennisball.fill", tint: PawTheme.grassGreen.opacity(0.18))
                }
            }
            .buttonStyle(.plain)
            .frame(height: 36)

            HStack(spacing: 8) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title2)
                    .foregroundStyle(PawTheme.grassGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run 3 km with \(entry.pet.name)")
                        .font(.caption2.weight(.bold))
                    Text("\(max(3 - entry.pet.distanceTodayKilometers, 0), specifier: "%.1f") km left · \(Int(min(entry.pet.distanceTodayKilometers / 3, 1) * 100))% complete")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(PawTheme.inkSecondary)
                }
                Spacer()
                Text("+120 XP")
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
