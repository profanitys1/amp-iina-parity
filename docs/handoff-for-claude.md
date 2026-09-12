# Handoff — Aagedal Media Player (`amp`)

Written 2026-09-12 after landing the core-hardening plan. Read this before touching anything.

## Where things stand

- Repo `/Users/filip/src/amp`, branch `main` at `d43d97f`, working tree clean.
- `main` is **54 commits ahead of `upstream/main` and unpushed**. `origin` is the fork
  (`profanitys1/amp-iina-parity`); `origin/iina-parity` is 17 commits behind.
- Local `iina-parity` points at the same commit as `main`. It was kept on purpose: plans 1–5 in
  `docs/superpowers/plans/` each say "Work on branch `iina-parity`".
- Suite state: **613 passed, 0 failed, 5 skipped**, and **zero compiler warnings on a clean build**.

## Focus 1 — the flaky live-decode family (the only real open defect)

Everything else below is cosmetic. This is the thing worth your time.

### What happens

Full-suite runs intermittently fail **one** case inside `CompareLiveBackendTests`. A different case
each time, always a live-decode test that waits for a backend to reach a position. Observed failures:

- `testMPVPrimaryAndAVFoundationSecondaryShareTransport`
- `testMPVPrimaryAndAVFoundationSecondaryCapturePausedLoupesAlongsideScopes`
- `testMPVPrimaryAndAVFoundationSecondaryUseRelativeAlignmentForMismatchedMasters`
- `testAVFoundationPrimaryAndMPVSecondaryRenderLiveComparisonScopes`
- plus `SupportedFrameRates…` and a `LoudnessAnalysisTests` case, reported by other sessions.

### What is already established — do not redo this

- **It is not a regression from the hardening work.** It was observed at `1ac5cd4` and at `562ca3b`
  before the last two commits existed, and one run at `1ac5cd4` failed 3 of 4 attempts.
- **Each case passes in isolation.** `-only-testing:…RenderLiveComparisonScopes -test-iterations 5`
  gave 5/5. Same for others.
- **Load is not a sufficient explanation.** The worst runs happened at load average 16–25 (Spotlight
  re-indexing), but failures also occurred at load ~6.
- The failing witness is always a deadline, not a broken assertion. From an `.xcresult`:
  `CompareLiveBackendTests.swift:1285: XCTAssertTrue failed` where
  `waitUntil(tolerance:)` has `timeout: .seconds(3)` and the observed duration was 3.276 s — the
  helper returns `false` at its deadline, aborting the case. Every earlier assertion in the case passed.

### Where to look

- `Aagedal Media Player Tests/CompareLiveBackendTests.swift` — two `waitUntil` overloads near the
  bottom of the file: `waitUntil(_:timeout:)` defaults to 8 s, `waitUntil(tolerance:timeout:)`
  defaults to **3 s**. The tolerance used by the transport cases is `1.0 / 24.0`.
- The suite runs tests in parallel (several `Aagedal Media Player (<pid>)` runners appear in one log),
  and the long `LoudnessAnalysisTests` cases run 13–40 s concurrently with the live-decode ones.

### Hypotheses worth testing, cheapest first

1. **Contention, not logic.** Re-run the full suite with `-parallel-testing-enabled NO`. If it goes
   deterministically green over several runs, the fix is scheduling: serialize the target or the
   class, not tighten or loosen assertions.
2. **The 3 s budget is simply too tight** for cold decode + seek on a loaded machine. The honest fix
   is a condition-based wait with a generous cap, not a longer `sleep` — poll the condition, fail on
   a cap you can justify from measured decode latency.
3. **Double-counted quantization.** The primary clock is frame-quantized on both backends, and the
   assertion's tolerance is one frame (`1/24`). If the expected time is derived from a quantized
   primary and compared to a quantized secondary, two independent half-frame errors can exceed one
   frame at the tolerance boundary. This would make the assertion marginal by construction — worth
   checking before adding time.

### What to instrument before changing anything

At deadline expiry, log the observed `actual - expected` and the elapsed time instead of only failing.
Right now the miss size is invisible, so every hypothesis is untestable. One run with that
instrumentation tells you whether misses are 5 ms (marginal tolerance) or 900 ms (starvation).

### Environment facts that will waste your time otherwise

- Pass signing settings as **trailing build-setting arguments**, never env prefixes — env prefixes are
  ignored by the test action and the build then fails on signing:
  `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- Xcode 26 prints **no `Executed N tests` line**. Count with `grep -cE 'Test case .* passed on'`.
  Use an **unanchored** match: parallel-test output interleaving prefixes some lines, and a
  `^Test case '…'` pattern silently undercounts and invents phantom "missing tests".
- `Test Fixtures/Generated/` is gitignored, so a fresh clone skips 8+ suites. Regenerating needs a
  full ffmpeg (the bundled one is image-only): `scripts/generate-test-fixtures.sh`.
- Metal API Validation must stay OFF in the scheme (MoltenVK race, KhronosGroup/MoltenVK#2226).

## Focus 2 — parked cosmetic items

All verified-safe to leave; fix only if you are already in the file.

- `PlayerController.swift` — the inspector's decoder row reads "Not yet decoded" throughout
  audio-only playback; truthful but indistinguishable from a missing feature.
- `HardwareDecodingStatus.unavailable` is referenced only from tests.
- `HardwareDecoderWiringTests` — its doc comment claims more scope than it proves (it stops at
  `MPVPlayer`), and it `XCTSkip`s without `MANIFEST.txt`; its fixture resolver duplicates
  `GeneratedMediaFixtureTests.swift:224-231`.
- `MPVClockMirrorTests` covers only the mirror, so reinstating `queue.sync` would keep the suite green;
  its concurrency case cannot fail on arm64 (aligned stores are atomic).
- `MPVQueueIdentityTests.swift:16` reads a `@MainActor` property from a closure run across `queue.sync`.
- `PrintController`'s `deinit` now blocks the releasing thread on `queue.sync` where it previously did
  not; deliberate (symmetric with `destroy()`).
- The `deinit` teardown branch is **unreachable** while `wakeupContext` holds its
  `Unmanaged.passRetained(self)`, so it has no test by construction. The comment at the site says so.
- Nothing drives mpv's `"Reversal queue overflow"` log line into the buffer climb; the ladder, the
  cooldown and the matcher are unit-tested, the wiring is not.
- Nothing asserts the invariant `applyHDRState` protects (that a rebuild must not clobber the
  `transferFunction` it just applied).
- `HDRTransferResolver` substring matching is looser than its tests imply (`"foo-st2084"` matches).
  Correct for container-declared names; note only.
- `OneShotFlagTests.testExactlyOneConcurrentClaimWins` is decoration for `OSAllocatedUnfairLock`
  rather than proof of it. The regression it guards is covered by the other two cases.

**Two citations that were checked and are NOT defects** — do not "fix" them:
`CompareReviewDiskFullTests.swift:13` already throws `XCTSkip`; `CompareLiveBackendTests.swift:70` is a
`setUp` early return that gates only a profiling assertion, not the tests.

## Focus 3 — the next work

`docs/superpowers/plans/` holds five independent plans, each shippable alone:

| # | Plan | Depends on |
|---|---|---|
| 1 | Preferences, migration and menus | — |
| 2 | Colour pipeline (EDR, ICC, display peak) | — |
| 3 | Hardware decode probing and a video filter chain | — |
| 4 | User-editable key bindings | — |
| 5 | Playback clock split (stop whole-tree re-renders) | — |

The README in that directory records the scope decisions and an explicit out-of-scope list. Plan 6
(the one just landed) is `2026-09-12-06-core-hardening.md`. Plans 1–5 are independent of each other
and of plan 6.

## Swift concurrency conventions in this repo — non-obvious, cost me time

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means every type is main-actor isolated unless it says
otherwise. Consequences that are not obvious from the code:

- `NSView.awakeFromNib()` and `XCTestCase.setUp`/`tearDown` are declared **nonisolated** in the SDKs.
  You cannot make an override `@MainActor` (error: "has different actor isolation from nonisolated
  overridden declaration") and you cannot drop the `nonisolated` marker either. Wrap the body in
  `MainActor.assumeIsolated { }`.
- Queue-confined state takes `nonisolated(unsafe)` — see `MPVPlayer.swift` for `mpv`, `wakeupContext`
  and the clock-coalescing fields, which are touched only on `com.aagedal.mpv`.
- The test target's convention for state touched from `setUp`/`tearDown` is `nonisolated(unsafe)` on
  the property, not `@MainActor` on the method.
- An immutable `let` of a `Sendable` type is reachable from a `nonisolated` context; a mutable `var`
  is not.
- `@Published` replays its current value to a new subscriber, so a per-load object repointed at a
  reused publisher can hand stale state to a fresh observation.
