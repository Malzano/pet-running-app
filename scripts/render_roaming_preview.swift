// Invoke with scripts/render_roaming_preview.py, which supplies current app sources.
import Foundation
import AppKit
import SceneKit
import simd
import Metal
import AVFoundation
import CoreVideo

// Small UIKit adapter: preserve the production shadow renderer unchanged.
typealias UIColor = NSColor
typealias UIImage = NSImage
typealias UIBezierPath = NSBezierPath
extension NSBezierPath {
    func addLine(to point: CGPoint) { line(to: point) }
}
struct UIGraphicsImageRendererContext { let cgContext: CGContext }
struct UIGraphicsImageRenderer {
    let size: CGSize
    func image(actions: (UIGraphicsImageRendererContext) -> Void) -> NSImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        actions(UIGraphicsImageRendererContext(cgContext: context))
        return NSImage(cgImage: context.makeImage()!, size: size)
    }
}

enum PreviewEnvironment {
    static var backdrop: NSColor { NSColor(red: 237.0 / 255, green: 241.0 / 255, blue: 232.0 / 255, alpha: 1) }
    static var assets: URL { URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) }
}

private struct Influence { var index: Int; var weight: Float }
private struct SkinVertex { var point: SIMD4<Float>; var influences: [Influence] }

/// CPU skinning measures the real deforming silhouette, not the static bind box.
@MainActor
private struct SkinBounds {
    let skinner: SCNSkinner
    let vertices: [SkinVertex]
    let inverses: [simd_float4x4]

    init?(_ node: SCNNode) {
        guard let skin = node.skinner, let geometry = skin.baseGeometry,
              let positions = geometry.sources(for: .vertex).first,
              let inverse = skin.boneInverseBindTransforms else { return nil }
        skinner = skin
        inverses = inverse.map { simd_float4x4($0.scnMatrix4Value) }
        let points = SourceReader(positions), weights = SourceReader(skin.boneWeights), indices = SourceReader(skin.boneIndices)
        vertices = (0..<positions.vectorCount).map { index in
            let point = SIMD4(points.number(index, 0), points.number(index, 1), points.number(index, 2), 1)
            let influences = (0..<weights.components).compactMap { component -> Influence? in
                let weight = weights.number(index, component)
                return weight > 0 ? Influence(index: Int(indices.number(index, component)), weight: weight) : nil
            }
            return SkinVertex(point: point, influences: influences)
        }
    }

    private struct SourceReader {
        let data: Data
        let offset: Int, stride: Int, bytes: Int, components: Int
        let floating: Bool
        init(_ source: SCNGeometrySource) {
            data = source.data; offset = source.dataOffset; stride = source.dataStride
            bytes = source.bytesPerComponent; components = source.componentsPerVector
            floating = source.usesFloatComponents
        }
        func number(_ vector: Int, _ component: Int) -> Float {
            let position = offset + stride * vector + bytes * component
            return data.withUnsafeBytes { buffer in
                if floating {
                    if bytes == 8 { return Float(buffer.loadUnaligned(fromByteOffset: position, as: Double.self)) }
                    return buffer.loadUnaligned(fromByteOffset: position, as: Float.self)
                }
                if bytes == 1 { return Float(buffer.loadUnaligned(fromByteOffset: position, as: UInt8.self)) }
                if bytes == 2 { return Float(buffer.loadUnaligned(fromByteOffset: position, as: UInt16.self)) }
                return Float(buffer.loadUnaligned(fromByteOffset: position, as: UInt32.self))
            }
        }
    }

    func projectedExtents(camera: SCNNode, aspect: Float) -> SIMD4<Float> {
        let view = camera.simdWorldTransform.inverse
        let scale = Float(camera.camera!.orthographicScale)
        let transforms = zip(skinner.bones, inverses).map { view * $0.simdWorldTransform * $1 }
        var result = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
        for vertex in vertices {
            var p = SIMD4<Float>.zero
            for influence in vertex.influences { p += transforms[influence.index] * vertex.point * influence.weight }
            let x = 0.5 + p.x / (2 * scale * aspect)
            let y = 0.5 - p.y / (2 * scale)
            result = SIMD4(min(result.x, x), min(result.y, y), max(result.z, x), max(result.w, y))
        }
        return result
    }
}

@MainActor
private func groundBounds(scene: SCNScene, camera: SCNNode, aspect: Float) -> SIMD4<Float> {
    let view = camera.simdWorldTransform.inverse
    let scale = Float(camera.camera!.orthographicScale)
    var result = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
    scene.rootNode.enumerateChildNodes { node, _ in
        guard node.name == "habitat-ground", let source = node.geometry?.sources(for: .vertex).first else { return }
        let data = source.data, stride = source.dataStride, offset = source.dataOffset, bytes = source.bytesPerComponent
        let transform = view * node.simdWorldTransform
        data.withUnsafeBytes { buffer in
            for index in 0..<source.vectorCount {
                func value(_ component: Int) -> Float {
                    let position = offset + stride * index + bytes * component
                    return bytes == 8 ? Float(buffer.loadUnaligned(fromByteOffset: position, as: Double.self))
                                      : buffer.loadUnaligned(fromByteOffset: position, as: Float.self)
                }
                let p = transform * SIMD4(value(0), value(1), value(2), 1)
                let x = 0.5 + p.x / (2 * scale * aspect), y = 0.5 - p.y / (2 * scale)
                result = SIMD4(min(result.x, x), min(result.y, y), max(result.z, x), max(result.w, y))
            }
        }
    }
    return result
}

@MainActor
private final class Video {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let width: Int
    let height: Int
    let fps: Int32

    init(url: URL, width: Int, height: Int, fps: Int) throws {
        try? FileManager.default.removeItem(at: url)
        self.width = width; self.height = height; self.fps = Int32(fps)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000, AVVideoExpectedSourceFrameRateKey: fps]])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: NSImage, frame: Int) throws {
        while !input.isReadyForMoreMediaData {
            if let error = writer.error { throw error }
            Thread.sleep(forTimeInterval: 0.001)
        }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { throw PreviewError.message("Cannot allocate video frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.setFillColor(PreviewEnvironment.backdrop.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
            throw writer.error ?? PreviewError.message("Video append failed")
        }
    }

    func finish() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }
}

enum PreviewError: Error { case message(String) }

@MainActor
@main
struct RoamingPreview {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 9 else { throw PreviewError.message("Run scripts/render_roaming_preview.py") }
        let output = URL(fileURLWithPath: args[2], isDirectory: true)
        let species = args[3] == "all" ? PetSpecies.allCases : [PetSpecies(rawValue: args[3])!]
        let seconds = Double(args[4])!, auditSeconds = Double(args[5])!, fps = Int(args[6])!
        let width = Int(args[7])!, height = Int(args[8])!
        var reports: [[String: Any]] = []
        for animal in species {
            guard let rig = CompanionRig(species: animal) else { throw PreviewError.message("Could not load \(animal.rawValue)") }
            rig.configureHabitat(roaming: true)
            rig.resizeViewport(CGSize(width: width, height: height))
            // Export the transparent native scene against the surrounding habitat color.
            rig.scene.background.contents = PreviewEnvironment.backdrop
            rig.showsProps = true
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice())
            renderer.scene = rig.scene; renderer.pointOfView = rig.camera
            renderer.autoenablesDefaultLighting = false
            var skins: [SkinBounds] = []
            rig.scene.rootNode.enumerateChildNodes { node, _ in if let skin = SkinBounds(node) { skins.append(skin) } }
            guard !skins.isEmpty else { throw PreviewError.message("No skinned vertices to audit") }
            let video = seconds > 0 ? try Video(url: output.appendingPathComponent("\(animal.rawValue)-roaming.mp4"), width: width, height: height, fps: fps) : nil
            var roaming = CompanionRoaming(species: animal)
            var weights = SIMD4<Float>.zero, feeding: Float = 0
            var specialTime: Float = 0, specialWeight: Float = 0
            var previousAction = PetMotion.idle
            var extents = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
            var maxEllipse: Float = 0, auditSamples = 0, clippedSamples = 0
            var plantDrift: [Float] = [], turningDrift: [Float] = [], straightDrift: [Float] = []
            var actions = Set<String>(), savedActions = Set<String>(), nextVideoFrame = 0
            let rate = max(60, fps), dt = Float(1) / Float(rate)
            let totalFrames = Int(ceil(max(seconds, auditSeconds) * Double(rate)))
            for frame in 0..<max(totalFrames, 1) {
                try autoreleasepool {
                let time = Double(frame) / Double(rate)
                // A real approach precedes each interaction; no pose teleportation.
                if frame == 3 * rate { roaming.request(.play) }
                if frame == 14 * rate { roaming.request(.feed) }
                if frame == 27 * rate { roaming.request(.greet) }
                if frame == 34 * rate { roaming.request(animal.specialMoveName == nil ? .wander : .special) }
                let pose = roaming.step(deltaTime: dt)
                specialTime += dt
                if pose.action != previousAction, pose.action == .special { specialTime = 0 }
                previousAction = pose.action
                let action = String(describing: pose.action)
                actions.insert(action)
                var target = SIMD4<Float>.zero
                switch pose.action {
                case .walking: target.x = 1
                case .running: target.y = 1
                case .jumping: target.z = 1
                case .playing, .celebrating: target.w = 1
                case .feeding, .special: break
                case .idle: target.x = min(1, abs(pose.turnRate) > 0.15 ? abs(pose.turnRate) * 1.3 : 0)
                }
                weights += (target - weights) * (1 - exp(-dt * 9))
                feeding += ((pose.action == .feeding ? Float(1) : 0) - feeding) * (1 - exp(-dt * 9))
                specialWeight += ((pose.action == .special ? Float(1) : 0) - specialWeight) * (1 - exp(-dt * 9))
                rig.pose(time: Float(time), phase: pose.gaitDistance / rig.walkCycleDistance, weights: weights,
                         feeding: feeding, actionTime: pose.actionTime, jumpTime: pose.actionTime, roaming: pose,
                         specialTime: specialTime, specialWeight: specialWeight)
                SCNTransaction.flush()
                CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.00001, false)
                let ellipse = pose.position / CompanionRoaming.fieldRadii
                maxEllipse = max(maxEllipse, simd_length_squared(ellipse))
                for plant in rig.previewFootPlants() {
                    let delta = plant.actual - plant.anchor
                    let drift = simd_length(SIMD2(delta.x, delta.z))
                    plantDrift.append(drift)
                    if abs(pose.turnRate) > 0.25 { turningDrift.append(drift) } else { straightDrift.append(drift) }
                }
                if frame % rate == 0 || frame == totalFrames - 1 {
                    var current = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
                    for skin in skins {
                        let b = skin.projectedExtents(camera: rig.camera, aspect: Float(width) / Float(height))
                        current = SIMD4(min(current.x, b.x), min(current.y, b.y), max(current.z, b.z), max(current.w, b.w))
                    }
                    extents = SIMD4(min(extents.x, current.x), min(extents.y, current.y), max(extents.z, current.z), max(extents.w, current.w))
                    auditSamples += 1
                    if current.x < 0 || current.y < 0 || current.z > 1 || current.w > 1 { clippedSamples += 1 }
                }
                let captureVideo = video != nil && time < seconds && time + 0.00001 >= Double(nextVideoFrame) / Double(fps)
                let captureStill = !savedActions.contains(action) && (pose.actionTime > 0.4 || frame == 0)
                if captureVideo || captureStill {
                    try autoreleasepool {
                        let image = renderer.snapshot(atTime: time, with: CGSize(width: width, height: height), antialiasingMode: .multisampling4X)
                        if captureVideo { try video!.append(image, frame: nextVideoFrame); nextVideoFrame += 1 }
                        if captureStill {
                            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(animal.rawValue)-\(action).png"))
                            savedActions.insert(action)
                        }
                    }
                }
                }
            }
            if let video { try await video.finish() }
            func driftReport(_ values: [Float]) -> [String: Any] {
                let sorted = values.sorted()
                return ["samples": sorted.count, "maximum_world_units": sorted.last ?? 0,
                        "p95_world_units": sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]]
            }
            let ground = groundBounds(scene: rig.scene, camera: rig.camera, aspect: Float(width) / Float(height))
            let report: [String: Any] = ["species": animal.rawValue, "simulated_seconds": max(seconds, auditSeconds),
                "gait_cycle_world_units": rig.walkCycleDistance, "maximum_ground_ellipse_squared_radius": maxEllipse,
                "camera_pet_bounds_normalized": [extents.x, extents.y, extents.z, extents.w], "camera_samples": auditSamples,
                "camera_ground_bounds_normalized": [ground.x, ground.y, ground.z, ground.w],
                "camera_clipped_samples": clippedSamples, "observed_actions": actions.sorted(),
                "stance_horizontal_anchor_error": driftReport(plantDrift), "turning_anchor_error": driftReport(turningDrift),
                "straight_anchor_error": driftReport(straightDrift), "video_frames": nextVideoFrame]
            reports.append(report)
            print("\(animal.displayName): \(clippedSamples)/\(auditSamples) clipped samples; stance p95 \(driftReport(plantDrift)["p95_world_units"]!)")
            if animal.specialMoveName != nil {
                try await renderSpecial(species: animal, output: output, videos: seconds > 0, width: width, height: height, fps: fps)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["reports": reports, "notes": [
            "Camera bounds use all skinned mesh vertices at one-second intervals, in the actual configured orthographic camera.",
            "Anchor error measures planted foot bone versus stored world anchor each 60Hz step; contact skin may differ from its bone pivot.",
            "Platform adapter changes drawing/types/asset lookup only. source-manifest.json records exact input source hashes.",
            "Offline Metal rendering verifies scene geometry and animation; device frame pacing and touch input still require native runtime testing."]], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("audit.json"))
    }

    /// A separate close view makes every signature motion reviewable even when
    /// the roaming preview is shorter than its scripted interaction schedule.
    private static func renderSpecial(species: PetSpecies, output: URL, videos: Bool, width: Int, height: Int, fps: Int) async throws {
        guard let rig = CompanionRig(species: species) else { throw PreviewError.message("Could not load \(species.rawValue)") }
        rig.resizeViewport(CGSize(width: width, height: height))
        rig.scene.background.contents = PreviewEnvironment.backdrop
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice())
        renderer.scene = rig.scene
        renderer.pointOfView = rig.camera
        let video = videos ? try Video(url: output.appendingPathComponent("\(species.rawValue)-special.mp4"), width: width, height: height, fps: fps) : nil
        let frames = videos ? 6 * fps : 1
        for frame in 0..<frames {
            try autoreleasepool {
                let time = videos ? Float(frame) / Float(fps) : 2
                let specialTime = videos ? max(0, time - 0.6) : 2
                let weight: Float = !videos || (time >= 0.6 && specialTime < CompanionSpecialEffects.duration) ? 1 : 0
                rig.pose(time: time, phase: time * 0.5, weights: .zero, specialTime: specialTime, specialWeight: weight)
                SCNTransaction.flush()
                let image = renderer.snapshot(atTime: Double(time), with: CGSize(width: width, height: height), antialiasingMode: .multisampling4X)
                if let video { try video.append(image, frame: frame) }
                if !videos || frame == Int(2.6 * Double(fps)) {
                    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(species.rawValue)-special.png"))
                }
            }
        }
        if let video { try await video.finish() }
    }
}
