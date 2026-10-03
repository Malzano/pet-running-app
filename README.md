# PawPace

PawPace is a native SwiftUI workout companion. New players receive a mystery egg that hatches into one of nine companions and grows through baby and adult stages. Home is a full-screen meadow with rotation and pinch zoom; Workout records your chosen activity; your companion’s progress sheet shows growth, genes, and habitat choices. Species and special moves remain a surprise until hatching, with no catalogue or species previews. Completed workouts earn XP and friendship, and daily progress counts active minutes. The project includes Home Screen widgets, an Apple Watch app, and a workout Live Activity.

## Adventures and everyday movement

The Planner tab lets you schedule activities or rest days, edit their date/time and duration, and optionally request local reminders. Completed workouts match the same activity and local start day when they meet the planned minutes; one workout can complete one plan. Rescheduling or removing a plan never changes earned companion progress. The Today card can start your planned activity and relates it to your current companion's journey. Plans are stored privately on the phone. See [Planner, Buddy and Club work](design/planner-buddy-club.md) for the implementation checklist and follow-up improvements.

Open the map on Home for your weekly adventure, grown-up expeditions, and the friends you have already welcomed. There is no undiscovered-species catalogue. Every 180 credited adult minutes earns another persisted mystery egg. Welcome it after your current youngster grows up; the previous companion keeps a place at home. Each companion retains its name, lifecycle, care stats, accessory and adult milestones. Level, XP, currency, daily credit and habitat belong to the family.

Expeditions take 60, 120 or 180 adult progress minutes and unlock a decoration and a dated memory. Happy hop unlocks after 60 adult minutes; a distinct victory dance and Trusted friend milestone unlock after 180. Weekly adventures let players choose 2–5 activity days, each requiring five progress minutes, and award permanent keepsakes. Rest never removes progress. Weeks start Monday; a target change applies next week once progress has begun.

New expeditions branch halfway through: choose one of two paths, each with a distinct story and keepsake. Movement keeps counting while you decide, and old expeditions retain their original rewards. Adventures → Arrange your garden places earned objects in three nooks; companions approach them for a hop or a quiet pause. Adventures → Memory book keeps dated hatches, first outings, learned tricks and expedition stories for discovered friends. Optional photos stay on the phone, resized and stripped of original metadata, outside backups; they never change your photo library. Historical milestones without saved dates are not invented.

Settings → Everyday activity optionally imports new shared Apple Health workouts and steps after opt-in. It refreshes on app foreground or Sync now, checking up to seven recent days for delayed uploads. One hundred steps earn one game progress minute. Daily credit uses the greater of workout minutes or step progress, capped at 60 minutes across the whole family; this prevents adding the same movement twice. Step progress contributes to Endurance; only newly awarded minutes shape genes. Imported workout UUIDs, app metadata and persisted time unions prevent repeated reward credit. Imported workouts are never saved back to Health. Turning the feature off preserves progress.

Workout summaries and Adventures offer native image sharing, with a preview and a concealed companion by default. Players can reveal only their own hatched companion and choose whether to include activity and minutes. Cards omit routes and Health measurements. See [the implementation and verification plan](design/discovery-adventures.md).

After hatching, Buddy → Play opens your companion's personality and three interactive games: aim a throw in Little fetch, remember hiding places in Hide & seek, and repeat a three-step Trick trail. A completed three-round game builds friendship once, preserves the learned routine, and helps shape favorite games and temperament. Curious, playful and calm companions explore at different rhythms; identity-derived seeds let the same species have different habits. These preferences remain with each companion when you visit someone else or welcome an egg. Games never add movement credit, XP, coins, growth or rarity chances. There are no game deadlines or lost lives, and eggs reveal no personality or species clues.

## Private Club

Club adds private invitations, cooperative activity-day goals, four campsite stages, host-scheduled activities, deduplicated Planner copies, and four preset encouragements. Each member has a generated alias. Activity sharing starts off, and an opted-in current day needs five credited movement minutes; it sends only a timestamped achievement. No pet names, species, special moves, routes, photos or workout measurements are sent. The phone keeps an account-scoped offline queue with stable command IDs and visible failed actions.

The real client and Node/SQLite service are implemented and tested locally. **Live Club is not configured in this checkout**: there is no API URL or Apple signing team. The app shows an honest connection state rather than fabricated members. See [server setup, data retention and two-account acceptance](server/club/README.md). Buddy and Planner remain available without an account.

## Requirements

- macOS with Xcode 16 or newer for local builds; use the currently required SDK for App Store uploads (the development Mac has Xcode 27)
- iOS 17 or newer
- A physical iPhone for complete HealthKit, route, widget, and Live Activity testing
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Generate and open the Xcode project

```sh
brew install xcodegen
cd /path/to/pet-running-app
xcodegen generate
open PawPace.xcodeproj
```

In Xcode, select your Apple Developer team for `PawPace`, `PawPaceWatch`, `PawPaceWidgets`, and `PawPaceLiveActivity`. Replace the sample bundle identifiers and App Group if those identifiers are unavailable in your account, and keep `WKCompanionAppBundleIdentifier` in the Watch Info.plist aligned with the phone ID. The value in `PawPaceShared.suiteName` must match the phone and widget entitlements.

## Targets

- `PawPace`: SwiftUI app with Buddy, Planner, Club and Workout experiences.
- `PawPaceWatch`: activity selection and HealthKit workout sessions on Apple Watch.
- `PawPaceWidgets` and `PawPaceLiveActivity`: companion widgets and workout controls.
- `PawPaceTests`: progression, migration, workout catalog, sync policy, and real animal rig tests.

## Workouts

The searchable catalog supports all 80 current public HealthKit activities, including strength, yoga, swimming, cycling, wheelchair workouts, sports, and Multisport. Indoor/outdoor and pool/open-water settings configure the actual HealthKit session. A pool swim includes a lap length. Multisport uses manual Swim → Cycle → Run stages, with a Next stage control on either device.

The workout screen always shows time and earned XP. Heart rate and active calories appear when sensor data is available; distance, pace per kilometre, swim pace per 100 metres, and speed are shown only for relevant activities. Outdoor route tracking is restricted to suitable activities. Apple Watch provides live workout measurements; phone-only recording can use location and available HealthKit samples. Missing sensor values remain empty.

Workout type coverage does not reproduce all of Apple's coaching, automatic multisport recognition, sport-specific intervals, or specialized hardware features. Swimming and Watch measurements need physical-device validation. See [workout coverage and sources](design/workout-coverage.md).

## Animal assets and animation

### Eggs, growth, and genetics

New saves receive one random, persisted egg. It hatches after 30 active workout minutes, then needs another 180 minutes to reach adulthood. Up to 60 progress minutes per day count toward growth, genetics and adult adventures; saved workout IDs prevent duplicate credit. Feeding, play, XP, pace, calories, and heart rate do not accelerate growth. Rest days retain all progress.

The animal species and coat inheritance roll are fixed when the egg arrives, and revealed at hatching. New eggs have an 84% Common, 15% Rare, and 1% Mythic species chance, split evenly between the three companions in each tier. This does not reroll existing eggs. Workout minutes contribute to Endurance (mint), Power (peach), Calm (lavender), or Explorer (sky) genes. The strongest trait determines ordinary coat color, which can change during babyhood and settles at adulthood. Independently, every species has a 5% Moonlight and 1% Aurora coat chance; harder workouts do not change either set of odds. See [lifecycle rules](design/pet-lifecycle.md) for mappings and persistence behavior.

| Species tier | Companions | Signature movements |
| --- | --- | --- |
| Common | Corgi, Bunny, Penguin | Their established playful gestures |
| Rare | Red panda, Fox, Axolotl | Leaf tumble, Firefly pounce, Bubble dance |
| Mythic | Dragon, Unicorn, Phoenix | Fire breath, Rainbow leap, Ember flourish |

After hatching, Play includes a Rare or Mythic friend's signature move, with a dedicated practice screen that keeps the animation visible. Tapping the garden's toy also retains the existing signature interaction. Players discover their companion through hatching and play; the in-app guide keeps species identities, counts, and special moves a mystery. Species rarity is distinct from a rare coat, and every tier grows at the same pace.

Existing saves retain their companion, equipment, currency, and progress as a grown-up pet. Lifecycle saves cannot freely switch species. New eggs use a procedural 3D shell and nest, babies use smaller grounded versions of the animal rigs, and genetic colors carry through the phone, Watch, widgets, and Live Activity.

The iPhone app renders textured, skinned Meshy models with SceneKit. Custom joint animation drives foot placement, head/neck turns, body balance, ears, tails, wings and flippers across idle, walking, running, jumping, playing, feeding, celebration and signature moves. Each new export has a reviewed `.motion.json` mapping its actual skeleton. The corgi and bunny use weighted tail joints; the penguin export has no separate tail joint and uses pelvis/spine follow-through for its rear body. Walking has distinct species-specific gaits. Play and feeding react to objects in the scene. Signature effects use bounded, reusable geometry and share the gesture's clock. Animation targets 60 frames per second, pauses when inactive, and respects Reduce Motion.

On Home, pets explore an actual 3D meadow. They accelerate and turn gradually, take shorter steps around corners, pause to look around, and face the ball or bowl before interacting. Their gait follows ground travel; planted paws remain anchored while the body moves above them. Tap the grass to guide a pet, tap the pet for a greeting, or use Rest / Explore. Drag horizontally to rotate the garden through 360°, pinch or use the zoom buttons to move between 0.75× and 2.25×, and use Reset to restore the starting view. The camera follows the pet while keeping the world fixed. VoiceOver offers rotation, zoom and reset actions; the large-text layout scrolls so controls remain accessible. Dark mode dims the scene for readable controls. The pastel garden includes a fruit tree, mushrooms, flower and clover patches, a fence, and a picnic corner around its open walking area. The field camera adapts to narrow screens. Workout and summary portraits retain their close framing.

Original downloads and provenance are in `design/meshy-source`. Runtime `.scn` files in `PawPace/Resources/Animals` contain the geometry, textures, and skeleton; widgets and Watch use matching lightweight portraits from `SharedUI/AnimalPortraits.xcassets`.

To regenerate a runtime model and portrait on macOS:

```sh
swift scripts/convert_meshy_glb.swift design/meshy-source/corgi.glb PawPace/Resources/Animals/corgi.scn
swift scripts/render_pet_portrait.swift PawPace/Resources/Animals/corgi.scn SharedUI/AnimalPortraits.xcassets/pet-corgi.imageset/portrait.png
xcodegen generate
```

Use the source corresponding to the species. Red panda and Fox use derived 30,000-triangle GLBs under `design/meshy-source/optimized`; the originals remain editable. The [mobile asset pipeline](scripts/OPTIMIZE_MESHY.md) documents the pinned development tools, exact skin-attribute checks, portrait framing and regeneration commands. Conversion preserves all skin influences and scales textures for mobile use. No network connection, Meshy API key, or runtime third-party library is required by the app. Legacy saves preserve their recorded species; saves predating species selection fall back to a corgi.

To render current roaming behavior and audit camera/foot placement on macOS:

```sh
python3 scripts/render_roaming_preview.py --output /tmp/pawpace-roaming-review
```

The preview script extracts the current production rig, field, profiles, effects and movement controller; its source manifest records their hashes. It supports all nine pets, checks a longer traversal and exports separate six-second signature clips for Rare and Mythic companions. Use `--species dragon` to inspect one species, or `--seconds 0` for stills and audits without videos.

## Journal, recovery, and settings

First launch explains the egg and workout loop. Settings includes naming, a companion guide, Health permissions, privacy information, and a local workout journal. Journal deletion requires confirmation and leaves companion progress and Apple Health records in place.

Phone-only interrupted workouts keep a protected checkpoint. The user reviews the last recorded time, which restores paused; time while the app was closed is excluded. Pending Watch Health records and recovery metadata migrate to protected, backup-excluded files. A durable completion queue commits pet rewards and phone/Watch aliases atomically, then finishes journal and synchronization writes. Storage errors remain visible and retryable without granting rewards twice.

Public [privacy](release/website/privacy.html) and [support](release/website/support.html) pages are prepared as offline publication drafts. The publisher must supply real contact details and owned HTTPS URLs before they are published or entered in App Store Connect.

## Verify

See [verification results](design/verification.md) for the latest test and archive evidence, reviewed screen captures, and remaining physical-device checks. Source validation also requires a textured rig, portrait and valid authored motion mapping for every new species.

```sh
python3 scripts/validate_sources.py
python3 scripts/validate_release.py
xcodebuild -project PawPace.xcodeproj -scheme PawPace -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' CODE_SIGNING_ALLOWED=NO test
```

See [release preparation](design/app-store-readiness.md) for archive checks, privacy manifests, signing, physical-device acceptance tests, and the remaining publisher requirements. [Store copy](design/app-store-metadata.md) is prepared as a reviewable draft. No App Store upload or submission has been made.
