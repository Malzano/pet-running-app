import Combine
import CoreLocation
import Foundation

struct RunSummary: Identifiable, Equatable {
    let id = UUID()
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let elapsedSeconds: Int
    let averagePaceSecondsPerKilometer: Int
    let averageHeartRate: Int?
    let experienceEarned: Int

    var distanceKilometers: Double { distanceMeters / 1_000 }
}

@MainActor
final class RunTracker: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var heartRate: Int?
    @Published private(set) var locationAuthorization: CLAuthorizationStatus

    private let locationManager = CLLocationManager()
    private let healthKit: HealthKitService
    private let petName: String
    private let liveActivity = LiveActivityService.shared
    private var lastLocation: CLLocation?
    private var startedAt: Date?
    private var segmentStartedAt: Date?
    private var accumulatedSeconds: TimeInterval = 0
    private var timer: AnyCancellable?
    private var lastLiveActivityUpdate = Date.distantPast
    private var lastHeartRateUpdate = Date.distantPast
    private var notificationToken: NSObjectProtocol?

    init(healthKit: HealthKitService, petName: String) {
        self.healthKit = healthKit
        self.petName = petName
        self.locationAuthorization = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 3
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true

        notificationToken = NotificationCenter.default.addObserver(forName: .pawPaceToggleRun, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.togglePause()
            }
        }
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    var distanceKilometers: Double { distanceMeters / 1_000 }

    var paceSecondsPerKilometer: Int {
        guard distanceMeters >= 50 else { return 0 }
        return Int(Double(elapsedSeconds) / distanceKilometers)
    }

    var experienceEarned: Int {
        max(0, Int((distanceKilometers * 52).rounded()))
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func start() {
        guard phase == .idle || phase == .finished else { return }

        if locationAuthorization == .notDetermined {
            requestLocationPermission()
        }

        phase = .running
        distanceMeters = 0
        elapsedSeconds = 0
        route = []
        heartRate = nil
        accumulatedSeconds = 0
        lastLocation = nil
        startedAt = .now
        segmentStartedAt = .now
        PawPaceShared.defaults.set(false, forKey: PawPaceShared.runPausedKey)
        locationManager.startUpdatingLocation()
        startTimer()
        liveActivity.start(petName: petName, targetKilometers: 3)
        publishLiveActivity(force: true)
    }

    func pause() {
        guard phase == .running else { return }
        if let segmentStartedAt {
            accumulatedSeconds += Date().timeIntervalSince(segmentStartedAt)
        }
        segmentStartedAt = nil
        phase = .paused
        locationManager.stopUpdatingLocation()
        lastLocation = nil
        PawPaceShared.defaults.set(true, forKey: PawPaceShared.runPausedKey)
        tick()
        publishLiveActivity(force: true)
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .running
        segmentStartedAt = .now
        PawPaceShared.defaults.set(false, forKey: PawPaceShared.runPausedKey)
        locationManager.startUpdatingLocation()
        publishLiveActivity(force: true)
    }

    func togglePause() {
        phase == .running ? pause() : resume()
    }

    func finish() async -> RunSummary? {
        guard phase == .running || phase == .paused, let startedAt else { return nil }

        if phase == .running, let segmentStartedAt {
            accumulatedSeconds += Date().timeIntervalSince(segmentStartedAt)
        }

        phase = .finished
        locationManager.stopUpdatingLocation()
        timer?.cancel()
        timer = nil
        elapsedSeconds = max(Int(accumulatedSeconds.rounded()), 1)
        let endedAt = Date()
        let summary = RunSummary(
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            averagePaceSecondsPerKilometer: paceSecondsPerKilometer,
            averageHeartRate: heartRate,
            experienceEarned: experienceEarned
        )

        let finalState = activityState(encouragement: "Quest complete! \(petName) earned \(experienceEarned) XP.")
        await liveActivity.end(with: finalState)
        try? await healthKit.saveRun(summary)
        return summary
    }

    func reset() {
        phase = .idle
        distanceMeters = 0
        elapsedSeconds = 0
        route = []
        heartRate = nil
        accumulatedSeconds = 0
        startedAt = nil
        segmentStartedAt = nil
        lastLocation = nil
    }

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        if phase == .running, let segmentStartedAt {
            elapsedSeconds = Int((accumulatedSeconds + Date().timeIntervalSince(segmentStartedAt)).rounded())
        } else {
            elapsedSeconds = Int(accumulatedSeconds.rounded())
        }

        if Date().timeIntervalSince(lastHeartRateUpdate) >= 10 {
            lastHeartRateUpdate = .now
            Task { [weak self] in
                guard let self else { return }
                if let latest = await healthKit.latestHeartRate() {
                    heartRate = latest
                }
            }
        }
        publishLiveActivity(force: false)
    }

    private func publishLiveActivity(force: Bool) {
        guard force || Date().timeIntervalSince(lastLiveActivityUpdate) >= 5 else { return }
        lastLiveActivityUpdate = .now
        let state = activityState(encouragement: encouragement)
        Task { await liveActivity.update(with: state) }
    }

    private var encouragement: String {
        switch distanceKilometers {
        case ..<0.5: "Easy paws first—find your rhythm."
        case ..<1.5: "Great pace! The trail is opening up."
        case ..<2.5: "I can smell quest rewards ahead!"
        default: "Final stretch—maximum zoomies!"
        }
    }

    private func activityState(encouragement: String) -> PawPaceActivityAttributes.ContentState {
        PawPaceActivityAttributes.ContentState(
            distanceKilometers: distanceKilometers,
            elapsedSeconds: elapsedSeconds,
            paceSecondsPerKilometer: paceSecondsPerKilometer,
            heartRate: heartRate ?? 0,
            experienceEarned: experienceEarned,
            isPaused: phase == .paused,
            encouragement: encouragement
        )
    }
}

extension RunTracker: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorization = manager.authorizationStatus
        if phase == .running, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .running else { return }

        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 30 {
            guard abs(location.timestamp.timeIntervalSinceNow) < 15 else { continue }

            if let lastLocation {
                let delta = location.distance(from: lastLocation)
                if delta >= 1, delta <= 100 {
                    distanceMeters += delta
                }
            }

            lastLocation = location
            route.append(location.coordinate)
        }
    }
}

