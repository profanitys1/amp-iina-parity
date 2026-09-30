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

Differences from the task text below: the deployment target is now 26.0, not 15.0, and the inspector is no longer a native `.inspector` column. The Tasks 1–6 sections are kept as the record of what landed. **Do not execute Preconditions or Tasks 1–6 again.** Only Task 7 remains, and it needs a person.

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
| ArtCNN strong | `ArtCNN_C4F32.glsl` | 39.1 | ~15/s | no |

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
| Play gaia.mov in its window | `ratio=` equals min(drawable width/1280, drawable height/720). Tier by the rules: ≤ 1.0 → none (Faithful); > 1.0 and < 1.9 → `RAVU zoom`; ≥ 1.9 → `ArtCNN strong`, then a step-down to `ArtCNN light` | hidden at Faithful, otherwise the tier name |
| Fullscreen (ratio 2.694) | `Render tier: ArtCNN strong`, then within about 3 s `stepped down: over GPU budget`, then `Render tier: ArtCNN light`. No further lines while playing | "ArtCNN light · stepped down" |
| Leave fullscreen while playing | One new `Render tier:` line about 300 ms after the resize ends, never heavier than ArtCNN light (the floor holds until the next file) | matches the logged tier |
| Pause for 10 s, then resume | No step-down lines while paused | unchanged |
| ⌘I, or the Playlist button | The glass panel appears over the picture; the ✕ and ⌘I close it | — |

Pass: the sequence matches, and within one file no tier is entered, stepped down from, and entered again (no oscillation). Judge picture quality yourself by toggling Enhance off and on in the same scene.

- [ ] **Step 4: Check the shader-failure path**

```bash
mkdir -p "$TMPDIR/amp-verify/shaders"
cp ~/.config/mpv/shaders/SSimSuperRes.glsl ~/.config/mpv/shaders/ArtCNN_C4F16.glsl ~/.config/mpv/shaders/ArtCNN_C4F32.glsl "$TMPDIR/amp-verify/shaders/"
printf '//!HOOK LUMA\n//!BIND HOOKED\nvec4 hook() { return syntax error }\n' > "$TMPDIR/amp-verify/shaders/ArtCNN_C4F16.glsl"
echo "$TMPDIR/amp-verify/shaders"
```

In Settings → Rendering → Shader Folder, click **Choose…** and pick the printed folder. Play gaia.mov fullscreen.

Expected log, in order:
1. `Render tier: ArtCNN strong`
2. a step-down over budget
3. `Render tier: ArtCNN light`
4. `[mpv/vo/gpu-next/libplacebo] Failed executing hook, disabling`
5. `stepped down: libplacebo disabled a shader hook`
6. `Render tier: Sharpened` (RAVU zoom is not in this folder, so it counts as unavailable)

Afterwards, click **Reset** in Shader Folder.

- [ ] **Step 5: Record the results and commit**

Append a `## Device results (YYYY-MM-DD)` section to the spec. For each case, copy the log lines and write pass or fail. If a case failed, describe what happened instead. Do not change code in this task.

```bash
git add docs/superpowers/specs/2026-09-30-auto-enhance-tier-design.md
git commit -m "docs: record on-device results for automatic render tiers"
```

## Handoff note

Code for Tasks 1–6 is on `main` (see Status). Next: a person runs Task 7. The MLX / Core ML upscaling idea (models from OpenModelDB and GitHub, benchmarked on gaia.mov) is a separate project. It needs its own brainstorm and spec before any plan, because running models per frame means a render path outside mpv's Vulkan output (see `.claude/worktrees/latest-releases-perf-video-11175f/docs/research/2026-09-12-upscaling-sub-1080p.md`).
