# Roaming scene preview

Run from a macOS machine with Xcode command-line tools and Metal:

```sh
python3 scripts/render_roaming_preview.py --output /tmp/pawpace-roaming-preview
```

The runner extracts the **current checkout's** `CompanionRig`, `CompanionField`,
`CompanionRoaming`, `PetSpecies`, and `PetMotion`. It compiles those sources with a
small AppKit adapter, then uses SceneKit's Metal renderer. No cached animator or
hand-recreated animal scene is used. `source-manifest.json` records input SHA-256
hashes and the command's options; `CurrentCompanion.swift` and
`PreviewHarness.swift` preserve the exact adapted source used for that run.
The export uses an opaque pale habitat background (`#EDF1E8`) so transparent
scene corners display correctly in video players and image previews.

Defaults produce one 36-second H.264 video per animal, action PNGs, and a
180-second audit. The deterministic scenario wanders for three seconds, approaches
the ball, approaches the bowl at second 14, greets the user at second 27, then
resumes exploring. Each interaction uses the actual controller's arrival and turn
logic. The renderer receives the same exponential animation blends as the app.

Useful options:

```sh
# Compile without rendering.
python3 scripts/render_roaming_preview.py --compile-only

# Render one pet at the phone habitat's approximate aspect ratio.
python3 scripts/render_roaming_preview.py --species bunny --width 720 --height 680

# Audit ten simulated minutes without producing a video (action PNGs remain).
python3 scripts/render_roaming_preview.py --seconds 0 --audit-seconds 600
```

`audit.json` reports:

- **Camera bounds:** every vertex of each skinned animal mesh, projected through
  the configured camera at one-second intervals. Values are normalized viewport
  coordinates, with top-left `(0, 0)` and bottom-right `(1, 1)`.
- **Ground bounds:** maximum squared elliptical radius reached by the controller.
  A result no greater than one remains in the central walking area.
- **Foot contact:** horizontal distance between each planted foot bone and the
  renderer's stored world-space anchor, observed at 60 Hz or the video frame rate
  if higher. Straight and turning contacts are reported separately. This measures
  the IK endpoint; visible skinned paw contact may differ slightly from its pivot.
- **Observed actions:** confirms the scenario actually reached play/feed/jump.

Offline rendering checks geometry, framing, and deterministic animation. Native
iOS frame pacing, accessibility, and touch hit testing need the app/simulator.
Output goes to `/tmp` by default and is not added to the repository.
