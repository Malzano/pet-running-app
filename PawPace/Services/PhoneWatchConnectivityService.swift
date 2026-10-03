import Foundation
import OSLog
import WatchConnectivity

@MainActor
final class PhoneWatchConnectivityService: NSObject {
    private static let log = Logger(subsystem: "com.pawpace.app.sync", category: "phone-connectivity")

    var onRunState: ((PawPaceRunState) -> Void)? {
        didSet {
            guard let onRunState, !pendingInboundRunStates.isEmpty else { return }
            let pending = pendingInboundRunStates.sorted { $0.updatedAt < $1.updatedAt }
            pendingInboundRunStates.removeAll()
            pending.forEach(onRunState)
        }
    }

    private let session: WCSession?
    private var latestPayload = PawPaceWatchPayload(pet: .starter, run: .idle)
    private var latestReceivedRunUpdate = Date.distantPast
    private var latestRunUpdateByWorkout: [UUID: Date] = [:]
    private var pendingInboundRunStates: [PawPaceRunState] = []

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func sync(pet: PetSnapshot, run: PawPaceRunState) {
        // Keep the latest command in application context until the Watch
        // reports that phase. Periodic telemetry must not overwrite the only
        // durable copy of a pause/resume/finish command.
        let pendingControl = latestPayload.control.flatMap { control in
            run.workoutID == control.workoutID && run.phase == control.phase ? control : nil
        }
        let payload = PawPaceWatchPayload(pet: pet, run: run, control: pendingControl)
        latestPayload = payload
        guard let session, let data = try? JSONEncoder().encode(payload) else { return }

        do {
            try session.updateApplicationContext([PawPaceWatchMessageKey.payload: data])
        } catch {
            Self.log.error("context sync failed: \(error.localizedDescription, privacy: .private)")
        }
        if session.isReachable {
            session.sendMessage(
                [PawPaceWatchMessageKey.payload: data],
                replyHandler: nil
            ) { error in
                Self.log.error("message sync failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func resendLatestPayload() {
        sync(pet: latestPayload.pet, run: latestPayload.run)
    }

    @discardableResult
    func sendControl(
        pet: PetSnapshot,
        run: PawPaceRunState,
        action: PawPaceWatchControlAction,
        replyToWatchWorkoutID: UUID? = nil
    ) -> PawPaceWatchPayload? {
        guard
            let workoutID = run.workoutID,
            let startedAt = run.startedAt,
            run.phase == action.phase
        else { return nil }
        let control = PawPaceWatchControl(
            id: UUID(),
            workoutID: workoutID,
            action: action,
            startedAt: startedAt,
            issuedAt: .now,
            replyToWatchWorkoutID: replyToWatchWorkoutID,
            workoutConfiguration: run.workoutConfiguration,
            multisportLegIndex: run.multisportLegIndex
        )
        let payload = PawPaceWatchPayload(pet: pet, run: run, control: control)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        latestPayload = payload

        Self.log.notice(
            "send action=\(action.rawValue, privacy: .private) workout=\(workoutID.uuidString, privacy: .private) reply=\(replyToWatchWorkoutID?.uuidString ?? "-", privacy: .private) reachable=\(self.session?.isReachable ?? false)"
        )

        if let session {
            do {
                try session.updateApplicationContext([PawPaceWatchMessageKey.payload: data])
            } catch {
                Self.log.error("control context failed: \(error.localizedDescription, privacy: .private)")
            }
            session.transferUserInfo([PawPaceWatchMessageKey.payload: data])
            if session.isReachable {
                session.sendMessage(
                    [PawPaceWatchMessageKey.payload: data],
                    replyHandler: nil
                ) { error in
                    Self.log.error("control message failed: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
        return payload
    }
}

extension PhoneWatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        receive(session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            self?.resendLatestPayload()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in
            self?.resendLatestPayload()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        Task { @MainActor [weak self] in
            self?.resendLatestPayload()
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
                Self.log.error("user info transfer failed: \(message, privacy: .private)")
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
        if
            let data = message[PawPaceWatchMessageKey.payload] as? Data,
            let payload = try? JSONDecoder().decode(PawPaceWatchPayload.self, from: data)
        {
            Task { @MainActor [weak self] in
                self?.accept(payload.run)
            }
        }
    }

    private func accept(_ state: PawPaceRunState) {
        if let workoutID = state.workoutID {
            guard state.updatedAt > latestRunUpdateByWorkout[workoutID, default: .distantPast] else { return }
            latestRunUpdateByWorkout[workoutID] = state.updatedAt
            if latestRunUpdateByWorkout.count > 64,
               let oldest = latestRunUpdateByWorkout.min(by: { $0.value < $1.value })?.key {
                latestRunUpdateByWorkout.removeValue(forKey: oldest)
            }
        } else {
            guard state.updatedAt > latestReceivedRunUpdate else { return }
            latestReceivedRunUpdate = state.updatedAt
        }
        if
            let control = latestPayload.control,
            control.workoutID == state.workoutID,
            control.phase == state.phase,
            control.action != .nextActivity || state.multisportLegIndex >= control.multisportLegIndex,
            state.updatedAt >= control.issuedAt
        {
            latestPayload.control = nil
        }
        if let onRunState {
            Self.log.notice(
                "receive phase=\(state.phase.rawValue, privacy: .private) workout=\(state.workoutID?.uuidString ?? "-", privacy: .private)"
            )
            onRunState(state)
        } else {
            pendingInboundRunStates.append(state)
            if pendingInboundRunStates.count > 64 {
                pendingInboundRunStates.removeFirst(pendingInboundRunStates.count - 64)
            }
        }
    }
}
