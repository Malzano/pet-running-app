# Meshy companion sources

These original GLB files were downloaded from the user's signed-in Meshy workspace for PawPace. Keep them as the editable source models. The confirmed expansion adds Red panda, Fox and Axolotl as Rare species, and Dragon, Unicorn and Phoenix as Mythic species. The six expansion models were generated and Smart Rigged in that workspace; the retained axolotl reference is `fantasy-references/axolotl.png`. The iPhone app loads the converted SceneKit resources in `PawPace/Resources/Animals`; Watch, widgets, and Live Activities use transparent portraits in `SharedUI/AnimalPortraits.xcassets`.

| Animal | Source triangles | Runtime vertices | Runtime triangles | Skin joints | Preserved influences per vertex |
| --- | ---: | ---: | ---: | ---: | ---: |
| Corgi | 15,955 | 11,499 | 15,955 | 37 | 20 |
| Bunny | 31,007 | 22,438 | 31,007 | 42 | 12 |
| Penguin | 20,609 | 16,050 | 20,609 | 23 | 4 |
| Red panda | 216,760 | 18,835 | 30,000 | 44 | 12 |
| Fox | 256,422 | 19,410 | 30,000 | 42 | 8 |
| Axolotl | 31,169 | 29,014 | 31,169 | 34 | 8 |
| Dragon | 31,217 | 28,563 | 31,217 | 86 | 12 |
| Unicorn | 31,108 | 29,108 | 31,108 | 41 | 12 |
| Phoenix | 30,998 | 30,885 | 30,998 | 50 | 12 |

Counts come from the actual GLB index buffers and converted `.rig.json` reports, rather than rounded Meshy UI counts. The four latter expansion models were remeshed to approximately 30,000 triangles in Meshy before Smart Rigging. Red panda and Fox retain their original high-poly sources and use local optimized derivatives. All nine converter reports record zero dropped skin weight.

`optimized/*.optimization.json` records the original and derived GLB hashes and verifies unchanged skeletons, original node transforms, inverse bind matrices, textures, animation channels and every retained vertex attribute. Red panda and Fox achieved 30,000 triangles at measured relative geometry errors of approximately 0.00244 and 0.00207 respectively. These are offline asset checks; device frame pacing still requires runtime testing.

The app authors its own joint motion. Imported animations are deliberately not included in converted scenes: the penguin source has humanoid-style clips. The renderer restores each bind pose before applying a blended species-specific gait, foot-target inverse kinematics, jumps, and playful gestures. Each new animal has an authored `.motion.json` profile mapping its real bones, including dragon and phoenix wings. The signature moves are Leaf tumble, Firefly pounce, Bubble dance, Fire breath, Rainbow leap, and Ember flourish. They use procedural motion and effects in the app rather than downloaded animation clips.

## Rebuild resources

Conversion and portrait rendering use the macOS SDK and require Xcode. They need no Blender installation or third-party runtime library. The optional high-poly reduction step uses pinned glTF Transform and meshoptimizer development tools; see [mobile asset pipeline](../../scripts/OPTIMIZE_MESHY.md).

```sh
for pet in corgi bunny penguin red-panda fox axolotl dragon unicorn phoenix; do
  source="design/meshy-source/$pet.glb"
  if [ -f "design/meshy-source/optimized/$pet.glb" ]; then
    source="design/meshy-source/optimized/$pet.glb"
  fi
  swift scripts/convert_meshy_glb.swift \
    "$source" \
    "PawPace/Resources/Animals/$pet.scn"
  swift scripts/render_pet_portrait.swift \
    "PawPace/Resources/Animals/$pet.scn" \
    "SharedUI/AnimalPortraits.xcassets/pet-$pet.imageset/portrait.png"
done
```

The converter preserves the entire skeleton, inverse bind transforms, and all skin influences. It reduces embedded textures to 1024px albedo, 512px normal, and 256px roughness/metallic maps. Each `.rig.json` lists original names, local transforms, world positions, mesh counts, and final bounds for rig inspection.

Skinned geometry is placed directly under the scene root because glTF evaluates skin transforms in scene space. This also ensures that the penguin's 0.01-scaled armature and counter-scaled inverse binds produce a matching visible size and scene bounding box. Final heights are 1.7 model units for corgi and bunny, and 0.35 for penguin; the renderer normalizes these at runtime.

The original three conversions were verified by reopening the scenes, rendering through Metal, and checking every joint's world transform multiplied by its inverse bind against the identity matrix (maximum error below 0.000001). All six added scenes were reopened by the converter and their transparent 512×512 portraits rendered and reviewed. Full body framing includes horns, gills, wings and tails. Ordinary and signature motion use the current production-source preview harness; its manifests record the exact implementation being reviewed.

Workspace provenance is recorded here; it does not substitute for confirming the Meshy account's commercial distribution rights before an App Store release.
