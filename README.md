# PawPace

PawPace is a native SwiftUI fitness companion game. Runs earn XP and friendship, unlock equipment, and evolve an original creature companion. The project includes interactive Home Screen widgets and a running Live Activity.

## Requirements

- macOS with Xcode 16 or newer
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

In Xcode, select your Apple Developer team for both `PawPace` and `PawPaceWidgets`. Replace the sample bundle identifiers and App Group if those identifiers are unavailable in your account. The value in `PawPaceShared.suiteName` must always match both entitlements.

## Targets

- `PawPace`: SwiftUI app with Home, Chat, Run, and Collection experiences.
- `PawPaceWidgets`: 2×2 compact widget, 4×4 habitat widget, and running Live Activity.
- `PawPaceTests`: progression and persistence-independent model tests.

## Current chat behavior

The first implementation uses a local personality engine and on-device speech recognition/text-to-speech, so it runs without an API key. Replace `LocalCompanionChatService` with a secure backend implementation when connecting an AI model. Never ship a provider API key inside the iOS app.

