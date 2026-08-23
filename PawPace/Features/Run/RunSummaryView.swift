import SwiftUI

struct RunSummaryView: View {
    let summary: RunSummary
    let pet: PetSnapshot
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            PawTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text("QUEST COMPLETE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(PawTheme.adventureBlue)

                    Text("Trail conquered!")
                        .font(.system(size: 31, weight: .heavy, design: .rounded))

                    ZStack {
                        Circle().fill(PawTheme.energyYellow.opacity(0.22)).frame(width: 240, height: 240)
                        MochiCreatureView(mood: .proud, stage: pet.stage, accessory: pet.equippedAccessory)
                            .frame(width: 230, height: 230)
                    }

                    Text("“That was legendary. I counted every step—and only got distracted by three birds.”")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PawTheme.inkSecondary)
                        .padding(.horizontal, 24)

                    HStack(spacing: 9) {
                        MetricPill(icon: "figure.run", value: PawPaceFormatting.distance(kilometers: summary.distanceKilometers), label: "kilometers")
                        MetricPill(icon: "stopwatch.fill", value: PawPaceFormatting.duration(seconds: summary.elapsedSeconds), label: "duration", tint: PawTheme.coralOrange)
                        MetricPill(icon: "speedometer", value: PawPaceFormatting.pace(secondsPerKilometer: summary.averagePaceSecondsPerKilometer), label: "avg pace", tint: PawTheme.grassGreen)
                    }

                    VStack(spacing: 10) {
                        RewardRow(symbol: "sparkles", title: "Creature experience", value: "+\(summary.experienceEarned) XP", tint: PawTheme.energyYellow)
                        RewardRow(symbol: "heart.fill", title: "Friendship", value: "+\(max(2, Int(summary.distanceKilometers * 3)))", tint: Color.pink)
                        RewardRow(symbol: "shippingbox.fill", title: "Trail discovery", value: "Leaf charm", tint: PawTheme.grassGreen)
                    }
                    .pawCard()

                    Button(action: dismiss) {
                        Text("Continue adventure")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(PawTheme.adventureBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct RewardRow: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.headline.bold())
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
        }
    }
}

