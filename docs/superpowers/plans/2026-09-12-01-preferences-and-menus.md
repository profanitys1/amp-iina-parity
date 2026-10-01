# Plan 1: Preferences, first-run migration and dynamic menus

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every preference reachable, give preference keys a migration path before they start moving, and stop the menus lying about what is available.

**Architecture:** A versioned migration runs once at launch, before anything reads a default. `SettingsView.swift` is split so each pane is its own file, and the twenty settings with no control get one. Menu items that are currently always-enabled become driven by the same focused-value state the rest of the menu already uses.

**Tech Stack:** Swift 6, SwiftUI, UserDefaults.

## Global Constraints

- Deployment target macOS 15.0, Swift 6 strict concurrency.
- Build/test with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`.
- SPDX header on every file; `OSLog` subsystem `com.aagedal.MediaPlayer`; no attribution lines in commits.
- **Migration lands before the split.** Once panes move, key names will follow; without a migration in place, every rename silently resets a user's preference.
- **Do not change any existing key name in this plan.** Migration is the mechanism; use it later, deliberately.
- `Speed Down` and `Speed Up` keep no keyboard shortcut. That gap is deliberate — a shortcut there collides with the `[`/`]` rate stepping in the key monitor.
- Settings that are runtime state, not preferences, stay out of the UI: `playbackVolume`, `playbackMuted`, `controlBarPositionHorizontal`, `controlBarPositionVertical`, `didShowCompareModeCallout`, `didShowAutoUpdateNotice`, `updateLastChecked`.


## Status (2026-10-01): Tasks 1 to 3 landed on `main`; Task 4 was already in place

Commits `e2736e2`, `c8ee2c2` and `a4b54a6`. Full suite: 712 passed, 5 skipped, 0 failed.

- **Task 1:** `SettingsMigration` runs at launch, before `registerDefaults`.
- **Task 2:** the panes live in `UI/Settings/`. They are `internal`, not `private`, because `SettingsView` in another file has to reach them.
- **Task 3:**
  - The new Playback pane holds the 14 settings that had no control, plus `hardwareDecoder`.
  - A new Colour section in Rendering holds `hdrEnabled`, `loadDisplayICCProfile` and `toneMappingTargetPeakOverride`.
  - The 14 settings were not registered at all, so `defaultsDictionary` now includes them (same defaults, so no behaviour change).
  - `SettingsCoverageTests.testEveryDeclaredSettingIsListed` parses `AppSettings.swift`, so a declared but unregistered key can no longer slip past the coverage test.
  - Verified on device: the panes render, and with `preventDisplaySleep` on, playback holds `PreventUserIdleDisplaySleep`; with it off, no assertion.
- **Task 4: not built.** Every item in the table already had the right `.disabled(...)` condition on `main` (Comparison Review Notes uses `isCompareModeActive != true`). A `MenuAvailability` type would only restate the same rules.

The settings tab bar now overflows into a `»` menu (Audio, Shortcuts and Updates). It already did before this plan; the sidebar this plan defers is the fix when that becomes a problem.

---

## File Structure

Before: `UI/SettingsView.swift` is 845 lines holding six panes; `RenderSettingsView`
and `UpdateSettingsView` already live in their own files.

| File | Responsibility |
|------|----------------|
| `Logic/SettingsMigration.swift` | **New.** Versioned, once-per-upgrade preference migration. |
| `UI/Settings/SettingsView.swift` | Moved. The `TabView` only. |
| `UI/Settings/GeneralSettingsView.swift` | Moved out of the monolith. |
| `UI/Settings/ScreenshotSettingsView.swift` | Moved. |
| `UI/Settings/ExportSettingsView.swift` | Moved. |
| `UI/Settings/ScopeSettingsView.swift` | Moved. |
| `UI/Settings/AudioSettingsView.swift` | Moved. |
| `UI/Settings/KeyboardShortcutsView.swift` | Moved. |
| `UI/Settings/LocationSettingsSection.swift` | Moved. Shared by Screenshots and Export. |
| `UI/Settings/PlaybackSettingsView.swift` | **New.** The unreachable audio/decode/demuxer settings. |

---

### Task 1: Versioned preference migration

**Files:**
- Create: `Aagedal Media Player/Logic/SettingsMigration.swift`
- Modify: `Aagedal Media Player/Aagedal_Media_PlayerApp.swift` (`applicationDidFinishLaunching`)
- Test: `Aagedal Media Player Tests/SettingsMigrationTests.swift`

**Interfaces:**
- Produces:
  ```swift
  nonisolated enum SettingsMigration {
      static let currentVersion: Int
      static func migrate(_ defaults: UserDefaults)
      static func rename(from old: String, to new: String, in defaults: UserDefaults)
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/SettingsMigrationTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class SettingsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// A fresh install is stamped with the current version and nothing is moved.
    func testFreshInstallIsStampedCurrent() {
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"),
                       SettingsMigration.currentVersion)
    }

    func testRenameMovesAValue() {
        defaults.set(42, forKey: "oldKey")
        SettingsMigration.rename(from: "oldKey", to: "newKey", in: defaults)
        XCTAssertEqual(defaults.integer(forKey: "newKey"), 42)
        XCTAssertNil(defaults.object(forKey: "oldKey"))
    }

    /// A value the user already set under the new name wins over the old one.
    func testRenameDoesNotClobberAnExistingValue() {
        defaults.set(1, forKey: "oldKey")
        defaults.set(2, forKey: "newKey")
        SettingsMigration.rename(from: "oldKey", to: "newKey", in: defaults)
        XCTAssertEqual(defaults.integer(forKey: "newKey"), 2)
        XCTAssertNil(defaults.object(forKey: "oldKey"))
    }

    func testRenameOfAbsentKeyIsHarmless() {
        SettingsMigration.rename(from: "missing", to: "target", in: defaults)
        XCTAssertNil(defaults.object(forKey: "target"))
    }

    /// Running twice must not repeat work.
    func testMigrationIsIdempotent() {
        SettingsMigration.migrate(defaults)
        let stamped = defaults.integer(forKey: "settingsVersion")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"), stamped)
    }

    /// A profile from a newer build must not be downgraded.
    func testFutureVersionIsLeftAlone() {
        defaults.set(SettingsMigration.currentVersion + 5, forKey: "settingsVersion")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"),
                       SettingsMigration.currentVersion + 5)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/SettingsMigrationTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'SettingsMigration' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/SettingsMigration.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Moves stored preferences forward across upgrades. This exists before any key
// is renamed on purpose: without it, renaming a key silently resets whatever
// the user had chosen, and there is no way to notice after the fact.
//
// To add a migration: raise currentVersion by one, and add a case to the switch
// for the version being migrated FROM.

import Foundation
import OSLog

nonisolated enum SettingsMigration {
    static let versionKey = "settingsVersion"

    /// Raise by one whenever a step is added below.
    static let currentVersion = 1

    private static let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "settings")

    static func migrate(_ defaults: UserDefaults = .standard) {
        let stored = defaults.integer(forKey: versionKey)

        // A profile written by a newer build: leave it alone rather than
        // rewriting keys this build does not understand.
        guard stored < currentVersion else { return }

        // A first run has nothing to move; stamping it means later upgrades
        // know where they started from.
        guard stored > 0 else {
            defaults.set(currentVersion, forKey: versionKey)
            return
        }

        for version in stored..<currentVersion {
            apply(version: version, in: defaults)
        }
        defaults.set(currentVersion, forKey: versionKey)
        logger.info("Migrated preferences from version \(stored, privacy: .public) to \(currentVersion, privacy: .public)")
    }

    /// One step, migrating away from `version`.
    private static func apply(version: Int, in defaults: UserDefaults) {
        switch version {
        default:
            break
        }
    }

    /// Moves a value to a new key, keeping whatever is already there.
    static func rename(from old: String, to new: String, in defaults: UserDefaults = .standard) {
        guard let value = defaults.object(forKey: old) else { return }
        if defaults.object(forKey: new) == nil {
            defaults.set(value, forKey: new)
        }
        defaults.removeObject(forKey: old)
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/SettingsMigrationTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Run it at launch, before defaults are registered**

In `Aagedal Media Player/Aagedal_Media_PlayerApp.swift`, make
`applicationDidFinishLaunching` start with:

```swift
        SettingsMigration.migrate()
        AppSettings.registerDefaults()
```

Order matters: migration must see the stored domain before registration layers
defaults over it.

- [ ] **Step 6: Commit**

```bash
git add "Aagedal Media Player/Logic/SettingsMigration.swift" \
        "Aagedal Media Player/Aagedal_Media_PlayerApp.swift" \
        "Aagedal Media Player Tests/SettingsMigrationTests.swift"
git commit -m "Give preferences a migration path

Added before any key is renamed, because a rename without one silently resets
whatever the user chose and leaves no trace."
```

---

### Task 2: Split the settings monolith

**Files:**
- Create: `Aagedal Media Player/UI/Settings/` and move seven views into it
- Delete: the moved code from `Aagedal Media Player/UI/SettingsView.swift`

**Interfaces:**
- Unchanged: `SettingsView` remains the entry point with the same name. The pane
  structs stay `private` to their new files except where already shared.
- `LocationSettingsSection` becomes `internal` (it is used by two panes).

**Why:** 845 lines holding six panes is hard to edit without collateral damage,
and `RenderSettingsView`/`UpdateSettingsView` already demonstrate the one-file-per-pane
pattern this follows.

- [ ] **Step 1: Create the directory and move the panes**

The project uses file-system-synchronised groups, so creating files on disk is
enough — no `.xcodeproj` edit is required.

```bash
mkdir -p "Aagedal Media Player/UI/Settings"
```

Move each of these out of `UI/SettingsView.swift` into its own file under
`UI/Settings/`, carrying its `@AppStorage` properties with it and adding the
SPDX header and the `import SwiftUI` each needs:

| From lines | New file | Type |
|---|---|---|
| 230-387 | `GeneralSettingsView.swift` | `GeneralSettingsView` |
| 290-386 | `LocationSettingsSection.swift` | `LocationSettingsSection` (make it `internal`) |
| 388-450 | `ScreenshotSettingsView.swift` | `ScreenshotSettingsView` |
| 454-592 | `ExportSettingsView.swift` | `ExportSettingsView` |
| 596-669 | `ScopeSettingsView.swift` | `ScopeSettingsView` |
| 670-753 | `AudioSettingsView.swift` | `AudioSettingsView` |
| 757-845 | `KeyboardShortcutsView.swift` | `KeyboardShortcutsView` |

`LocationSettingsSection` is nested inside the General range; extract it first,
then the rest. Each moved struct loses its `private` modifier only if it is used
from another file — `LocationSettingsSection` is; the panes are not, so they
stay `private` in their own file.

Finally move `SettingsView` itself to `UI/Settings/SettingsView.swift` and delete
`UI/SettingsView.swift`.

- [ ] **Step 2: Build after every two files**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`. A "cannot find type in scope" means a struct that
needs to be `internal` is still `private`.

- [ ] **Step 3: Confirm the panes still render**

Launch the app, open Settings, and click through all eight tabs. Each must show
the same controls as before.

- [ ] **Step 4: Commit**

```bash
git add -A "Aagedal Media Player/UI/Settings" "Aagedal Media Player/UI/SettingsView.swift"
git commit -m "Split the settings panes into their own files

845 lines holding six panes made every edit risk collateral damage. Matches
the one-file-per-pane pattern the render and update panes already used."
```

---

### Task 3: A pane for the settings nothing can reach

**Files:**
- Create: `Aagedal Media Player/UI/Settings/PlaybackSettingsView.swift`
- Modify: `Aagedal Media Player/UI/Settings/SettingsView.swift` (add the tab)
- Test: `Aagedal Media Player Tests/SettingsCoverageTests.swift`

**Interfaces:**
- Consumes: the settings Plan 0 added — `preventDisplaySleep`, `quitWhenNoOpenedWindow`,
  `audioPassthroughCodecs`, `replayGainMode`, `replayGainPreamp`, `replayGainClip`,
  `replayGainFallback`, `gaplessAudio`, `forceAVFoundationOutput`, `videoDecodeThreads`,
  `audioDecodeThreads`, `preferredAudioLanguages`, `demuxerMaxBytes`, `demuxerReadaheadSeconds`.
- Also surfaces, if Plans 2 and 3 have landed: `hdrEnabled`, `loadDisplayICCProfile`,
  `toneMappingTargetPeakOverride`, `hardwareDecoder`.

- [ ] **Step 1: Write the failing test**

This test is the point of the task: it fails whenever a setting is added without
a way to change it.

Create `Aagedal Media Player Tests/SettingsCoverageTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

/// Guards against a setting being added with no way to change it. Twenty keys
/// had drifted into that state before this existed.
final class SettingsCoverageTests: XCTestCase {
    /// Runtime state and one-shot flags, which are deliberately not preferences.
    private let notUserFacing: Set<String> = [
        "playbackVolume",
        "playbackMuted",
        "controlBarPositionHorizontal",
        "controlBarPositionVertical",
        "didShowCompareModeCallout",
        "didShowAutoUpdateNotice",
        "updateLastChecked",
        "updateCheckInterval",
        "settingsVersion",
    ]

    func testEveryUserFacingSettingHasAControl() throws {
        let settingsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("Aagedal Media Player/UI")
        let sources = try FileManager.default
            .subpathsOfDirectory(atPath: settingsDirectory.path)
            .filter { $0.hasSuffix(".swift") }
            .map { try String(contentsOf: settingsDirectory.appendingPathComponent($0), encoding: .utf8) }
            .joined()

        var missing: [String] = []
        for key in AppSettings.allKeys where !notUserFacing.contains(key) {
            if !sources.contains("AppSettings.\(key)") {
                missing.append(key)
            }
        }
        XCTAssertTrue(missing.isEmpty,
                      "Settings with no control anywhere in UI/: \(missing.sorted().joined(separator: ", "))")
    }
}
```

- [ ] **Step 2: Expose the key list**

The test needs to enumerate keys. In
`Aagedal Media Player/Logic/AppSettings.swift`, add at the end of the enum:

```swift
    /// Every stored key, for coverage checks. Keep in step with registerDefaults.
    static var allKeys: [String] {
        Array(defaultsDictionary.keys)
    }
```

and refactor `registerDefaults(in:)` to build from one dictionary so the two
cannot drift:

```swift
    static var defaultsDictionary: [String: Any] {
        [
            allowMultipleWindows.key: allowMultipleWindows.defaultValue,
            // … every existing entry from registerDefaults, unchanged …
        ]
    }

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: defaultsDictionary)
    }
```

- [ ] **Step 3: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/SettingsCoverageTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Settings with no control|Executed"
```

Expected: a failure naming `audioPassthroughCodecs`, `replayGainMode`,
`preventDisplaySleep` and the rest.

- [ ] **Step 4: Write the pane**

Create `Aagedal Media Player/UI/Settings/PlaybackSettingsView.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Decode, audio-output and buffering settings. Every control here defaults to
// mpv's own behaviour, so an untouched install plays exactly as it did.

import SwiftUI

struct PlaybackSettingsView: View {
    @AppStorage(AppSettings.preventDisplaySleep.key)
    private var preventDisplaySleep = AppSettings.preventDisplaySleep.defaultValue
    @AppStorage(AppSettings.quitWhenNoOpenedWindow.key)
    private var quitWhenNoOpenedWindow = AppSettings.quitWhenNoOpenedWindow.defaultValue
    @AppStorage(AppSettings.audioPassthroughCodecs.key)
    private var audioPassthroughCodecs = AppSettings.audioPassthroughCodecs.defaultValue
    @AppStorage(AppSettings.replayGainMode.key)
    private var replayGainMode = AppSettings.replayGainMode.defaultValue
    @AppStorage(AppSettings.replayGainPreamp.key)
    private var replayGainPreamp = AppSettings.replayGainPreamp.defaultValue
    @AppStorage(AppSettings.replayGainClip.key)
    private var replayGainClip = AppSettings.replayGainClip.defaultValue
    @AppStorage(AppSettings.replayGainFallback.key)
    private var replayGainFallback = AppSettings.replayGainFallback.defaultValue
    @AppStorage(AppSettings.gaplessAudio.key)
    private var gaplessAudio = AppSettings.gaplessAudio.defaultValue
    @AppStorage(AppSettings.forceAVFoundationOutput.key)
    private var forceAVFoundationOutput = AppSettings.forceAVFoundationOutput.defaultValue
    @AppStorage(AppSettings.videoDecodeThreads.key)
    private var videoDecodeThreads = AppSettings.videoDecodeThreads.defaultValue
    @AppStorage(AppSettings.audioDecodeThreads.key)
    private var audioDecodeThreads = AppSettings.audioDecodeThreads.defaultValue
    @AppStorage(AppSettings.preferredAudioLanguages.key)
    private var preferredAudioLanguages = AppSettings.preferredAudioLanguages.defaultValue
    @AppStorage(AppSettings.demuxerMaxBytes.key)
    private var demuxerMaxBytes = AppSettings.demuxerMaxBytes.defaultValue
    @AppStorage(AppSettings.demuxerReadaheadSeconds.key)
    private var demuxerReadaheadSeconds = AppSettings.demuxerReadaheadSeconds.defaultValue

    var body: some View {
        Form {
            Section("Session") {
                Toggle("Keep the Display Awake While Playing", isOn: $preventDisplaySleep)
                Toggle("Quit When the Last Window Closes", isOn: $quitWhenNoOpenedWindow)
            }

            Section("Audio Output") {
                Toggle("Force AVFoundation Output", isOn: $forceAVFoundationOutput)
                TextField("Passthrough Codecs", text: $audioPassthroughCodecs,
                          prompt: Text("ac3,dts,eac3"))
                Text("Comma-separated codecs to send to a receiver undecoded. Empty decodes everything locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Gapless Playback", selection: $gaplessAudio) {
                    Text("Weak").tag("weak")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                }
            }

            Section("Level Adjustment") {
                Picker("ReplayGain", selection: $replayGainMode) {
                    Text("Off").tag("no")
                    Text("Track").tag("track")
                    Text("Album").tag("album")
                }
                Text("Off by default: a review tool should not quietly change the level of the thing being reviewed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if replayGainMode != "no" {
                    Stepper("Pre-amp: \(replayGainPreamp, specifier: "%.1f") dB",
                            value: $replayGainPreamp, in: -15...15, step: 0.5)
                    Stepper("Fallback: \(replayGainFallback, specifier: "%.1f") dB",
                            value: $replayGainFallback, in: -15...15, step: 0.5)
                    Toggle("Prevent Clipping", isOn: $replayGainClip)
                }
            }

            Section("Decoding") {
                Stepper(videoDecodeThreads == 0
                        ? "Video Threads: Automatic"
                        : "Video Threads: \(videoDecodeThreads)",
                        value: $videoDecodeThreads, in: 0...32)
                Stepper(audioDecodeThreads == 0
                        ? "Audio Threads: Automatic"
                        : "Audio Threads: \(audioDecodeThreads)",
                        value: $audioDecodeThreads, in: 0...32)
                TextField("Preferred Audio Languages", text: $preferredAudioLanguages,
                          prompt: Text("eng,nor"))
            }

            Section("Buffering") {
                TextField("Demuxer Size", text: $demuxerMaxBytes, prompt: Text("Automatic"))
                Text("For example 2GiB. Backward playback and long-GOP 4K both want more than the default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(demuxerReadaheadSeconds == 0
                        ? "Readahead: Automatic"
                        : "Readahead: \(demuxerReadaheadSeconds, specifier: "%.0f") s",
                        value: $demuxerReadaheadSeconds, in: 0...120, step: 5)
            }

            Section {
                Text("Changes apply the next time a file is opened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 5: Add the tab**

In `Aagedal Media Player/UI/Settings/SettingsView.swift`, after the General tab:

```swift
            PlaybackSettingsView()
                .tabItem { Label("Playback", systemImage: "play.circle") }
```

- [ ] **Step 6: Run the coverage test and watch it pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/SettingsCoverageTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Settings with no control|Executed"
```

Expected: `Executed 1 test, with 0 failures`. If it still names keys added by
Plans 2 or 3, add those controls here too, or add them to `notUserFacing` only
if they are genuinely internal.

- [ ] **Step 7: Verify by hand**

Open Settings, Playback. Change Video Threads to 4, open a file, and confirm
playback still works. Turn "Keep the Display Awake While Playing" off, play, and
confirm with `pmset -g assertions` that no display assertion is held.

- [ ] **Step 8: Commit**

```bash
git add "Aagedal Media Player/UI/Settings/PlaybackSettingsView.swift" \
        "Aagedal Media Player/UI/Settings/SettingsView.swift" \
        "Aagedal Media Player/Logic/AppSettings.swift" \
        "Aagedal Media Player Tests/SettingsCoverageTests.swift"
git commit -m "Give the unreachable settings a home

Fourteen settings had no control anywhere, so the only way to change them was
to edit the defaults domain by hand. A test now fails when a setting is added
without a way to change it."
```

---

### Task 4: Menus that reflect what is actually available

**Files:**
- Modify: `Aagedal Media Player/Aagedal_Media_PlayerApp.swift` (the `.commands` block, lines 71-295)
- Test: `Aagedal Media Player Tests/MenuAvailabilityTests.swift`

**Interfaces:**
- Consumes the existing focused values: `isMediaLoaded`, `canOpenPreviousFile`,
  `canOpenNextFile`, `isCompareModeActive`.
- Produces: `MenuAvailability` — a pure decision type so the rules are testable
  without a running menu.

**The problem:** several items are always enabled and post commands that do
nothing when no file is loaded. The focused values to fix that already exist and
are already used by some items; this makes the rest consistent.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/MenuAvailabilityTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class MenuAvailabilityTests: XCTestCase {
    private let empty = MenuAvailability(isMediaLoaded: false, isCompareModeActive: false,
                                         canOpenPreviousFile: false, canOpenNextFile: false)
    private let playing = MenuAvailability(isMediaLoaded: true, isCompareModeActive: false,
                                           canOpenPreviousFile: true, canOpenNextFile: true)

    /// Opening a file must always be possible; that is the way out of an empty window.
    func testOpenIsAlwaysAvailable() {
        XCTAssertTrue(empty.allows(.openFile))
        XCTAssertTrue(playing.allows(.openFile))
    }

    func testPlaybackNeedsMedia() {
        XCTAssertFalse(empty.allows(.togglePlayback))
        XCTAssertTrue(playing.allows(.togglePlayback))
    }

    func testScreenshotNeedsMedia() {
        XCTAssertFalse(empty.allows(.captureScreenshot))
        XCTAssertTrue(playing.allows(.captureScreenshot))
    }

    func testFileNavigationFollowsTheFolder() {
        XCTAssertFalse(empty.allows(.openPreviousFile))
        XCTAssertTrue(playing.allows(.openPreviousFile))
    }

    /// Review notes belong to Compare Mode and mean nothing outside it.
    func testReviewNotesNeedCompareMode() {
        XCTAssertFalse(playing.allows(.toggleReviewNotes))
        let comparing = MenuAvailability(isMediaLoaded: true, isCompareModeActive: true,
                                         canOpenPreviousFile: false, canOpenNextFile: false)
        XCTAssertTrue(comparing.allows(.toggleReviewNotes))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MenuAvailabilityTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'MenuAvailability' in scope`.

- [ ] **Step 3: Write the decision type**

Create `Aagedal Media Player/Logic/MenuAvailability.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Whether a menu command applies right now. Kept apart from the menu itself so
// the rules can be checked without a running app — several items used to stay
// enabled and post a command that quietly did nothing.

import Foundation

nonisolated struct MenuAvailability {
    let isMediaLoaded: Bool
    let isCompareModeActive: Bool
    let canOpenPreviousFile: Bool
    let canOpenNextFile: Bool

    enum Command {
        case openFile
        case togglePlayback
        case captureScreenshot
        case exportTrim
        case openPreviousFile
        case openNextFile
        case toggleReviewNotes
        case toggleInspectionLoupe
        case reloadPlayer
        case copyTimecode
        case pasteTimecode
    }

    func allows(_ command: Command) -> Bool {
        switch command {
        case .openFile:
            return true
        case .openPreviousFile:
            return canOpenPreviousFile
        case .openNextFile:
            return canOpenNextFile
        case .toggleReviewNotes:
            return isMediaLoaded && isCompareModeActive
        case .togglePlayback, .captureScreenshot, .exportTrim,
             .toggleInspectionLoupe, .reloadPlayer, .copyTimecode, .pasteTimecode:
            return isMediaLoaded
        }
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MenuAvailabilityTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Drive the menu from it**

In `Aagedal Media Player/Aagedal_Media_PlayerApp.swift`, add a computed property
beside `mediaLoaded`:

```swift
    private var menuAvailability: MenuAvailability {
        MenuAvailability(
            isMediaLoaded: isMediaLoaded ?? false,
            isCompareModeActive: isCompareModeActive ?? false,
            canOpenPreviousFile: canOpenPreviousFile ?? false,
            canOpenNextFile: canOpenNextFile ?? false)
    }
```

Then add `.disabled(!menuAvailability.allows(.togglePlayback))` and the matching
call for each item in the table below. Items that already carry a
`.disabled(!mediaLoaded)` keep working — replace those for consistency.

| Menu item | Command |
|---|---|
| Play / Pause, Mute, volume, Reverse, Fast Forward, slow/speed items | `.togglePlayback` |
| Save Screenshot / Export Comparison Still | `.captureScreenshot` |
| Export Trim… | `.exportTrim` |
| Previous File in Folder | `.openPreviousFile` |
| Next File in Folder | `.openNextFile` |
| Comparison Review Notes | `.toggleReviewNotes` |
| Inspection Loupe | `.toggleInspectionLoupe` |
| Reload Player | `.reloadPlayer` |
| Copy Timecode | `.copyTimecode` |
| Paste Timecode | `.pasteTimecode` |

Leave Speed Down and Speed Up without a keyboard shortcut.

- [ ] **Step 6: Verify by hand**

Launch with no file open. Every item in the table must be greyed out except
Open. Open a file and confirm they enable; leave Compare Mode and confirm
Comparison Review Notes greys out again.

- [ ] **Step 7: Run the full suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed [0-9]+ tests|error:|TEST"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add "Aagedal Media Player/Logic/MenuAvailability.swift" \
        "Aagedal Media Player/Aagedal_Media_PlayerApp.swift" \
        "Aagedal Media Player Tests/MenuAvailabilityTests.swift"
git commit -m "Grey out menu items that cannot do anything

Several stayed enabled with no file open and posted a command that quietly did
nothing. The focused values needed to know better already existed."
```

---

## Deliberately not built

IINA's `PreferenceWindowController` — a sidebar list with a search field over
searchable panes. The tabbed container already works and holds nine panes
comfortably; the sidebar earns its place at roughly a dozen. Revisit when the
tab strip runs out of room, not before.
