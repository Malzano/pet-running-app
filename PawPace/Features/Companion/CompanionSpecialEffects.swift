import SceneKit
import UIKit
import simd

/// One deterministic clock drives both the animal gesture and its decoration.
/// Geometry is allocated once; replaying a move never adds emitters or nodes.
@MainActor
final class CompanionSpecialEffects {
    static let duration: Float = 4
    let root = SCNNode()
    private let species: PetSpecies
    private var pieces: [SCNNode] = []

    struct Pose {
        var lift: Float = 0
        var roll: Float = 0
        var pitch: Float = 0
        var head = SIMD3<Float>.zero
        var tail = SIMD3<Float>.zero
        var wing: Float = 0
        var jaw: Float = 0
    }

    static func pose(species: PetSpecies, time: Float, weight: Float) -> Pose {
        guard time.isFinite, weight.isFinite, time >= 0, time < duration else { return Pose() }
        let p = time / duration
        let burst = arc(p, from: 0.17, to: 0.82) * max(0, min(weight, 1))
        let anticipation = arc(p, from: 0, to: 0.23) * max(0, min(weight, 1))
        var pose = Pose()
        pose.head = SIMD3(anticipation * 0.15 - burst * 0.15, sin(time * 3) * burst * 0.07, 0)
        pose.tail = SIMD3(0.1 * burst, sin(time * 7) * burst * 0.35, 0)
        switch species {
        case .redPanda:
            let turn = min(1, max(0, (p - 0.2) / 0.56))
            pose.roll = (turn * turn * (3 - 2 * turn)) * 2 * .pi * weight
            // Roll around the torso, with enough clearance for the small paws.
            pose.lift = burst * 0.22
        case .fox:
            pose.lift = burst * 0.22
            pose.pitch = -sin(p * 2 * .pi) * burst * 0.16
        case .axolotl:
            pose.lift = burst * 0.14
            pose.roll = sin(time * 3) * burst * 0.09
            pose.tail.y = sin(time * 5) * burst * 0.45
        case .dragon:
            pose.head.x = anticipation * 0.22 - burst * 0.12
            pose.head.y = -burst * 0.5
            pose.jaw = burst * 0.3
            pose.wing = burst * 0.18
        case .unicorn:
            pose.lift = burst * 0.28
            pose.pitch = -sin(p * 2 * .pi) * burst * 0.14
        case .phoenix:
            pose.lift = burst * 0.23
            pose.wing = burst * (0.3 + sin(time * 8) * 0.22)
            pose.head.x = -burst * 0.16
        default: break
        }
        return pose
    }

    init(species: PetSpecies) {
        self.species = species
        root.name = "companion-special-effects"
        root.isHidden = true
        guard species.specialMoveName != nil else { return }
        if species == .unicorn {
            let colors: [UIColor] = [.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemCyan, .systemPurple]
            for (index, color) in colors.enumerated() {
                let shape = SCNGeometry(sources: [.init(vertices: (0...40).flatMap { step -> [SCNVector3] in
                    let a = Float(step) / 40 * .pi
                    let radius = Float(0.55 + Double(index) * 0.042)
                    return [SCNVector3(cos(a) * radius, sin(a) * radius, 0),
                            SCNVector3(cos(a) * (radius + 0.028), sin(a) * (radius + 0.028), 0)]
                })], elements: [SCNGeometryElement(indices: (0..<40).flatMap { index -> [Int32] in
                    let n = Int32(index * 2)
                    return [n, n + 1, n + 2, n + 1, n + 3, n + 2]
                }, primitiveType: .triangles)])
                shape.firstMaterial = material(color, glow: true)
                let node = SCNNode(geometry: shape)
                node.name = "rainbow-band-\(index)"
                root.addChildNode(node)
                pieces.append(node)
            }
        } else {
            for index in 0..<24 {
                let geometry: SCNGeometry
                let color: UIColor
                switch species {
                case .redPanda:
                    let leaf = SCNSphere(radius: 0.035)
                    leaf.segmentCount = 8
                    geometry = leaf
                    color = index.isMultiple(of: 2) ? UIColor(red: 0.65, green: 0.83, blue: 0.35, alpha: 1) : UIColor(red: 0.91, green: 0.71, blue: 0.32, alpha: 1)
                case .fox:
                    let spark = SCNSphere(radius: 0.019)
                    spark.segmentCount = 8
                    geometry = spark
                    color = UIColor(red: 1, green: 0.9, blue: 0.38, alpha: 1)
                case .axolotl:
                    let bubble = SCNSphere(radius: 0.035 + CGFloat(index % 4) * 0.013)
                    bubble.segmentCount = 14
                    geometry = bubble
                    color = UIColor(red: 0.60, green: 0.9, blue: 1, alpha: 0.55)
                default:
                    let puff = SCNSphere(radius: 0.045)
                    puff.segmentCount = 10
                    geometry = puff
                    color = index.isMultiple(of: 3) ? UIColor(red: 1, green: 0.9, blue: 0.4, alpha: 1) : UIColor(red: 1, green: 0.47, blue: 0.24, alpha: 1)
                }
                geometry.firstMaterial = material(color, glow: species != .redPanda && species != .axolotl)
                let node = SCNNode(geometry: geometry)
                node.name = "special-particle-\(index)"
                root.addChildNode(node)
                pieces.append(node)
            }
        }
    }

    func update(time: Float, weight: Float, muzzle: SIMD3<Float>, growthScale: Float, direction: SIMD3<Float> = SIMD3(0, 0, 1)) {
        guard time.isFinite, weight.isFinite, time >= 0, time < Self.duration, weight > 0.001,
              species.specialMoveName != nil else {
            root.isHidden = true
            return
        }
        let phase = time / Self.duration
        let envelope = Self.arc(phase, from: 0.13, to: 0.96) * min(1, weight)
        root.isHidden = envelope < 0.001
        root.opacity = CGFloat(envelope)
        for (index, node) in pieces.enumerated() {
            let i = Float(index)
            let angle = i * 2.39996 + time * 1.7
            let progress = (time * 0.7 + i / 24).truncatingRemainder(dividingBy: 1)
            switch species {
            case .dragon:
                // Short, friendly fire puffs emerge from the moving muzzle.
                let distance = progress * 0.65 * growthScale
                let forward = simd_length_squared(direction) > 0.0001 ? simd_normalize(direction) : SIMD3<Float>(0, 0, 1)
                let side = SIMD3<Float>(forward.z, 0, -forward.x)
                node.simdPosition = muzzle + forward * distance + side * (sin(angle * 2) * 0.10 * progress)
                    + SIMD3(0, 0.02 + progress * 0.10, 0)
                node.simdOrientation = simd_quatf(from: SIMD3(0, 0, 1), to: forward)
                node.simdScale = SIMD3(0.45 + progress * 1.5, 0.45 + progress * 1.5, 1.0 + progress * 2.2) * growthScale
                node.opacity = CGFloat(sin(progress * .pi))
            case .unicorn:
                node.simdPosition = SIMD3(0, 0.07 * growthScale, -0.28 * growthScale)
                node.simdScale = SIMD3(repeating: growthScale * (0.78 + envelope * 0.22))
                node.opacity = 0.8
            case .redPanda:
                let radius = (0.3 + progress * 0.55) * growthScale
                node.simdPosition = SIMD3(cos(angle) * radius, (0.12 + sin(progress * .pi) * 0.55) * growthScale, sin(angle) * radius)
                node.simdScale = SIMD3(0.65, 0.23, 1.7) * growthScale
                node.simdEulerAngles = SIMD3(time * 2 + i, angle, time + i)
            case .fox:
                let radius = (0.4 + Float(index % 4) * 0.1) * growthScale
                node.simdPosition = SIMD3(cos(angle) * radius, (0.35 + sin(time * 2 + i) * 0.2) * growthScale, sin(angle) * radius)
                node.simdScale = SIMD3(repeating: (0.8 + 0.5 * sin(time * 6 + i)) * growthScale)
            case .axolotl:
                node.simdPosition = SIMD3(cos(angle) * 0.5, 0.1 + progress * 1.0, sin(angle) * 0.45) * growthScale
                node.simdScale = SIMD3(repeating: (0.6 + sin(progress * .pi) * 0.5) * growthScale)
                node.opacity = CGFloat(sin(progress * .pi) * 0.7)
            case .phoenix:
                let radius = (0.25 + progress * 0.65) * growthScale
                node.simdPosition = SIMD3(cos(angle) * radius, (0.2 + sin(progress * .pi) * 0.8) * growthScale, sin(angle) * radius)
                node.simdScale = SIMD3(0.55, 1.4, 0.55) * growthScale
                node.opacity = CGFloat(sin(progress * .pi))
            default: node.isHidden = true
            }
        }
    }

    private static func arc(_ value: Float, from start: Float, to end: Float) -> Float {
        guard value > start, value < end else { return 0 }
        let a = sin((value - start) / (end - start) * .pi)
        return a * a
    }

    private func material(_ color: UIColor, glow: Bool) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = glow ? .constant : .physicallyBased
        material.roughness.contents = 0.6
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        return material
    }
}
