# HANDOFF — AMP: VLC behaviour + IINA look + verified fixes
# Note: GEMINI_API_KEY must be provided via environment variable; do not commit keys.

Written 2026-10-13 by a Claude (Opus) session so another LLM can continue if this one is rate-limited. Read this whole file before acting.

## 0. Where things are

- Repo: `/Users/filip/src/amp` (macOS 26 SwiftUI/AppKit video player "Aagedal Media Player", libmpv via MPVKit fork). Read `CLAUDE.md` in the repo root first: build/test commands, signing overrides, architecture.
- Main checkout `/Users/filip/src/amp` is on branch `main` at commit `676caf1` with only untracked docs. Do not edit source there.
- Work worktree (use this): `/Users/filip/src/amp/.claude/worktrees/antigravity-amp-vlc-parity-96dc20`, branch `worktree-antigravity-amp-vlc-parity-96dc20`, also at `676caf1`, clean except new docs.
- Installed app: `/Applications/amp.app` = clean Release build of `676caf1` (v1.6.1). `/Applications/amp_old.app` is an older build left by a previous agent; leave it unless the user says otherwise. The user wants every new build installed to `/Applications/amp.app` (replace the old one).
- All research for this effort: `docs/research/2026-10-13-vlc-iina-parity/` in the worktree (listed in section 4).

## 1. What happened so far

1. Another agent ("antigravity") left uncommitted changes in the main checkout: click-to-pause and double-click-fullscreen gesture recognizers on the MPV/AVPlayer views, scroll volume/seek with no trackpad accumulation, global scaler/deband/tone-mapping changes (`ewa_lanczos` for all profiles, `sigmoid-upscaling`, `tone-mapping=bt.2390`, deband always configured), and re-maximizing the window on every new file. The user said it "messed everything up".
2. Fix applied: those changes were saved to branch **`antigravity-wip`** (commit `d0e6c7d`) and reverted in the main checkout. The app was rebuilt from `676caf1` and installed as `/Applications/amp.app`. Do not re-apply `antigravity-wip` wholesale; it is kept only for reference.
3. Research done (all saved in the folder in section 4):
   - VLC macOS behaviour catalog from VLC source (ground truth).
   - AMP GUI inventory.
   - Second opinions from Gemini 3.1 Pro, DeepSeek and Gemini 4 Argon.
   - Gemini 4 Argon full-source review of the whole app, sent with the whole AMP source.
   - Gemini 4 Argon "make AMP look like IINA" answer, sent with IINA v1.5.0 source plus AMP UI source.
4. Verification of Gemini's bug claims (done by a Sonnet worker reading the code). See section 3.
5. In progress when this was written: four Sonnet verification workers. Their outputs land in `/private/tmp/claude-501/-Users-filip-src-amp--claude-worktrees-antigravity-amp-vlc-parity-96dc20/6a4342a3-017b-4b0c-9336-d64c130305d4/scratchpad/`:
   - `verified-vlc.md`: Section A of the Argon review checked against code, with the exact AMP APIs a plan needs.
   - `verified-iina.md`: every IINA value checked against IINA source.
   - `verified-engine.md`: Sections B–H checked against code and the mpv manual.
   - `verified-apple-apis.md`: AppKit/SwiftUI claims checked on the web. **Done**, copied to the research folder. Key results:
     - `performDrag` returns immediately and may swallow mouseUp. Start the drag in `mouseDragged` after a dead zone, as IINA and mpv do. mpv also zeroes its double-click timer once a drag starts.
     - `contentAspectRatio` applies only to user resizes. mpv re-sets the ratio after every `setFrame`. Note the AMP `maximize()` comment says otherwise; clearing the lock first stays harmless.
     - SwiftUI rebuilding manually inserted menus is UNSETTLED. Prefer `CommandMenu` and test on macOS 26.
     - Bare-key menu shortcuts stealing keys from text fields is UNSETTLED; needs a runtime test.
     - VLC uses `deltaY` with no momentum filter; IINA filters momentum.
     - `MPNowPlayingInfoCenter.playbackState` must be set on every play/pause.
     - `fileResourceIdentifier` does not persist across reboots; key resume entries by path.
     - Float on top: copy IINA. Skip it in native fullscreen, set `.normal` on entering fullscreen, restore on exit.

   If those files exist, copy them into `docs/research/2026-10-13-vlc-iina-parity/` and use them. If not, rerun that verification (the prompts are summarised in section 6).

## 2. Decisions the user has made (do not reopen)

- **Behaviour = VLC for standard interactions. Look = IINA. AMP's own features stay.** AMP-only features are: shader render profiles with an automatic picker, Compare Mode, scopes, loupe, waveform, timecode, trim/export, JKL shuttle, and multi-window sync.
- **Keymap: switchable.** Setting "Keyboard: VLC / AMP Pro", default **VLC**. AMP Pro keeps today's JKL, arrows and `[ ]` keys. AMP's I/O trim keys and timecode digit entry remain in both modes.
- **Double-click on video = "fill screen, stay windowed".** It is *not* native fullscreen. The window grows to `screen.visibleFrame` and the menu bar and Dock stay visible. Double-click again restores the previous frame. If the window is in native fullscreen, double-click exits it.
- **Single click on video does nothing except drag the window**, starting after a 3 pt threshold. It does *not* pause (VLC 3.0 behaviour).
- **Workflow the user wants:**
  - Plans are written by Opus with the `superpowers:writing-plans` skill: no placeholders, no assumptions, every API name verified in code.
  - Questions go to **Gemini 4 Argon** (`gemini-4-argon` via the Generative Language API; see section 5).
  - Implementation is done by **DeepSeek workers in Orca** (`orca orchestration worker-start --agent omp`; see section 5).
  - Use Haiku or Sonnet for reading and Sonnet for verification.
- Commit messages: plain `git commit -m "message"`, no attribution or co-author lines. Use `pnpm`, never `npm`. Don't build or test after every change; verify once per checkpoint.

## 3. Verified bugs (checked in code by a Sonnet verifier)

| # | Bug | Verdict | Minimal fix |
|---|---|---|---|
| 1 | External subtitles added with `PlayerController.addSubtitle(url:)` (`mpv sub-add`, `MPVPlayer.swift:~1578`) never refresh `trackSelection`, so they are missing from the subtitle menus. `buildMPVSubtitleTrackOptions()` (`PlayerController.swift:~1518`) is never called. | CONFIRMED | Rebuild the track options after `sub-add`, or observe mpv `track-list`. |
| 2 | `MPVViewController` posts `.reloadPlayer` (full mpv destroy, recreate and reseek) on did-enter/exit fullscreen, did-end-live-resize, and a ≥1.5× drawable jump (`MPVVideoView.swift:~233-394`). This is a deliberate workaround for a stale dst-rect. | CONFIRMED | Root-cause fix needed. Check `verified-engine.md` C1/C4 before touching it. |
| 3 | The automatic render profile (the default) runs `FrameAnalyzer`, which spawns up to 9 sequential ffmpeg processes per file open (`FrameAnalyzer.swift:~94-107`). | CONFIRMED | Cache the result per URL + mtime. |
| 4 | The Enhance suggestion button posts `.setRenderProfile`, which is persisted to UserDefaults (`MPVPlayer.swift:~1337`) and applied to every window (`ContentViewCommandHandlers.swift:~149`). One click silently replaces the user's Faithful default. | CONFIRMED | Apply per player without persisting. |
| 5 | Every profile except Faithful forces `video-sync=display-resample` + `interpolation=yes` with `tscale=oversample` (`RenderProfile.swift:~116`, `MPVPlayer.swift:~351`), even when fps divides the refresh rate (24p on 120 Hz). | CONFIRMED (deliberate, see code comment) | Gate interpolation when refresh is an integer multiple of fps. |
| 6 | `HDRFrameData ==` always returns false (`ScopeComputer.swift:~27`). | CONFIRMED, intentional | Optional cleanup. |
| 7 | The Compare secondary controller is never passed to `SleepPreventer.forget`. | PARTLY: stale dictionary entry only, no wake lock | `forget(secondary)` in compare `stop()`. |
| 8 | Scope and waveform window controllers keep NotificationCenter tokens when released without `close()`. | PARTLY: inert | Remove in `deinit`. |
| 9 | mpv handle data race. | FALSE | — |
| 10 | Keys double-fire in Compare Mode. | FALSE | — |

Unverified claim from Argon (verify before acting): bare-key SwiftUI menu shortcuts in `Aagedal_Media_PlayerApp.swift` (`m`, `t`, `j`, `l`, space) fire while typing in a TextField such as Compare review notes.

## 4. Research files (`docs/research/2026-10-13-vlc-iina-parity/`)

- `vlc-macos-behaviour-catalog.md`: VLC ground truth (mouse, scroll algorithm, keys, window, menus, resume, OSD texts).
- `amp-gui-inventory-short.md`: what AMP does today. The full inventory was in the session; regenerate it if needed.
- `2026-10-13-gemini4-argon-full-review.md`: Gemini 4 Argon full-app review. Part 0 bugs, A (VLC parity implementation), B architecture, C Metal/render, D engine, E image quality, F UX, G testing, H top-30. **Not verified; line numbers are often wrong. Verify everything.**
- `2026-10-13-gemini4-argon-iina-look.md`: Gemini 4 Argon IINA look spec, 15 sections plus ranked tasks. **Not verified.**
- `2026-10-13-iina-look-query-draft.md`: the exact question that was sent for the IINA answer (user-approved).
- `gemini4-full-review-questions.md`: the exact question set sent for the full review.
- `gemini4-appkit-answers.md`, `gemini31-appkit-answers.md`: the 10 AppKit questions answered by both models. Argon corrected 3.1 on `contentAspectRatio`/`setFrame`, `fileResourceIdentifier` persistence, and SwiftUI wiping manual menus.
- `gemini31-vlc-gap-list.md`, `gemini31-engine-review.md`, `deepseek-vlc-gap-list.md`: earlier second opinions.
- `draft-phase1-worker-spec.md`: an early worker spec for the mouse surface. It is superseded by the plan, but its behaviour list is correct per the user's decisions.

Known corrections to Gemini (do not repeat them):
- KrigBilateral is not a neural network.
- `coreaudio-exclusive=yes` as a default is harmful for a general player.
- libmpv's render API has no Metal type; check `include/mpv/render.h`.
- VLC macOS uses F/G for audio delay and H/J for subtitle delay, not J/K.
- The `maximize()` code comment in `WindowConfigurator.swift` says AppKit reshapes `setFrame` to a locked `contentAspectRatio`. Clear the aspect lock before filling the screen; the existing `maximize()` already does this.

## 5. How to run the tools

**Gemini 4 Argon** (1,048,576 input tokens; 32,768 output tokens, so long answers need a continuation turn). The user supplied the API key in chat. Ask the user for it; never write it to disk or commit it.
```bash
jq -n --rawfile p prompt.txt '{contents:[{role:"user",parts:[{text:$p}]}]}' > req.json
curl -sS --max-time 1800 -o raw.json -H "x-goog-api-key: $GEMINI_API_KEY" -H "Content-Type: application/json" \
  -d @req.json "https://generativelanguage.googleapis.com/v1beta/models/gemini-4-argon:generateContent"
jq -r '.candidates[0].content.parts[]? | select(.thought != true) | .text // empty' raw.json > answer.md
jq -r '.candidates[0].finishReason' raw.json   # MAX_TOKENS => append model turn + "continue exactly where you stopped"
```
Do not pass `generationConfig`; the endpoint rejected it. To list models: `GET /v1beta/models?pageSize=1000`.

Other tools on this machine:
- `codex` hit a usage limit today.
- The `gemini` CLI is rejected for this account; use the API above.
- `opencode run -m deepseek/deepseek-flash` works.

**Orca / DeepSeek workers** (load the version-matched guide with `orca skills get orchestration` first):
- The runtime is started (`orca open`).
- `orca orchestration run-create` failed with `no_active_sender_terminal`. It must be run from inside an Orca terminal (`ORCA_TERMINAL_HANDLE` set), or with `--from <handle>`. Resolve this first.
- Worker command: `orca orchestration worker-start --spec "<self-contained task>" --worktree path:<worktree> --agent omp --json`. Do not pass `--model`.
- Wait with `orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms 900000 --json`. Answer worker questions; send hard ones to Gemini 4 Argon.

## 6. Next steps (in order)

1. **Collect verification.** Copy `verified-*.md` from the scratchpad (section 1) into the research folder. If any are missing, re-run them with Sonnet workers:
   - (a) Section A of the Argon review against code, plus exact AMP API signatures.
   - (b) every IINA value against IINA v1.5.0 source (`git clone --depth 1 --branch v1.5.0 https://github.com/iina/iina`).
   - (c) Sections B–H against code and the mpv master manual (`DOCS/man/options.rst`).
   - (d) AppKit/SwiftUI claims against Apple docs, forums and IINA/VLC/mpv GitHub.
2. **Write three plans** with the `superpowers:writing-plans` skill into `docs/superpowers/plans/`:
   - `2026-10-13-vlc-behaviour.md`, with tasks in this order:
     1. scroll accumulator (pure struct with tests)
     2. fill-screen toggle (pure decision function with tests)
     3. video mouse surface NSView: drag after 3 pt, double-click fill, right-click VLC menu, scroll, pinch. Insert it in `PlayerView`'s ZStack only when `acceptsKeyboardInput && compareSession?.isActive != true`, so the Compare wipe drag keeps working.
     4. volume max 125 %: `PlayerController` clamp, `PlaybackVolume.mpvValue` (currently clamps to 100), the slider `maxValue` with a tick at 100, AVPlayer adapter clamped to 1.0.
     5. OSD messages: SwiftUI overlay, `.allowsHitTesting(false)`, VLC texts, VoiceOver announcement.
     6. keymap preset setting plus a VLC key table, with the menu shortcut fix.
     7. ⌘0–3 window sizes, float on top, aspect re-lock on user resize.
     8. elapsed/remaining toggle.
     9. resume playback (ask/always/never, VLC rules, non-blocking banner).
     10. Now Playing / media keys.
     11. Audio/Video/Subtitles menus via `CommandMenu` + `@FocusedObject`.
   - `2026-10-13-iina-look.md`, from `verified-iina.md` only.
   - `2026-10-13-verified-fixes-and-engine.md`: section 3 bugs plus `verified-engine.md` items.
3. Ask the user to review each plan.
4. Execute with DeepSeek workers in Orca, one task per worker, with the plan task text as the spec. Review every `worker_done` diff yourself and run the tests.
5. After each checkpoint, build Release and install to `/Applications/amp.app`:
   ```bash
   xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -configuration Release \
     -destination "platform=macOS" -derivedDataPath /tmp/amp-dd CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= build
   rm -rf /Applications/amp.app && ditto "/tmp/amp-dd/Build/Products/Release/Aagedal Media Player.app" /Applications/amp.app
   ```

## 7. Code facts already confirmed (save re-reading)

- `PlayerView` (`UI/PlayerView.swift`):
  - The ZStack holds `Color.black`, then the AVPlayer `PlayerContainerView` or the MPV `MPVVideoView` inside a `GeometryReader`, then `AudioOnlyPresentationView`, `overlayIndicators`, `playbackStateOverlay` and the enhancement banner.
  - `handleKeyEvent(_:_:_:)` order: text and focus guards, then `keybindings.json` override, then `PlayerKeyMap.characterAction`, then compare `B`, then I/O trim, then Space, then JKL, then the arrow table, then timecode digits.
- `ComparePlayerView` is used for all playback (`ContentView.swift:~135`). The secondary `PlayerView` gets `acceptsKeyboardInput: false` and no `compareSession`.
- Commands:
  - `AppCommand` (`Logic/AppCommand.swift`) is a typed enum, posted with `NotificationCenter.default.post(_:)` and received via `appCommandPublisher`.
  - Handlers live in `UI/ContentViewCommandHandlers.swift`, guarded by `WindowManager.shared.isActiveWindow(nsWindow)` or `shouldHandlePlaybackCommand(window:)`.
  - Cases include `togglePlayback`, `toggleMute`, `adjustVolume(by:)`, `seekBySeconds`, `seekByFrames`, `seekToEdge`, `stepRate(forward:)`, `toggleFullscreen`, `captureScreenshot`, `openNextFile`, `openPreviousFile`, `setRenderProfile` and `openSubtitleFile`.
- `PlayerController`:
  - `volume` is clamped to `0...100` at `:43`, `:230` and `:845`.
  - Methods: `adjustVolume(by:)`, `toggleMute()`, `togglePlayback()`, `play()`, `pause()`, `stepRate(forward:)`, `seek(by:)`, `seekByFrames(_:)`, `seekTo(_:)`, `toggleFullscreen()`, `selectAudioTrack(at:)`, `selectSubtitleTrack(at:)` (MPV only), `addSubtitle(url:)`.
  - `audioTrackOptions`, `subtitleTrackOptions` and the selected indices come from `trackSelection`.
- `PlaybackVolume.mpvValue(for:)` clamps to 100 and returns `100 * cbrt(percent/100)`. The AVPlayer adapter sets `player.volume = Float(v/100)`.
- `WindowConfigurator.Coordinator` has `maximize(_:)` (clears the aspect lock and min size, then calls `setFrame(visibleFrame, animate: false)`), `applyMinSize`, `applyInitialSize`, `lastAspectRatio`, `lastSourceSize` and `hasMaximizedForMedia`. `AppSettings.openMaximized` defaults to true and is hidden from Settings.
- `PlayerKeyMap` (`UI/PlayerKeyMap.swift`) is pure and testable: `characterAction`, `arrowDecision` and `userOverride`.
- `AppSettings` uses the `AppSetting<Value>(key:defaultValue:)` pattern with `UserDefaults.standard.value(for:)` and `set(_:for:)`.
- The Xcode project uses file-system synchronized groups, so new files are included automatically.

## 8. Progress update (later the same session)

- All four verifications are done and copied to `docs/research/2026-10-13-vlc-iina-parity/`: `verified-vlc.md`, `verified-iina.md`, `verified-engine.md`, `verified-apple-apis.md`.
- Binding design decisions for the VLC plan: `docs/research/2026-10-13-vlc-iina-parity/vlc-plan-design-decisions.md`.
- IINA-look decisions from the user:
  - Keep the 690×540 minimum window size.
  - Keep AMP's hidden title (no IINA title bar).
  - Controls auto-hide while paused, as IINA does.
  - The floating controller defaults to 10% of the video height above the bottom, as IINA does.
- Engine verification highlights:
  - The stale dst-rect root cause: the fork's `moltenvk` context never emits `VO_EVENT_RESIZE`; its control returns `VO_NOTIMPL` (patch 0001).
  - `coreaudio-exclusive` and `gpu-hwdec-interop=moltenvk` are invalid options.
  - libmpv's render API has no Metal type.
  - `FloatingOSCView.swift:108` seeks exactly on every drag event.
  - FSRCNNX is stripped above 60 Hz while the picker still counts it.
- Plans being written by Sonnet workers with `superpowers:writing-plans`, in `docs/superpowers/plans/`:
  - `2026-10-13-vlc-behaviour.md`
  - `2026-10-13-verified-fixes-and-engine.md`
  - `2026-10-13-iina-look.md` (runs after the VLC plan)

  If a plan file is missing, rerun its writer with the same inputs.

## 9. Current state

**Plan writers.** Three Sonnet plan writers are running in the background, launched from the Claude session. No plan file existed yet when this section was written. Expected outputs, all under `docs/superpowers/plans/`:
- `2026-10-13-vlc-behaviour.md`
- `2026-10-13-verified-fixes-and-engine.md`
- `2026-10-13-iina-look.md`

If the session died and a file is missing, rerun that writer. Each writer invokes `superpowers:writing-plans`, uses only the verified inputs listed in sections 6 and 8, writes no source code, and does no placeholder work.

**Orca setup (done).**
- amp repo registered in Orca: repo id `55119b69-a730-4455-9fdd-12a5806ce5a6`, external worktree visibility `show`.
- This worktree is visible to Orca as `path:/Users/filip/src/amp/.claude/worktrees/antigravity-amp-vlc-parity-96dc20`.
- Coordinator terminal: `term_93e81cc5-c9f8-4cb7-b36d-c37ffe1ab668`, titled "amp-coordinator", in this worktree. Pass `--from` with this handle on orchestration commands run from outside Orca.
- Orchestration run created: `run_e0ef0925264b`.

**Worker model (user requirement).** DeepSeek V4.1 Flash with thinking off. In omp the model id is `deepseek/deepseek-flash`; `omp models deepseek --json` lists it as "DeepSeek V4.1 Flash". The suffix `:off` disables thinking; tested with `omp -p --model "deepseek/deepseek-flash:off" ...`, which works. Orca's `--effort` flag is unsupported for omp, so the suffix is the way. Note that omp's own default in `~/.omp/agent/config.yml` is `deepseek/deepseek-v4-flash:max`, a different model with max thinking. Always pass `--model` explicitly.

Dispatch command for each task:
```bash
orca orchestration worker-start --run run_e0ef0925264b --from term_93e81cc5-c9f8-4cb7-b36d-c37ffe1ab668 \
  --worktree path:/Users/filip/src/amp/.claude/worktrees/antigravity-amp-vlc-parity-96dc20 \
  --agent omp --model "deepseek/deepseek-flash:off" \
  --task-title "<plan task N title>" --spec "<full task text copied from the merged plan + global constraints>" --json
orca orchestration check --from term_93e81cc5-c9f8-4cb7-b36d-c37ffe1ab668 --wait --types "worker_done,escalation,question" --timeout-ms 900000 --json
```
Run tasks **sequentially** in one worktree, because the tasks touch overlapping files. Review each `worker_done` diff and run the task's tests before dispatching the next task. Send worker questions to Gemini 4 Argon when the coordinator can't answer from the code.

**Next steps once the plans exist.**
1. Read all three plans. Check them against `vlc-plan-design-decisions.md`, `verified-*.md` and the user's IINA decisions.
2. Merge them into one file, `docs/superpowers/plans/2026-10-13-amp-vlc-iina-engine.md`, in this order:
   1. Part A: verified quick fixes.
   2. Part B: VLC behaviour.
   3. Part C: IINA look. It restyles the OSD and banner that Part B creates.
   4. Part D: engine and quality, including the MPVKit fork resize fix B1 as its own group.

   Keep each part's Global Constraints, and renumber the tasks in sequence.
3. Show the merged plan to the user for review. The user already chose the execution method: Orca + omp + DeepSeek V4.1 Flash with thinking off.
4. Commit the plans and research docs on branch `worktree-antigravity-amp-vlc-parity-96dc20` with `git commit -m "Add VLC/IINA/engine research and implementation plan"`. Commit only after the user approves; the workers need the file in the tree.
5. Dispatch the tasks one by one as above. At each checkpoint (the end of each part), build Release and install to `/Applications/amp.app` (command in section 6).
