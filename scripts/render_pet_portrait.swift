#!/usr/bin/env swift
// Render transparent portraits with complete horns, tails and wing silhouettes.
// Usage: swift scripts/render_pet_portrait.swift source.scn output.png [size]
//        [--yaw-degrees 11.31] [--elevation-degrees 2.70] [--padding 0.12]
// modelYawDegrees from adjacent .motion.json matches the app's forward direction.
// CLI angles adjust the camera, without changing the source asset or profile.
import Foundation
import AppKit
import SceneKit
import Metal
import simd

func failure(_ message: String) -> NSError {
    NSError(domain: "PawPacePortrait", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

func render() throws {
    let args = CommandLine.arguments
    guard args.count >= 3 else { throw failure("Expected source.scn output.png [size] [camera options]") }
    let source = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
    var size = 512, index = 3
    var yawDegrees = 11.31, elevationDegrees = 2.70, padding = 0.12
    if args.indices.contains(index), let requested = Int(args[index]) { size = requested; index += 1 }
    while index < args.count {
        guard args.indices.contains(index + 1), let value = Double(args[index + 1]), value.isFinite else {
            throw failure("Expected a finite value after \(args[index])")
        }
        switch args[index] {
        case "--yaw-degrees": yawDegrees = value
        case "--elevation-degrees": elevationDegrees = value
        case "--padding": padding = value
        default: throw failure("Unknown portrait option: \(args[index])")
        }
        index += 2
    }
    guard (128...4096).contains(size), (-75...75).contains(elevationDegrees), (0.02...0.45).contains(padding) else {
        throw failure("Size must be 128...4096, elevation -75...75, and padding 0.02...0.45")
    }
    let scene = try SCNScene(url: source, options: [.checkConsistency: true])
    let profileURL = source.deletingPathExtension().appendingPathExtension("motion.json")
    var modelYaw: Float = 0
    if FileManager.default.fileExists(atPath: profileURL.path) {
        guard let profile = try JSONSerialization.jsonObject(with: Data(contentsOf: profileURL)) as? [String: Any] else {
            throw failure("Malformed motion profile beside source scene")
        }
        if let yaw = profile["modelYawDegrees"] as? NSNumber {
            modelYaw = yaw.floatValue
            guard modelYaw.isFinite else { throw failure("Nonfinite modelYawDegrees in motion profile") }
        }
    }
    if modelYaw != 0 {
        let orientation = SCNNode()
        orientation.name = "portrait-model-orientation"
        for child in scene.rootNode.childNodes { orientation.addChildNode(child) }
        orientation.simdEulerAngles.y = modelYaw * .pi / 180
        scene.rootNode.addChildNode(orientation)
    }
    let bounds = scene.rootNode.boundingBox
    let minimum = SIMD3<Float>(bounds.min), maximum = SIMD3<Float>(bounds.max)
    let extent = maximum - minimum
    let diameter = max(extent.x, max(extent.y, extent.z))
    guard diameter.isFinite, diameter > 0.001 else { throw failure("Scene has no finite model bounds") }
    let center = (minimum + maximum) * 0.5
    scene.background.contents = NSColor.clear
    scene.rootNode.enumerateChildNodes { node, _ in
        node.removeAllAnimations()
        for material in node.geometry?.materials ?? [] {
            material.metalness.contents = 0
            material.roughness.contents = 0.85
        }
    }
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera!.usesOrthographicProjection = true
    camera.camera!.zNear = Double(diameter) * 0.01
    camera.camera!.zFar = Double(diameter) * 12
    let yaw = Float(yawDegrees) * .pi / 180, elevation = Float(elevationDegrees) * .pi / 180
    let direction = SIMD3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
    camera.simdPosition = center + direction * diameter * 4
    camera.look(at: SCNVector3(center))
    scene.rootNode.addChildNode(camera)
    // Fit the projected width as well as height. Using height alone clips broad
    // creatures and long tails in the square Watch and widget portraits.
    let view = camera.simdWorldTransform.inverse
    var projectedMinimum = SIMD2<Float>(repeating: .infinity)
    var projectedMaximum = SIMD2<Float>(repeating: -.infinity)
    for x in [minimum.x, maximum.x] {
        for y in [minimum.y, maximum.y] {
            for z in [minimum.z, maximum.z] {
                let point = view * SIMD4(x, y, z, 1)
                projectedMinimum = simd_min(projectedMinimum, SIMD2(point.x, point.y))
                projectedMaximum = simd_max(projectedMaximum, SIMD2(point.x, point.y))
            }
        }
    }
    let projectedExtent = projectedMaximum - projectedMinimum
    camera.camera!.orthographicScale = Double(max(projectedExtent.x, projectedExtent.y)) / (2 * (1 - padding))
    let ambient = SCNNode()
    ambient.light = SCNLight(); ambient.light!.type = .ambient
    ambient.light!.intensity = 550; ambient.light!.color = NSColor.white
    scene.rootNode.addChildNode(ambient)
    let key = SCNNode()
    key.light = SCNLight(); key.light!.type = .directional
    key.light!.intensity = 1000; key.light!.color = NSColor(calibratedRed: 1, green: 0.96, blue: 0.90, alpha: 1)
    key.simdPosition = center + SIMD3(2, 3, 3) * diameter; key.look(at: SCNVector3(center))
    scene.rootNode.addChildNode(key)
    let fill = SCNNode()
    fill.light = SCNLight(); fill.light!.type = .directional
    fill.light!.intensity = 500; fill.light!.color = NSColor(calibratedRed: 0.85, green: 0.92, blue: 1, alpha: 1)
    fill.simdPosition = center + SIMD3(-2, 1, -1) * diameter; fill.look(at: SCNVector3(center))
    scene.rootNode.addChildNode(fill)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene; renderer.pointOfView = camera
    let image = renderer.snapshot(atTime: 0, with: NSSize(width: size, height: size), antialiasingMode: .multisampling4X)
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else { throw failure("Snapshot failed") }
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: output)
    print("\(output.path) (\(size)×\(size), model yaw \(modelYaw)°, camera yaw \(yawDegrees)°, padding \(padding))")
}

do { try render() }
catch { fputs("Portrait failed: \(error.localizedDescription)\n", stderr); exit(1) }
