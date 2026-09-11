# IINA-parity chrome, keys and fixture validation — 2026-09-11

The IINA-style player chrome, the rebuilt key layer, and the 37 fixture-gated
tests that had never run in this checkout are covered here by agent-executed
evidence: a green suite at the tip, four fixture-gate falsifications, rendered
and live captures read back as images, and a Release build installed into
`/Applications` and launched with a purpose-built 30 s clip. The branch is
**not merged and not pushed**; the landing procedure is documented at the end
and is explicitly not executed.

## Scope and setup

- Repository `/Users/filip/src/amp`, branch `iina-parity`, HEAD
  `b065b2b` (`Sit the floating card flush with the bottom edge`), 27 commits
  over `upstream/main` (`f30f8cf`, the local snapshot), working tree clean.
- Build and test route: scheme `Aagedal Media Player`, destination
  `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, invoked through `xcodebuild`.
  No `project.pbxproj` change, no scheme change, no version bump:
  `MARKETING_VERSION = 1.6.1` / `CURRENT_PROJECT_VERSION = 163` are the values
  the installed bundle reports.
- Toolchain and host: Xcode 26.6 (17F113), macOS 26.6.2 (25G83), Apple M1 Pro,
  32 GB, arm64.
- Playback engine: `MPVKit-GPL` at revision `230c317` (mpv v0.41.0, FFmpeg
  n8.1.2, no LuaJIT; `Package.swift:94` — "GPL builds with MXF demuxer,
  VVC/APV decoders (MPV 0.41, FFmpeg n8.1.2), no LuaJIT"), plus the app's own
  bundled ffmpeg 9.0.1, sha256
  `dc3770d91735cfe8b0ef8f4eb7c6f8431d722cca0d79c0959d62be216868d604`, equal to
  `checksums/ffmpeg.sha256`.
- Fixture tree: `Test Fixtures/Generated/` (gitignored), produced by
  `scripts/generate-test-fixtures.sh` with ffmpeg 9.0.1 — **35 files: 34 media
  + `MANIFEST.txt`**. `MANIFEST.txt` is three lines:
  `Aagedal Media Player generated media fixtures`, `schema=5`, and
  `ffmpeg=ffmpeg version 9.0.1 Copyright (c) 2000-2026 the FFmpeg developers`.
- Installed IINA used for the key and look comparison: `/Applications/IINA.app`
  **1.5.0-beta1 (build 170)**, preset `IINA Default`
  (`defaults read com.colliderli.iina currentInputConfigName`). The look
  reference is the "Measured from the installed build" section of
  `docs/IINA_OSC_REFERENCE.md` (460 × 80 pt silhouette, **0 pt bottom gap**,
  ≈7.5 pt silhouette corner radius, 39.5 pt title-bar band), not the older
  commit-`a320321` table in the same file.
- Evidence root: `/Users/filip/.omo/evidence/amp-iina-parity-continuation`
  (`$EVID` below).

## Observed results

1. **Pre-change baseline.** 508 passed / 0 failed / 38 skipped, 546 cases:
   `~/Library/Developer/Xcode/DerivedData/Aagedal_Media_Player-dlyzzenbkijroeectcjdibzqfcou/Logs/Test/Test-Aagedal Media Player-2026.09.11_15-48-40-+0200.xcresult`.
   The 38 skips were the 37 fixture-gated tests plus the opt-in disk-image test.
2. **Fixture-only checkpoint at the time of todo 4.** 545 passed / 0 failed /
   1 skipped, 546 cases, `result "Passed"` — `$EVID/task-4-full-suite.xcresult`
   (log `$EVID/task-4-full-suite.log`, roster
   `$EVID/task-4-full-suite.tests.json`). The single skip is
   `CompareReviewDiskFullTests.testRealVolumeExhaustionPreservesSidecarAndAllowsRetry()`.
3. **The 37 previously-skipped fixture tests execute and pass.**
   `$EVID/task-2-fixture-suites-serial.xcresult` — 57 passed / 0 failed /
   0 skipped across `CompareLiveBackendTests`, `ComparisonStillExporterTests`,
   `GeneratedMediaFixtureTests` and `TimelineThumbnailLoaderTests`
   (`$EVID/task-2-fixture-suites-serial.log`). The first two parallel runs of
   the same four classes are recorded too: 56/1/0 each, with the failure moving
   between the two `*ProfileLiveLoupes` tests (`$EVID/task-2-fixture-suites.xcresult`,
   `$EVID/task-2-fixture-suites-r2.xcresult`, analysis in
   `$EVID/task-2-fixes.md` and under Limits below).
4. **Gate falsifications (fresh runs, one gated file moved aside per run).**
   `$EVID/task-2-gate-falsify.log` records all four:
   - `MANIFEST.txt` aside → `GeneratedMediaFixtureTests` 0 passed / **10 skipped**
     (`$EVID/task-2-gate-falsify-manifest.xcresult`);
   - `MANIFEST.txt` aside → `CompareLiveBackendTests` 4 passed / **25 skipped**
     (`$EVID/task-2-gate-falsify-manifest-live.xcresult`) — 35 MANIFEST-gated
     tests in total, which is the count success criterion 1 names;
   - `rotation-par.mp4` aside → `TimelineThumbnailLoaderTests` 5 passed /
     **1 skipped** (`$EVID/task-2-gate-falsify-rotation.xcresult`);
   - `chapters-subtitles-long-gop.mkv` aside → `ComparisonStillExporterTests`
     11 passed / **1 skipped** (`$EVID/task-2-gate-falsify-stills.xcresult`).
   The skip text was recovered from the result bundle and names the generator:
   "Generated media fixtures are unavailable. Run scripts/generate-test-fixtures.sh
   or set MEDIA_FIXTURE_DIR." — `$EVID/task-2-gate-falsify-skip-message.txt`.
   All 35 fixture files were restored after the runs (verified by count).
5. **Smoke decodes of one fixture per group** (durations in seconds) —
   `$EVID/task-1-generate.log:67-77`: `rates/24.mp4` 0.5, `compare/source-a.mov`
   12.0, `loupe/landscape.mp4` 2.0, `hdr10.mp4` 2.0, `multichannel-5.1.m4a` 1.0,
   `chapters-subtitles-long-gop.mkv` 5.0; every clip decodes to a real track
   (`h264`, `hevc`, `alac`, `subrip`). The same six are loaded at runtime by the
   live-backend tests through both the MPV and AVFoundation paths (item 3).
6. **Disk-image harness, fresh on this machine** (macOS 26.6.2 / 25G83; the
   2026-09-10 APFS document was measured on macOS 27.0 / 26A428 and is not
   current-environment evidence):
   `$EVID/diskfull-hfs/status.txt` and `$EVID/diskfull-apfs/status.txt` both
   read `Harness exit status: 0` / `Detach: completed or not mounted`, both
   `Tests.xcresult` report 1 passed / 0 failed / 0 skipped (0.064 s for HFS+,
   `$EVID/diskfull-hfs/tests.json`), and both runs produced a UUID proof token
   (`verified-token.txt`: `9AFE8B37-F69F-4C99-A82F-42FDD794461D` HFS+,
   `8CC6A6C1-AEE0-466A-87E2-2FB150C9C777` APFS). Logs `$EVID/task-3-hfs.log`,
   `$EVID/task-3-apfs.log`, `$EVID/diskfull-*/run.log`. No image is left
   attached (`hdiutil info` shows none) and no `/private/tmp/aagedal-disk-full.*`
   directory remains. The same test stays opt-in in an ordinary run: with no
   `AAGEDAL_DISK_FULL_*` environment it reports 1 skipped with "Requires the
   disposable disk-image harness" — `$EVID/task-3-optin-check.xcresult`,
   `$EVID/task-3-optin.log`.
7. **Final suite at the tip.** `$EVID/task-17-final-suite.xcresult` (log
   `$EVID/task-17-final-suite.log`, roster `$EVID/task-17-final-suite.tests.json`):
   **570 passed / 0 failed / 1 skipped, 571 cases**, `result "Passed"`,
   18:24:40–18:26:46 local. The single skip is
   `CompareReviewDiskFullTests.testRealVolumeExhaustionPreservesSidecarAndAllowsRetry()`.
   N, the number of test methods the new files add, derived at the tip with
   `rg -c 'func test'` over the six files the plan names:
   `IINAParityChromeTests.swift` 3, `PlayerChromeBehaviourTests.swift` 6,
   `OSCDragPersistenceTests.swift` 0 (absent — see Limits),
   `PlayerKeyMapTests.swift` 7, `PlayerArrowKeyMapTests.swift` 6,
   `PlayerKeyWiringTests.swift` 3 → **N = 25**. The roster delta against the
   checkpoint (item 2) is exactly 25 added cases and 0 removed
   (`$EVID/task-17-added-cases.txt`, `$EVID/task-17-final-cases.txt`), matching
   the per-file counts one for one. Arithmetic: total cases 546 + N = **571**,
   passed 545 + N = **570**. (The plan's shorthand `passedTests == 546 + N`
   assumed no skip; the harness mandates exactly one, so the honest identities
   are total = 546 + N and passed = 545 + N with one skip.)
8. **Chrome geometry, mode switch, sidebar, position and subtitle selection.**
   At the tip: `$EVID/task-15-flush-card.xcresult` — 15 passed / 0 failed
   (`IINAParityChromeTests` 3 incl. the rendered-evidence writer,
   `PlayerChromeBehaviourTests` 6, `OSCPositionTests` 6). Earlier acceptance
   runs: `$EVID/task-8-chrome-r9.xcresult` (4 passed; one of those methods, the
   title-bar height test, was later deleted with the filename strip — see
   Limits), `$EVID/task-9-switch-r10.xcresult` (6 passed),
   `$EVID/task-11-oscposition.xcresult` (6 passed),
   `$EVID/task-12-14-regression.xcresult` (96 passed / 0 failed). Each new test
   was shown to fail under a branch perturbation before it was accepted:
   `$EVID/task-9-falsify*.log`, `$EVID/task-12-falsify.log`,
   `$EVID/task-13-falsify.log`, `$EVID/task-14-falsify.log` with their
   `-failures.txt` summaries.
9. **Rendered, live and IINA side-by-side images, judged by reading them.**
   In-process renders `$EVID/chrome/chrome-1x.png` (610 KB) and
   `$EVID/chrome/chrome-2x.png` (2.2 MB); live captures
   `$EVID/live/player-first-frame.png`, `$EVID/live/player.png`,
   `$EVID/live/faded.png`, `$EVID/live/empty.png`,
   `$EVID/live/empty-later.png`; the installed-IINA captures
   `$EVID/iina/iina-osc.png`, `$EVID/iina/iina-no-osc.png`,
   `$EVID/iina/iina-idle.png`, `$EVID/iina/iina-welcome-recents.png`; the
   per-element verdict with measured numbers is
   `$EVID/task-10-visual-verdict.md`. Fresh captures at this tip from the
   **installed Release binary** while it played `$EVID/install-check.mp4`:
   `$EVID/live/installed-card.png`, `$EVID/live/installed-card-2.png` (card
   present; visually read: volume group, transport, toolbar and a
   `00:00 / 00:30` scrubber) and `$EVID/live/installed-faded.png` (chrome gone
   after the pointer left). Measured from `installed-card.png` by row-wise
   saturation inside vs outside the card band
   (`$EVID/task-15-measure-card.swift`, output appended to
   `$EVID/task-15-install.log` §11): silhouette top row 279.0 pt of a 360 pt
   window, silhouette height 162 px = **81.0 pt**, **bottom gap 0 px = 0.0 pt**
   (flush), and the same scan on `installed-faded.png` finds **no card band**,
   so the measurement discriminates. The installed IINA's own numbers, measured
   the same way, are 460.0 × 80.0 pt with a 0.0 pt gap and an ≈8.5 pt
   silhouette radius (`$EVID/iina/iina-osc.png` minus
   `$EVID/iina/iina-no-osc.png`; method and numbers in
   `docs/IINA_OSC_REFERENCE.md`). The card width matches exactly; the 81 pt vs
   80 pt silhouette height is within a point of the installed build, and the
   authored 12 pt corner radius is kept deliberately. The earlier 25 pt bottom
   margin recorded in `task-10-visual-verdict.md` was measured before commit
   `b065b2b` and is superseded by this flush measurement.
10. **Key matrices and runtime wiring.** `$EVID/task-12-keys-r2.xcresult`
    (7 passed: the full character matrix incl. wipe precedence),
    `$EVID/task-13-arrows-r2.xcresult` (11 passed: the 28-cell arrow matrix plus
    `AppCommandTests` and `PlaybackVolumeTests`), `$EVID/task-14-wiring-r2.xcresult`
    (3 passed: real controller state for `stepRate`, volume and pause), and the
    row-by-row documentation audit `$EVID/task-14-shortcut-inventory.txt`
    (45 rows, 0 without a matching registration or handler). The call-site
    ordering rule is asserted, not assumed: the falsification that moved the
    helper call inside the compare-session guard failed the ordering assertion
    and the ordinary-playback test (`$EVID/task-12-falsify-failures.txt`).
11. **Release install into `/Applications`.** `$EVID/task-15-install.log` and
    `$EVID/task-15-shas.txt`: previous installed binary sha256
    `576802ed1f8043e6cc2d050f958064eb012616832efc79c5c36181d36ac3f22a` (its
    provenance from `38d34c7` is an inference from sha + mtime, not proof);
    durable backup at
    `~/Library/Application Support/amp-app-backups/Aagedal Media Player-20260911-181853.app`
    with the same sha256, verified after copying; Release build with
    `-derivedDataPath "$EVID/dd-release"` from `b065b2b` → built binary
    `47becf7b10f663f45f276c3f01d75c0066373ded83011c7b1df23bbe56f3d495`,
    `CFBundleShortVersionString` `1.6.1`, `CFBundleVersion` `163`; staged into
    `/Applications/.Aagedal Media Player.new.app` and its sha verified **before**
    the `rm -rf`/`mv`; installed sha equals the built sha; no staged bundle left
    behind. Launch check with the purpose-built 30.000000 s clip
    `$EVID/install-check.mp4` (ffmpeg `testsrc2` + 440 Hz sine, libx264/aac):
    process alive after 10 s, clean quit 2 s after `osascript`, no leftover
    process (`pgrep` empty).

## Limits and evidence

- **Fixtures are gitignored.** A fresh clone re-skips the **37 fixture-gated
  tests** until `scripts/generate-test-fixtures.sh` is run; the fixture-only
  checkpoint and the tip counts above depend on that generated tree existing.
- **The disk-image test is opt-in and is never covered by the ordinary suite.**
  Its single skip in every full run is deliberate
  (`$EVID/task-3-optin-check.xcresult`); its real coverage is the two harness
  runs in item 6. No claim in this document infers a fixture or disk-image pass
  from the ordinary suite run.
- **The card's drag gesture has no machine coverage.** Three documented
  synthesis routes (window dispatch, application/responder delivery, and real
  `CGEvent` posting) all failed to reach SwiftUI's `DragGesture` in a hosted
  window, so `OSCDragPersistenceTests` was not landed and no commit was made —
  `$EVID/task-11-drag-residual.md`, raw results in
  `$EVID/task-11-attempts/delivery-modes.txt`. What still covers the behaviour:
  `OSCPositionTests` (snap math and clamps, 6 tests), the stored-fraction
  rendering assertion in `IINAParityChromeTests`, and the write → defaults →
  read → `OSCPosition` round trip in `PlayerChromeBehaviourTests`. Not covered
  anywhere by machine: that a real user drag persists a new fraction.
- **The chrome fade is now behaviour-verified at the tip** —
  `$EVID/live/installed-card.png` shows the card, `$EVID/live/installed-faded.png`
  (4.5 s after the pointer left) does not, and the scan finds no card band in
  the second image. The exact constants (`PlayerOverlayController`'s 2.5 s idle
  timeout, `ContentView`'s 0.25 s animation) remain source-verified only.
- **The fixture-gated compare suite is load-sensitive on this machine.** With
  four parallel app instances, one of the two `*ProfileLiveLoupes` tests can
  fail because only 2 of the 3 scope sources get their turn inside the 8 s
  observation window; the same run passes serially and in isolation
  (`$EVID/task-2-fixes.md`). This is an environment characteristic, not a
  product defect: `git log upstream/main..HEAD` over the loupe/scope sources is
  empty, so this branch never touched that machinery. No assertion was changed
  and no skip was added.
- **The installed IINA cannot play the generated fixtures.** IINA 1.5.0-beta1
  aborts with `SIGABRT` (Abort trap: 6) inside libmpv's `copy_image` via
  `gl_video_render_frame` on every generated fixture, and the same stack occurs
  on unrelated files, so it is an IINA/libmpv bug on this OS build rather than a
  fixture defect. Crash reports from the comparison run:
  `~/Library/Logs/DiagnosticReports/IINA-2026-09-11-174840.ips`, `-174854.ips`,
  `-175038.ips`, `-175053.ips`, `-181054.ips`. The same-clip side-by-side was
  therefore impossible; `$EVID/iina/iina-osc.png` shows IINA's OSC on a clip it
  does play, and the caveat is stated in the verdict file. The user's own Movies
  library was never used as a test clip.
- **The live capture path was available, not TCC-blocked.** `screencapture -x -o
  -l <windowID>` plus CGWindowList window resolution worked for the built Debug
  product, the installed Release product and IINA; the pointer warp used for the
  hover state is recorded in `$EVID/task-15-install.log` §11.
- **Deliberate departures from IINA** (recorded, not defects): `⇧←`/`⇧→` stay
  AMP's ±10 s instead of IINA's subtitle seek; the rate step is AMP's additive
  0.5, clamped 0.25…8.0, with no reset binding (`resetPlaybackSpeed` has no
  user-facing shortcut); `⇧↑`/`⇧↓` keep an AMP-specific ±10-frame jump; `q`
  stays unbound in favour of `⌘Q`. Two deliberate *look* departures: the picture
  carries **no filename strip** (IINA shows a 39.5 pt title bar with the
  filename; AMP hides the title text and reaches the name from the Window menu
  and the playlist sidebar), and the card keeps its authored 12 pt corner radius
  even though the installed build's silhouette measures ≈7.5 pt.
- **Not implemented from IINA's default preset**, each group named so nothing is
  silently missing: subtitle seek on `⇧←`/`⇧→`; speed on
  `⌘[`/`⌘]`/`⌥⌘[`/`⌥⌘]`/`⌘\` and any multiplicative speed semantics; chapter
  navigation (`⇧⌘>`/`⇧⌘<`); audio and subtitle delay (`⇧(`/`⇧)`, `Z`/`X`/`C`);
  subtitle scale, position and visibility (`G`/`F`, `r`/`R`/`t`, `v`, `⌥v`);
  loop (`⌘l`/`⌘L`); stop (`⌘.`); window scale (`⌘0`/`⌘1`/`⌘2`); editions (`E`);
  track cycling (`⌃⌘v` video, `⌃⌘s` sub, `⌃⌘a` audio); always-on-top (`⌃⌘t`);
  progress display (`o`/`P`); page seeks (`⇧PGUP`/`⇧PGDN`, ∓600 s); the
  `ESC`/`ENTER` fullscreen pair; mute on `⌘/`; `q` quit; and the media/window
  keys `PLAY`, `PAUSE`, `PLAYPAUSE`, `PLAYONLY`, `PAUSEONLY`, `MUTE`,
  `VOLUME_UP`, `VOLUME_DOWN`, `NEXT`, `PREV`, `STOP`, `FORWARD`, `REWIND`,
  `POWER`, `CLOSE_WIN`. Also excluded by design: the 13 `#@iina`-prefixed menu
  *definitions* in `iina-default-input.conf` (`video-panel`, `audio-panel`,
  `sub-panel`, `playlist-panel`, `chapter-panel`, `fit-to-screen`,
  `smaller-window`, `bigger-window`, `toggle-pip`, `show-current-file-in-finder`,
  `toggle-music-mode`, `live-text`, `find-online-subs`) — they are IINA menu
  accelerators rather than mpv key bindings, and AMP has its own menu structure.
  The parity claim is scoped to the implemented list; it does not assert parity
  with all 78 active bindings in IINA's shipped preset.
- **Accepted known defects.** Compare Mode has had no exit control since commit
  `711fd80`; leave it by opening another file or closing the window. The
  "Comparison Controls" View-menu item and the popover it opened were deleted
  deliberately, so these routes have no UI any more: compare view mode beyond
  A/B, frame resolution, audio source, compared-channel isolation, safe-area and
  aspect-ratio guides, overlay blend, difference gain outside the scope window,
  scope source in overlay mode, B/A alignment offset, and the mismatch and
  audio-layout popovers. The engine APIs behind them remain and are still
  exercised by the live-backend tests.
- **Workspace side effects of the hygiene step.** `.gitignore` now ignores
  `AGENTS.md`, `.claude/` and `.gitnexus/` repo-wide. The GitNexus artifacts were
  deleted after backing up the small files to `$EVID/gitnexus-backup/`; the
  123 MB `.gitnexus/lbug` index and the parse caches were deliberately **not**
  backed up and are not recoverable from this machine's evidence root.
- **This document describes the branch tip `b065b2b` plus this file's own
  commit.** Nothing is merged: `upstream/main` still points at the local
  snapshot `f30f8cf`, and no push, tag, branch switch or rebase was performed.

## Integrated verification

Re-runnable commands (from `/Users/filip/src/amp`; use a fresh
`-resultBundlePath` each time, `xcodebuild` refuses to overwrite one):

```sh
# full suite at the tip
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" \
  -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests" \
  CODE_SIGNING_ALLOWED=NO -resultBundlePath "$EVID/recheck-full.xcresult"

# the four fixture-gated classes (expect 57 passed / 0 skipped with the tree present)
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" \
  -destination "platform=macOS" \
  -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests" \
  -only-testing:"Aagedal Media Player Tests/GeneratedMediaFixtureTests" \
  -only-testing:"Aagedal Media Player Tests/TimelineThumbnailLoaderTests" \
  -only-testing:"Aagedal Media Player Tests/ComparisonStillExporterTests" \
  CODE_SIGNING_ALLOWED=NO -resultBundlePath "$EVID/recheck-fixtures.xcresult"

# the opt-in disk-image harness (fresh artifact dirs; it is not idempotent)
AAGEDAL_DISK_FULL_OUTPUT="$EVID/recheck-hfs" ./scripts/test-compare-review-disk-full.sh
AAGEDAL_DISK_FULL_FILESYSTEM=APFS AAGEDAL_DISK_FULL_OUTPUT="$EVID/recheck-apfs" \
  ./scripts/test-compare-review-disk-full.sh

# suite counts come from the bundle, never from console prose
xcrun xcresulttool get test-results summary --path "$EVID/recheck-full.xcresult" --format json \
  | jq '{passedTests,failedTests,skippedTests,result,totalTestCount}'

# the installed app: binary identity, version, and a launch/quit check
shasum -a 256 "/Applications/Aagedal Media Player.app/Contents/MacOS/Aagedal Media Player"
plutil -extract CFBundleShortVersionString raw "/Applications/Aagedal Media Player.app/Contents/Info.plist"
plutil -extract CFBundleVersion raw "/Applications/Aagedal Media Player.app/Contents/Info.plist"
open -a "/Applications/Aagedal Media Player.app" "$EVID/install-check.mp4"
sleep 10 && pgrep -fl "Aagedal Media Player"
osascript -e 'quit app "Aagedal Media Player"'
```

Landing procedure — **documented, not executed**. It publishes to
`github.com/aagedal/Aagedal-Media-Player` and is the owner's decision:

```sh
git fetch upstream                 # refresh first: see the remote note below
git switch main
git merge --ff-only iina-parity    # clean against the local main f30f8cf: 27 ahead, 0 behind
git push upstream main
```

Remote note recorded at change-set time: the live remote
(`git ls-remote --heads upstream`) reports `refs/heads/main` =
`8ca83ffc7f6dcd0a3aa444d85877342587d8d94c`, an object that does not exist in
this checkout, while the local `upstream/main` and local `main` are still
`f30f8cf`. Nothing in this work fetched, pushed or tagged — there is no
`.git/FETCH_HEAD` in the repository. The fast-forward relation above is verified
against the **local** ref only; after `git fetch upstream`, if the fetched main
is not an ancestor of `iina-parity`, the push will not be a fast-forward and the
owner must reconcile it (merge or rebase) outside this plan's permissions.
