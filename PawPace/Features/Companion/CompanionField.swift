import SceneKit
import UIKit
import simd

/// A small, open meadow. The entire walking surface is flat at y = 0;
/// decorative geometry stays outside the companion's central roaming area.
@MainActor
enum CompanionField {
    static func make(decoration: String = "Flower Meadow", immersive: Bool = false, placements: [HabitatPlacement] = []) -> SCNNode {
        let field = SCNNode()
        field.name = "companion-field"
        let palette = Palette(decoration: decoration)
        if immersive {
            // A continuous lawn makes the home screen a place to spend time,
            // with the original little garden remaining its central clearing.
            let meadow = surface(palette: palette)
            meadow.name = "habitat-ground"
            meadow.simdScale = SIMD3(6, 1, 6)
            meadow.position.y = -0.008
            field.addChildNode(meadow)
        }
        field.addChildNode(surface(palette: palette))
        if !immersive { field.addChildNode(edge(palette: palette)) }

        // Small garden vignettes sit around the rim. The broad middle stays
        // open so the companion can roam and the field can be viewed from any side.
        let grassAngles: [Float] = [0.15, 0.62, 1.12, 1.85, 2.25, 2.82, 3.45, 4.12, 4.63, 5.13, 5.73]
        for (index, angle) in grassAngles.enumerated() {
            let tuft = grass(height: 0.09 + Float(index % 3) * 0.025, palette: palette)
            tuft.name = "meadow-grass-\(index)"
            tuft.simdPosition = perimeter(angle: angle, radius: 0.92)
            tuft.eulerAngles.y = angle + 0.4
            field.addChildNode(tuft)
        }

        for (index, angle) in [Float(0.94), 1.63, 2.56, 3.38, 5.42, 5.96].enumerated() {
            let patch = flowerPatch(color: palette.flowers[index % palette.flowers.count], palette: palette)
            patch.name = "meadow-flower-patch-\(index)"
            patch.simdPosition = perimeter(angle: angle, radius: 0.85)
            patch.eulerAngles.y = angle
            field.addChildNode(patch)
        }

        for (index, angle) in [Float(0.20), 1.32, 2.03, 2.94, 3.83, 4.92, 5.72].enumerated() {
            let leaves = cloverPatch(palette: palette)
            leaves.name = "meadow-clover-patch-\(index)"
            leaves.simdPosition = perimeter(angle: angle, radius: 0.92)
            leaves.eulerAngles.y = angle
            leaves.simdScale = SIMD3(repeating: index % 2 == 0 ? 1 : 0.8)
            field.addChildNode(leaves)
        }

        let tree = cloudTree(palette: palette)
        tree.name = "meadow-cloud-tree"
        tree.simdPosition = SIMD3(-2.00, 0, -1.10)
        field.addChildNode(tree)

        let mushrooms = mushroomPatch(palette: palette)
        mushrooms.name = "meadow-mushroom-family"
        mushrooms.simdPosition = SIMD3(-2.28, 0, 0.62)
        mushrooms.eulerAngles.y = -0.35
        field.addChildNode(mushrooms)

        let picnic = picnicCorner(palette: palette)
        picnic.name = "meadow-picnic-corner"
        picnic.simdPosition = SIMD3(2.08, 0, 0.34)
        picnic.eulerAngles.y = 0.18
        field.addChildNode(picnic)

        let fence = gardenFence(palette: palette)
        fence.name = "meadow-garden-fence"
        fence.simdPosition = SIMD3(0.35, 0, -1.87)
        fence.eulerAngles.y = -0.08
        field.addChildNode(fence)
        for placement in placements {
            let item = keepsake(placement.decoration, palette: palette)
            item.name = "keepsake-\(placement.spot.rawValue)"
            item.simdPosition = SIMD3(placement.spot.x, 0, placement.spot.z)
            field.addChildNode(item)
        }
        return field
    }

    private static func keepsake(_ item: HabitatDecoration, palette: Palette) -> SCNNode {
        let root = SCNNode()
        switch item {
        case .flags:
            for i in 0..<3 {
                let pole = roundedBox(width: 0.025, height: 0.55, length: 0.025, radius: 0.01, color: palette.wood)
                pole.simdPosition = SIMD3(Float(i - 1) * 0.22, 0.275, 0)
                root.addChildNode(pole)
                let flag = roundedBox(width: 0.16, height: 0.12, length: 0.02, radius: 0.01,
                                      color: i == 1 ? palette.pollen : UIColor.systemPink)
                flag.simdPosition = SIMD3(Float(i - 1) * 0.22 + 0.065, 0.45, 0)
                root.addChildNode(flag)
            }
        case .pebbles:
            for i in 0..<5 {
                let angle = Float(i) * 2 * .pi / 5
                let stone = sphere(radius: i == 0 ? 0.12 : 0.09, color: i % 2 == 0 ? UIColor(white: 0.72, alpha: 1) : palette.cream)
                stone.simdScale = SIMD3(1, 0.52, 0.8)
                stone.simdPosition = SIMD3(cos(angle) * 0.19, 0.05, sin(angle) * 0.16)
                root.addChildNode(stone)
            }
            let bloom = flower(color: palette.pollen, palette: palette)
            bloom.simdScale = SIMD3(repeating: 1.6); root.addChildNode(bloom)
        case .lanterns:
            let stand = roundedBox(width: 0.035, height: 0.70, length: 0.035, radius: 0.01, color: palette.wood)
            stand.position.y = 0.35; root.addChildNode(stand)
            let arm = roundedBox(width: 0.5, height: 0.03, length: 0.03, radius: 0.01, color: palette.wood)
            arm.position.y = 0.67; root.addChildNode(arm)
            for x: Float in [-0.20, 0.20] {
                let lantern = sphere(radius: 0.13, color: palette.pollen)
                lantern.simdPosition = SIMD3(x, 0.49, 0)
                lantern.simdScale = SIMD3(0.8, 1.1, 0.8)
                lantern.geometry?.firstMaterial?.emission.contents = UIColor(red: 0.35, green: 0.22, blue: 0.05, alpha: 1)
                root.addChildNode(lantern)
            }
        case .glowJar:
            let jar = roundedBox(width: 0.29, height: 0.38, length: 0.29, radius: 0.10, color: .systemMint)
            jar.position.y = 0.19; root.addChildNode(jar)
            let lid = roundedBox(width: 0.24, height: 0.05, length: 0.24, radius: 0.02, color: palette.wood)
            lid.position.y = 0.40; root.addChildNode(lid)
            for i in 0..<4 {
                let light = sphere(radius: 0.025, color: palette.pollen)
                light.simdPosition = SIMD3(i % 2 == 0 ? -0.06 : 0.07, 0.1 + Float(i) * 0.06, 0.146)
                light.geometry?.firstMaterial?.emission.contents = palette.pollen
                root.addChildNode(light)
            }
        case .campGlow:
            for i in 0..<3 {
                let log = roundedBox(width: 0.45, height: 0.08, length: 0.09, radius: 0.04, color: palette.wood)
                log.position.y = 0.05; log.eulerAngles.y = Float(i) * .pi / 3; root.addChildNode(log)
            }
            let glow = sphere(radius: 0.16, color: palette.pollen)
            glow.simdScale = SIMD3(0.8, 1.5, 0.8); glow.position.y = 0.24
            glow.geometry?.firstMaterial?.emission.contents = UIColor(red: 0.45, green: 0.19, blue: 0.03, alpha: 1)
            root.addChildNode(glow)
        case .cushion:
            let cushion = roundedBox(width: 0.55, height: 0.18, length: 0.43, radius: 0.09, color: palette.cream)
            cushion.position.y = 0.09; root.addChildNode(cushion)
            let patch = sphere(radius: 0.07, color: UIColor.systemTeal)
            patch.simdScale = SIMD3(1.6, 0.15, 1); patch.position.y = 0.185; root.addChildNode(patch)
        }
        return root
    }

    private struct Palette {
        let grassCenter = SIMD4<Float>(0.79, 0.91, 0.75, 1)
        let grassEdge = SIMD4<Float>(0.68, 0.84, 0.68, 1)
        let turf = SIMD4<Float>(0.62, 0.80, 0.65, 1)
        let base = SIMD4<Float>(0.91, 0.86, 0.75, 1)
        let blade = UIColor(red: 0.48, green: 0.72, blue: 0.52, alpha: 1)
        let bladeLight = UIColor(red: 0.68, green: 0.84, blue: 0.60, alpha: 1)
        let canopy = UIColor(red: 0.66, green: 0.83, blue: 0.67, alpha: 1)
        let canopyLight = UIColor(red: 0.76, green: 0.89, blue: 0.69, alpha: 1)
        let cream = UIColor(red: 1.00, green: 0.96, blue: 0.84, alpha: 1)
        let wood = UIColor(red: 0.78, green: 0.61, blue: 0.46, alpha: 1)
        let pollen = UIColor(red: 1.00, green: 0.83, blue: 0.43, alpha: 1)
        let flowers: [UIColor]

        init(decoration: String) {
            switch decoration {
            case "Trail Flags":
                flowers = [UIColor(red: 0.88, green: 0.61, blue: 0.43, alpha: 1),
                           UIColor(red: 0.95, green: 0.87, blue: 0.60, alpha: 1)]
            case "Star Lanterns":
                flowers = [UIColor(red: 0.70, green: 0.71, blue: 0.88, alpha: 1),
                           UIColor(red: 0.94, green: 0.89, blue: 0.65, alpha: 1)]
            case "Camp Glow":
                flowers = [UIColor(red: 0.93, green: 0.74, blue: 0.42, alpha: 1),
                           UIColor(red: 0.91, green: 0.86, blue: 0.70, alpha: 1)]
            default:
                flowers = [UIColor(red: 0.88, green: 0.66, blue: 0.66, alpha: 1),
                           UIColor(red: 0.96, green: 0.92, blue: 0.78, alpha: 1)]
            }
        }
    }

    private static func perimeter(angle: Float, radius: Float) -> SIMD3<Float> {
        SIMD3(cos(angle) * 2.82 * radius, 0, sin(angle) * 2.12 * radius)
    }

    private static func surface(palette: Palette) -> SCNNode {
        let segments = 96
        let rings: [Float] = [0.001, 0.45, 0.78, 1]
        var vertices: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        var triangles: [Int32] = []
        for radius in rings {
            let blend = radius * radius * 0.80
            let color = palette.grassCenter * (1 - blend) + palette.grassEdge * blend
            for index in 0..<segments {
                let angle = Float(index) / Float(segments) * 2 * .pi
                vertices.append(SCNVector3(cos(angle) * 2.82 * radius, 0, sin(angle) * 2.12 * radius))
                colors.append(color)
            }
        }
        for ring in 0..<(rings.count - 1) {
            for index in 0..<segments {
                let a = Int32(ring * segments + index)
                let b = Int32(ring * segments + (index + 1) % segments)
                let c = a + Int32(segments)
                let d = b + Int32(segments)
                triangles += [a, b, c, b, d, c]
            }
        }
        // Fill the tiny centre explicitly, rather than leaving a ray-cast hole.
        let center = Int32(vertices.count)
        vertices.append(SCNVector3Zero)
        colors.append(palette.grassCenter)
        for index in 0..<segments {
            triangles += [center, Int32((index + 1) % segments), Int32(index)]
        }
        let normals = Array(repeating: SCNVector3(0, 1, 0), count: vertices.count)
        let geometry = coloredGeometry(vertices: vertices, normals: normals, colors: colors, triangles: triangles)
        let ground = SCNNode(geometry: geometry)
        ground.name = "habitat-ground"
        ground.castsShadow = false
        return ground
    }

    private static func edge(palette: Palette) -> SCNNode {
        let segments = 96
        // Several curved rings give the meadow a soft, padded silhouette,
        // with mint turf rolling gently into a warm biscuit-coloured underside.
        let rings: [(x: Float, z: Float, y: Float, normalY: Float, color: SIMD4<Float>)] = [
            (2.82, 2.12, 0, 1.0, palette.grassEdge),
            (2.87, 2.17, -0.014, 0.82, palette.grassEdge),
            (2.91, 2.21, -0.052, 0.48, palette.turf),
            (2.92, 2.22, -0.10, 0.05, palette.turf),
            (2.90, 2.20, -0.15, -0.36, palette.base),
            (2.85, 2.15, -0.198, -0.65, palette.base),
            (2.77, 2.07, -0.228, -0.85, palette.base),
            (2.68, 1.98, -0.24, -0.96, palette.base)
        ]
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        var triangles: [Int32] = []
        for ring in rings {
            for index in 0..<segments {
                let angle = Float(index) / Float(segments) * 2 * .pi
                vertices.append(SCNVector3(cos(angle) * ring.x, ring.y, sin(angle) * ring.z))
                let radial = sqrt(max(0, 1 - ring.normalY * ring.normalY))
                let normal = simd_normalize(SIMD3(cos(angle) * radial, ring.normalY, sin(angle) * radial))
                normals.append(SCNVector3(normal))
                colors.append(ring.color)
            }
        }
        for ring in 0..<(rings.count - 1) {
            for index in 0..<segments {
                let a = Int32(ring * segments + index)
                let b = Int32(ring * segments + (index + 1) % segments)
                let c = a + Int32(segments)
                let d = b + Int32(segments)
                triangles += [a, b, c, b, d, c]
            }
        }
        let border = SCNNode(geometry: coloredGeometry(vertices: vertices, normals: normals, colors: colors, triangles: triangles))
        border.name = "habitat-ground"
        return border
    }

    private static func coloredGeometry(
        vertices: [SCNVector3], normals: [SCNVector3],
        colors: [SIMD4<Float>], triangles: [Int32]
    ) -> SCNGeometry {
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: colors.count,
            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), colorSource],
            elements: [SCNGeometryElement(indices: triangles, primitiveType: .triangles)]
        )
        geometry.firstMaterial = matte(.white)
        return geometry
    }

    private static func grass(height: Float, palette: Palette) -> SCNNode {
        let tuft = SCNNode()
        for index in 0..<3 {
            let direction = Float(index) * 2.1
            let leaf = sphere(radius: 0.027, color: index % 2 == 0 ? palette.blade : palette.bladeLight)
            leaf.name = "rounded-grass-leaf-\(index)"
            leaf.simdPosition = SIMD3(cos(direction) * 0.027, height * 0.43, sin(direction) * 0.027)
            leaf.simdScale = SIMD3(0.62, height / 0.054, 1)
            leaf.eulerAngles = SCNVector3(0.2, direction, index == 1 ? 0.25 : -0.2)
            tuft.addChildNode(leaf)
        }
        return tuft
    }

    private static func flowerPatch(color: UIColor, palette: Palette) -> SCNNode {
        let patch = SCNNode()
        for index in 0..<3 {
            let bloom = flower(color: index == 1 ? palette.cream : color, palette: palette)
            bloom.name = "daisy-\(index)"
            bloom.simdPosition = SIMD3(Float(index - 1) * 0.095, 0, index == 1 ? -0.055 : 0.03)
            bloom.simdScale = SIMD3(repeating: index == 1 ? 1.2 : 0.83)
            patch.addChildNode(bloom)
        }
        return patch
    }

    private static func cloverPatch(palette: Palette) -> SCNNode {
        let patch = SCNNode()
        for index in 0..<3 {
            let angle = Float(index) / 3 * 2 * Float.pi
            let leaf = sphere(radius: 0.060, color: index == 1 ? palette.bladeLight : palette.blade)
            leaf.name = "clover-leaf-\(index)"
            leaf.simdPosition = SIMD3(cos(angle) * 0.035, 0.014, sin(angle) * 0.035)
            leaf.simdScale = SIMD3(1, 0.25, 0.9)
            patch.addChildNode(leaf)
        }
        return patch
    }

    private static func cloudTree(palette: Palette) -> SCNNode {
        let tree = SCNNode()
        let trunk = SCNCapsule(capRadius: 0.068, height: 0.43)
        trunk.radialSegmentCount = 12
        trunk.firstMaterial = matte(palette.wood)
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.name = "cloud-tree-trunk"
        trunkNode.position.y = 0.22
        tree.addChildNode(trunkNode)
        let crowns: [(Float, Float, Float, CGFloat)] = [
            (-0.18, 0.52, 0.02, 0.22), (0.17, 0.53, -0.01, 0.23),
            (0, 0.69, 0, 0.25), (0, 0.51, 0.15, 0.22)
        ]
        for (index, crown) in crowns.enumerated() {
            let leaf = sphere(radius: crown.3, color: index % 2 == 0 ? palette.canopy : palette.canopyLight)
            leaf.name = "cloud-tree-canopy-\(index)"
            leaf.simdPosition = SIMD3(crown.0, crown.1, crown.2)
            leaf.simdScale = SIMD3(1, 0.92, 0.85)
            tree.addChildNode(leaf)
        }
        for (index, position) in [SIMD3<Float>(-0.18, 0.52, 0.20), SIMD3<Float>(0.13, 0.63, 0.19)].enumerated() {
            let fruit = sphere(radius: 0.045, color: palette.flowers[0])
            fruit.name = "cloud-tree-fruit-\(index)"
            fruit.simdPosition = position
            tree.addChildNode(fruit)
        }
        let shrub = sphere(radius: 0.15, color: palette.bladeLight)
        shrub.name = "cloud-tree-foot-clover"
        shrub.simdPosition = SIMD3(-0.10, 0.04, 0.07)
        shrub.simdScale = SIMD3(1.4, 0.4, 0.9)
        tree.addChildNode(shrub)
        return tree
    }

    private static func mushroomPatch(palette: Palette) -> SCNNode {
        let patch = SCNNode()
        for index in 0..<3 {
            let mushroom = SCNNode()
            mushroom.name = "mushroom-\(index)"
            mushroom.simdPosition = SIMD3(Float(index - 1) * 0.17, 0, index == 1 ? -0.07 : 0.04)
            mushroom.simdScale = SIMD3(repeating: index == 1 ? 1.0 : 0.67)
            let stalk = SCNCapsule(capRadius: 0.044, height: 0.16)
            stalk.radialSegmentCount = 10
            stalk.firstMaterial = matte(palette.cream)
            let stalkNode = SCNNode(geometry: stalk)
            stalkNode.name = "mushroom-stalk"
            stalkNode.position.y = 0.08
            mushroom.addChildNode(stalkNode)
            let cap = sphere(radius: 0.12, color: palette.flowers[index % palette.flowers.count])
            cap.name = "mushroom-cap"
            cap.position.y = 0.17
            cap.simdScale = SIMD3(1, 0.62, 1)
            mushroom.addChildNode(cap)
            for spotIndex in 0..<3 {
                let angle = Float(spotIndex) * 2.1
                let spot = sphere(radius: 0.020, color: palette.cream)
                spot.name = "mushroom-spot-\(spotIndex)"
                spot.simdPosition = SIMD3(cos(angle) * 0.062, 0.229, sin(angle) * 0.062)
                spot.simdScale = SIMD3(1, 0.25, 1)
                mushroom.addChildNode(spot)
            }
            patch.addChildNode(mushroom)
        }
        return patch
    }

    private static func picnicCorner(palette: Palette) -> SCNNode {
        let picnic = SCNNode()
        let blanket = roundedBox(width: 0.56, height: 0.018, length: 0.60, radius: 0.025, color: palette.flowers[0])
        blanket.name = "picnic-blanket"
        blanket.position.y = 0.012
        picnic.addChildNode(blanket)
        // Soft cream gingham checks, placed just above the blanket.
        for row in 0..<3 {
            for column in 0..<3 where (row + column) % 2 == 0 {
                let check = roundedBox(width: 0.16, height: 0.004, length: 0.17, radius: 0.007, color: palette.cream)
                check.name = "picnic-gingham-\(row)-\(column)"
                check.simdPosition = SIMD3(Float(column - 1) * 0.18, 0.023, Float(row - 1) * 0.19)
                picnic.addChildNode(check)
            }
        }
        let basket = roundedBox(width: 0.22, height: 0.15, length: 0.17, radius: 0.035, color: palette.wood)
        basket.name = "picnic-basket"
        basket.simdPosition = SIMD3(0.055, 0.10, -0.15)
        picnic.addChildNode(basket)
        let rim = roundedBox(width: 0.235, height: 0.022, length: 0.18, radius: 0.014, color: palette.cream)
        rim.name = "picnic-basket-rim"
        rim.simdPosition = SIMD3(0.055, 0.17, -0.15)
        picnic.addChildNode(rim)
        let handle = SCNTorus(ringRadius: 0.066, pipeRadius: 0.012)
        handle.ringSegmentCount = 16
        handle.pipeSegmentCount = 8
        handle.firstMaterial = matte(palette.wood)
        let handleNode = SCNNode(geometry: handle)
        handleNode.name = "picnic-basket-handle"
        handleNode.simdPosition = SIMD3(0.055, 0.208, -0.15)
        handleNode.eulerAngles.x = .pi / 2
        picnic.addChildNode(handleNode)
        let fruit = sphere(radius: 0.045, color: palette.flowers[0])
        fruit.name = "picnic-peach"
        fruit.simdPosition = SIMD3(-0.095, 0.067, 0.095)
        picnic.addChildNode(fruit)
        return picnic
    }

    private static func gardenFence(palette: Palette) -> SCNNode {
        let fence = SCNNode()
        for index in 0..<4 {
            let post = roundedBox(width: 0.08, height: 0.29, length: 0.07, radius: 0.035, color: palette.cream)
            post.name = "garden-fence-post-\(index)"
            post.simdPosition = SIMD3(Float(index) * 0.20 - 0.30, 0.145, 0)
            fence.addChildNode(post)
        }
        for (index, height) in [Float(0.095), 0.21].enumerated() {
            let rail = roundedBox(width: 0.72, height: 0.05, length: 0.045, radius: 0.02, color: palette.cream)
            rail.name = "garden-fence-rail-\(index)"
            rail.simdPosition = SIMD3(0, height, -0.038)
            fence.addChildNode(rail)
        }
        let bloom = flowerPatch(color: palette.flowers[0], palette: palette)
        bloom.name = "garden-fence-daisies"
        bloom.simdPosition = SIMD3(0.20, 0, 0.13)
        fence.addChildNode(bloom)
        return fence
    }

    private static func sphere(radius: CGFloat, color: UIColor) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 16
        geometry.firstMaterial = matte(color)
        return SCNNode(geometry: geometry)
    }

    private static func roundedBox(width: CGFloat, height: CGFloat, length: CGFloat, radius: CGFloat, color: UIColor) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: min(radius, height / 2))
        geometry.chamferSegmentCount = 5
        geometry.firstMaterial = matte(color)
        return SCNNode(geometry: geometry)
    }

    private static func flower(color: UIColor, palette: Palette) -> SCNNode {
        let bloom = SCNNode()
        let stem = SCNCylinder(radius: 0.006, height: 0.11)
        stem.radialSegmentCount = 8
        stem.firstMaterial = matte(palette.blade)
        let stemNode = SCNNode(geometry: stem)
        stemNode.position.y = 0.055
        bloom.addChildNode(stemNode)
        let petals = SCNNode()
        petals.position.y = 0.115
        petals.eulerAngles = SCNVector3(0.15, 0, 0.2)
        for index in 0..<5 {
            let angle = Float(index) / 5 * 2 * Float.pi
            let petal = SCNSphere(radius: 0.035)
            petal.segmentCount = 12
            petal.firstMaterial = matte(color)
            let node = SCNNode(geometry: petal)
            node.simdPosition = SIMD3(cos(angle) * 0.034, 0, sin(angle) * 0.034)
            node.simdScale = SIMD3(1, 0.38, 0.70)
            node.eulerAngles.y = -angle
            petals.addChildNode(node)
        }
        let pollen = SCNSphere(radius: 0.019)
        pollen.segmentCount = 12
        pollen.firstMaterial = matte(palette.pollen)
        let center = SCNNode(geometry: pollen)
        center.position.y = 0.007
        center.simdScale = SIMD3(1, 0.48, 1)
        petals.addChildNode(center)
        bloom.addChildNode(petals)
        return bloom
    }

    private static func matte(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .lambert
        material.isDoubleSided = true
        return material
    }
}
