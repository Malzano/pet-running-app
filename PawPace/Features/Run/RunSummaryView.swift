import SwiftUI
import CoreLocation
import MapKit

struct RunSummaryView: View {
    let summary: RunSummary
    let pet: PetSnapshot
    var route: [CLLocationCoordinate2D] = []
    var friendStore: ClubStore? = nil
    var saveMessage: String? = nil
    var rewardsPending = false
    let dismiss: () -> Void
    @State private var showsShare = false
    @State private var showsFriendShare = false

    private var milestoneTitle: String? {
        if pet.lifecycle?.maturedAt == summary.endedAt { return "All grown up, together." }
        if pet.lifecycle?.hatchedAt == summary.endedAt { return "Your egg has hatched!" }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("\(summary.workoutConfiguration.activity.displayName) complete")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PawTheme.inkSecondary)
                    Text(milestoneTitle ?? "Time well spent, together.")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                AnimalCompanionView(species: pet.species, motion: .celebrating,
                                    lifeStage: pet.lifeStage, variant: pet.lifecycle?.variant ?? .classic)
                    .frame(height: 225)
                    .frame(maxWidth: .infinity)
                    .background(PawTheme.habitatGradient, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

                if let saveMessage {
                    Label(saveMessage, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(PawTheme.inkSecondary)
                        .pawCard()
                }

                HStack(spacing: 18) {
                    if summary.workoutConfiguration.activity.supportsDistance {
                        summaryMetric(PawPaceFormatting.distance(kilometers: summary.distanceKilometers), label: "kilometers")
                    }
                    summaryMetric(PawPaceFormatting.duration(seconds: summary.elapsedSeconds), label: "time")
                    if summary.workoutConfiguration.activity.supportsPace {
                        summaryMetric(PawPaceFormatting.pace(secondsPerKilometer: summary.workoutConfiguration.measurement == .swimPace ? summary.averagePaceSecondsPerKilometer / 10 : summary.averagePaceSecondsPerKilometer), label: summary.workoutConfiguration.measurement == .swimPace ? "pace / 100 m" : "pace / km")
                    } else {
                        summaryMetric(summary.activeEnergyKilocalories > 0 ? "\(Int(summary.activeEnergyKilocalories))" : "—", label: "active kcal")
                    }
                }

                if summary.workoutConfiguration.supportsRoute || !route.isEmpty {
                    routeRecap
                }

                if pet.lifecycle != nil {
                    PetGrowthCard(pet: pet)
                }

                HStack(spacing: 12) {
                    Image(systemName: "leaf")
                        .font(.title2.weight(.light))
                        .foregroundStyle(PawTheme.adventureBlue)
                        .frame(width: 42, height: 42)
                        .background(PawTheme.surfaceRaised, in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(rewardsPending ? "Your rewards are waiting" : "Growing a little closer")
                            .font(.subheadline.weight(.semibold))
                        Text(rewardsPending ? "We’ll retry adding your XP and growth when local storage is available." : "+\(summary.experienceEarned) XP · +\(summary.friendshipEarned) friendship")
                            .font(.caption)
                            .foregroundStyle(PawTheme.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                if friendStore != nil {
                    Button { showsFriendShare = true } label: {
                        Label("Celebrate with friends", systemImage: "person.2")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                }

                Button { showsShare = true } label: {
                    Label("Share this adventure", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button(action: dismiss) {
                    Text(pet.lifeStage == .egg ? "Back to your egg" : "Back to \(pet.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PawTheme.buttonForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(PawTheme.adventureBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .sheet(isPresented: $showsFriendShare) {
            if let friendStore { NavigationStack { FriendPostComposer(store: friendStore, summary: summary) } }
        }
        .sheet(isPresented: $showsShare) { CompanionShareView(pet: pet, summary: summary) }
        .scrollIndicators(.hidden)
        .background(PawTheme.background.ignoresSafeArea())
        .foregroundStyle(PawTheme.ink)
    }

    private var routeRecap: some View {
        let recorded = route.filter { CLLocationCoordinate2DIsValid($0) }
        return VStack(alignment: .leading, spacing: 14) {
            Label("The path you took", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(.headline, design: .rounded))
            if recorded.count > 1, let start = recorded.first, let finish = recorded.last {
                Map(initialPosition: .automatic, interactionModes: []) {
                    MapPolyline(coordinates: recorded)
                        .stroke(PawTheme.adventureBlue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    Annotation("Start", coordinate: start, anchor: .center) {
                        Circle().fill(PawTheme.surface).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(PawTheme.adventureBlue, lineWidth: 3))
                    }
                    Annotation("Finish", coordinate: finish) {
                        Image(systemName: "flag.fill").font(.caption)
                            .foregroundStyle(PawTheme.buttonForeground)
                            .padding(9).background(PawTheme.adventureBlue, in: Circle())
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel("Your recorded route, with start and finish marked")
                Text("Just for this recap. Your route isn’t saved to your journal or shared.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            } else {
                Label("No route recorded", systemImage: "location.slash")
                    .font(.subheadline.weight(.medium))
                Text("Your time and effort still count. A route appears here when your phone records an outdoor path.")
                    .font(.caption).foregroundStyle(PawTheme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pawCard()
        .accessibilityIdentifier("workoutRouteRecap")
    }

    private func summaryMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(PawTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
