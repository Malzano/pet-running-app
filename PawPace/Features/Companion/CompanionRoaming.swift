import Foundation
import simd

enum CompanionRoamingIntent: Sendable {
    case wander
    case rest
    case moveTo(SIMD2<Float>)
    case play
    case feed
    case greet
    case special
    case visitDecoration(SIMD2<Float>, playful: Bool)
}

enum CompanionRoamingBehavior: Sendable {
    case wandering
    case approaching
    case interacting
    case settling
    case resting
}

struct CompanionRoamingPose: Sendable {
    /// Position on the ground plane, in world X and Z units.
    var position: SIMD2<Float>
    /// Continuous radians, with zero facing +Z and positive angles facing +X.
    var yaw: Float
    var speed: Float
    var turnRate: Float
    /// Actual ground distance, suitable for advancing a planted-foot gait.
    var gaitDistance: Float
    /// Head direction relative to the body, in radians.
    var lookYaw: Float
    var action: PetMotion
    var actionTime: Float
}

/// A deterministic ground-plane controller. Translation always follows the
/// body's heading; a pet slows down before turning or reaching its destination.
/// SceneKit, wall clocks and random system state are deliberately kept outside.
struct CompanionRoaming {
    static let fieldRadii = SIMD2<Float>(1.35, 0.85)
    static let ballPosition = SIMD2<Float>(1.2, 0.85)
    static let bowlPosition = SIMD2<Float>(-1.2, 0.75)
    static let greetingYaw: Float = 0.43

    private(set) var pose = CompanionRoamingPose(
        position: SIMD2(0, -0.12), yaw: 0.25, speed: 0, turnRate: 0,
        gaitDistance: 0, lookYaw: 0, action: .idle, actionTime: 0
    )
    private(set) var destination = SIMD2<Float>.zero
    var behavior: CompanionRoamingBehavior { externallyResting ? .resting : mode }
    var temperament: BuddyTemperament?

    private let species: PetSpecies
    private var randomState: UInt64
    private var mode: CompanionRoamingBehavior = .wandering
    private var interaction: CompanionRoamingIntent?
    private var elapsed: Float = 0
    private var modeTime: Float = 0
    private var pauseDuration: Float = 1.5
    private var heldYaw: Float = 0.25
    private var externallyResting = false
    private var aligningInteraction = false
    private var lookPhase: Float = 0
    private var lastSpecialTime: Float = 0

    init(species: PetSpecies, seed: UInt64 = 0x5EED) {
        self.species = species
        let speciesSalt: UInt64
        switch species {
        case .corgi: speciesSalt = 0xA14B
        case .bunny: speciesSalt = 0xB28D
        case .penguin: speciesSalt = 0xC39F
        case .redPanda: speciesSalt = 0xD4A1
        case .fox: speciesSalt = 0xE5B3
        case .axolotl: speciesSalt = 0xF6C5
        case .dragon: speciesSalt = 0xA7D7
        case .unicorn: speciesSalt = 0xB8E9
        case .phoenix: speciesSalt = 0xC9FB
        }
        randomState = seed ^ speciesSalt
        lookPhase = random(in: 0...(2 * .pi))
        chooseDestination()
    }

    /// Rest remains in effect until another request. Other interactions complete
    /// and return to wandering without resetting the pet's position or gait.
    mutating func request(_ intent: CompanionRoamingIntent) {
        switch intent {
        case .wander:
            interaction = nil
            begin(.wandering)
            chooseDestination()
        case .rest:
            interaction = nil
            heldYaw = pose.yaw
            begin(.resting)
        case let .moveTo(point):
            guard point.x.isFinite, point.y.isFinite else { return }
            interaction = nil
            destination = Self.bounded(point, radius: 0.82)
            begin(.approaching)
        case .play, .feed:
            interaction = intent
            destination = interactionApproach(for: intent)
            begin(.approaching)
        case let .visitDecoration(point, _):
            guard point.x.isFinite, point.y.isFinite else { return }
            interaction = intent
            destination = Self.bounded(point, radius: 0.82)
            begin(.approaching)
        case .special:
            if case .special = interaction { return }
            guard species.specialMoveName != nil else { request(.play); return }
            interaction = intent
            lastSpecialTime = elapsed
            destination = pose.position
            heldYaw = pose.yaw + Self.angleDifference(Self.greetingYaw, pose.yaw)
            begin(.approaching)
        case .greet:
            interaction = intent
            destination = pose.position
            heldYaw = pose.yaw + Self.angleDifference(Self.greetingYaw, pose.yaw)
            begin(.approaching)
        }
    }

    func interactionApproach(for intent: CompanionRoamingIntent) -> SIMD2<Float> {
        let prop: SIMD2<Float>
        switch intent {
        case .play: prop = Self.ballPosition
        case .feed: prop = Self.bowlPosition
        default: return pose.position
        }
        let reach: Float
        switch species {
        case .corgi: reach = 0.68
        case .bunny: reach = 0.60
        case .penguin, .redPanda, .axolotl, .phoenix: reach = 0.58
        case .fox, .dragon: reach = 0.68
        case .unicorn: reach = 0.72
        }
        return Self.bounded(prop - simd_normalize(prop) * reach, radius: 0.82)
    }

    /// Suspension or debugger stalls never fast-forward a pet across the field.
    /// Small integration steps also keep steering stable at 30, 60 and 120 Hz.
    @discardableResult
    mutating func step(deltaTime: Float, isResting: Bool = false) -> CompanionRoamingPose {
        guard deltaTime.isFinite, deltaTime > 0 else { return pose }
        if isResting && !externallyResting { heldYaw = pose.yaw }
        externallyResting = isResting
        var remaining = min(deltaTime, 0.1)
        while remaining > 0.000001 {
            let dt = min(remaining, 1 / 120)
            integrate(dt)
            remaining -= dt
        }
        return pose
    }

    private var cruisingSpeed: Float {
        let base: Float = switch species {
        case .corgi: 0.43
        case .bunny: 0.38
        case .penguin, .axolotl: 0.30
        case .redPanda: 0.35
        case .fox: 0.46
        case .dragon: 0.34
        case .unicorn: 0.42
        case .phoenix: 0.33
        }
        return base * (temperament == .calm ? 0.82 : temperament == .playful ? 1.08 : 1)
    }

    private mutating func integrate(_ dt: Float) {
        elapsed += dt
        if !externallyResting { modeTime += dt }
        let resting = externallyResting || mode == .resting
        let navigating = !resting && (mode == .wandering || mode == .approaching)
        let offset = destination - pose.position
        let distance = simd_length(offset)
        var desiredYaw = heldYaw
        var desiredSpeed: Float = 0

        if navigating {
            if mode == .approaching, interaction != nil, distance < 0.10 {
                aligningInteraction = true
            }
            if distance > 0.035 { desiredYaw = atan2(offset.x, offset.y) }
            if aligningInteraction {
                desiredYaw = interactionYaw()
            }
            let headingError = Self.angleDifference(desiredYaw, pose.yaw)
            // Large course changes happen on planted feet before forward travel.
            let alignment = max(0, cos(headingError))
            desiredSpeed = min(cruisingSpeed, max(0, distance - 0.025) * 2.2)
                * alignment * alignment
            if abs(headingError) > 1.2 { desiredSpeed = 0 }
            if distance < 0.055 { desiredSpeed = 0 }
            if aligningInteraction { desiredSpeed = 0 }
        }

        let yawError = Self.angleDifference(desiredYaw, pose.yaw)
        let maximumTurn: Float = species == .penguin ? 1.5 : 1.8
        let desiredTurn = min(maximumTurn, max(-maximumTurn, yawError * 3.2))
        pose.turnRate = Self.approach(pose.turnRate, desiredTurn, by: dt * 4.5)
        pose.yaw += pose.turnRate * dt

        let forward = SIMD2<Float>(sin(pose.yaw), cos(pose.yaw))
        let boundaryDistance = availableDistance(heading: forward)
        // Brake along the current heading, before an outward curve can leave
        // the ellipse. The final ray limit never pushes a pet sideways.
        desiredSpeed = min(desiredSpeed, sqrt(max(0, 2 * 1.4 * (boundaryDistance - 0.07))))
        pose.speed = Self.approach(pose.speed, desiredSpeed, by: dt * (desiredSpeed < pose.speed ? 1.4 : 0.75))
        let travel = min(pose.speed * dt, max(0, boundaryDistance))
        pose.position += forward * travel
        pose.gaitDistance += travel

        if !resting {
            if navigating, (aligningInteraction || distance < 0.07), pose.speed < 0.045 {
                if interaction != nil {
                    if abs(Self.angleDifference(interactionYaw(), pose.yaw)) < 0.10,
                       abs(pose.turnRate) < 0.25 {
                        heldYaw = interactionYaw()
                        begin(.interacting)
                    }
                } else {
                    heldYaw = pose.yaw
                    pauseDuration = random(in: 1.0...2.7) * (temperament == .calm ? 1.8 : temperament == .playful ? 0.8 : 1)
                    begin(.settling)
                }
            } else if mode == .interacting, modeTime >= interactionDuration {
                interaction = nil
                heldYaw = pose.yaw
                pauseDuration = random(in: 0.45...1.0)
                begin(.settling)
            } else if mode == .settling, modeTime >= pauseDuration {
                if species.specialMoveName != nil, elapsed - lastSpecialTime >= 60, random(in: 0...1) < 0.18 {
                    request(.special)
                } else {
                    begin(.wandering)
                    chooseDestination()
                }
            }
        }

        let lookTarget: Float
        if resting {
            lookTarget = sin(elapsed * 0.45 + lookPhase) * 0.07
        } else if mode == .interacting {
            lookTarget = Self.angleDifference(interactionYaw(), pose.yaw)
        } else if navigating {
            lookTarget = min(0.36, max(-0.36, yawError * 0.45))
        } else {
            lookTarget = sin(elapsed * 1.05 + lookPhase) * (temperament == .curious ? 0.40 : 0.33)
        }
        pose.lookYaw += (lookTarget - pose.lookYaw) * (1 - exp(-dt * 5))

        let nextAction: PetMotion
        if !resting, mode == .interacting {
            switch interaction {
            case .play: nextAction = .playing
            case .feed: nextAction = .feeding
            case .greet: nextAction = .jumping
            case .special: nextAction = .special
            case let .visitDecoration(_, playful): nextAction = playful ? .jumping : .idle
            default: nextAction = .idle
            }
        } else if pose.speed > 0.012 || (!resting && abs(pose.turnRate) > 0.18) {
            nextAction = .walking
        } else {
            nextAction = .idle
        }
        if pose.action != nextAction {
            pose.action = nextAction
            pose.actionTime = 0
        } else {
            pose.actionTime += dt
        }
    }

    private var interactionDuration: Float {
        switch interaction {
        case .play: 3.4
        case .feed: 3.0
        case .greet: 1.5
        case .special: 4
        case .visitDecoration: 3
        default: 0
        }
    }

    private func interactionYaw() -> Float {
        let target: SIMD2<Float>
        switch interaction {
        case .play: target = Self.ballPosition
        case .feed: target = Self.bowlPosition
        case .greet, .special: return Self.greetingYaw
        case let .visitDecoration(point, _): target = point
        default: return heldYaw
        }
        let offset = target - pose.position
        return atan2(offset.x, offset.y)
    }

    private mutating func begin(_ next: CompanionRoamingBehavior) {
        mode = next
        modeTime = 0
        if next == .approaching || next == .wandering { aligningInteraction = false }
    }

    private mutating func chooseDestination() {
        var best = -pose.position * 0.6
        var bestScore: Float = -.infinity
        let forward = SIMD2<Float>(sin(pose.yaw), cos(pose.yaw))
        // Favor a new area and the current heading, without repeatedly marching
        // between fixed waypoints or snapping toward a randomly chosen angle.
        for _ in 0..<12 {
            let angle = random(in: 0...(2 * .pi))
            let radius = sqrt(random(in: 0.10...0.64))
            let candidate = SIMD2<Float>(cos(angle), sin(angle)) * Self.fieldRadii * radius
            let offset = candidate - pose.position
            let distance = simd_length(offset)
            guard distance > 0.42 else { continue }
            let score = min(distance, 1.15) + simd_dot(offset / distance, forward) * 0.4 + random(in: 0...0.25)
            if score > bestScore {
                best = candidate
                bestScore = score
            }
        }
        destination = best
    }

    private func availableDistance(heading: SIMD2<Float>) -> Float {
        let p = pose.position / Self.fieldRadii
        let d = heading / Self.fieldRadii
        let a = simd_dot(d, d)
        let b = simd_dot(p, d)
        let c = simd_dot(p, p) - 0.999 * 0.999
        return max(0, (-b + sqrt(max(0, b * b - a * c))) / a)
    }

    private static func bounded(_ point: SIMD2<Float>, radius: Float) -> SIMD2<Float> {
        let length = simd_length(point / fieldRadii)
        return length > radius ? point * (radius / length) : point
    }

    private static func angleDifference(_ target: Float, _ current: Float) -> Float {
        atan2(sin(target - current), cos(target - current))
    }

    private static func approach(_ value: Float, _ target: Float, by amount: Float) -> Float {
        value + min(amount, max(-amount, target - value))
    }

    private mutating func random(in range: ClosedRange<Float>) -> Float {
        randomState &+= 0x9E3779B97F4A7C15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        let unit = Float(value >> 40) / Float(1 << 24)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
