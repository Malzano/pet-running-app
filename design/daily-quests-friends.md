# Daily quests and friends — 27 September 2026

User scope: a friendlier buddy-centered active workout, route in the finish recap; Duolingo-like daily/weekly streaks, random decorations or mystery eggs; a friends list and feed showing workouts and results. Keep undiscovered species concealed. Build/install/launch the simulator after completing the work.

## Implementation checklist

- [x] Center the moving/front-facing buddy during workouts; move transient route to summary; verify paused, egg, dark, small and large-text layouts.
- [x] Daily quests: a Buddy check-in or care, five movement minutes, and an optional completed game for hatched companions. Daily streak counts a check-in or movement; weekly streak counts the existing chosen movement-day target. This is the recommended default after an optional preference question received no answer.
- [x] Persist streak evidence and one claim per earned daily/weekly reward. Show current/best streaks, week calendar and completed quests. Missing a day never removes pets, items or movement progress.
- [x] A saved surprise grants an unowned placeable decoration or a mystery egg. Keep egg species hidden; no duplicate decoration rewards or paid rolls. Show odds and let earned gifts wait to be opened.
- [x] Private, accepted friends with requests, remove/block controls, a list and recent workout feed. Reuse the existing Apple account/service, offline command queue and permissions.
- [x] Explicitly share workout results from the finish screen/journal. Display activity, date, duration and optional distance; no route, heart rate, calories, photos or undiscovered pet identities. Allow deleting posts and preset encouragement. No automatic historical uploads.
- [x] Server permission/deduplication/deletion tests, local migration/reward tests, native screenshot review, final build/install/launch.

## External acceptance

The existing Apple team and HTTPS Club host are not configured. Implement and test the actual friends client/service locally; show honest disconnected states in the app. Real two-account acceptance still needs the owner's configured service and Apple identity.


## Delivered behavior

Buddy now has a Daily quests / Open a surprise entry beside the streak. A check-in (including for an unhatched egg), care action or five credited movement minutes qualifies the daily streak. Completed games also record a check-in and the optional play quest. The current streak remains visible while today is still unfinished; it resets after a full missed day. Best streak, earned gifts, pets and garden items remain. Calendar-day arithmetic handles daylight saving and year boundaries. The weekly streak uses the existing 2–5-day movement goal and its locked target for weeks already started. New check-in rewards begin with this feature, without inventing earlier visits.

A daily qualification earns one saved gift; a completed weekly target earns one more. Daily rolls are 85% unowned decoration / 15% mystery egg, weekly rolls 65% / 35%. With all six garden decorations owned, rolls grant eggs. Decoration choice is uniform among unowned items. The claim and its result are written with the unlock in one snapshot mutation. Reopening cannot reroll or grant twice. An egg keeps its own fixed seed, stays concealed, and waits in Adventures until no young companion is active. Care, play and gift opening add no movement credit. Gifts have no payment, expiry or speed advantage.

Club contains Feed, Friends and Clubs. Private codes and accepted requests connect friends. The dashboard counts friends and shared workouts this week; cards show activity, completion date, duration and optional distance, with one cheer per friend/post. Add, accept, dismiss, remove, block and unblock are implemented. Code replacement invalidates old codes. Share a saved workout through the feed’s compose button or Celebrate with friends in the finish recap. The compose screen previews the exact fields, leaves distance off by default, and exposes failures rather than claiming a failed post succeeded. New friends see only posts created after acceptance. The feed displays the latest 100 posts from the last 30 days; server retention is until removal/account deletion, not automatic 30-day erasure. No live workout presence or public feed is sent.

The active workout uses a large front-facing SceneKit buddy, running/walking with the relevant activity or resting when paused. Reduce Motion and mystery eggs retain existing behavior. The finish recap fits recorded GPS points with start/finish markers. Missing GPS shows an honest empty state; indoor summaries omit the map. The route stays transient, is identity-checked against that workout, and never enters the journal, recovery checkpoint, share card or friend payload.

## Verification

- `/tmp/pawpace-engagement-regression.xcresult`: **254 iOS tests passed**, including all existing regression suites, 8 quest tests, 3 friend-client tests, route identity/serialization checks and every actual animal silhouette in the front camera.
- `/tmp/pawpace-engagement-polish.xcresult`: **12 focused tests passed** after layout and failure-message changes. The final native screenshot suite also passed in `/tmp/pawpace-engagement-final-visuals.xcresult` after contrast-only adjustments; those final captures were reviewed.
- `/tmp/pawpace-friends-server-final.log`: **13 service tests passed** against actual local HTTP/SQLite, including acceptance, unknown-user access, pre-friendship history, codes, blocking, exact allowed payload fields, duplicate posts/cheers, post deletion replay and account deletion.
- Native light/dark, accessibility text, small phone, mystery egg, active/paused workout, route/no-route, gifts, friends and post-composer captures: `/Users/athikom/Developer/pawpace-preview/daily-friends/`. Fixture friends, streaks and workout values appear only in tests, never in the production app.
- The first 53-test focused run completed all assertions successfully but Xcode hung while collecting simulator diagnostics. It was stopped; the completed 254-test run above supersedes it. No claim is based on that interrupted result bundle.
- Source validation and whitespace checks pass. The simulator’s existing 2:25 interrupted running workout remains recoverable; no user workout was discarded. The Mac is locked, preventing manual window navigation. Installation, process launch and the recovery screen were verified through simulator developer tools.

## Next improvements, in order

1. Connect the existing Apple team and HTTPS service, then verify friends end to end with two real signed accounts. Exercise accepted requests, optional distance, offline replay, remove/block, and account deletion. This remains an external setup requirement, not a completed real-user acceptance claim.
2. Try the daily loop with a small beta group before tuning gift frequency. The first set reuses six placeable garden items; add more decorative sets before introducing seasons. Evaluate a gentle streak-freeze option and optional reminder time without taking earned progress away.
3. Add friend-chosen display names/avatars and optional notification preferences after identity/service acceptance. Consider richer friend profiles and feed pagination if the 100-post window becomes restrictive. Keep workout sharing explicit and avoid revealing undiscovered species.
4. On physical phones, review VoiceOver, touch comfort, battery use during an animated workout, GPS quality and resumed route gaps. A recovered workout still cannot reconstruct GPS points from a previous process because routes are intentionally not persisted.

Final install/launch verified just after midnight on 28 September: iPhone 18 Pro Max, process 34378. `latest-simulator.png` shows the retained 2:25 workout recovery prompt. The preview tabs contain native test captures with explicitly documented sample data.
