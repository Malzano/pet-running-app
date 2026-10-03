import SwiftUI

/// Only these explicit fields reach the export. No route, Health readings,
/// location, hidden species, or other family members enter a concealed card.
struct CompanionShareContent {
    let pet: PetSnapshot
    var summary: RunSummary?
    var revealsCompanion: Bool
    var includesWorkout: Bool = true
    var concealsCompanion: Bool { pet.lifeStage == .egg || !revealsCompanion }
    var title: String {
        if summary != nil { return "A little movement.\nA little magic." }
        return concealsCompanion ? "A new friend.\nA secret worth keeping." : "Look who I found."
    }
    var companionCaption: String {
        concealsCompanion ? "A little mystery, all my own" : "\(pet.name) · \(pet.species.displayName)"
    }
}

struct CompanionShareCard: View {
    let content: CompanionShareContent
    var body: some View {
        VStack(spacing: 22) {
            Text("PAWPACE").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(4)
                .foregroundStyle(PawTheme.adventureBlue)
            Text(content.title).font(.system(size: 31, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            ZStack {
                Circle().fill(PawTheme.habitatGradient).frame(width: 230, height: 230)
                if content.concealsCompanion {
                    AnimalPortraitView(species: .corgi, lifeStage: .egg, variant: .classic)
                        .frame(width: 188, height: 210)
                } else {
                    AnimalPortraitView(pet: content.pet).frame(width: 188, height: 210)
                }
            }
            Text(content.companionCaption)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center).lineLimit(2)
            if content.includesWorkout, let summary = content.summary {
                Label("\(summary.workoutConfiguration.activity.displayName) · \(summary.elapsedSeconds / 60) min",
                      systemImage: summary.workoutConfiguration.activity.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(PawTheme.surface, in: Capsule())
            }
            Text("Little steps. A world to discover.")
                .font(.system(size: 12)).foregroundStyle(PawTheme.inkSecondary)
        }
        .padding(28)
        .frame(width: 360)
        .background(PawTheme.background)
        .foregroundStyle(PawTheme.ink)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .medium)
    }
}

struct CompanionShareView: View {
    let pet: PetSnapshot
    var summary: RunSummary?
    @Environment(\.dismiss) private var dismiss
    @State private var revealsCompanion = false
    @State private var includesWorkout = true
    @State private var exportedImage: Image?
    @State private var exportError = false

    private var content: CompanionShareContent {
        CompanionShareContent(pet: pet, summary: summary, revealsCompanion: revealsCompanion, includesWorkout: includesWorkout)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let exportedImage {
                        exportedImage.resizable().scaledToFit()
                            .frame(maxWidth: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .accessibilityLabel("\(content.title). \(content.companionCaption)")
                    }
                    if pet.lifeStage != .egg {
                        Toggle("Reveal my companion", isOn: $revealsCompanion)
                        Text("Keep the surprise, or show the friend you discovered. The preview is exactly what you’ll share.")
                            .font(.caption).foregroundStyle(PawTheme.inkSecondary)
                    }
                    if summary != nil { Toggle("Include activity and minutes", isOn: $includesWorkout) }
                    if exportError {
                        Text("The card couldn’t be prepared.").font(.footnote)
                        Button("Try again", action: render)
                    }
                }
                .padding(22)
            }
            .safeAreaInset(edge: .bottom) {
                Group {
                    if let exportedImage {
                        ShareLink(item: exportedImage, preview: SharePreview("A little PawPace adventure", image: exportedImage)) {
                            Label("Share card", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(PawTheme.buttonForeground)
                    } else if !exportError { ProgressView("Preparing your card") }
                }
                .padding(18)
                .background(PawTheme.background)
            }
            .background(PawTheme.background)
            .toolbarBackground(PawTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("Share a little magic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear(perform: render)
            .onChange(of: revealsCompanion) { _, _ in render() }
            .onChange(of: includesWorkout) { _, _ in render() }
        }
        .tint(PawTheme.adventureBlue)
        .foregroundStyle(PawTheme.ink)
    }

    @MainActor private func render() {
        exportedImage = nil
        let renderer = ImageRenderer(content: CompanionShareCard(content: content))
        renderer.scale = 3
        if let image = renderer.uiImage {
            exportedImage = Image(uiImage: image)
            exportError = false
        } else { exportError = true }
    }
}
