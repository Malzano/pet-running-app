# Workout coverage

Checked 24 September 2026 against Apple's current workout list and the installed Xcode iPhoneOS 27 SDK, `HealthKit.framework/Headers/HKWorkoutActivityType.h` and `HKTypeIdentifiers.h`.

## Catalog and compatibility

`Shared/WorkoutActivity.swift` contains **80 selectable activities: 79 single-activity types and Multisport**. This covers every nondeprecated, publicly available HealthKit workout type in the installed SDK, including the activities in [Apple's Workout app list](https://support.apple.com/en-us/105089). Indoor/outdoor and pool/open-water are configurations of their activity, rather than duplicate sports. Apple's “Dance” maps to `cardioDance`, “Rolling” to `preparationAndRecovery`, and “Stair Stepper” to `stairClimbing`.

The catalog intentionally excludes three deprecated aliases (raw IDs 14, 15, 30), the unassigned ID 81, the transition segment (83), and unavailable rest/group sentinels (2998/2999). Underwater Diving (84) is an additional public HealthKit type; recording that session does not implement a dive computer or depth/decompression instrumentation. The authoritative type definitions are [HKWorkoutActivityType](https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype) and the local SDK header.

Identifiers are portable Codable strings. HealthKit's numeric IDs are mapped explicitly and verified against an independent raw-ID coverage fixture. A missing legacy workout configuration decodes as Outdoor Running. Existing activity-only configurations use that activity's sensible default setting. Invalid locations are normalized; nonfinite, nonpositive, or excessive pool lengths fall back to 25 metres.

## Measurements

| Activities | Primary measurement | Distance source |
| --- | --- | --- |
| Run, walk, hike | Pace | Walking/running distance |
| Wheelchair walk/run pace | Pace | Wheelchair distance |
| Cycling, hand cycling | Speed | Cycling distance |
| Swimming | Swim pace | Swimming distance |
| Downhill skiing, snowboarding | Speed | Downhill snow-sports distance |
| Cross-country skiing, rowing, paddling, skating | Speed | Corresponding sport distance on iOS 18 / watchOS 11 or newer |
| Multisport | Combined distance and duration | Current leg's distance type; no combined pace |
| Other sports, strength, dance, recovery, mind/body | Duration | No unrelated running distance |

Distance capability is not a guarantee of samples: equipment, device sensors, authorization, and OS version determine availability. The four newer distance identifiers are availability-gated; they return nil on iOS 17 / watchOS 10. GPS routes require an outdoor configuration and a route-appropriate activity. A pool swim never requests an open-water route, even at an outdoor pool. Indoor cycling must not turn GPS drift into distance.

Non-distance workouts earn 6 XP per active minute. Distance workouts retain the existing 52 XP/km reward, with a 3 XP/minute fallback when distance is unavailable; Multisport uses duration rewards. No calories, distances, or heart-rate values are fabricated for missing sensors.

## Multisport

The configuration carries an ordered list of swimming, cycling, and running legs, allowing triathlons and combinations such as run–bike–run. Other sports are not valid legs of HealthKit's `swimBikeRun` type. Each leg gets its own HealthKit configuration and distance metric. Pool swimming retains its lap length; cycling and running default outdoors.

The tracking integration must actually call HealthKit's activity-change API when the user advances a leg. It must preserve the overall workout ID, aggregate each completed leg once, and keep transitions and overall duration distinct. Automatic sport recognition from Apple's own Workout app is not implied. See Apple's [multisport activity model](https://developer.apple.com/documentation/healthkit/dividing-a-healthkit-workout-into-activities) and [Workout app multisport behavior](https://support.apple.com/guide/watch/combine-multiple-workouts-apdf42f22a41/watchos).

`WorkoutActivityTests.swift` covers complete catalog IDs, real HealthKit constants, search, Codable migration, pool/open-water configuration, indoor GPS exclusion, duration rewards, invalid inputs, and multisport leg configuration. UI, connectivity, session recovery, and HealthKit saving require their own integration validation.
