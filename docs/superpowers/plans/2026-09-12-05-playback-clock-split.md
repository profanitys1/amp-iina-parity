# Plan 5: Playback clock split

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `ContentView` re-evaluating its whole body on every playback-clock tick.

**Architecture:** `currentPlaybackTime` is `@Published` on `PlayerController`, which `ContentView` holds as a `@StateObject`. Every tick therefore invalidates a 689-line body and everything inlined in it. Move the clock onto its own small `ObservableObject` that only the four views which display time observe. `PlayerController.currentPlaybackTime` stays as a non-published computed passthrough, so the ~12 logic call sites are untouched.

**Tech Stack:** Swift 6, SwiftUI, Combine.

## Global Constraints

- Deployment target macOS 15.0, Swift 6 strict concurrency.
- Build/test with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`.
- SPDX header on every file; no attribution lines in commits.
- Plan 0 must have landed (the clock is already coalesced to 0.1s while playing; this plan removes the remaining per-tick invalidation).
- Do not change observable behaviour: the timecode, scrubber, waveform playhead and OSC must update exactly as they do now.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Logic/PlaybackClock.swift` | **New.** One `@Published var seconds`. Nothing else. |
| `Logic/PlayerController.swift` | Modified. Owns a `PlaybackClock`; `currentPlaybackTime` becomes a passthrough. |
| `UI/ControlsView.swift` | Modified. Observes the clock. |
| `UI/FloatingOSCView.swift` | Modified. Observes the clock. |
| `UI/AudioWaveformView.swift` | Modified. Observes the clock. |
| `UI/PlayerView.swift` | Modified. `onReceive` reads the clock's publisher. |

**Views that must NOT observe the clock** (they only read it inside closures, so
observing would reintroduce the problem): `ContentView`, `ContentViewCommandHandlers`.

---

### Task 1: The clock object

**Files:**
- Create: `Aagedal Media Player/Logic/PlaybackClock.swift`
- Test: `Aagedal Media Player Tests/PlaybackClockTests.swift`

**Interfaces:**
- Produces, used by Tasks 2-3:
  ```swift
  @MainActor final class PlaybackClock: ObservableObject {
      @Published var seconds: Double
      var publisher: Published<Double>.Publisher { $seconds }
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/PlaybackClockTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class PlaybackClockTests: XCTestCase {
    func testStartsAtZero() {
        XCTAssertEqual(PlaybackClock().seconds, 0)
    }

    func testPublisherDeliversUpdates() {
        let clock = PlaybackClock()
        var received: [Double] = []
        let cancellable = clock.publisher.sink { received.append($0) }
        clock.seconds = 1.5
        clock.seconds = 2.0
        cancellable.cancel()
        XCTAssertEqual(received, [0, 1.5, 2.0])
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/PlaybackClockTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'PlaybackClock' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/PlaybackClock.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The playback position, on its own so that changing it does not invalidate
// every view that happens to observe the player.

import Combine
import Foundation

@MainActor
final class PlaybackClock: ObservableObject {
    @Published var seconds: Double = 0

    var publisher: Published<Double>.Publisher { $seconds }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/PlaybackClockTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/PlaybackClock.swift" \
        "Aagedal Media Player Tests/PlaybackClockTests.swift"
git commit -m "Add a standalone playback clock"
```

---

### Task 2: Move the clock off the controller's change stream

**Files:**
- Modify: `Aagedal Media Player/Logic/PlayerController.swift:68` (the property), `:210` (the publisher)
- Test: `Aagedal Media Player Tests/PlayerClockPassthroughTests.swift`

**Interfaces:**
- Produces: `PlayerController.clock: PlaybackClock` (a `let`).
- Preserved unchanged: `PlayerController.currentPlaybackTime: Double` (get and set)
  and `PlayerController.playbackTimePublisher`. Every existing call site keeps working.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/PlayerClockPassthroughTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class PlayerClockPassthroughTests: XCTestCase {
    func testWritingTheControllerUpdatesTheClock() {
        let controller = PlayerController()
        controller.currentPlaybackTime = 12.5
        XCTAssertEqual(controller.clock.seconds, 12.5)
    }

    func testWritingTheClockIsVisibleOnTheController() {
        let controller = PlayerController()
        controller.clock.seconds = 3.25
        XCTAssertEqual(controller.currentPlaybackTime, 3.25)
    }

    /// The whole point: a clock tick must not tell observers of the controller
    /// that the controller changed.
    func testClockTickDoesNotNotifyControllerObservers() {
        let controller = PlayerController()
        var controllerNotifications = 0
        let cancellable = controller.objectWillChange.sink { _ in controllerNotifications += 1 }
        controller.currentPlaybackTime = 1
        controller.currentPlaybackTime = 2
        cancellable.cancel()
        XCTAssertEqual(controllerNotifications, 0)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/PlayerClockPassthroughTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|failed|Executed"
```

Expected: compile error, no member `clock`.

- [ ] **Step 3: Replace the published property with a passthrough**

In `Aagedal Media Player/Logic/PlayerController.swift`, replace line 68:

```swift
    @Published var currentPlaybackTime: Double = 0
```

with:

```swift
    /// The playback position lives on its own object. It changes up to ten
    /// times a second, and publishing it here would re-evaluate every view that
    /// observes the controller — ContentView included — at that rate.
    let clock = PlaybackClock()

    var currentPlaybackTime: Double {
        get { clock.seconds }
        set { clock.seconds = newValue }
    }
```

Then replace line 210:

```swift
    var playbackTimePublisher: Published<Double>.Publisher { $currentPlaybackTime }
```

with:

```swift
    var playbackTimePublisher: Published<Double>.Publisher { clock.publisher }
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/PlayerClockPassthroughTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Build and confirm no call site broke**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`. The passthrough keeps all twelve existing readers
and writers compiling unchanged.

- [ ] **Step 6: Commit**

```bash
git add "Aagedal Media Player/Logic/PlayerController.swift" \
        "Aagedal Media Player Tests/PlayerClockPassthroughTests.swift"
git commit -m "Take the playback clock off the controller's change stream

The position changes up to ten times a second and every one of those told
every observer of the controller that the controller had changed, which
re-evaluated ContentView's whole body. It now lives on its own object;
currentPlaybackTime stays as a passthrough so no caller had to move."
```

---

### Task 3: Let the four time-displaying views observe the clock

**Files:**
- Modify: `Aagedal Media Player/UI/ControlsView.swift:41-43` (add the property), `:78`, `:166`, `:905`, `:977`
- Modify: `Aagedal Media Player/UI/FloatingOSCView.swift:19` (add), `:102`, `:107`
- Modify: `Aagedal Media Player/UI/AudioWaveformView.swift:10-11` (add), `:201`
- Modify: `Aagedal Media Player/UI/PlayerView.swift:73`

**Interfaces:**
- Consumes: `PlayerController.clock`.

**Why each view needs this:** after Task 2 these views stop redrawing on a tick,
because they observe `controller`, which no longer announces the change. Each
must observe `controller.clock` instead. Missing one leaves a frozen readout —
that is the regression to watch for.

- [ ] **Step 1: Add the observation to ControlsView**

In `Aagedal Media Player/UI/ControlsView.swift`, directly below
`@ObservedObject var compareSession: CompareSessionController` (line 43):

```swift
    /// The clock is a separate object so a tick does not invalidate the whole
    /// window; this view shows the time, so it observes it directly.
    @ObservedObject var clock: PlaybackClock
```

Replace `controller.currentPlaybackTime` with `clock.seconds` at lines 78, 905
and 977, and change line 166 to:

```swift
        .onChange(of: clock.seconds) { _, time in
```

At the second `@ObservedObject var controller: PlayerController` (line 1139),
add the same `clock` property, since that nested view also displays time.

- [ ] **Step 2: Pass the clock in at every ControlsView call site**

```bash
rg -n 'ControlsView\(' --glob '*.swift' .
```

For each hit, add `clock: controller.clock,` to the initialiser call, matching the
`controller:` argument already there.

- [ ] **Step 3: Repeat for FloatingOSCView**

In `Aagedal Media Player/UI/FloatingOSCView.swift`, below line 19:

```swift
    @ObservedObject var clock: PlaybackClock
```

Replace `controller.currentPlaybackTime` with `clock.seconds` at lines 102 and 107.
Then update its call sites:

```bash
rg -n 'FloatingOSCView\(' --glob '*.swift' .
```

- [ ] **Step 4: Repeat for AudioWaveformView**

In `Aagedal Media Player/UI/AudioWaveformView.swift`, below line 11:

```swift
    @ObservedObject var clock: PlaybackClock
```

Replace `controller.currentPlaybackTime` with `clock.seconds` at line 201, then:

```bash
rg -n 'AudioWaveformView\(' --glob '*.swift' .
```

- [ ] **Step 5: PlayerView needs no property**

`PlayerView.swift:73` uses `.onReceive(controller.playbackTimePublisher)`, which
Task 2 already repointed at the clock. Leave it as it is — `onReceive` does not
require observation.

- [ ] **Step 6: Build**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`. A "missing argument for parameter 'clock'" error
means a call site from Steps 2-4 was missed.

- [ ] **Step 7: Verify the readouts still move**

Launch the app, open a file, press play, and confirm by eye that all of these
advance: the timecode in the control bar, the scrubber knob, the floating OSC
time, and — with the waveform window open — the playhead.

```bash
open -a "$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -name 'Aagedal Media Player.app' -path '*Debug*' | head -1)"
```

A frozen readout means that view still reads `controller.currentPlaybackTime`
without observing `clock`.

- [ ] **Step 8: Run the full suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed [0-9]+ tests|error:|TEST"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 9: Commit**

```bash
git add "Aagedal Media Player/UI/ControlsView.swift" \
        "Aagedal Media Player/UI/FloatingOSCView.swift" \
        "Aagedal Media Player/UI/AudioWaveformView.swift"
git commit -m "Observe the clock only where the time is shown

The four views that display playback position take the clock directly.
ContentView does not, which is the point: it no longer re-evaluates its body
when the position changes."
```
