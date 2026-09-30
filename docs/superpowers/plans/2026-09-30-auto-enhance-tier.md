# Auto-Enhance Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user turns on "Enhance", amp picks a shader tier (SSimSuperRes, RAVU zoom, or ArtCNN) from the upscale ratio. It steps the tier down when the GPU cannot keep up. The default render path stays faithful.

**Architecture:** Two pure value types hold the decision logic, and both are tested with Swift Testing:
- `RenderTier` and `TierSelector` choose the tier from the ratio, the shader files available, and a fallback floor.
- `GPUBudgetMonitor` turns a once-a-second sample (mpv `vo-passes` JSON plus `frame-drop-count`) into a verdict.

`MPVPlayer` supplies the inputs: drawable size from an `MPVMetalLayer` callback, and source size from mpv. It applies a tier through the same `change-list glsl-shaders` path the manual profiles use. SwiftUI adds a settings toggle and a badge over the player.

**Tech Stack:** Swift 6.4 (Xcode 27.0, Swift 6 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in the app target), SwiftUI, Swift Testing, `Synchronization.Mutex`, and libmpv 0.41.0 / libplacebo 7.360.1 via MPVKit `230c317`.

**Spec:** `docs/superpowers/specs/2026-09-30-auto-enhance-tier-design.md`. Its "Verified facts" section gives the source for every number used here.

**Verification status:** Every code block in Tasks 1–6 was applied verbatim to a scratch worktree on 2026-09-30 and built with Xcode 27.0 in Swift 6 mode.
- Result: 0 errors and 0 warnings on a clean build.
- Full suite: 649 passed, 0 failed, 5 skipped.

## Status (2026-09-30): Tasks 1–6 are done; only Task 7 remains

Tasks 1–6 were implemented and landed on `main`, verified with a clean build (0 warnings) and the full suite (634 passed, 0 failed, 5 skipped by `xcresulttool`):

| Commit | Content |
|---|---|
| `1013b26` | Task 1: builds cleanly in Swift 6.4 mode |
| `29322b0` | Tasks 2–6: tier ladder, selector, GPU budget monitor, drawable callback, MPVPlayer wiring, Enhance toggle, badge |
| `2f0fc09` | Control-bar gear opens Settings (`openSettings()`; `showSettingsWindow:` was removed in macOS 14); Playlist button toggles; inspector ✕ |
| `fbbf129` | Deployment target macOS 26.0 (`glassEffect` needs 26); `Text + Text` deprecation fixed |
| `1beebdd` | Playlist/metadata panel floats over the picture as Liquid Glass (`.clear` tinted 50% black); ⌘I or ✕ closes it |
| `2569bc3` | Heaviest tier `artcnnStrong` (ArtCNN_C4F32) replaced by `fsrcnnx` (FSRCNNX_x2_16-0-4-1) after the gaia.mov benchmark; `VOPassTiming` ignores passes mpv never samples |

Differences from the task text below: the deployment target is now 26.0, not 15.0; the inspector is no longer a native `.inspector` column; and `artcnnStrong` in the code blocks is now `fsrcnnx`. The Tasks 1–6 sections are kept as the record of what landed. **Do not execute Preconditions or Tasks 1–6 again.** Only Task 7 remains, and it needs a person.

## How to execute this plan

- Work in `/Users/filip/src/amp` on branch `main`. Do not create a worktree. The tests need `Test Fixtures/Generated/`, which is gitignored and exists only in that checkout.
- Do exactly what each step says, in order. Do not rename anything, reformat code, or "improve" code outside the given edits.
- **Edit format.** Every edit to an existing file is a **Find** block and a **Replace** block. The Find text must occur exactly once in the file, and the match is exact, including leading spaces. Replace it with the Replace text.
- **Stop rule.** Stop and report, without trying a fix of your own, if any of these happens:
  - a Find block matches zero times or more than once;
  - a command prints an `error:` line;
  - a count differs from the "Expected" value;
  - a command prints a `warning:` line for a file this plan touches.
- Never pass `SWIFT_VERSION=5` or any other build setting not written here.
- Never use `git add -A`, `git add .` or `git commit -a`. Stage files by the exact paths given. The working tree also holds the user's own uncommitted changes, which must stay out of every commit: the deleted `LICENSE`, `Aagedal Media Player Tests/CompareLiveBackendTests.swift`, and `.omc/`.
- Commit messages are exactly as written. Add no other lines.

## Commands used throughout

**Test one or more suites:**
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/SUITE" > "$TMPDIR/amp-test.log" 2>&1
```
Replace `SUITE` with the suite name. Repeat the whole `-only-testing:"…"` argument for each suite.

**Test everything:** the same command with no `-only-testing` argument. It takes about 2 minutes.

**Read the result of either:**
```bash
grep -E '^\*\* TEST (SUCCEEDED|FAILED) \*\*' "$TMPDIR/amp-test.log"
grep -E '^/.*: (error|warning):' "$TMPDIR/amp-test.log" | grep -v SourcePackages | sort -u
echo passed $(grep -c "^Test case '.*' passed" "$TMPDIR/amp-test.log") failed $(grep -c "^Test case '.*' failed" "$TMPDIR/amp-test.log") skipped $(grep -c "^Test case '.*' skipped" "$TMPDIR/amp-test.log")
```

**Clean build, to check warnings:**
```bash
xcodebuild clean build -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= > "$TMPDIR/amp-build.log" 2>&1
grep -E '^\*\* BUILD (SUCCEEDED|FAILED) \*\*' "$TMPDIR/amp-build.log"
grep -E '^/.*: (error|warning):' "$TMPDIR/amp-build.log" | grep -v SourcePackages | sort -u
```

**Known flaky tests.** `docs/handoff-for-claude.md` ("Focus 1") records intermittent deadline failures in `CompareLiveBackendTests`. A different live-decode case fails each time, and each passes on its own. This plan does not touch that code. Apply this rule only to full-suite runs:
- If every failed case listed by `grep "^Test case '.*' failed" "$TMPDIR/amp-test.log"` belongs to `CompareLiveBackendTests` and `** TEST FAILED **` is the only problem, run the full suite once more.
- If the second run matches the Expected line, continue.
- Stop on any other failure, or on a second failed run.

Signing is ad hoc (`CODE_SIGN_IDENTITY=-`) because this Mac has no "Mac Development" certificate. If the test bundle fails to compile, the log also shows `Command CodeSign failed … code object is not signed at all`. That line is a consequence. Report the compile `error:` above it instead.

## Global Constraints

- The deployment target stays `MACOSX_DEPLOYMENT_TARGET = 15.0`. Use no API newer than macOS 15.
- New tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Existing XCTest files are not changed.
- Pure logic types and their extensions are declared `nonisolated`. The app target defaults everything else to `MainActor`, and tests call these types from nonisolated code.
- Shaders come only from the shader library directory (default `~/.config/mpv/shaders`). Never copy or bundle shader files.
- Numbers, all from the spec's measurements:
  - budget fraction `0.5`
  - warm-up `30` samples per fresh pass
  - drop rule: `frame-drop-count` rises by `3` or more within `2` s
  - sampling interval `1` s
  - resize debounce `300` ms
  - ArtCNN minimum ratio `1.9`
- Read `vo-passes` only on `MPVPlayer.queue`, never on the main thread. `vo_control` blocks until the VO thread answers.
- The libplacebo shader-failure log is prefix `vo/gpu-next/libplacebo`, text starting `Failed executing hook`.

## Preconditions

- [ ] **Step P1: Check the checkout**

```bash
cd /Users/filip/src/amp
git branch --show-current
git status --short
test -f "Test Fixtures/Generated/compare/source-a.mov" && echo fixtures-ok
xcodebuild -version | head -1
```

Expected:
1. `main`
2. Exactly these eight lines, in any order:
   ```text
    M "Aagedal Media Player Tests/CompareLiveBackendTests.swift"
    M "Aagedal Media Player/Logic/AppSettings.swift"
    M "Aagedal Media Player/Logic/ComparisonStillExporter.swift"
    M "Aagedal Media Player/Logic/PlayerController+Observers.swift"
    M "Aagedal Media Player/Logic/PlayerController.swift"
    M "Aagedal Media Player/UI/PlayerOverlayViews.swift"
    D LICENSE
   ?? .omc/
   ```
   The first and the last two belong to the user. The other five are Task 1's edits.
3. `fixtures-ok`
4. `Xcode 27.0`

If `fixtures-ok` is missing, run `scripts/generate-test-fixtures.sh` and check again. If it is still missing, stop.

---

### Task 1: Build in Swift 6.4 language mode without warnings

Under Xcode 27 / Swift 6.4 the project did not compile in its own Swift 6 mode. Five edits fix it. They were applied to the working tree on 2026-09-30 and are not committed yet.

**Files:**
- Modify: `Aagedal Media Player/UI/PlayerOverlayViews.swift`
- Modify: `Aagedal Media Player/Logic/AppSettings.swift`
- Modify: `Aagedal Media Player/Logic/PlayerController.swift`
- Modify: `Aagedal Media Player/Logic/PlayerController+Observers.swift`
- Modify: `Aagedal Media Player/Logic/ComparisonStillExporter.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: a Swift 6 build with no errors and no warnings. Every later task depends on it.

- [ ] **Step 1: Confirm the five edits are present**

```bash
grep -c '^nonisolated private struct ProgressCapsuleBorder: Shape {$' "Aagedal Media Player/UI/PlayerOverlayViews.swift"
grep -c '^nonisolated extension UserDefaults {$' "Aagedal Media Player/Logic/AppSettings.swift"
grep -c '^nonisolated extension Double {$' "Aagedal Media Player/Logic/PlayerController.swift"
grep -c 'repeats: true) { \[weak self, weak observedMPV\] _ in$' "Aagedal Media Player/Logic/PlayerController+Observers.swift"
grep -c '^    @concurrent static func image($' "Aagedal Media Player/Logic/ComparisonStillExporter.swift"
```

Expected: `1` five times. For any line that prints `0`, apply that file's edit below, then run Step 1 again. The five edits:

`Aagedal Media Player/UI/PlayerOverlayViews.swift`. `Shape`'s requirements are nonisolated, and a main-actor struct's conformance crossed isolation.

Find:
```swift
private struct ProgressCapsuleBorder: Shape {
```
Replace:
```swift
nonisolated private struct ProgressCapsuleBorder: Shape {
```

`Aagedal Media Player/Logic/AppSettings.swift`. These are pure wrappers over thread-safe `UserDefaults`, called from nonisolated tests.

Find:
```swift
extension UserDefaults {
    func value<Value: Sendable>(for setting: AppSetting<Value>) -> Value {
```
Replace:
```swift
nonisolated extension UserDefaults {
    func value<Value: Sendable>(for setting: AppSetting<Value>) -> Value {
```

`Aagedal Media Player/Logic/PlayerController.swift`. The function is pure and is called from nonisolated tests.

Find:
```swift
extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
```
Replace:
```swift
nonisolated extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
```

`Aagedal Media Player/Logic/PlayerController+Observers.swift`. Swift 6.4 warns `[#ImplicitStrongCapture]` when an inner closure captures weakly something the outer closure captures strongly.

Find:
```swift
        mpvLoopObserverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
```
Replace:
```swift
        mpvLoopObserverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self, weak observedMPV] _ in
```

`Aagedal Media Player/Logic/ComparisonStillExporter.swift`. In the macOS 27 SDK, `AVAssetImageGenerator.image(at:)` is `@concurrent`. Sending the caller-isolated `generator` to it failed with `sending 'generator' risks causing data races`.

Find:
```swift
    static func image(
        from url: URL, at time: TimeInterval, maximumSize: CGSize = .zero,
```
Replace:
```swift
    @concurrent static func image(
        from url: URL, at time: TimeInterval, maximumSize: CGSize = .zero,
```

- [ ] **Step 2: Clean build**

Run the clean-build command.

Expected: `** BUILD SUCCEEDED **`, and the error/warning `grep` prints nothing.

- [ ] **Step 3: Run the full suite**

Run the test-everything command, then the read-result commands.

Expected:
- `** TEST SUCCEEDED **`
- no `error:` or `warning:` lines
- `passed 615 failed 0 skipped 5`

- [ ] **Step 4: Commit**

```bash
git add "Aagedal Media Player/UI/PlayerOverlayViews.swift" "Aagedal Media Player/Logic/AppSettings.swift" "Aagedal Media Player/Logic/PlayerController.swift" "Aagedal Media Player/Logic/PlayerController+Observers.swift" "Aagedal Media Player/Logic/ComparisonStillExporter.swift"
git commit -m "Build cleanly in the Swift 6.4 language mode"
```

---

### Task 2: Tier ladder and selector

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/RenderProfile.swift` (`ShaderLibrary`)
- Create: `Aagedal Media Player/Logic/MPV/RenderTier.swift`
- Create (test): `Aagedal Media Player Tests/RenderTierTests.swift`

The project uses `PBXFileSystemSynchronizedRootGroup`, so new files join their targets automatically. Do not edit `project.pbxproj`.

**Interfaces:**
- Consumes: `RenderProfile.sharpen.shaderFileNames`, `RenderProfile.sharpen.scaleOptions`, `RenderProfile.off.scaleOptions`. All three already exist.
- Produces:
  - `nonisolated enum RenderTier: Int, CaseIterable, Comparable, Sendable { case faithful, sharpen, ravuZoom, artcnnLight, artcnnStrong }` with:
    - `displayName: String`
    - `shaderFileNames: [String]`
    - `scaleOptions: [String: String]`
    - `isEligible(ratio: Double) -> Bool`
    - `steppedDown: RenderTier`
    - `static let neuralDoublerMinimumRatio = 1.9`
  - `nonisolated enum TierSelector` with:
    - `static func upscaleRatio(source: CGSize, drawable: CGSize) -> Double?`
    - `static func select(ratio: Double, available: Set<RenderTier>, floor: RenderTier) -> RenderTier`
  - `ShaderLibrary.shaderPaths(named: [String]) -> [String]`
  - `ShaderLibrary.missingShaderNames(named: [String]) -> [String]`

- [ ] **Step 1: Create the test file**

Create `Aagedal Media Player Tests/RenderTierTests.swift` with exactly this content:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import Foundation
import Testing

struct RenderTierTests {
    private static let everyTier = Set(RenderTier.allCases)

    @Test(arguments: [
        (0.5, RenderTier.faithful),
        (1.0, .faithful),
        (1.2, .ravuZoom),
        (1.57, .ravuZoom),
        (1.9, .artcnnStrong),
        (2.0, .artcnnStrong),
        (3.0, .artcnnStrong),
    ])
    func picksTheHeaviestTierTheRatioAllows(ratio: Double, expected: RenderTier) {
        #expect(TierSelector.select(ratio: ratio, available: Self.everyTier, floor: .artcnnStrong) == expected)
    }

    @Test(arguments: [
        (2.0, RenderTier.artcnnLight, RenderTier.artcnnLight),
        (2.0, .ravuZoom, .ravuZoom),
        (2.0, .sharpen, .sharpen),
        (2.0, .faithful, .faithful),
        (1.57, .ravuZoom, .ravuZoom),
        (1.57, .sharpen, .sharpen),
    ])
    func neverExceedsTheFloor(ratio: Double, floor: RenderTier, expected: RenderTier) {
        #expect(TierSelector.select(ratio: ratio, available: Self.everyTier, floor: floor) == expected)
    }

    @Test func skipsTiersWhoseShadersAreMissing() {
        let withoutArtCNN: Set<RenderTier> = [.faithful, .sharpen, .ravuZoom]
        #expect(TierSelector.select(ratio: 2.0, available: withoutArtCNN, floor: .artcnnStrong) == .ravuZoom)

        let withoutRAVU: Set<RenderTier> = [.faithful, .sharpen, .artcnnLight, .artcnnStrong]
        #expect(TierSelector.select(ratio: 1.2, available: withoutRAVU, floor: .artcnnStrong) == .sharpen)

        #expect(TierSelector.select(ratio: 2.0, available: [], floor: .artcnnStrong) == .faithful)
    }

    @Test func ratioIsTheTighterAxis() throws {
        // Fullscreen drawable measured on an M1 Pro 16" on 2026-09-30.
        let ratio = try #require(TierSelector.upscaleRatio(
            source: CGSize(width: 1920, height: 1080),
            drawable: CGSize(width: 3448, height: 2164)
        ))
        #expect(abs(ratio - 3448.0 / 1920.0) < 1e-9)
    }

    @Test func ratioNeedsBothSizes() {
        #expect(TierSelector.upscaleRatio(source: .zero, drawable: CGSize(width: 10, height: 10)) == nil)
        #expect(TierSelector.upscaleRatio(source: CGSize(width: 10, height: 10), drawable: .zero) == nil)
    }

    @Test func stepsDownOneRungAndStopsAtFaithful() {
        #expect(RenderTier.artcnnStrong.steppedDown == .artcnnLight)
        #expect(RenderTier.sharpen.steppedDown == .faithful)
        #expect(RenderTier.faithful.steppedDown == .faithful)
    }

    @Test func onlySharpenChangesTheScaler() {
        for tier in RenderTier.allCases {
            let expected = tier == .sharpen ? RenderProfile.sharpen.scaleOptions : RenderProfile.off.scaleOptions
            #expect(tier.scaleOptions == expected, "\(tier)")
        }
    }

    @Test func libraryResolvesNameLists() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "RenderTierTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appending(path: "ravu-zoom-ar-r3.hook"))

        let library = ShaderLibrary(directoryPath: directory.path)
        let names = ["ravu-zoom-ar-r3.hook", "ArtCNN_C4F16.glsl"]

        #expect(library.shaderPaths(named: names).count == 1)
        #expect(library.shaderPaths(named: names).first?.hasSuffix("ravu-zoom-ar-r3.hook") == true)
        #expect(library.missingShaderNames(named: names) == ["ArtCNN_C4F16.glsl"])
    }
}
```

- [ ] **Step 2: Confirm the tests fail**

Run the test command with suite `RenderTierTests`, then the read-result commands.

Expected: `** TEST FAILED **`, with an `error:` line containing `cannot find 'TierSelector' in scope`. This failure is intended. Go on to Step 3.

- [ ] **Step 3: Generalise `ShaderLibrary`**

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`:

Find:
```swift
    func shaderPaths(for profile: RenderProfile) -> [String] {
        profile.shaderFileNames.compactMap { name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    /// Shader names `profile` asks for that the directory does not contain.
    func missingShaderNames(for profile: RenderProfile) -> [String] {
        profile.shaderFileNames.filter { name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            return !FileManager.default.fileExists(atPath: path)
        }
    }
```
Replace:
```swift
    func shaderPaths(for profile: RenderProfile) -> [String] {
        shaderPaths(named: profile.shaderFileNames)
    }

    /// Shader names `profile` asks for that the directory does not contain.
    func missingShaderNames(for profile: RenderProfile) -> [String] {
        missingShaderNames(named: profile.shaderFileNames)
    }

    /// Existing paths for `names`, in the given order. Shared by the manual
    /// profiles and the automatic tiers.
    func shaderPaths(named names: [String]) -> [String] {
        names.compactMap { name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    /// The subset of `names` the directory does not contain.
    func missingShaderNames(named names: [String]) -> [String] {
        names.filter { name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            return !FileManager.default.fileExists(atPath: path)
        }
    }
```

- [ ] **Step 4: Create `RenderTier.swift`**

Create `Aagedal Media Player/Logic/MPV/RenderTier.swift` with exactly this content:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// One rung of the automatic enhancement ladder, lightest first.
///
/// Used only while Enhance is on and the manual profile is Faithful. Costs
/// below were measured on an M1 Pro, 720p fullscreen (2.69x), 24 fps source:
/// SSimSuperRes 10.1 ms, RAVU zoom 9.3 ms, ArtCNN C4F16 12.0 ms, C4F32 28.2 ms
/// per frame. The order follows image-quality intent, not cost. The GPU
/// budget monitor corrects for cost at runtime.
nonisolated enum RenderTier: Int, CaseIterable, Comparable, Sendable {
    case faithful
    case sharpen
    case ravuZoom
    case artcnnLight
    case artcnnStrong

    /// ArtCNN always emits exactly 2x. Below this ratio the overshoot would be
    /// thrown away again by `dscale`, which costs GPU time for nothing.
    static let neuralDoublerMinimumRatio = 1.9

    static func < (lhs: RenderTier, rhs: RenderTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .faithful: "Faithful"
        case .sharpen: "Sharpened"
        case .ravuZoom: "RAVU zoom"
        case .artcnnLight: "ArtCNN light"
        case .artcnnStrong: "ArtCNN strong"
        }
    }

    var shaderFileNames: [String] {
        switch self {
        case .faithful: []
        case .sharpen: RenderProfile.sharpen.shaderFileNames
        case .ravuZoom: ["ravu-zoom-ar-r3.hook"]
        case .artcnnLight: ["ArtCNN_C4F16.glsl"]
        case .artcnnStrong: ["ArtCNN_C4F32.glsl"]
        }
    }

    var scaleOptions: [String: String] {
        self == .sharpen ? RenderProfile.sharpen.scaleOptions : RenderProfile.off.scaleOptions
    }

    /// RAVU zoom renders at the target size, so it suits any upscale.
    /// SSimSuperRes guards itself with `!WHEN` and only runs when upscaling.
    func isEligible(ratio: Double) -> Bool {
        switch self {
        case .faithful: true
        case .sharpen, .ravuZoom: ratio > 1.0
        case .artcnnLight, .artcnnStrong: ratio >= Self.neuralDoublerMinimumRatio
        }
    }

    var steppedDown: RenderTier { RenderTier(rawValue: rawValue - 1) ?? .faithful }
}

/// Picks a tier from the upscale ratio, what is installed, and how far the
/// GPU monitor has forced the ladder down.
nonisolated enum TierSelector {
    /// Drawable pixels per source pixel on the tighter axis. `nil` until both
    /// sizes are known.
    static func upscaleRatio(source: CGSize, drawable: CGSize) -> Double? {
        guard source.width > 0, source.height > 0, drawable.width > 0, drawable.height > 0 else { return nil }
        return min(drawable.width / source.width, drawable.height / source.height)
    }

    /// The heaviest tier that is eligible for `ratio`, installed, and no
    /// heavier than `floor`.
    static func select(ratio: Double, available: Set<RenderTier>, floor: RenderTier) -> RenderTier {
        RenderTier.allCases.reversed().first { tier in
            tier <= floor && available.contains(tier) && tier.isEligible(ratio: ratio)
        } ?? .faithful
    }
}
```

- [ ] **Step 5: Confirm the tests pass**

Run the test command with both suites, `RenderTierTests` and `RenderProfileTests`, then the read-result commands.

Expected: `** TEST SUCCEEDED **` and `passed 27 failed 0 skipped 0`. That is 19 `RenderTierTests` cases (parameterized arguments count one each) plus 8 `RenderProfileTests` cases.

- [ ] **Step 6: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/RenderProfile.swift" "Aagedal Media Player/Logic/MPV/RenderTier.swift" "Aagedal Media Player Tests/RenderTierTests.swift"
git commit -m "Add the automatic render tier ladder and selector"
```

---

### Task 3: GPU budget monitor

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/GPUBudgetMonitor.swift`
- Create (test): `Aagedal Media Player Tests/GPUBudgetMonitorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `nonisolated struct VOPassTiming: Equatable, Sendable { let totalMilliseconds: Double; let minimumSampleCount: Int }`. It has its memberwise init, plus `init?(json: String)` declared in a `nonisolated extension`.
  - `nonisolated struct BudgetSample: Sendable { let timing: VOPassTiming?; let droppedFrames: Int; let uptime: TimeInterval }`
  - `nonisolated struct GPUBudgetMonitor: Sendable` with:
    - `enum Verdict { case warmingUp, withinBudget, overBudget }`
    - `init(sourceFPS: Double, displayFPS: Double)`
    - `let budgetMilliseconds: Double?`
    - `mutating func evaluate(_ sample: BudgetSample) -> Verdict`
    - `static func isShaderFailure(prefix: String, text: String) -> Bool`

- [ ] **Step 1: Create the test file**

Create `Aagedal Media Player Tests/GPUBudgetMonitorTests.swift` with exactly this content. The JSON is trimmed from real `vo-passes` output captured from mpv 0.41.0 on 2026-09-30.

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import Testing

struct GPUBudgetMonitorTests {
    @Test func parsesFreshPassesFromMpvJSON() throws {
        let json = #"{"fresh":[{"desc":"merging planes","last":35666,"avg":99470,"peak":405833,"count":7,"samples":[405833]},{"desc":"ortho (vert) upscaling (lanczos)","last":434083,"avg":1000000,"peak":595667,"count":31,"samples":[]}],"redraw":[]}"#
        let timing = try #require(VOPassTiming(json: json))
        #expect(abs(timing.totalMilliseconds - 1.09947) < 1e-9)
        #expect(timing.minimumSampleCount == 7)
    }

    @Test(arguments: [#"{"fresh":[],"redraw":[]}"#, "fresh:\n", ""])
    func rejectsEmptyOrNonJSONPasses(json: String) {
        #expect(VOPassTiming(json: json) == nil)
    }

    @Test func budgetIsHalfThePeriodOfTheSlowerRate() throws {
        let cinema = try #require(GPUBudgetMonitor(sourceFPS: 24, displayFPS: 120).budgetMilliseconds)
        #expect(abs(cinema - 500.0 / 24.0) < 1e-9)
        let noDisplay = try #require(GPUBudgetMonitor(sourceFPS: 60, displayFPS: 0).budgetMilliseconds)
        #expect(abs(noDisplay - 500.0 / 60.0) < 1e-9)
        #expect(GPUBudgetMonitor(sourceFPS: 0, displayFPS: .nan).budgetMilliseconds == nil)
    }

    @Test func waitsForEveryPassToWarmUp() {
        var monitor = GPUBudgetMonitor(sourceFPS: 24, displayFPS: 120)
        let compileSpike = BudgetSample(
            timing: VOPassTiming(totalMilliseconds: 81.66, minimumSampleCount: 0), droppedFrames: 0, uptime: 0)
        #expect(monitor.evaluate(compileSpike) == .warmingUp)
    }

    // 24 fps figures measured at 2.69x on an M1 Pro: C4F16 12.0 ms, C4F32 28.2 ms.
    @Test func judgesWarmTimingsAgainstTheBudget() {
        var light = GPUBudgetMonitor(sourceFPS: 24, displayFPS: 120)
        #expect(light.evaluate(BudgetSample(
            timing: VOPassTiming(totalMilliseconds: 12.0, minimumSampleCount: 49), droppedFrames: 0, uptime: 0)) == .withinBudget)

        var strong = GPUBudgetMonitor(sourceFPS: 24, displayFPS: 120)
        #expect(strong.evaluate(BudgetSample(
            timing: VOPassTiming(totalMilliseconds: 28.2, minimumSampleCount: 78), droppedFrames: 0, uptime: 0)) == .overBudget)
    }

    @Test func aDropBurstIsOverBudgetEvenWithoutTimings() {
        var monitor = GPUBudgetMonitor(sourceFPS: 0, displayFPS: 0)
        #expect(monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 0, uptime: 0)) == .withinBudget)
        #expect(monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 8, uptime: 1)) == .overBudget)
    }

    // RAVU zoom dropped 2 frames while its shader compiled, then none.
    @Test func startUpDropsBelowTheLimitAreTolerated() {
        var monitor = GPUBudgetMonitor(sourceFPS: 0, displayFPS: 0)
        for (second, drops) in [(0.0, 0), (1, 1), (2, 2), (3, 2), (4, 2)] {
            #expect(monitor.evaluate(BudgetSample(timing: nil, droppedFrames: drops, uptime: second)) == .withinBudget)
        }
    }

    @Test func dropsOutsideTheWindowAreForgotten() {
        var monitor = GPUBudgetMonitor(sourceFPS: 0, displayFPS: 0)
        _ = monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 0, uptime: 0))
        _ = monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 2, uptime: 1))
        #expect(monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 4, uptime: 5)) == .withinBudget)
    }

    @Test(arguments: [
        ("vo/gpu-next/libplacebo", "Failed executing hook, disabling\n", true),
        ("vo/gpu-next/libplacebo", "Failed creating render pass for dispatch\n", false),
        ("cplayer", "Failed executing hook, disabling\n", false),
    ])
    func recognisesOnlyTheLibplaceboHookFailure(prefix: String, text: String, expected: Bool) {
        #expect(GPUBudgetMonitor.isShaderFailure(prefix: prefix, text: text) == expected)
    }
}
```

- [ ] **Step 2: Confirm the tests fail**

Run the test command with suite `GPUBudgetMonitorTests`, then the read-result commands.

Expected: `** TEST FAILED **`, with an `error:` line containing `cannot find 'VOPassTiming' in scope`. This failure is intended. Go on to Step 3.

- [ ] **Step 3: Create `GPUBudgetMonitor.swift`**

Create `Aagedal Media Player/Logic/MPV/GPUBudgetMonitor.swift` with exactly this content. The extension must be `nonisolated extension`. A plain `extension` gets `MainActor` isolation in this target, and the tests would then fail to compile with `call to main actor-isolated initializer 'init(json:)' in a synchronous nonisolated context`.

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// GPU time per fresh frame, from mpv's `vo-passes` property.
nonisolated struct VOPassTiming: Equatable, Sendable {
    /// Sum of every fresh pass's average, in milliseconds.
    let totalMilliseconds: Double
    /// The fewest samples any fresh pass has. libplacebo keeps samples per
    /// pass and starts again from zero when a shader stack changes, so a low
    /// count means the averages still include the shader compile.
    let minimumSampleCount: Int
}

nonisolated extension VOPassTiming {
    /// Parses `vo-passes` read as a string. mpv prints node properties with
    /// `json_write`, and every time is in nanoseconds.
    init?(json: String) {
        struct Pass: Decodable { let avg: Int64; let count: Int64 }
        struct Passes: Decodable { let fresh: [Pass] }
        guard let passes = try? JSONDecoder().decode(Passes.self, from: Data(json.utf8)),
              let fewest = passes.fresh.map(\.count).min() else { return nil }
        self.init(
            totalMilliseconds: Double(passes.fresh.reduce(0) { $0 + $1.avg }) / 1_000_000,
            minimumSampleCount: Int(fewest)
        )
    }
}

/// One once-a-second reading taken while playing.
nonisolated struct BudgetSample: Sendable {
    let timing: VOPassTiming?
    /// mpv's `frame-drop-count`. Frames dropped by the VO under `framedrop=vo`.
    let droppedFrames: Int
    /// `ProcessInfo.systemUptime` when the sample was taken.
    let uptime: TimeInterval
}

/// Decides whether the active shader tier fits the GPU.
///
/// The budget is half the frame period of the slower of source and display,
/// because fresh frames are needed only at that rate. The 0.5 comes from
/// measurement: at 24 fps, ArtCNN C4F32 dropped frames while using 68% of
/// the period, and C4F16 at 29% did not. The drop counter backs the timing
/// up, because `vo-passes` misses queueing and presentation cost.
nonisolated struct GPUBudgetMonitor: Sendable {
    enum Verdict: Equatable, Sendable { case warmingUp, withinBudget, overBudget }

    static let budgetFraction = 0.5
    static let warmUpSamples = 30
    static let dropLimit = 3
    static let dropWindow: TimeInterval = 2

    /// `nil` when neither frame rate is known. Only drops count then.
    let budgetMilliseconds: Double?
    private var dropHistory: [(uptime: TimeInterval, count: Int)] = []

    init(sourceFPS: Double, displayFPS: Double) {
        let slowest = [sourceFPS, displayFPS].filter { $0.isFinite && $0 > 0 }.min()
        budgetMilliseconds = slowest.map { Self.budgetFraction * 1000 / $0 }
    }

    mutating func evaluate(_ sample: BudgetSample) -> Verdict {
        dropHistory.append((sample.uptime, sample.droppedFrames))
        dropHistory.removeAll { sample.uptime - $0.uptime > Self.dropWindow }
        if let oldest = dropHistory.first, sample.droppedFrames - oldest.count >= Self.dropLimit {
            return .overBudget
        }
        guard let budget = budgetMilliseconds, let timing = sample.timing else { return .withinBudget }
        guard timing.minimumSampleCount >= Self.warmUpSamples else { return .warmingUp }
        return timing.totalMilliseconds > budget ? .overBudget : .withinBudget
    }

    /// libplacebo logs this at error level when a user shader fails, and then
    /// skips the hook every frame without further notice (`renderer.c:1103`).
    static func isShaderFailure(prefix: String, text: String) -> Bool {
        prefix == "vo/gpu-next/libplacebo" && text.hasPrefix("Failed executing hook")
    }
}
```

- [ ] **Step 4: Confirm the tests pass**

Run the test command with suite `GPUBudgetMonitorTests`, then the read-result commands.

Expected: `** TEST SUCCEEDED **` and `passed 13 failed 0 skipped 0`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/GPUBudgetMonitor.swift" "Aagedal Media Player Tests/GPUBudgetMonitorTests.swift"
git commit -m "Add the GPU budget monitor for shader tiers"
```

---

### Task 4: Report drawable size changes

The MPVKit fork's `moltenvk` context (patch `0001-player-add-moltenvk-context.patch`) returns `VO_NOTIMPL` from `control` and never emits `VO_EVENT_RESIZE`, so mpv's `osd-width` cannot be trusted. Every real size change goes through `MPVMetalLayer.drawableSize`'s setter, which already filters out MoltenVK's 1×1 writes.

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVMetalLayer.swift`
- Create (test): `Aagedal Media Player Tests/MPVMetalLayerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `nonisolated(unsafe) var onDrawableSizeChange: (@Sendable (CGSize) -> Void)?` on `MPVMetalLayer`. It is called after each accepted size change. It is not called for 1×1 writes or when the size is unchanged. It runs on whichever thread assigned the size.

- [ ] **Step 1: Create the test file**

Create `Aagedal Media Player Tests/MPVMetalLayerTests.swift` with exactly this content:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import CoreGraphics
import Synchronization
import Testing

struct MPVMetalLayerTests {
    private final class SizeLog: Sendable {
        let sizes = Mutex<[CGSize]>([])
    }

    @Test func reportsOnlyAcceptedChanges() {
        let layer = MPVMetalLayer()
        let log = SizeLog()
        layer.onDrawableSizeChange = { size in log.sizes.withLock { $0.append(size) } }

        layer.drawableSize = CGSize(width: 3448, height: 2164)
        layer.drawableSize = CGSize(width: 3448, height: 2164)
        layer.drawableSize = CGSize(width: 1, height: 1)
        layer.drawableSize = CGSize(width: 1920, height: 1080)

        #expect(log.sizes.withLock { $0 } == [CGSize(width: 3448, height: 2164), CGSize(width: 1920, height: 1080)])
    }
}
```

- [ ] **Step 2: Confirm the test fails**

Run the test command with suite `MPVMetalLayerTests`, then the read-result commands.

Expected: `** TEST FAILED **`, with an `error:` line containing `has no member 'onDrawableSizeChange'`. This failure is intended. Go on to Step 3.

- [ ] **Step 3: Add the callback**

In `Aagedal Media Player/Logic/MPV/MPVMetalLayer.swift`:

Find:
```swift
    // Workaround for a MoltenVK that sets the drawableSize to 1x1 to forcefully complete
    // the presentation, this causes flicker and the drawableSize possibly staying at 1x1
    nonisolated override var drawableSize: CGSize {
        get { return super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
```
Replace:
```swift
    /// Called after every accepted drawable size change, on whichever thread
    /// assigned it. Set once, before the layer is handed to mpv.
    nonisolated(unsafe) var onDrawableSizeChange: (@Sendable (CGSize) -> Void)?

    // Workaround for a MoltenVK that sets the drawableSize to 1x1 to forcefully complete
    // the presentation, this causes flicker and the drawableSize possibly staying at 1x1
    nonisolated override var drawableSize: CGSize {
        get { return super.drawableSize }
        set {
            guard Int(newValue.width) > 1 && Int(newValue.height) > 1 else { return }
            let old = super.drawableSize
            super.drawableSize = newValue
            if super.drawableSize != old { onDrawableSizeChange?(super.drawableSize) }
        }
    }
```

- [ ] **Step 4: Confirm the test passes**

Run the test command with suite `MPVMetalLayerTests`, then the read-result commands.

Expected: `** TEST SUCCEEDED **` and `passed 1 failed 0 skipped 0`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVMetalLayer.swift" "Aagedal Media Player Tests/MPVMetalLayerTests.swift"
git commit -m "Report drawable size changes from the Metal layer"
```

---

### Task 5: Wire automatic tiers into MPVPlayer

**Files:**
- Modify: `Aagedal Media Player/Logic/AppSettings.swift`
- Modify: `Aagedal Media Player/Logic/AppCommand.swift`
- Modify: `Aagedal Media Player/UI/ContentViewCommandHandlers.swift`
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`
- Modify (test): `Aagedal Media Player Tests/RenderTierTests.swift`

**Interfaces:**
- Consumes:
  - From Task 2: `RenderTier`, `TierSelector.select(ratio:available:floor:)`, `TierSelector.upscaleRatio(source:drawable:)`, `ShaderLibrary.shaderPaths(named:)`, `ShaderLibrary.missingShaderNames(named:)`.
  - From Task 3: `GPUBudgetMonitor`, `BudgetSample`, `VOPassTiming(json:)`, `GPUBudgetMonitor.isShaderFailure(prefix:text:)`.
  - From Task 4: `MPVMetalLayer.onDrawableSizeChange`.
- Produces:
  - `AppSettings.enhance`: `AppSetting<Bool>`, key `"enhance"`, default `false`.
  - `AppCommand.setEnhance(Bool)`.
  - On `MPVPlayer`:
    - `@Published private(set) var activeTier: RenderTier`
    - `@Published private(set) var isTierSteppedDown: Bool`
    - `func setEnhanceEnabled(_ enabled: Bool)`

- [ ] **Step 1: Add the failing test**

In `Aagedal Media Player Tests/RenderTierTests.swift`:

Find:
```swift
        #expect(library.missingShaderNames(named: names) == ["ArtCNN_C4F16.glsl"])
    }
}
```
Replace:
```swift
        #expect(library.missingShaderNames(named: names) == ["ArtCNN_C4F16.glsl"])
    }

    @Test func enhanceIsOffByDefault() {
        #expect(AppSettings.enhance.key == "enhance")
        #expect(AppSettings.enhance.defaultValue == false)
    }
}
```

Run the test command with suite `RenderTierTests`, then the read-result commands.

Expected: `** TEST FAILED **`, with an `error:` line containing `has no member 'enhance'`. This failure is intended.

- [ ] **Step 2: Add the setting**

In `Aagedal Media Player/Logic/AppSettings.swift`, first edit:

Find:
```swift
    static let shaderDirectory = AppSetting(key: "shaderDirectory", defaultValue: "")
```
Replace:
```swift
    static let shaderDirectory = AppSetting(key: "shaderDirectory", defaultValue: "")
    /// Picks a shader tier automatically from the upscale ratio and GPU
    /// headroom. Off by default so the picture stays faithful to the source.
    static let enhance = AppSetting(key: "enhance", defaultValue: false)
```

Second edit, in the same file:

Find:
```swift
            shaderDirectory.key: shaderDirectory.defaultValue,
```
Replace:
```swift
            shaderDirectory.key: shaderDirectory.defaultValue,
            enhance.key: enhance.defaultValue,
```

- [ ] **Step 3: Add the command and its handler**

In `Aagedal Media Player/Logic/AppCommand.swift`:

Find:
```swift
    case setRenderProfile(RenderProfile)
```
Replace:
```swift
    case setRenderProfile(RenderProfile)
    case setEnhance(Bool)
```

In `Aagedal Media Player/UI/ContentViewCommandHandlers.swift`:

Find:
```swift
                controller.mpvPlayer?.setRenderProfile(profile)
            }
```
Replace:
```swift
                controller.mpvPlayer?.setRenderProfile(profile)
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .setEnhance(let enabled) = command else { return }
                // Global preference, like the render profile: every window follows it.
                controller.mpvPlayer?.setEnhanceEnabled(enabled)
            }
```

- [ ] **Step 4: Add the tier state to `MPVPlayer`**

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`:

Find:
```swift
    private(set) var renderProfile: RenderProfile = .off
```
Replace:
```swift
    private(set) var renderProfile: RenderProfile = .off

    /// The automatic tier in effect. `.faithful` whenever Enhance is off or a
    /// manual profile other than Faithful is chosen.
    @Published private(set) var activeTier: RenderTier = .faithful

    /// True when the GPU monitor forced a lighter tier than the ratio allows.
    @Published private(set) var isTierSteppedDown = false

    /// The heaviest tier allowed after GPU step-downs. Reset for each file.
    private var tierFloor: RenderTier = .artcnnStrong
    /// Tiers whose shaders libplacebo rejected. Kept for this player's lifetime.
    private var brokenTiers: Set<RenderTier> = []
    private var drawableSize: CGSize = .zero
    private var displayRefreshRate: Double = 0
    private var budgetMonitor = GPUBudgetMonitor(sourceFPS: 0, displayFPS: 0)
    private var tierReselection: Task<Void, Never>?
    private var budgetSampling: Task<Void, Never>?
```

- [ ] **Step 5: Replace `setRenderProfile` and add the enhancement logic**

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`:

Find:
```swift
    /// Switches the shader stack on a running player.
    ///
    /// The list is cleared and rebuilt one path at a time so a directory
    /// containing mpv's list separator cannot corrupt the stack here.
    func setRenderProfile(_ profile: RenderProfile) {
        renderProfile = profile
        UserDefaults.standard.set(profile.rawValue, for: AppSettings.renderProfile)

        guard mpv != nil else { return }

        command("change-list", args: ["glsl-shaders", "clr", ""])
        for path in shaderLibrary.shaderPaths(for: profile) {
            command("change-list", args: ["glsl-shaders", "append", path])
        }
        setFlag("deband", profile.enablesDeband)
        for (name, value) in profile.scaleOptions {
            setString(name, value)
        }
    }
```
Replace:
```swift
    /// Switches the shader stack on a running player.
    func setRenderProfile(_ profile: RenderProfile) {
        renderProfile = profile
        UserDefaults.standard.set(profile.rawValue, for: AppSettings.renderProfile)

        guard mpv != nil else { return }

        applyShaderStack(
            paths: shaderLibrary.shaderPaths(for: profile),
            scaleOptions: profile.scaleOptions,
            deband: profile.enablesDeband
        )
        activeTier = .faithful
        isTierSteppedDown = false
        updateBudgetSampling()
        reselectTier()
    }

    /// Replaces the shader list one path at a time, so a directory containing
    /// mpv's list separator cannot corrupt it, then sets the scaler options.
    private func applyShaderStack(paths: [String], scaleOptions: [String: String], deband: Bool) {
        command("change-list", args: ["glsl-shaders", "clr", ""])
        for path in paths {
            command("change-list", args: ["glsl-shaders", "append", path])
        }
        setFlag("deband", deband)
        for (name, value) in scaleOptions {
            setString(name, value)
        }
    }

    // MARK: - Automatic Enhancement

    func setEnhanceEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, for: AppSettings.enhance)
        reselectTier()
    }

    private func drawableSizeDidChange(_ size: CGSize) {
        drawableSize = size
        scheduleTierReselection()
    }

    /// A live window resize reports many sizes. Swapping shaders on each one
    /// would recompile them repeatedly, so wait for the size to settle.
    private func scheduleTierReselection() {
        tierReselection?.cancel()
        tierReselection = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.reselectTier()
        }
    }

    private func reselectTier() {
        guard mpv != nil, renderProfile == .off else { return }

        var target = RenderTier.faithful
        var steppedDown = false
        var ratioText = "unknown"
        if UserDefaults.standard.value(for: AppSettings.enhance),
           let source = videoSourceSize,
           let ratio = TierSelector.upscaleRatio(source: source, drawable: drawableSize) {
            ratioText = String(format: "%.3f", ratio)
            let library = shaderLibrary
            let available = Set(RenderTier.allCases.filter { tier in
                !brokenTiers.contains(tier) && library.missingShaderNames(named: tier.shaderFileNames).isEmpty
            })
            target = TierSelector.select(ratio: ratio, available: available, floor: tierFloor)
            steppedDown = target < TierSelector.select(ratio: ratio, available: available, floor: .artcnnStrong)
        }
        isTierSteppedDown = steppedDown
        guard target != activeTier else { return }

        activeTier = target
        applyShaderStack(
            paths: shaderLibrary.shaderPaths(named: target.shaderFileNames),
            scaleOptions: target.scaleOptions,
            deband: false
        )
        budgetMonitor = GPUBudgetMonitor(sourceFPS: getDouble("container-fps"), displayFPS: displayRefreshRate)
        logger.info("Render tier: \(target.displayName, privacy: .public) ratio=\(ratioText, privacy: .public) drawable=\(Int(self.drawableSize.width))x\(Int(self.drawableSize.height))")
        updateBudgetSampling()
    }

    private func stepDownTier(reason: String) {
        guard activeTier != .faithful else { return }
        tierFloor = activeTier.steppedDown
        logger.notice("Render tier \(self.activeTier.displayName, privacy: .public) stepped down: \(reason, privacy: .public)")
        reselectTier()
    }

    private func handleShaderFailure() {
        guard activeTier != .faithful else { return }
        brokenTiers.insert(activeTier)
        stepDownTier(reason: "libplacebo disabled a shader hook")
    }

    /// Samples once a second while a non-faithful tier is active.
    private func updateBudgetSampling() {
        guard activeTier != .faithful else {
            budgetSampling?.cancel()
            budgetSampling = nil
            return
        }
        guard budgetSampling == nil else { return }
        budgetSampling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                guard self.isPlaying, let sample = await self.readBudgetSample() else { continue }
                if self.budgetMonitor.evaluate(sample) == .overBudget {
                    self.stepDownTier(reason: "over GPU budget")
                }
            }
        }
    }

    /// Reads on mpv's queue: `vo-passes` blocks until the VO thread answers,
    /// which can take a whole frame under a heavy shader. The queue also
    /// serializes the read with `destroy()`.
    private nonisolated func readBudgetSample() async -> BudgetSample? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self, let mpv = self.mpv else {
                    continuation.resume(returning: nil)
                    return
                }
                var drops = Int64()
                mpv_get_property(mpv, "frame-drop-count", MPV_FORMAT_INT64, &drops)
                var timing: VOPassTiming?
                if let raw = mpv_get_property_string(mpv, "vo-passes") {
                    timing = VOPassTiming(json: String(cString: raw))
                    mpv_free(raw)
                }
                continuation.resume(returning: BudgetSample(
                    timing: timing,
                    droppedFrames: Int(drops),
                    uptime: ProcessInfo.processInfo.systemUptime
                ))
            }
        }
    }
```

- [ ] **Step 6: Connect the inputs**

Make six edits in `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`.

(a) Stop the tasks on teardown.

Find:
```swift
    func destroy() {
        guard mpv != nil else { return }
```
Replace:
```swift
    func destroy() {
        tierReselection?.cancel()
        budgetSampling?.cancel()
        guard mpv != nil else { return }
```

(b) Receive drawable sizes.

Find:
```swift
    func attachDrawable(_ layer: MPVMetalLayer) {
        metalLayer = layer
```
Replace:
```swift
    func attachDrawable(_ layer: MPVMetalLayer) {
        metalLayer = layer
        drawableSize = layer.drawableSize
        layer.onDrawableSizeChange = { [weak self] size in
            Task { @MainActor in self?.drawableSizeDidChange(size) }
        }
```

(c) Re-select when the source size changes.

Find:
```swift
                                    self.videoAspectRatio = CGFloat(dispW) / CGFloat(dispH)
```
Replace:
```swift
                                    self.videoAspectRatio = CGFloat(dispW) / CGFloat(dispH)
                                    self.scheduleTierReselection()
```

(d) Detect a rejected shader.

Find:
```swift
                            self.logger.error("[mpv/\(prefix, privacy: .public)] \(text, privacy: .public)")
                        }
```
Replace:
```swift
                            self.logger.error("[mpv/\(prefix, privacy: .public)] \(text, privacy: .public)")
                        }
                        if GPUBudgetMonitor.isShaderFailure(prefix: prefix, text: text) {
                            DispatchQueue.main.async { [weak self] in self?.handleShaderFailure() }
                        }
```

(e) Give each new file the whole ladder again.

Find:
```swift
                        self.isFileLoaded = true
```
Replace:
```swift
                        self.isFileLoaded = true
                        // A new file gets the whole ladder back. Broken tiers stay excluded.
                        self.tierFloor = .artcnnStrong
                        self.reselectTier()
```

(f) Remember the display refresh rate.

Find:
```swift
        guard fps > 0 else { return }
        setString("display-fps-override", String(format: "%.3f", fps))
```
Replace:
```swift
        guard fps > 0 else { return }
        displayRefreshRate = fps
        setString("display-fps-override", String(format: "%.3f", fps))
```

- [ ] **Step 7: Run the new test**

Run the test command with suite `RenderTierTests`, then the read-result commands.

Expected: `** TEST SUCCEEDED **`, no `error:` or `warning:` lines, and `passed 20 failed 0 skipped 0`.

- [ ] **Step 8: Run the full suite**

Run the test-everything command, then the read-result commands.

Expected: `** TEST SUCCEEDED **`, no `error:` or `warning:` lines, and `passed 649 failed 0 skipped 5`.

- [ ] **Step 9: Commit**

```bash
git add "Aagedal Media Player/Logic/AppSettings.swift" "Aagedal Media Player/Logic/AppCommand.swift" "Aagedal Media Player/UI/ContentViewCommandHandlers.swift" "Aagedal Media Player/Logic/MPV/MPVPlayer.swift" "Aagedal Media Player Tests/RenderTierTests.swift"
git commit -m "Select and step down render tiers automatically while playing"
```

---

### Task 6: Enhance toggle and tier badge

**Files:**
- Modify: `Aagedal Media Player/UI/RenderSettingsView.swift`
- Create: `Aagedal Media Player/UI/RenderTierBadge.swift`
- Modify: `Aagedal Media Player/UI/PlayerView.swift`

**Interfaces:**
- Consumes:
  - From Task 5: `AppSettings.enhance`, `AppCommand.setEnhance`, `MPVPlayer.activeTier`, `MPVPlayer.isTierSteppedDown`.
  - From Task 2: `RenderTier.displayName`, `RenderTier.shaderFileNames`, `ShaderLibrary.missingShaderNames(named:)`.
- Produces: `struct RenderTierBadge: View`, initialised as `RenderTierBadge(player: MPVPlayer)`.

- [ ] **Step 1: Add the Enhance toggle and move the profile picker under Advanced**

Make four edits in `Aagedal Media Player/UI/RenderSettingsView.swift`.

(a) Find:
```swift
    private var shaderDirectory = AppSettings.shaderDirectory.defaultValue
```
Replace:
```swift
    private var shaderDirectory = AppSettings.shaderDirectory.defaultValue
    @AppStorage(AppSettings.enhance.key)
    private var enhance = AppSettings.enhance.defaultValue
```

(b) Find:
```swift
            Section("Shaders") {
```
Replace:
```swift
            Section("Enhancement") {
                Toggle("Enhance", isOn: $enhance)
                    .onChange(of: enhance) { _, newValue in
                        NotificationCenter.default.post(.setEnhance(newValue))
                    }
                Text("Picks a sharpening or neural upscaling shader from how much the picture is enlarged, and steps down when the GPU cannot keep up. Enhancement alters the image; leave it off for inspection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
```

(c) Find:
```swift
                Text(profile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
```
Replace:
```swift
                Text(profile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if profile != .off {
                    Text("A manual profile other than Faithful overrides Enhance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

(d) Find:
```swift
                Text("Heavier profiles cost GPU time per frame. Chroma reconstruction is cheap at any resolution; the upscaling networks are sized for sub-4K and sub-1080p sources respectively.")
```
Replace:
```swift
                Text("Shaders cost GPU time per frame. With Enhance on, amp measures that cost while playing and drops to a lighter shader when a frame no longer fits.")
```

- [ ] **Step 2: Create the badge**

Create `Aagedal Media Player/UI/RenderTierBadge.swift` with exactly this content. Its style copies `PlaybackSpeedIndicator`.

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Names the automatic shader tier while Enhance is changing the picture.
struct RenderTierBadge: View {
    @ObservedObject var player: MPVPlayer
    @AppStorage(AppSettings.shaderDirectory.key)
    private var shaderDirectory = AppSettings.shaderDirectory.defaultValue

    private var missingShaderNames: [String] {
        ShaderLibrary(directoryPath: shaderDirectory)
            .missingShaderNames(named: RenderTier.allCases.flatMap(\.shaderFileNames))
    }

    var body: some View {
        if player.activeTier != .faithful || player.isTierSteppedDown {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                Text(player.isTierSteppedDown
                     ? "\(player.activeTier.displayName) · stepped down"
                     : player.activeTier.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.75))
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .help(missingShaderNames.isEmpty
                  ? "Enhance is altering the picture."
                  : "Not in the shader folder: \(missingShaderNames.joined(separator: ", "))")
            .accessibilityLabel("Enhancement: \(player.activeTier.displayName)")
        }
    }
}
```

- [ ] **Step 3: Show the badge over the player**

In `Aagedal Media Player/UI/PlayerView.swift`. Compare Mode panels are also `PlayerView`s (`ComparePlayerView.swift` creates two), so each panel gets its own badge.

Find:
```swift
                PlaybackSpeedIndicator(
                    speed: controller.currentPlaybackSpeed,
                    isReversing: controller.isReversing
                )
                Spacer()
```
Replace:
```swift
                PlaybackSpeedIndicator(
                    speed: controller.currentPlaybackSpeed,
                    isReversing: controller.isReversing
                )
                if controller.useMPV, let mpvPlayer = controller.mpvPlayer {
                    RenderTierBadge(player: mpvPlayer)
                }
                Spacer()
```

- [ ] **Step 4: Clean build and full suite**

Run the clean-build command.

Expected: `** BUILD SUCCEEDED **`, and the error/warning `grep` prints nothing.

Run the test-everything command, then the read-result commands.

Expected: `** TEST SUCCEEDED **`, no `error:` or `warning:` lines, and `passed 649 failed 0 skipped 5`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/UI/RenderSettingsView.swift" "Aagedal Media Player/UI/RenderTierBadge.swift" "Aagedal Media Player/UI/PlayerView.swift"
git commit -m "Add the Enhance toggle and the render tier badge"
```

**An automated executor stops here.** Task 7 needs a person at the Mac: it involves clicking in the app, going fullscreen and watching the picture.

---

### Task 7: On-device verification with gaia.mov (performed by a person)

This checks what the unit tests cannot reach: `vo-passes` through the fork's `moltenvk` context, real resize events, and stepping down under load, on the file the enhancement is for.

**Test file:** `/Users/filip/Downloads/Movies/gaia.mov`. Verified with `ffprobe`: ProRes 422 HQ, 1280×720, 30 fps progressive, 10-bit 4:2:2 (`yuv422p10le`), SDR BT.601 (`smpte170m`), 137 Mbit/s, 468 s.

**Expected cost on this Mac.** Measured on 2026-09-30 with `/opt/homebrew/bin/mpv` 0.41.0 / libplacebo 7.360.1 (the versions amp bundles), `--hwdec=videotoolbox --dscale=mitchell --cscale=spline36 --fs`. Fullscreen drawable 3448×2164, so the ratio is min(3448/1280, 2164/720) = 2.694. At 30 fps the budget is 0.5 × 1000/30 = 16.7 ms.

| Tier | Shader | ms/frame | Drops | Fits 16.7 ms |
|---|---|---|---|---|
| Faithful | none | 5.8 | start-up only | yes |
| RAVU zoom | `ravu-zoom-ar-r3.hook` | 10.7 | 0 | yes |
| Sharpened | `SSimSuperRes.glsl` | 11.2 | 0 | yes |
| ArtCNN light | `ArtCNN_C4F16.glsl` | 13.7 | 0 | yes |
| FSRCNNX | `FSRCNNX_x2_16-0-4-1.glsl` | ~16.1 (15.2 sampled + unsampled final pass) | 0 | yes, narrowly |

Since commit `2569bc3` the heaviest tier is FSRCNNX; ArtCNN C4F32 (39.1 ms, no quality gain) was removed.

**Files:**
- Modify: `docs/superpowers/specs/2026-09-30-auto-enhance-tier-design.md` (append "Device results")

- [ ] **Step 1: Build and launch**

```bash
cd /Users/filip/src/amp
xcodebuild build -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: `** BUILD SUCCEEDED **`.

In a second terminal, start the log stream:

```bash
log stream --level info --predicate 'subsystem == "com.aagedal.MediaPlayer" AND category == "MPVPlayer" AND (eventMessage CONTAINS "Render tier" OR eventMessage CONTAINS "mpv/vo")'
```

Launch the build with gaia.mov:

```bash
open -a "$(xcodebuild -project 'Aagedal Media Player.xcodeproj' -scheme 'Aagedal Media Player' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/Aagedal Media Player.app" /Users/filip/Downloads/Movies/gaia.mov
```

- [ ] **Step 2: Set the preferences**

Open Settings (the gear in the control bar, or ⌘,), then the **Rendering** tab:
1. Set **Advanced → Profile** to **Faithful**. The stored profile on this Mac is "Neural upscale — light", and a manual profile other than Faithful overrides Enhance.
2. Turn **Enhance** on.

- [ ] **Step 3: Check each case**

Every tier change logs `Render tier: <name> ratio=<r> drawable=<w>x<h>`. The badge appears at the top left, next to the speed indicator.

| Case | Expected log | Expected badge |
|---|---|---|
| Play gaia.mov in its window | `ratio=` equals min(drawable width/1280, drawable height/720). Tier by the rules: ≤ 1.0 → none (Faithful); > 1.0 and < 1.9 → `RAVU zoom`; ≥ 1.9 → `FSRCNNX` | hidden at Faithful, otherwise the tier name |
| Fullscreen (ratio 2.694) | `Render tier: FSRCNNX` and no step-down (about 16.1 ms against 16.7 ms). If the Mac is warm or throttling, one step-down to `ArtCNN light` is also a pass | "FSRCNNX" (or "ArtCNN light · stepped down") |
| Leave fullscreen while playing | One new `Render tier:` line about 300 ms after the resize ends if the ratio crosses a rule boundary; never heavier than the floor reached so far in this file | matches the logged tier |
| Pause for 10 s, then resume | No step-down lines while paused | unchanged |
| ⌘I, or the Playlist button | The glass panel appears over the picture; the ✕ and ⌘I close it | — |

Pass: the sequence matches, and within one file no tier is entered, stepped down from, and entered again (no oscillation). Judge picture quality yourself by toggling Enhance off and on in the same scene.

- [ ] **Step 4: Check the shader-failure path**

```bash
mkdir -p "$TMPDIR/amp-verify/shaders"
cp ~/.config/mpv/shaders/SSimSuperRes.glsl ~/.config/mpv/shaders/ArtCNN_C4F16.glsl "$TMPDIR/amp-verify/shaders/"
printf '//!HOOK LUMA\n//!BIND HOOKED\nvec4 hook() { return syntax error }\n' > "$TMPDIR/amp-verify/shaders/FSRCNNX_x2_16-0-4-1.glsl"
echo "$TMPDIR/amp-verify/shaders"
```

In Settings → Rendering → Shader Folder, click **Choose…** and pick the printed folder. Play gaia.mov fullscreen.

Expected log, in order:
1. `Render tier: FSRCNNX`
2. `[mpv/vo/gpu-next/libplacebo] Failed executing hook, disabling`
3. `stepped down: libplacebo disabled a shader hook`
4. `Render tier: ArtCNN light`

Afterwards, click **Reset** in Shader Folder.

- [ ] **Step 5: Record the results and commit**

Append a `## Device results (YYYY-MM-DD)` section to the spec. For each case, copy the log lines and write pass or fail. If a case failed, describe what happened instead. Do not change code in this task.

```bash
git add docs/superpowers/specs/2026-09-30-auto-enhance-tier-design.md
git commit -m "docs: record on-device results for automatic render tiers"
```

## Continuation guide (written 2026-09-30 for whoever picks this up)

This section is the handoff. It lists the state, what is open, and how to reproduce every measurement. Everything here was verified on 2026-09-30 unless marked otherwise.

### 1. State of the repository

- Repo `/Users/filip/src/amp`, branch `main`, head `8d8384e` (unpushed). Xcode 27.0, Swift 6.4, macOS 27.0.1, Apple M1 Pro (14-core GPU, 32 GB).
- Last full run: 635 passed, 0 failed, 5 skipped (read with `xcresulttool`, see "Commands used throughout"). Clean build: 0 warnings.
- Uncommitted files that belong to the user, never stage them: `LICENSE` (deleted), `Aagedal Media Player Tests/CompareLiveBackendTests.swift`, `.omc/`.
- Deployment target is macOS 26.0. `appcast.xml` still lists release 1.6.0 with `minimumSystemVersion` 15.0, which is correct for that shipped build. The next release must set 26.0 (the template comment already says so). macOS 15 users stop receiving Sparkle updates from that release on.
- Extra git worktrees exist under `~/src/amp.agent-*` and `.claude/worktrees/`. They are not ours. Leave them.
- `Test Fixtures/Generated/` is gitignored and only exists in the main checkout. Run tests there, never in a fresh worktree.

### 2. What shipped, where it lives

| File | Role |
|---|---|
| `Aagedal Media Player/Logic/MPV/RenderTier.swift` | `RenderTier` ladder (`faithful`, `sharpen`, `ravuZoom`, `artcnnLight`, `fsrcnnx`) and `TierSelector` |
| `Aagedal Media Player/Logic/MPV/GPUBudgetMonitor.swift` | `VOPassTiming` (parses mpv `vo-passes` JSON), `BudgetSample`, `GPUBudgetMonitor` |
| `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` | tier selection, step-down, sampling loop, `setEnhanceEnabled` |
| `Aagedal Media Player/Logic/MPV/MPVMetalLayer.swift` | `onDrawableSizeChange` callback |
| `Aagedal Media Player/UI/RenderTierBadge.swift`, `RenderSettingsView.swift`, `PlayerView.swift` | badge, Enhance toggle, badge placement |
| `Aagedal Media Player/ContentView.swift` | `inspectorPanel` (Liquid Glass card over the picture), gear calls `openSettings()` |
| `Aagedal Media Player/Logic/SparkleUpdater.swift` | `SettingsWindow.openFromAppKit()` for the update alert |
| `docs/superpowers/specs/2026-09-30-auto-enhance-tier-design.md` | design, "Verified facts" |
| `docs/research/2026-09-30-gaia-upscaler-benchmark.md` | benchmark table |
| `docs/research/2026-09-30-openmodeldb-model-survey.md` | OpenModelDB + GitHub survey (heuristic filter, see its header) |

Behaviour in one paragraph: with Enhance on and the manual profile at Faithful, amp computes ratio = min(drawable/source) per axis. Tier rules: ratio ≤ 1.0 faithful; 1.0 < ratio < 1.9 RAVU zoom (else SSimSuperRes); ≥ 1.9 FSRCNNX. Once a second it reads mpv `vo-passes` and `frame-drop-count`. Over budget (sum of fresh-pass averages > 0.5 × frame period of the slower of source and display, or 3+ drops within 2 s) lowers the tier floor one step for the rest of the file. A shader libplacebo rejects is marked broken for the player's lifetime.

### 3. Open work, in priority order

1. **Task 7 (needs a person at the Mac).** Follow Task 7 above with gaia.mov. Expected on this Mac: FSRCNNX at fullscreen (ratio 2.694), about 16.1 ms of a 16.7 ms budget, so it may step down to ArtCNN light when the Mac is warm. Both outcomes are acceptable. Record results in the spec under "Device results".
2. **Headroom of the FSRCNNX tier is thin (16.1 of 16.7 ms).** After Task 7, decide whether the budget fraction (0.5) or the tier order needs a tweak. Do not change it without the Task 7 logs.
3. **RAVU zoom crashes FFmpeg's libplacebo filter** (exit code 139, no message) with `ravu-zoom-ar-r3.hook` via `/Users/filip/ffmpeg-apple-silicon/dist/9.0.1/full/ffmpeg`. mpv 0.41.0 runs the same file fine, so amp is not affected. Open question for the ffmpeg build repo (`/Users/filip/ffmpeg-apple-silicon`, libplacebo 7.360.1). Until fixed, RAVU zoom has a speed number (10.7 ms) but no quality score.
4. **FSRCNNX licence and training data are not stated** in its repo. Check `https://github.com/igv/FSRCNN-TensorFlow` before shipping anything that bundles it. amp does not bundle shaders (users supply the folder), so this only matters for documentation.
5. **Settings window stays opaque.** The user tried a see-through Settings window and rejected it ("not a good look"). The metadata/playlist panel is glass and was approved. Do not re-add glass to `SettingsView`.
6. **Esc does not close the inspector.** An `.onExitCommand` was tried and removed because it did not fire in testing. ⌘I and the ✕ close it. Fixing Esc needs a key handler at the window level (`PlayerView.handleKeyEvent`).
7. **Control bar is cramped with the glass panel open in small windows** (fullscreen button clipped in a 640-point window). Cosmetic, not started.
8. **Better-than-shader quality needs a new project** (see section 5). Needs a brainstorm and a spec before any plan.

### 4. How to reproduce the benchmark

Needs: the ffmpeg build at `/Users/filip/ffmpeg-apple-silicon/dist/9.0.1/full/ffmpeg` (libplacebo 7.360.1, libvmaf), mpv at `/opt/homebrew/bin/mpv` 0.41.0, shaders in `~/.config/mpv/shaders`, `jq`, `gtimeout`. The ffmpeg libplacebo filter needs the Vulkan loader on the dyld path; the repo's own `tools/score_upscale.sh` does the same.

**Privacy rule.** `/Users/filip/Downloads/Movies/gaia.mov` contains explicit personal content. Never extract, view or screenshot its frames, and never put frames in a report. Numbers only. For anything visual (UI work), use a synthetic clip with the same format:

```bash
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 -t 120 -c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le "$TMPDIR/testsrc-720p30-prores.mov"
```

**gaia.mov facts** (`ffprobe`): ProRes 422 HQ, 1280×720, 30 fps progressive, `yuv422p10le`, `smpte170m`, 137 Mbit/s, 468 s, AAC audio.

**A. Quality: 2× reconstruction** (run in a scratch directory):

```bash
export DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib
FF=/Users/filip/ffmpeg-apple-silicon/dist/9.0.1/full/ffmpeg
S=$HOME/.config/mpv/shaders
"$FF" -hide_banner -loglevel error -y -ss 120 -i /Users/filip/Downloads/Movies/gaia.mov -t 10 -an -c:v ffv1 ref720.mkv
"$FF" -hide_banner -loglevel error -y -i ref720.mkv -vf "scale=640:360:flags=bicubic" -c:v ffv1 lr360.mkv
SHADER=ArtCNN_C4F16.glsl   # or none, FSRCNNX_x2_16-0-4-1.glsl, SSimSuperRes.glsl, ...
A=":custom_shader_path=$S/$SHADER"; [ "$SHADER" = none ] && A=""
"$FF" -hide_banner -loglevel error -y -init_hw_device vulkan -i lr360.mkv -vf "libplacebo=w=1280:h=720:upscaler=lanczos:format=yuv422p10le$A" -c:v ffv1 -level 3 -slicecrc 1 "up-$SHADER.mkv"
"$FF" -hide_banner -loglevel error -i "up-$SHADER.mkv" -i ref720.mkv -lavfi "[0:v]setpts=PTS-STARTPTS,format=yuv420p[d];[1:v]setpts=PTS-STARTPTS,format=yuv420p[r];[d][r]libvmaf=log_fmt=json:log_path=v-$SHADER.json:feature=name=psnr|name=float_ssim" -f null -
jq '{vmaf:.pooled_metrics.vmaf.mean, psnr_y:.pooled_metrics.psnr_y.mean, ssim:.pooled_metrics.float_ssim.mean, frames:(.frames|length)}' "v-$SHADER.json"
```

Gotchas found the hard way:
- Put only one output stream in a command. A `filter_complex` that both upscales and feeds libvmaf failed with `Invalid argument`; render to a file first, score second.
- Use `ffv1 -level 3 -slicecrc 1`. A plain ffv1 render of the FSRCNNX output had a corrupt frame (`bytestream end mismatching`) and gave a wrong score (98.031 instead of 98.492).
- `frames` must equal 300. If it differs, discard the run.
- Without `DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib`, ffmpeg prints `Unable to open the libvulkan library!`.
- Caveat: the test input is a synthetic bicubic downscale of the master, not a real 360p source. It ranks shaders; it does not prove how they look on real low-resolution video. VMAF rewards sharpening (ArtCNN C4F16 DS scored 99.995 with a lower SSIM than the neutral model), so judge by PSNR-Y and SSIM together.

**B. Speed: real playback.** Save as `probe3.lua`:

```lua
local n = 0
mp.add_periodic_timer(1, function()
  n = n + 1
  local j = mp.get_property_native("vo-passes")
  local tot, minc = 0, 1e9
  if j and j.fresh then for _, p in ipairs(j.fresh) do tot = tot + p.avg; if p.count < minc then minc = p.count end end end
  if n >= 12 then print(string.format("RESULT total_ms=%.2f mincount=%d drops=%s hwdec=%s osd=%sx%s", tot/1e6, minc, mp.get_property("frame-drop-count"), mp.get_property("hwdec-current"), mp.get_property("osd-width"), mp.get_property("osd-height"))) end
  if n == 15 then mp.command("quit") end
end)
```

```bash
S=$HOME/.config/mpv/shaders
gtimeout 90 /opt/homebrew/bin/mpv --no-config --vo=gpu-next --gpu-api=vulkan --hwdec=videotoolbox --framedrop=vo --dscale=mitchell --cscale=spline36 --fs --start=120 --no-audio --script=probe3.lua --glsl-shaders="$S/ArtCNN_C4F16.glsl" /Users/filip/Downloads/Movies/gaia.mov 2>&1 | rg '^\[probe3\] RESULT' | tail -2
```

For `SSimSuperRes.glsl` add `--scale=ewa_lanczossharp --scaler-resizes-only=no`. The fullscreen drawable on this Mac is 3448×2164 (ratio 2.694 for 1280×720). `mincount=0` means one pass is never sampled (seen with FSRCNNX_x2_16; amp ignores such passes). The probe reads the screen mpv opens on, so run it with the display awake and no other GPU load.

**C. Apple's built-in upscaler** (`VTLowLatencySuperResolutionScalerConfiguration`, probe compiled with `swiftc`):

```swift
import VideoToolbox
typealias C = VTLowLatencySuperResolutionScalerConfiguration
print("supported:", C.isSupported)
print("720p factors:", C.supportedScaleFactors(frameWidth: 1280, frameHeight: 720))
print("360p factors:", C.supportedScaleFactors(frameWidth: 640, frameHeight: 360))
for f in C.supportedScaleFactors { print("factor", f, "maxDim", C.maximumDimension(forSpatialScaleFactor: f), "maxPixels", C.maximumPixelCount(forSpatialScaleFactor: f)) }
```

Result on this Mac: supported; 720p → [1.5]; 360p → [1.5, 2.0]; max source dimension 1280 at 1.5×, 960 at 2×, 480 at 4×. So a 720p source can only reach 1920×1080 with it, and it takes 8-bit 4:2:0 input only (from the SDK headers, `VTFrameProcessor_LowLatencySuperResolutionScaler.h`).

### 5. Results to date (gaia.mov, 10 s from t = 120 s, 300 frames)

| Shader | VMAF | PSNR-Y dB | SSIM | ms/frame fullscreen | drops |
|---|---|---|---|---|---|
| lanczos (Faithful) | 91.323 | 39.407 | 0.99910 | 5.8 | 0 |
| ArtCNN_C4F16 | 98.879 | 43.151 | 0.99940 | 13.7 | 0 |
| ArtCNN_C4F16_DS | 99.995 | 43.156 | 0.99863 | 13.8 | 0 |
| ArtCNN_C4F16_DN | 93.081 | 41.420 | 0.99841 | not measured | — |
| ArtCNN_C4F32 | 98.847 | 43.168 | 0.99939 | 39.1 | about 15/s |
| FSRCNNX_x2_16-0-4-1 | 98.492 | 44.597 | 0.99956 | about 16.1 | 0 |
| FSRCNNX_x2_8-0-4-1 | 97.184 | 42.807 | 0.99677 | 10.6 | 0 |
| SSimSuperRes (+ ewa_lanczossharp) | 97.304 | 41.455 | 0.99891 | 11.2 | 0 |
| ravu-zoom-ar-r3 | not scorable (ffmpeg crash) | — | — | 10.7 | 0 |

The `_DS` and `_DN` ArtCNN variants are not in the ladder: DS sharpens (an enhancement, not a neutral reconstruction), DN softens.

### 6. The neural-model project (not started; needs its own brainstorm and spec)

The user wants amp to use MLX and Metal, modified mpv and ffmpeg, and models from OpenModelDB and GitHub. What is known:

- **OpenModelDB survey** (`docs/research/2026-09-30-openmodeldb-model-survey.md`, produced by a subagent, claims cite sources, filter is heuristic: 246 of 671 records). No live-action-trained model is real-time here. Small RGB models (Compact, SPAN) need about 1.1 TFLOP per 720p frame against a budget of roughly 30–40 GFLOP (derived from ArtCNN C4F16's 12k parameters at 13.7 ms). `2xLiveActionV1_SPAN` is the best content match but licensed CC-BY-NC-SA-4.0, so offline use only. Transformer models (DAT, HAT, SwinIR) are far beyond budget. The only published Apple Silicon data point found was community/vendor: PiperSR (453k parameters, Neural Engine) 22.5 ms for 360p→720p on an M2 Max.
- **No converter** from Compact/SPAN/RealPLKSR to mpv GLSL was found (GitHub code search returned nothing; read as "not found", not "does not exist").
- **Installed on this Mac:** `mlx` 0.31.2, `coremltools` 9.0, `torch` 2.13 (MPS works), chaiNNer, Upscayl. The ffmpeg build has no DNN filters.
- **Architecture constraint:** amp renders through mpv's Vulkan output via MoltenVK. Running a Core ML / MLX model per frame means either an ffmpeg filter (offline or pre-render) or a second render path beside mpv. The earlier 2026-09-12 research (`.claude/worktrees/latest-releases-perf-video-11175f/docs/research/2026-09-12-upscaling-sub-1080p.md`) reached the same conclusion for Apple's own scalers.
- **Realistic options, ranked:** (a) offline pre-render of gaia.mov with a real model (quality ceiling, not real-time); (b) train a small ArtCNN-sized network on live-action data and export it as an mpv shader (the only way to get the right domain at real-time cost; needs training data that the user owns or licenses, and a chaiNNer/ArtCNN export path); (c) Apple's 1.5× scaler as a pre-stage before mpv's own 1.8× scale to the display (limits: 8-bit, 1.5×, unmeasured latency).
- **Rule:** ask the user before downloading any model weights, and show sources, sizes and licences first.

### 7. Facts and gotchas (all cost real time once)

- Swift 6.4 isolation: with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, an `extension` of a `nonisolated` type still gets MainActor isolation. Write `nonisolated extension`. The compiler error reads "call to main actor-isolated initializer ... in a synchronous nonisolated context".
- Count test results from the result bundle (`xcresulttool get test-results summary`), not by counting log lines: with parallel runners, log lines collide and a pass can go missing.
- Swift Testing parameterized tests count once in `xcresulttool` but once per argument in the log, so the two counts differ (635 vs 650).
- Test bundle codesign: a failed compile prints `code object is not signed at all` afterwards. That line is a consequence. Look for the compile `error:` above it.
- `showSettingsWindow:` was removed in macOS 14. Use `@Environment(\.openSettings)`, or `SettingsWindow.openFromAppKit()` outside SwiftUI.
- The moltenvk context in the MPVKit fork (`Sources/BuildScripts/patch/libmpv/0001-player-add-moltenvk-context.patch`, pinned at revision `230c317`) never emits a resize event, so `osd-width` is not reliable. `MPVMetalLayer.drawableSize`'s setter is the source of truth.
- Reading `vo-passes` blocks until the VO thread answers: do it on `MPVPlayer.queue`, never on the main thread.
- amp quits when its last window closes (setting `quitWhenNoOpenedWindow`, default true). A UI test run that closes the window ends the app.
- UI tests with real clicks can change stored preferences. One test run muted playback (`playbackMuted`); check `defaults read com.aagedal.MediaPlayer` afterwards.
- Known flaky tests: `CompareLiveBackendTests` live-decode cases fail intermittently on a deadline (see `docs/handoff-for-claude.md`, "Focus 1"). Re-run once; stop on any other failure.
- Liquid Glass API: `glassEffect(_:in:)` is macOS 26+. The panel uses `.glassEffect(.clear.tint(.black.opacity(0.5)), in: .rect(cornerRadius: 18))` (the user asked for 50% more tint visibility than 0.35).
- Git: no attribution lines in commit messages. Commit messages are plain. Stage files by exact path.

### 8. Confirmed defect: stale budget monitor when a new file opens

Evidence: `MPVPlayer.reselectTier()` has `guard target != activeTier else { return }` before the line that rebuilds `budgetMonitor`. Opening a second file that keeps the same tier therefore keeps the first file's frame rate and drop history. Example: a 24 fps file (budget 20.8 ms) then a 60 fps file (should be 8.3 ms): the old budget stays, so the tier does not step down when it should. Not reproduced in the app yet; found by reading the code.

Fix (two edits in `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`):

Find:
```swift
        budgetMonitor = GPUBudgetMonitor(sourceFPS: getDouble("container-fps"), displayFPS: displayRefreshRate)
        logger.info("Render tier: \(target.displayName
```
Replace:
```swift
        refreshBudgetMonitor()
        logger.info("Render tier: \(target.displayName
```

Find:
```swift
    private func stepDownTier(reason: String) {
```
Replace:
```swift
    /// A new budget for the current file: its frame rate and a clean drop history.
    private func refreshBudgetMonitor() {
        budgetMonitor = GPUBudgetMonitor(sourceFPS: getDouble("container-fps"), displayFPS: displayRefreshRate)
    }

    private func stepDownTier(reason: String) {
```

Then in the `MPV_EVENT_FILE_LOADED` block, directly after `self.reselectTier()`, add `self.refreshBudgetMonitor()`. Check that `container-fps` is already set at `FILE_LOADED` (log it once); if it reads 0 there, move the call to the first `videoParamsDw` event instead.

### 9. Test gap: the MPVPlayer wiring has no automated test

Only the pure types (`TierSelector`, `GPUBudgetMonitor`, `VOPassTiming`, `MPVMetalLayer` callback) are tested. `reselectTier`, `stepDownTier`, `handleShaderFailure`, the floor reset per file, and `brokenTiers` are covered only by Task 7, by hand. Sections 8 and 10 are both bugs of that kind. Proposed design step (needs a short spec before anyone codes it): extract a pure `TierController` value type whose inputs are events (`drawableChanged`, `sourceChanged`, `enhanceToggled`, `fileLoaded`, `budgetVerdict`, `shaderFailed`) and whose outputs are tier changes, so the state machine can be tested without mpv. `MPVPlayer` would only apply its outputs.

### 10. HDR and wide-gamut content is not gated

Evidence: `reselectTier()` never looks at the colour encoding, although `MPVPlayer` already publishes `videoGamma` and `videoSigPeak`. The shaders (ArtCNN, FSRCNNX, RAVU, SSimSuperRes) work on the luma plane in its source encoding and were written for SDR; how they behave on PQ or HLG luma has not been measured. Do not guess; measure, then gate.

1. Make a PQ test clip (recipe verified on 2026-09-30 to produce `hevc, yuv420p10le, smpte2084, bt2020` with the ffmpeg build at `/Users/filip/ffmpeg-apple-silicon/dist/9.0.1/full/ffmpeg`):

```bash
ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 -t 10 \
  -vf "format=yuv420p10le,zscale=tin=bt709:t=smpte2084:pin=bt709:p=bt2020:min=bt709:m=bt2020nc,format=yuv420p10le" \
  -c:v libx265 -x265-params "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:log-level=error" hdr-test.mp4
```

2. Play it fullscreen in amp with Enhance on and look for banding, halos or brightness shifts against Enhance off. A person must judge this.
3. If it looks wrong, gate in `reselectTier()`: treat `HDRTransferResolver.resolve(colorTransfer: videoGamma) != .sdr` as "no enhancement". `HDRTransferResolver` already exists (`Aagedal Media Player/Logic/Scopes/HDRTransferResolver.swift`) and its own doc says it maps mpv's `video-params/gamma`. mpv documents those strings as "subject to change", so reuse the resolver instead of comparing strings yourself. Add a Swift Testing case for it.

### 11. Verified: screenshots, scopes and the loupe do not see the enhancement

amp captures frames with `screenshot-raw` (`MPVPlayer.screenshotRaw`, used by `FrameCapture` for the scopes and the loupe). On 2026-09-30, with standalone mpv 0.41.0 (same options as amp, fullscreen, drawable 3448×2164) on the synthetic ProRes clip, `screenshot-raw` with `FSRCNNX_x2_16-0-4-1.glsl` loaded and without any shader returned byte-identical data (1280×720, `bgr0`, same md5). `screenshot-to-file … video` was identical too, while `… window` differed (3448×2164, enhanced). So for an inspection player the measurement paths stay faithful to the source. Limits: one shader (FSRCNNX), standalone mpv rather than amp itself, one clip. Repeat with `ArtCNN_C4F16.glsl` and `ravu-zoom-ar-r3.hook`, then once inside amp (scopes with Enhance on and off on the same paused frame), before relying on it in docs.

Script used (`shot.lua`; run with `OUT=<file>`):

```lua
mp.register_event("file-loaded", function()
  mp.add_timeout(3, function()
    local r = mp.command_native({"screenshot-raw"})
    local f = io.open(os.getenv("OUT"), "wb"); f:write(r.data); f:close()
    print("RAW", r.w, r.h, r.stride, r.format)
    mp.command("quit")
  end)
end)
```

```bash
OUT=raw.bin mpv --no-config --vo=gpu-next --gpu-api=vulkan --hwdec=videotoolbox --fs --pause --start=10 --no-audio --script=shot.lua --glsl-shaders=$HOME/.config/mpv/shaders/FSRCNNX_x2_16-0-4-1.glsl clip.mov
md5 -q raw.bin
```

Because this makes the picture on screen differ from what the scopes measure, the UI should say so. Suggestion: add one line to the Enhance description in Settings ("Scopes, loupe and screenshots always use the original pixels.") only after the repeat above passes.

### 12. Other risks and ideas, not started

Each needs a decision before it becomes a task.

- **No quick A/B.** Enhance can only be toggled in Settings. A menu item with a shortcut (View menu, routed through `AppCommand.setEnhance`) would make quality comparison instant. `rg setEnhance` shows the command is only posted from `RenderSettingsView`.
- **Thermal and power state.** The monitor reacts to dropped frames, which come late. `ProcessInfo.processInfo.thermalState` (`.serious`, `.critical`) and `ProcessInfo.processInfo.isLowPowerModeEnabled` are available inputs for an earlier step-down. The earlier research noted about 30% less throughput on ProMotion fullscreen after heat. Untested idea.
- **Compare Mode shares one GPU.** Each player measures only its own passes, so two enhanced panels can each look inside budget while the total is not. The drop counter would still catch it. The Compare row in Task 7 tests this by hand.
- **Shader compile stall when a tier first loads.** The first second after loading a shader reports large summed pass time (81.66 ms for ArtCNN_C4F32 on a 720p24 probe) and mpv issue 12221 documents about 100 ms GLSL→SPIR-V stalls. The warm-up gate hides this from the monitor, but the viewer may see a hitch when Enhance turns on or the tier changes. Measure it with a screen recording before calling it fine.
- **Shader cache crash on macOS.** mpv issue 17422 (shader cache bus error) was reported on libplacebo 7.360.0. amp pins 7.360.1. Unresolved from earlier research: whether `--gpu-shader-cache` is safe and worth enabling on 7.360.1 (cache removes the compile stall, the crash report says it can also crash).
- **HDR/EDR colour hint.** Still open from the earlier research: the mpv manual says `target-colorspace-hint` works on Wayland, D3D11 and winvk, while the MoltenVK path and `VK_EXT_swapchain_colorspace` are both live on macOS. amp never sets `layer.colorspace`. Needs an on-device test with a real HDR file (the clip in section 10 works). Separate spec.
- **Interlaced, anamorphic, rotated sources.** The ratio uses mpv's display size with rotation applied, so anamorphic and rotated files should be correct, but no test file of either kind was used. Interlaced content is not deinterlaced before the shaders in amp's current options (not checked).
- **ProRes RAW and audio-only files** use AVPlayer or no video, so Enhance never applies to them (`useMPV` is false, or `videoSourceSize` is nil, so the selector returns Faithful).
- **Accessibility and appearance for the glass panel.** Untested: System Settings → Accessibility → Display → Reduce Transparency and Increase Contrast, light and dark appearance, and VoiceOver. The ✕ and the badge have accessibility labels.
- **Real low-resolution material.** All quality numbers come from a synthetic bicubic downscale of gaia.mov. Add real low-resolution, non-explicit footage (for example a 480p broadcast capture the user owns) before trusting the ranking beyond this file.
- **Release checklist.** `CHANGELOG.md` has `## [1.6.1] — Unreleased` with an Added section and no entry for Enhance, the glass panel, the control-bar fixes or the macOS 26 minimum. `README.md` does not mention shaders or Enhance (`rg` finds nothing). Write both. Run the preflight in `docs/RELEASE.md` (signing, notarization). Set `sparkle:minimumSystemVersion` to 26.0 in the new `appcast.xml` item. Metal API validation must stay off in the Xcode scheme (MoltenVK issue 2226, see `CLAUDE.md`).
- **Decisions already made, do not re-litigate.** Recorded by the earlier Qwen session in `~/.qwen/projects/-Users-filip-src/memory/project/` on 2026-09-30: (1) render profiles may only use shaders from `~/.config/mpv/shaders`, never copied from `~/Downloads/AI/Shaders` and never bundled, so `adaptive-sharpen.glsl` (only in Downloads) is out; (2) the default stays inspection-faithful and enhancement is opt-in; (3) selection by upscale ratio is approved. Also: the user prefers cheaper subagent models (Sonnet or Haiku) and low rate-limit use.

### 13. Where to start

1. Run Task 7 (a person). 2. Fix section 8 (small, testable). 3. Do the measurement steps in sections 10 and 11. 4. Fix whatever they find and whatever Task 7 finds; write the section 9 spec if the state machine keeps growing. 5. Commit the results docs. 6. Release checklist in section 12. 7. Only then decide between the neural-model project (section 6) and the polish items in section 3. Do not start the neural-model project without a brainstorm.
