You are a principal engineer and product designer reviewing AMP (Aagedal Media Player), a macOS 26 SwiftUI/AppKit video player on Apple Silicon. Playback: libmpv (mpv master, vo=gpu-next, libplacebo master, MoltenVK 1.4.2, CAMetalLayer attached via `wid`, hwdec=videotoolbox zero-copy, custom MPVKit fork with CVDisplayLink vsync patch) plus AVPlayer only for ProRes RAW. Full app source, CLAUDE.md, a VLC-macOS behaviour catalog taken from VLC source, and AMP's current GUI inventory follow below.

The owner's goals: (1) AMP's GUI must behave like VLC for macOS (decided: switchable keymap VLC default / "AMP Pro" with JKL; double-click on video = fill screen but stay windowed, not native fullscreen); (2) best possible image quality per source on Apple Silicon; (3) rock-solid, fast, low-power engine; (4) clean maintainable architecture.

Answer EVERY question below. Be concrete: file + function names from the source, exact mpv option strings, Swift code snippets where useful, risk and effort for each change. Mark anything you are unsure of as "UNCERTAIN" and never invent APIs (e.g. state clearly whether libmpv's render API has a Metal backend in 2026, do not guess). Flag every bug, race, leak or harmful setting you spot in the source, with file:function. Prioritise: end with a single ranked TOP-30 action list (impact/effort). Use up to your full output budget.

## A. VLC GUI parity (implementation details)
A1. Mouse on video via a transparent NSView in the SwiftUI ZStack (between video and overlay controls): performDrag after 3pt threshold vs on mouseDown; clickCount==2 reliability; does it block .onContinuousHover/.onHover or overlay clicks; hitTest/acceptsFirstMouse needs; where exactly to insert in PlayerView/ContentView given the existing overlay structure.
A2. Fill-screen-stay-windowed toggle: does contentAspectRatio constrain programmatic setFrame? zoom(_:)+windowWillUseStandardFrame vs manual save/restore given SwiftUI owns the NSWindow delegate and WindowConfigurator manages size/aspect; interaction with openMaximized (first media load already fills visibleFrame — what should the first double-click do then?).
A3. Scroll wheel copy of VLC (Y threshold 1.0, X 0.8, axis lock 0.4 s, natural-direction inversion): deltaY vs scrollingDeltaY; momentum events; Magic Mouse vs trackpad vs wheel mouse; seek 3 s per step vs AMP multi-window sync.
A4. Right-click menu on the video (VLC voutMenu) — NSMenu target/action vs closures in Swift 6; full item list including tracks/aspect/crop submenus.
A5. Switchable keymap design: local NSEvent monitor vs SwiftUI .keyboardShortcut precedence; making menu shortcut labels follow the active keymap; avoiding conflicts with focused text fields, timecode entry, Compare Mode, Full Keyboard Access; the existing user keybindings.json override (KeyBindingTable).
A6. Dynamic Audio / Video / Subtitles top-level menus with per-file track lists in a SwiftUI App: CommandMenu+ForEach over observable state of the KEY window's controller (multi-window!) vs NSMenuDelegate on NSApp.mainMenu; does SwiftUI wipe manual menus.
A7. VLC on-screen messages ("Volume 85%", "0:42 / 1:30:00", "Audio track: English", "Speed: 1.25x"): SwiftUI overlay vs mpv show-text/osd; design that works for both backends and fullscreen, plus accessibility (VoiceOver announcements).
A8. Resume playback like VLC (ask/always/never, store rules: skip <3 min, <5% & <60 s, >95% & <60 s left; 10 s countdown): key by path vs bookmark vs fileResourceIdentifier in a (sandboxed?) app — check the entitlements implied by the source; UI for the prompt that doesn't block playback start.
A9. Now Playing / media keys (MPRemoteCommandCenter + MPNowPlayingInfoCenter) for libmpv audio: playbackState, elapsed time updates cadence, artwork from a frame, multi-window (which window owns it), Sparkle/no entitlements needed?
A10. Window: VLC ⌘0/⌘1/⌘2/⌘3 half/normal/double/fit with Retina backing scale, Float on Top (window level and fullscreen interplay), aspect lock on user resize after maximize, VLC "video-autoresize" on new file.
A11. Volume up to 125% (VLC max): PlaybackVolume.mpvValue cube-root mapping above 100, mpv volume-max, AVPlayer's 0–1 cap, slider UI with a tick at 100%.
A12. Anything else in VLC macOS's GUI a VLC user would miss in AMP (Jump to Time ⌘J, A→B loop, playlist window, snapshot, track sync window, video/audio effects panel, subtitle styling, drag-drop subtitle onto window, title with proxy icon, close window stops playback, pause on minimize) — which are worth copying, how.

## B. Architecture & code quality
B1. PlayerController size/responsibilities — concrete decomposition with file names and the order to do it without breaking SwiftUI bindings; ObservableObject → @Observable migration worth it?
B2. Swift 6 concurrency: MPVPlayer @unchecked Sendable, event loop/wakeup callback threading (is there redundant GCD dispatch per wakeup?), nonisolated(unsafe) observers, MainActor.assumeIsolated uses — list each unsafe spot and the safe replacement.
B3. NotificationCenter-based AppCommand broadcast for multi-window: keep or replace (focused values, per-window command routers)?
B4. Testability: what to mock, which pure functions to extract, which existing tests are weak or flaky by design.
B5. Dead code, duplicated logic, over-engineering you can see (e.g. multiple reload hacks); what to delete.
B6. Error handling / diagnostics: logging, crash resilience if mpv/MoltenVK fails, recovery paths.

## C. Metal / render backend
C1. `wid` + MoltenVK CAMetalLayer vs libmpv render API (mpv_render_context) in 2026: which APIs actually exist (OpenGL, SW, Vulkan? Metal?), what AMP gains/loses, the stale dst-rect / force-reload hacks in MPVViewController — root cause and proper fix.
C2. HDR/EDR on CAMetalLayer: colorspace, wantsExtendedDynamicRangeContent, CAEDRMetadata, target-peak / target-colorspace-hint / target-trc choices, reference white, XDR displays vs SDR external monitors, ICC profiles (DisplayColorController/DisplayICCProfileStore) — review the current code for errors.
C3. Vsync and frame pacing: CVDisplayLink patch vs CADisplayLink (macOS 14+), ProMotion/VRR, video-sync=display-resample + interpolation (tscale choice), 24p on 60/120 Hz, judder, frame drops, power cost.
C4. Resizing/fullscreen transitions without flicker or reload; drawableSize/contentsScale handling; multiple displays with different scale/EDR.
C5. GPU budget / power: GPUBudgetMonitor, battery vs AC policies, thermal state; what to throttle first.

## D. Engine
D1. hwdec=videotoolbox(-copy) correctness for 10-bit/HDR/HEVC/AV1(M3+)/VP9/ProRes; fallback strategy; gpu-hwdec-interop.
D2. Demuxer/cache options (demuxer-max-bytes/back-bytes, cache, readahead) for local 4K/8K, network streams, and backward playback (ReverseBufferPolicy).
D3. Seeking: hr-seek, exact vs keyframe while scrubbing vs on release, thumbnail scrubbing cost, frame stepping backward performance.
D4. Startup latency: time-to-first-frame budget, what in setupMPV/preparePlayback/metadata loading blocks it, parallelisation.
D5. Audio: coreaudio vs avfoundation AO, exclusive mode (pros/cons for a general player — is exclusive harmful?), spdif passthrough, gapless, loudness/replaygain, audio-device switching, channel routing correctness.
D6. Subtitles: libass settings, sub-scale/fonts, embedded fonts, PGS/VobSub, sub-auto, secondary subs, subtitle-delay UI.
D7. Network/streaming: should AMP support URLs/yt-dlp; ytdl hook; security considerations.
D8. Multi-window synchronized playback design soundness.

## E. Image quality (Apple Silicon M1–M5)
E1. Scalers: lanczos vs ewa_lanczos vs ewa_lanczossharp vs spline36 cost on Apple GPUs at 1080p→4K/5K, 4K→5K, 720p→4K; when `scaler-resizes-only`, `correct-downscaling`, `linear-downscaling`, `sigmoid-upscaling`, antiring are worth it. Review RenderProfile/profile picker/classifier choices and cost table for mistakes.
E2. Chroma: cscale choice, KrigBilateral (is it a neural net? no — state precisely), CfL (cfl.glsl), 4:2:2 handling.
E3. Neural/prescalers: ArtCNN variants, FSRCNNX, nnedi3, Anime4K, RAVU — which are actually worth it per source class on M-series, frame budgets at 24/30/60 fps and 120 Hz displays.
E4. Deband (params per source), dither (dither-depth auto, error-diffusion), grain (film grain synthesis vs added grain), nlmeans denoise cost/benefit, sharpening (adaptive-sharpen, CAS) for compressed web video.
E5. Tone mapping: spline vs bt.2390 vs bt.2446a vs st2094-40/10 for HDR10/HLG/Dolby Vision profile 5/8 on SDR, EDR and XDR displays; gamut mapping mode; hdr-compute-peak / peak detection; inverse tone mapping of SDR on XDR (should it be off?).
E6. Deinterlacing (bwdif/yadif, auto detection) and telecine; interpolation/motion smoothing (tscale oversample vs mitchell etc.).
E7. Automatic per-source profile selection: what signals to use (bitrate, codec, resolution, fps, film grain, banding stats), and how to verify quality objectively (VMAF/SSIM/butteraugli on captures) in tests.
E8. Anything in the current quality pipeline that is harmful or wasted GPU.

## F. Product & UX
F1. Top UX gaps vs IINA and VLC beyond the above (playlist UI, thumbnails on scrub, PiP, chapters, A-B loop, bookmarks, recent files, welcome window).
F2. Settings organisation; defaults a first-time user should get.
F3. Accessibility (VoiceOver, Full Keyboard Access, reduced motion, contrast), localisation readiness.
F4. Performance perceived by users: app launch time, window open time, memory footprint with multiple windows.
F5. Distribution: Sparkle updates, notarization, hardened runtime, sandbox (yes/no for a player), crash reporting, privacy.
F6. Security: bundled ffmpeg binary invocation (argument injection via filenames?), keybindings.json parsing, subtitle files, URL handling.

## G. Testing & verification
G1. How to automate GUI behaviour tests for the VLC parity (XCUITest feasibility for mouse/scroll/menu), and render-quality regression tests.
G2. Which current tests to add first given the risk areas.

## H. Final output
H1. Ranked TOP-30 action list (impact, effort S/M/L, risk), each a one-line imperative referencing files.
H2. Things AMP should NOT do (bad ideas commonly suggested).
