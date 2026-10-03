# Discovery and adventures

Implemented 25 September 2026. The product remains an account-free, local companion app. Undiscovered species have no catalogue, silhouette checklist, or preview. This change implements the five recommendations from the WIRTUAL comparison; clubs, coaching programs, a public social feed and commercial reward partnerships remain later decisions.

## Player experience

1. **Repeatable discovery.** Every 180 credited minutes with a grown companion earns a mystery egg. Its inheritance is generated and persisted at the milestone. Welcoming it never rerolls it. A player finishes raising the current youngster before welcoming another; existing companions remain visitable from the map's At home section. Only already-welcomed companions appear there. Duplicate species are possible and remain distinct companions.
2. **An adult story.** Three repeatable expeditions take 60, 120 and 180 adult progress minutes. Each finishes with a dated memory and a habitat decoration, usable immediately. The active expedition waits while visiting a youngster and resumes with any grown companion. Each individual adult also earns a Happy hop at 60 minutes and a distinct Victory dance plus Trusted friend milestone at 180. There is no expiry or rest penalty.
3. **Everyday movement.** Settings → Everyday activity asks for read access to steps and workouts, separately from workout-recording permission. It is off by default. It imports data recorded after opt-in and rechecks up to seven days on app foreground or Sync now. Turning it off stops reads and preserves rewards. Re-enabling starts a new read window; independent high-water marks count newly shared steps without replaying the old window. Workouts imported from Health are not written back to Health.
4. **Gentle weekly adventures.** Choose two to five days per week, with at least five progress minutes on each qualifying day. Weeks begin Monday in the local calendar. The target locks once a qualifying day is earned; later edits set the next week's target. Completing it automatically awards a permanent keepsake exactly once, even after relaunch or delayed activity. Rest days do not remove earned progress.
5. **Sharing.** Workout results and Adventures open a preview of a 1080-pixel-wide image card. The default conceals the companion. Players can reveal their own hatched companion and include or omit activity type and minutes. Eggs remain concealed even if reveal is requested. No route, coordinates, heart rate or other Health readings enter the export. The system share sheet handles the user's chosen destination; PawPace does not send anything automatically.

## Ownership and credit

`CompanionJourney` is stored in the same atomic protected snapshot as lifecycle growth, XP and workout identities. Each resident retains a stable identity, name, species, lifecycle and genes, friendship, energy, mood, accessory and adult minutes. Level, XP, coins, the equipped habitat, discoveries and weekly rewards are shared by the family. Changing companions is disabled during an active, interrupted or finishing workout.

One hundred steps is one **game progress minute**, not a physiological estimate. On a day, the credit entitlement is the larger of total unique workout minutes and step progress, capped at 60 minutes. They are not added together. This deliberately favors conservative credit where activity sources overlap. Only the new increase in entitlement can grow the visiting companion or advance an adult adventure. Step credit shapes Endurance; previously awarded genes are not rewritten when a workout arrives later. Movement applies to the companion being visited when that movement reaches PawPace.

Growth through adulthood and the excess credited minutes are split: the remaining growth finishes the youngster; only the remainder advances adult milestones. Switching pets cannot reset the family's cap. Completed workouts use their finish day, including workouts crossing midnight. Step totals use their Health calendar day. Records of historical days preserve caps through delayed delivery.

Workout identities, known phone/Watch aliases and persisted unions of active intervals prevent repeated reward credit. Health imports also exclude PawPace-originated saves and their sync metadata, and manually entered workouts. The existing durable completion outbox handles rewards and journal retries. Deleting the journal does not delete the reward ledger. Disabling Everyday activity while a read is in flight discards the result. Permission errors, empty shared data, and storage failures have separate, honest messages; an empty Health result is never treated as proof of denied permission.

On the phone, snapshot mutation timestamps reflect arrival time rather than historical workout time, so the Watch can accept new progress from delayed activity. Fitness-bearing files continue to use the existing protected, backup-excluded storage.

## Verification

`CompanionJourneyTests` covers repeated eggs, inheritance persistence, resident preservation and switching, shared daily limits, maturity spillover, expedition idempotency, step/workout ordering, late and decreasing data, opt-in windows, overlap exclusion, legacy migration, weekly boundaries and targets, concealed share content and delayed Watch updates.

`EverydayActivityTests` uses an injected reader to exercise opt-in, repeated sync, permission failure, storage retry, and disabling during a read. `JourneyPresentationTests` captures the adult and young-family journey, memories, tricks, accessibility text, Everyday activity, the sharing preview and both card variants. Existing workout, recovery, storage, animation and lifecycle suites remain part of regression verification. Exact run results and reviewed artifacts are recorded in `verification.md`.

The Simulator cannot establish signed physical Health reads, real device upload timing or actual Watch delivery. Those remain physical-device acceptance checks, alongside manual share destinations and accessibility navigation.

## Recommended next work

1. **Signed iPhone/Watch acceptance, then a small beta.** Exercise the opt-in flow with real steps and external workouts, delayed Watch uploads, offline days, permission changes, sharing, and backup-free storage recovery. Ship only after these routes work on devices.
2. **Validate pacing before expanding the roster.** Observe whether a small group returns after adulthood, finds the map, understands weekly goals and wants to earn another egg. Test the 180-minute egg interval and the conservative step conversion with user consent and qualitative feedback before changing rarity or adding grind.
3. **Protect the family investment.** Add an explicit encrypted export/restore or an opt-in backup design, preserving identities and reward ledgers. The current local data is excluded from system backups, so replacement-phone recovery is a material product gap.
4. **Expand the world based on beta feedback.** Add a small set of richer expedition chapters and companion interactions. Consider opt-in, spoiler-controlled friend sharing after the solo discovery loop is compelling. Clubs, training plans and brand rewards require separate backend, editorial and partnership work.

## Sources used for implementation

- [Apple: statistics collection queries](https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries)
- [Apple: ShareLink](https://developer.apple.com/documentation/swiftui/sharelink)
- [Apple: ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer)
- [WIRTUAL's published features and release history](https://apps.apple.com/us/app/wirtual/id1502074660)
