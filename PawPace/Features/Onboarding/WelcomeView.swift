import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("WELCOME TO PAWPACE")
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(PawTheme.adventureBlue)
                    Text("Little steps.\nA friend for life.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Make time for movement, and watch a little companion grow with you.")
                        .font(.body)
                        .foregroundStyle(PawTheme.inkSecondary)
                }
                AnimalPortraitView(species: .corgi, lifeStage: .egg, variant: .classic)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 32))
                    .accessibilityLabel("A mystery egg waiting to hatch")
                VStack(alignment: .leading, spacing: 22) {
                    GuideRow(symbol: "sparkles", title: "Your own surprise egg", detail: "A little friend is waiting inside. Who will you meet when it hatches?")
                    GuideRow(symbol: "figure.walk", title: "Move a little, grow together", detail: "Earn 30 progress minutes to hatch. Another 180 minutes grows your baby into an adult. Workouts count, and you can enable everyday activity in Settings.")
                    GuideRow(symbol: "leaf", title: "A gentle rhythm is enough", detail: "Your workout mix shapes its genes and coat. Up to 60 minutes a day count, and rest never takes progress away.")
                }

            }
            .padding(28)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Text("Meet my egg")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(PawTheme.buttonForeground)
                        .background(PawTheme.adventureBlue, in: Capsule())
                }
                .buttonStyle(.plain)
                Text("No account needed. Choose Health and location access when you start a workout.")
                    .font(.caption)
                    .foregroundStyle(PawTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(PawTheme.background)
        }
        .background(PawTheme.background.ignoresSafeArea())
        .foregroundStyle(PawTheme.ink)
    }
}

struct CompanionGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Every little adventure counts")
                    .font(.system(.title, design: .rounded, weight: .bold))
                GuideRow(symbol: "circle.dotted", title: "Egg → baby → grown-up", detail: "Your egg hatches after 30 progress minutes. Your baby grows up after 180 more. Saved workouts count active time; paused time doesn’t count. Optional everyday activity also lets shared steps and new Apple Health workouts contribute.")
                GuideRow(symbol: "hand.draw", title: "Make yourself at home", detail: "Drag the garden to turn it, pinch to zoom, and use Reset view to return home. After hatching, tap your friend or use the care buttons to give a snack and play.")
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your habits shape a unique friend").font(.headline)
                    ForEach(PetGeneticTrait.allCases, id: \.self) { trait in
                        GuideRow(symbol: trait.symbol, title: "\(trait.displayName) · \(trait.colorVariant.displayName)", detail: trait.workoutExamples)
                    }
                    Text("The trait with the most credited minutes shapes an ordinary coat. Genes settle at adulthood. Every type of movement counts equally per minute; a harder workout doesn’t hatch an egg faster.")
                        .font(.subheadline)
                        .foregroundStyle(PawTheme.inkSecondary)
                }
                .pawCard()
                GuideRow(symbol: "pawprint", title: "A friend to discover", detail: "Every egg holds a surprise. Some companions are rarer than others, and you’ll discover yours when it hatches. Your friend is chosen when the egg arrives; reopening the app or working out harder won’t change who is inside.")
                GuideRow(symbol: "sparkles", title: "A coat of their own", detail: "Your workout mix shapes an ordinary coat, while some eggs hold an unexpected color of their own. That surprise is chosen when the egg arrives and revealed at hatching.")
                GuideRow(symbol: "star.circle", title: "A little extra magic", detail: "After hatching, try Play to discover your friend’s personality. Some companions have a special move waiting to surprise you. Every friend grows at the same gentle pace.")
                GuideRow(symbol: "map", title: "Adventures keep growing", detail: "Open the map from Home. Grown companions find another mystery egg after 180 progress minutes. Choose expeditions to discover decorations and memories, and return to any friend you’ve welcomed. Level, XP, coins, and your habitat belong to the whole home; each friend keeps their own name, genes, care, and grown-up milestones.")
                GuideRow(symbol: "calendar", title: "A rhythm of your own", detail: "Choose two to five days of movement a week. Five progress minutes makes an activity day. Weekly keepsakes stay yours; rest days never reset your adventures. A new target applies next week once you’ve begun.")
                GuideRow(symbol: "moon", title: "Rest is part of the story", detail: "Up to 60 active minutes each day count toward growth and genes. Longer workouts still appear in your journal. Your companion never loses growth on a rest day.")
                GuideRow(symbol: "applewatch", title: "With or without a Watch", detail: "Use a paired Apple Watch for a live workout, or use your iPhone’s workout timer. Outdoor distance uses location. Available Health readings depend on your devices and permissions; missing readings appear as a dash.")
                Text("PawPace is a companion for movement, not a medical or training service. Choose activities and a pace that feel right for you.")
                    .font(.footnote)
                    .foregroundStyle(PawTheme.inkSecondary)
            }
            .padding(24)
        }
        .background(PawTheme.background.ignoresSafeArea())
        .foregroundStyle(PawTheme.ink)
        .navigationTitle("Companion guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuideRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(PawTheme.adventureBlue)
                .frame(width: 28, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(PawTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
