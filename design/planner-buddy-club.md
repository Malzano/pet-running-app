# Planner, Buddy and Club implementation

Requested 26 September 2026. Implement the accepted proposal point by point; this checklist is the scope, not a claim of completion. Keep undiscovered species, names, signature moves and reward previews concealed.

## 1. Planner

- [x] Dedicated Planner tab; Home is now labeled Buddy. Club joins the navigation in step 3.
- [x] Week view distinguishes planned activities, completed workouts and rest days, including multiple states on one day.
- [x] Create and edit activity, date/time, duration and optional local reminders.
- [x] Reschedule without affecting earned companion progress.
- [x] Match recorded workouts to plans once, including the shared journal used by imported/Watch completions.
- [x] Today card starts the chosen workout and explains its companion connection.
- [x] Durable local storage, preserved corrupt files, save-failure handling and reviewed large-text layouts.

Planner matches the same activity on the workout's local start day, when one workout meets the planned duration (5–240 minutes). The closest scheduled time wins. IDs and overlapping active intervals prevent duplicate source copies from completing another plan. Removing a plan or journal keeps those ownership records. Completed plans cannot be rescheduled, and plans themselves do not award movement credit. Rest days retain all companion progress. The calendar uses local dates and Monday weeks without assuming every day is 24 hours.

Reminders request authorization only when saving a future reminder. They contain generic lock-screen text, are cancelled/replaced after edits or completion, and open Planner. A serialized replacement queue prevents an old async request from restoring removed reminders. The next 50 are scheduled; the UI explains the limit and schedules later reminders on the next launch. Notification denial does not discard the plan. Actual notification delivery and signed Watch/Health sources still need device acceptance; test doubles do not prove those external services.

Verification: 12 Planner behavior tests and one six-screen rendering test; 28 selected tests passed with workout-completion, summary-dismissal and Health-import regression suites. See `verification.md` for results and screenshots.

Further Planner improvements after the accepted scope: recurring schedules/copy-week, optional calendar export, and choosing which workout to associate when several equally plausible sessions exist. Validate the simple automatic matching rule in a small beta before adding training advice.

## 2. Buddy

- [x] Personal preferences and personality expressed in behavior; companions of the same species can differ.
- [x] Interactive fetch, hide-and-seek and short trick sequences beyond existing Play animations.
- [x] Branching expedition choices with distinct memories and decorations.
- [x] Place earned decorations in the habitat and let companions interact with them.
- [x] Memory book includes hatch, first outing, learned tricks, expeditions and optional photos; only discovered companions appear.
- [x] Persist progress per companion, retain existing saves, honor Reduce Motion and verify interaction/state transitions (automated checks; physical acceptance remains below).

**Buddy personality and games delivered 26 September.** Buddy → Play and Adventures → Play together open the same game hub. Companions start with stable identity-based preferences and adapt through care, exploration and games. Calm companions walk more slowly and pause longer; playful companions move a little faster and pause less; curious companions look around more. The Home controller also uses each companion's seed, rather than one movement seed per species. Ordinary care influences personality at most once per minute; game wins adapt it without changing growth or rarity.

Little fetch accepts aimed taps inside a target and visibly moves the ball and portrait to fetch it. An accessible target button follows the same rules. Hide & seek has four labeled hiding places, a player-controlled memorization stage, retries and a look-again option. Trick trail teaches three gestures in sequence, resets only the current sequence after a mistake, and remembers the last completed routine for practice. Three rounds finish a game. Each completed session persists exactly once and adds three friendship points (capped at 100), no movement, XP, coins, or inheritance changes. Leaving an unfinished game starts fresh next time; no earned progress is removed.

The shared snapshot stores the active companion's `BuddyBond`; archived residents retain their own copy. Old saves default to an empty game history without fictional memories. New eggs start fresh. Completion checks both the original companion ID and finished state before awarding anything. Save failures remain retryable. The game hub, special moves and personality are concealed for eggs. Reduce Motion leaves the 3D companion still and skips the fetch travel animation; backgrounding resets transient fetch motion without awarding another round.

49 focused tests passed for the game rules, old-save decoding, per-resident retention, reward idempotency, actual roaming bounds and existing Reduce Motion behavior. Native light/dark/large-text fixtures were reviewed; a faded hide-and-seek reveal was corrected. Completed routines and special moves have dedicated practice screens so their animations stay visible beside their controls.

Further play improvements after the accepted scope: test aiming comfort and VoiceOver navigation on physical phones, tune how quickly preferences change from small beta feedback, and consider optional sound/haptics and more routine variations. Do not make games a way to grind rare species.

**Buddy adventures, garden and memory book delivered 26 September.** New expeditions offer two choices at their halfway point. Each of the six paths has its own story and earned object. Credited movement continues to accumulate up to the expedition target while a choice is pending; there is no time limit. A choice cannot be changed after saving, stale choices cannot apply to a different expedition, and completion awards its memory and unlock once. Existing in-progress expeditions retain their original completion behavior and rewards. Garden decoration previews only include earned items.

The shared family garden has three named nooks. Place, move, replace or put away any earned keepsake; one item occupies one nook and no item appears twice. The six objects have distinct SceneKit geometry. Tap a placed object, use its VoiceOver action, or choose Visit in the arrangement screen: a hatched companion approaches it and hops for flags/lanterns or pauses to admire the quieter objects. Reduce Motion keeps the companion still; the arrangement screen also provides a written response. Visiting a keepsake awards no movement or growth. Layouts persist in the shared snapshot and an old equipped earned decoration remains visible until the player arranges the garden.

The memory book combines saved hatch/maturity dates, first recorded post-hatch movement, first learned routine, dated adult trick milestones and completed expeditions. It follows each discovered companion through visits and new eggs. Missing historical dates remain absent; earlier expeditions without an identity stay in the all-friends view. Optional photos use the system photo picker, downsample to 1,200 pixels, strip original metadata and save separately on the phone in protected, backup-excluded storage. Removing a memory photo leaves the source photo library alone. Photos do not sync to Watch or Club. A new photo cannot overwrite an unreadable existing save silently.

70 focused tests passed for branches, legacy migration, reward identity, photos, every species approaching each nook, memory retention, lifecycle and play regressions. The final 11-test overlap passed after visual fixes and an explicit GPS-metadata stripping test. Eight native fixture captures were reviewed, including dark mode, large text and an unhatched egg; contrast and navigation-bar overlap were fixed. Build, render-adapter compilation and source checks passed. The latest app was installed and launched in the iPhone 18 Pro simulator. See `verification.md` for exact evidence and preview paths.

Further Buddy improvements in priority order:
1. Physical-device acceptance: play through all games with touch and VoiceOver, check Reduce Motion in Settings, select/replace/remove an actual library photo, and verify garden camera/scroll behavior on smaller phones. Automated rules and hosted renders do not prove those system interactions.
2. Tune the three-nook placement and keepsake scale with real users before adding free dragging or more objects; keep walking paths clear. Quiet-object visits currently use the existing idle pose rather than a new sniff/sit animation.
3. Add more expedition chapters and choices after testing whether players understand the halfway decision. Keep rewards hidden until earned and avoid paid or speed-based rarity advantages.
4. Consider captions, photo export and opt-in photo backup later. The current local-only photo behavior deliberately means those images are lost when the app's local data is removed.

## 3. Club

**Implemented locally; real account/service acceptance is still outstanding.** The seven implementation items below have automated evidence, not a claim of a deployed service.

- [x] Dedicated Club tab with create/join and private invitations.
- [x] Shared-state client and service with accounts; production shows no pretend members or fabricated activity.
- [x] Cooperative activity-day goals and an evolving shared campsite.
- [x] Schedule group activities and add them to Planner without duplicates.
- [x] Send quick encouragement to members.
- [x] Conceal unknown species and prevent disclosure through names/special moves.
- [x] Handle offline state, membership permissions, retries and duplicate contributions.
- [ ] Verify actual multi-user flows against the provisioned service and real Apple accounts.

Club has a native Sign in with Apple flow and a separate Node/SQLite service. Private seven-day invitation links are revocable by replacement. Clubs have up to 30 members, a host, a fixed time zone and a 2–70 activity-day weekly target. A member shares nothing automatically on joining. Explicit opt-in allows one day per member and club date after five credited movement minutes; only a dated achievement is sent. There is no historical backfill. Duplicate copies, retries and server restarts preserve one contribution. Local steps, workout records, heart rate, routes, pet names, species, special moves and photos are never sent. A generated plant alias identifies each member. Unknown companion terms in custom club names are concealed on display.

The campsite progresses at 5, 20 and 50 lifetime shared days. The host can schedule ten common activities and cancel an event; members can add a plan once through its stable event ID. The personal copy remains independently editable; a later group cancellation is explained in Club and does not silently remove a personal plan. Four fixed encouragements avoid free-form chat. The host can remove members or close the club, and members can leave. Removal revokes the current invitation. Members can erase shared days or delete their account from inside the app; account deletion revokes Apple access before removing server data and hosted clubs.

The account-scoped offline queue persists an action before sending it. Before syncing, the phone checks Apple credential state; revoked or missing credentials stop uploads and conceal the account until sign-in. Apple revocation notifications also stop subsequent requests during an in-flight sync. Unavailable state checks preserve queued work for retry without uploading it. Commands retain their ID across retries; permanent failures stay visible for review. Turning activity sharing off pauses new local uploads immediately and removes queued day contributions. Corrupt files are preserved. Tokens use device-only Keychain storage; Club caches and pending actions use protected, backup-excluded storage. HTTPS is mandatory and credential redirects are rejected. The server checks membership and host permissions rather than relying on hidden buttons. Service credentials, hosting and the Apple team are still missing; details and the acceptance matrix are in [Club service setup](../server/club/README.md).

The original optional iCloud proposal was replaced with a separate backend after checking [Apple's health-data rule](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research), which prohibits storing personal health information in iCloud. An updated preference question was sent; with no reply, implementation proceeded with the recommended separate service, keeping the full shared-activity scope. This was an implementation assumption, not a user-confirmed hosting choice.

Further Club improvements in priority order:
1. Connect the owner's Apple team and HTTPS host, then finish real two-account testing: Apple sign-in, private invite, two contributions, offline replay, host removal, cancelled plans, opt-out and account deletion. This is the remaining accepted-scope gate.
2. Before public release, add service monitoring without personal payloads, a tested backup/deletion policy, server-to-server credential-revocation handling, and load/abuse checks appropriate to the chosen host. The current single-instance SQLite service is suitable for acceptance, not a demonstrated production-capacity claim.
3. Consider optional change notifications and a visible Planner link to group cancellation. Keep users in control of their personal schedule.
4. After beta feedback, add recurring group plans, next-week target changes and host transfer. Avoid leaderboards, pace comparisons or revealing undiscovered pets.

## Delivery and follow-up

- [x] Build and inspect native simulator fixture screens for all three areas. The latest build also runs on iPhone 18 Pro Max, with the actual Buddy screen and all four tabs visually verified on 27 September. Manual navigation remains unverified because Device Hub window control times out.
- [x] Run final local behavior/integration and regression checks: 236 iOS tests and 11 server tests passed. Provisioned-service and physical-device checks remain separate.
- [x] Record completed work, concrete limitations and prioritized further improvements above.

Planner and Buddy remain usable without an account. The overall goal is unfinished: actual multi-user Club acceptance requires the owner's Apple signing setup and chosen Club host. The 27 September check still found zero valid local signing identities and blank team/API settings. The latest simulator build is running; the earlier locked-Mac condition has been superseded by a Device Hub window-control timeout. Local implementation, tests and previews are ready; actual multi-user acceptance cannot be replaced by fixtures. Continue with the owner's team/hosting details and follow the service acceptance matrix. No paid resources, deployment, signing registration, TestFlight upload or store submission have been performed.


## 27 September additions

The buddy-focused workout screen, daily quests/streak gifts, and private friends/result feed extend this implementation. See [Daily quests and friends](daily-quests-friends.md) for behavior, evidence and prioritized follow-ups. Optional explicit friend posts can share reduced workout results; the club activity-day contribution remains unchanged. Real Apple/service acceptance is still outstanding.
