import Foundation
import OSLog
import WatchConnectivity

@MainActor
final class WatchPetConnectivityService: NSObject, ObservableObject {
    static let shared = WatchPetConnectivityService()
    private static let log = Logger(subsystem: "com.pawpace.app.sync", category: "watch-connectivity")

    @Published private(set) var pet: PetSnapshot
    @Published private(set) var phoneRunState: PawPaceRunState
    @Published private(set) var isPhoneReachable = false

    var onControl: ((PawPaceWatchControl) -> Void)? {
        didSet {
            guard let onControl, !pendingControls.isEmpty else { return }
            let controls = pendingControls.sorted { $0.issuedAt < $1.issuedAt }
            pendingControls.removeAll()
            controls.forEach(onControl)
        }
    }

    private let session: WCSession?
    private var hasAuthoritativePet: Bool
    private var latestPhoneRunUpdate: Date
    private var latestControlUpdateByWorkout: [UUID: Date]
    private var handledControlIDs: [UUID: Date]
    private var pendingControls: [PawPaceWatchControl]
    private var latestPublishedPayload: PawPaceWatchPayload?

    private override init() {
        let connectivitySession = WCSession.isSupported() ? WCSession.default : nil
        let initialPayload = connectivitySession.flatMap {
            Self.decodePayload(from: $0.receivedApplicationContext)
        }
        let cachedPet = PawPaceShared.loadSnapshotIfPresent()
        // A neutral egg placeholder is replaced by the phone's saved starter.
        pet = initialPayload?.pet ?? cachedPet ?? .newPlayer(seed: 0)
        phoneRunState = initialPayload?.run ?? .idle
        latestPhoneRunUpdate = initialPayload?.run.updatedAt ?? .distantPast
        if let initialControl = initialPayload?.control {
            latestControlUpdateByWorkout = [initialControl.workoutID: initialControl.issuedAt]
            handledControlIDs = [initialControl.id: initialControl.issuedAt]
            pendingControls = [initialControl]
        } else {
            latestControlUpdateByWorkout = [:]
            handledControlIDs = [:]
            pendingControls = []
        }
        hasAuthoritativePet = initialPayload != nil || cachedPet != nil
        session = connectivitySession
        latestPublishedPayload = nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func publish(run: PawPaceRunState) {
        let payload = PawPaceWatchPayload(pet: pet, run: run)
        latestPublishedPayload = payload
        deliver(payload)
    }

    private func resendLatestPayload() {
        guard let latestPublishedPayload else { return }
        deliver(latestPublishedPayload)
    }

    private func deliver(_ payload: PawPaceWatchPayload) {
        guard let session, let data = try? JSONEncoder().encode(payload) else { return }

        do {
            try session.updateApplicationContext([PawPaceWatchMessageKey.payload: data])
        } catch {
            Self.log.error("state context failed: \(error.localizedDescription, privacy: .private)")
        }
        if payload.run.phase == .finished || payload.run.phase == .failed {
            session.transferUserInfo([PawPaceWatchMessageKey.payload: data])
        }
        if session.isReachable {
            session.sendMessage(
                [PawPaceWatchMessageKey.payload: data],
                replyHandler: nil
            ) { error in
                let message = error.localizedDescription
                Task { @MainActor in
                    Self.log.error("state message failed: \(message, privacy: .private)")
                }
            }
        }
    }

    func apply(_ payload: PawPaceWatchPayload) {
        if PawPaceSyncPolicy.shouldAcceptPet(
            payload.pet,
            current: pet,
            hasAuthoritativePet: hasAuthoritativePet
        ) {
            pet = payload.pet
            hasAuthoritativePet = true
            PawPaceShared.saveSnapshot(payload.pet)
        }
        if payload.run.updatedAt > latestPhoneRunUpdate {
            phoneRunState = payload.run
            latestPhoneRunUpdate = payload.run.updatedAt
        }
        if let control = payload.control {
            Self.log.notice(
                "payload action=\(control.action.rawValue, privacy: .private) workout=\(control.workoutID.uuidString, privacy: .private) reply=\(control.replyToWatchWorkoutID?.uuidString ?? "-", privacy: .private)"
            )
            accept(control)
        }
    }

    private func accept(_ control: PawPaceWatchControl) {
        guard handledControlIDs[control.id] == nil else { return }
        handledControlIDs[control.id] = control.issuedAt
        if handledControlIDs.count > 128,
           let oldest = handledControlIDs.min(by: { $0.value < $1.value })?.key {
            handledControlIDs.removeValue(forKey: oldest)
        }

        guard control.issuedAt > latestControlUpdateByWorkout[control.workoutID, default: .distantPast] else {
            return
        }
        latestControlUpdateByWorkout[control.workoutID] = control.issuedAt
        Self.log.notice(
            "accept action=\(control.action.rawValue, privacy: .private) workout=\(control.workoutID.uuidString, privacy: .private)"
        )
        if let onControl {
            onControl(control)
        } else {
            pendingControls.append(control)
        }
    }
}

extension WatchPetConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        let payload = Self.decodePayload(from: context)
        Task { @MainActor [weak self] in
            self?.isPhoneReachable = reachable
            if let payload {
                self?.apply(payload)
            }
            self?.resendLatestPayload()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isPhoneReachable = reachable
            if reachable {
                self?.resendLatestPayload()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        if let error {
            let message = error.localizedDescription
            Task { @MainActor in
                Self.log.error("state transfer failed: \(message, privacy: .private)")
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receive(userInfo)
    }

    private nonisolated func receive(_ message: [String: Any]) {
        guard let payload = Self.decodePayload(from: message) else { return }
        Task { @MainActor [weak self] in
            self?.apply(payload)
        }
    }

    private nonisolated static func decodePayload(from message: [String: Any]) -> PawPaceWatchPayload? {
        guard let data = message[PawPaceWatchMessageKey.payload] as? Data else { return nil }
        return try? JSONDecoder().decode(PawPaceWatchPayload.self, from: data)
    }
}
