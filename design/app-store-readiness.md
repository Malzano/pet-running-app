# App Store release preparation

Updated 26 September 2026. Version **1.0.0, build 1** has local release preparation; the new optional Club service still needs provisioning and acceptance. The archive evidence below predates Planner, expanded Buddy and Club; see the latest section of verification for current checks. The nine-species expansion has a validated unsigned device archive for all four shipped bundles. Its 168-case Simulator run exposed one framing issue; that issue was fixed and all 18 affected camera/special tests passed on rerun, while the other 167 cases passed in the full run. The results are recorded in [verification](verification.md). The signing, public policy, asset ownership and physical-device items below must be completed before submission; this local validation does not establish App Store approval.

## Packaging prepared in the repository

- iPhone application for iOS 17+, Apple Watch companion for watchOS 10+, Home Screen widgets, and the separate iOS 18+ Live Activity extension. Xcode 27 is installed on the development Mac. Apple currently requires Xcode 26+ with a version 26+ SDK for uploads. The deployment target is separate from the SDK used to build. [Current requirements](https://developer.apple.com/news/upcoming-requirements/) · [Submission SDKs](https://developer.apple.com/app-store/submitting/)
- Existing phone and Watch icons are opaque 1024 × 1024 PNGs in `AppIcon.appiconset`. The phone's app-icon build setting is explicit. Xcode supports generating asset-catalog icon sizes from this single source image. [Asset catalog icons](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- Release uses optimized whole-module compilation, debug symbol bundles, no testability, and product validation. All embedded targets inherit one marketing version and build number. The first release is prepared as version `1.0.0`, build `1`.
- Each shipped bundle explicitly copies a `PrivacyInfo.xcprivacy`. iOS targets declare own preferences (`CA92.1`) and same-App-Group preferences (`1C8F.1`); Watch declares own preferences only. There are no tracking domains. The phone manifest now declares account-linked User ID, Fitness, Health and Other User Content for optional Club functionality; the Watch and extensions collect no developer data. Health and Fitness cover a dated achievement that can derive from HealthKit or a PawPace workout; raw measurements are not uploaded. [Apple's reason categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- Phone and Watch have HealthKit entitlements and purpose strings that describe workouts, heart rate, energy, and distance. Location access is explained for outdoor distance workouts. The phone and both extensions share the same App Group; the Watch uses WatchConnectivity. [HealthKit privacy requirements](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
- Buddy and Planner need no account. Club has a Sign in with Apple client and a separate Node/SQLite service, but its API URL and signing team are currently unconfigured. There are no advertisements, purchases, analytics SDK or remote chat service. Legacy chat/voice source files remain excluded in `project.yml`.
- Fitness-bearing pet snapshots use a protected JSON file in `Library/Application Support/PawPacePrivate`, inside the shared iOS App Group or the Watch's private container. The directory is excluded from backup before any file write. Successful migration removes the old preferences copy; unreadable/corrupt originals are preserved and surfaced as an error. Coordinated transactions prevent widget interactions from overwriting a newer workout save. Workout reward IDs are persisted with pet progress, so an interrupted external-ledger update cannot credit the same workout twice.

## Data inventory and policy work

The privacy declaration describes the current shipping code, not a promise that every future feature has the same data practices. Review it whenever adding a SDK, server, diagnostics upload, or sharing feature.

| Data | Purpose and storage |
| --- | --- |
| Pet name, species, growth, traits, currency, habitat and movement totals | Protected local snapshot excluded from backup; selected pet state reaches the paired Watch and iOS widgets. Legacy preferences are removed after successful migration. Older device backups may still contain the earlier preferences copy. |
| Workout identifiers and credit ledger | Local deduplication of saved rewards and growth. |
| Workout time and available fitness measurements | Shown during workouts and in summaries; Apple Health access requires the user's permission. New journal records use a protected local file excluded from backup. |
| Interrupted sessions and pending Health saves | Protected local files excluded from backup retain the workout identity, configuration, measured state and necessary summaries. Recovery offers recorded time as paused; time while the app was closed is not credited. Legacy phone pending-summary and Watch recovery preferences migrate after a successful private-file write. |
| Pending completions | A protected outbox retains the canonical workout summary and known phone/Watch IDs until pet rewards, the requested journal entry and terminal acknowledgments are durable. Journal deletion cancels pending journal writes while retaining earned pet rewards. |
| GPS coordinates | Temporary route/distance calculations during suitable outdoor workouts. Raw routes are not uploaded to a developer service or retained in the journal. |
| Personal plans and memory photos | Protected phone storage, excluded from backup. Photo metadata is removed; photos are never sent to Club. |
| Optional Club account and social data | Apple subject, generated alias, membership, private club names, scheduled activities and preset encouragements reach the Club service only after sign-in. See [service inventory and retention](../server/club/README.md). |
| Optional Club activity days | An opted-in dated achievement is linked to the member alias; underlying workouts, steps, routes, measurements and companion identity remain local. Erase-days, leave and account deletion controls remove the relevant service records. |
| HealthKit workout copies | Saved to Apple Health when authorized. The user controls those copies and permissions in Apple Health. Clearing the PawPace journal does not delete Health records or undo earned pet rewards. |

Apple distinguishes local processing from data collected by the developer. A release with Club must **not** use the earlier Data Not Collected answer. Declare the collected User ID, Health/Fitness and Other User Content as linked to the user for app functionality, with no tracking. Confirm the exact final label against the deployed service and publisher support/logging practices before submission. Apple's own framework data practices are separate. [App privacy definitions](https://developer.apple.com/app-store/app-privacy-details/)

The app includes an in-app explanation of data use and controls. A hosted public privacy policy and public support page still need an owner-provided URL and contact identity. Keep the hosted policy consistent with the in-app explanation, including retention, deletion, permissions, paired-device sharing and HealthKit. Do not insert placeholder domains into the app. Apple requires an accessible policy inside the app and a policy link in its store metadata. [Review guideline 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)

The workout journal and pet snapshots use Application Support storage with file protection and backup exclusion, rather than placing fitness history or movement totals in preferences. The dedicated parent directories retain exclusion across atomic file replacement. This cannot retroactively remove data from older system backups. [UserDefaults storage](https://developer.apple.com/documentation/foundation/userdefaults) · [Backup exclusion](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup)

## Required owner and device work

| Gate | Evidence still needed |
| --- | --- |
| Signing and identifiers | `DEVELOPMENT_TEAM` is blank, and the local signing-identity audit found **0 valid code-signing identities**. Select an existing Apple Developer Program team with distribution access for **all four shipped targets**, register available bundle IDs and the App Group, and obtain valid provisioning. If IDs change, update the Watch companion ID in its Info.plist and `PawPaceShared.suiteName` as well. No developer membership or identifier ownership has been assumed. |
| Club service and Apple sign-in | Supply an Apple team with Sign in with Apple enabled for the actual phone bundle ID, a server-side key, an HTTPS service with persistent protected storage, and the app API build setting. Complete the two-account matrix in [Club service setup](../server/club/README.md), including Apple token exchange/revocation and account deletion. No live backend or real two-account verification exists yet. |
| HealthKit on real hardware | The device audit found simulators only, with no physical device connected. Signed physical iPhone + paired Apple Watch testing is needed for sensor readings, actual Health saves, permission denial/revocation, phone/Watch recovery, finish delivery, indoor/pool sessions, outdoor GPS and screen-locked workouts. Simulator tests do not replace these. |
| Public policy and support | Owner-controlled HTTPS policy and support URLs, accurate contact details, and policy text approved by the publisher. Add the public policy link to the in-app privacy screen once supplied. |
| Rights and publisher details | Confirm commercial distribution rights for all nine bundled Meshy models, the axolotl reference artwork, and icon. The source directory records downloads from the user's workspace but does not prove the account's license terms. Supply the actual copyright/publisher identity. |
| Store setup | Create/choose the owner's App Store Connect record, confirm version 1.0.0 and complete the current age-rating questionnaire, privacy answers, category, territorial availability and export-compliance questionnaire, and attach final screenshots/review notes. No prices, legal declarations, or ownership records have been submitted. |
| Final distribution validation | Generate a signed device archive; run Xcode Organizer **Validate App**, resolve all errors, then conduct TestFlight testing before App Review. No upload or submission has been made. |

These distribution steps require the developer's team and a real archive. [Prepare distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution) · [Validate and beta test](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)

## Repeatable local checks

Run from the repository root:

```sh
python3 scripts/validate_sources.py
python3 scripts/validate_release.py
xcodegen generate
xcodebuild -project PawPace.xcodeproj -scheme PawPace -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project PawPace.xcodeproj -scheme PawPace -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/PawPaceRelease.xcarchive CODE_SIGNING_ALLOWED=NO archive
python3 scripts/validate_release.py --archive /tmp/PawPaceRelease.xcarchive
```

The unsigned archive checks compilation and packaging only. For an archive made with the owner's team and provisioning, add `--require-signing` to the validation script. The script checks all four bundled executables, consistent versions/IDs, compiled assets, privacy manifests, runtime animals and debug symbols. It never uploads, signs, or changes account settings. Keep build/test output outside the repository and use a new archive/result path for each final run. See [verification results](verification.md) for completed checks and remaining device limitations.

The current local archive is `/Users/athikom/Developer/PawPace-Releases/PawPace-1.0.0-fantasy-final-20260925.xcarchive`; its build log is `/tmp/pawpace-fantasy-final-archive.log`. Test results and the resolved framing regression are recorded in [verification](verification.md). Live catalogue movement, orbit and button zoom were checked in Simulator, with both saved phone snapshots unchanged. Manual pinch and physical-device Data Protection, HealthKit, paired-device delivery and performance still require acceptance testing.

## Physical acceptance scenarios

1. Install cleanly, receive one egg, relaunch without rerolling, complete a short phone workout with Health and Location both denied, and confirm time/progress still work. Check the user-facing permission explanation and help.
2. Grant only selected Health types, record with available sensors, verify missing values stay empty, and compare the saved Apple Health workout type, dates, duration, energy and distance with the completed session. Revoke permissions while inactive and retry.
3. Complete Watch-started and phone-started sessions; pause/resume on either device, lock screens, move out of range, reconnect, finish offline, and relaunch. Confirm one saved workout and one reward, with setup/paused time excluded.
4. Check outdoor walking/running/cycling GPS accuracy; test indoor distance fallback, pool lap length/swimming measurements, manual Multisport stages and recovery after interruption. Declare only features that pass on the hardware supported at launch.
5. Test the minimum supported OS versions as well as current versions; small iPhone/Watch sizes, accessibility text, VoiceOver, Reduce Motion and low power. Check prolonged field rendering for battery use and heat.
6. Hatch and grow an actual pet over multiple sessions/days; check the daily cap, coat changes, rare reveal persistence, existing-save migration, widget/Watch sync, rename and journal deletion. Do not use fixture screenshots as proof of end-to-end hardware behavior.
7. Verify the public policy/support links, first launch, journal empty/error states, app background/foreground, no-network operation, widgets, Live Activity controls and App Store screenshot fidelity on the final signed build.
