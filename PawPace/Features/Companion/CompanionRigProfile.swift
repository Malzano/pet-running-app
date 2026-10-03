import Foundation

/// Bone names belong to an individual Meshy export, not to a species. New
/// exports carry this small mapping beside their scene so movement never guesses
/// a knee or animates a decorative mesh in place of the real weighted skeleton.
struct CompanionRigProfile: Codable {
    enum Gait: String, Codable { case quadruped, bounding, biped, crawling }

    struct Leg: Codable {
        var pivots: [String]
        var foot: String
        var front: Bool
        var left: Bool
        var phase: Float
    }

    struct Joint: Codable {
        var name: String
        var weight: Float
    }

    var gait: Gait
    var legs: [Leg]
    var head: [Joint]
    var torso: [Joint]
    var tail: [Joint]
    var ears: [Joint] = []
    var leftWing: [Joint] = []
    var rightWing: [Joint] = []
    var jaw: String? = nil
    var modelYawDegrees: Float? = nil
    /// Model-space offsets as fractions of the source model's height.
    var muzzleOffset: [Float] = [0, 0, 0.12]

    var stance: Float { gait == .bounding ? 0.43 : 0.64 }
    var isBiped: Bool { gait == .biped }
    var requiredJointNames: Set<String> {
        Set(legs.flatMap { $0.pivots + [$0.foot] }
            + (head + torso + tail + ears + leftWing + rightWing).map(\.name)
            + (jaw.map { [$0] } ?? []))
    }

    static func load(for species: PetSpecies, bundle: Bundle = .main) -> Self? {
        if let legacy = legacy(species) { return legacy }
        let url = bundle.url(forResource: species.rawValue, withExtension: "motion.json", subdirectory: "Animals")
            ?? bundle.url(forResource: species.rawValue, withExtension: "motion.json")
        guard let url, let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(Self.self, from: data),
              !profile.legs.isEmpty, !profile.head.isEmpty,
              profile.muzzleOffset.count == 3,
              profile.muzzleOffset.allSatisfy(\.isFinite) else { return nil }
        return profile
    }

    private static func legacy(_ species: PetSpecies) -> Self? {
        func joint(_ name: String, _ weight: Float = 1) -> Joint { Joint(name: name, weight: weight) }
        func leg(_ names: [String], _ foot: String, _ front: Bool, _ left: Bool, _ phase: Float, prefix: String = "Bone_") -> Leg {
            Leg(pivots: names.map { prefix + $0 }, foot: prefix + foot, front: front, left: left, phase: phase)
        }
        switch species {
        case .corgi:
            return Self(gait: .quadruped, legs: [
                leg(["030", "029", "028", "027"], "026", true, true, 0),
                leg(["036", "035", "034", "033"], "032", true, false, 0.5),
                leg(["007", "006", "005", "004"], "003", false, true, 0.75),
                leg(["017", "016", "015", "014"], "013", false, false, 0.25)
            ], head: [joint("Bone_024", 0.4), joint("Bone_022", 0.6)],
               torso: [joint("Bone_020")], tail: [joint("Bone_011"), joint("Bone_010", 0.3)])
        case .bunny:
            return Self(gait: .bounding, legs: [
                leg(["029", "028", "027", "026"], "025", true, true, 0.1),
                leg(["035", "034", "033", "032"], "031", true, false, 0.1),
                leg(["014", "013", "012"], "011", false, true, 0),
                leg(["019", "018", "017"], "016", false, false, 0)
            ], head: [joint("Bone_023", 0.3), joint("Bone_022", 0.7)],
               torso: [joint("Bone_008")], tail: [joint("Bone_003", 0.8)])
        case .penguin:
            return Self(gait: .biped, legs: [
                leg(["LeftUpLeg", "LeftLeg"], "LeftFoot", true, true, 0, prefix: "mixamorig:"),
                leg(["RightUpLeg", "RightLeg"], "RightFoot", true, false, 0.5, prefix: "mixamorig:")
            ], head: [joint("mixamorig:Neck", 0.25), joint("mixamorig:Head", 0.75)],
               torso: [joint("mixamorig:Spine")], tail: [joint("mixamorig:Hips")])
        default: return nil
        }
    }
}
