# Gemini 4 Argon — round 2 prompt (one shot)

Copy everything below the line into Gemini 4 Argon. If Gemini has a URL tool, give it the URLs listed in each section. If that tool limits how many links it takes, start with the ★ ones. Every URL returned HTTP 200 on 2026-10-13.

---

You are reviewing a macOS 26 video player ("AMP", Swift 6.2, SwiftUI/AppKit, libmpv). Answer ONLY from primary sources: source code at a named commit/tag (quote exact lines + URL) or official Apple docs (quote + URL). If you cannot find a primary source, write VERDICT: UNSETTLED — do not infer, do not answer from memory. Your previous answer contained claims that the sources refuted (e.g. "setFrame(animate:true) blocks per Apple docs" — Apple's page has no such text; "VLC fires one wheel step then zeroes" — VLCVoutView.m loops `while (ABS(cumulated) >= threshold)`). For every item output: VERDICT (CONFIRMED / REFUTED / UNSETTLED), quoted lines, URL, and corrected code where asked.

## Context

mpv setup (libmpv, wid embedding):
- wid = CAMetalLayer pointer; vo=gpu-next; gpu-api=vulkan; gpu-context=moltenvk; hwdec=videotoolbox (zero-copy) or auto
- framedrop=vo; hwdec-extra-frames=4; tscale=oversample; screen-name=<CGDirectDisplayID>; display-fps-override NOT set
- every render profile except "off" sets video-sync=display-resample + interpolation=yes ("off" sets video-sync=audio + interpolation=no)
- the main thread sizes the layer: `metalLayer.drawableSize = view.bounds * contentsScale` (in viewDidLayout / explicit sizing)

Versions: mpv pinned at commit `3186d369f9f090cd1363be0ac46a037824b702c6`; MoltenVK 1.4.2; libplacebo master `92b5ac6` (API 7.374).

The moltenvk context is a fork patch (not upstream). Abridged 0004 (`context_moltenvk.m`):

```c
struct priv { struct mpvk_ctx vk; CAMetalLayer *layer; CVDisplayLinkRef link; CGDirectDisplayID display; mp_mutex lock;
              int64_t times[VSYNC_SLOTS]; int64_t durations[VSYNC_SLOTS]; int count; int overflowed; };
// CVDisplayLink callback stores output->hostTime into times[] and videoRefreshPeriod/videoTimeScale*1e9*rateScalar into durations[].
// moltenvk_get_vsync: info->last_queue_display_time = p->times[0]; info->vsync_duration = p->durations[0];
struct ra_ctx_params params = { .get_vsync = moltenvk_get_vsync, };
static int moltenvk_control(struct ra_ctx *ctx, int *events, int request, void *arg)
{ if (request == VOCTRL_VO_OPTS_CHANGED) bind_display(ctx); return VO_NOTIMPL; }
```

Already verified (do not re-argue):
- At 3186d369, `vo.c` `update_display_fps()` asks `VOCTRL_GET_DISPLAY_FPS`. Nothing answers it here, so `display_fps` stays 0 and the `display-fps` property is UNAVAILABLE.
- `vo_gpu_next` forwards unhandled VOCTRLs to `ra_ctx->fns->control`, and calls `resize(vo)` when the returned events contain `VO_EVENT_RESIZE`.
- `vo.c` calls `VOCTRL_CHECK_EVENTS` once per VO loop.
- Upstream `context_mac.m` calls `ra_vk_ctx_resize(ctx, framePixel w,h)` from its control when `VO_EVENT_RESIZE` is flagged.
- `ra_vk_ctx_resize` updates `ctx->vo->dwidth/dheight`.

Symptom we need to fix ("B1"): after a programmatic window resize, the picture keeps the old destination rectangle until mpv is recreated.

## A. Engine (mpv @3186d369 + fork)

**A1.** With `display_fps = 0` and `get_vsync` providing `last_queue_display_time`, does `video-sync=display-resample` + `interpolation=yes` engage?
- Trace `vo.c` (`update_display_fps`, `check_estimated_display_fps`, `vo_get_vsync_interval`, `MAX_VSYNC_SAMPLES`) and `player/video.c` (where display sync is chosen or abandoned when the vsync interval is <= 0).
- How many vsync samples, or seconds, until the estimate is used at 120 Hz and 60 Hz?
- Can macOS ProMotion (variable refresh, panel dropping below 120 Hz) keep the jitter test from ever passing?
- Which log lines show which path is active?

**A2.** Write the exact patch on top of 0004's `context_moltenvk.m` that:
- (a) answers `VOCTRL_GET_DISPLAY_FPS` from the bound CVDisplayLink the way upstream `video/out/mac/common.swift` `currentFps()` does: actual output period first, nominal as fallback (quote `currentFps`);
- (b) flags `VO_EVENT_WIN_STATE` when `bind_display()` changes the display or refresh, so `vo.c` re-queries;
- (c) on `VOCTRL_CHECK_EVENTS`, compares `layer.drawableSize` with the last applied size and, when it changed and both sides are > 0, calls `ra_vk_ctx_resize(ctx, w, h)` and sets `*events |= VO_EVENT_RESIZE`.

Include the priv fields, the initialisation of the last size, and the locking. Return `VO_NOTIMPL` vs `VO_TRUE` correctly for each request (quote the `vo_gpu_next.c` control fallthrough at 3186d369).

**A3.** The resize happens on the main thread while mpv may be paused.
- Does the VO thread run `VOCTRL_CHECK_EVENTS` while paused with no new frames (`vo_wait_default` / `wait_vo` timing at 3186d369)?
- If not, what is the supported way for the context to wake the VO after the layer resizes (`vo_wakeup` from a KVO or notification on the layer? something else)?

Quote the code path.

**A4.** Three safety questions; quote other contexts that do the same thing where relevant:
- Is reading `CAMetalLayer.drawableSize` from mpv's VO thread safe? Use an Apple doc or the MoltenVK source: where does MoltenVK 1.4.2 read `drawableSize` / `naturalDrawableSize` for `VkSurfaceCapabilities` `currentExtent`, and from which thread?
- Does libplacebo 7.374 already recreate the swapchain when MoltenVK returns `VK_SUBOPTIMAL_KHR` / `OUT_OF_DATE` after a `drawableSize` change (quote `vulkan/swapchain.c`), so that only `vo->dwidth/dheight` + `VO_EVENT_RESIZE` are missing?
- Is calling `ra_vk_ctx_resize` from the context's `control()` on the VO thread safe?

**A5.** `tscale=oversample` with display-resample at an integral cadence (24 fps on 120 Hz, 30 on 120, 60 on 120):
- Does `interpolation=yes` produce any blended output frames?
- Does it cost a full render per vsync compared with `interpolation=no`? Quote the `video/out/gpu_next` or `vo.c` logic on redraw/repeat when interpolating.
- We plan to turn interpolation off when `round(Hz/fps) >= 2` and `|Hz/fps − round| / round < 1 %`. Is that worth it?
- If `display-fps` stays unavailable, is `estimated-display-fps` (or something else) the right input?

Sources for A:
- ★ https://raw.githubusercontent.com/profanitys1/MPVKit/amp-master-vsync/Sources/BuildScripts/patch/libmpv/0004-moltenvk-vsync-feedback.patch
- ★ https://raw.githubusercontent.com/profanitys1/MPVKit/amp-master-vsync/Sources/BuildScripts/patch/libmpv/0001-player-add-moltenvk-context.patch
- ★ https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/vo.c
- ★ https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/vo_gpu_next.c
- ★ https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/player/video.c
- ★ https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/vulkan/context.c
- ★ https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/vulkan/context_mac.m
- ★ https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/mac/common.swift
- ★ https://raw.githubusercontent.com/haasn/libplacebo/92b5ac6/src/vulkan/swapchain.c
- ★ https://raw.githubusercontent.com/KhronosGroup/MoltenVK/v1.4.2/MoltenVK/MoltenVK/GPUObjects/MVKSurface.mm
- https://raw.githubusercontent.com/KhronosGroup/MoltenVK/v1.4.2/MoltenVK/MoltenVK/GPUObjects/MVKSwapchain.mm
- https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/vo.h
- https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/gpu_next/context.c
- https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/vulkan/context.h

## B. mpv properties (master or 3186d369)

**B1.** Setting `video-aspect-override` or `video-crop` at runtime while PAUSED:
- Is the picture redrawn immediately?
- Does an observer of `video-params/dw,dh` fire without resuming playback?

Quote the `UPDATE_IMGPAR` path.

**B2.** Do `video-aspect-override` and `video-crop` set via `mpv_set_property` persist across `loadfile` in the same mpv instance? We reset the UI's choice per file and need to know whether to reset mpv too.

**B3.** Confirm that `video-dec-params/par` is the decoder pixel aspect ratio WITHOUT the aspect override. input.rst says `video-dec-params` is "Exactly like video-params, but no overrides applied". Our crop method, for review: we compute a VLC-style ratio crop as `WxH+X+Y` in source pixels from w,h and the full-frame display ratio (the override ratio if set, else `w*par/h`), inverting the target for 90/270° rotation. Any flaw?

Sources for B:
- ★ https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/DOCS/man/input.rst
- ★ https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/filters/f_decoder_wrapper.c
- https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/DOCS/man/options.rst
- https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/player/command.c
- https://raw.githubusercontent.com/mpv-player/mpv/3186d369f9f090cd1363be0ac46a037824b702c6/video/mp_image.c

## C. AppKit / SwiftUI / Swift 6.2 (macOS 26 SDK)

**C1.** ZStack layering. An NSViewRepresentable NSView (handles mouseDown, mouseDragged, scrollWheel and `menu(for:)`) sits under a full-size SwiftUI GeometryReader. The GeometryReader contains only a card moved with `.offset`; the card has `.gesture` and `.onHover`.
- Do clicks, scrolls and right-clicks on the EMPTY area of the GeometryReader reach the NSView?
- Does `.onHover` on the card still fire?

Primary sources only: Apple docs, a WWDC session, or a forum answer by an Apple engineer.

**C2.** `@FocusedObject` read inside a View used as CommandMenu content (the Apple engineer workaround in developer.apple.com/forums/thread/651748). Are there documented macOS 14–26 bugs where Picker items inside a CommandMenu go stale when the focused ObservableObject publishes or the key window changes? Give Feedback IDs or forum threads with dates.

**C3.** Swift 6.2 with `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` and approachable concurrency: a non-`@Sendable` closure passed to an Objective-C API from a MainActor method.
- Is it inferred `@MainActor`?
- Does the compiler insert a dynamic isolation check that traps if the framework calls it off the main thread?

Apply this to:
- `MPRemoteCommand.addTarget(handler:)` (thread undocumented);
- `NotificationCenter.addObserver(forName:object:queue: .main)` with `MainActor.assumeIsolated` inside;
- a Combine `NotificationCenter.Publisher.sink`.

Is this pattern correct, and does it compile?

```swift
center.playCommand.addTarget { @Sendable _ in
    Task { @MainActor in NowPlayingCoordinator.shared.play() }
    return .success
}
```

Quote the Swift Evolution proposals (SE-0423 dynamic isolation checks, SE-0466 default isolation, SE-0470 isolated conformances).

**C4.** Does `NSWindow.contentAspectRatio` constrain programmatic `setFrame(_:display:)` / `setFrame(_:display:animate:)` in practice on macOS 14–26? Apple's contentAspectRatio page says programmatic sizes ignore it. Our code comment claims AppKit reshaped `setFrame` to the locked ratio, and raised an exception in `-[NSWindow _reallySetFrame:]` for a full-screen rect. Evidence only.

**C5.** Does a right-click (rightMouseDown → `menu(for:)`) on a non-key window of the active app make that window key before or after the menu shows?

Sources for C:
- ★ https://raw.githubusercontent.com/swiftlang/swift-evolution/main/proposals/0423-dynamic-actor-isolation.md
- ★ https://raw.githubusercontent.com/swiftlang/swift-evolution/main/proposals/0466-control-default-actor-isolation.md
- https://raw.githubusercontent.com/swiftlang/swift-evolution/main/proposals/0470-isolated-conformances.md
- https://raw.githubusercontent.com/swiftlang/swift-evolution/main/proposals/0461-async-function-isolation.md
- https://raw.githubusercontent.com/swiftlang/swift-evolution/main/visions/approachable-concurrency.md
- ★ https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/contentaspectratio.json
- https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/setframe(_:display:animate:).json
- https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/minsize.json
- https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/performdrag(with:).json
- https://developer.apple.com/tutorials/data/documentation/mediaplayer/mpremotecommand/addtarget(handler:).json
- ★ https://developer.apple.com/tutorials/data/documentation/swiftui/focusedobject.json
- https://developer.apple.com/tutorials/data/documentation/swiftui/view/focusedsceneobject(_:).json
- https://developer.apple.com/tutorials/data/documentation/swiftui/commandmenu.json
- ★ https://developer.apple.com/forums/thread/651748

## D. VLC 3.0.x macOS behaviour

Quote `modules/gui/macosx` at branch `3.0.x`. The relevant files are `Windows.m`, `VLCVoutWindowController.m`, `VLCInputManager.m`, `VLCResumeDialogController.m` and `VLCMainMenu.m`. In 3.0.x the resume logic is in `VLCInputManager.m` (`storePlaybackPositionForItem:` at line ~717, dialog shown at ~685), and the window classes are in `Windows.m` (`performZoom:` at ~324, `macosx-video-autoresize` at ~503).

**D1.** Float on Top: the exact NSWindow level VLC sets (see `VLCVoutWindowController.m` ~108, `NSStatusWindowLevel`), and how it is restored around fullscreen and minimize.

**D2.** Fit to Screen (⌘3): the exact geometry. `VLCMainMenu.m` ~950 calls `performZoom:` — what does VLC's override in `Windows.m` do?

**D3.** "Continue playback?" resume dialog:
- Is playback paused or playing while the dialog shows?
- What happens on the 10 s timeout?
- What happens if the user closes the window during it?

**D4.** Does VLC resize the video window when the user changes Aspect Ratio or Crop (`macosx-video-autoresize`, `resizeWindow`)? Quote.

**D5.** Esc in VLC 3 macOS: it leaves fullscreen (non-native or native). Does Esc do anything when windowed?

Sources for D:
- ★ https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/gui/macosx/Windows.m
- ★ https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/gui/macosx/VLCVoutWindowController.m
- ★ https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/gui/macosx/VLCInputManager.m
- ★ https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/gui/macosx/VLCResumeDialogController.m
- https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/gui/macosx/VLCMainMenu.m
- https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/gui/macosx/VLCVoutView.m
- https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/gui/macosx/macosx.m
- https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/gui/macosx/VLCCoreInteraction.m
- https://raw.githubusercontent.com/videolan/vlc/3.0.x/modules/control/hotkeys.c
- https://raw.githubusercontent.com/videolan/vlc/3.0.x/src/libvlc-module.c

## Output

Numbered A1–D5, each with VERDICT, quotes, URLs and code. No preamble.
