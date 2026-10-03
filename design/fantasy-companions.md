# Rare and Mythic companions

Created in the owner's signed-in Meshy workspace on 25 September 2026. All new generation jobs used the **Private** setting. Original rigged GLBs are retained in `design/meshy-source`; optimized SceneKit resources and bone reports live in `PawPace/Resources/Animals`.

| Tier | Species | Signature move |
| --- | --- | --- |
| Rare | Red panda | Leaf tumble with a spiral of leaves |
| Rare | Fox | Firefly pounce with a trail of glowing fireflies |
| Rare | Axolotl | Bubble dance with floating translucent bubbles |
| Mythic | Dragon | Fire breath from its moving muzzle |
| Mythic | Unicorn | Rainbow leap with a six-color arc |
| Mythic | Phoenix | Ember flourish with wings and warm sparks |

Every companion uses the app's normal idle, walk, run, jump, play and feed states. Signature moves are four-second procedural animations driven by real skeleton bones and lightweight SceneKit effects. They are authored in the app; Meshy's Smart Rig supplies the weighted skeleton, not the special animation. Reduce Motion stops the animated pose and effects, and rendering pauses when the app becomes inactive.

The Home **Play** action triggers a hatched Rare or Mythic companion's signature move. There is no player-facing species catalogue or preview screen. Species identities and signature moves are discovered through hatching and play; the companion guide does not reveal the roster.

New eggs use 84% Common, 15% Rare and 1% Mythic species odds, split evenly among the three species in each tier. This is independent of the existing 5% Moonlight / 1% Aurora coat roll. Existing saved eggs and companions retain their original species, inheritance and workout progress. See [lifecycle rules](pet-lifecycle.md).

## Source generation

Red panda, fox, dragon, unicorn and phoenix use Meshy 6 Text to 3D geometry with Meshy 7 textures, followed by Smart Rig. Prompts describe one full-body, friendly, rounded mobile-game animal with a neutral pose, separated limbs and tail, matte pastel materials, and no scenery, pedestal, text or clothing. The key appearance directions were:

- **Red panda:** cinnamon-orange fur, cream cheeks/muzzle, chocolate paws, rounded ears and a long striped tail.
- **Fox:** apricot-orange fur, cream muzzle/chest/tail tip, dark paws, triangular ears and a fluffy tail.
- **Dragon:** mint-teal scales, cream belly, cream/gold horns and dorsal details, two peach-membrane wings and a tapered tail.
- **Unicorn:** ivory coat, one golden spiral horn, lavender/blush mane and tail, lilac hooves and small horse ears.
- **Phoenix:** coral/apricot feathers, cream-gold belly, golden beak, crest feathers and two feathered wings.

The initial text-only axolotl was rejected because the shape looked like a horned reptile. The final model uses Meshy 7.1 Image to 3D from `fantasy-references/axolotl.png`, then a roughly 30,000-triangle Meshy remesh and Smart Rig. The reference was created with the built-in image-generation tool using this prompt:

> Use case: stylized-concept. Asset type: single character reference for Meshy image-to-3D. Create a single adorable PINK AXOLOTL salamander toy-like mobile game pet, full body, low three-quarter front camera, on plain white background. Clearly axolotl, NOT dragon, not lizard. Broad smooth rounded oval head with two round glossy black eyes, gentle small smile. THREE soft rounded fern-shaped CORAL PINK EXTERNAL GILLS extending from EACH SIDE of head (six total), no horns, no ears. Pale blush pink smooth skin, cream belly. Long low rounded salamander body, FOUR short stumpy legs resting on ground, each separated clearly with tiny rounded toes. Thick long soft tapering tail behind with a rounded translucent pink fin, visible curving slightly to side away from body. Neutral standing pose on all four legs. Cute oversized head, cheerful, elegant soft pastel stylized 3D render, matte clay-like finish, simple clean silhouette, matching cozy pet game. Entire character centered with space on all sides and every foot visible. No spikes, no claws, no horns, no wings, no scales, no props, no base, no bubbles, no water, no words, no text, no watermark. Lighting is soft even studio lighting with minimal shadow. Single view only, no collage.

Model outcomes were selected for their actual shape. Red panda and dragon are upright; fox, unicorn and axolotl use four-foot gaits; phoenix uses two feet and wings. Each `.motion.json` maps the actual source skeleton. No new species borrows a different animal's bone indices.

## Runtime assets

Original sources remain untouched. High-poly sources are simplified to a mobile-size mesh using `scripts/optimize_meshy_glb.mjs`; the script preserves the skeleton, inverse bind matrices and complete skin-weight sets for surviving vertices, and writes a verification report. Conversion downsizes embedded textures and emits a `.rig.json`. Portraits for Watch, widgets and catalogue rows are rendered from the same models.

Asset rights and final physical-device performance remain part of the existing [release checklist](app-store-readiness.md). A private-generation setting is recorded provenance, not a substitute for the publisher's license review.
