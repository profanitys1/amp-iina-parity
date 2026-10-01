# Plan 2: Colour pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app colour-correct on the display it is actually on: honour the display's ICC profile for SDR, enable EDR only for genuine HDR content, and tell mpv the display's real peak brightness.

**Architecture:** A single `DisplayColorController` owns the policy. It observes screen changes and mpv's video colour parameters, decides SDR-vs-HDR, and applies the decision to both the `CAMetalLayer` and mpv. `MPVVideoView` already observes window/screen notifications and owns both objects, so it hosts the controller.

**Tech Stack:** Swift 6, AppKit, CoreGraphics, ColorSync, mpv (`vo=gpu-next`, `gpu-api=vulkan`, `gpu-context=moltenvk`).

## Global Constraints

- Deployment target macOS 15.0, Swift 6 strict concurrency.
- Build/test with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`.
- Metal API Validation stays OFF in the scheme.
- SPDX header on every file; `OSLog` subsystem `com.aagedal.MediaPlayer`.
- Commit messages carry no attribution lines.
- **This app embeds mpv with `wid=`, not the render API.** There is no render context, so `MPV_RENDER_PARAM_ICC_PROFILE` — the mechanism IINA uses — is unavailable. `icc-profile-auto` depends on that parameter and will not work here. The profile must be written to a file and passed as `icc-profile=<path>`.
- Do not remove `target-colorspace-hint=yes` (`MPVPlayer.swift:271`). It is what signals the swapchain colour space under Vulkan/MoltenVK and has no IINA equivalent.


## Status (2026-10-01): all five tasks landed on `main`

Commits `259c936`, `c9d4a5b`, `3503760`, `1d14391` and `f7279f3`. Full suite: 684 passed, 5 skipped, 0 failed.

Verified on device with the `colour` log category:
- an SDR clip logs `EDR=false prim=auto trc=auto`;
- a PQ/BT.2020 clip logs `EDR=true prim=bt.2020 trc=pq` once mpv reports the parameters, and renders.

Two deliberate differences from the task text:
- `DisplayColorState.decide` reuses `HDRTransferResolver` instead of comparing `"pq"`/`"hlg"` itself.
- `screenshot-tag-colorspace` is left at mpv's default (`yes`). The plan turned it off for SDR, which would have stripped the colour tag from SDR screenshots. The `tagsScreenshotColorspace` field was therefore dropped.

The three new settings (`hdrEnabled`, `loadDisplayICCProfile`, `toneMappingTargetPeakOverride`) have no UI yet; Plan 1 surfaces them.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Logic/MPV/DisplayColorState.swift` | **New.** Pure value type: given video primaries/gamma and display capability, decide SDR or HDR and what to set. No AppKit, no mpv — fully testable. |
| `Logic/MPV/DisplayColorController.swift` | **New.** Applies a `DisplayColorState` to an `MPVMetalLayer` and an `MPVPlayer`; owns the exported ICC file. |
| `Logic/MPV/MPVMetalLayer.swift` | Modified. Stops forcing EDR on; gains `apply(_:)`. |
| `Logic/MPV/MPVPlayer.swift` | Modified. Exposes `getString`/`getDouble` so colour params can be read. |
| `Logic/MPV/MPVVideoView.swift` | Modified. Owns the controller, refreshes on screen change and on colour-space change. |
| `Logic/AppSettings.swift` | Modified. Three new settings. |

---

### Task 1: The decision, as a pure value type

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/DisplayColorState.swift`
- Test: `Aagedal Media Player Tests/DisplayColorStateTests.swift`

**Interfaces:**
- Produces, used by Tasks 2-4:
  ```swift
  nonisolated enum VideoTransfer: String { case pq, hlg, sdr }
  nonisolated struct DisplayColorState: Equatable {
      var usesEDR: Bool
      var targetPrimaries: String?   // nil means "auto"
      var targetTransfer: String?    // nil means "auto"
      var tagsScreenshotColorspace: Bool
      static func decide(primaries: String?, gamma: String?,
                         displaySupportsEDR: Bool, hdrEnabled: Bool) -> DisplayColorState
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/DisplayColorStateTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class DisplayColorStateTests: XCTestCase {
    func testBT709IsSDR() {
        let state = DisplayColorState.decide(primaries: "bt.709", gamma: "bt.1886",
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertFalse(state.usesEDR)
        XCTAssertNil(state.targetPrimaries)
        XCTAssertNil(state.targetTransfer)
        XCTAssertFalse(state.tagsScreenshotColorspace)
    }

    /// PQ or HLG with wide primaries is the only thing that counts as HDR.
    func testPQBT2020IsHDR() {
        let state = DisplayColorState.decide(primaries: "bt.2020", gamma: "pq",
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertTrue(state.usesEDR)
        XCTAssertEqual(state.targetPrimaries, "bt.2020")
        XCTAssertEqual(state.targetTransfer, "pq")
        XCTAssertTrue(state.tagsScreenshotColorspace)
    }

    /// HLG is converted to PQ for display, as IINA does.
    func testHLGIsConvertedToPQ() {
        let state = DisplayColorState.decide(primaries: "display-p3", gamma: "hlg",
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertTrue(state.usesEDR)
        XCTAssertEqual(state.targetTransfer, "pq")
        XCTAssertEqual(state.targetPrimaries, "display-p3")
    }

    func testHDRContentOnSDRDisplayFallsBackToSDR() {
        let state = DisplayColorState.decide(primaries: "bt.2020", gamma: "pq",
                                             displaySupportsEDR: false, hdrEnabled: true)
        XCTAssertFalse(state.usesEDR)
    }

    func testHDRDisabledByUserFallsBackToSDR() {
        let state = DisplayColorState.decide(primaries: "bt.2020", gamma: "pq",
                                             displaySupportsEDR: true, hdrEnabled: false)
        XCTAssertFalse(state.usesEDR)
    }

    /// Missing parameters must not be guessed at.
    func testUnknownParametersAreSDR() {
        let state = DisplayColorState.decide(primaries: nil, gamma: nil,
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertFalse(state.usesEDR)
    }

    /// An unrecognised primaries value with an HDR transfer is not assumed HDR.
    func testUnsupportedPrimariesIsSDR() {
        let state = DisplayColorState.decide(primaries: "smpte-431", gamma: "pq",
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertFalse(state.usesEDR)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/DisplayColorStateTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'DisplayColorState' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/MPV/DisplayColorState.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Decides how the picture should be shown on the display it is on.
//
// The HDR test matches IINA's isHDRVideo() (VideoView.swift:437-460): an HDR
// transfer function AND primaries wide enough to mean it. Anything else is SDR,
// including unknown values — a review tool must not guess at colour.

import Foundation

nonisolated struct DisplayColorState: Equatable {
    /// Whether the layer should accept extended-range content.
    var usesEDR: Bool
    /// mpv `target-prim`, or nil for "auto".
    var targetPrimaries: String?
    /// mpv `target-trc`, or nil for "auto".
    var targetTransfer: String?
    /// mpv `screenshot-tag-colorspace`.
    var tagsScreenshotColorspace: Bool

    static let sdr = DisplayColorState(usesEDR: false, targetPrimaries: nil,
                                       targetTransfer: nil, tagsScreenshotColorspace: false)

    static func decide(
        primaries: String?,
        gamma: String?,
        displaySupportsEDR: Bool,
        hdrEnabled: Bool
    ) -> DisplayColorState {
        guard hdrEnabled, displaySupportsEDR,
              let primaries, let gamma,
              gamma == "pq" || gamma == "hlg",
              primaries == "bt.2020" || primaries == "display-p3" else {
            return .sdr
        }
        // PQ is shown as authored; HLG is converted to PQ for display.
        return DisplayColorState(usesEDR: true,
                                 targetPrimaries: primaries,
                                 targetTransfer: "pq",
                                 tagsScreenshotColorspace: true)
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/DisplayColorStateTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/DisplayColorState.swift" \
        "Aagedal Media Player Tests/DisplayColorStateTests.swift"
git commit -m "Decide SDR or HDR from the video's colour parameters

An HDR transfer function alone is not enough; the primaries have to be wide
too, and an unknown value is treated as SDR rather than guessed at."
```

---

### Task 2: Display peak brightness

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/DisplayPeakBrightness.swift`
- Test: `Aagedal Media Player Tests/DisplayPeakBrightnessTests.swift`

**Interfaces:**
- Produces, used by Task 4:
  `DisplayPeakBrightness.nits(forHeadroom: CGFloat, referenceWhite: CGFloat) -> Int?`
  and `DisplayPeakBrightness.nits(for screen: NSScreen) -> Int?`.

**Why this exists:** mpv cannot query display brightness on macOS, so `target-peak=auto`
falls back to a transfer-function guess. IINA reads the private
`CoreDisplay_DisplayCreateInfoDictionary` (`iina-Bridging-Header.h:27`) for
`NonReferencePeakHDRLuminance` / `DisplayBacklight`. This plan uses the public
`NSScreen` EDR headroom instead, which needs no private API:
peak ≈ headroom × SDR reference white (100 nits by convention).

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/DisplayPeakBrightnessTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class DisplayPeakBrightnessTests: XCTestCase {
    /// A 10x headroom display at the 100-nit SDR reference is a 1000-nit panel.
    func testHeadroomScalesReferenceWhite() {
        XCTAssertEqual(DisplayPeakBrightness.nits(forHeadroom: 10, referenceWhite: 100), 1000)
    }

    /// No headroom means no EDR, so there is nothing to report.
    func testNoHeadroomReturnsNil() {
        XCTAssertNil(DisplayPeakBrightness.nits(forHeadroom: 1, referenceWhite: 100))
    }

    func testBelowUnityHeadroomReturnsNil() {
        XCTAssertNil(DisplayPeakBrightness.nits(forHeadroom: 0.5, referenceWhite: 100))
    }

    func testFractionalHeadroomRounds() {
        XCTAssertEqual(DisplayPeakBrightness.nits(forHeadroom: 1.6, referenceWhite: 100), 160)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/DisplayPeakBrightnessTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'DisplayPeakBrightness' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/MPV/DisplayPeakBrightness.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// mpv has no way to ask macOS how bright the display gets, so target-peak=auto
// falls back to a guess from the transfer function. IINA reads the private
// CoreDisplay_DisplayCreateInfoDictionary for NonReferencePeakHDRLuminance.
// The public EDR headroom gets the same answer without private API: headroom is
// a multiple of SDR reference white, which is 100 nits by convention.

import AppKit

nonisolated enum DisplayPeakBrightness {
    static let sdrReferenceWhiteNits: CGFloat = 100

    static func nits(forHeadroom headroom: CGFloat, referenceWhite: CGFloat) -> Int? {
        guard headroom > 1, headroom.isFinite else { return nil }
        return Int((headroom * referenceWhite).rounded())
    }

    @MainActor
    static func nits(for screen: NSScreen) -> Int? {
        nits(forHeadroom: screen.maximumPotentialExtendedDynamicRangeColorComponentValue,
             referenceWhite: sdrReferenceWhiteNits)
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/DisplayPeakBrightnessTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/DisplayPeakBrightness.swift" \
        "Aagedal Media Player Tests/DisplayPeakBrightnessTests.swift"
git commit -m "Derive display peak brightness from EDR headroom

mpv cannot query display brightness on macOS. Headroom is a multiple of SDR
reference white, so it yields the panel's peak without the private CoreDisplay
API the reference implementation uses."
```

---

### Task 3: Export the display's ICC profile to a file

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/DisplayICCProfileStore.swift`
- Test: `Aagedal Media Player Tests/DisplayICCProfileStoreTests.swift`

**Interfaces:**
- Produces, used by Task 4: `DisplayICCProfileStore.url(for data: Data) throws -> URL`.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/DisplayICCProfileStoreTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class DisplayICCProfileStoreTests: XCTestCase {
    private var store: DisplayICCProfileStore!

    override func setUp() {
        super.setUp()
        store = DisplayICCProfileStore(
            directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.directory)
        store = nil
        super.tearDown()
    }

    func testWritesProfileAndReturnsReadableURL() throws {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        let url = try store.url(for: data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    /// The same profile must not be rewritten — this runs on every screen change.
    func testSameProfileReusesTheSameFile() throws {
        let data = Data([0x0A, 0x0B])
        let first = try store.url(for: data)
        let second = try store.url(for: data)
        XCTAssertEqual(first, second)
    }

    func testDifferentProfilesGetDifferentFiles() throws {
        let first = try store.url(for: Data([0x01]))
        let second = try store.url(for: Data([0x02]))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data([0x01]))
        XCTAssertEqual(try Data(contentsOf: second), Data([0x02]))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/DisplayICCProfileStoreTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'DisplayICCProfileStore' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/MPV/DisplayICCProfileStore.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// mpv's icc-profile-auto only works through MPV_RENDER_PARAM_ICC_PROFILE, which
// needs a render context. This app embeds mpv with wid=, so there is no render
// context and no way to hand mpv a profile in memory. Writing the display's
// profile to a file and pointing icc-profile at it is the route that works.

import CryptoKit
import Foundation

struct DisplayICCProfileStore {
    let directory: URL

    init(directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("com.aagedal.MediaPlayer/ICCProfiles", isDirectory: true)) {
        self.directory = directory
    }

    /// Writes the profile if it is not already on disk, and returns its path.
    /// Named by content hash so an unchanged profile is written once.
    func url(for data: Data) throws -> URL {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let target = directory.appendingPathComponent("\(digest).icc")
        guard !FileManager.default.fileExists(atPath: target.path) else { return target }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return target
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/DisplayICCProfileStoreTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/DisplayICCProfileStore.swift" \
        "Aagedal Media Player Tests/DisplayICCProfileStoreTests.swift"
git commit -m "Write the display's ICC profile where mpv can read it

icc-profile-auto needs a render context this app does not have, so the profile
goes to a content-addressed file and mpv is pointed at it instead."
```

---

### Task 4: Apply the decision to the layer and to mpv

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/DisplayColorController.swift`
- Modify: `Aagedal Media Player/Logic/MPV/MPVMetalLayer.swift`
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` (raise `getString`/`getDouble` to internal)
- Modify: `Aagedal Media Player/Logic/AppSettings.swift`
- Test: `Aagedal Media Player Tests/MPVMetalLayerColorTests.swift`

**Interfaces:**
- Consumes: `DisplayColorState.decide(...)`, `DisplayPeakBrightness.nits(for:)`,
  `DisplayICCProfileStore.url(for:)`, `MPVPlayer.setString(_:_:)`.
- Produces, used by Task 5: `DisplayColorController.refresh(screen:)`, and its
  initialiser `init(player: MPVPlayer, layer: MPVMetalLayer)`.
- Produces settings, surfaced by Plan 1: `AppSettings.hdrEnabled` (Bool, true),
  `loadDisplayICCProfile` (Bool, true), `toneMappingTargetPeakOverride` (Int, 0 = auto).

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/MPVMetalLayerColorTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import CoreGraphics
@testable import Aagedal_Media_Player

final class MPVMetalLayerColorTests: XCTestCase {
    /// SDR content must not sit in an EDR-flagged layer. This was the bug: the
    /// layer forced wantsExtendedDynamicRangeContent on for everything.
    func testSDRStateTurnsEDROffAndSetsDisplayColorSpace() {
        let layer = MPVMetalLayer()
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        layer.apply(.sdr, sdrColorSpace: sRGB)
        XCTAssertFalse(layer.wantsExtendedDynamicRangeContent)
        XCTAssertEqual(layer.colorspace, sRGB)
    }

    func testHDRStateTurnsEDROnAndUsesPQColorSpace() {
        let layer = MPVMetalLayer()
        let state = DisplayColorState(usesEDR: true, targetPrimaries: "bt.2020",
                                      targetTransfer: "pq", tagsScreenshotColorspace: true)
        layer.apply(state, sdrColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        XCTAssertTrue(layer.wantsExtendedDynamicRangeContent)
        XCTAssertEqual(layer.colorspace, CGColorSpace(name: CGColorSpace.itur_2100_PQ))
    }

    func testDisplayP3HDRUsesDisplayP3PQ() {
        let layer = MPVMetalLayer()
        let state = DisplayColorState(usesEDR: true, targetPrimaries: "display-p3",
                                      targetTransfer: "pq", tagsScreenshotColorspace: true)
        layer.apply(state, sdrColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        XCTAssertEqual(layer.colorspace, CGColorSpace(name: CGColorSpace.displayP3_PQ))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVMetalLayerColorTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `value of type 'MPVMetalLayer' has no member 'apply'`.

- [ ] **Step 3: Teach the layer to take a state**

In `Aagedal Media Player/Logic/MPV/MPVMetalLayer.swift`, delete
`configureForHDR()` and its three call sites, and add:

```swift
    /// Applies a colour decision. SDR content gets the display's own colour
    /// space and no EDR; HDR content gets a PQ space and EDR. Forcing EDR on
    /// for everything, as this layer used to, shows SDR material through an
    /// extended-range path it was never graded for.
    nonisolated func apply(_ state: DisplayColorState, sdrColorSpace: CGColorSpace) {
        guard state.usesEDR else {
            colorspace = sdrColorSpace
            wantsExtendedDynamicRangeContent = false
            return
        }
        let name: CFString = state.targetPrimaries == "display-p3"
            ? CGColorSpace.displayP3_PQ
            : CGColorSpace.itur_2100_PQ
        colorspace = CGColorSpace(name: name)
        wantsExtendedDynamicRangeContent = true
    }
```

Add `import CoreGraphics` at the top if it is not already present.

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVMetalLayerColorTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Add the settings**

In `Aagedal Media Player/Logic/AppSettings.swift`, beside the other rendering
settings:

```swift
    static let hdrEnabled = AppSetting(key: "hdrEnabled", defaultValue: true)
    static let loadDisplayICCProfile = AppSetting(key: "loadDisplayICCProfile", defaultValue: true)
    /// 0 means derive the peak from the display's EDR headroom.
    static let toneMappingTargetPeakOverride = AppSetting(key: "toneMappingTargetPeakOverride", defaultValue: 0)
```

Register all three in `registerDefaults(in:)` alongside the existing keys.

- [ ] **Step 6: Expose mpv's colour parameters**

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, change `getString` and
`getDouble` from `private func` to `func` so the controller can read
`video-params/primaries`, `video-params/gamma` and `video-params/sig-peak`.

- [ ] **Step 7: Write the controller**

Create `Aagedal Media Player/Logic/MPV/DisplayColorController.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Keeps the picture correct for the display it is on. Modelled on IINA's
// VideoView.refreshEdrMode (VideoView.swift:415-435), with two differences
// forced by this app embedding mpv via wid= rather than the render API:
// the ICC profile goes to mpv as a file path, and the peak comes from the
// public EDR headroom rather than the private CoreDisplay dictionary.

import AppKit
import OSLog

@MainActor
final class DisplayColorController {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "colour")
    private let profileStore = DisplayICCProfileStore()
    private weak var player: MPVPlayer?
    private weak var layer: MPVMetalLayer?
    private var lastApplied: DisplayColorState?

    init(player: MPVPlayer, layer: MPVMetalLayer) {
        self.player = player
        self.layer = layer
    }

    /// Re-decides and re-applies. Safe to call repeatedly; only changes are pushed.
    func refresh(screen: NSScreen?) {
        guard let player, let layer else { return }
        let defaults = UserDefaults.standard

        let headroom = screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
        let state = DisplayColorState.decide(
            primaries: player.getString(MPVProperty.videoParamsPrimaries),
            gamma: player.getString(MPVProperty.videoParamsGamma),
            displaySupportsEDR: headroom > 1,
            hdrEnabled: defaults.value(for: AppSettings.hdrEnabled))

        let sdrColorSpace = screen?.colorSpace?.cgColorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        layer.apply(state, sdrColorSpace: sdrColorSpace)

        player.setString(MPVProperty.targetPrim, state.targetPrimaries ?? "auto")
        player.setString(MPVProperty.targetTrc, state.targetTransfer ?? "auto")
        player.setString(MPVProperty.screenshotTagColorspace,
                         state.tagsScreenshotColorspace ? "yes" : "no")

        applyICCProfile(for: screen, state: state, player: player, defaults: defaults)
        applyTargetPeak(for: screen, state: state, player: player, defaults: defaults)

        if lastApplied != state {
            logger.info("Colour state: EDR=\(state.usesEDR, privacy: .public) prim=\(state.targetPrimaries ?? "auto", privacy: .public) trc=\(state.targetTransfer ?? "auto", privacy: .public)")
            lastApplied = state
        }
    }

    private func applyICCProfile(
        for screen: NSScreen?,
        state: DisplayColorState,
        player: MPVPlayer,
        defaults: UserDefaults
    ) {
        // An HDR path is already display-referred; a display profile on top of
        // it would double-correct, which is why IINA only sets one or the other.
        guard !state.usesEDR,
              defaults.value(for: AppSettings.loadDisplayICCProfile),
              let data = screen?.colorSpace?.iccProfileData else {
            player.setString(MPVProperty.iccProfile, "")
            return
        }
        do {
            let url = try profileStore.url(for: data)
            player.setString(MPVProperty.iccProfile, url.path)
        } catch {
            logger.error("Could not write the display ICC profile: \(error.localizedDescription, privacy: .public)")
            player.setString(MPVProperty.iccProfile, "")
        }
    }

    private func applyTargetPeak(
        for screen: NSScreen?,
        state: DisplayColorState,
        player: MPVPlayer,
        defaults: UserDefaults
    ) {
        guard state.usesEDR else {
            player.setString(MPVProperty.targetPeak, "auto")
            return
        }
        let override = defaults.value(for: AppSettings.toneMappingTargetPeakOverride)
        if override > 0 {
            player.setString(MPVProperty.targetPeak, String(override))
            return
        }
        if let screen, let nits = DisplayPeakBrightness.nits(for: screen) {
            player.setString(MPVProperty.targetPeak, String(nits))
        } else {
            player.setString(MPVProperty.targetPeak, "auto")
        }
    }
}
```

- [ ] **Step 8: Add the mpv property names**

In `Aagedal Media Player/Logic/MPV/MPVProperty.swift`, beside the existing
`videoParams*` constants:

```swift
    nonisolated static let targetPrim = "target-prim"
    nonisolated static let targetTrc = "target-trc"
    nonisolated static let targetPeak = "target-peak"
    nonisolated static let iccProfile = "icc-profile"
    nonisolated static let screenshotTagColorspace = "screenshot-tag-colorspace"
```

- [ ] **Step 9: Build**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 10: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/DisplayColorController.swift" \
        "Aagedal Media Player/Logic/MPV/MPVMetalLayer.swift" \
        "Aagedal Media Player/Logic/MPV/MPVPlayer.swift" \
        "Aagedal Media Player/Logic/MPV/MPVProperty.swift" \
        "Aagedal Media Player/Logic/AppSettings.swift" \
        "Aagedal Media Player Tests/MPVMetalLayerColorTests.swift"
git commit -m "Show SDR as SDR and HDR as HDR

The Metal layer forced extended dynamic range on for every file and never set
a colour space, so SDR material was shown through an EDR path it was not
graded for. Decide per file and per display instead: SDR gets the display's
own profile, HDR gets a PQ space, EDR and the target peak follow."
```

---

### Task 5: Refresh on every event that can change the answer

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVVideoView.swift`

**Interfaces:**
- Consumes: `DisplayColorController.refresh(screen:)`.

**The four triggers**, matching IINA's call sites (`MPVController.swift:1273`,
`PlayerWindowController.swift:89`/`:261`, `VideoView.swift:271`):
the window moves to another screen; the screen's colour space changes; mpv
reports new video colour parameters; the file finishes loading.

- [ ] **Step 1: Hold a controller**

In `MPVViewController`, beside `metalLayer`:

```swift
    private var colorController: DisplayColorController?
```

At the end of `viewDidLoad()`, after `attachDrawableIfSized()`:

```swift
        colorController = DisplayColorController(player: player, layer: metalLayer)
```

- [ ] **Step 2: Refresh alongside the refresh rate**

`applyDisplayRefreshRate()` already runs on window-screen change, on
screen-parameter change, and on attach. Extend it:

```swift
    private func applyDisplayRefreshRate() {
        guard let screen = view.window?.screen else { return }
        player.applyDisplayRefreshRate(Double(screen.maximumFramesPerSecond))
        colorController?.refresh(screen: screen)
    }
```

- [ ] **Step 3: Observe colour-space changes**

Add beside the other observer properties:

```swift
    nonisolated(unsafe) private var colorSpaceObserver: NSObjectProtocol?
```

Add it to both teardown lists (in `deinit` and in `installWindowObservers`), and
register it next to `didChangeScreenObserver`:

```swift
        colorSpaceObserver = NotificationCenter.default.addObserver(
            forName: NSScreen.colorSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDisplayRefreshRate() }
        }
```

- [ ] **Step 4: Refresh when mpv reports new colour parameters**

`MPVPlayer` already publishes `videoGamma` and `videoSigPeak`. Observe the one
that matters from the view controller, in `viewDidLoad()` after the controller
is created:

```swift
        gammaObservation = player.$videoGamma
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.colorController?.refresh(screen: self.view.window?.screen)
                }
            }
```

with the property, and `import Combine` at the top:

```swift
    private var gammaObservation: AnyCancellable?
```

- [ ] **Step 5: Build and verify on a real file**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
```

Then launch the app, open an SDR file and watch the log:

```bash
log stream --predicate 'subsystem == "com.aagedal.MediaPlayer" AND category == "colour"' --style compact
```

Expected: one `Colour state: EDR=false prim=auto trc=auto` line per file, and a
new line when you drag the window to a display with different capabilities.
Opening an HDR file must log `EDR=true`.

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed [0-9]+ tests|error:|TEST"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVVideoView.swift"
git commit -m "Re-decide colour whenever the answer could change

The window moving to another display, the display's profile changing, and mpv
reporting new colour parameters all change what the right answer is."
```

---

## Known risk to check first

`icc-profile` is a `gpu-next` option and this app runs `vo=gpu-next`, so it
should apply. Verify before building on it:

```bash
mpv --list-options 2>/dev/null | grep -E "icc-profile|target-peak|target-prim|target-trc"
```

If `icc-profile` is absent from the bundled mpv, Tasks 3 and the ICC half of
Task 4 do not apply — keep the EDR/SDR fix and the target-peak work, which do
not depend on it, and report that ICC needs the render API.
