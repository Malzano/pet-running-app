import SwiftUI
import SceneKit
import simd

/// The phone companion uses the original Meshy meshes and skin weights. Every
/// pose starts from the exported bind pose, so switching actions never accumulates
/// rotations or inherits the unsuitable humanoid animation from an animal export.
struct AnimalCompanionView: UIViewRepresentable {
    let species: PetSpecies
    var motion: PetMotion = .idle
    var facesViewer = false
    var interaction: Int = 0
    var showsObjects = false
    var roams = false
    var staticHabitat = false
    var isResting = false
    var decoration = "Flower Meadow"
    var cameraReset = 0
    var cameraZoom: Binding<Double>? = nil
    var immersive = false
    var lifeStage: PetLifeStage = .adult
    var variant: PetColorVariant = .classic
    var companionSeed: UInt64 = 0x5EED
    var temperament: BuddyTemperament? = nil
    var placements: [HabitatPlacement] = []
    var visitingSpot: HabitatSpot? = nil
    var decorationVisit = 0
    var onPlay: (() -> Void)? = nil
    var onFeed: (() -> Void)? = nil
    var onPet: (() -> Void)? = nil
    var onRoam: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CompanionSceneView {
        let view = CompanionSceneView()
        context.coordinator.attach(view)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: CompanionSceneView, context: Context) {
        let allowsCamera = roams || staticHabitat
        context.coordinator.onZoomChange = { cameraZoom?.wrappedValue = $0 }
        context.coordinator.update(
            species: species, motion: motion, interaction: interaction,
            reduceMotion: reduceMotion, active: scenePhase == .active,
            showsProps: showsObjects, roams: roams, staticHabitat: staticHabitat, isResting: isResting, decoration: decoration,
            cameraReset: cameraReset, cameraZoom: cameraZoom?.wrappedValue, immersive: immersive,
            lifeStage: lifeStage, variant: variant, companionSeed: companionSeed, temperament: temperament,
            placements: placements, facesViewer: facesViewer
        )
        context.coordinator.visitDecoration(spot: visitingSpot, revision: decorationVisit, placements: placements)
        view.onDecoration = roams && lifeStage != .egg ? { [weak coordinator = context.coordinator] spot in
            guard let item = placements.first(where: { $0.spot == spot }) else { return }
            coordinator?.visitDecoration(item)
            onRoam?()
        } : nil
        view.placedKeepsakes = placements
        view.onPlay = lifeStage == .egg ? nil : onPlay
        view.onFeed = lifeStage == .egg ? nil : onFeed
        view.onPet = lifeStage == .egg ? nil : onPet
        view.onRotate = allowsCamera ? { [weak coordinator = context.coordinator] angle in
            coordinator?.rotate(by: angle)
        } : nil
        view.onZoom = allowsCamera ? { [weak coordinator = context.coordinator] scale in
            coordinator?.zoom(by: scale)
        } : nil
        view.onResetCamera = allowsCamera ? { [weak coordinator = context.coordinator] in
            coordinator?.resetCamera()
        } : nil
        view.onDestination = roams && lifeStage != .egg ? { [weak coordinator = context.coordinator] point in
            coordinator?.guide(to: point)
            onRoam?()
        } : nil
        view.isUserInteractionEnabled = allowsCamera || onPlay != nil || onFeed != nil || onPet != nil
        if lifeStage == .egg {
            view.accessibilityLabel = "Mystery egg, resting in a soft grassy nest"
            view.accessibilityHint = allowsCamera ? "Drag left or right to rotate the garden. Pinch to zoom. Complete workouts to help your egg hatch." : "Complete workouts to help your egg hatch."
            return
        }
        let action: String
        switch motion {
        case .idle: action = "resting"
        case .walking: action = species == .bunny ? "hopping" : "walking"
        case .running: action = "running"
        case .jumping: action = "jumping"
        case .playing, .celebrating: action = "playing with you"
        case .feeding: action = "enjoying a snack"
        case .special: action = species.specialMoveName ?? "playing with you"
        }
        view.accessibilityLabel = "\(lifeStage.displayName) \(variant == .classic ? "" : variant.displayName + " ")\(species.rawValue.capitalized) companion, \(roams && !isResting ? "exploring the field" : action)"
        view.accessibilityHint = roams ? "Drag left or right to rotate the garden. Pinch to zoom. Tap the grass to guide your companion, or tap a toy to play." : (staticHabitat ? "Drag left or right to rotate the garden. Pinch to zoom." : "")
    }

    static func dismantleUIView(_ view: CompanionSceneView, coordinator: Coordinator) {
        coordinator.stop()
        view.visibilityChanged = nil
        view.layoutChanged = nil
        view.onRotate = nil
        view.onZoom = nil
        view.onResetCamera = nil
        view.onDecoration = nil
        view.scene = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var view: CompanionSceneView?
        private var displayLink: CADisplayLink?
        private var clockTarget: CompanionClockTarget?
        private var rig: CompanionRig?
        private var species: PetSpecies?
        private var lifeStage: PetLifeStage = .adult
        private var variant: PetColorVariant = .classic
        private var companionSeed: UInt64 = 0x5EED
        private var decorationVisit = 0
        private var motion: PetMotion = .idle
        private var interaction = 0
        private var reduced = false
        private var active = true
        private var previousTime: CFTimeInterval = 0
        private var elapsed: Float = 0
        private var actionElapsed: Float = 0
        private var jumpElapsed: Float = 0
        private var phase: Float = 0
        private var reactionAge: Float = 10
        private var reactionMotion: PetMotion = .playing
        private var weights = SIMD4<Float>.zero // walk, run, jump, play
        private var feeding: Float = 0
        private var celebrationWeight: Float = 0
        private var specialWeight: Float = 0
        private var specialElapsed: Float = 0
        private var roaming: CompanionRoaming?
        private var roamingPose: CompanionRoamingPose?
        private var roams = false
        private var allowsCamera = false
        private var isResting = false
        private var previousRoamingAction: PetMotion = .idle
        private var habitatYaw: Float = 0
        private var cameraReset = 0
        private var habitatZoom = CompanionCameraZoom.standard
        var onZoomChange: ((Double) -> Void)?

        func attach(_ view: CompanionSceneView) {
            self.view = view
            view.visibilityChanged = { [weak self] in self?.updateClock() }
            view.layoutChanged = { [weak self] size in self?.rig?.resizeViewport(size) }
            let target = CompanionClockTarget()
            target.coordinator = self
            clockTarget = target
            let link = CADisplayLink(target: target, selector: #selector(CompanionClockTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func update(species: PetSpecies, motion: PetMotion, interaction: Int, reduceMotion: Bool, active: Bool, showsProps: Bool, roams: Bool = false, staticHabitat: Bool = false, isResting: Bool = false, decoration: String = "Flower Meadow", cameraReset: Int = 0, cameraZoom: Double? = nil, immersive: Bool = false, lifeStage: PetLifeStage = .adult, variant: PetColorVariant = .classic, companionSeed: UInt64 = 0x5EED, temperament: BuddyTemperament? = nil, placements: [HabitatPlacement] = [], facesViewer: Bool = false) {
            if self.species != species || self.lifeStage != lifeStage || self.variant != variant || self.companionSeed != companionSeed {
                self.species = species
                self.lifeStage = lifeStage
                self.variant = variant
                self.companionSeed = companionSeed
                weights = .zero
                feeding = 0
                specialWeight = 0
                celebrationWeight = 0
                specialElapsed = 0
                phase = 0
                elapsed = 0
                actionElapsed = 0
                jumpElapsed = 0
                reactionAge = 10
                roaming = CompanionRoaming(species: species, seed: companionSeed)
                roamingPose = roaming?.step(deltaTime: 0)
                previousRoamingAction = .idle
                self.interaction = interaction
                if let newRig = CompanionRig(species: species, lifeStage: lifeStage, variant: variant) {
                    rig = newRig
                    view?.scene = newRig.scene
                    view?.pointOfView = newRig.camera
                    view?.showFallback(nil)
                    newRig.configureHabitat(roaming: roams, decoration: decoration, immersive: immersive, staticHabitat: staticHabitat, placements: placements)
                    newRig.pose(time: 0, phase: 0, weights: .zero, roaming: roams && lifeStage != .egg ? roamingPose : nil)
                } else {
                    rig = nil
                    view?.scene = nil
                    view?.showFallback(species)
                }
            }
            if self.motion != motion || self.interaction != interaction {
                if motion == .special, specialWeight < 0.03 || specialElapsed >= CompanionSpecialEffects.duration {
                    specialElapsed = 0
                    reactionAge = 0
                    reactionMotion = .special
                }
                // Independent clocks keep an outgoing jump or moving toy at
                // its current phase while its weight fades into the next action.
                if motion == .jumping && weights.z < 0.03 { jumpElapsed = 0 }
                if (motion == .feeding || motion == .playing || motion == .celebrating)
                    && weights.w < 0.03 && feeding < 0.03 {
                    actionElapsed = 0
                }
            }
            if self.interaction != interaction {
                if roams && lifeStage != .egg {
                    rig?.clearDestination()
                    switch motion {
                    case .playing, .celebrating: roaming?.request(.play)
                    case .special: roaming?.request(.special)
                    case .feeding: roaming?.request(.feed)
                    case .jumping: roaming?.request(.greet)
                    case .walking, .running: roaming?.request(.wander)
                    case .idle: break
                    }
                }
                if motion == .jumping || motion == .feeding || motion == .playing || motion == .celebrating || motion == .special {
                    reactionAge = 0
                    reactionMotion = motion
                } else {
                    reactionAge = 10
                }
                self.interaction = interaction
            }
            if self.motion != motion && (motion == .idle || motion == .walking || motion == .running) { reactionAge = 10 }
            self.motion = motion
            roaming?.temperament = temperament
            self.reduced = reduceMotion
            self.active = active
            self.roams = roams
            self.allowsCamera = roams || staticHabitat
            self.isResting = isResting
            rig?.configureHabitat(roaming: roams, decoration: decoration, immersive: immersive, staticHabitat: staticHabitat, placements: placements)
            rig?.configurePortrait(facesViewer: facesViewer)
            if self.cameraReset != cameraReset {
                self.cameraReset = cameraReset
                habitatYaw = 0
                habitatZoom = CompanionCameraZoom.standard
            } else if let cameraZoom, cameraZoom.isFinite {
                habitatZoom = CompanionCameraZoom.clamped(cameraZoom)
            }
            rig?.setHabitatYaw(habitatYaw)
            rig?.setHabitatZoom(habitatZoom)
            updateZoomAccessibility()
            if let size = view?.bounds.size { rig?.resizeViewport(size) }
            rig?.showsProps = showsProps
            if reduceMotion {
                weights = .zero
                feeding = 0
                specialWeight = 0
                celebrationWeight = 0
                rig?.pose(time: 0, phase: 0, weights: .zero, roaming: roams && lifeStage != .egg ? roamingPose : nil)
                view?.setNeedsDisplay()
            }
            updateClock()
            if lifeStage == .egg { view?.setNeedsDisplay() }
        }

        func guide(to point: SIMD2<Float>) {
            guard roams, !reduced, lifeStage != .egg else { return }
            roaming?.request(.moveTo(point))
            if let destination = roaming?.destination { rig?.showDestination(destination) }
        }

        func visitDecoration(spot: HabitatSpot?, revision: Int, placements: [HabitatPlacement]) {
            guard revision != decorationVisit else { return }
            decorationVisit = revision
            guard let item = placements.first(where: { $0.spot == spot }) else { return }
            visitDecoration(item)
        }

        func visitDecoration(_ item: HabitatPlacement) {
            guard roams, !reduced, lifeStage != .egg else { return }
            roaming?.request(.visitDecoration(SIMD2(item.spot.x, item.spot.z), playful: item.decoration.isPlayful))
            if let destination = roaming?.destination { rig?.showDestination(destination) }
        }

        func rotate(by angle: Float) {
            guard allowsCamera, angle.isFinite else { return }
            habitatYaw = (habitatYaw + angle).truncatingRemainder(dividingBy: 2 * .pi)
            rig?.setHabitatYaw(habitatYaw)
            view?.setNeedsDisplay()
        }

        func zoom(by scale: Double) {
            guard allowsCamera, scale.isFinite, scale > 0 else { return }
            // Bound the factor before multiplication, including malformed input
            // from an interrupted gesture, so camera state is always finite.
            habitatZoom = CompanionCameraZoom.clamped(habitatZoom * min(scale, 100))
            rig?.setHabitatZoom(habitatZoom)
            updateZoomAccessibility()
            onZoomChange?(habitatZoom)
            view?.setNeedsDisplay()
        }

        func resetCamera() {
            habitatYaw = 0
            habitatZoom = CompanionCameraZoom.standard
            rig?.setHabitatYaw(0)
            rig?.setHabitatZoom(habitatZoom)
            updateZoomAccessibility()
            onZoomChange?(habitatZoom)
            view?.setNeedsDisplay()
        }

        private func updateZoomAccessibility() {
            view?.accessibilityValue = allowsCamera ? "Zoom \(Int((habitatZoom * 100).rounded())) percent" : nil
        }

        private func updateClock() {
            let shouldPlay = active && !reduced && lifeStage != .egg && view?.window != nil && rig != nil
            if displayLink?.isPaused == shouldPlay { previousTime = 0 }
            displayLink?.isPaused = !shouldPlay
            view?.isPlaying = shouldPlay
        }

        fileprivate func tick(_ link: CADisplayLink) {
            let dt = previousTime == 0 ? Float(1.0 / 60.0) : min(Float(link.timestamp - previousTime), 0.05)
            previousTime = link.timestamp
            advance(deltaTime: dt)
        }

        /// Uses simulation time, so a resumed screen never catches up a long
        /// wall-clock gap. Also provides deterministic lifecycle verification.
        func advance(deltaTime: Float) {
            guard active, !reduced, lifeStage != .egg, deltaTime.isFinite, deltaTime > 0 else { return }
            let dt = min(deltaTime, 0.05)
            elapsed += dt
            actionElapsed += dt
            jumpElapsed += dt
            specialElapsed += dt
            reactionAge += dt
            var target = SIMD4<Float>.zero
            let reactionDuration: Float = reactionMotion == .special ? CompanionSpecialEffects.duration : 2.2
            var effectiveMotion = reactionAge < reactionDuration ? reactionMotion : (motion == .special ? .idle : motion)
            if roams {
                roamingPose = roaming?.step(deltaTime: dt, isResting: isResting)
                effectiveMotion = roamingPose?.action ?? .idle
                if effectiveMotion != previousRoamingAction {
                    if effectiveMotion == .jumping { jumpElapsed = 0 }
                    if effectiveMotion == .special { specialElapsed = 0 }
                    if effectiveMotion == .playing || effectiveMotion == .feeding { actionElapsed = 0 }
                    previousRoamingAction = effectiveMotion
                }
            }
            switch effectiveMotion {
            case .idle: break
            case .walking: target.x = 1
            case .running: target.y = 1
            case .jumping: target.z = 1
            case .playing, .celebrating: target.w = 1
            case .feeding, .special: break
            }
            if roams, let roamingPose, effectiveMotion == .idle,
               abs(roamingPose.turnRate) > 0.15 {
                target.x = min(1, abs(roamingPose.turnRate) * 1.3)
            }
            // Exponential blending is independent of frame rate, including when
            // a tap retriggers a response or the run is paused mid-stride.
            weights += (target - weights) * (1 - exp(-dt * 9))
            feeding += ((effectiveMotion == .feeding ? Float(1) : 0) - feeding) * (1 - exp(-dt * 9))
            specialWeight += ((effectiveMotion == .special ? Float(1) : 0) - specialWeight) * (1 - exp(-dt * 9))
            celebrationWeight += ((effectiveMotion == .celebrating ? Float(1) : 0) - celebrationWeight) * (1 - exp(-dt * 9))
            phase += dt * (1.15 + weights.y * 1.0)
            rig?.pose(time: elapsed, phase: phase, weights: weights, feeding: feeding, actionTime: actionElapsed, jumpTime: jumpElapsed, roaming: roams ? roamingPose : nil, specialTime: specialElapsed, specialWeight: specialWeight, celebrationWeight: celebrationWeight)
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
            clockTarget = nil
            view?.isPlaying = false
        }
    }
}

@MainActor
private final class CompanionClockTarget: NSObject {
    weak var coordinator: AnimalCompanionView.Coordinator?
    @objc func tick(_ link: CADisplayLink) { coordinator?.tick(link) }
}

final class CompanionSceneView: SCNView, UIGestureRecognizerDelegate {
    var visibilityChanged: (() -> Void)?
    var layoutChanged: ((CGSize) -> Void)?
    var onPlay: (() -> Void)?
    var onFeed: (() -> Void)?
    var onPet: (() -> Void)?
    var onDestination: ((SIMD2<Float>) -> Void)?
    var onDecoration: ((HabitatSpot) -> Void)?
    var placedKeepsakes: [HabitatPlacement] = [] { didSet { updateAccessibilityActions() } }
    var onRotate: ((Float) -> Void)? {
        didSet {
            orbitGesture.isEnabled = onRotate != nil
            updateAccessibilityActions()
        }
    }
    var onZoom: ((Double) -> Void)? {
        didSet {
            zoomGesture.isEnabled = onZoom != nil
            updateAccessibilityActions()
        }
    }
    var onResetCamera: (() -> Void)?
    private let fallback = UILabel()
    private lazy var orbitGesture = UIPanGestureRecognizer(target: self, action: #selector(orbit(_:)))
    private lazy var zoomGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
    private var initialOrbitTranslation: CGFloat = 0

    init() {
        super.init(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        backgroundColor = .clear
        isOpaque = false
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        autoenablesDefaultLighting = false
        allowsCameraControl = false
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        orbitGesture.name = "PawPace garden orbit"
        orbitGesture.maximumNumberOfTouches = 1
        orbitGesture.delegate = self
        orbitGesture.isEnabled = false
        addGestureRecognizer(orbitGesture)
        zoomGesture.name = "PawPace garden zoom"
        zoomGesture.delegate = self
        zoomGesture.isEnabled = false
        addGestureRecognizer(zoomGesture)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.require(toFail: orbitGesture)
        tap.require(toFail: zoomGesture)
        addGestureRecognizer(tap)
        fallback.font = .systemFont(ofSize: 105)
        fallback.textAlignment = .center
        fallback.translatesAutoresizingMaskIntoConstraints = false
        fallback.isHidden = true
        addSubview(fallback)
        NSLayoutConstraint.activate([
            fallback.centerXAnchor.constraint(equalTo: centerXAnchor),
            fallback.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        visibilityChanged?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutChanged?(bounds.size)
    }

    func showFallback(_ species: PetSpecies?) {
        fallback.isHidden = species == nil
        fallback.text = species?.emoji
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === orbitGesture else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let velocity = orbitGesture.velocity(in: self)
        let translation = orbitGesture.translation(in: self)
        // Leave vertical drags to the enclosing SwiftUI ScrollView.
        let direction = translation == .zero ? velocity : translation
        let begins = onRotate != nil && abs(direction.x) > abs(direction.y)
        initialOrbitTranslation = begins ? translation.x : 0
        return begins
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === orbitGesture || gestureRecognizer === zoomGesture,
              let scrollView = other.view as? UIScrollView,
              other === scrollView.panGestureRecognizer else { return false }
        return isDescendant(of: scrollView)
    }

    @objc private func orbit(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
        // UIKit resets translation when recognition begins. Retain that first
        // movement so even a short/coalesced drag turns the garden immediately.
        let distance = gesture.state == .began ? initialOrbitTranslation : gesture.translation(in: self).x
        onRotate?(-Float(distance / max(bounds.width, 1)) * 2 * .pi)
        initialOrbitTranslation = 0
        gesture.setTranslation(.zero, in: self)
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
        onZoom?(Double(gesture.scale))
        gesture.scale = 1
    }

    private func updateAccessibilityActions() {
        var actions: [UIAccessibilityCustomAction] = []
        if onPet != nil { actions.append(UIAccessibilityCustomAction(name: "Pet and jump", target: self, selector: #selector(petCompanion))) }
        if onFeed != nil { actions.append(UIAccessibilityCustomAction(name: "Give a snack", target: self, selector: #selector(feedCompanion))) }
        if onPlay != nil { actions.append(UIAccessibilityCustomAction(name: "Play with the ball", target: self, selector: #selector(playWithCompanion))) }
        if onDecoration != nil {
            for item in placedKeepsakes {
                actions.append(UIAccessibilityCustomAction(name: "Visit \(item.decoration.rawValue), \(item.spot.title)") { [weak self] _ in
                    self?.onDecoration?(item.spot)
                    return self?.onDecoration != nil
                })
            }
        }
        if onRotate != nil {
            actions += [
                UIAccessibilityCustomAction(name: "Rotate garden left", target: self, selector: #selector(rotateLeft)),
                UIAccessibilityCustomAction(name: "Rotate garden right", target: self, selector: #selector(rotateRight))
            ]
        }
        if onZoom != nil {
            actions += [
                UIAccessibilityCustomAction(name: "Zoom in", target: self, selector: #selector(zoomIn)),
                UIAccessibilityCustomAction(name: "Zoom out", target: self, selector: #selector(zoomOut))
            ]
        }
        if onRotate != nil || onZoom != nil {
            actions.append(UIAccessibilityCustomAction(name: "Reset garden view", target: self, selector: #selector(resetGardenView)))
        }
        accessibilityCustomActions = actions
    }

    @objc private func zoomIn() -> Bool { onZoom?(CompanionCameraZoom.step); return onZoom != nil }
    @objc private func zoomOut() -> Bool { onZoom?(1 / CompanionCameraZoom.step); return onZoom != nil }
    @objc private func rotateLeft() -> Bool { onRotate?(-.pi / 4); return onRotate != nil }
    @objc private func rotateRight() -> Bool { onRotate?(.pi / 4); return onRotate != nil }
    @objc private func resetGardenView() -> Bool { onResetCamera?(); return onResetCamera != nil }
    @objc private func petCompanion() -> Bool { onPet?(); return onPet != nil }
    @objc private func feedCompanion() -> Bool { onFeed?(); return onFeed != nil }
    @objc private func playWithCompanion() -> Bool { onPlay?(); return onPlay != nil }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let hits = hitTest(point, options: nil)
        for result in hits {
            var node: SCNNode? = result.node
            while let current = node {
                if let name = current.name, name.hasPrefix("keepsake-"),
                   let spot = HabitatSpot(rawValue: String(name.dropFirst(9))), onDecoration != nil {
                    onDecoration?(spot); return
                }
                if current.name == "play-ball" { onPlay?(); return }
                if current.name == "food-bowl" { onFeed?(); return }
                if current.name == "pet-shadow" { break }
                if current.name == "habitat-pet" { onPet?(); return }
                if current.name == "habitat-ground", onDestination != nil {
                    // Tiny scene props retain a comfortable touch target.
                    if isNearProp("play-ball", point: point) { onPlay?(); return }
                    if isNearProp("food-bowl", point: point) { onFeed?(); return }
                    onDestination?(SIMD2(result.worldCoordinates.x, result.worldCoordinates.z))
                    return
                }
                node = current.parent
            }
        }
        if onDestination == nil, !hits.isEmpty { onPet?() }
    }

    private func isNearProp(_ name: String, point: CGPoint) -> Bool {
        guard let node = scene?.rootNode.childNode(withName: name, recursively: true), !node.isHidden else { return false }
        let projected = projectPoint(node.presentation.worldPosition)
        return hypot(CGFloat(projected.x) - point.x, CGFloat(projected.y) - point.y) < 22
    }
}

/// One zoom range is shared by pinch gestures, visible controls, and VoiceOver.
/// Magnification changes projection; it never scales the animal or its ground.
enum CompanionCameraZoom {
    static let minimum = 0.75
    static let maximum = 2.25
    static let standard = 1.0
    static let step = 1.2

    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return standard }
        return min(maximum, max(minimum, value))
    }
}

@MainActor
final class CompanionRig {
    let scene = SCNScene()
    let camera = SCNNode()
    private let locomotionRoot = SCNNode()
    private let modelRoot = SCNNode()
    private let poseRoot = SCNNode()
    private let shadow = SCNNode()
    private let ball = SCNNode()
    private let bowl = SCNNode()
    private let snack = SCNNode()
    var showsProps = false {
        didSet {
            ball.isHidden = !showsProps || lifeStage == .egg
            bowl.isHidden = !showsProps || lifeStage == .egg
        }
    }
    private let species: PetSpecies
    private let lifeStage: PetLifeStage
    private let variant: PetColorVariant
    private let height: Float
    private let modelScale: Float
    private var joints: [String: Joint] = [:]
    private var motionProfile: CompanionRigProfile?
    private var specialEffects: CompanionSpecialEffects?
    private var legs: [Leg] = []
    private var field: SCNNode?
    private var fieldDecoration = ""
    private var fieldPlacements: [HabitatPlacement] = []
    private var viewportAspect: Double = 1
    private var habitatYaw: Float = 0
    private var habitatZoom = CompanionCameraZoom.standard
    private var immersive = false
    private var plantedFeet: [String: (cycle: Int, position: SIMD3<Float>)] = [:]
    private var lastRoamingDistance: Float = 0
    private var lastRoamingYaw: Float = 0
    private var roamingPhase: Float = 0
    private var contactShadows: [(leg: Leg, node: SCNNode)] = []
    private let destinationMarker = SCNNode()
    private var guidedDestination: SIMD2<Float>?

    var walkCycleDistance: Float {
        let stance: Float = motionProfile?.stance ?? 0.64
        return max(0.04, 2 * walkingStride * modelScale / stance)
    }

    private var walkingStride: Float {
        min(height * 0.085, (legs.map(\.reach).min() ?? height * 0.35) * 0.24)
    }

    private var turningStrideRadius: Float {
        // Outer paws cover a much longer arc than the body's center when
        // turning on the spot. Counting that distance makes them lift and
        // replant before the shoulder has to twist beyond its natural reach.
        max(0.18, legs.map {
            let point = locomotionRoot.simdConvertPosition($0.restFoot, from: modelRoot)
            return simd_length(SIMD2(point.x, point.z))
        }.max() ?? 0.35) * 1.8
    }

    private struct Joint {
        let node: SCNNode
        let rest: simd_float4x4
        let modelOrientation: simd_quatf
    }

    private struct Leg {
        let pivots: [SCNNode]
        let foot: SCNNode
        let restFoot: SIMD3<Float>
        let footOrientation: simd_quatf
        let reach: Float
        let front: Bool
        let left: Bool
        let phase: Float
    }

    init?(species: PetSpecies, lifeStage: PetLifeStage = .adult, variant: PetColorVariant = .classic) {
        self.species = species
        self.lifeStage = lifeStage
        self.variant = variant
        // Eggs are a complete procedural companion, so they do not reveal or
        // depend on the hidden animal's mesh before hatching.
        if lifeStage == .egg {
            height = 1.2
            modelScale = 1
            locomotionRoot.name = "habitat-egg"
            scene.rootNode.addChildNode(locomotionRoot)
            configureStage()
            configureEgg()
            return
        }
        let assetURL = Bundle.main.url(forResource: species.rawValue, withExtension: "scn", subdirectory: "Animals")
            ?? Bundle.main.url(forResource: species.rawValue, withExtension: "scn")
        guard let assetURL,
              let source = try? SCNScene(url: assetURL, options: nil),
              let profile = CompanionRigProfile.load(for: species) else { return nil }
        motionProfile = profile
        if let yaw = profile.modelYawDegrees, yaw.isFinite, abs(yaw) > 0.001 {
            let alignment = SCNNode()
            alignment.name = "source-forward-alignment"
            alignment.simdEulerAngles.y = yaw * .pi / 180
            for node in source.rootNode.childNodes { alignment.addChildNode(node) }
            source.rootNode.addChildNode(alignment)
        }
        let bounds = source.rootNode.boundingBox
        let size = SIMD3<Float>(bounds.max) - SIMD3<Float>(bounds.min)
        height = max(size.y, 0.01)
        // Scale the entire model coordinate system, including foot anchors and
        // stride distance. Scaling only the mesh would detach a baby's paws.
        let growthScale: Float = lifeStage == .baby ? 0.68 : 1
        modelScale = growthScale * 1.66 / max(height, max(size.x * 1.12, size.z * 0.93))
        modelRoot.simdScale = SIMD3(repeating: modelScale)
        modelRoot.simdPosition = SIMD3(
            -(bounds.min.x + bounds.max.x) * 0.5 * modelScale,
            -bounds.min.y * modelScale,
            -(bounds.min.z + bounds.max.z) * 0.5 * modelScale
        )
        locomotionRoot.name = "habitat-pet"
        scene.rootNode.addChildNode(locomotionRoot)
        locomotionRoot.addChildNode(modelRoot)
        modelRoot.addChildNode(poseRoot)
        for node in source.rootNode.childNodes { poseRoot.addChildNode(node) }
        // Source files may contain imported humanoid clips. Only our custom
        // joint controller owns animation, including on the Mixamo penguin rig.
        var weightedBones = Set<String>()
        poseRoot.enumerateChildNodes { node, _ in
            node.skinner?.bones.compactMap(\.name).forEach { weightedBones.insert($0) }
        }
        poseRoot.enumerateChildNodes { node, _ in
            node.removeAllAnimations()
            if let name = node.name, weightedBones.contains(name) || profile.requiredJointNames.contains(name) {
                self.joints[name] = Joint(
                    node: node, rest: node.simdTransform,
                    modelOrientation: self.modelRoot.simdWorldOrientation.inverse * node.simdWorldOrientation
                )
            }
            node.geometry?.materials.forEach { material in
                material.lightingModel = .physicallyBased
                material.roughness.contents = 0.82
                material.metalness.contents = 0
                material.multiply.contents = self.phenotypeColor
                if self.variant != .classic {
                    // Tint luminance rather than the exported orange/beige fur.
                    // SceneKit applies the multiply color after this surface
                    // stage, retaining texture markings and physical lighting.
                    material.shaderModifiers = [.surface: """
                    #pragma body
                    float petLuminance = dot(_surface.diffuse.rgb, float3(0.2126, 0.7152, 0.0722));
                    _surface.diffuse.rgb = float3(petLuminance);
                    """]
                }
            }
        }
        guard profile.requiredJointNames.isSubset(of: Set(joints.keys)) else { return nil }
        configureLegs()
        guard legs.count == profile.legs.count else { return nil }
        let effects = CompanionSpecialEffects(species: species)
        specialEffects = effects
        locomotionRoot.addChildNode(effects.root)
        configureStage()
        configureProps()
        if variant.isRare { configureGeneticSparkles() }
        let ring = SCNTorus(ringRadius: 0.13, pipeRadius: 0.011)
        ring.ringSegmentCount = 32
        ring.pipeSegmentCount = 6
        ring.firstMaterial = propMaterial(UIColor(red: 0.94, green: 0.97, blue: 0.83, alpha: 1))
        destinationMarker.geometry = ring
        destinationMarker.name = "walk-destination"
        destinationMarker.opacity = 0.75
        destinationMarker.isHidden = true
        scene.rootNode.addChildNode(destinationMarker)
    }

    private func configureLegs() {
        guard let motionProfile else { return }
        for leg in motionProfile.legs {
            addLeg(leg.pivots, foot: leg.foot, front: leg.front, left: leg.left, phase: leg.phase)
        }
    }

    private func addLeg(_ names: [String], foot: String, front: Bool, left: Bool, phase: Float) {
        let pivots = names.compactMap { joints[$0]?.node }
        guard pivots.count == names.count, let endpoint = joints[foot] else { return }
        let points = (pivots + [endpoint.node]).map { modelRoot.simdConvertPosition(.zero, from: $0) }
        let reach = zip(points, points.dropFirst()).reduce(Float(0)) { $0 + simd_distance($1.0, $1.1) }
        guard reach > 0.0001, reach.isFinite else { return }
        legs.append(Leg(
            pivots: pivots, foot: endpoint.node, restFoot: points.last!,
            footOrientation: endpoint.modelOrientation, reach: reach,
            front: front, left: left, phase: phase
        ))
    }

    private func configureStage() {
        scene.background.contents = UIColor.clear
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        // Keep full ear / flipper silhouettes visible at the jump apex.
        camera.camera?.orthographicScale = 1.22
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 30
        camera.camera?.wantsHDR = true
        // A transparent habitat has no luminance backdrop for eye adaptation;
        // lock exposure so moving the head cannot bleach the white fur over time.
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.18
        camera.position = SCNVector3(2.35, 1.7, 4.8)
        camera.look(at: SCNVector3(0, 0.85, 0))
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 0.96, green: 0.97, blue: 1, alpha: 1)
        ambient.light?.intensity = 500
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = UIColor(red: 1, green: 0.95, blue: 0.87, alpha: 1)
        key.light?.intensity = 470
        key.eulerAngles = SCNVector3(-0.7, -0.6, -0.2)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 130
        rim.light?.color = UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1)
        rim.position = SCNVector3(-2, 2.5, -2)
        scene.rootNode.addChildNode(rim)

        let growthScale: CGFloat = lifeStage == .baby ? 0.68 : 1
        let plane = SCNPlane(
            width: lifeStage == .egg ? 1.45 : (species == .penguin ? 0.88 : 1.3) * growthScale,
            height: lifeStage == .egg ? 1.4 : (species == .penguin ? 0.66 : 1.45) * growthScale
        )
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Self.shadowTexture()
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        plane.firstMaterial = material
        shadow.geometry = plane
        shadow.name = "pet-shadow"
        shadow.eulerAngles.x = -.pi / 2
        shadow.position.y = 0.006
        shadow.renderingOrder = 1
        locomotionRoot.addChildNode(shadow)
        for leg in legs {
            let contact = SCNNode(geometry: SCNPlane(width: (species == .penguin ? 0.24 : 0.18) * growthScale, height: 0.24 * growthScale))
            contact.geometry?.firstMaterial = material
            contact.name = "pet-shadow"
            contact.eulerAngles.x = -.pi / 2
            contact.renderingOrder = 2
            contact.isHidden = true
            scene.rootNode.addChildNode(contact)
            contactShadows.append((leg, contact))
        }
    }

    func configureHabitat(roaming: Bool, decoration: String = "Flower Meadow", immersive: Bool = false, staticHabitat: Bool = false, placements: [HabitatPlacement] = []) {
        contactShadows.forEach { $0.node.isHidden = !roaming }
        if roaming || staticHabitat {
            if field == nil || fieldDecoration != decoration || self.immersive != immersive || fieldPlacements != placements {
                field?.removeFromParentNode()
                let node = CompanionField.make(decoration: decoration, immersive: immersive, placements: placements)
                scene.rootNode.addChildNode(node)
                field = node
                fieldDecoration = decoration
                fieldPlacements = placements
                self.immersive = immersive
            }
            updateProjection()
            updateHabitatCamera()
        } else if field != nil {
            field?.removeFromParentNode()
            field = nil
            clearDestination()
            locomotionRoot.simdTransform = matrix_identity_float4x4
            plantedFeet.removeAll()
            lastRoamingDistance = 0
            lastRoamingYaw = 0
            roamingPhase = 0
            camera.camera?.orthographicScale = 1.22
            camera.position = SCNVector3(2.35, 1.7, 4.8)
            camera.look(at: SCNVector3(0, 0.85, 0))
        }
    }

    func configurePortrait(facesViewer: Bool) {
        guard field == nil else { return }
        camera.position = facesViewer ? SCNVector3(0, 1.45, 5.4) : SCNVector3(2.35, 1.7, 4.8)
        camera.look(at: SCNVector3(0, 0.85, 0))
    }

    func resizeViewport(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let aspect = Double(size.width / size.height)
        guard aspect.isFinite, aspect > 0 else { return }
        viewportAspect = aspect
        updateProjection()
    }

    func setHabitatZoom(_ zoom: Double) {
        guard zoom.isFinite else { return }
        habitatZoom = CompanionCameraZoom.clamped(zoom)
        updateProjection()
        if field != nil { updateHabitatCamera() }
    }

    private func updateProjection() {
        guard field != nil else {
            camera.camera?.orthographicScale = 1.22
            return
        }
        // The immersive garden extends beyond the viewport. Retain enough
        // horizontal room for a full-grown companion on a tall phone display.
        let base: Double
        if immersive {
            // Framing is authored with each rig's fully deformed silhouette:
            // long tails need horizontal room when the player orbits, while
            // tall ears and horns need room above a jump. Keep the same zoom
            // ratio at every step, including the closest view on narrow phones.
            let framing: (vertical: Double, horizontal: Double)
            if lifeStage == .adult {
                switch species {
                case .corgi: framing = (3.7, 2.4)
                case .redPanda: framing = (3.35, 2.1)
                case .fox, .dragon: framing = (2.95, 2.2)
                case .axolotl: framing = (2.95, 2.6)
                case .unicorn: framing = (3.5, 2.6)
                default: framing = (2.95, 1.7)
                }
            } else {
                framing = (2.95, 1.7)
            }
            base = max(framing.vertical, framing.horizontal / viewportAspect)
        } else {
            base = 2.85 * max(1, 1.08 / viewportAspect)
        }
        camera.camera?.orthographicScale = base / habitatZoom
    }

    /// Orbit the camera instead of rotating the scene, so taps, planted feet,
    /// and roaming destinations stay in the same world coordinate system.
    func setHabitatYaw(_ yaw: Float) {
        guard yaw.isFinite else { return }
        habitatYaw = yaw.truncatingRemainder(dividingBy: 2 * .pi)
        if field != nil { updateHabitatCamera() }
    }

    private func updateHabitatCamera() {
        let radius: Float = sqrt(3.3 * 3.3 + 7.2 * 7.2)
        let angle = atan2(Float(3.3), Float(7.2)) + habitatYaw
        let follow = immersive ? Float(1) : min(1, max(0, Float(habitatZoom - 1) / 0.7))
        let position = locomotionRoot.simdPosition
        let target = SIMD3<Float>(position.x * follow, 0.32 + 0.33 * follow, position.z * follow)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        camera.simdPosition = target + SIMD3(sin(angle) * radius, 5.48, cos(angle) * radius)
        camera.look(at: SCNVector3(target), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        SCNTransaction.commit()
    }

    func showDestination(_ position: SIMD2<Float>) {
        guard lifeStage != .egg else { return }
        guidedDestination = position
        destinationMarker.simdPosition = SIMD3(position.x, 0.014, position.y)
        destinationMarker.isHidden = false
    }

    func clearDestination() {
        guidedDestination = nil
        destinationMarker.isHidden = true
    }

    private static func shadowTexture() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128))
        return renderer.image { context in
            let colors = [UIColor(red: 0.12, green: 0.22, blue: 0.18, alpha: 0.34).cgColor,
                          UIColor(red: 0.12, green: 0.22, blue: 0.18, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.cgContext.drawRadialGradient(
                gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 3,
                endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: []
            )
        }
    }

    func pose(time: Float, phase: Float, weights: SIMD4<Float>, feeding: Float = 0, actionTime: Float? = nil, jumpTime: Float? = nil, roaming: CompanionRoamingPose? = nil, specialTime: Float = 0, specialWeight: Float = 0, celebrationWeight: Float = 0) {
        // Incubating eggs stay in their nest, even when the surrounding field
        // is interactive or a workout preview requests a running pose.
        guard lifeStage != .egg else { return }
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        var phase = phase
        if let roaming {
            let distance = max(0, roaming.gaitDistance - lastRoamingDistance)
            let turn = abs(atan2(sin(roaming.yaw - lastRoamingYaw), cos(roaming.yaw - lastRoamingYaw)))
            roamingPhase += max(distance, turn * turningStrideRadius) / walkCycleDistance
            lastRoamingDistance = roaming.gaitDistance
            lastRoamingYaw = roaming.yaw
            phase = roamingPhase
            locomotionRoot.simdPosition = SIMD3(roaming.position.x, 0, roaming.position.y)
            locomotionRoot.simdEulerAngles = SIMD3(0, roaming.yaw, 0)
            if let guidedDestination, simd_distance(roaming.position, guidedDestination) < 0.13 {
                clearDestination()
            }
        } else {
            plantedFeet.removeAll()
        }
        if field != nil && (immersive || habitatZoom > 1) { updateHabitatCamera() }
        joints.values.forEach { $0.node.simdTransform = $0.rest }
        let special = CompanionSpecialEffects.pose(species: species, time: specialTime, weight: specialWeight)
        let travel = min(weights.x + weights.y, 1)
        let angle = phase * 2 * Float.pi
        let actionClock = actionTime ?? time
        let jumpPhase = ((jumpTime ?? actionClock) * 0.76).truncatingRemainder(dividingBy: 1)
        let airborne = smoothArc(jumpPhase, start: 0.22, end: 0.78)
        let crouchArc = sin(min(jumpPhase / 0.22, 1) * .pi)
        let crouch = crouchArc * crouchArc * (jumpPhase < 0.22 ? 1 : 0)
        let jump = weights.z * (airborne * 0.19 - crouch * 0.025)
        let bunnyHop = motionProfile?.gait == .bounding ? pow(max(0, sin(angle)), 2) * travel * 0.042 : 0
        let bodyLift = height * (jump + bunnyHop + travel * 0.006 * (1 - cos(angle * 2)))
        let waddle = motionProfile?.isBiped == true ? sin(angle) * travel * 0.055 : 0
        poseRoot.simdPosition = SIMD3(0, bodyLift, 0)
        poseRoot.simdEulerAngles = SIMD3(
            -sin(angle) * weights.y * 0.024 + sin(time * 3) * weights.w * 0.022,
            sin(time * 2.5) * weights.w * 0.04,
            waddle
        )
        var secondary = secondaryMotion(
            time: time, angle: angle, actionClock: actionClock,
            jumpPhase: jumpPhase, airborne: airborne, crouch: crouch,
            weights: weights, feeding: feeding
        )
        // A learned victory dance: grounded side-to-side balance and a head
        // wiggle, distinct from chasing the play ball. Blend back to rest.
        let dance = min(max(celebrationWeight, 0), 1)
        secondary.head.z += sin(actionClock * 5) * 0.12 * dance
        secondary.head.y += sin(actionClock * 2.5) * 0.16 * dance
        secondary.torso.z += sin(actionClock * 5) * 0.035 * dance
        secondary.tail.y += sin(actionClock * 8) * 0.25 * dance
        secondary.head += special.head
        secondary.tail += special.tail
        secondary.flippers += special.wing
        if let roaming {
            // Eyes/head lead the turn; shoulders and tail follow the body.
            secondary.head.y += roaming.lookYaw
            secondary.torso.z -= min(max(roaming.turnRate * roaming.speed * 0.05, -0.035), 0.035)
            secondary.tail.y -= min(max(roaming.turnRate * 0.055, -0.08), 0.08)
        }
        // Move the chest/pelvis before solving the feet, so secondary body
        // motion cannot pull a planted paw off the ground afterward.
        animateTorso(secondary)

        for leg in legs {
            let runPhase: Float = leg.front == leg.left ? 0 : 0.5
            let offset = motionProfile?.gait == .quadruped ? leg.phase + (runPhase - leg.phase) * weights.y : leg.phase
            let cycle = (phase + offset).truncatingRemainder(dividingBy: 1)
            let stance: Float = motionProfile?.stance ?? 0.64
            let stride = (roaming == nil ? min(height * 0.085, leg.reach * 0.24) : walkingStride) * (1 + weights.y * 0.28)
            var target = leg.restFoot
            if cycle < stance {
                target.z += stride * (1 - 2 * (roaming == nil ? smoothStep(cycle / stance) : cycle / stance)) * travel
            } else {
                let swing = (cycle - stance) / (1 - stance)
                if roaming != nil {
                    // Match the backward ground-contact velocity at lift-off
                    // and landing, then smoothly bring the paw forward.
                    let tangent = -2 * (1 - stance) / stance
                    let t2 = swing * swing
                    let t3 = t2 * swing
                    target.z += stride * (-1 + 6 * t2 - 4 * t3 + tangent * (2 * t3 - 3 * t2 + swing)) * travel
                } else {
                    target.z += stride * (-1 + 2 * smoothStep(swing)) * travel
                }
                let footArc = sin(swing * .pi)
                target.y += footArc * footArc * min(height * 0.055, leg.reach * 0.17) * travel
            }
            // Ground targets remain fixed in model space during the stance.
            // Lift every foot with the body only during a deliberate jump/hop.
            target.y += height * (max(jump, 0) + bunnyHop * 0.65)
            target.z -= weights.z * airborne * leg.reach * (leg.front ? 0.08 : 0.13)
            // Draw the paws toward the belly during a flourish. The skeleton
            // joins the leap/roll instead of hanging in a rigid translated pose.
            let specialTuck = min(1, max(0, special.lift / 0.2))
            target.y += leg.reach * specialTuck * 0.16
            target.z -= leg.reach * specialTuck * (leg.front ? 0.10 : 0.17)
            if motionProfile?.isBiped != true && leg.front && (!leg.left || species == .bunny) {
                target.y += weights.w * leg.reach * (0.10 + max(0, sin(actionClock * 7)) * 0.14)
                target.z += weights.w * leg.reach * 0.1
            }
            if motionProfile?.isBiped == true && leg.left {
                target.z += weights.w * leg.reach * max(0, sin(actionClock * 7)) * 0.20
                target.y += weights.w * leg.reach * max(0, sin(actionClock * 7)) * 0.10
            }
            if roaming != nil, let name = leg.foot.name {
                if cycle < stance, travel > 0.35, weights.z < 0.05, weights.w < 0.1, feeding < 0.1, specialWeight < 0.05 {
                    let cycleIndex = Int(floor(phase + offset))
                    if plantedFeet[name]?.cycle != cycleIndex {
                        plantedFeet[name] = (cycleIndex, modelRoot.simdConvertPosition(target, to: nil))
                    }
                    if let anchor = plantedFeet[name] {
                        target = modelRoot.simdConvertPosition(anchor.position, from: nil)
                    }
                } else {
                    plantedFeet[name] = nil
                }
            }
            solve(leg, target: target)
        }

        animateHeadAndTail(secondary, time: time, angle: angle, actionClock: actionClock, weights: weights, feeding: feeding)
        if let jaw = motionProfile?.jaw { rotate(jaw, angles: SIMD3(special.jaw, 0, 0)) }
        // Apply a flourish after the grounded leg solution. A roll pivots about
        // the torso rather than the feet, and returns exactly to the bind pose.
        if specialWeight > 0.001 {
            let pivot = SIMD3<Float>(0, height * 0.45, 0)
            let rotation = simd_quatf(angle: special.roll, axis: SIMD3(0, 0, 1))
                * simd_quatf(angle: special.pitch, axis: SIMD3(1, 0, 0))
            poseRoot.simdPosition += pivot - rotation.act(pivot) + SIMD3(0, height * special.lift, 0)
            poseRoot.simdOrientation = rotation * poseRoot.simdOrientation
        }
        let mouthJoint = motionProfile?.head.last.flatMap { joints[$0.name] }
        let offset = motionProfile?.muzzleOffset ?? [0, 0, 0.12]
        let mouthBase = mouthJoint.map { modelRoot.simdConvertPosition(.zero, from: $0.node) } ?? SIMD3(0, height * 0.7, 0)
        let mouthRotation = mouthJoint.map {
            modelRoot.simdWorldOrientation.inverse * $0.node.simdWorldOrientation * $0.modelOrientation.inverse
        } ?? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        let mouth = locomotionRoot.simdConvertPosition(mouthBase + mouthRotation.act(SIMD3(offset[0], offset[1], offset[2]) * height), from: modelRoot)
        let breathDirection = locomotionRoot.simdConvertVector(mouthRotation.act(SIMD3(0, 0, 1)), from: modelRoot)
        specialEffects?.update(time: specialTime, weight: specialWeight, muzzle: mouth,
                               growthScale: lifeStage == .baby ? 0.68 : 1, direction: breathDirection)
        let lift = max((bodyLift + height * special.lift) * modelScale, 0)
        shadow.opacity = CGFloat(max(0.30, 1 - lift * 1.3))
        shadow.simdScale = SIMD3(repeating: 1 - min(lift * 0.5, 0.28))
        if roaming != nil {
            for contact in contactShadows {
                let foot = contact.leg.foot.simdWorldPosition
                let restY = modelRoot.simdConvertPosition(contact.leg.restFoot, to: nil).y
                contact.node.simdPosition = SIMD3(foot.x, 0.009, foot.z)
                contact.node.eulerAngles.y = locomotionRoot.eulerAngles.y
                contact.node.opacity = CGFloat(max(0, 1 - max(0, foot.y - restY) * 9))
            }
        }
        animateProps(time: actionClock, play: weights.w, feeding: feeding, roaming: roaming)
    }

    private struct SecondaryMotion {
        var head = SIMD3<Float>.zero // pitch, yaw, roll in model space
        var tail = SIMD3<Float>.zero
        var torso = SIMD3<Float>.zero
        var ears: Float = 0
        var flippers: Float = 0
    }

    private func secondaryMotion(
        time: Float, angle: Float, actionClock: Float,
        jumpPhase: Float, airborne: Float, crouch: Float,
        weights: SIMD4<Float>, feeding: Float
    ) -> SecondaryMotion {
        let travel = min(weights.x + weights.y, 1)
        let idle = max(0, 1 - travel - weights.z - weights.w - feeding)
        let landing = smoothArc(jumpPhase, start: 0.78, end: 1)
        let jumpAngle = jumpPhase * 2 * Float.pi
        let toyAngle = actionClock * 2 * Float.pi * 1.1
        var pose = SecondaryMotion()

        // Each layer keeps its own fixed-frequency phase. Blend amplitudes,
        // never frequency, so entering play cannot make a wag jump in time.
        pose.head = SIMD3(
            sin(time * 1.8) * 0.035,
            sin(time * 1.15) * 0.085,
            sin(time * 1.4 - 0.35) * 0.035
        ) * idle
        pose.head += SIMD3(
            sin(angle * 2 - 0.65) * (species == .bunny ? 0.085 : 0.055),
            -sin(angle - 0.25) * 0.045,
            -sin(angle) * (species == .penguin ? 0.055 : 0.03)
        ) * travel
        pose.head.x += sin(angle * 2 - 0.8) * weights.y * 0.035
        pose.head += SIMD3(
            crouch * 0.13 - airborne * 0.12 + landing * 0.10,
            sin(jumpAngle) * 0.055,
            sin(jumpAngle - 0.35) * 0.035
        ) * weights.z
        pose.head += SIMD3(
            -0.045 - sin(toyAngle) * 0.065,
            0.13 + sin(toyAngle - 0.5) * 0.085,
            sin(toyAngle * 0.5) * 0.065
        ) * weights.w
        pose.head += SIMD3(
            0.14 + sin(actionClock * 8) * 0.055,
            -0.17 + sin(actionClock * 3) * 0.035,
            sin(actionClock * 4) * 0.035
        ) * feeding

        pose.tail = SIMD3(
            sin(time * 2.2 - 0.7) * 0.07,
            sin(time * 2.6 - 0.4) * 0.20,
            0
        ) * idle
        pose.tail += SIMD3(
            sin(angle * 2 - 1.1) * 0.11,
            sin(angle - 0.7) * (0.23 + weights.y * 0.08),
            0
        ) * travel
        pose.tail += SIMD3(
            -crouch * 0.15 + airborne * 0.20 - landing * 0.15,
            sin(jumpAngle - 0.65) * 0.19,
            0
        ) * weights.z
        pose.tail += SIMD3(
            sin(toyAngle - 0.7) * 0.10,
            sin(actionClock * 10 - 0.55) * 0.38,
            0
        ) * weights.w
        pose.tail += SIMD3(
            sin(actionClock * 4 - 0.7) * 0.08,
            sin(actionClock * 5 - 0.6) * 0.22,
            0
        ) * feeding

        pose.torso = SIMD3(
            sin(time * 1.8) * 0.012 * idle + sin(angle * 2 - 0.3) * 0.022 * travel,
            -sin(angle - 0.25) * 0.018 * travel,
            sin(time * 1.4) * 0.009 * idle + sin(angle) * 0.015 * travel
        )
        pose.torso.x += weights.z * (crouch * 0.025 - airborne * 0.035 + landing * 0.03)
        pose.torso.x += weights.w * sin(toyAngle) * 0.02 + feeding * sin(actionClock * 4) * 0.02
        pose.torso.y += weights.w * sin(toyAngle * 0.5) * 0.025 + feeding * sin(actionClock * 3) * 0.018
        pose.ears = sin(time * 2.1) * 0.035 * idle + sin(angle - 0.9) * 0.12 * travel
        pose.ears += weights.z * (crouch * 0.08 - airborne * 0.14 + landing * 0.12)
        pose.ears += weights.w * sin(toyAngle - 0.7) * 0.095 + feeding * sin(actionClock * 4 - 0.4) * 0.065
        pose.flippers = sin(time * 1.8) * 0.025 * idle + 0.06 * travel
        pose.flippers += weights.z * (airborne * 0.20 + landing * 0.08)
        pose.flippers += weights.w * (0.18 + sin(actionClock * 10) * 0.12) + feeding * (0.055 + sin(actionClock * 4) * 0.035)
        return pose
    }

    private func animateTorso(_ motion: SecondaryMotion) {
        switch species {
        case .corgi:
            rotate("Bone_020", angles: motion.torso)
        case .bunny:
            rotate("Bone_008", angles: motion.torso)
        case .penguin:
            // This Meshy/Mixamo rig has no tail joint. Its rear silhouette is
            // weighted to Hips/Spine: animate that real pelvis, with a smaller
            // counter-rotation above it, rather than inventing a rigid tail.
            let rear = SIMD3(motion.tail.x * 0.24, motion.tail.y * 0.22, motion.torso.z)
            rotate("mixamorig:Hips", angles: rear)
            rotate("mixamorig:Spine", angles: motion.torso - rear * 0.45)
        default:
            for joint in motionProfile?.torso ?? [] { rotate(joint.name, angles: motion.torso * joint.weight) }
            for joint in motionProfile?.tail ?? [] { rotate(joint.name, angles: motion.tail * joint.weight) }
        }
    }

    private func animateHeadAndTail(
        _ motion: SecondaryMotion, time: Float, angle: Float, actionClock: Float,
        weights: SIMD4<Float>, feeding: Float
    ) {
        switch species {
        case .corgi:
            // 024 is the neck base; 022/021 carry most face/skull weights.
            // Split articulation so a head turn bends the neck naturally.
            rotate("Bone_024", angles: motion.head * 0.40)
            rotate("Bone_022", angles: motion.head * 0.60)
            rotate("Bone_011", angles: motion.tail)
            rotate("Bone_010", angles: SIMD3(motion.tail.x * 0.35, motion.tail.y * 0.30, 0))
        case .bunny:
            // 023 is the neck base; 022 parents the weighted face and ears.
            rotate("Bone_023", angles: motion.head * 0.30)
            rotate("Bone_022", angles: motion.head * 0.70)
            rotate("Bone_003", angles: motion.tail * 0.80)
            rotate("Bone_038", angles: SIMD3(motion.ears, 0, motion.head.z * 0.25))
            rotate("Bone_041", angles: SIMD3(motion.ears * 0.82, 0, -motion.head.z * 0.22))
            rotate("Bone_037", angles: SIMD3(-motion.ears * 0.24, 0, 0))
            rotate("Bone_040", angles: SIMD3(-motion.ears * 0.20, 0, 0))
        case .penguin:
            rotate("mixamorig:Neck", angles: motion.head * 0.25)
            rotate("mixamorig:Head", angles: motion.head * 0.75)
            let travel = min(weights.x + weights.y, 1)
            for (name, side) in [("LeftArm", Float(1)), ("RightArm", Float(-1))] {
                rotate("mixamorig:" + name, angles: SIMD3(
                    sin(angle + side * .pi / 2) * travel * 0.10
                        + sin(time * 1.8) * 0.015 + feeding * sin(actionClock * 4) * 0.025,
                    0, side * (0.04 + motion.flippers)
                ))
            }
        default:
            for joint in motionProfile?.head ?? [] { rotate(joint.name, angles: motion.head * joint.weight) }
            for joint in motionProfile?.ears ?? [] { rotate(joint.name, angles: SIMD3(motion.ears * joint.weight, 0, 0)) }
            for (wing, side) in [(motionProfile?.leftWing ?? [], Float(1)), (motionProfile?.rightWing ?? [], Float(-1))] {
                for joint in wing {
                    rotate(joint.name, angles: SIMD3(sin(angle) * min(1, weights.x + weights.y) * 0.08, 0, side * motion.flippers) * joint.weight)
                }
            }
        }
    }

    /// Stable semantic observations keep tests independent of exporter names.
    var articulatedJointNames: (head: String?, rear: String?, leg: String?) {
        (motionProfile?.head.last?.name, motionProfile?.tail.first?.name ?? motionProfile?.torso.first?.name,
         motionProfile?.legs.first?.pivots.last)
    }

    /// Internal, deterministic observation for animation regression tests.
    func jointPositions() -> [String: SIMD3<Float>] {
        joints.mapValues { modelRoot.simdConvertPosition(.zero, from: $0.node) }
    }

    private var phenotypeColor: UIColor {
        switch variant {
        case .classic: return .white
        case .mint: return UIColor(red: 0.61, green: 0.94, blue: 0.78, alpha: 1)
        case .peach: return UIColor(red: 1, green: 0.70, blue: 0.61, alpha: 1)
        case .lavender: return UIColor(red: 0.79, green: 0.66, blue: 1, alpha: 1)
        case .sky: return UIColor(red: 0.63, green: 0.83, blue: 1, alpha: 1)
        case .moonlight: return UIColor(red: 0.81, green: 0.89, blue: 1, alpha: 1)
        case .aurora: return UIColor(red: 0.78, green: 0.95, blue: 0.83, alpha: 1)
        }
    }

    private func configureEgg() {
        let shell = SCNNode(geometry: Self.eggGeometry())
        shell.name = "mystery-egg-shell"
        shell.geometry?.firstMaterial = propMaterial(UIColor(red: 1, green: 0.96, blue: 0.84, alpha: 1))
        locomotionRoot.addChildNode(shell)

        let spotColors = [
            UIColor(red: 0.76, green: 0.71, blue: 0.94, alpha: 1),
            UIColor(red: 0.63, green: 0.84, blue: 0.73, alpha: 1),
            UIColor(red: 0.98, green: 0.74, blue: 0.68, alpha: 1)
        ]
        let spots: [(Float, Float, CGFloat)] = [
            (0.80, 0.90, 0.09), (1.47, 1.15, 0.105), (1.92, 0.45, 0.075),
            (1.10, 2.20, 0.075), (1.95, 2.10, 0.085), (1.35, 3.70, 0.09),
            (1.80, 4.80, 0.08), (0.88, 5.50, 0.065)
        ]
        for (index, spot) in spots.enumerated() {
            let (theta, phi, size) = spot
            let radius = 0.46 * sin(theta) * (1 - 0.16 * cos(theta))
            let slope = 0.46 * (cos(theta) * (1 - 0.16 * cos(theta)) + 0.16 * sin(theta) * sin(theta))
            let normal = simd_normalize(SIMD3<Float>(0.60 * sin(theta) * cos(phi), slope, 0.60 * sin(theta) * sin(phi)))
            let patch = SCNSphere(radius: size)
            patch.segmentCount = 20
            patch.firstMaterial = propMaterial(spotColors[index % spotColors.count])
            let node = SCNNode(geometry: patch)
            node.simdScale = SIMD3(1, 0.78, 0.16)
            node.simdPosition = SIMD3(radius * cos(phi), 0.73 + 0.60 * cos(theta), radius * sin(phi)) + normal * 0.004
            node.simdOrientation = simd_quatf(from: SIMD3(0, 0, 1), to: normal)
            locomotionRoot.addChildNode(node)
        }

        // Soft grass and a little woven rim keep the egg grounded without
        // exposing the species or the inherited rarity hidden inside it.
        let grass = SCNSphere(radius: 0.62)
        grass.segmentCount = 32
        grass.firstMaterial = propMaterial(UIColor(red: 0.72, green: 0.83, blue: 0.56, alpha: 1))
        let cushion = SCNNode(geometry: grass)
        cushion.scale = SCNVector3(1, 0.12, 0.87)
        cushion.position.y = 0.075
        locomotionRoot.addChildNode(cushion)
        for index in 0..<3 {
            let ring = SCNTorus(ringRadius: 0.46 + CGFloat(index) * 0.025, pipeRadius: 0.035)
            ring.ringSegmentCount = 48
            ring.pipeSegmentCount = 10
            ring.firstMaterial = propMaterial(UIColor(red: 0.82 + CGFloat(index) * 0.025, green: 0.75 + CGFloat(index) * 0.025, blue: 0.52, alpha: 1))
            let strand = SCNNode(geometry: ring)
            strand.scale = SCNVector3(1, 0.7, 0.87)
            strand.position.y = 0.11 + Float(index) * 0.024
            locomotionRoot.addChildNode(strand)
        }
        for index in 0..<12 {
            let angle = Float(index) * .pi / 6
            let leaf = SCNSphere(radius: 0.12)
            leaf.segmentCount = 12
            leaf.firstMaterial = propMaterial(index.isMultiple(of: 2)
                ? UIColor(red: 0.57, green: 0.76, blue: 0.52, alpha: 1)
                : UIColor(red: 0.75, green: 0.85, blue: 0.60, alpha: 1))
            let blade = SCNNode(geometry: leaf)
            blade.scale = SCNVector3(0.60, 0.19, 1.25)
            blade.position = SCNVector3(sin(angle) * 0.54, 0.065, cos(angle) * 0.47)
            blade.eulerAngles.y = angle
            locomotionRoot.addChildNode(blade)
        }
    }

    private static func eggGeometry() -> SCNGeometry {
        let latitudeCount = 28
        let longitudeCount = 48
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for latitude in 0...latitudeCount {
            let theta = Float(latitude) / Float(latitudeCount) * .pi
            let radius = 0.46 * sin(theta) * (1 - 0.16 * cos(theta))
            let slope = 0.46 * (cos(theta) * (1 - 0.16 * cos(theta)) + 0.16 * sin(theta) * sin(theta))
            for longitude in 0...longitudeCount {
                let phi = Float(longitude) / Float(longitudeCount) * 2 * .pi
                vertices.append(SCNVector3(radius * cos(phi), 0.73 + 0.60 * cos(theta), radius * sin(phi)))
                normals.append(SCNVector3(simd_normalize(SIMD3<Float>(0.60 * sin(theta) * cos(phi), slope, 0.60 * sin(theta) * sin(phi)))))
                if latitude < latitudeCount, longitude < longitudeCount {
                    let a = Int32(latitude * (longitudeCount + 1) + longitude)
                    let b = a + Int32(longitudeCount + 1)
                    indices += [a, a + 1, b, b, a + 1, b + 1]
                }
            }
        }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }

    private func configureGeneticSparkles() {
        let growthScale: Float = lifeStage == .baby ? 0.68 : 1
        let positions = [SIMD3<Float>(-0.59, 0.98, 0), SIMD3<Float>(0.56, 0.72, 0.16), SIMD3<Float>(0.28, 1.35, -0.2)]
        for (index, position) in positions.enumerated() {
            let outline = UIBezierPath()
            for point in 0..<8 {
                let angle = CGFloat(point) * .pi / 4
                let radius: CGFloat = point.isMultiple(of: 2) ? 0.065 : 0.023
                let vertex = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                if point == 0 { outline.move(to: vertex) } else { outline.addLine(to: vertex) }
            }
            outline.close()
            let star = SCNShape(path: outline, extrusionDepth: 0.012)
            star.chamferRadius = 0.004
            let color = variant == .moonlight
                ? UIColor(red: 0.87, green: 0.92, blue: 1, alpha: 1)
                : [UIColor(red: 0.78, green: 0.96, blue: 0.87, alpha: 1), UIColor(red: 0.89, green: 0.76, blue: 0.98, alpha: 1), UIColor(red: 1, green: 0.89, blue: 0.66, alpha: 1)][index]
            star.firstMaterial = propMaterial(color)
            let node = SCNNode(geometry: star)
            node.name = "genetic-sparkle"
            node.simdPosition = position * growthScale
            node.simdScale = SIMD3(repeating: growthScale)
            node.constraints = [SCNBillboardConstraint()]
            // Static accents respect Reduce Motion and never need their own
            // animation clock or a replacement copy of the animal rig.
            locomotionRoot.addChildNode(node)
        }
    }

    private func configureProps() {
        ball.name = "play-ball"
        let sphere = SCNSphere(radius: 0.105)
        sphere.segmentCount = 28
        sphere.firstMaterial = propMaterial(UIColor(red: 0.94, green: 0.66, blue: 0.71, alpha: 1))
        ball.geometry = sphere
        let stripe = SCNTorus(ringRadius: 0.103, pipeRadius: 0.009)
        stripe.firstMaterial = propMaterial(UIColor(red: 1, green: 0.9, blue: 0.65, alpha: 1))
        let stripeNode = SCNNode(geometry: stripe)
        stripeNode.eulerAngles.z = .pi / 4
        ball.addChildNode(stripeNode)
        ball.position = SCNVector3(0.62, 0.11, 0.54)
        ball.isHidden = true
        scene.rootNode.addChildNode(ball)

        bowl.name = "food-bowl"
        let dish = SCNCylinder(radius: 0.16, height: 0.06)
        dish.radialSegmentCount = 32
        dish.firstMaterial = propMaterial(UIColor(red: 0.65, green: 0.76, blue: 0.88, alpha: 1))
        bowl.geometry = dish
        let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.143, pipeRadius: 0.023))
        rim.geometry?.firstMaterial = propMaterial(UIColor(red: 0.86, green: 0.91, blue: 0.98, alpha: 1))
        rim.position.y = 0.029
        bowl.addChildNode(rim)
        let food = SCNSphere(radius: 0.115)
        food.firstMaterial = propMaterial(UIColor(red: 0.88, green: 0.65, blue: 0.37, alpha: 1))
        let foodNode = SCNNode(geometry: food)
        foodNode.scale = SCNVector3(1, 0.15, 1)
        foodNode.position.y = 0.029
        bowl.addChildNode(foodNode)
        let morsel = SCNSphere(radius: 0.037)
        morsel.firstMaterial = propMaterial(UIColor(red: 0.96, green: 0.57, blue: 0.24, alpha: 1))
        snack.geometry = morsel
        snack.position.y = 0.07
        bowl.addChildNode(snack)
        bowl.position = SCNVector3(-0.60, 0.035, 0.55)
        bowl.isHidden = true
        scene.rootNode.addChildNode(bowl)
    }

    private func propMaterial(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = 0.72
        material.lightingModel = .physicallyBased
        return material
    }

    private func animateProps(time: Float, play: Float, feeding: Float, roaming: CompanionRoamingPose?) {
        // A short roll toward the front paw, followed by a bounce away from it.
        // The paw lift and head turn use this same clock, so the response has a
        // visible object and the tap is more than an unrelated whole-body wiggle.
        let ballPhase = (time * 1.1).truncatingRemainder(dividingBy: 1)
        let kick = sin(ballPhase * .pi)
        ball.simdPosition = SIMD3(0.62 - play * kick * 0.37, 0.11 + play * kick * kick * 0.25, 0.54 + play * sin(ballPhase * 2 * .pi) * 0.10)
        ball.simdEulerAngles = SIMD3(time * play * 4, 0, -time * play * 5)
        snack.simdPosition = SIMD3(feeding * (0.19 + sin(time * 5) * 0.015), 0.07 + feeding * (0.16 + max(0, sin(time * 5)) * 0.08), feeding * 0.015)
        snack.simdScale = SIMD3(repeating: 1 - feeding * (0.15 + max(0, sin(time * 8)) * 0.15))
        if let roaming {
            let ballBase = CompanionRoaming.ballPosition
            let bowlBase = CompanionRoaming.bowlPosition
            let forward = SIMD2<Float>(sin(roaming.yaw), cos(roaming.yaw))
            let rolling = forward * play * kick * 0.23
            ball.simdPosition = SIMD3(ballBase.x + rolling.x, 0.11 + play * kick * kick * 0.13, ballBase.y + rolling.y)
            bowl.simdPosition = SIMD3(bowlBase.x, 0.035, bowlBase.y)
            snack.simdPosition = SIMD3(-forward.x * feeding * 0.13, 0.07 + feeding * (0.13 + max(0, sin(time * 5)) * 0.08), -forward.y * feeding * 0.13)
        } else {
            bowl.simdPosition = SIMD3(-0.60, 0.035, 0.55)
        }
    }

    /// Constrained cyclic coordinate descent in the animal's sagittal plane.
    /// The axes are transformed from model space into each bone's parent space;
    /// the exporter gives left and right legs different local orientations.
    private func solve(_ leg: Leg, target: SIMD3<Float>) {
        var angles = Array(repeating: Float(0), count: leg.pivots.count)
        var hipAbduction: Float = 0
        for _ in 0..<7 {
            for index in leg.pivots.indices.reversed() {
                let joint = leg.pivots[index]
                let origin = modelRoot.simdConvertPosition(.zero, from: joint)
                let endpoint = modelRoot.simdConvertPosition(.zero, from: leg.foot)
                if index == 0 {
                    // A small shoulder/hip side bend lets a planted paw remain
                    // in place while the body turns above it. Knees keep their
                    // sagittal constraint instead of twisting sideways.
                    let currentSide = atan2(endpoint.x - origin.x, origin.y - endpoint.y)
                    let targetSide = atan2(target.x - origin.x, origin.y - target.y)
                    let sideDelta = atan2(sin(targetSide - currentSide), cos(targetSide - currentSide))
                    let next = min(max(hipAbduction + sideDelta * 0.72, -0.30), 0.30)
                    rotate(joint, axis: SIMD3(0, 0, 1), angle: next - hipAbduction)
                    hipAbduction = next
                }
                let current = SIMD2(endpoint.y - origin.y, endpoint.z - origin.z)
                let desired = SIMD2(target.y - origin.y, target.z - origin.z)
                guard simd_length_squared(current) > 0.00000001, simd_length_squared(desired) > 0.00000001 else { continue }
                let delta = atan2(current.x * desired.y - current.y * desired.x, simd_dot(current, desired))
                let limit: Float = index == 0 ? 0.43 : 0.68
                let next = min(max(angles[index] + delta * 0.72, -limit), limit)
                rotate(joint, axis: SIMD3(1, 0, 0), angle: next - angles[index])
                angles[index] = next
            }
        }
        // Preserve the sole's rest orientation instead of allowing accumulated
        // ankle rotations to make the paw paddle or roll onto its toes.
        if let parent = leg.foot.parent {
            leg.foot.simdOrientation = parent.simdWorldOrientation.inverse
                * modelRoot.simdWorldOrientation * leg.footOrientation
        }
    }

    private func rotate(_ name: String, axis: SIMD3<Float>, angle: Float) {
        guard let joint = joints[name] else { return }
        rotate(joint.node, axis: axis, angle: angle)
    }

    private func rotate(_ name: String, angles: SIMD3<Float>) {
        rotate(name, axis: SIMD3(1, 0, 0), angle: angles.x)
        rotate(name, axis: SIMD3(0, 1, 0), angle: angles.y)
        rotate(name, axis: SIMD3(0, 0, 1), angle: angles.z)
    }

    private func rotate(_ node: SCNNode, axis: SIMD3<Float>, angle: Float) {
        guard let parent = node.parent else { return }
        let localAxis = simd_normalize(parent.simdConvertVector(axis, from: modelRoot))
        node.simdOrientation = simd_quatf(angle: angle, axis: localAxis) * node.simdOrientation
    }

    private func smoothStep(_ value: Float) -> Float { value * value * (3 - 2 * value) }

    private func smoothArc(_ value: Float, start: Float, end: Float) -> Float {
        guard value > start && value < end else { return 0 }
        return pow(sin((value - start) / (end - start) * .pi), 2)
    }
}
