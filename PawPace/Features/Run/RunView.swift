import CoreLocation
import MapKit
import SwiftUI

struct RunView: View {
    @ObservedObject var tracker: RunTracker
    let onFinish: () async -> Void

    var body: some View {
        VStack(spacing: 13) {
            header
            map
            metrics
            controls
        }
        .padding(.horizontal, 17)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(PawTheme.background)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(tracker.phase == .idle ? "SUNDAY MORNING" : phaseLabel.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(PawTheme.inkSecondary)
                Text("Run together")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
            }
            Spacer()
            Image(systemName: tracker.phase == .running ? "location.fill" : "location")
                .font(.title3.bold())
                .foregroundStyle(PawTheme.adventureBlue)
                .frame(width: 44, height: 44)
                .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    private var map: some View {
        ZStack(alignment: .topLeading) {
            RunMapView(route: tracker.route)

            HStack(spacing: 7) {
                Circle()
                    .fill(tracker.phase == .paused ? PawTheme.energyYellow : PawTheme.grassGreen)
                    .frame(width: 8, height: 8)
                Text(mapStatus)
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.ultraThickMaterial, in: Capsule())
            .padding(12)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    MochiCreatureView(mood: tracker.phase == .running ? .excited : .happy, stage: .sprout)
                        .frame(width: 76, height: 76)
                        .padding(6)
                        .background(PawTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: PawTheme.ink.opacity(0.12), radius: 10, y: 5)
                        .padding(12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(PawTheme.line.opacity(0.7))
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            RunMetric(value: PawPaceFormatting.distance(kilometers: tracker.distanceKilometers), label: "kilometers", isPrimary: true)
            RunMetric(value: PawPaceFormatting.pace(secondsPerKilometer: tracker.paceSecondsPerKilometer), label: "avg pace")
            RunMetric(value: PawPaceFormatting.duration(seconds: tracker.elapsedSeconds), label: "time")
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch tracker.phase {
        case .idle, .finished:
            Button {
                tracker.start()
            } label: {
                Label("Start run with Mochi", systemImage: "play.fill")
                    .runControlStyle(background: PawTheme.energyYellow, foreground: PawTheme.ink)
            }
        case .running, .paused:
            HStack(spacing: 9) {
                Button {
                    tracker.togglePause()
                } label: {
                    Label(tracker.phase == .running ? "Pause" : "Resume", systemImage: tracker.phase == .running ? "pause.fill" : "play.fill")
                        .runControlStyle(background: PawTheme.adventureBlue, foreground: .white)
                }
                Button {
                    Task { await onFinish() }
                } label: {
                    Label("Finish", systemImage: "flag.checkered")
                        .runControlStyle(background: PawTheme.coralOrange, foreground: .white)
                }
            }
        }
    }

    private var phaseLabel: String {
        switch tracker.phase {
        case .idle: "Ready"
        case .running: "Tracking with GPS"
        case .paused: "Run paused"
        case .finished: "Run complete"
        }
    }

    private var mapStatus: String {
        switch tracker.locationAuthorization {
        case .denied, .restricted: "Location permission needed"
        case .notDetermined: "Waiting for permission"
        default: phaseLabel
        }
    }
}

private struct RunMapView: View {
    let route: [CLLocationCoordinate2D]
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            if route.count > 1 {
                MapPolyline(coordinates: route)
                    .stroke(PawTheme.adventureBlue, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .onChange(of: route.count) { _, _ in
            guard let latest = route.last else { return }
            withAnimation {
                camera = .region(
                    MKCoordinateRegion(
                        center: latest,
                        latitudinalMeters: 900,
                        longitudinalMeters: 900
                    )
                )
            }
        }
    }
}

private struct RunMetric: View {
    let value: String
    let label: String
    var isPrimary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: isPrimary ? 23 : 17, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PawTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(PawTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: PawTheme.ink.opacity(0.07), radius: 9, y: 4)
    }
}

private extension View {
    func runControlStyle(background: Color, foreground: Color) -> some View {
        self
            .font(.subheadline.weight(.bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(background, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

