# IINA-parity implementation plans

Five independent plans. Each ships working, testable software on its own, and each
can be executed without reading the others.

| # | Plan | Ships | Depends on |
|---|------|-------|-----------|
| 0 | [Land the in-flight work](2026-09-12-00-land-inflight-work.md) | The uncommitted session work, committed in reviewable pieces | — |
| 1 | [Preferences, migration and menus](2026-09-12-01-preferences-and-menus.md) | Settings split into files, every setting reachable, dynamic menus, first-run migration | 0 |
| 2 | [Colour pipeline](2026-09-12-02-colour-pipeline.md) | Display-change handling, ICC profile, active HDR/EDR tone mapping | 0 |
| 3 | [Hardware decode and filters](2026-09-12-03-hwdec-and-filters.md) | hwdec capability probing, generic video filter chain | 0 |
| 4 | [User-editable key bindings](2026-09-12-04-key-bindings.md) | Key map loaded from disk, user-overridable | 0 |
| 5 | [Playback clock split](2026-09-12-05-playback-clock-split.md) | ContentView stops re-rendering on every clock tick | 0 |

Plan 0 must land first — everything else assumes a clean tree. Plans 1-5 are
independent of each other and can run in any order or in parallel worktrees.

## Scope decisions already made

**In scope:** the five plans above.

**Explicitly out of scope** — do not add these, they were each declined by name:
resume position and the welcome window's Resume row; trackpad/scroll/pinch input;
screenshot directory/format/template; playlist queue, shuffle and repeat;
everything subtitle-related (styling, auto-match, secondary track, `slang`);
thumbnail disk cache; reduce-motion; the fadeable-view system; titlebar and fade
behaviour; A-B loop and its scrubber knob; OSC layout modes; the on-screen display;
equalizer and audio-device selection; tabbed multi-pane sidebar; plugins; mini
player; online subtitles; PIP; localization; legacy fullscreen; `--geometry`
parsing; Open URL and network streaming; `iina-cli`; Live Text/OCR; interactive
crop; centralized logger and log window; security-scoped bookmarks; Touch Bar;
power-source awareness; memory reporting; standalone About/Guide/History windows.

## Reference source

Several tasks quote IINA. Clone it next to the project — the exact values matter,
so read them from the source rather than from these plans where a plan says to:

```bash
git clone --depth 1 --branch develop https://github.com/iina/iina.git /tmp/iina-reference
```

IINA is GPL-3.0 and this project is GPL-3.0-or-later, so porting code is fine.
Any ported file keeps an attribution header naming the original.
