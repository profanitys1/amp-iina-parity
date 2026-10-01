# Plan 4: User-editable key bindings

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let someone rebind the player's keys without recompiling, while every existing default keeps working untouched.

**Architecture:** `PlayerKeyMap` is a compiled switch. Keep it as the source of the *defaults*, but resolve through a loaded `KeyBindingTable` that merges a user file over those defaults. The file is JSON at `~/Library/Application Support/Aagedal Media Player/keybindings.json`, absent by default.

**Tech Stack:** Swift 6, AppKit, Codable.

## Global Constraints

- Deployment target macOS 15.0, Swift 6 strict concurrency.
- Build/test with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`.
- SPDX header on every file; `OSLog` subsystem `com.aagedal.MediaPlayer`; no attribution lines in commits.
- **Every current binding must survive as a default.** The complete inventory is in Task 1; a binding silently lost is a regression.
- **Menu shortcuts stay in SwiftUI.** The 30 `.keyboardShortcut` items in `Aagedal_Media_PlayerApp.swift` are a separate mechanism from the `NSEvent` monitors and are out of scope here — rebinding those needs a different approach and is not attempted.
- **Speed Down and Speed Up must keep no shortcut.** That gap is deliberate: a binding there would collide with the monitor's `[`/`]` rate stepping.
- Do not change `PlayerView.handleKeyEvent`'s evaluation order. Timeline focus, overlay focus and text-input checks run before any binding lookup and must keep doing so.


## Status (2026-10-01): landed on `main`, with a safer lookup than the task text

Commits `e467c4b`, `9033f53`, `29c2928`, `7244940` and `cf7974e`. Full suite: 736 passed, 5 skipped, 0 failed.

**The main difference: overrides only.** The task text resolved every key through a table of exact chords. Today's compiled handler is looser than that table: Shift-P, Shift-F, `{`/`}`, Shift-J/K/L, Shift-Space and others all still act. Replacing the handler would have dropped those, against this plan's own "every current binding must survive" constraint. Instead:
- `KeyBindingTable` holds only what `keybindings.json` says.
- `PlayerView.handleKeyEvent` consults it first, after the focus guards. A chord the file names wins; `""` makes the key do nothing and pass through.
- A chord the file does not name falls through to the unchanged compiled code.
- `KeyBindingDefaults.table` remains the list of rebindable defaults, used to seed a new file.

Other differences:
- **Compare Mode's wipe:** it keeps `[`/`]` while wiping, before any override is consulted.
- **Space:** it stays with a focused overlay control, as before.
- **`KeyChord`:** it maps arrow keys with a switch, because `NSEvent.SpecialKey` is not Sendable.
- **Testable lookup:** the lookup is the pure `PlayerKeyMap.userOverride(…table:)`, unit-tested without touching the real Application Support file.

**Verified on device** with `{ "x": "togglePlayback", "p": "" }`: `x` toggled playback and `p` did nothing. The test file was removed afterwards.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Logic/Input/KeyChord.swift` | **New.** A key plus modifiers, parsed from and rendered to a string like `"shift+cmd+f"`. |
| `Logic/Input/KeyBindingAction.swift` | **New.** The stable string names bindings refer to. |
| `Logic/Input/KeyBindingTable.swift` | **New.** Defaults merged with overrides; the lookup. |
| `Logic/Input/KeyBindingStore.swift` | **New.** Reads and writes the JSON file. |
| `UI/PlayerKeyMap.swift` | Modified. Becomes the default table's source. |
| `UI/PlayerView.swift` | Modified. Consults the table. |

---

### Task 1: The chord type

**Files:**
- Create: `Aagedal Media Player/Logic/Input/KeyChord.swift`
- Test: `Aagedal Media Player Tests/KeyChordTests.swift`

**Interfaces:**
- Produces, used by Tasks 2-4:
  ```swift
  nonisolated struct KeyChord: Hashable, Codable {
      let key: String                  // lowercased character, or "left"/"right"/"up"/"down"/"space"
      let modifiers: Modifiers         // OptionSet: shift, control, option, command
      init?(string: String)            // "shift+cmd+f"
      var stringValue: String
      static func from(characters: String, specialKey: NSEvent.SpecialKey?, flags: NSEvent.ModifierFlags) -> KeyChord?
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/KeyChordTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

final class KeyChordTests: XCTestCase {
    func testBareCharacterRoundTrips() throws {
        let chord = try XCTUnwrap(KeyChord(string: "f"))
        XCTAssertEqual(chord.key, "f")
        XCTAssertTrue(chord.modifiers.isEmpty)
        XCTAssertEqual(chord.stringValue, "f")
    }

    func testModifiersParseInAnyOrderAndRenderCanonically() throws {
        let a = try XCTUnwrap(KeyChord(string: "cmd+shift+o"))
        let b = try XCTUnwrap(KeyChord(string: "shift+cmd+o"))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.stringValue, "shift+cmd+o")
    }

    func testNamedKeysParse() throws {
        XCTAssertEqual(try XCTUnwrap(KeyChord(string: "left")).key, "left")
        XCTAssertEqual(try XCTUnwrap(KeyChord(string: "space")).key, "space")
    }

    func testUppercaseInputIsNormalised() throws {
        XCTAssertEqual(try XCTUnwrap(KeyChord(string: "CMD+F")), try XCTUnwrap(KeyChord(string: "cmd+f")))
    }

    func testEmptyStringIsRejected() {
        XCTAssertNil(KeyChord(string: ""))
        XCTAssertNil(KeyChord(string: "cmd+"))
    }

    func testUnknownModifierIsRejected() {
        XCTAssertNil(KeyChord(string: "hyper+f"))
    }

    func testFromEventComponents() throws {
        let chord = try XCTUnwrap(KeyChord.from(characters: "F", specialKey: nil,
                                                flags: [.shift, .command]))
        XCTAssertEqual(chord.stringValue, "shift+cmd+f")
    }

    func testArrowFromSpecialKey() throws {
        let chord = try XCTUnwrap(KeyChord.from(characters: "", specialKey: .leftArrow, flags: []))
        XCTAssertEqual(chord.stringValue, "left")
    }

    /// Only the four modifiers that matter are recorded; caps lock and function
    /// must not make a chord fail to match.
    func testIrrelevantFlagsAreIgnored() throws {
        let chord = try XCTUnwrap(KeyChord.from(characters: "p", specialKey: nil,
                                                flags: [.capsLock, .function, .numericPad]))
        XCTAssertEqual(chord.stringValue, "p")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/KeyChordTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'KeyChord' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/Input/KeyChord.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One key plus its modifiers, in a form that survives a round trip through a
// configuration file. Modifier order is canonical on the way out so two
// spellings of the same chord compare equal.

import AppKit

nonisolated struct KeyChord: Hashable, Codable {
    struct Modifiers: OptionSet, Hashable, Codable {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1 << 0)
        static let control = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    let key: String
    let modifiers: Modifiers

    private static let modifierNames: [(String, Modifiers)] = [
        ("shift", .shift), ("ctrl", .control), ("alt", .option), ("cmd", .command),
    ]

    private static let specialKeyNames: [NSEvent.SpecialKey: String] = [
        .leftArrow: "left", .rightArrow: "right", .upArrow: "up", .downArrow: "down",
    ]

    init(key: String, modifiers: Modifiers) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    init?(string: String) {
        var parts = string.lowercased().split(separator: "+", omittingEmptySubsequences: false)
                          .map(String.init)
        guard let last = parts.popLast(), !last.isEmpty else { return nil }
        var modifiers: Modifiers = []
        for part in parts {
            guard let match = Self.modifierNames.first(where: { $0.0 == part }) else { return nil }
            modifiers.insert(match.1)
        }
        self.key = last
        self.modifiers = modifiers
    }

    var stringValue: String {
        let names = Self.modifierNames.filter { modifiers.contains($0.1) }.map(\.0)
        return (names + [key]).joined(separator: "+")
    }

    /// Builds a chord from what a key monitor actually reports. Flags beyond the
    /// four that matter — caps lock, function, numeric pad — are discarded, or a
    /// binding would stop matching on a keyboard that sets them.
    static func from(
        characters: String,
        specialKey: NSEvent.SpecialKey?,
        flags: NSEvent.ModifierFlags
    ) -> KeyChord? {
        var modifiers: Modifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }

        if let specialKey, let name = specialKeyNames[specialKey] {
            return KeyChord(key: name, modifiers: modifiers)
        }
        let trimmed = characters.lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed == " " { return KeyChord(key: "space", modifiers: modifiers) }
        return KeyChord(key: trimmed, modifiers: modifiers)
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/KeyChordTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/Input/KeyChord.swift" \
        "Aagedal Media Player Tests/KeyChordTests.swift"
git commit -m "Model a key chord that survives a config file round trip"
```

---

### Task 2: The action names, and the complete default table

**Files:**
- Create: `Aagedal Media Player/Logic/Input/KeyBindingAction.swift`
- Test: `Aagedal Media Player Tests/KeyBindingDefaultsTests.swift`

**Interfaces:**
- Produces, used by Tasks 3-4:
  ```swift
  nonisolated enum KeyBindingAction: String, CaseIterable, Codable {
      case togglePlayback, toggleFullscreen, stepRateForward, stepRateBackward
      case stepFrameForward, stepFrameBackward
      case reverse, fastForward, slowReverse, slowForward
      case setTrimIn, clearTrimIn, jumpToTrimIn
      case setTrimOut, clearTrimOut, jumpToTrimOut, clearAllTrim
      case toggleCompareSource
  }
  nonisolated enum KeyBindingDefaults {
      static let table: [KeyChord: KeyBindingAction]
  }
  ```

**Scope note:** arrow keys are **not** in this table. `PlayerKeyMap.arrowDecision`
encodes a two-axis matrix (action *and* local-versus-broadcast routing) across
eight modifier combinations; flattening that into rebindable chords changes
multi-window behaviour and deserves its own decision. Arrows keep their compiled
path unchanged. Compare Mode's `[`/`]` wipe also stays compiled, because it is
modal — the same key means something else only while wiping.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/KeyBindingDefaultsTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class KeyBindingDefaultsTests: XCTestCase {
    private func action(_ chord: String) -> KeyBindingAction? {
        guard let chord = KeyChord(string: chord) else { return nil }
        return KeyBindingDefaults.table[chord]
    }

    /// Every binding the compiled map had must still be a default.
    func testTransportDefaults() {
        XCTAssertEqual(action("p"), .togglePlayback)
        XCTAssertEqual(action("k"), .togglePlayback)
        XCTAssertEqual(action("space"), .togglePlayback)
        XCTAssertEqual(action("f"), .toggleFullscreen)
        XCTAssertEqual(action("j"), .reverse)
        XCTAssertEqual(action("l"), .fastForward)
        XCTAssertEqual(action("alt+j"), .slowReverse)
        XCTAssertEqual(action("alt+l"), .slowForward)
    }

    func testRateAndFrameDefaults() {
        XCTAssertEqual(action("["), .stepRateBackward)
        XCTAssertEqual(action("]"), .stepRateForward)
        XCTAssertEqual(action("."), .stepFrameForward)
        XCTAssertEqual(action(","), .stepFrameBackward)
    }

    func testTrimDefaults() {
        XCTAssertEqual(action("i"), .setTrimIn)
        XCTAssertEqual(action("alt+i"), .clearTrimIn)
        XCTAssertEqual(action("shift+i"), .jumpToTrimIn)
        XCTAssertEqual(action("o"), .setTrimOut)
        XCTAssertEqual(action("alt+o"), .clearTrimOut)
        XCTAssertEqual(action("shift+o"), .jumpToTrimOut)
        XCTAssertEqual(action("alt+x"), .clearAllTrim)
    }

    func testCompareDefault() {
        XCTAssertEqual(action("b"), .toggleCompareSource)
    }

    /// Command and control are the menu's territory; the monitor must not claim them.
    func testCommandAndControlAreNotBound() {
        XCTAssertNil(action("cmd+i"))
        XCTAssertNil(action("ctrl+i"))
        XCTAssertNil(action("cmd+p"))
    }

    /// Every action must be reachable, or it cannot be triggered at all.
    func testEveryActionHasADefault() {
        let bound = Set(KeyBindingDefaults.table.values)
        for action in KeyBindingAction.allCases {
            XCTAssertTrue(bound.contains(action), "\(action.rawValue) has no default chord")
        }
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/KeyBindingDefaultsTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'KeyBindingAction' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Aagedal Media Player/Logic/Input/KeyBindingAction.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The rebindable actions, and the defaults they start on. These names are
// written into the user's configuration file, so renaming a case breaks
// existing files — add a new case instead.
//
// Arrow keys are deliberately absent: their behaviour is a matrix of action
// and window routing across eight modifier combinations, and flattening it
// into chords would change multi-window behaviour. Compare Mode's wipe is
// absent for the same kind of reason — it is modal, so the same key means
// something different while wiping.

import Foundation

nonisolated enum KeyBindingAction: String, CaseIterable, Codable {
    case togglePlayback
    case toggleFullscreen
    case stepRateForward
    case stepRateBackward
    case stepFrameForward
    case stepFrameBackward
    case reverse
    case fastForward
    case slowReverse
    case slowForward
    case setTrimIn
    case clearTrimIn
    case jumpToTrimIn
    case setTrimOut
    case clearTrimOut
    case jumpToTrimOut
    case clearAllTrim
    case toggleCompareSource
}

nonisolated enum KeyBindingDefaults {
    /// Exactly the bindings the compiled key map had, so nothing is lost.
    static let table: [KeyChord: KeyBindingAction] = {
        var table: [KeyChord: KeyBindingAction] = [:]
        func bind(_ chord: String, _ action: KeyBindingAction) {
            guard let chord = KeyChord(string: chord) else {
                assertionFailure("Malformed default chord: \(chord)")
                return
            }
            table[chord] = action
        }
        bind("p", .togglePlayback)
        bind("k", .togglePlayback)
        bind("space", .togglePlayback)
        bind("f", .toggleFullscreen)
        bind("]", .stepRateForward)
        bind("[", .stepRateBackward)
        bind(".", .stepFrameForward)
        bind(",", .stepFrameBackward)
        bind("j", .reverse)
        bind("l", .fastForward)
        bind("alt+j", .slowReverse)
        bind("alt+l", .slowForward)
        bind("i", .setTrimIn)
        bind("alt+i", .clearTrimIn)
        bind("shift+i", .jumpToTrimIn)
        bind("o", .setTrimOut)
        bind("alt+o", .clearTrimOut)
        bind("shift+o", .jumpToTrimOut)
        bind("alt+x", .clearAllTrim)
        bind("b", .toggleCompareSource)
        return table
    }()
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/KeyBindingDefaultsTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/Input/KeyBindingAction.swift" \
        "Aagedal Media Player Tests/KeyBindingDefaultsTests.swift"
git commit -m "Name the rebindable actions and their defaults

The defaults are exactly the bindings the compiled map had. Arrows and the
Compare wipe stay compiled: one is a routing matrix, the other is modal."
```

---

### Task 3: Merging a user file over the defaults

**Files:**
- Create: `Aagedal Media Player/Logic/Input/KeyBindingTable.swift`
- Create: `Aagedal Media Player/Logic/Input/KeyBindingStore.swift`
- Test: `Aagedal Media Player Tests/KeyBindingTableTests.swift`

**Interfaces:**
- Produces, used by Task 4:
  ```swift
  nonisolated struct KeyBindingTable {
      static let defaults: KeyBindingTable
      init(overrides: [String: String])
      func action(for chord: KeyChord) -> KeyBindingAction?
  }
  @MainActor final class KeyBindingStore {
      static let shared: KeyBindingStore
      private(set) var table: KeyBindingTable
      var fileURL: URL { get }
      func reload()
      func writeDefaultFileIfMissing() throws
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/KeyBindingTableTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class KeyBindingTableTests: XCTestCase {
    private func chord(_ string: String) -> KeyChord { KeyChord(string: string)! }

    func testNoOverridesMatchesDefaults() {
        let table = KeyBindingTable(overrides: [:])
        XCTAssertEqual(table.action(for: chord("p")), .togglePlayback)
    }

    func testOverrideReplacesADefault() {
        let table = KeyBindingTable(overrides: ["x": "togglePlayback"])
        XCTAssertEqual(table.action(for: chord("x")), .togglePlayback)
        // The default is still there — rebinding adds, it does not move.
        XCTAssertEqual(table.action(for: chord("p")), .togglePlayback)
    }

    /// Mapping a chord to nothing is how a default is removed.
    func testEmptyActionUnbindsADefault() {
        let table = KeyBindingTable(overrides: ["p": ""])
        XCTAssertNil(table.action(for: chord("p")))
    }

    /// A typo must not take a working binding down with it.
    func testUnknownActionNameIsIgnored() {
        let table = KeyBindingTable(overrides: ["p": "teleport"])
        XCTAssertEqual(table.action(for: chord("p")), .togglePlayback)
    }

    func testMalformedChordIsIgnored() {
        let table = KeyBindingTable(overrides: ["hyper+q": "reverse"])
        XCTAssertEqual(table.action(for: chord("j")), .reverse)
    }

    func testOverrideOnAModifiedChord() {
        let table = KeyBindingTable(overrides: ["shift+cmd+k": "clearAllTrim"])
        XCTAssertEqual(table.action(for: chord("cmd+shift+k")), .clearAllTrim)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/KeyBindingTableTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: `cannot find 'KeyBindingTable' in scope`.

- [ ] **Step 3: Write the table**

Create `Aagedal Media Player/Logic/Input/KeyBindingTable.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The defaults with the user's file merged over them. A malformed chord or an
// unknown action name is skipped rather than fatal: a typo in a config file
// must not take working bindings down with it.

import Foundation
import OSLog

nonisolated struct KeyBindingTable {
    private let bindings: [KeyChord: KeyBindingAction]

    static let defaults = KeyBindingTable(overrides: [:])

    /// - Parameter overrides: chord string to action name. An empty action name
    ///   unbinds that chord.
    init(overrides: [String: String]) {
        let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "keybindings")
        var merged = KeyBindingDefaults.table
        for (chordString, actionName) in overrides {
            guard let chord = KeyChord(string: chordString) else {
                logger.warning("Ignoring unparseable key chord: \(chordString, privacy: .public)")
                continue
            }
            if actionName.isEmpty {
                merged.removeValue(forKey: chord)
                continue
            }
            guard let action = KeyBindingAction(rawValue: actionName) else {
                logger.warning("Ignoring unknown action: \(actionName, privacy: .public)")
                continue
            }
            merged[chord] = action
        }
        bindings = merged
    }

    func action(for chord: KeyChord) -> KeyBindingAction? { bindings[chord] }
}
```

- [ ] **Step 4: Write the store**

Create `Aagedal Media Player/Logic/Input/KeyBindingStore.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Reads keybindings.json from Application Support. The file is absent on a
// fresh install, in which case the defaults stand.

import Foundation
import OSLog

@MainActor
final class KeyBindingStore {
    static let shared = KeyBindingStore()

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "keybindings")
    private(set) var table: KeyBindingTable = .defaults

    var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Aagedal Media Player", isDirectory: true)
            .appendingPathComponent("keybindings.json")
    }

    private init() { reload() }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL) else {
            table = .defaults
            return
        }
        do {
            let overrides = try JSONDecoder().decode([String: String].self, from: data)
            table = KeyBindingTable(overrides: overrides)
            logger.info("Loaded \(overrides.count, privacy: .public) key binding overrides")
        } catch {
            logger.error("keybindings.json could not be read, using defaults: \(error.localizedDescription, privacy: .public)")
            table = .defaults
        }
    }

    /// Writes a fully-populated file the user can edit, if none exists yet.
    func writeDefaultFileIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var contents: [String: String] = [:]
        for (chord, action) in KeyBindingDefaults.table {
            contents[chord.stringValue] = action.rawValue
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(contents).write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 5: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/KeyBindingTableTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add "Aagedal Media Player/Logic/Input/KeyBindingTable.swift" \
        "Aagedal Media Player/Logic/Input/KeyBindingStore.swift" \
        "Aagedal Media Player Tests/KeyBindingTableTests.swift"
git commit -m "Merge a user key-binding file over the defaults

A malformed chord or unknown action name is skipped with a log line rather
than being fatal, so one typo cannot disable the keyboard."
```

---

### Task 4: Resolve through the table

**Files:**
- Modify: `Aagedal Media Player/UI/PlayerKeyMap.swift`
- Modify: `Aagedal Media Player/UI/PlayerView.swift:235` and the `i`/`o`/`x`/`b`/`j`/`k`/`l`/space branches in `handleKeyEvent`
- Test: `Aagedal Media Player Tests/PlayerKeyMapTests.swift` (extend the existing file if present)

**Interfaces:**
- Consumes: `KeyBindingStore.shared.table`, `KeyChord.from(characters:specialKey:flags:)`.
- Produces: `PlayerKeyMap.boundAction(characters:specialKey:modifiers:isWipeMode:) -> KeyBindingAction?`

- [ ] **Step 1: Add the resolver to PlayerKeyMap**

In `Aagedal Media Player/UI/PlayerKeyMap.swift`, add:

```swift
    /// Resolves a key event against the loaded bindings. Compare Mode's wipe
    /// still wins for `[`/`]` while wiping, because it is modal — the binding
    /// table has no way to express "only while in this mode".
    @MainActor
    static func boundAction(
        characters: String,
        specialKey: NSEvent.SpecialKey?,
        modifiers: NSEvent.ModifierFlags,
        isWipeMode: Bool
    ) -> KeyBindingAction? {
        let lower = characters.lowercased()
        let isWipeKey = lower == "[" || lower == "]" || characters == "{" || characters == "}"
        if isWipeMode, isWipeKey { return nil }
        guard let chord = KeyChord.from(characters: characters, specialKey: specialKey,
                                        flags: modifiers) else { return nil }
        return KeyBindingStore.shared.table.action(for: chord)
    }
```

Keep `characterAction(_:modifiers:isWipeMode:)` exactly as it is — the wipe path
still uses it.

- [ ] **Step 2: Consult the table in handleKeyEvent**

In `Aagedal Media Player/UI/PlayerView.swift`, inside `handleKeyEvent`, after the
timeline-focus, overlay-focus and text-input guards and after the existing
Compare-wipe handling, insert the binding lookup **before** the hardcoded
`i`/`o`/`b`/`j`/`k`/`l`/space branches:

```swift
        if let bound = PlayerKeyMap.boundAction(
            characters: characters, specialKey: specialKey,
            modifiers: modifiers, isWipeMode: compareSession.isWipeMode) {
            perform(bound)
            return true
        }
```

Then add `perform(_:)` to the same type, routing each action to the call the
hardcoded branch used to make. Copy the bodies out of the branches you are
replacing rather than rewriting them, then delete those branches:

```swift
    private func perform(_ action: KeyBindingAction) {
        switch action {
        case .togglePlayback: NotificationCenter.default.post(.togglePlayback)
        case .toggleFullscreen: NotificationCenter.default.post(.toggleFullscreen)
        case .stepRateForward: NotificationCenter.default.post(.stepRate(forward: true))
        case .stepRateBackward: NotificationCenter.default.post(.stepRate(forward: false))
        case .stepFrameForward: seekByFrames(1)
        case .stepFrameBackward: seekByFrames(-1)
        case .reverse: NotificationCenter.default.post(.reverse)
        case .fastForward: NotificationCenter.default.post(.fastForward)
        case .slowReverse: NotificationCenter.default.post(.slowReverse)
        case .slowForward: NotificationCenter.default.post(.slowForward)
        case .setTrimIn: controller.setTrimIn()
        case .clearTrimIn: controller.clearTrimIn()
        case .jumpToTrimIn: controller.jumpToTrimIn()
        case .setTrimOut: controller.setTrimOut()
        case .clearTrimOut: controller.clearTrimOut()
        case .jumpToTrimOut: controller.jumpToTrimOut()
        case .clearAllTrim: controller.clearTrimPoints()
        case .toggleCompareSource: compareSession.toggleActiveSource()
        }
    }
```

Match each call to what the removed branch actually did — the method names above
are the ones those branches use; if one differs, use the existing one.

- [ ] **Step 3: Build**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Verify every default by hand**

This is the regression that matters, and no unit test covers the wiring. Open a
file and confirm each of these still does what it did: `p`, `k`, space, `f`,
`[`, `]`, `.`, `,`, `j`, `l`, `⌥j`, `⌥l`, `i`, `⌥i`, `⇧i`, `o`, `⌥o`, `⇧o`,
`⌥x`, `b`. Then, with Compare Mode wiping, confirm `[` and `]` still nudge the
wipe rather than changing rate.

- [ ] **Step 5: Verify an override end to end**

```bash
mkdir -p ~/Library/Application\ Support/Aagedal\ Media\ Player
cat > ~/Library/Application\ Support/Aagedal\ Media\ Player/keybindings.json <<'JSON'
{ "x": "togglePlayback", "p": "" }
JSON
```

Relaunch. `x` must toggle playback and `p` must do nothing. Then delete the file
and relaunch to confirm the defaults come back:

```bash
rm ~/Library/Application\ Support/Aagedal\ Media\ Player/keybindings.json
```

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed [0-9]+ tests|error:|TEST"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add "Aagedal Media Player/UI/PlayerKeyMap.swift" \
        "Aagedal Media Player/UI/PlayerView.swift"
git commit -m "Resolve player keys through the binding table

Every default is unchanged; they now come from a table that a file in
Application Support can override. Compare Mode's wipe still wins for the
bracket keys while wiping, which a flat table cannot express."
```

---

### Task 5: Reveal the file from Settings

**Files:**
- Modify: `Aagedal Media Player/UI/SettingsView.swift` (the `KeyboardShortcutsView` pane, lines 757-845)

- [ ] **Step 1: Add the controls**

`KeyboardShortcutsView` is currently a read-only reference list. Add a section at
its end:

```swift
            Section("Customisation") {
                Text("Key bindings can be overridden in a JSON file. Each entry maps a chord such as \"shift+cmd+f\" to an action name; an empty action removes a binding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Create Bindings File") {
                        try? KeyBindingStore.shared.writeDefaultFileIfMissing()
                        NSWorkspace.shared.activateFileViewerSelecting([KeyBindingStore.shared.fileURL])
                    }
                    Button("Reload Bindings") {
                        KeyBindingStore.shared.reload()
                    }
                }
            }
```

- [ ] **Step 2: Build and try both buttons**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
```

Open Settings, Shortcuts, press Create Bindings File: Finder must reveal a
populated `keybindings.json`. Edit one entry, press Reload Bindings, and confirm
the change takes effect without relaunching.

- [ ] **Step 3: Commit**

```bash
git add "Aagedal Media Player/UI/SettingsView.swift"
git commit -m "Let the bindings file be created and reloaded from Settings"
```

---

## Deliberately not built

A graphical key-binding editor with conflict detection, and rebindable menu
shortcuts. The file plus reload covers the stated need — muscle memory from
another tool — at a fraction of the cost. Build the editor only if editing JSON
turns out to be the actual complaint.
