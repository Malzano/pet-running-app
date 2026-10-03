# Pet lifecycle

Fresh players receive one egg with a persisted random seed, species, and inheritance roll. Reopening the app does not create another egg. Species stays concealed until hatching. Existing snapshots without lifecycle data keep their established companion as an adult, together with their earned resources.

New eggs use a weighted species catalogue, independent of coat inheritance:

| Species rarity | Combined chance | Companions | Chance per companion |
| --- | ---: | --- | ---: |
| Common | 84% | Corgi, Bunny, Penguin | 28% |
| Rare | 15% | Red panda, Fox, Axolotl | 5% |
| Mythic | 1% | Dragon, Unicorn, Phoenix | 1/3% |

The species roll uses 3,000 fixed slots, so the equal split is exact rather than rounded. Existing eggs retain the animal and coat already stored in their lifecycle; loading a saved egg never reapplies the new catalogue to its seed. All tiers earn growth and ordinary workout rewards at the same rate. Species rarity is shown separately from a rare coat after hatching, and undiscovered species remain hidden: there is no catalogue or species preview, and the guide does not name possible companions or their special moves.

Rare and Mythic companions each have a signature movement: red panda **Leaf tumble**, fox **Firefly pounce**, axolotl **Bubble dance**, dragon **Fire breath**, unicorn **Rainbow leap**, and phoenix **Ember flourish**. These are companion behaviors, not ways to increase growth or alter inheritance.

| Stage | Requirement | Appearance |
| --- | --- | --- |
| Egg | First 30 progress minutes | Spotted egg in a grassy nest |
| Baby | Another 180 progress minutes | Smaller version of the hatched animal |
| Adult | 210 total credited minutes | Full size; genes and coat settled |

Completed workouts and optional everyday activity contribute. All supported activities earn the same growth per active minute. Growth, genes and adult adventures share a family-wide 60-minute daily cap, counted on the workout's finish day. A workout crossing midnight belongs to that finish day. Historical day totals and processed workout IDs survive save/load, including delayed Watch delivery. Time beyond a growth cap can still earn ordinary workout rewards. Pauses are excluded by the workout recorder; feeding, petting, play, speed, heart rate and calories do not add growth. Rest days do not remove growth.

| Gene | Examples | Ordinary coat |
| --- | --- | --- |
| Endurance | Walk/run, wheelchair, cycle, swim, row | Mint |
| Power | Strength, core, boxing, gymnastics | Peach |
| Calm | Yoga, Pilates, flexibility, recovery | Lavender |
| Explorer | Hiking, dance, games, sports | Sky |

The full, exhaustive activity mapping is `WorkoutActivity.geneticTrait`. Duration weights each gene; a stable enum order resolves exact ties. The dominant trait determines ordinary coat color while growing. Adult genetics are fixed. The genetic signature and habitat choices are available in the companion’s progress sheet from Home.

One independent inheritance roll produces 94% ordinary workout-shaped color, 5% Moonlight, and 1% Aurora. A rare coat replaces the ordinary coat but retains the workout-shaped gene profile. It is revealed at hatching and shown through tint and static sparkle accents. The seed and actual inheritance values are saved, so a restart cannot reroll them.

The iPhone is the reward authority for completed phone and Watch workouts. Workout IDs are saved in the same atomic pet snapshot as XP, currency, and movement totals; the legacy external reward ledger remains compatible, and the lifecycle also deduplicates its own workout IDs. Pet snapshots carry the same lifecycle to Watch and widgets. Live Activity fields are optional for compatibility with older activity payloads.

Snapshots use coordinated, protected local JSON storage excluded from device backup. A successful migration preserves the old pet and then removes its preferences copy. Corrupt or unreadable saves are kept and surfaced to the user; they do not silently become a new egg. Garden interactions read and mutate the latest stored snapshot in one transaction, preserving workouts saved by another app/extension process.

Balance constants live in `Shared/PetLifecycle.swift`. Hatch and maturity timestamps let the workout summary celebrate the completing session. The garden still rotates at every stage; eggs stay in their nest and gain care actions after hatching.

## Continuing discovery

The family state lives in `CompanionJourney`, in the same atomic snapshot as the active pet. Adult progress beyond maturity contributes to a repeatable 180-minute egg meter. Each earned egg is generated and saved at the milestone, not when opened. A player can welcome the next egg only when the whole family is grown; earlier companions remain visitable. Switching companions cannot reset the daily cap or replay workout identities.

Expeditions, weekly rhythms, everyday activity deduplication, and sharing rules are documented in [discovery and adventures](discovery-adventures.md). Step progress is a game conversion (100 steps per minute), counts toward Endurance, and shares a daily maximum with workout minutes rather than being added to them. Only newly credited minutes shape genes, so previously awarded step growth is not rewritten by a later workout.
