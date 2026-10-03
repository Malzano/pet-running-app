# Mobile Meshy assets

Keep the downloaded, rigged originals in `design/meshy-source`. Derive mobile assets without remeshing or replacing the source skeleton:

```sh
npm install --prefix /tmp/pawpace-mesh-tools --no-audit --no-fund \
  @gltf-transform/core@4.5.0 @gltf-transform/functions@4.5.0 \
  @gltf-transform/extensions@4.5.0 meshoptimizer@1.2.0

node scripts/optimize_meshy_glb.mjs \
  design/meshy-source/red-panda.glb \
  design/meshy-source/optimized/red-panda.glb 30000 0.02

swift scripts/convert_meshy_glb.swift \
  design/meshy-source/optimized/red-panda.glb \
  PawPace/Resources/Animals/red-panda.scn

swift scripts/render_pet_portrait.swift \
  PawPace/Resources/Animals/red-panda.scn \
  SharedUI/AnimalPortraits.xcassets/pet-red-panda.imageset/portrait.png
```

The optimizer uses exact attribute welding, meshoptimizer's index-only simplifier with `Regularize`, and compaction. Surviving vertices retain every attribute byte, including all `JOINTS_n` and `WEIGHTS_n` streams. Bone indices are not treated as interpolated numeric attributes. Skeleton hierarchy, original transforms, inverse bind matrices, animation channels and embedded texture hashes are verified before and after serialization. A written `.optimization.json` records source/output SHA-256 hashes, geometry error and triangle counts. The original file is never overwritten.

glTF Transform's writer can normalize near-unit TRS values. The script restores the original node transform fields into the derived GLB and verifies the reloaded skeleton against the source. It does not run a general optimization preset, prune skeleton nodes, cap influences, quantize attributes, or change textures. The SceneKit converter separately resizes textures and authors the runtime rig report.

The requested triangle count is a target subject to the error bound. Check `totalTriangles` in the report rather than assuming the target was met. Sources already around 30,000 triangles can be converted directly. Always inspect the converted portrait, ordinary movement and signature movement after reduction; an error bound does not replace visual checks.

New species require a reviewed `<species>.motion.json` beside the scene. `modelYawDegrees`, when present, is also honored by the portrait renderer. Its camera can be adjusted with `--yaw-degrees`, `--elevation-degrees`, and `--padding`. Framing uses both projected width and height so horns, broad wings and long tails fit the square portrait. Add the corresponding universal `Contents.json` to the imageset.

Run `python3 scripts/render_roaming_preview.py --species red-panda --output /tmp/pawpace-red-panda-review` to export roaming and special movement clips, stills, and a geometry audit from the current production rig. `--seconds 0` skips videos while retaining stills and audits. `python3 scripts/validate_release.py` requires a scene, skinned conversion report, portrait and valid motion profile for each new species in the Swift catalogue.

References: [glTF Transform simplify](https://gltf-transform.dev/modules/functions/functions/simplify), [meshoptimizer simplification](https://github.com/zeux/meshoptimizer#simplification), and the maintainer's [guidance on skinned meshes](https://github.com/zeux/meshoptimizer/discussions/973).
