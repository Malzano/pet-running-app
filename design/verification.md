## Latest simulator launch · 27 September 2026

The latest source built successfully (`/tmp/pawpace-run-build.log`), installed with existing data preserved and launched on iPhone 18 Pro Max (`8BDC5997-DE68-41E2-A8F4-FE0856A17791`). The actual simulator screenshot `/Users/athikom/Developer/pawpace-preview/latest-simulator.png` was inspected: Buddy shows the existing grown companion and the Buddy, Planner, Club and Workout tabs. This is an app launch capture, not a test fixture. Device Hub's window-control API timed out, so foregrounding and manual navigation were not verified. The other booted iPhone 18 Pro still had an earlier system Open in PawPace prompt.

The project workflow in `AGENTS.md` now records the user's instruction to build, install and run the latest app in the simulator after each completed task. Club's signing and host prerequisites remain absent; the successful simulator launch does not verify the external service.

## Apple account revocation handling · 26 September 2026

Club now asks Apple's credential-state API before sending any queued actions, including on cold launch. Revoked, missing, transferred or unknown credentials conceal cached account data and require sign-in again. A transient check failure preserves the offline queue without uploading it. The app listens for Apple's credential-revoked notification, stops later requests during an in-flight sync, ignores stale responses and dismisses open Club sheets. The existing account-scoped cache is preserved for the same verified account; an already-sent request cannot be recalled. Best-effort service logout invalidates that session when reachable. A Keychain-clear failure does not keep the current in-memory session active, and the next launch checks again before uploading.

**17 selected iOS tests passed, zero failures** at `/tmp/pawpace-club-identity-tests.xcresult` (log `/tmp/pawpace-club-identity-tests.log`): 14 Club behavior tests, one Club presentation test and two summary regressions. Four new cases cover all invalid credential states, unavailable checks, revocation during a suspended upload and failed Keychain clearing. The notification case was then strengthened to post the actual `ASAuthorizationAppleIDProvider.credentialRevokedNotification`; that single overlapping test passed at `/tmp/pawpace-club-revocation-notification.xcresult`. These use a test-only credential-state provider and exercise the production observer/queue. They do not prove Apple's behavior on a signed physical phone. The preceding 236-test full-suite result remains below; overlapping test runs are not added together.

Sources: [Apple credential states](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider/credentialstate) and [revocation notification](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider/credentialrevokednotification). Server-to-server revocation notifications remain a production follow-up; the client checks do not establish immediate revocation of every session on unopened devices.

Debug build and the updated unsigned Release archive passed. The archive `/tmp/PawPaceClubIdentity.xcarchive` passed four-bundle packaging validation; logs are `/tmp/pawpace-club-identity-build.log` and `/tmp/pawpace-club-identity-archive.log`. Source validation (104 Swift files, nine property lists, 15 catalogs) and `git diff --check` passed. The latest Debug app was installed and launched again on the iPhone 18 Pro simulator.

The signing audit still reports zero valid local identities; `DEVELOPMENT_TEAM` and `PAWPACE_CLUB_API_URL` remain blank. A fresh native UI check still reports that the Mac is locked. Owner account/hosting details and an unlocked Mac are required for the remaining real-account acceptance and live walkthrough.

## Club and complete feature regression · 26 September 2026

Planner, expanded Buddy and the Club client/service implementation are built. **Live Club is not configured or verified**: the phone's API setting and Apple team remain blank, and the signing audit found zero local code-signing identities. No deployment, paid service, Apple registration or distribution upload has occurred. The remaining accepted-scope gate is real two-account Club acceptance; see [the checklist](planner-buddy-club.md) and [service setup/acceptance](../server/club/README.md).

- **236 iOS tests passed, zero failures**, including every existing test and the new Planner/Buddy/Club suites. Result: `/tmp/pawpace-planner-buddy-club-regression.xcresult`; log: `/tmp/pawpace-planner-buddy-club-regression.log`. This supersedes the earlier 25-test Club-focused run (`/tmp/pawpace-club-tests.xcresult`); do not add overlapping runs to claim unique coverage.
- **11 Node service tests passed, zero failures** (nine top-level cases including two nested persistence cases). Log: `/tmp/pawpace-club-server-final-tests.log`. They exercise real local HTTP/SQLite, separate injected account identities, invitations, permissions, consent, duplicate/replayed days, event cancellation, encouragement, logout/deletion, restart durability and DST week boundaries. Cryptographic tests use generated RSA/EC keys and an injected Apple transport to check signature/audience/issuer/expiry/nonce, code exchange, identity mismatch, ES256 client secrets and revocation failure. These do not call or prove Apple's production service.
- **Unsigned Release archive succeeded** at `/tmp/PawPacePlannerBuddyClub.xcarchive`; log: `/tmp/pawpace-planner-buddy-club-archive.log`. `validate_release.py --archive` passed all four bundles, including models, assets, versions and each bundle's privacy manifest. This validates packaging, not signing or App Store acceptance.
- Source checks passed **104 Swift files, nine property lists and 15 asset catalogs**. `git diff --check` passed. The phone manifest now declares the optional Club collection explicitly; local-only Watch/extensions retain separate declarations.

Twelve Club native fixture captures are saved in `/Users/athikom/Developer/pawpace-preview/club/`: overview, campsite, group activities, members, creation, joining, scheduling, dark mode, large text, offline queue and two unconfigured-connection views. The first eleven were reviewed, then the final member pluralization and visible connection notice were inspected after the complete run. They use isolated test data, not real clubs or earned user activity. Further final Planner and Buddy fixtures from that run are in `/Users/athikom/Developer/pawpace-preview/final-feature-review/`; Planner today and Buddy memory book were reviewed again. Earlier detailed layout reviews remain recorded below.

The final Debug app installed and launched successfully on iPhone 18 Pro (`F25EB4F1-2FDD-4858-A67A-0B7574C5AE9D`, iOS 27). A native UI attempt returned **Mac locked; automatic unlock unavailable**. The actual simulator capture `/Users/athikom/Developer/pawpace-preview/club/simulator-launch-awaiting-open.png` shows an outstanding system Open in PawPace dialog over onboarding; it is not evidence of successfully navigating to Club. No input bypass was used. The fixture captures provide the visual review; the live walkthrough awaits an unlocked Mac. Unsigned HealthKit entitlement and unpaired-Watch messages are expected and do not establish Health/Watch functionality.

The new in-app privacy text, main-app manifest and release notes distinguish local Buddy/Planner data from optional Club account and activity-day collection. `server/club/README.md` specifies secrets/configuration, TLS/persistence assumptions, live-record deletion, pending backup policy and the exact two-account acceptance matrix. Physical reminders, Health/Watch behavior, photo picking, VoiceOver/touch and real-service account revocation remain acceptance/hardening items rather than completed claims.

## Buddy adventures, garden and memory book · 26 September 2026

The remaining Buddy features are implemented: six branching expedition outcomes, three garden placement nooks with distinct 3D keepsakes and companion reactions, and a discovered-friends memory book with optional local photos. Club and final cross-feature regression remain active in [the scope checklist](planner-buddy-club.md).

Debug build passed at `/tmp/pawpace-keepsakes-build.log`. **70 focused tests passed, zero failures**, in `/tmp/pawpace-keepsakes-tests.xcresult` (log `/tmp/pawpace-keepsakes-tests.log`): ten keepsake tests, one native presentation test, 11 play tests, 16 journey tests, seven roaming tests and 25 lifecycle tests. Checks cover every branch, banked movement, stale/repeated choices, original legacy rewards, earned-only layouts, object uniqueness, saved empty layouts, per-friend memory retention, concealed eggs/unknown identities, all nine species reaching all three nooks, Reduce Motion, and local photo storage.

After fixing the garden button contrast and opaque navigation backgrounds, **11 overlapping tests passed, zero failures**, in `/tmp/pawpace-keepsakes-layout-tests.xcresult`. The photo test now embeds real GPS metadata into a generated input, verifies it exists, and verifies the saved resized image has none; invalid replacement preserves the previous photo. These two runs do not represent 81 unique tests.

Eight final native fixture images are saved in `/Users/athikom/Developer/pawpace-preview/buddy-keepsakes/`: expedition choice, garden, placement inventory, memory book/detail, dark memory book, large-text garden and concealed egg memory book. Initial captures were inspected; corrected expedition and garden captures were reviewed again. Fixtures use test-only progress and are not the user's earned history. The macOS scene-render adapter initially failed on an iOS-only gray color constant; a platform-neutral equivalent fixed it. Final compile passed at `/tmp/pawpace-keepsakes-render-check.log`.

Source validation passed 97 Swift files, eight property lists and 15 asset catalogs, and `git diff --check` passed. The latest app was installed and launched with `simctl` on iPhone 18 Pro (`F25EB4F1-2FDD-4858-A67A-0B7574C5AE9D`, iOS 27). Onboarding was skipped only for that launch via its existing defaults argument. The Codex file preview request returned queued; this is not proof of a foreground screen change.

Physical touch/VoiceOver navigation, system photo picking and signed Health/Watch behavior remain device acceptance checks. Simulator HealthKit entitlement and unpaired-Watch warnings are expected for this unsigned environment and do not prove those integrations. No cloud service or signing setup was performed for Buddy.

## Buddy personality and play · 26 September 2026

The first two Buddy improvements are implemented: per-companion preferences expressed through actual garden behavior, and interactive fetch, hide-and-seek and trick-sequence games. The broader Buddy work (branching stories, placed decorations and the memory book) and Clubs remain active in [the full checklist](planner-buddy-club.md).

The Debug build succeeded. **49 focused tests passed, zero failures**, at `/tmp/pawpace-buddy-play-verified-tests.xcresult` (log `/tmp/pawpace-buddy-play-verified-tests.log`): 11 game/personality tests, one native presentation test, 16 journey tests, seven roaming tests, 13 snapshot tests, and the existing Reduce Motion animation test. These cover game input and state transitions, mismatched companion/egg/incomplete-session rejection, exactly-once saved friendship, unchanged growth/economy, routine retention, legacy decoding and identity-based roaming boundedness for every species. An initial attempt failed to compile because the presentation test tried to set a read-only accessibility environment value; that override was removed. Reduce Motion is tested through the production coordinator API instead.

The native captures in `/Users/athikom/Developer/pawpace-preview/buddy-play/` show personality, fetch, hiding/memorizing, trick learning/practice, completion, the concealed egg state, large text and dark appearance. The initial ten fixtures were inspected. After fixing the dimmed memorization reveal, a further three selected tests passed at `/tmp/pawpace-buddy-play-layout-tests.xcresult`; the corrected reveal and retained-routine capture were inspected. These are fixture captures, not a claim of manual touch/VoiceOver playthrough or real user activity. The macOS production-scene render adapter compiled successfully with the new temperament dependency (`/tmp/pawpace-buddy-render-check.log`).

The final layout-only test passed at `/tmp/pawpace-buddy-play-final-layout-tests.xcresult` after moving learned-routine and signature practice beside their animation preview. The final routine practice screen was inspected, and all 12 final fixture captures were copied to the preview directory. These overlapping runs are not 53 unique tests. Final source validation passed 91 Swift files, eight property lists and 15 asset catalogs; `git diff --check` passed. The current build was installed on the iPhone 18 Pro simulator.

Physical touch feel, VoiceOver navigation and performance remain acceptance checks. No external service, account setup or production signing was performed for this step.

## Planner · 26 September 2026

Planner is implemented as the second tab, with Home relabeled Buddy. Club and the expanded Buddy features remain active work in [the implementation checklist](planner-buddy-club.md).

The initial build succeeded. The final behavior/regression run passed **28 tests, zero failures** in `/tmp/pawpace-planner-verified-tests.xcresult` (log `/tmp/pawpace-planner-verified-tests.log`): 12 planner domain/storage/reminder-queue tests, one presentation test, four Everyday activity tests, nine workout completion tests and two summary dismissal tests. The final layout-only pass also succeeded at `/tmp/pawpace-planner-layout-tests.xcresult`. These overlap; they are not 29 unique cases. Source validation passed 87 Swift files, eight property lists and 15 asset catalogs; `git diff --check` passed.

The six native fixture images in `/Users/athikom/Developer/pawpace-preview/planner/` cover the empty planner, a planned day, editor, rest in dark mode, and large text at the top and bottom. Images were reviewed; the editor's oversized activity row was fixed, large-text content adapts, and the day strip scrolls to the selection without clipping its markers. Test fixtures do not seed or replace the user's planner. The final app was installed and launched on iPhone 18 Pro (iOS 27), with onboarding skipped for that launch only using a UserDefaults argument. Opening `pawpace://planner` reached the Simulator's “Open in PawPace?” confirmation. `planner-simulator.png` records that actual state over Buddy with the new tabs; it is not a screenshot of Planner. Native Device Hub control timed out, so manually tapping Open remains needed for this deep-link check. Planner itself was inspected through the hosted native captures.

Reminder selection uses the real UserNotifications API, but notification authorization/delivery and interaction with system Focus settings still need physical-device acceptance. The automated reminder test proves replacement ordering via an injected scheduler. Health and Watch checks here cover local application logic; signed physical HealthKit/Watch operation remains outstanding. No production signing or distribution was performed.

## Discovery and adventures · 25 September 2026

The implementation adds repeatable persisted eggs with resident preservation, adult expeditions and learned gestures, optional Apple Health workout/step import, configurable gentle weekly adventures, and concealed-by-default image sharing. No undiscovered-species catalogue is exposed. See [feature rules and next recommendations](discovery-adventures.md).

The full Simulator suite passed **187 tests with zero failures** in `/tmp/pawpace-journey-full-tests.xcresult` (`/tmp/pawpace-journey-full-tests.log`). Xcode's subsequent diagnostic collection timed out after 600 seconds; the test action itself completed with **TEST SUCCEEDED**. After hardening re-enabled step windows and delayed snapshot timestamps, **30 focused tests passed** in `/tmp/pawpace-journey-final-verified-tests.xcresult`, covering the 16 journey cases, four activity-service cases, nine completion/retry cases and the native presentation capture test. These are overlapping runs, not 217 unique tests.

The final layout pass passed in `/tmp/pawpace-journey-layout-tests.xcresult`, after improving egg-button contrast, keeping the share action visible on small screens, placing an available egg first, and making scrolling navigation backgrounds opaque. Source validation and `git diff --check` passed. The test builds compile the phone, Watch, widgets and Live Activity targets.

Nine final fixture captures are saved in `/Users/athikom/Developer/pawpace-preview/discovery/`: adult discovery, memories, the resident home, accessibility text, learned tricks, Everyday activity, small-screen sharing, and concealed/revealed 1080-pixel image exports. The initial nine were visually reviewed; the changed adult, family and sharing captures were reviewed again after the layout fixes. The fixtures use test progression and are not real workout evidence.

Native click-through QA was unavailable: the Computer Use inventory reported that the Mac was locked and could not be unlocked automatically. Real Health permission choices and step/workout data, signed physical Watch delivery, and user-selected system share destinations remain device acceptance checks. The injected Health-reader tests prove application control flow and duplicate-credit behavior, not physical HealthKit integration. No new device archive, distribution signing, TestFlight upload or App Store submission was performed in this change.

# Verification record

## Rare and Mythic expansion · 25 September 2026

All six new companions are imported from the owner's Meshy workspace, with actual weighted skeletons, mobile meshes, portraits, normal movement and species-specific special moves. The final runtime catalogue contains nine animals. See [generation and motion provenance](fantasy-companions.md).

The 168-test Simulator run at `/tmp/pawpace-fantasy-final-tests.xcresult` passed 167 cases and exposed one new-model maximum-zoom framing regression (67 silhouette assertions in that single case). After fixing adult framing for the new silhouettes, all **18 camera and special-animation tests passed with zero failures**, including that regression, at `/tmp/pawpace-fantasy-camera-tests.xcresult`. This exercises all nine species through eight orbit angles, jumping and narrow/wide layouts, plus effect cleanup, mouth tracking, Reduce Motion and stable catalogue camera behavior. The remaining full-suite cases passed without changes to their implementation.

The final Debug build succeeded (`/tmp/pawpace-fantasy-final-build.log`). A fresh unsigned device archive also succeeded and passed `scripts/validate_release.py --archive` for all four shipping bundles, including every new model and motion profile:

`/Users/athikom/Developer/PawPace-Releases/PawPace-1.0.0-fantasy-final-20260925.xcarchive`

Archive log: `/tmp/pawpace-fantasy-final-archive.log`. Source validation and `git diff --check` passed. This supersedes the earlier three-species archive as the current local candidate; signing and physical-device release gates remain unchanged.

The final build was installed and launched on both existing iPhone simulators and the paired Apple Watch simulator. Live native checks opened Friends → Mythic → Meet, triggered Dragon fire breath and Unicorn rainbow leap, rotated the preview, and verified visible zoom controls from 150% to 180% with distinct accessibility labels. The preview keeps its meadow and camera across moves. Manual two-finger pinch and physical-device performance remain unverified. Both complete saved phone snapshots matched the pre-expansion baseline exactly after reinstall and preview use, including the New Player egg and its 41 credited Calm seconds.

Final rendered media is in `/Users/athikom/Developer/pawpace-preview/fantasy/`, shown by `fantasy-preview.html`. All nine 45-second roaming audits had **0/46 clipped skinned-mesh samples** each. The six new pets' 95th-percentile planted-paw drift was 0.0076–0.0188 scene units; these normalized coordinates are not a physical measurement. All 30 expansion preview assets returned HTTP 200 with matching file lengths, and the source manifest matches the final animator and assets. Normal and special clips were visually reviewed. A live unicorn simulator recording and screenshot are also saved in that directory.

## Release candidate 1.0.0 · 25 September 2026

The final Simulator suite passed **157 tests with zero failures** using Xcode 27. The complete result is `/tmp/pawpace-1.0-final-tests.xcresult`. It covers the immersive Home camera and controls, egg/baby/adult genetics, workout and Watch identity handling, recovery, protected-storage migration, corruption preservation, journal behavior, completion retries, and canonical/alias reward deduplication.

The unsigned device Release archive completed successfully (exit 0):

`/Users/athikom/Developer/PawPace-Releases/PawPace-1.0.0-20260925.xcarchive`

The archive log is `/tmp/pawpace-1.0-archive.log`. `scripts/validate_release.py --archive` passed for all **four shipped bundles**, checking matching versions, executables, icons, animal models and privacy manifests. This verifies local device compilation and packaging. It is not a distribution-signed archive or an App Store Connect validation result.

The local candidate includes the large garden Home, rotation and zoom controls, onboarding, pet naming, a companion guide, privacy and Health settings, a local workout journal, and interrupted phone-workout recovery. Fitness-bearing snapshots, recovery records and completion records use protected local files excluded from backup. The completion outbox retains known phone/Watch identities until pet rewards, requested journal writes and terminal acknowledgments are durable. Journal deletion cancels pending journal writes without undoing earned pet rewards.

Seven final release fixture captures were reviewed, covering small-screen Home, dark appearance, accessibility text, welcome, settings and journal views. Content was readable with scrolling where expected. Earlier manual Simulator interactions confirmed the immersive Home and button zoom from **100% to 144%**. The Mac was locked during the final manual-interaction pass, so that pass could not continue. Pinch zoom has not been manually exercised; fixture renders and gesture tests do not establish manual pinch behavior or physical-device performance.

The final Debug build was installed and launched on both the PawPace New Player and existing iPhone 18 Pro Max simulators, plus the paired Apple Watch Series 12 simulator. Actual final egg, adult-corgi and Watch captures were visually reviewed and saved in `/Users/athikom/Developer/pawpace-preview/release`. Every pre-existing field of the New Player snapshot matched the earlier persistence baseline after reinstall and migration into the private JSON file, including the egg seed and 41 credited Calm workout seconds. The legacy preferences snapshot was removed only after the migration succeeded. The refreshed preview and all 11 referenced assets returned HTTP 200.

Backup-exclusion metadata was checked in Simulator. iOS Data Protection attributes are unavailable on the host Simulator filesystem, so the file-protection assertion is restricted to physical devices. Locked-device storage, real HealthKit readings/saves, GPS, Watch delivery and battery/thermal behavior remain physical-device acceptance gates.

The release still requires a developer team and signing credentials (**0 valid local code-signing identities**), signed physical iPhone/Apple Watch testing, public privacy/support URLs with publisher contact details, and confirmation of commercial artwork rights. No physical device was connected during this work. No TestFlight upload or App Store submission has been made. See [release preparation](app-store-readiness.md) for the remaining owner and device work.

## Earlier workout and animation verification · 24 September 2026

Verified 24 September 2026 with the installed Xcode 27 SDK.

- The iPhone app, Watch app, companion widgets, and Live Activity build for Simulator.
- All **66 tests pass** on the iPhone 18 Pro Max / iOS 27 simulator. Coverage includes all 80 catalog mappings, swimming configuration, duration rewards, legacy decoding, pause intervals, Watch launch handshakes, existing sync/reward policies, all three textured skeletons, actual head/rear joint motion, frame-to-frame continuity, and Reduce Motion. New roaming tests check ten minutes of bounded traversal per species, steering, prop approaches, world transforms, skinned-mesh framing, and background freeze/resume.
- Native SwiftUI screenshots were rendered at a 393 × 852 point viewport for Home, running, swimming, yoga, Multisport, the searchable catalog, and a yoga summary. The yoga fixture deliberately has no distance or heart-rate data.
- Every workout's SF Symbol resolves on the tested OS.
- The animal preview is a 36-second, 720 × 720, 60 fps render of the actual scenes. Jump framing was checked for all three species. Rendering at 60 fps is not a physical-device performance benchmark.
- Structural validation and `git diff --check` pass.

The roaming full-suite result is `/tmp/pawpace-roaming-final-tests.xcresult`. Review media is in `/Users/athikom/Developer/pawpace-preview`; the `roaming` folder contains three 36-second, 30 fps videos and the source manifests used to generate them.

The roaming render harness checked 180 seconds for each species at both regular and narrow phone aspect ratios, with no clipped pet silhouettes. The narrow field retains 4.7% horizontal margins. The 95th-percentile planted-paw error while turning is at most 0.022 world units across the three species. These are geometric checks of the actual animated scenes, not a device frame-rate benchmark.

## Earlier lifecycle verification · 25 September 2026

At this earlier checkpoint, all **97 tests passed** on the iPhone 18 Pro Max / iOS 27 simulator. That full-suite result is `/tmp/pawpace-lifecycle-verified-tests.xcresult`. This includes egg persistence, legacy save compatibility, stage boundaries, all activity-to-gene mappings, daily caps, duplicate workout handling, frozen adult genes, rarity boundaries, independent egg rendering, baby size and ground contact for all three animals, and rare coat materials. Watch setup-delay and recovery regressions ensure permission and connection time does not contribute to active workout time.

A fresh, separate **PawPace New Player** simulator was used to preserve the existing companion. A 41-second Yoga workout was completed through the app; it contributed exactly 41 growth seconds and 41 Calm gene seconds. The entire saved snapshot remained identical after relaunch. Egg Home, Friends, workout setup and summary were visually checked. Final stage and portrait captures verify the mint, Moonlight and Aurora materials; nonclassic textures retain their markings while using luminance-based coat tinting. The standalone scene preview harness also compiles with the lifecycle types.

The visual preview at `/Users/athikom/Developer/pawpace-preview/index.html` includes the actual egg simulator screen and clearly labeled fixture renders of the growth stages. Rarity distribution is defined by the deterministic inheritance mapping; this validation is not a statistical population simulation.

## Limits of this verification

Simulator builds were unsigned (`CODE_SIGNING_ALLOWED=NO`), so HealthKit's entitlement checks prevent real sensor/Health store testing there. Physical iPhone and Apple Watch testing still needs an appropriate development team and entitlements. In particular, live heart rate, pool lap detection, GPS accuracy, multi-device delivery, session recovery, and actual HealthKit saving were not exercised with real hardware. Backend code also passed direct typechecking against the iOS 17 / watchOS 10 deployment targets.

Multisport stages are manual; this implementation does not claim Apple's automatic sport recognition or every sport-specific coaching feature. The Meshy penguin has no separate tail geometry or tail bone, so its rear motion uses pelvis/spine follow-through. The corgi and bunny articulate their own weighted tail bones.
