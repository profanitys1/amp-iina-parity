# Round-two questions: verified answers

These answer the questions in `2026-10-13-gemini4-argon-round2-prompt.md`; Gemini hit its tier limit, so a workflow answered them from primary sources instead. Each group had one research agent and one independent adversarial verifier that re-opened every cited source. The full answers, with verbatim quotes and line numbers, are in the workflow journal (run `wf_0d457263-db7`). This page is the checked summary.

| Id | Verifier | Status |
|---|---|---|
| A1 | holds | verified |
| A2 | holds | verified; patch applies and compiles |
| A3 | holds | verified |
| A4 | holds | verified |
| A5 | holds after correction | verified with the correction below |
| B1 | holds | verified |
| B2 | holds | verified, plus one addition |
| B3 | holds after correction | verified with the corrections below |
| C3 | holds | verified empirically on Swift 6.2.4, 6.3.3 and 6.4.1 |
| C1, C2, C5 | verdict UNSETTLED held; verifier corrected details | no primary source; manual Mac checks in the plan |
| C4 | holds | UNSETTLED in practice; docs say programmatic sizes ignore the lock |
| D1, D3 | holds | verified |
| D2, D4, D5 | holds after correction | verified with the corrections below |

Pins: mpv `3186d369f9f090cd1363be0ac46a037824b702c6`, libplacebo `92b5ac6`, MoltenVK `v1.4.2`, MPVKit fork `profanitys1/MPVKit` `amp-master-vsync` (patches 0001–0004).

## A. Engine

### A1. Display sync never engages on the fork

Nothing answers `VOCTRL_GET_DISPLAY_FPS`: `moltenvk_control` returns `VO_NOTIMPL`, and 0004 only adds `get_vsync`. So `display_fps` stays 0. That leaves `vsync_interval` at 0, and `vo_get_vsync_interval` returns -1. `handle_display_sync_frame` then returns at `player/video.c` L833-835, before `display_synced` and `display_sync_active` are set.

The vsync estimator only samples display-synced swaps (`vo.c` L487-490), so it never starts. This is a closed loop: **`video-sync=display-resample` and `interpolation=yes` are both silently inactive in every AMP render profile today.**
- `display-sync-active` is false.
- `display-fps` and `estimated-display-fps` are unavailable.
- The `-v` line "Assuming %f FPS for display sync." (vo.c L562) never prints.

If a nominal fps existed, the estimate would need 510 display-synced swaps: 4.25 s at 120 Hz, 8.5 s at 60 Hz. A failed jitter test only keeps the nominal interval, so ProMotion jitter cannot switch display sync off. Whether CVDisplayLink timestamps vary on ProMotion is UNSETTLED.

### A2. Fork patch: 0005-moltenvk-display-fps-resize.patch

The patch is in this folder, on top of 0001+0004. It adds three things to `context_moltenvk.m`:
- **(a)** `VOCTRL_GET_DISPLAY_FPS` from the bound CVDisplayLink, mirroring upstream `mac/common.swift` `currentFps()`: actual output period first, nominal as fallback.
- **(b)** `VO_EVENT_WIN_STATE` when the display or its refresh changes, plus the upstream 0.1 s re-check.
- **(c)** On `VOCTRL_CHECK_EVENTS`, a `layer.drawableSize` comparison. A change calls `ra_vk_ctx_resize` and returns `VO_EVENT_RESIZE | VO_EVENT_EXPOSE`. The display link thread calls `vo_wakeup` when the size changes, so a paused player picks it up within one vsync.

The verifier checked it three ways:
- It rebuilt the file from 0001+0004, and `git apply --check` succeeds.
- `clang-18 -fsyntax-only -Wall -Wextra -Wshadow` passes against stub headers. That is not an SDK build.
- Every symbol exists at the mpv pin, and the lock order (`p->lock` → `vo->in->lock`) cannot invert.

**Open risk, inherited from 0004:** Apple does not document whether `CVDisplayLinkStop` waits for a callback that is already running.

### A3. Waking the VO while paused

While paused, `render_frame` goes to `done` (vo.c L932-937), and the VO sleeps in `vo_wait_default` for up to 1000 s. `VOCTRL_CHECK_EVENTS` therefore runs only when something calls `vo_wakeup`, which is thread-safe (vo.h L424-431). Upstream does this through `windowDidResize` → `flagEvents` → `vo_wakeup`.

The app cannot nudge it from outside: `video-zoom` and similar only reach `VOCTRL_SET_PANSCAN` → `resize(vo)` with the stale `dwidth`. `VOCTRL_EXTERNAL_RESIZE` is Android/D3D11-only. So the wake belongs in the context (A2c).

The comment in `MPVVideoView.swift` claims "dwidth/dheight are supposed to update inside vk_acquire". That is wrong: only `ra_vk_ctx_resize` writes them (`vulkan/context.c` L497-498).

### A4. Thread safety

- **Reading `drawableSize` on the VO thread is safe.** MoltenVK itself reads it off-main: `MVKSurface`/`CAMetalLayer+MoltenVK` naturalExtent, and the swapchain status checks at acquire and present. Apple lists `CAMetalLayer` as Sendable.
- **libplacebo already recreates the swapchain on SUBOPTIMAL/OUT_OF_DATE** (swapchain.c L878-885, L924, L1026-1035). It never updates `vo->dwidth/dheight`. That is the B1 bug.
- **Calling `ra_vk_ctx_resize` from `control()` on the VO thread is the standard pattern.** The xlib, win, wayland and mac Vulkan contexts all do it.
- **Keep AMP's invariant** that `drawableSize == bounds × contentsScale`, set together with `metalLayer.frame`. MoltenVK's currentExtent is derived from bounds.

### A5. Cadence gate (corrected)

At an integral cadence (24, 30 or 60 fps on 120 Hz), display-resample retimes the video exactly. mpv's factor-1 test is `|ratio/rint(ratio) - 1| <= 0.01`, inclusive. With `tscale=oversample` this gives no visible blending.

Under display sync, mpv draws and flips every vsync whether interpolation is on or off, and gpu-next caches the scaled frame in both modes.

**Verifier correction:** at N ≥ 3, the next frame can still be kept at weight ≈ 0. It is the nearest frame (`refimg`), which is exempt from the 1e-3 cutoff (renderer.c L3954). On about 1 vsync in N this costs one extra mix pass and an early cache render. That cost is not zero, but it is small and invisible.

`estimated-display-fps` is unusable as a gate input, because it is only available once display sync is already running. **Conclusion:** the cadence gate is low-value and is dropped from the plan.

## B. mpv properties

### B1. Runtime crop and aspect while paused

Both options carry `UPDATE_IMGPAR`. A paused change triggers an exact refresh seek (`issue_refresh_seek(MPSEEK_VERY_EXACT)`), so:
- the picture updates after a GOP-length re-decode;
- `MPV_EVENT_SEEK` and `PLAYBACK_RESTART` are emitted.

What each property reports afterwards:
- **`video-aspect-override`** changes `video-params/par,dw,dh`, and observers fire while paused.
- **`video-crop`** never changes `video-params/*`, which is read before `apply_video_crop`. It changes only `video-out-params/dw,dh,crop-*` (and `dwidth`/`dheight`).

Two more details:
- The option's own observer fires immediately, before the picture changes.
- `MPVProperty.swift` says `video-out-params` is unreliable with videotoolbox. The source says `vo->params` is set before `VIDEO_RECONFIG`. Verify this at runtime.

### B2. Persistence across `loadfile`

Both options are global and survive `loadfile … replace`. `reset-on-next-file` has no default. Fix: set `reset-on-next-file=video-aspect-override,video-crop` before `mpv_initialize`; mpv then restores both at the end of every file.

**Verifier addition:** `loadfile replace` is asynchronous, so the restore can overwrite a value written right after `loadfile`. To apply a remembered per-file crop, write it only after `MPV_EVENT_START_FILE`/`FILE_LOADED`, or pass it in loadfile's options argument.

### B3. PAR source and the crop maths (corrected)

**`video-dec-params/par`.** It is the bitstream SAR without the override (CONFIRMED). It is 0.0 when the bitstream has no SAR, and it excludes the container PAR that mpv prefers by default (MKV DisplayWidth, AVStream SAR). So it is the wrong source. Use one of:
- `video-params/par`, read while `video-aspect-override` is `no` (true at the start of every file once B2 is in place);
- or demux-par if > 0, else dec par if > 0, else 1.

**The ratio maths is correct:**
- with F = full-frame display ratio and T = target, F > T gives cropW = w·T/F; otherwise cropH = h·F/T;
- under an override O, F = O.

**Required details:**
- **Rotation.** The crop and the override both apply before rotation. For 90/270 the crop target is 1/T, and an on-screen aspect choice must be written to `video-aspect-override` as 1/ratio. F must come from the value as written.
- **Container crop.** `video-crop` replaces any container crop. Compute inside `video-params/crop-x/y/w/h` when that rect is smaller than the frame, and clear with `""` (never `0x0+0+0`).
- **String format.** Only `WxH+X+Y`. **Never send a ratio string:** `16:9` parses as an x:y offset and silently applies a symmetric inset crop (16 px left/right, 9 px top/bottom).
- **Bounds.** Clamp to [1, base], centre with integer floor, and send `""` when the result equals the base rect.
- **Odd sizes.** No even-coordinate requirement on gpu-next + videotoolbox: libplacebo maps chroma as fractional rects.

## C. Swift 6.2 isolation (C3)

Tested empirically with a Swift-5-mode library calling back from a background thread. App flags: `-swift-version 6 -default-isolation MainActor`, plus the five approachable-concurrency features. Toolchains 6.2.4, 6.3.3 and 6.4.1, signature-verified.

| Pattern | Result |
|---|---|
| plain closure literal passed to a non-concurrency-checked API, called off main | **TRAP** (inferred @MainActor; SE-0423 check → `dispatch_assert_queue`) |
| `{ @Sendable _ in Task { @MainActor in … }; return .success }` | compiles, runs clean |
| `{ @Sendable _ in DispatchQueue.main.async { … } }` | compiles, runs clean |
| `@Sendable` + `MainActor.assumeIsolated` called off main | **TRAP** |
| closure stored in a `let`, then passed | **no check, silent data race** |
| method reference to a @MainActor method | **TRAP** via thunk |
| `NotificationCenter.addObserver(queue: .main)` + `assumeIsolated` | clean |
| `addObserver(queue: nil)` + `assumeIsolated`, posted off main | **TRAP** |
| Combine `sink` without `.receive(on: .main)`, upstream off main | **TRAP** |

These results become plan rules:
- Every `MPRemoteCommand` handler is `{ @Sendable _ in Task { @MainActor in … }; return .success }`. The handler thread is undocumented, and Apple DTS reports MediaPlayer calling closures off main (forum thread 764874).
- Keep `queue: .main` on observers that use `assumeIsolated`.
- Keep `.receive(on: DispatchQueue.main)` before sinks fed from background threads.
- Never pass a pre-built closure variable to a framework callback.

**Still unsettled:** whether the macOS 26 MediaPlayer and Combine overlays are built in Swift 6 mode. If they are, there is no check, but the @Sendable pattern is safe either way.

## C. AppKit / SwiftUI (C1, C2, C4, C5)

- **C1 (UNSETTLED).** No primary source says whether the empty area of a full-size SwiftUI `GeometryReader` lets clicks through to an `NSViewRepresentable` underneath. The plan therefore adds a manual check and two fallbacks: `allowsHitTesting`, and measuring with `onGeometryChange(for:of:action:)` (macOS 13+). macOS 26 release note 108560020 reports gestures lost when `onHover` is used inside an overlay. Keep hover and gesture on the card itself.
- **C2 (UNSETTLED).** No documented bug matches stale Picker rows in a CommandMenu. Related facts:
  - Apple's workaround is to read focused values inside a View used as the menu content (forum 651748, Apple staff, 2020).
  - Picker-in-Menu has an Apple-acknowledged bug, FB15061288 (forum 763217, DTS, 2024).
  - `focusedSceneValue(_:)` for `@Observable` objects exists on macOS 14+ (verifier correction).

  The plan uses View content with Toggle rows, plus a two-window manual check.
- **C4.** Apple's docs say `contentAspectRatio`, `aspectRatio` and the resize increments are ignored for programmatic sizes. Setting one of them cancels the other. No source supports AMP's comment that AppKit reshapes `setFrame` to the locked ratio. Four apps report that assigning `.zero` leaves a degenerate ratio that traps, so the plan unlocks with `contentResizeIncrements = 1×1` and adds an A/B check on the Mac.
- **C5 (UNSETTLED).** Nothing says whether a right-click makes a non-key window key before `menu(for:)`. The plan builds the menu from the view's own window and controller, and calls `window.makeKey()` in `rightMouseDown`.

## D. VLC 3.0.x macOS (clone at f1369aeb)

- **D1. Float on Top uses `NSStatusWindowLevel`** (VLCVoutWindowController.m 96-113).
  - VLC drops it to normal for fullscreen and miniaturize, and restores it afterwards (Windows.m 434-444, 534-545, 633-641, 735-741).
  - Helper panels sit at status level + 1, except the main window, which takes the same level.
- **D2 (corrected). Fit to Screen (⌘3) calls `[[NSApp keyWindow] performZoom:]`** (VLCMainMenu.m 948-951).
  - In the default configuration, with a titled window, this is AppKit's standard zoom. VLC does not override `windowWillUseStandardFrame:`, so the frame "nearly fills the current screen".
  - Only borderless windows use VLC's `customZoom:`. That zooms to `visibleFrame` without keeping the aspect, and toggles back to the saved frame within 3 px.
  - AMP maps ⌘3 to its fill toggle.
- **D3. Resume.** Thresholds and the 30-item cap are verified (VLCInputManager.m 691-764).
  - Playback is NOT paused while the dialog shows. The dialog is non-modal (`makeKeyAndOrderFront`).
  - Continue seeks. A 10 s countdown ends with Restart, which does not seek.
  - Return activates Continue. Changing the item cancels the offer.
- **D4 (corrected). Changing aspect or crop resizes the window.** The path is the core's fit_window → `vout_window_SetSize` → `setNativeVideoSize:`. With `macosx-video-autoresize` (default on), that animates the window to the new native size at zoom 1, anchored top-left and clamped to `visibleFrame`.
  - It is skipped in fullscreen.
  - A no-op aspect change does not resize.
- **D5 (corrected). Esc leaves fullscreen only. Windowed, it is swallowed** (VLCVoutView.m 171-176, 187).
  - VLC's own key mapping deliberately does not support Esc (VLCStringUtility.m 346), so the core `key-leave-fullscreen` hotkey is not reachable from the Cocoa key path.

## Round three: web and GitHub search for C1, C2, C5

New primary evidence from web searches and from shallow clones of IINA (`629ee348`), mpv, Chromium and WebKit. Verdicts stay UNSETTLED for the exact questions, but the plan now rests on stronger ground.

- **C1. Apple DTS (forum 812113, Jan 2026, macOS 26.2, FB21579636) says overlapping hosting views are "expected behavior".**
  - The recommended fix is to "override `hitTest` and route events as desired", for example by returning `nil` from the top `NSHostingView`'s `hitTest` so clicks always pass through to the view below.
  - Apple staff first called the report a possible regression, then confirmed it as expected.
  - A reply in the same thread says a hit test can reach a SwiftUI button while its `DragGesture` still gets no events. So keep gestures on the card itself.
  - The plan's fallback (an `NSHostingView` subclass whose `hitTest` returns `nil` outside the card) is now Apple-endorsed, not just WWDC26-289 guidance.
  - Still unsourced: what SwiftUI does for the empty area of a `GeometryReader`. Community answers only say hit testing uses the layout frame, and `contentShape` changes the hit area.
- **C2. A published, dated working pattern exists (TrozWare, 2025).**
  - It publishes state with `focusedSceneValue` as an optional `Binding`, reads it with `@FocusedBinding` in the App's `CommandMenu`, and uses a `Picker` with `.pickerStyle(.inline)`.
  - The author reports it works "even in tabbed windows".
  - The author reports Picker rows "only got updated as the menu opened". That is acceptable, because the menu is closed while the state changes.
  - He abandoned `focusedSceneObject` only because he moved to Observation, not because it failed.
  - The plan keeps View-typed content with Toggle rows and adds this Binding pattern as the fallback if the two-window check shows stale rows.
- **C5. IINA's source documents an AppKit quirk (iina `MainWindowController.swift` L1187-1194, `VideoView.swift` L112-118).**
  - AppKit has "special handling for rightMouseDown having to do with contextual menus".
  - The event reaches the view, not the window controller, even though the docs say it goes up the responder chain.
  - IINA acts on `rightMouseUp`.
  - Chromium's `BridgedContentView.acceptsFirstMouse` returns `YES` for all events. WebKit's `acceptsFirstMouse` is conditional (drag or scroll while inactive).
  - Nothing states the order of "make key" versus `menu(for:)`.
  - The plan does not depend on the answer: the menu is built from the view's own window and controller, and `rightMouseDown` calls `window.makeKey()`.
