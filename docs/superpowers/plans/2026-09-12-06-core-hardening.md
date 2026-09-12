# Core Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the defects a read-only audit of the MPV core found — a main-thread stall on the mpv queue, teardown outside the serial queue, an unconditional 4 GiB decode buffer, a duplicated HDR transition, a fixed 0.5 s wait where mpv already emits an event, a data race in the scope capture path, and no way to see which hardware decoder actually engaged — and make the test suite tell the truth about what it skipped.

**Architecture:** No new subsystems. Every task is a bounded change to an existing file plus one new pure helper that carries the decision under test. The recurring pattern is already the codebase's own: extract the decision into a `nonisolated` value type with a pure function (`PlaybackVolume`, `PlaybackSeekTime`, `LatestFrameGate`, `OperationGeneration` all follow it), unit-test that, then wire it into the imperative shell. Where a fix is inherently about a live mpv context, the test uses the fixture-backed integration pattern that `CompareLiveBackendTests` already established.

**Tech Stack:** Swift 6, SwiftUI + AppKit, XCTest, Xcode 26 command-line builds, libmpv (MPVKit-GPL, mpv 0.41.0, FFmpeg n8.1.2, MoltenVK 1.4.2), `OSAllocatedUnfairLock` from the `os` module.

**Spec:** This plan implements the findings recorded in the core audit delivered on 2026-09-12. The audit's evidence is reproduced inline per task, as `file:line` anchors, because the executor works task-by-task and cannot see the audit.

## Global Constraints

- Deployment target macOS 15.0. Swift 6 strict concurrency is on and the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type is main-actor isolated unless it says otherwise. Types touched from an mpv event thread or a `NotificationCenter` block need explicit `nonisolated`.
- Build and test with signing disabled, or the build fails on this machine with "No signing certificate":
  `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- Pass those three settings as **trailing build-setting arguments**. Environment-variable prefixes are ignored by `build-for-testing` and the build then fails on signing.
- Metal API Validation must stay OFF in the scheme's Run diagnostics (MoltenVK race, KhronosGroup/MoltenVK#2226).
- Every source file carries `// SPDX-License-Identifier: GPL-3.0-or-later`.
- Logging uses `OSLog` with subsystem `com.aagedal.MediaPlayer`.
- Commit messages: the message only. No `Generated with`, no `Co-Authored-By`.
- Work on branch `iina-parity`.
- Xcode 26 does not print an `Executed N tests` line. Judge a run by `TEST SUCCEEDED` and by the per-case lines `Test case '<Suite>.<method>()' passed on ...`.
- New files under `Aagedal Media Player/` or `Aagedal Media Player Tests/` join their target automatically: the project uses `PBXFileSystemSynchronizedRootGroup` (four of them in `Aagedal Media Player.xcodeproj/project.pbxproj`). Do not edit the project file.
- Test suites that touch main-actor state declare `@MainActor` on the `XCTestCase` subclass. Assertions inside an `@autoclosure` cannot read a main-actor property from a nonisolated context, which is why the constant under test is `nonisolated`.

## Scope

This plan deliberately does **not** repeat work already planned:

| Concern | Already planned in |
|---|---|
| Display colour, EDR, ICC, display peak brightness | `2026-09-12-02-colour-pipeline.md` |
| hwdec probe, hwdec preference, generic `vf` chain | `2026-09-12-03-hwdec-and-filters.md` |
| Moving the clock off `PlayerController` to stop whole-tree re-renders | `2026-09-12-05-playback-clock-split.md` |

Task 3 below only *observes* the effective decoder. It never sets `hwdec`, so it neither conflicts with plan 3 nor depends on it landing first.

## Task Ordering

Tasks 1 and 2 are independent and can land first. Tasks 3 through 9 touch `MPVPlayer.swift`, `PlayerController.swift` and `FrameCapture.swift` and must land in order, one commit each, because each one re-reads the file the previous one edited.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Aagedal Media Player Tests/OptionalInput.swift` | Create. One helper that turns a missing environment variable into `XCTSkip`. |
| `Aagedal Media Player Tests/OptionalInputTests.swift` | Create. Proves the helper skips when unset and returns when set. |
| `Aagedal Media Player Tests/ITUProgrammeLoudnessTests.swift` | Modify. Use the helper instead of passing silently. |
| `Aagedal Media Player Tests/ITUSevenPointOneLoudnessTests.swift` | Modify. Same. |
| `Aagedal Media Player Tests/LoudnessPerformanceTests.swift` | Modify. Same. |
| `Aagedal Media Player Tests/TimelineThumbnailLoaderTests.swift` | Modify. Same. |
| `Aagedal Media Player Tests/RIFXAudioDecodingTests.swift` | Modify. Skip when the bundled ffmpeg is absent instead of failing. |
| `Aagedal Media Player/Logic/MPV/HardwareDecodingStatus.swift` | Create. Maps an mpv `hwdec-current` value to a user-facing label and a boolean. |
| `Aagedal Media Player Tests/HardwareDecodingStatusTests.swift` | Create. |
| `Aagedal Media Player/Logic/MPV/MPVClockMirror.swift` | Create. Lock-protected last clock sample, readable without touching the mpv queue. |
| `Aagedal Media Player Tests/MPVClockMirrorTests.swift` | Create. |
| `Aagedal Media Player/Logic/MPV/ReverseBufferPolicy.swift` | Create. Decides the next reversal-buffer size after each overflow. |
| `Aagedal Media Player Tests/ReverseBufferPolicyTests.swift` | Create. |
| `Aagedal Media Player/Logic/Scopes/HDRTransferResolver.swift` | Create. One pure decision from a colour-transfer string to transfer function plus peak. |
| `Aagedal Media Player Tests/HDRTransferResolverTests.swift` | Create. |
| `Aagedal Media Player/Logic/Scopes/OneShotFlag.swift` | Create. Thread-safe claim-once gate. |
| `Aagedal Media Player Tests/OneShotFlagTests.swift` | Create. |
| `Aagedal Media Player/Logic/MPV/MPVProperty.swift` | Modify. Add `hwdecCurrent` and `videoReversalBuffer`. |
| `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` | Modify. Observe `hwdec-current`; read the clock from the mirror; tear down on the serial queue; raise the reversal buffer on demand; clear the mirror on destroy. |
| `Aagedal Media Player/Logic/PlayerController.swift` | Modify. One HDR transition; refresh tracks on the file-loaded signal. |
| `Aagedal Media Player/UI/RenderSettingsView.swift` | Modify. Show the effective decoder. |
| `Aagedal Media Player/Logic/Scopes/FrameCapture.swift` | Modify. Replace the racy static flag with `OneShotFlag`. |

---

### Task 1: Make opt-in test suites report a skip instead of a pass

Four suites currently return early when their environment variable is unset. They report `passed` while running no assertions, so a green suite overstates coverage. Verified pattern, `ITUProgrammeLoudnessTests.swift:15`:

```swift
guard let directory = ProcessInfo.processInfo.environment["ITU_LOUDNESS_REFERENCE_DIRECTORY"] else { return }
```

The same shape appears at `ITUSevenPointOneLoudnessTests.swift:13`, `LoudnessPerformanceTests.swift:14` and `TimelineThumbnailLoaderTests.swift:16`.

**Files:**
- Create: `Aagedal Media Player Tests/OptionalInput.swift`
- Create: `Aagedal Media Player Tests/OptionalInputTests.swift`
- Modify: `Aagedal Media Player Tests/ITUProgrammeLoudnessTests.swift:13-17`
- Modify: `Aagedal Media Player Tests/ITUSevenPointOneLoudnessTests.swift:11-15`
- Modify: `Aagedal Media Player Tests/LoudnessPerformanceTests.swift:12-16`
- Modify: `Aagedal Media Player Tests/TimelineThumbnailLoaderTests.swift:14-18`

**Interfaces:**
- Produces: `OptionalInput.require(_ name: String) throws -> String`. Throws `XCTSkip` when the variable is missing or empty; otherwise returns the value. Later tasks do not call it.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/OptionalInputTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

final class OptionalInputTests: XCTestCase {
    private let name = "AAGEDAL_OPTIONAL_INPUT_TEST"

    override func tearDown() {
        unsetenv(name)
        super.tearDown()
    }

    /// A missing variable must skip, not return an empty string the caller
    /// would then hand to file APIs.
    func testMissingVariableSkips() {
        unsetenv(name)
        XCTAssertThrowsError(try OptionalInput.require(name)) { error in
            XCTAssertTrue(error is XCTSkip, "Expected XCTSkip, got \(type(of: error))")
        }
    }

    /// An empty value is as useless as a missing one.
    func testEmptyVariableSkips() {
        setenv(name, "", 1)
        XCTAssertThrowsError(try OptionalInput.require(name)) { error in
            XCTAssertTrue(error is XCTSkip, "Expected XCTSkip, got \(type(of: error))")
        }
    }

    func testPresentVariableIsReturned() throws {
        setenv(name, "/tmp/example", 1)
        XCTAssertEqual(try OptionalInput.require(name), "/tmp/example")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/OptionalInputTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: compile error, `cannot find 'OptionalInput' in scope`.

- [ ] **Step 3: Write the helper**

Create `Aagedal Media Player Tests/OptionalInput.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

/// Reads an environment variable that some suites cannot run without.
///
/// Returning early instead would report the suite as passed while it asserted
/// nothing, which is how a green run can overstate what was covered. Skipping
/// keeps that distinction visible in the test report.
nonisolated enum OptionalInput {
    static func require(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw XCTSkip("Set \(name) to run this suite.")
        }
        return value
    }
}
```

- [ ] **Step 4: Run the helper's tests**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/OptionalInputTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: three `passed` lines and `TEST SUCCEEDED`.

- [ ] **Step 5: Route the four suites through it**

In `ITUProgrammeLoudnessTests.swift`, replace the first three lines of the test body — the doc comment stays:

```swift
    func testOfficialProgrammeReferencesWhenRequested() async throws {
        let directory = try OptionalInput.require("ITU_LOUDNESS_REFERENCE_DIRECTORY")
        // ITU-R BS.2217-2, programme rows on printed pages 4–5: -23 ±0.1 LKFS.
```

The old body began:

```swift
        guard let directory = ProcessInfo.processInfo.environment["ITU_LOUDNESS_REFERENCE_DIRECTORY"] else { return }
        XCTAssertFalse(directory.isEmpty, "Specify the directory containing all three official WAV files")
        guard !directory.isEmpty else { return }
```

The `XCTAssertFalse` and second `guard` are dead once `require` has rejected the empty case.

In `ITUSevenPointOneLoudnessTests.swift`, replace:

```swift
        guard let directory = ProcessInfo.processInfo.environment["ITU_7_1_REFERENCE_DIRECTORY"] else { return }
        XCTAssertFalse(directory.isEmpty)
        guard !directory.isEmpty else { return }
```

with:

```swift
        let directory = try OptionalInput.require("ITU_7_1_REFERENCE_DIRECTORY")
```

In `LoudnessPerformanceTests.swift`, replace:

```swift
        guard let input = ProcessInfo.processInfo.environment["LOUDNESS_PROFILE_INPUTS"] else { return }
```

with:

```swift
        let input = try OptionalInput.require("LOUDNESS_PROFILE_INPUTS")
```

In `TimelineThumbnailLoaderTests.swift`, replace:

```swift
        guard let input = ProcessInfo.processInfo.environment["TIMELINE_PROFILE_INPUTS"] else { return }
```

with:

```swift
        let input = try OptionalInput.require("TIMELINE_PROFILE_INPUTS")
```

- [ ] **Step 6: Verify the four suites now skip**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/ITUProgrammeLoudnessTests" -only-testing:"Aagedal Media Player Tests/ITUSevenPointOneLoudnessTests" -only-testing:"Aagedal Media Player Tests/LoudnessPerformanceTests" -only-testing:"Aagedal Media Player Tests/TimelineThumbnailLoaderTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -iE "skipped|passed|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: each suite reports a skip, and the run still ends `TEST SUCCEEDED`. Previously the same command reported four passes.

- [ ] **Step 7: Commit**

```bash
git add "Aagedal Media Player Tests/OptionalInput.swift" \
        "Aagedal Media Player Tests/OptionalInputTests.swift" \
        "Aagedal Media Player Tests/ITUProgrammeLoudnessTests.swift" \
        "Aagedal Media Player Tests/ITUSevenPointOneLoudnessTests.swift" \
        "Aagedal Media Player Tests/LoudnessPerformanceTests.swift" \
        "Aagedal Media Player Tests/TimelineThumbnailLoaderTests.swift"
git commit -m "Report opt-in test suites as skipped, not passed

Four suites returned early when their reference directory or profile input
was unset, which reported them as passed while they asserted nothing.
Route them through one helper that throws XCTSkip, so a green run says what
it actually covered."
```

---

### Task 2: Skip the RIFX suite when the bundled ffmpeg is absent

`RIFXAudioDecodingTests.swift:11` hard-unwraps the bundled binary. The app ships it at `Aagedal Media Player/Binaries/ffmpeg` and `FFmpegService.ffmpegPath` is `Bundle.main.path(forResource: "ffmpeg", ofType: nil)`, so this passes in a normal build. When the resource is missing the suite fails with an unrelated "unexpectedly found nil" rather than saying the environment is incomplete.

**Files:**
- Modify: `Aagedal Media Player Tests/RIFXAudioDecodingTests.swift:11`

**Interfaces:**
- Consumes: `OptionalInput` from Task 1. This task cannot start before Task 1 is committed.
- Produces: nothing later tasks call.

- [ ] **Step 1: Write the failing test**

Add to `Aagedal Media Player Tests/OptionalInputTests.swift`, inside `OptionalInputTests`:

```swift
    /// A nil optional is the shape a missing bundled resource arrives in.
    func testMissingOptionalSkips() {
        XCTAssertThrowsError(try OptionalInput.require(path: nil, what: "the bundled ffmpeg")) { error in
            XCTAssertTrue(error is XCTSkip, "Expected XCTSkip, got \(type(of: error))")
        }
    }

    func testPresentOptionalIsReturned() throws {
        XCTAssertEqual(try OptionalInput.require(path: "/bin/ls", what: "a binary"), "/bin/ls")
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/OptionalInputTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: compile error, `extra arguments at positions #1, #2 in call` — the two-argument overload does not exist yet.

- [ ] **Step 3: Add the overload**

Append inside `nonisolated enum OptionalInput` in `Aagedal Media Player Tests/OptionalInput.swift`:

```swift
    /// Reads a resource whose absence is an environment problem, not a defect.
    static func require(path: String?, what: String) throws -> String {
        guard let path, !path.isEmpty else {
            throw XCTSkip("\(what) is unavailable in this build.")
        }
        return path
    }
```

- [ ] **Step 4: Run the helper's tests**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/OptionalInputTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: five `passed` lines and `TEST SUCCEEDED`.

- [ ] **Step 5: Use it in the RIFX suite**

In `RIFXAudioDecodingTests.swift`, replace:

```swift
        let ffmpeg = try XCTUnwrap(FFmpegService.ffmpegPath)
```

with:

```swift
        let ffmpeg = try OptionalInput.require(path: FFmpegService.ffmpegPath, what: "The bundled ffmpeg")
```

Every later use of `ffmpeg` in that method is unaffected: the binding is still a non-optional `String`.

- [ ] **Step 6: Verify the suite still runs and passes**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/RIFXAudioDecodingTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `passed` and `TEST SUCCEEDED`, because the bundled binary is present in this checkout.

- [ ] **Step 7: Commit**

```bash
git add "Aagedal Media Player Tests/OptionalInput.swift" \
        "Aagedal Media Player Tests/OptionalInputTests.swift" \
        "Aagedal Media Player Tests/RIFXAudioDecodingTests.swift"
git commit -m "Skip the RIFX suite when the bundled ffmpeg is missing

The suite hard-unwrapped the bundled binary, so an incomplete build failed
with an unrelated nil unwrap instead of saying the environment was not
ready to run it."
```

---

### Task 3: Show which hardware decoder actually engaged

`MPVPlayer.swift:247` sets `hwdec` and never asks what mpv chose. mpv exposes `hwdec-current` for exactly this: "The current hardware decoding in use. If decoding is active, return one of the values used by the `hwdec` option/property. `no` indicates software decoding. If no decoder is loaded, the property is unavailable." (`DOCS/man/input.rst:2844`.) Without it, a silent fall back to software decoding is invisible.

This task only observes. It does not change how `hwdec` is set, so it is independent of plan 3.

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/HardwareDecodingStatus.swift`
- Create: `Aagedal Media Player Tests/HardwareDecodingStatusTests.swift`
- Modify: `Aagedal Media Player/Logic/MPV/MPVProperty.swift` (add `hwdecCurrent` under the "Video parameters" block)
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` (add the published field, register the observer, handle the event)
- Modify: `Aagedal Media Player/UI/RenderSettingsView.swift` (show it)

**Interfaces:**
- Produces: `HardwareDecodingStatus` with `init(mpvValue: String?)`, `var isHardwareBacked: Bool`, `var label: String`, and `static let unavailable: HardwareDecodingStatus`.
- Produces: `MPVPlayer.activeHardwareDecoder: String?` — `@Published private(set)`, main-actor, `nil` until mpv reports a value.
- Produces: `PlayerController.activeHardwareDecoder: String?` — `@Published private(set)`, reset to `nil` on teardown.
- Produces: `AppCommand.hardwareDecoderChanged(String)` — the cross-window carrier, matching the existing `setRenderProfile(RenderProfile)` case.
- Produces: `MPVProperty.hwdecCurrent` — `"hwdec-current"`.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/HardwareDecodingStatusTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class HardwareDecodingStatusTests: XCTestCase {
    /// mpv reports `no` when it fell back to software decoding.
    func testSoftwareDecodingIsNotHardwareBacked() {
        let status = HardwareDecodingStatus(mpvValue: "no")
        XCTAssertFalse(status.isHardwareBacked)
        XCTAssertEqual(status.label, "Software decoding")
    }

    /// No decoder loaded yet is not the same as software decoding, and must
    /// not be shown as if it were a result.
    func testUnavailableIsDistinctFromSoftware() {
        let status = HardwareDecodingStatus(mpvValue: nil)
        XCTAssertFalse(status.isHardwareBacked)
        XCTAssertEqual(status.label, "Not yet decoded")
        XCTAssertEqual(HardwareDecodingStatus.unavailable.label, status.label)
    }

    func testVideoToolboxIsHardwareBacked() {
        let status = HardwareDecodingStatus(mpvValue: "videotoolbox")
        XCTAssertTrue(status.isHardwareBacked)
        XCTAssertEqual(status.label, "Hardware decoding (videotoolbox)")
    }

    /// The copy-back variant is still hardware decode; it only changes where
    /// the frames land, which matters to filters, not to the user.
    func testCopyBackVariantIsHardwareBacked() {
        XCTAssertTrue(HardwareDecodingStatus(mpvValue: "videotoolbox-copy").isHardwareBacked)
    }

    /// An empty string is what a malformed event yields; treat it as absent.
    func testEmptyStringIsTreatedAsAbsent() {
        XCTAssertEqual(HardwareDecodingStatus(mpvValue: "").label, "Not yet decoded")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/HardwareDecodingStatusTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: compile error, `cannot find 'HardwareDecodingStatus' in scope`.

- [ ] **Step 3: Write the value type**

Create `Aagedal Media Player/Logic/MPV/HardwareDecodingStatus.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What mpv is actually decoding with, as reported by `hwdec-current`.
///
/// The value is read-only from the app's point of view. It exists so a silent
/// fall back to software decoding — the outcome when VideoToolbox refuses a
/// codec — is visible rather than inferred from CPU load.
nonisolated struct HardwareDecodingStatus: Equatable, Sendable {
    /// The raw mpv value, or `nil` when no decoder is loaded yet.
    let mpvValue: String?

    /// mpv reports this when it is decoding in software.
    static let softwareValue = "no"

    static let unavailable = HardwareDecodingStatus(mpvValue: nil)

    init(mpvValue: String?) {
        let trimmed = mpvValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mpvValue = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// True only for a real hardware decoder. `videotoolbox-copy` still
    /// decodes on the GPU; the copy is about where frames land.
    var isHardwareBacked: Bool {
        guard let mpvValue else { return false }
        return mpvValue != Self.softwareValue
    }

    var label: String {
        guard let mpvValue else { return "Not yet decoded" }
        if mpvValue == Self.softwareValue { return "Software decoding" }
        return "Hardware decoding (\(mpvValue))"
    }
}
```

- [ ] **Step 4: Run the value type's tests**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/HardwareDecodingStatusTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: five `passed` lines and `TEST SUCCEEDED`.

- [ ] **Step 5: Add the property constant**

In `MPVProperty.swift`, add below `videoParamsSigPeak`:

```swift
    /// The decoder mpv actually engaged. `no` means software decoding; the
    /// property is unavailable until a decoder is loaded.
    nonisolated static let hwdecCurrent = "hwdec-current"
```

- [ ] **Step 6: Publish it from MPVPlayer**

In `MPVPlayer.swift`, add below the `videoSigPeak` declaration (search for `@Published var videoSigPeak`):

```swift
    /// The decoder mpv reports it is using. `nil` until a decoder is loaded.
    @Published private(set) var activeHardwareDecoder: String?
```

Register the observer in `setupMPV()`, immediately after the `videoParamsSigPeak` observation:

```swift
        mpv_observe_property(mpv, 0, MPVProperty.hwdecCurrent, MPV_FORMAT_STRING)
```

Handle the event in `readEvents()`. The string-property shape already exists for `videoParamsGamma`; add a sibling case directly after the `videoParamsSigPeak` case and before `default:`:

```swift
                        case MPVProperty.hwdecCurrent:
                            if property.format == MPV_FORMAT_STRING,
                               let strPtr = UnsafePointer<UnsafeMutablePointer<CChar>>(OpaquePointer(property.data))?.pointee {
                                let decoder = String(cString: strPtr)
                                DispatchQueue.main.async { self.activeHardwareDecoder = decoder }
                            }
```

Note the ordering constraint: `MPVProperty.hwdecCurrent` must appear in the same `switch` as the other cases, and `videoParamsGamma` already proves the cast is valid for `MPV_FORMAT_STRING`.

- [ ] **Step 7: Carry it to the settings window**

Settings is its own scene — `Aagedal_Media_PlayerApp.swift:297-299` is `Settings { SettingsView() }` — so it has no `PlayerController` in its environment and there is one controller per window. Use the app's existing cross-window channel, the typed `AppCommand` broadcast, exactly as `setRenderProfile` already travels.

In `AppCommand.swift`, add a case after `case setRenderProfile(RenderProfile)`:

```swift
    case hardwareDecoderChanged(String)
```

In `PlayerController.swift`, add beside `var playbackTimePublisher`:

```swift
    /// The decoder mpv reports for the current backend, or `nil` when nothing
    /// is loaded. Forwarded so the settings window can show it without holding
    /// the per-load player instance.
    @Published private(set) var activeHardwareDecoder: String?
```

In `setupMPVObservations`, add beside the `mpvSigPeakCancellable` sink (which begins at `:724`):

```swift
        mpvDecoderCancellable = mpv.$activeHardwareDecoder
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mpv] decoder in
                guard let self, mpv != nil,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { return }
                self.activeHardwareDecoder = decoder
                NotificationCenter.default.post(.hardwareDecoderChanged(decoder ?? ""))
            }
```

Declare the cancellable beside `mpvSigPeakCancellable` at `PlayerController.swift:179`:

```swift
    private var mpvDecoderCancellable: AnyCancellable?
```

Release it in `teardown`, beside `mpvSigPeakCancellable = nil` at `:1643`:

```swift
        mpvDecoderCancellable = nil
        activeHardwareDecoder = nil
        NotificationCenter.default.post(.hardwareDecoderChanged(""))
```

In `RenderSettingsView.swift`, add beside the view's other properties:

```swift
    @State private var decoderStatus = HardwareDecodingStatus.unavailable
```

Add this section as the last child inside the existing `Form`, after the closing brace of `Section("Shaders")`:

```swift
            Section("Decoding") {
                LabeledContent("Video decoder") {
                    Text(decoderStatus.label)
                        .foregroundStyle(decoderStatus.isHardwareBacked ? .primary : .secondary)
                }

                Text("Reported by mpv for the file that is playing. A codec VideoToolbox cannot decode falls back to software, which shows here as Software decoding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

Subscribe to the broadcast by adding after the closing brace of the `Form`:

```swift
        .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
            guard case .hardwareDecoderChanged(let value) = notification.appCommand else { return }
            decoderStatus = HardwareDecodingStatus(mpvValue: value)
        }
```

`appCommandPublisher` and `appCommand` are defined in `AppCommand.swift` at `:76` and `:65`; the `setRenderProfile` case shows the same shape.

- [ ] **Step 8: Build**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 9: Confirm the app still launches**

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -name 'Aagedal Media Player.app' -path '*Debug*' | head -1)
open -a "$APP"
sleep 5
osascript -e 'tell application "System Events" to tell process "Aagedal Media Player" to count windows'
osascript -e 'tell application "Aagedal Media Player" to quit'
```

Expected: `1`. Opening Settings by hand and seeing the Decoding section read "Not yet decoded" is the confirmation that the broadcast plumbing is sound; it shows that value, not a crash, when no file is playing.

- [ ] **Step 10: Run the full suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case '.*' failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 11: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/HardwareDecodingStatus.swift" \
        "Aagedal Media Player Tests/HardwareDecodingStatusTests.swift" \
        "Aagedal Media Player/Logic/MPV/MPVProperty.swift" \
        "Aagedal Media Player/Logic/MPV/MPVPlayer.swift" \
        "Aagedal Media Player/Logic/PlayerController.swift" \
        "Aagedal Media Player/Logic/AppCommand.swift" \
        "Aagedal Media Player/UI/RenderSettingsView.swift"
git commit -m "Report the decoder mpv actually engaged

mpv exposes hwdec-current for this, and the app never asked. A codec
VideoToolbox refuses falls back to software silently, so the only symptom
was CPU load. Observing the property costs one registration and makes the
fallback visible in Rendering settings, carried to the settings scene over
the same typed AppCommand channel setRenderProfile already uses."
```

---

### Task 4: Read the playback clock without blocking the main thread

`PlayerController.playbackTimeSnapshot()` calls `mpvPlayer?.playbackTimeSnapshot()`, which takes `queue.sync` (`MPVPlayer.swift:456-461`). The caller is main-actor, so the main thread blocks on mpv's serial queue whenever it is busy draining events or extracting a 4K `screenshot-raw`. It is called twice per tick in the comparison drift loop (`CompareSessionController.swift:2042-2043`) and from eight further sites.

Fix: have the event loop keep the last observed clock in a lock-protected mirror, and read the mirror instead of entering the queue.

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/MPVClockMirror.swift`
- Create: `Aagedal Media Player Tests/MPVClockMirrorTests.swift`
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` (`playbackTimeSnapshot`, the `timePos` event case, `destroy`)

**Interfaces:**
- Produces: `MPVClockMirror` — `final class`, `Sendable`, with `func store(_ value: TimeInterval?)` and `func sample() -> TimeInterval?`.
- Produces: `MPVPlayer.playbackTimeSnapshot() -> TimeInterval?` keeps its signature and becomes non-blocking.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/MPVClockMirrorTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class MPVClockMirrorTests: XCTestCase {
    func testStartsEmpty() {
        XCTAssertNil(MPVClockMirror().sample())
    }

    func testReturnsTheLastStoredValue() {
        let mirror = MPVClockMirror()
        mirror.store(1.5)
        mirror.store(2.25)
        XCTAssertEqual(mirror.sample(), 2.25)
    }

    /// Clearing must be observable, so a torn-down player cannot report the
    /// previous file's clock to a caller that has not re-loaded yet.
    func testStoringNilClears() {
        let mirror = MPVClockMirror()
        mirror.store(3.0)
        mirror.store(nil)
        XCTAssertNil(mirror.sample())
    }

    /// The event thread writes while the main actor reads. Run both hard and
    /// assert only that the reader never sees a partial value.
    func testConcurrentWritersAndReadersAgree() async {
        let mirror = MPVClockMirror()
        let values = (0..<1_000).map { TimeInterval($0) / 10 }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for value in values { mirror.store(value) }
            }
            group.addTask {
                for _ in 0..<1_000 {
                    if let sampled = mirror.sample() {
                        XCTAssertTrue(sampled >= 0 && sampled <= values.last!, "torn read: \(sampled)")
                    }
                }
            }
        }
        XCTAssertEqual(mirror.sample(), values.last)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVClockMirrorTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: compile error, `cannot find 'MPVClockMirror' in scope`.

- [ ] **Step 3: Write the mirror**

Create `Aagedal Media Player/Logic/MPV/MPVClockMirror.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Holds the most recent playback clock sample so it can be read without
/// entering mpv's serial queue.
///
/// `mpv_get_property` is only safe while serialized on that queue, and taking
/// it with `queue.sync` from the main actor stalls the UI whenever the queue is
/// draining events or extracting a 4K screenshot. The event loop already sees
/// every `time-pos` change, so it records it here instead.
final class MPVClockMirror: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval?

    func store(_ value: TimeInterval?) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func sample() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
```

- [ ] **Step 4: Run the mirror's tests**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVClockMirrorTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: four `passed` lines and `TEST SUCCEEDED`.

- [ ] **Step 5: Feed the mirror from the event loop**

In `MPVPlayer.swift`, add beside the other private state near `queue`:

```swift
    /// Last clock sample seen by the event loop, so readers never enter `queue`.
    private let clockMirror = MPVClockMirror()
```

In `readEvents()`, inside the `case MPVProperty.timePos:` branch, record the sample before coalescing decides whether to publish:

```swift
                        case MPVProperty.timePos:
                            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                                self.clockMirror.store(value)
                                self.publishTimePos(value)
                            }
```

- [ ] **Step 6: Read the mirror instead of the queue**

Replace `playbackTimeSnapshot()` in `MPVPlayer.swift` — the current body is:

```swift
    nonisolated func playbackTimeSnapshot() -> TimeInterval? {
        queue.sync {
            guard let mpv else { return nil }
            return doublePropertyLocked(MPVProperty.timePos, context: mpv)
        }
    }
```

with:

```swift
    nonisolated func playbackTimeSnapshot() -> TimeInterval? {
        clockMirror.sample()
    }
```

Update the doc comment above it to match, replacing the existing two-line comment with:

```swift
    /// The most recent clock sample the event loop observed.
    ///
    /// This never enters mpv's queue, so main-actor callers cannot stall behind
    /// an event drain or a screenshot. It is the same sample mpv reported for
    /// `time-pos`, just read without a round trip.
```

- [ ] **Step 7: Clear the mirror on teardown**

In `destroy()`, inside the `queue.sync` block, after `self.mpv = nil`, add:

```swift
            self.clockMirror.store(nil)
```

`clockMirror` is `let` and `@unchecked Sendable`, so touching it from inside the queue block is safe and does not extend the context's lifetime.

- [ ] **Step 8: Run the suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case '.*' failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: `TEST SUCCEEDED`. The comparison drift tests in `CompareLiveBackendTests` exercise `playbackTimeSnapshot` across both backends and are the regression guard for this change.

- [ ] **Step 9: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVClockMirror.swift" \
        "Aagedal Media Player Tests/MPVClockMirrorTests.swift" \
        "Aagedal Media Player/Logic/MPV/MPVPlayer.swift"
git commit -m "Read the playback clock without blocking the main thread

playbackTimeSnapshot took queue.sync, so a main-actor caller stalled
whenever mpv's queue was draining events or extracting a 4K screenshot —
twice per tick in the comparison drift loop. The event loop already sees
every time-pos change; it records it in a lock-protected mirror and readers
take that instead."
```

---

### Task 5: Tear down on the serial queue in deinit

`MPVPlayer.swift:103-109` runs `mpv_set_wakeup_callback` and `mpv_terminate_destroy` straight from `deinit`, unlike `destroy()` (`:120-141`) which does both inside `queue.sync`. If the last reference is ever dropped without `destroy()` — a path `PlayerController.swift:1629` normally prevents — mpv can be freed while the event loop is still inside `mpv_wait_event`.

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` (queue identity, `deinit`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing later tasks call.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/MPVQueueIdentityTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class MPVQueueIdentityTests: XCTestCase {
    /// The guard that makes an on-queue teardown safe only works if the queue
    /// carries its identity marker from construction.
    func testQueueCarriesIdentityKey() {
        let player = MPVPlayer()
        XCTAssertFalse(player.isRunningOnMPVQueue)

        var observed = true
        player.withMPVQueueForTesting {
            observed = player.isRunningOnMPVQueue
        }
        XCTAssertTrue(observed)
    }

    /// A player with no mpv context must deallocate cleanly; this is the case
    /// a naive queue.sync teardown would deadlock on if run on the queue.
    func testReleaseWithoutContextDoesNotCrash() {
        var player: MPVPlayer? = MPVPlayer()
        XCTAssertNotNil(player)
        player = nil
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVQueueIdentityTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: compile error, `value of type 'MPVPlayer' has no member 'isRunningOnMPVQueue'`.

- [ ] **Step 3: Give the queue an identity and expose the check**

In `MPVPlayer.swift`, add beside the `queue` declaration:

```swift
    /// Lets teardown detect it is already serialized on `queue`, where a
    /// synchronous re-entry would deadlock.
    private static let queueIdentityKey = DispatchSpecificKey<UInt8>()

    /// True when the calling thread is executing on mpv's serial queue.
    var isRunningOnMPVQueue: Bool {
        DispatchQueue.getSpecific(key: Self.queueIdentityKey) != nil
    }
```

In `override init()`, above `super.init()`, add:

```swift
        queue.setSpecific(key: Self.queueIdentityKey, value: 1)
```

If `override init()` currently reads only `super.init()` — it does, at line 95 — the added line goes immediately before it.

Add the test seam beside `isRunningOnMPVQueue`:

```swift
    /// Runs `body` on mpv's serial queue. Test seam only.
    func withMPVQueueForTesting(_ body: () -> Void) {
        queue.sync(execute: body)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVQueueIdentityTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: two `passed` lines and `TEST SUCCEEDED`.

- [ ] **Step 5: Route deinit through the queue**

Replace the teardown inside `deinit` — currently:

```swift
        // Safety net — destroy() should have been called already.
        if mpv != nil {
            mpv_set_wakeup_callback(mpv, nil, nil)
            mpv_terminate_destroy(mpv)
            mpv = nil
        }
```

with:

```swift
        // Safety net — destroy() should have been called already.
        if let context = mpv {
            mpv_set_wakeup_callback(context, nil, nil)
            // Destroy on the same queue the event loop runs on, or mpv can be
            // freed while mpv_wait_event is still reading it. Re-entering the
            // queue synchronously from the queue itself would deadlock, so the
            // check picks the direct path in that one case.
            if isRunningOnMPVQueue {
                mpv_terminate_destroy(context)
            } else {
                queue.sync { mpv_terminate_destroy(context) }
            }
            mpv = nil
        }
```

The local `context` binding is deliberate: referencing `self` inside a `queue.sync` closure from `deinit` is the pattern Swift rejects for escaping closures, and binding first keeps the closure free of `self`.

- [ ] **Step 6: Run the suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case '.*' failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVPlayer.swift" \
        "Aagedal Media Player Tests/MPVQueueIdentityTests.swift"
git commit -m "Tear the mpv context down on its own queue in deinit

destroy() already serialized teardown the right way; the deinit safety net
did not, so dropping the last reference without destroy() could free mpv
while the event loop was still inside mpv_wait_event. The queue now carries
an identity key so the direct path is taken instead of deadlocking when
deinit somehow runs on that queue."
```

---

### Task 6: Raise the reverse-decode buffer when it is needed, not always

`MPVPlayer.swift:266-267` sets `video-reversal-buffer=4GiB` and `audio-reversal-buffer=128MiB` on every player, for a feature most sessions never use. mpv's own guidance is the opposite: "Use this option if you get reversal queue overflow errors during backward playback. Increase the size until the warning disappears." (`DOCS/man/options.rst:718`.)

The reversal buffer defaults are small; the app's 4 GiB is a pre-emptive guess. The message-parsing seam already exists at `MPVPlayer.swift:829-833`, which watches mpv's log for `"Backward playback is likely stuck"`.

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/ReverseBufferPolicy.swift`
- Create: `Aagedal Media Player Tests/ReverseBufferPolicyTests.swift`
- Modify: `Aagedal Media Player/Logic/MPV/MPVProperty.swift` (add `videoReversalBuffer`)
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` (drop the init options, raise on overflow)

**Interfaces:**
- Produces: `ReverseBufferPolicy` — `nonisolated enum` with `static let ladder: [String]`, `static func next(currentIndex: Int) -> String?` and `static func parseIndex(fromBufferValue: String) -> Int`.
- Produces: `MPVProperty.videoReversalBuffer` — `"video-reversal-buffer"`.
- Produces: `MPVPlayer.overflowDidOccur` — `PassthroughSubject<Void, Never>`; `MPVPlayer.reversalBufferStep` — `private(set) var`, main-actor.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/ReverseBufferPolicyTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class ReverseBufferPolicyTests: XCTestCase {
    /// mpv's default is used until mpv itself complains, so the first step up
    /// is the first entry in the ladder, not the biggest one.
    func testFirstOverflowTakesTheFirstStep() {
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: -1), "1GiB")
    }

    func testLadderClimbsOneStepAtATime() {
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: 0), "2GiB")
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: 1), "4GiB")
    }

    /// Past the top of the ladder the policy stops rather than growing without
    /// bound, so a pathological file cannot ask for 64 GiB.
    func testLadderEnds() {
        XCTAssertNil(ReverseBufferPolicy.next(currentIndex: 2))
    }

    func testIndexRoundTripsThroughTheValue() {
        for (index, value) in ReverseBufferPolicy.ladder.enumerated() {
            XCTAssertEqual(ReverseBufferPolicy.index(ofBufferValue: value), index)
        }
    }

    /// An unknown value means the buffer was not set by this policy.
    func testUnknownValueHasNoIndex() {
        XCTAssertNil(ReverseBufferPolicy.index(ofBufferValue: "512MiB"))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/ReverseBufferPolicyTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: compile error, `cannot find 'ReverseBufferPolicy' in scope`.

- [ ] **Step 3: Write the policy**

Create `Aagedal Media Player/Logic/MPV/ReverseBufferPolicy.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Decides how large a backward-decode buffer to ask mpv for.
///
/// mpv's documentation is explicit that this is a remedy for reversal queue
/// overflow, not a default: the buffer exists to bound resource use, and a
/// file that never overflows should never pay for one that does. The app
/// previously set 4 GiB on every player up front.
nonisolated enum ReverseBufferPolicy {
    /// Ascending sizes, applied one step per reported overflow.
    static let ladder = ["1GiB", "2GiB", "4GiB"]

    /// The size to apply after `currentIndex` overflows, or `nil` when the
    /// ladder is exhausted and mpv should keep its own default.
    static func next(currentIndex: Int) -> String? {
        let next = currentIndex + 1
        guard ladder.indices.contains(next) else { return nil }
        return ladder[next]
    }

    /// The ladder position a value corresponds to, or `nil` if the value did
    /// not come from this policy.
    static func index(ofBufferValue value: String) -> Int? {
        ladder.firstIndex(of: value)
    }
}
```

- [ ] **Step 4: Run the policy's tests**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/ReverseBufferPolicyTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: five `passed` lines and `TEST SUCCEEDED`.

- [ ] **Step 5: Add the property constant**

In `MPVProperty.swift`, add below `hwdecCurrent`:

```swift
    /// Backward-decode buffer, raised only after mpv reports a queue overflow.
    nonisolated static let videoReversalBuffer = "video-reversal-buffer"
```

- [ ] **Step 6: Stop pre-allocating the buffer at init**

In `MPVPlayer.swift`, delete these two lines from `setupMPV()` and the six-line comment block immediately above them:

```swift
        checkError(mpv_set_option_string(mpv, "video-reversal-buffer", "4GiB"), context: "video-reversal-buffer")
        checkError(mpv_set_option_string(mpv, "audio-reversal-buffer", "128MiB"), context: "audio-reversal-buffer")
```

The comment to remove is the block beginning `// Buffers required for --play-direction=backward` and ending `// and 4K AV1 without affecting RAM use on simpler files.`

Add beside the mirror from Task 4:

```swift
    /// How far up `ReverseBufferPolicy` has climbed, or -1 before any overflow.
    private var reversalBufferStep = -1

    /// Emits once per reported reversal queue overflow.
    let overflowDidOccur = PassthroughSubject<Void, Never>()
```

`PassthroughSubject` needs `import Combine`, which `MPVPlayer.swift` already has at line 6.

- [ ] **Step 7: Detect the overflow and climb**

In `readEvents()`, inside `case MPV_EVENT_LOG_MESSAGE:`, immediately after the existing `"Backward playback is likely stuck"` check and before the closing brace of that case, add:

```swift
                        // mpv reports this when the reversal buffer is too
                        // small for the file. Climb one step and let the
                        // attempt run; the ladder ends at 4 GiB.
                        if text.contains("Reversal queue overflow") {
                            DispatchQueue.main.async { [weak self] in
                                self?.raiseReversalBuffer()
                            }
                        }
```

Add the method beside `setPlayDirection`:

```swift
    /// Raises the backward-decode buffer one step. No-op once the ladder is
    /// exhausted, so a file that overflows at every size does not loop.
    func raiseReversalBuffer() {
        guard let size = ReverseBufferPolicy.next(currentIndex: reversalBufferStep) else { return }
        guard let index = ReverseBufferPolicy.index(ofBufferValue: size) else { return }
        reversalBufferStep = index
        setString(MPVProperty.videoReversalBuffer, size)
        overflowDidOccur.send()
        logger.info("Raised the reversal buffer to \(size, privacy: .public)")
    }
```

The literal `"Reversal queue overflow"` is mpv's own wording; `MPVPlayer.swift:829-833` already relies on the same technique for `"Backward playback is likely stuck"`.

- [ ] **Step 8: Verify the option is settable at runtime**

`setString` routes to `mpv_set_property_string` and logs a warning on failure, so a rejection is visible rather than silent. Confirm it is accepted on this mpv build, and record the answer in the commit message.

```bash
cd /Users/filip/src/amp
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testExplicitMPVSurfaceGrowthDefersOneReloadAndRespectsPairedOwnership" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|TEST SUCCEEDED|TEST FAILED"
```

Expected: `passed`, which proves an mpv context still initializes after the two init options were removed.

If a later manual run shows `setString video-reversal-buffer failed: property unavailable`, mpv rejected the runtime write. In that case apply the size at context creation instead: keep the `reversalBufferStep` field, and in `setupMPV()` set the option from `ReverseBufferPolicy.ladder[step]` when `reversalBufferStep >= 0`. Do not add that branch pre-emptively — the point of this step is to find out which path this mpv build takes.

- [ ] **Step 9: Run the suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case '.*' failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 10: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/ReverseBufferPolicy.swift" \
        "Aagedal Media Player Tests/ReverseBufferPolicyTests.swift" \
        "Aagedal Media Player/Logic/MPV/MPVProperty.swift" \
        "Aagedal Media Player/Logic/MPV/MPVPlayer.swift"
git commit -m "Raise the reverse-decode buffer only when mpv asks for it

Every player set a 4 GiB reversal buffer up front for a feature most
sessions never use, and mpv documents the option as a remedy for reversal
queue overflow rather than a default. Start at mpv's own value and climb a
1/2/4 GiB ladder one step per reported overflow, stopping at the top."
```

Report the Step 8 finding — whether this mpv build accepted the runtime write, or whether the context-creation branch was needed — in the task's completion summary. Do not encode it in the commit message: the message states the change, and the finding is an execution detail.

---

### Task 7: One HDR state transition, not two

HDR state is applied in two places with different teardown. `updateTransferFunction()` (`PlayerController.swift:305-335`) uses `stopCapture(rebuildPipeline: false)` and a comment at `:329-330` explains that a full rebuild resets `transferFunction`. The gamma sink (`PlayerController.swift:695-721`) uses a full `stopCapture()` and `startCapture()`. Two behaviours, one truth.

The decision itself is duplicated too: both map a colour-transfer string to a transfer function and a peak. Extract it once.

**Files:**
- Create: `Aagedal Media Player/Logic/Scopes/HDRTransferResolver.swift`
- Create: `Aagedal Media Player Tests/HDRTransferResolverTests.swift`
- Modify: `Aagedal Media Player/Logic/PlayerController.swift` (`updateTransferFunction`, the gamma sink)

**Interfaces:**
- Produces: `HDRTransferResolver` — `nonisolated enum` with `static func resolve(colorTransfer: String?) -> TransferFunction`.
- Consumes: `TransferFunction` from `ScopeComputer.swift:12`.
- Note: `contentPeakNits` is deliberately **not** part of this type. Peak selection depends on metadata the resolver must not know about, and it is already centralized in `peakNitsFromMetadata` and `snappedPeakNits`.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/HDRTransferResolverTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class HDRTransferResolverTests: XCTestCase {
    /// The three spellings mpv and SwiftMediaMetadata use for PQ.
    func testPqSpellings() {
        for value in ["smpte2084", "PQ", "st2084", "smpte2084 (PQ)"] {
            XCTAssertEqual(HDRTransferResolver.resolve(colorTransfer: value), .pq, value)
        }
    }

    func testHlgSpelling() {
        for value in ["arib-std-b67", "HLG", "arib-std-b67 (HLG)"] {
            XCTAssertEqual(HDRTransferResolver.resolve(colorTransfer: value), .hlg, value)
        }
    }

    /// SDR transfers, and anything unrecognised, must resolve to SDR rather
    /// than guessing HDR and clipping the picture.
    func testSdrAndUnknownResolveToSdr() {
        for value in ["bt709", "bt1886", "gamma28", "", "something-new"] {
            XCTAssertEqual(HDRTransferResolver.resolve(colorTransfer: value), .sdr, value)
        }
    }

    /// The metadata path passes nil when a file has no video stream.
    func testNilResolvesToSdr() {
        XCTAssertEqual(HDRTransferResolver.resolve(colorTransfer: nil), .sdr)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/HDRTransferResolverTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: compile error, `cannot find 'HDRTransferResolver' in scope`.

- [ ] **Step 3: Write the resolver**

Create `Aagedal Media Player/Logic/Scopes/HDRTransferResolver.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Maps a container's colour-transfer label to the transfer function the scope
/// pipeline must use.
///
/// Two callers need this and used to carry their own copy: the metadata path
/// and mpv's `video-params/gamma`. Anything not recognised resolves to SDR, so
/// an unfamiliar label cannot silently push HDR scaling onto SDR content.
nonisolated enum HDRTransferResolver {
    static func resolve(colorTransfer: String?) -> TransferFunction {
        guard let colorTransfer = colorTransfer?.lowercased(), !colorTransfer.isEmpty else {
            return .sdr
        }
        if colorTransfer.contains("smpte2084")
            || colorTransfer.contains("st2084")
            || colorTransfer == "pq" {
            return .pq
        }
        if colorTransfer.contains("arib-std-b67") || colorTransfer == "hlg" {
            return .hlg
        }
        return .sdr
    }
}
```

- [ ] **Step 4: Run the resolver's tests**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/HDRTransferResolverTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: four `passed` lines and `TEST SUCCEEDED`.

- [ ] **Step 5: Add the single transition**

In `PlayerController.swift`, add above `updateTransferFunction()`:

```swift
    /// Applies one HDR state and rebuilds the capture pipeline if it is live.
    ///
    /// Both the metadata path and mpv's gamma report funnel through here so
    /// there is one teardown behaviour. `rebuildPipeline: false` matters: a
    /// full rebuild resets `transferFunction`, so the state being applied here
    /// would be thrown away by the restart it triggered.
    private func applyHDRState(transferFunction: TransferFunction, peakNits: Float) {
        frameCapture.transferFunction = transferFunction
        frameCapture.contentPeakNits = peakNits
        if frameCapture.isCapturing {
            frameCapture.stopCapture(rebuildPipeline: false)
            frameCapture.startCapture()
        }
    }
```

- [ ] **Step 6: Route the metadata path through it**

Replace the body of `updateTransferFunction()` — everything from `let videoStream = ...` to the closing brace — with:

```swift
        let videoStream = mediaItem?.metadata?.primaryVideoStream
        let transfer = HDRTransferResolver.resolve(colorTransfer: videoStream?.colorTransfer)

        guard transfer != .sdr else {
            applyHDRState(transferFunction: .sdr, peakNits: 100)
            return
        }

        let peak = peakNitsFromMetadata(videoStream, fallback: 1000)
        applyHDRState(transferFunction: transfer, peakNits: peak)
        logger.info("HDR detected: \(String(describing: transfer), privacy: .public) transfer function, peak \(peak) nits")
```

- [ ] **Step 7: Route the gamma sink through it**

In the `mpvGammaCancellable` sink, replace everything from `let wasCapturing = self.frameCapture.isCapturing` to the end of the sink closure's body — that is, the `switch gamma` block plus the `if wasCapturing` block — with:

```swift
                let videoStream = self.mediaItem?.metadata?.primaryVideoStream
                let transfer = HDRTransferResolver.resolve(colorTransfer: gamma)
                if transfer == .sdr {
                    self.applyHDRState(transferFunction: .sdr, peakNits: 100)
                } else {
                    self.applyHDRState(
                        transferFunction: transfer,
                        peakNits: self.peakNitsFromMetadata(videoStream, fallback: 1000)
                    )
                }
```

The `wasCapturing` local is no longer needed; `applyHDRState` performs the same check internally.

- [ ] **Step 8: Run the suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case '.*' failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: `TEST SUCCEEDED`. `hdr10.mp4` exists in `Test Fixtures/Generated/`, and the scope tests in `CompareLiveBackendTests` exercise the capture path with it.

- [ ] **Step 9: Commit**

```bash
git add "Aagedal Media Player/Logic/Scopes/HDRTransferResolver.swift" \
        "Aagedal Media Player Tests/HDRTransferResolverTests.swift" \
        "Aagedal Media Player/Logic/PlayerController.swift"
git commit -m "Apply HDR state through one transition

The metadata path and mpv's gamma report each had their own copy of the
transfer-function decision, and they tore the capture pipeline down
differently: one suppressed the rebuild that resets transferFunction, the
other did not. Both now resolve through one value type and apply through
one method."
```

---

### Task 8: Refresh tracks when mpv says the file loaded

`PlayerController.swift:743-751` waits a fixed 0.5 s after starting MPV playback before refreshing audio tracks and chapters. mpv already emits `MPV_EVENT_FILE_LOADED` at exactly the right moment, and `MPVPlayer.swift:836` already handles it by publishing `isFileLoaded`, which `mpvFileLoadedTask` (`PlayerController.swift:588-608`) already observes.

**Files:**
- Modify: `Aagedal Media Player/Logic/PlayerController.swift` (`mpvFileLoadedTask`, the `asyncAfter` block)
- Create: `Aagedal Media Player Tests/TrackRefreshTimingTests.swift`

**Interfaces:**
- Consumes: `refreshAudioTrackOptions(playerItem:)` and `refreshChapterOptions(playerItem:)`, both already present at `PlayerController.swift:1325` and `:1492`.
- Produces: nothing later tasks call.

- [ ] **Step 1: Write the failing test**

The discriminator is timing: the current code cannot refresh before 500 ms, and the fixed version can. The test asserts the refresh completes well inside that window.

Create `Aagedal Media Player Tests/TrackRefreshTimingTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class TrackRefreshTimingTests: XCTestCase {
    /// The multichannel fixture carries a real audio track list. A fixed
    /// 0.5 s wait cannot satisfy this budget, so the test fails against the
    /// old implementation and passes against the event-driven one.
    func testTrackOptionsArriveWithTheFileLoadedSignal() async throws {
        let url = try fixtureDirectory().appending(path: "multichannel-5.1.m4a")
        let controller = PlayerController()
        let item = PlayerWindowCoordinator.makeMediaItem(for: url)
        controller.loadMedia(item)
        defer { controller.teardown() }

        let arrived = await waitUntil(timeout: 0.3) {
            !controller.audioTrackOptions.isEmpty
        }
        XCTAssertTrue(
            arrived,
            "Audio track options must follow MPV_EVENT_FILE_LOADED, not a 0.5 s timer"
        )
    }

    /// Same resolution order the existing fixture-backed suites use: an
    /// explicit override first, then the generated directory beside the
    /// repository. A missing manifest skips rather than failing.
    private func fixtureDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = repository.appending(path: "Test Fixtures/Generated", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: url.appending(path: "MANIFEST.txt").path) else {
            throw XCTSkip(
                "Generated media fixtures are unavailable. Run scripts/generate-test-fixtures.sh " +
                "or set MEDIA_FIXTURE_DIR."
            )
        }
        return url
    }

    /// Polls the main actor until `condition` holds or the budget expires.
    private func waitUntil(
        timeout: TimeInterval,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/TrackRefreshTimingTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAIL — `Audio track options must follow MPV_EVENT_FILE_LOADED, not a 0.5 s timer`. If `loadMedia` requires a signature this test did not use, read `PlayerController.loadMedia` and match it exactly; do not substitute a different entry point.

- [ ] **Step 3: Move the refresh onto the loaded signal**

In `mpvFileLoadedTask`, the `if isLoaded` branch currently reads:

```swift
                if isLoaded {
                    guard self.playbackFailure == nil else { break }
                    self.markPlaybackReady(isBuffering: mpv.isBusy)
                    break
                }
```

Replace it with:

```swift
                if isLoaded {
                    guard self.playbackFailure == nil else { break }
                    // mpv has the demuxer open and the track and chapter lists
                    // populated here, which is the signal the fixed 0.5 s wait
                    // was standing in for.
                    self.refreshAudioTrackOptions(playerItem: nil)
                    self.refreshChapterOptions(playerItem: nil)
                    self.markPlaybackReady(isBuffering: mpv.isBusy)
                    break
                }
```

- [ ] **Step 4: Remove the fixed wait**

Delete this block from the end of `setupMPVObservations`, immediately before `installMPVLoopObserver()`:

```swift
        // Refresh audio tracks after MPV parses the media
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak mpv] in
            guard let self, mpv != nil,
                  observationIdentity.matches(
                      preparationID: self.preparationID,
                      player: self.mpvPlayer
                  ) else { return }
            self.refreshAudioTrackOptions(playerItem: nil)
            self.refreshChapterOptions(playerItem: nil)
        }
```

The observation-identity check it performed is redundant in the new location: `mpvFileLoadedTask` already guards on `observationIdentity.matches(...)` before reaching the branch.

- [ ] **Step 5: Run the timing test**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/TrackRefreshTimingTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `passed` and `TEST SUCCEEDED`.

- [ ] **Step 6: Run the suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case '.*' failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: `TEST SUCCEEDED`. This is the regression guard for the track-list and chapter-list suites.

- [ ] **Step 7: Commit**

```bash
git add "Aagedal Media Player/Logic/PlayerController.swift" \
        "Aagedal Media Player Tests/TrackRefreshTimingTests.swift"
git commit -m "Refresh tracks when mpv reports the file loaded

A fixed 0.5 s wait stood in for knowing when the demuxer had opened. mpv
already emits MPV_EVENT_FILE_LOADED, and the controller already observes
the isFileLoaded it publishes, so the track and chapter lists can be
refreshed at the moment they exist rather than half a second later."
```

---

### Task 9: Remove the data race on the HDR log gate

`FrameCapture.swift:147` declares `private nonisolated(unsafe) static var hdrFormatLogged = false`. It is read and written at `:630-631` from `screenshotAndDownsampleHDR`, a `nonisolated private static ... async` function, and reset on the main actor at `:247`. Two threads can pass the check and both log, and the unsynchronized access is undefined behaviour under Swift's memory model regardless of the benign outcome.

**Files:**
- Create: `Aagedal Media Player/Logic/Scopes/OneShotFlag.swift`
- Create: `Aagedal Media Player Tests/OneShotFlagTests.swift`
- Modify: `Aagedal Media Player/Logic/Scopes/FrameCapture.swift` (import, declaration, use, reset)

**Interfaces:**
- Produces: `OneShotFlag` — `final class`, `Sendable`, with `func claim() -> Bool`. Returns `true` exactly once per `reset()`.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/OneShotFlagTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class OneShotFlagTests: XCTestCase {
    func testFirstClaimWins() {
        let flag = OneShotFlag()
        XCTAssertTrue(flag.claim())
        XCTAssertFalse(flag.claim())
    }

    func testResetAllowsOneMoreClaim() {
        let flag = OneShotFlag()
        XCTAssertTrue(flag.claim())
        flag.reset()
        XCTAssertTrue(flag.claim())
        XCTAssertFalse(flag.claim())
    }

    /// Exactly one claimant must win, however hard the callers race.
    func testExactlyOneConcurrentClaimWins() async {
        for _ in 0..<50 {
            let flag = OneShotFlag()
            let winners = await withTaskGroup(of: Bool.self) { group -> Int in
                for _ in 0..<64 {
                    group.addTask { flag.claim() }
                }
                var count = 0
                for await won in group where won { count += 1 }
                return count
            }
            XCTAssertEqual(winners, 1, "a race let more than one claim through")
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/OneShotFlagTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: compile error, `cannot find 'OneShotFlag' in scope`.

- [ ] **Step 3: Write the flag**

Create `Aagedal Media Player/Logic/Scopes/OneShotFlag.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os

/// A claim-once gate that is safe to touch from any thread.
///
/// Used for one-shot diagnostics, where the point is that the work happens
/// exactly once no matter how many callers race for it. `OSAllocatedUnfairLock`
/// carries the state rather than a bare `static var`, which had no
/// synchronization at all.
final class OneShotFlag: @unchecked Sendable {
    private let claimed = OSAllocatedUnfairLock(initialState: false)

    /// Returns `true` to exactly one caller per reset, `false` to the rest.
    func claim() -> Bool {
        claimed.withLock { alreadyClaimed in
            guard !alreadyClaimed else { return false }
            alreadyClaimed = true
            return true
        }
    }

    func reset() {
        claimed.withLock { $0 = false }
    }
}
```

- [ ] **Step 4: Run the flag's tests**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/OneShotFlagTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case|error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: three `passed` lines and `TEST SUCCEEDED`.

- [ ] **Step 5: Replace the racy static**

In `FrameCapture.swift`, replace the declaration at `:147`:

```swift
    private nonisolated(unsafe) static var hdrFormatLogged = false
```

with:

```swift
    private static let hdrFormatLogged = OneShotFlag()
```

- [ ] **Step 6: Use the gate**

In `screenshotAndDownsampleHDR`, replace:

```swift
        // One-shot diagnostic: log format and sample pixel values on first HDR capture
        if !Self.hdrFormatLogged {
            Self.hdrFormatLogged = true
```

with:

```swift
        // One-shot diagnostic: log format and sample pixel values on first HDR capture
        if Self.hdrFormatLogged.claim() {
```

- [ ] **Step 7: Reset through the flag**

At `FrameCapture.swift:247`, find the main-actor reset of the old static, which currently assigns `Self.hdrFormatLogged = false` — search for `hdrFormatLogged` to locate it, since it sits inside a capture-restart path — and replace the assignment with:

```swift
            Self.hdrFormatLogged.reset()
```

- [ ] **Step 8: Run the suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case '.*' failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 9: Commit**

```bash
git add "Aagedal Media Player/Logic/Scopes/OneShotFlag.swift" \
        "Aagedal Media Player Tests/OneShotFlagTests.swift" \
        "Aagedal Media Player/Logic/Scopes/FrameCapture.swift"
git commit -m "Synchronize the HDR log gate

The one-shot diagnostic flag was a nonisolated(unsafe) static var written
from an off-actor capture path and cleared on the main actor, so two
captures could both log and the access had no ordering at all. A
lock-backed claim-once gate makes the guarantee the comment already
claimed."
```

---

## Verification

After every task is committed, run the whole suite once from a clean build directory and confirm the branch is clean.

```bash
cd /Users/filip/src/amp
git status --short
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Test case '.*' failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: `git status --short` prints nothing, and the suite ends `TEST SUCCEEDED` with four suites newly reported as skipped rather than passed.

Then confirm each fix is actually present, rather than trusting the plan:

```bash
rg -n 'queue\.sync' "Aagedal Media Player/Logic/MPV/MPVPlayer.swift"
rg -n 'nonisolated\(unsafe\) static var' "Aagedal Media Player/Logic/Scopes/FrameCapture.swift"
rg -n 'asyncAfter' "Aagedal Media Player/Logic/PlayerController.swift"
rg -n 'video-reversal-buffer' "Aagedal Media Player/Logic/MPV/MPVPlayer.swift"
rg -n 'hwdec-current' "Aagedal Media Player/Logic/MPV/"
```

Expected: the first two print nothing. The third prints nothing for the 0.5 s track-refresh wait; if `asyncAfter` survives elsewhere, read each remaining site and confirm it is not a substitute for an event. The fourth prints only `MPVProperty.videoReversalBuffer` and the `raiseReversalBuffer` call, with no `mpv_set_option_string` for it in `setupMPV()`. The fifth prints the constant and the observation registration.
