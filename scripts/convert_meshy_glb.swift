#!/usr/bin/env swift
// Offline Meshy GLB -> SceneKit conversion. No application runtime dependencies.
// Usage: swift scripts/convert_meshy_glb.swift source.glb destination.scn
// Preserves the rest skeleton and all normalized weights per vertex.
// Writes a companion .rig.json with joint coordinates for authoring species-specific motion.
import Foundation
import AppKit
import SceneKit
import simd

struct ConversionError: Error, CustomStringConvertible { let description: String }
func fail(_ message: String) -> ConversionError { ConversionError(description: message) }
func scalar<T>(_ bytes: Data, _ offset: Int, _: T.Type) -> T {
    bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
}
func packed<T>(_ values: [T]) -> Data { values.withUnsafeBufferPointer { Data(buffer: $0) } }
func vector(_ values: [Float]) -> SIMD3<Float> { SIMD3(values[0], values[1], values[2]) }
func matrix(_ values: [Float]) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4(values[0], values[1], values[2], values[3]),
        SIMD4(values[4], values[5], values[6], values[7]),
        SIMD4(values[8], values[9], values[10], values[11]),
        SIMD4(values[12], values[13], values[14], values[15])
    ))
}
func numbers(_ value: Any?) -> [Float]? { (value as? [NSNumber])?.map(\.floatValue) }
func xyz(_ value: SIMD3<Float>) -> [Float] { [value.x, value.y, value.z] }

final class GLB {
    let json: [String: Any]
    let bin: Data
    let url: URL
    init(url: URL) throws {
        self.url = url
        let bytes = try Data(contentsOf: url)
        guard bytes.count >= 20, scalar(bytes, 0, UInt32.self) == 0x46546C67,
              scalar(bytes, 4, UInt32.self) == 2 else { throw fail("Expected glTF 2.0 GLB") }
        var jsonBytes: Data?; var binary: Data?; var offset = 12
        while offset + 8 <= bytes.count {
            let length = Int(scalar(bytes, offset, UInt32.self))
            let type = scalar(bytes, offset + 4, UInt32.self)
            guard offset + 8 + length <= bytes.count else { throw fail("Truncated GLB chunk") }
            let chunk = bytes.subdata(in: offset + 8 ..< offset + 8 + length)
            if type == 0x4E4F534A { jsonBytes = chunk }
            if type == 0x004E4942 { binary = chunk }
            offset += 8 + length
        }
        guard let source = jsonBytes,
              let parsed = try JSONSerialization.jsonObject(with: source) as? [String: Any],
              let binary else { throw fail("GLB must contain JSON and BIN chunks") }
        json = parsed; bin = binary
        if let required = parsed["extensionsRequired"] as? [String], !required.isEmpty {
            throw fail("Unsupported required extensions: \(required.joined(separator: ", "))")
        }
    }
    func array(_ key: String) -> [[String: Any]] { json[key] as? [[String: Any]] ?? [] }
    func view(_ index: Int) throws -> Data {
        let views = array("bufferViews")
        guard views.indices.contains(index) else { throw fail("Invalid buffer view") }
        let info = views[index]
        guard (info["buffer"] as? Int ?? 0) == 0 else { throw fail("External GLB buffer unsupported") }
        let start = info["byteOffset"] as? Int ?? 0, count = info["byteLength"] as? Int ?? 0
        guard start >= 0, start + count <= bin.count else { throw fail("Buffer view outside binary chunk") }
        return bin.subdata(in: start ..< start + count)
    }
    func accessor(_ index: Int) throws -> (values: [Float], count: Int, components: Int) {
        let accessors = array("accessors")
        guard accessors.indices.contains(index) else { throw fail("Invalid accessor \(index)") }
        let info = accessors[index]
        guard info["sparse"] == nil, let viewIndex = info["bufferView"] as? Int,
              let type = info["componentType"] as? Int, let count = info["count"] as? Int,
              let shape = info["type"] as? String,
              let components = ["SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4,"MAT4":16][shape],
              let size = [5120:1,5121:1,5122:2,5123:2,5125:4,5126:4][type]
        else { throw fail("Unsupported accessor \(index)") }
        let bytes = try view(viewIndex)
        let stride = array("bufferViews")[viewIndex]["byteStride"] as? Int ?? components * size
        let start = info["byteOffset"] as? Int ?? 0
        guard count == 0 || start + (count - 1) * stride + components * size <= bytes.count else {
            throw fail("Accessor outside buffer view")
        }
        let normalized = info["normalized"] as? Bool ?? false
        var values = [Float](); values.reserveCapacity(count * components)
        for row in 0..<count { for component in 0..<components {
            let offset = start + row * stride + component * size
            let value: Float
            switch type {
            case 5120: value = Float(scalar(bytes, offset, Int8.self)) / (normalized ? 127 : 1)
            case 5121: value = Float(scalar(bytes, offset, UInt8.self)) / (normalized ? 255 : 1)
            case 5122: value = Float(scalar(bytes, offset, Int16.self)) / (normalized ? 32767 : 1)
            case 5123: value = Float(scalar(bytes, offset, UInt16.self)) / (normalized ? 65535 : 1)
            case 5125: value = Float(scalar(bytes, offset, UInt32.self))
            default: value = scalar(bytes, offset, Float.self)
            }
            values.append(normalized ? max(value, -1) : value)
        }}
        return (values, count, components)
    }
    func image(_ textureIndex: Int) throws -> NSImage {
        let textures = array("textures"), images = array("images")
        guard textures.indices.contains(textureIndex), let source = textures[textureIndex]["source"] as? Int,
              images.indices.contains(source) else { throw fail("Invalid texture \(textureIndex)") }
        let info = images[source]
        let data: Data
        if let viewIndex = info["bufferView"] as? Int { data = try view(viewIndex) }
        else if let uri = info["uri"] as? String, !uri.contains(":") {
            data = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(uri))
        } else { throw fail("Unsupported image URI") }
        guard let image = NSImage(data: data) else { throw fail("Unreadable image \(source)") }
        return image
    }
}

func geometrySource(_ values: [Float], _ count: Int, _ components: Int, _ semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
    SCNGeometrySource(data: packed(values), semantic: semantic, vectorCount: count,
                      usesFloatComponents: true, componentsPerVector: components,
                      bytesPerComponent: 4, dataOffset: 0, dataStride: components * 4)
}

func resized(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
    let size = image.size
    let scale = min(1, maxDimension / max(size.width, size.height))
    let target = NSSize(width: max(1, round(size.width * scale)), height: max(1, round(size.height * scale)))
    let result = NSImage(size: target)
    result.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: target), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
    result.unlockFocus()
    return result
}

func convert(source: URL, destination: URL) throws {
    let glb = try GLB(url: source)
    let scene = SCNScene()
    let nodeInfo = glb.array("nodes")
    let nodes = nodeInfo.enumerated().map { (index, info) -> SCNNode in
        let node = SCNNode(); node.name = info["name"] as? String ?? "node_\(index)"
        if let values = numbers(info["matrix"]) { node.simdTransform = matrix(values) }
        else {
            if let v = numbers(info["translation"]) { node.simdPosition = vector(v) }
            if let v = numbers(info["rotation"]) { node.simdOrientation = simd_quatf(ix: v[0], iy: v[1], iz: v[2], r: v[3]) }
            if let v = numbers(info["scale"]) { node.simdScale = vector(v) }
        }
        return node
    }
    for (index, info) in nodeInfo.enumerated() {
        for child in info["children"] as? [Int] ?? [] { nodes[index].addChildNode(nodes[child]) }
    }
    let selectedScene = glb.json["scene"] as? Int ?? 0
    let scenes = glb.array("scenes")
    guard scenes.indices.contains(selectedScene) else { throw fail("No GLB scene") }
    for index in scenes[selectedScene]["nodes"] as? [Int] ?? [] { scene.rootNode.addChildNode(nodes[index]) }
    let materials: [SCNMaterial] = try glb.array("materials").map { info in
        let material = SCNMaterial(); material.name = info["name"] as? String
        material.lightingModel = .physicallyBased
        material.isDoubleSided = info["doubleSided"] as? Bool ?? false
        let pbr = info["pbrMetallicRoughness"] as? [String:Any] ?? [:]
        let color = numbers(pbr["baseColorFactor"]) ?? [1,1,1,1]
        if let texture = pbr["baseColorTexture"] as? [String: Any], let index = texture["index"] as? Int {
            material.diffuse.contents = resized(try glb.image(index), maxDimension: 1024)
        } else { material.diffuse.contents = NSColor(red: CGFloat(color[0]), green: CGFloat(color[1]), blue: CGFloat(color[2]), alpha: CGFloat(color[3])) }
        material.metalness.contents = pbr["metallicFactor"] as? Double ?? 1
        material.roughness.contents = pbr["roughnessFactor"] as? Double ?? 1
        if let texture = pbr["metallicRoughnessTexture"] as? [String: Any], let index = texture["index"] as? Int {
            let textureImage = resized(try glb.image(index), maxDimension: 256)
            material.metalness.contents = textureImage; material.metalness.textureComponents = .blue
            material.roughness.contents = textureImage; material.roughness.textureComponents = .green
        }
        if let texture = info["normalTexture"] as? [String: Any], let index = texture["index"] as? Int {
            material.normal.contents = resized(try glb.image(index), maxDimension: 512)
            material.normal.intensity = texture["scale"] as? CGFloat ?? 1
        }
        if let alpha = info["alphaMode"] as? String, alpha == "BLEND" { material.blendMode = .alpha }
        // glTF UV origin is upper-left; SceneKit image textures use the same decoded image orientation.
        for property in [material.diffuse, material.normal, material.roughness, material.metalness] {
            property.wrapS = .repeat; property.wrapT = .repeat
            property.magnificationFilter = .linear; property.minificationFilter = .linear; property.mipFilter = .linear
        }
        return material
    }
    let meshes = glb.array("meshes"), skins = glb.array("skins")
    var meshReport: [[String: Any]] = []
    for (nodeIndex, info) in nodeInfo.enumerated() {
        guard let meshIndex = info["mesh"] as? Int else { continue }
        let mesh = meshes[meshIndex]
        for (primitiveIndex, primitive) in (mesh["primitives"] as? [[String: Any]] ?? []).enumerated() {
            guard (primitive["mode"] as? Int ?? 4) == 4,
                  let attributes = primitive["attributes"] as? [String: Int],
                  let positionIndex = attributes["POSITION"] else { throw fail("Expected triangle mesh positions") }
            var sources: [SCNGeometrySource] = []
            let positions = try glb.accessor(positionIndex)
            sources.append(geometrySource(positions.values, positions.count, positions.components, .vertex))
            for (key, semantic) in [("NORMAL", SCNGeometrySource.Semantic.normal), ("TEXCOORD_0", .texcoord), ("TANGENT", .tangent)] {
                if let index = attributes[key] {
                    let values = try glb.accessor(index)
                    sources.append(geometrySource(values.values, values.count, values.components, semantic))
                }
            }
            let indices: [UInt32]
            if let index = primitive["indices"] as? Int { indices = try glb.accessor(index).values.map { UInt32($0) } }
            else { indices = (0..<positions.count).map(UInt32.init) }
            let element = SCNGeometryElement(data: packed(indices), primitiveType: .triangles, primitiveCount: indices.count / 3, bytesPerIndex: 4)
            let geometry = SCNGeometry(sources: sources, elements: [element])
            if let materialIndex = primitive["material"] as? Int { geometry.materials = [materials[materialIndex]] }
            let meshNode = SCNNode(geometry: geometry)
            meshNode.name = "\(nodes[nodeIndex].name ?? "mesh")_primitive_\(primitiveIndex)"
            nodes[nodeIndex].addChildNode(meshNode)
            var report: [String: Any] = ["node": meshNode.name!, "vertices": positions.count, "triangles": indices.count / 3]
            if let skinIndex = info["skin"] as? Int {
                let skin = skins[skinIndex]
                guard let joints = skin["joints"] as? [Int] else { throw fail("Missing skin joints") }
                var weightSets: [[Float]] = [], jointSets: [[Float]] = []
                var set = 0
                while let weightIndex = attributes["WEIGHTS_\(set)"], let jointIndex = attributes["JOINTS_\(set)"] {
                    weightSets.append(try glb.accessor(weightIndex).values)
                    jointSets.append(try glb.accessor(jointIndex).values); set += 1
                }
                guard !weightSets.isEmpty else { throw fail("Skinned mesh has no weights") }
                let influenceCount = weightSets.count * 4
                var weights = [Float](); weights.reserveCapacity(positions.count * influenceCount)
                var jointIndices = [UInt16](); jointIndices.reserveCapacity(positions.count * influenceCount)
                var droppedTotal: Float = 0, droppedMaximum: Float = 0
                for vertex in 0..<positions.count {
                    var influences: [(weight: Float, joint: UInt16)] = []
                    for set in weightSets.indices { for component in 0..<4 {
                        let offset = vertex * 4 + component
                        let weight = weightSets[set][offset]
                        if weight > 0 { influences.append((weight, UInt16(jointSets[set][offset]))) }
                    }}
                    influences.sort { $0.weight > $1.weight }
                    let strongest = Array(influences.prefix(influenceCount)); let total = strongest.reduce(Float(0)) { $0 + $1.weight }
                    let dropped = influences.dropFirst(influenceCount).reduce(Float(0)) { $0 + $1.weight }
                    droppedTotal += dropped; droppedMaximum = max(droppedMaximum, dropped)
                    for component in 0..<influenceCount {
                        weights.append(component < strongest.count && total > 0 ? strongest[component].weight / total : (component == 0 && total == 0 ? 1 : 0))
                        jointIndices.append(component < strongest.count ? strongest[component].joint : 0)
                    }
                }
                let weightSource = geometrySource(weights, positions.count, influenceCount, .boneWeights)
                let jointSource = SCNGeometrySource(data: packed(jointIndices), semantic: .boneIndices,
                    vectorCount: positions.count, usesFloatComponents: false, componentsPerVector: influenceCount,
                    bytesPerComponent: 2, dataOffset: 0, dataStride: influenceCount * 2)
                let inverseBinds: [NSValue]
                if let accessor = skin["inverseBindMatrices"] as? Int {
                    let values = try glb.accessor(accessor).values
                    inverseBinds = joints.indices.map { NSValue(scnMatrix4: SCNMatrix4(matrix(Array(values[$0 * 16 ..< $0 * 16 + 16])))) }
                } else { inverseBinds = joints.map { _ in NSValue(scnMatrix4: SCNMatrix4Identity) } }
                let skinner = SCNSkinner(baseGeometry: geometry, bones: joints.map { nodes[$0] },
                                        boneInverseBindTransforms: inverseBinds, boneWeights: weightSource, boneIndices: jointSource)
                if let skeleton = skin["skeleton"] as? Int { skinner.skeleton = nodes[skeleton] }
                else if let commonRoot = nodes[joints[0]].parent { skinner.skeleton = commonRoot }
                meshNode.skinner = skinner
                // glTF skin transforms are expressed in scene space; the mesh-node's
                // transform does not affect skinned positions. Keep its rest bounds
                // in that same space (critical for exports with a 0.01 armature scale).
                scene.rootNode.addChildNode(meshNode)
                report["bones"] = joints.count
                report["sourceInfluencesPerVertex"] = weightSets.count * 4
                report["meanDroppedWeight"] = droppedTotal / Float(positions.count)
                report["maximumDroppedWeight"] = droppedMaximum
            }
            meshReport.append(report)
        }
    }
    let jointIndices = Set(skins.flatMap { $0["joints"] as? [Int] ?? [] })
    let joints: [[String: Any]] = nodeInfo.indices.filter { jointIndices.contains($0) }.map { index in
        let node = nodes[index]
        let q = node.simdOrientation.vector
        return ["name": node.name!, "parent": node.parent?.name ?? "scene",
                "position": xyz(node.simdPosition), "worldPosition": xyz(node.simdWorldPosition),
                "rotation": [q.x,q.y,q.z,q.w],
                "children": node.childNodes.compactMap(\.name)]
    }
    let report: [String: Any] = ["source": source.lastPathComponent, "meshes": meshReport,
        "sourceAnimations": (glb.json["animations"] as? [Any] ?? []).count,
        "joints": joints,
        "boundsMin": [scene.rootNode.boundingBox.min.x,scene.rootNode.boundingBox.min.y,scene.rootNode.boundingBox.min.z],
        "boundsMax": [scene.rootNode.boundingBox.max.x,scene.rootNode.boundingBox.max.y,scene.rootNode.boundingBox.max.z]]
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard scene.write(to: destination, options: nil, delegate: nil, progressHandler: nil) else { throw fail("SceneKit failed to write \(destination.path)") }
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: destination.deletingPathExtension().appendingPathExtension("rig.json"))
    let reloaded = try SCNScene(url: destination, options: nil)
    var skinCount = 0, geometryCount = 0
    reloaded.rootNode.enumerateChildNodes { node, _ in
        if node.skinner != nil { skinCount += 1 }; if node.geometry != nil { geometryCount += 1 }
    }
    print("Converted \(source.lastPathComponent) -> \(destination.path): \(geometryCount) meshes, \(skinCount) skins, \(joints.count) joints")
    for mesh in meshReport { print(mesh) }
}

do {
    guard CommandLine.arguments.count == 3 else { throw fail("Usage: swift scripts/convert_meshy_glb.swift source.glb destination.scn") }
    try convert(source: URL(fileURLWithPath: CommandLine.arguments[1]), destination: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch { fputs("Conversion failed: \(error)\n", stderr); exit(1) }
