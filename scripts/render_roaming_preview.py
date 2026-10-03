#!/usr/bin/env python3
"""Render the current iOS companion implementation offline on macOS.

Only platform adapters and read-only audit observations are injected. The rig,
field, controller and shared enums are extracted from the checkout each run.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
COMPANION = ROOT / 'PawPace/Features/Companion'


def declaration(source: str, marker: str) -> str:
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    position = opening + 1
    while depth:
        if source[position] == '{':
            depth += 1
        elif source[position] == '}':
            depth -= 1
        position += 1
    return source[start:position]


def main():
    shared = (ROOT / 'Shared/PawPaceShared.swift').read_text()
    species_body = declaration(shared, 'enum PetSpecies:').split('var id:', 1)[0]
    species_names = [raw or name for name, raw in re.findall(
        r'^\s*case\s+(\w+)(?:\s*=\s*"([^"]+)")?\s*$', species_body, re.MULTILINE)]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/pawpace-roaming-preview'))
    parser.add_argument('--species', choices=['all'] + species_names, default='all')
    parser.add_argument('--seconds', type=float, default=42, help='Roaming video duration (0 skips all video).')
    parser.add_argument('--audit-seconds', type=float, default=180)
    parser.add_argument('--fps', type=int, default=30)
    parser.add_argument('--width', type=int, default=720)
    parser.add_argument('--height', type=int, default=680)
    parser.add_argument('--compile-only', action='store_true')
    args = parser.parse_args()
    if args.seconds < 0 or args.audit_seconds < 0 or not 1 <= args.fps <= 120:
        parser.error('Durations must be nonnegative and fps must be 1...120.')
    if args.width <= 0 or args.height <= 0 or args.width % 2 or args.height % 2:
        parser.error('Video dimensions must be positive even integers.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source_files = [ROOT / 'Shared/PawPaceShared.swift', ROOT / 'Shared/PetLifecycle.swift', ROOT / 'Shared/BuddyBond.swift', ROOT / 'Shared/BuddyKeepsakes.swift',
                    ROOT / 'SharedUI/MochiCreatureView.swift',
                    COMPANION / 'AnimalCompanionView.swift', COMPANION / 'CompanionField.swift',
                    COMPANION / 'CompanionRoaming.swift', COMPANION / 'CompanionRigProfile.swift',
                    COMPANION / 'CompanionSpecialEffects.swift', Path(__file__),
                    ROOT / 'scripts/render_roaming_preview.swift']
    sources = {path: path.read_text() for path in source_files}
    rig = declaration(sources[COMPANION / 'AnimalCompanionView.swift'], '@MainActor\nfinal class CompanionRig')
    lookup = r'let assetURL = Bundle\.main\.url\(forResource: species\.rawValue, withExtension: "scn", subdirectory: "Animals"\)\s*\?\? Bundle\.main\.url\(forResource: species\.rawValue, withExtension: "scn"\)'
    rig, count = re.subn(lookup, 'let assetURL: URL? = PreviewEnvironment.assets.appendingPathComponent(species.rawValue + ".scn")', rig)
    if count != 1:
        raise RuntimeError('Asset lookup changed; update this platform adapter before rendering.')
    profile = sources[COMPANION / 'CompanionRigProfile.swift']
    profile_lookup = r'let url = bundle\.url\(forResource: species\.rawValue, withExtension: "motion.json", subdirectory: "Animals"\)\s*\?\? bundle\.url\(forResource: species\.rawValue, withExtension: "motion.json"\)'
    profile, count = re.subn(profile_lookup,
        'let url: URL? = PreviewEnvironment.assets.appendingPathComponent(species.rawValue + ".motion.json")', profile)
    if count != 1:
        raise RuntimeError('Motion profile lookup changed; update this platform adapter before rendering.')
    for old, new in [('-(bounds.min.x + bounds.max.x)', '-Float(bounds.min.x + bounds.max.x)'),
                     ('-bounds.min.y * modelScale', '-Float(bounds.min.y) * modelScale'),
                     ('-(bounds.min.z + bounds.max.z)', '-Float(bounds.min.z + bounds.max.z)'),
                     ('strand.position.y =', 'strand.simdPosition.y =')]:
        rig = rig.replace(old, new)
    field = sources[COMPANION / 'CompanionField.swift'].replace('import UIKit', 'import AppKit')
    effects = sources[COMPANION / 'CompanionSpecialEffects.swift'].replace('import UIKit', 'import AppKit')
    # UIKit SCNVector3 uses Float; macOS SCNVector3 uses CGFloat. SIMD is Float on both.
    # Adapt reads as well as writes so node-to-node component copies retain Float.
    field = re.sub(r'\.eulerAngles\.([xyz])\b', r'.simdEulerAngles.\1', field)
    rig = re.sub(r'\.eulerAngles\.([xyz])\b', r'.simdEulerAngles.\1', rig)
    generated = '\n\n'.join([
        'import Foundation\nimport AppKit\nimport SceneKit\nimport simd',
        declaration(sources[ROOT / 'Shared/PawPaceShared.swift'], 'enum PetSpeciesRarity:'),
        declaration(sources[ROOT / 'Shared/PawPaceShared.swift'], 'enum PetSpecies:'),
        declaration(sources[ROOT / 'Shared/PetLifecycle.swift'], 'enum PetLifeStage:'),
        declaration(sources[ROOT / 'Shared/PetLifecycle.swift'], 'enum PetColorVariant:'),
        declaration(sources[ROOT / 'Shared/BuddyBond.swift'], 'enum BuddyTemperament:'),
        declaration(sources[ROOT / 'Shared/BuddyKeepsakes.swift'], 'enum HabitatDecoration:'),
        declaration(sources[ROOT / 'Shared/BuddyKeepsakes.swift'], 'enum HabitatSpot:'),
        declaration(sources[ROOT / 'Shared/BuddyKeepsakes.swift'], 'struct HabitatPlacement:'),
        declaration(sources[ROOT / 'SharedUI/MochiCreatureView.swift'], 'enum PetMotion:'),
        sources[COMPANION / 'CompanionRoaming.swift'], field, profile, effects,
        declaration(sources[COMPANION / 'AnimalCompanionView.swift'], 'enum CompanionCameraZoom'), rig,
        '''// Read-only audit access, kept out of application code.
extension CompanionRig {
    func previewFootPlants() -> [(name: String, anchor: SIMD3<Float>, actual: SIMD3<Float>)] {
        plantedFeet.compactMap { name, planted in
            guard let joint = joints[name] else { return nil }
            return (name, planted.position, joint.node.simdWorldPosition)
        }
    }
}
'''])
    generated_path = output / 'CurrentCompanion.swift'
    generated_path.write_text(generated)
    manifest = {'sources': {str(path.relative_to(ROOT)): hashlib.sha256(sources[path].encode()).hexdigest()
                            for path in source_files},
                'arguments': {key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()},
                'assets': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in sorted((ROOT / 'PawPace/Resources/Animals').iterdir())
                           if path.name.endswith(('.scn', '.motion.json'))},
                'adaptations': ['UIKit→AppKit color/image/path shim', 'Bundle asset lookup→repository asset directory',
                                'macOS SCNVector3 component casts and SIMD Euler components', 'read-only planted-foot observations',
                                'motion profile Bundle lookup→repository asset directory',
                                'opaque pale habitat backdrop for exported media']}
    (output / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    harness_path = output / 'PreviewHarness.swift'
    harness_path.write_text(sources[ROOT / 'scripts/render_roaming_preview.swift'])
    executable = output / 'render-roaming-preview'
    subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', str(generated_path),
                    str(harness_path), '-o', str(executable)], check=True)
    if args.compile_only:
        print(f'Compiled {executable}')
        return
    subprocess.run([str(executable), str(ROOT / 'PawPace/Resources/Animals'), str(output), args.species,
                    str(args.seconds), str(args.audit_seconds), str(args.fps), str(args.width), str(args.height)], check=True)
    print(f'Preview and audit: {output}')


if __name__ == '__main__':
    main()
