# Plan 3: Hardware decode probing and a video filter chain

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop assuming VideoToolbox can decode everything, and give the app a real video-filter chain instead of one hardcoded flip.

**Architecture:** A `HardwareDecodeCapabilities` cache answers "can this Mac hardware-decode this codec" off the main thread, and narrows mpv's `hwdec-codecs` whitelist at startup. Separately, a small `MPVVideoFilter` value type plus a labelled add/remove chain replaces the single `vf=lavfi=[vflip]` option, following the pattern `applyAudioChannelRouting` already uses for `af`.

**Tech Stack:** Swift 6, VideoToolbox, CoreMedia, mpv.

## Global Constraints

- Deployment target macOS 15.0, Swift 6 strict concurrency.
- Build/test with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`.
- SPDX header on every file; `OSLog` subsystem `com.aagedal.MediaPlayer`; no attribution lines in commits.
- **`MPVPlayer.command(_:args:)` is `private`.** Anything issuing mpv commands must live inside `MPVPlayer.swift`, as `applyAudioChannelRouting` and `setRenderProfile` already do. `setString` is internal and callable from outside.
- **Do not break the reflection path.** `correctsReflection` couples two decisions: it forces `hwdec` from `videotoolbox` to `videotoolbox-copy` *and* installs `vf=lavfi=[vflip]`. The copy-back variant is required because a `vf` chain cannot operate on an opaque VideoToolbox surface. Any change that lets a filter be added at runtime must also force copy-back, or the picture goes black.
- ProRes RAW never reaches mpv — `PlayerController` routes it to AVPlayer. Do not add ProRes RAW to any mpv codec list.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Logic/MPV/HardwareDecodeCapabilities.swift` | **New.** Async VideoToolbox probe, cached. Ported from IINA. |
| `Logic/MPV/MPVCodecWhitelist.swift` | **New.** Pure: narrow a comma-separated `hwdec-codecs` list given a support predicate. |
| `Logic/MPV/MPVVideoFilter.swift` | **New.** Value type rendering an mpv filter string. |
| `Logic/MPV/MPVPlayer.swift` | Modified. Probes codecs at init; owns the labelled filter chain. |
| `Logic/AppSettings.swift` | Modified. `hardwareDecoder` setting. |

---

### Task 1: Narrowing the codec whitelist, as a pure function

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/MPVCodecWhitelist.swift`
- Test: `Aagedal Media Player Tests/MPVCodecWhitelistTests.swift`

**Interfaces:**
- Produces, used by Task 3:
  ```swift
  nonisolated enum MPVCodecWhitelist {
      static func narrowed(_ whitelist: String,
                           isSupported: (String) -> Bool?) -> String?
  }
  ```
  Returns `nil` when nothing needs removing, so the caller can skip the write.
  The predicate returns `nil` for a codec this app does not know how to check,
  which is retained untouched.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/MPVCodecWhitelistTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class MPVCodecWhitelistTests: XCTestCase {
    func testUnsupportedCodecIsRemoved() {
        let result = MPVCodecWhitelist.narrowed("h264,av1,vp9") { codec in
            codec == "av1" ? false : true
        }
        XCTAssertEqual(result, "h264,vp9")
    }

    /// No change means no write, so mpv is not told something it already knows.
    func testEverythingSupportedReturnsNil() {
        let result = MPVCodecWhitelist.narrowed("h264,av1") { _ in true }
        XCTAssertNil(result)
    }

    /// A codec this app cannot check must be left alone, not dropped.
    func testUnknownCodecIsRetained() {
        let result = MPVCodecWhitelist.narrowed("h264,av1,theora") { codec in
            codec == "theora" ? nil : (codec == "av1" ? false : true)
        }
        XCTAssertEqual(result, "h264,theora")
    }

    func testAllUnsupportedYieldsEmptyString() {
        let result = MPVCodecWhitelist.narrowed("av1,vp9") { _ in false }
        XCTAssertEqual(result, "")
    }

    func testWhitespaceAroundEntriesIsIgnored() {
        let result = MPVCodecWhitelist.narrowed("h264, av1 ,vp9") { codec in
            codec == "av1" ? false : true
        }
        XCTAssertEqual(result, "h264,vp9")
    }

    func testEmptyWhitelistReturnsNil() {
        XCTAssertNil(MPVCodecWhitelist.narrowed("") { _ in false })
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVCodecWhitelistTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'MPVCodecWhitelist' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/MPV/MPVCodecWhitelist.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Narrows mpv's hwdec-codecs list to what this Mac can actually decode in
// hardware. Modelled on IINA's adjustCodecWhiteList (MPVController.swift:201).
// Asking VideoToolbox to hardware-decode something it cannot leaves mpv falling
// back silently, with no diagnostic and worse performance than saying so.

import Foundation

nonisolated enum MPVCodecWhitelist {
    /// - Parameter isSupported: `true` keep, `false` drop, `nil` when this app
    ///   has no opinion — an unknown codec is kept rather than guessed at.
    /// - Returns: the narrowed list, or `nil` when nothing changed.
    static func narrowed(
        _ whitelist: String,
        isSupported: (String) -> Bool?
    ) -> String? {
        let codecs = whitelist
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !codecs.isEmpty else { return nil }

        var kept: [String] = []
        var dropped = false
        for codec in codecs {
            if isSupported(codec) == false {
                dropped = true
            } else {
                kept.append(codec)
            }
        }
        return dropped ? kept.joined(separator: ",") : nil
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVCodecWhitelistTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVCodecWhitelist.swift" \
        "Aagedal Media Player Tests/MPVCodecWhitelistTests.swift"
git commit -m "Narrow mpv's hardware-decode whitelist by capability

A codec this app cannot check is kept rather than guessed at, and an
unchanged list is not written back."
```

---

### Task 2: The VideoToolbox probe

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/HardwareDecodeCapabilities.swift`
- Test: `Aagedal Media Player Tests/HardwareDecodeCapabilitiesTests.swift`

**Interfaces:**
- Produces, used by Task 3:
  ```swift
  final class HardwareDecodeCapabilities: @unchecked Sendable {
      static let shared: HardwareDecodeCapabilities
      func beginProbing()
      func isSupported(mpvCodec: String) -> Bool?
  }
  ```

**Note on the reference:** IINA calls `Logger.fatal` when the cache is used
before `checkCapabilities()` (`HardwareDecodeCapabilities.swift:64-77`). This
port returns `nil` instead — an unprobed cache means "no opinion", which
Task 1 already treats as "keep the codec".

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/HardwareDecodeCapabilitiesTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class HardwareDecodeCapabilitiesTests: XCTestCase {
    /// A codec outside the probed set has no answer, so callers keep it.
    func testUnknownCodecHasNoOpinion() {
        let capabilities = HardwareDecodeCapabilities()
        capabilities.beginProbing()
        XCTAssertNil(capabilities.isSupported(mpvCodec: "theora"))
    }

    /// h264 is not probed: every Mac this app runs on decodes it in hardware,
    /// and probing costs a long VideoToolbox call for a foregone answer.
    func testH264IsNotProbed() {
        let capabilities = HardwareDecodeCapabilities()
        capabilities.beginProbing()
        XCTAssertNil(capabilities.isSupported(mpvCodec: "h264"))
    }

    /// Probed codecs must return a definite answer once probing finishes.
    func testProbedCodecsAnswerDefinitely() {
        let capabilities = HardwareDecodeCapabilities()
        capabilities.beginProbing()
        for codec in ["av1", "vp9", "prores"] {
            XCTAssertNotNil(capabilities.isSupported(mpvCodec: codec),
                            "\(codec) should have a definite answer")
        }
    }

    /// Asking before probing must not crash or block forever.
    func testQueryBeforeProbingReturnsNil() {
        XCTAssertNil(HardwareDecodeCapabilities().isSupported(mpvCodec: "av1"))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/HardwareDecodeCapabilitiesTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'HardwareDecodeCapabilities' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/MPV/HardwareDecodeCapabilities.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from IINA's HardwareDecodeCapabilities.swift (GPL-3.0), by low-batt.
// https://github.com/iina/iina
//
// VTIsHardwareDecodeSupported is slow and must not run on the main thread, so
// the answers are gathered once on a background queue and cached. Unlike the
// original, an unprobed or unknown codec returns nil rather than trapping:
// "no opinion" is a safe answer, because the caller keeps the codec.

import CoreMedia
import Foundation
import OSLog
import VideoToolbox

final class HardwareDecodeCapabilities: @unchecked Sendable {
    static let shared = HardwareDecodeCapabilities()

    /// mpv's codec names, mapped to the CoreMedia types that can satisfy them.
    /// h264 and hevc are absent on purpose: every supported Mac decodes them,
    /// and probing costs a long call for a foregone answer. ProRes RAW is
    /// absent because it never reaches mpv — it is routed to AVPlayer.
    private static let codecTypes: [String: [CMVideoCodecType]] = [
        "av1": [kCMVideoCodecType_AV1],
        "vp9": [kCMVideoCodecType_VP9],
        "prores": [
            kCMVideoCodecType_AppleProRes422,
            kCMVideoCodecType_AppleProRes422HQ,
            kCMVideoCodecType_AppleProRes422LT,
            kCMVideoCodecType_AppleProRes422Proxy,
            kCMVideoCodecType_AppleProRes4444,
            kCMVideoCodecType_AppleProRes4444XQ,
        ],
    ]

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "hwdec")
    private let lock = NSLock()
    private var probe: DispatchWorkItem?
    private var supported: [String: Bool] = [:]

    /// Starts probing on a background queue. Safe to call more than once.
    func beginProbing() {
        lock.lock()
        guard probe == nil else { lock.unlock(); return }
        let work = DispatchWorkItem { [self] in
            var results: [String: Bool] = [:]
            for (codec, types) in Self.codecTypes {
                results[codec] = types.contains { type in
                    VTRegisterSupplementalVideoDecoderIfAvailable(type)
                    return VTIsHardwareDecodeSupported(type)
                }
            }
            lock.lock()
            supported = results
            lock.unlock()
            logger.info("Hardware decode support: \(results.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "), privacy: .public)")
        }
        probe = work
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    /// - Returns: `nil` when this app has no opinion — the codec is not probed,
    ///   or probing has not been started.
    func isSupported(mpvCodec: String) -> Bool? {
        guard Self.codecTypes[mpvCodec] != nil else { return nil }
        lock.lock()
        let pending = probe
        lock.unlock()
        guard let pending else { return nil }
        pending.wait()
        lock.lock()
        defer { lock.unlock() }
        return supported[mpvCodec]
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/HardwareDecodeCapabilitiesTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/HardwareDecodeCapabilities.swift" \
        "Aagedal Media Player Tests/HardwareDecodeCapabilitiesTests.swift"
git commit -m "Ask VideoToolbox what this Mac can actually decode

Ported from IINA. The probe is slow enough that Apple warns against running it
on the main thread, so it runs once on a background queue and is cached."
```

---

### Task 3: Use the probe, and let the user choose

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` (the `hwdec` line, ~line 248)
- Modify: `Aagedal Media Player/Logic/AppSettings.swift`
- Modify: `Aagedal Media Player/Aagedal_Media_PlayerApp.swift` (start probing at launch)
- Test: `Aagedal Media Player Tests/HardwareDecoderSettingTests.swift`

**Interfaces:**
- Produces, surfaced by Plan 1: `AppSettings.hardwareDecoder` (String, default `"auto"`),
  valid values `"auto"`, `"videotoolbox"`, `"videotoolbox-copy"`, `"no"`.
- Produces: `MPVPlayer.hwdecOptionValue(preference:correctsReflection:) -> String` (static, internal).

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/HardwareDecoderSettingTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class HardwareDecoderSettingTests: XCTestCase {
    /// Reflection correction needs a video filter, and a filter cannot touch an
    /// opaque VideoToolbox surface, so copy-back is forced regardless of choice.
    func testReflectionForcesCopyBack() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "videotoolbox", correctsReflection: true),
            "videotoolbox-copy")
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "auto", correctsReflection: true),
            "videotoolbox-copy")
    }

    /// Turning hardware decoding off must stay off even with a filter installed.
    func testDisabledStaysDisabled() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "no", correctsReflection: true),
            "no")
    }

    func testAutoMapsToVideoToolbox() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "auto", correctsReflection: false),
            "videotoolbox")
    }

    func testExplicitChoiceIsHonoured() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "videotoolbox-copy", correctsReflection: false),
            "videotoolbox-copy")
    }

    /// An unrecognised stored value must not be passed to mpv verbatim.
    func testUnknownPreferenceFallsBackToVideoToolbox() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "nonsense", correctsReflection: false),
            "videotoolbox")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/HardwareDecoderSettingTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: no member `hwdecOptionValue`.

- [ ] **Step 3: Add the setting**

In `Aagedal Media Player/Logic/AppSettings.swift`, beside the rendering settings:

```swift
    /// "auto", "videotoolbox", "videotoolbox-copy" or "no".
    static let hardwareDecoder = AppSetting(key: "hardwareDecoder", defaultValue: "auto")
```

Register it in `registerDefaults(in:)`.

- [ ] **Step 4: Add the resolver and use it**

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, add near the other statics:

```swift
    /// Resolves the hwdec option. Reflection correction installs a video filter,
    /// and a filter cannot operate on the opaque surface `videotoolbox` hands
    /// back, so that case forces copy-back — except when the user has turned
    /// hardware decoding off outright.
    static func hwdecOptionValue(preference: String, correctsReflection: Bool) -> String {
        if preference == "no" { return "no" }
        if correctsReflection { return "videotoolbox-copy" }
        switch preference {
        case "videotoolbox-copy": return "videotoolbox-copy"
        case "videotoolbox", "auto": return "videotoolbox"
        default: return "videotoolbox"
        }
    }
```

Replace the existing hwdec line:

```swift
        checkError(mpv_set_option_string(mpv, "hwdec", correctsReflection ? "videotoolbox-copy" : "videotoolbox"), context: "hwdec")
```

with:

```swift
        let hwdec = Self.hwdecOptionValue(
            preference: UserDefaults.standard.value(for: AppSettings.hardwareDecoder),
            correctsReflection: correctsReflection)
        checkError(mpv_set_option_string(mpv, "hwdec", hwdec), context: "hwdec")
```

- [ ] **Step 5: Narrow the whitelist after mpv initialises**

`hwdec-codecs` only has its default value after `mpv_initialize`. In
`setupMPV()`, immediately after the `mpv_initialize` success check, add:

```swift
        applyCodecWhitelist()
```

and add the method beside `applyAudioAndDecoderOptions()`:

```swift
    /// Removes codecs this Mac cannot hardware-decode from mpv's whitelist, so
    /// mpv stops attempting a path that silently falls back.
    private func applyCodecWhitelist() {
        guard let current = getString("hwdec-codecs") else { return }
        guard let narrowed = MPVCodecWhitelist.narrowed(current, isSupported: { codec in
            HardwareDecodeCapabilities.shared.isSupported(mpvCodec: codec)
        }) else { return }
        logger.info("Narrowing hwdec-codecs from \(current, privacy: .public) to \(narrowed, privacy: .public)")
        setString("hwdec-codecs", narrowed)
    }
```

- [ ] **Step 6: Start probing at launch**

In `Aagedal Media Player/Aagedal_Media_PlayerApp.swift`, in
`applicationDidFinishLaunching`, before the first window can appear:

```swift
        HardwareDecodeCapabilities.shared.beginProbing()
```

- [ ] **Step 7: Run the tests and build**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/HardwareDecoderSettingTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 8: Verify against a real file**

Play any file and confirm the whitelist decision is logged:

```bash
log stream --predicate 'subsystem == "com.aagedal.MediaPlayer" AND category == "hwdec"' --style compact
```

Expected: one `Hardware decode support: av1=… prores=… vp9=…` line at launch.
A `Narrowing hwdec-codecs` line appears only on Macs missing a codec.

- [ ] **Step 9: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVPlayer.swift" \
        "Aagedal Media Player/Logic/AppSettings.swift" \
        "Aagedal Media Player/Aagedal_Media_PlayerApp.swift" \
        "Aagedal Media Player Tests/HardwareDecoderSettingTests.swift"
git commit -m "Stop assuming VideoToolbox decodes everything

hwdec was hardcoded, so on a Mac without AV1 or VP9 hardware support mpv
attempted a path that silently fell back. Probe the codecs, narrow mpv's
whitelist to what the machine can do, and let the decoder be chosen. Reflection
correction still forces copy-back, since its filter cannot read the opaque
surface the zero-copy path returns."
```

---

### Task 4: A filter value type

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/MPVVideoFilter.swift`
- Test: `Aagedal Media Player Tests/MPVVideoFilterTests.swift`

**Interfaces:**
- Produces, used by Task 5:
  ```swift
  nonisolated struct MPVVideoFilter: Equatable {
      let label: String
      let name: String
      let parameters: [(String, String)]
      var filterString: String        // "@label:name=k=v:k2=v2"
      static func lavfi(label: String, graph: String) -> MPVVideoFilter
      static func lut3d(label: String, path: String) -> MPVVideoFilter
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/MPVVideoFilterTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class MPVVideoFilterTests: XCTestCase {
    func testLabelledFilterWithoutParameters() {
        let filter = MPVVideoFilter(label: "amp-flip", name: "vflip", parameters: [])
        XCTAssertEqual(filter.filterString, "@amp-flip:vflip")
    }

    func testParametersAreJoinedInOrder() {
        let filter = MPVVideoFilter(label: "amp-crop", name: "crop",
                                    parameters: [("w", "640"), ("h", "480")])
        XCTAssertEqual(filter.filterString, "@amp-crop:crop=w=640:h=480")
    }

    /// A lavfi graph is wrapped in brackets, which is how mpv expects it.
    func testLavfiGraphIsBracketed() {
        let filter = MPVVideoFilter.lavfi(label: "amp-reflect", graph: "vflip")
        XCTAssertEqual(filter.filterString, "@amp-reflect:lavfi=[vflip]")
    }

    /// A LUT path can contain spaces and must survive quoting.
    func testLUTPathIsQuoted() {
        let filter = MPVVideoFilter.lut3d(label: "amp-lut", path: "/Volumes/Grade A/show.cube")
        XCTAssertEqual(filter.filterString,
                       "@amp-lut:lavfi=[lut3d=file='/Volumes/Grade A/show.cube']")
    }

    func testLabelIsUsedForRemoval() {
        let filter = MPVVideoFilter.lavfi(label: "amp-lut", graph: "null")
        XCTAssertEqual(filter.removalArgument, "@amp-lut")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVVideoFilterTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'MPVVideoFilter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/MPV/MPVVideoFilter.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One entry in mpv's video filter chain. Every filter carries a label so it can
// be removed by name later, the way the audio channel router already works.
// The string format follows mpv's filter syntax; see IINA's MPVFilter.swift
// for the fuller model this is a deliberate subset of.

import Foundation

nonisolated struct MPVVideoFilter: Equatable {
    let label: String
    let name: String
    let parameters: [Parameter]

    struct Parameter: Equatable {
        let key: String
        let value: String
    }

    init(label: String, name: String, parameters: [(String, String)]) {
        self.label = label
        self.name = name
        self.parameters = parameters.map { Parameter(key: $0.0, value: $0.1) }
    }

    var filterString: String {
        let base = "@\(label):\(name)"
        guard !parameters.isEmpty else { return base }
        let joined = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: ":")
        return "\(base)=\(joined)"
    }

    /// mpv removes a labelled filter by its label alone.
    var removalArgument: String { "@\(label)" }

    static func lavfi(label: String, graph: String) -> MPVVideoFilter {
        MPVVideoFilter(label: label, name: "lavfi", parameters: [("", "")])
            .replacingLavfiGraph(graph)
    }

    /// A 3D LUT, the filter a grading review most often wants.
    static func lut3d(label: String, path: String) -> MPVVideoFilter {
        lavfi(label: label, graph: "lut3d=file='\(path)'")
    }

    private func replacingLavfiGraph(_ graph: String) -> MPVVideoFilter {
        var copy = MPVVideoFilter(label: label, name: "lavfi", parameters: [])
        copy.lavfiGraph = graph
        return copy
    }

    private var lavfiGraph: String? {
        get { storedGraph }
        set { storedGraph = newValue }
    }

    private var storedGraph: String?
}
```

Then correct `filterString` to account for the graph — replace the computed
property with:

```swift
    var filterString: String {
        if let storedGraph {
            return "@\(label):lavfi=[\(storedGraph)]"
        }
        let base = "@\(label):\(name)"
        guard !parameters.isEmpty else { return base }
        let joined = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: ":")
        return "\(base)=\(joined)"
    }
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVVideoFilterTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 5 tests, with 0 failures`. If `lavfi(label:graph:)` does not
round-trip, simplify: store the graph as a stored property set in a dedicated
initialiser rather than through the `replacingLavfiGraph` dance.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVVideoFilter.swift" \
        "Aagedal Media Player Tests/MPVVideoFilterTests.swift"
git commit -m "Model one mpv video filter

Every filter carries a label so it can be removed by name, which is how the
audio channel router already works."
```

---

### Task 5: The runtime filter chain

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`

**Interfaces:**
- Consumes: `MPVVideoFilter`.
- Produces: `MPVPlayer.setVideoFilter(_ filter: MPVVideoFilter?, label: String)` — passing
  `nil` removes the filter with that label.

**Why this replaces the init-time option:** `vf=lavfi=[vflip]` is set once with
`mpv_set_option_string` and replaces the whole graph, so nothing else can ever
add a filter. Moving it to a labelled runtime entry frees the chain, following
`applyAudioChannelRouting` (`MPVPlayer.swift:598`).

- [ ] **Step 1: Add the chain**

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, beside
`applyAudioChannelRouting()`:

```swift
    /// Labels currently installed in the video filter chain.
    private var activeVideoFilterLabels: Set<String> = []

    /// Installs or removes one labelled video filter. mpv keeps the rest of the
    /// chain intact, so filters no longer have to be decided at startup.
    ///
    /// A filter cannot read the opaque surface `hwdec=videotoolbox` returns, so
    /// anything that installs one must also be running copy-back — see
    /// `hwdecOptionValue(preference:correctsReflection:)`.
    func setVideoFilter(_ filter: MPVVideoFilter?, label: String) {
        guard mpv != nil else { return }
        if let filter {
            if activeVideoFilterLabels.contains(label) {
                command("vf", args: ["remove", "@\(label)"])
            }
            if command("vf", args: ["add", filter.filterString]) {
                activeVideoFilterLabels.insert(label)
            }
        } else if activeVideoFilterLabels.contains(label),
                  command("vf", args: ["remove", "@\(label)"]) {
            activeVideoFilterLabels.remove(label)
        }
    }
```

- [ ] **Step 2: Move the reflection flip onto the chain**

Delete the init-time block:

```swift
        if correctsReflection {
            checkError(mpv_set_option_string(mpv, "vf", "lavfi=[vflip]"), context: "display reflection")
        }
```

and install it after `mpv_initialize` succeeds, beside `applyCodecWhitelist()`:

```swift
        if correctsReflection {
            // A reflected matrix decomposes into the rotation mpv already
            // applies and a vertical flip in coded-raster coordinates. The
            // filter fixes the surface, the scopes and screenshots together.
            setVideoFilter(.lavfi(label: Self.reflectionFilterLabel, graph: "vflip"),
                           label: Self.reflectionFilterLabel)
        }
```

with the label beside the other statics:

```swift
    static let reflectionFilterLabel = "amp-reflection"
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Verify the reflection path still works**

This is the regression that matters. Find a QuickTime file whose
`preferredTransform` has a negative determinant — a mirrored export, or produce
one:

```bash
ffmpeg -f lavfi -i testsrc=size=640x480:duration=3 -vf hflip -metadata:s:v rotate=0 -c:v prores_ks /tmp/mirrored.mov
```

Open it and confirm the picture is not upside down, and that the scopes and a
screenshot agree with what is on screen. A black picture instead means hwdec is
not on copy-back — check Task 3's resolver.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed [0-9]+ tests|error:|TEST"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVPlayer.swift"
git commit -m "Give video filters a chain instead of one fixed slot

The reflection flip was set as a startup option that replaced the entire
filter graph, so nothing else could ever be added. It is now a labelled entry
added at runtime, which leaves room for a LUT or a crop beside it."
```

---

## What this deliberately does not build

A filter *UI* and a preset catalogue. `setVideoFilter` is the mechanism; a
grading-review LUT picker is the obvious next consumer, and belongs in its own
plan against a real workflow rather than being guessed at here.
