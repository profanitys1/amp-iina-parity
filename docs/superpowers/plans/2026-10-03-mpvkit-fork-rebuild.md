# MPVKit Fork Rebuild (vsync + libplacebo/mpv master) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** amp plays every video with display-synced, interpolated presentation and no sustained frame drops on the 120 Hz panel, on top of libplacebo master and mpv master.

**Architecture:** Rebuild four pieces of the MPVKit-GPL binary set and leave every other prebuilt target alone. The four are libplacebo (from a pinned master commit via `mpvkit/libplacebo-build`), the FFmpeg GPL libraries (rebuilt only because `vf_libplacebo` links the API-versioned symbol `pl_log_create_<API>`), and libmpv-GPL (from a pinned mpv master commit). libmpv also gets a new patch that gives MPVKit's `moltenvk` gpu-context a CVDisplayLink-driven `get_vsync`. The binaries are published as a release on `profanitys1/MPVKit`, amp is pinned to that fork revision, and amp turns on `video-sync=display-resample` + `interpolation` for every profile except Faithful.

**Tech Stack:** Swift/SwiftUI macOS app (Xcode 27.0, macOS 27.0.1 host, M1 Pro), libmpv C API, MPVKit build scripts (Swift `make build`), meson/ninja, Objective-C (mpv context), CoreVideo CVDisplayLink, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-03-mpvkit-fork-rebuild-design.md`

## Global Constraints

- libplacebo pin: `92b5ac6db79f4d680eb656692f7bf51e9606f42a` (haasn/libplacebo master, 2026-10-01, API 7.374).
- mpv pin: `3186d369f9f090cd1363be0ac46a037824b702c6` (mpv-player/mpv master, 2026-09-29).
- MoltenVK stays 1.4.2. FFmpeg source stays `n8.1.2`. Every other binary target keeps its current URL and checksum.
- Fork: `https://github.com/profanitys1/MPVKit` (already exists, `main` = `230c317`, no releases). Release tag: `amp-1.0.0-mpv3186d36-pl92b5ac6`.
- Publishing a GitHub release and pushing to the fork are outward-facing: ask the user in chat and wait for a clear yes before each.
- Never judge amp's rendering with a standalone mpv. Verify only in `/Applications/amp.app` (memory `amp-run-and-bench`).
- Package managers: none are added. Build tools already present: meson 1.12.1, ninja, nasm, pkg-config, wget, cmake, sdl2, jinja2 (both `/opt/homebrew/bin/python3` and `/Library/Frameworks/Python.framework` python3).
- Git: plain `git commit -m "message"`, no attribution lines. In amp, commit only files this plan names (the tree has an unrelated untracked `.omc/`).
- Scratch directory for logs and downloads: `/private/tmp/claude-501/-Users-filip/76015831-5409-4349-b9b4-ff5981154e06/scratchpad` (below: `$SCRATCH`).

## Verified facts this plan relies on (2026-10-03)

| Fact | Source |
|---|---|
| No newer MoltenVK (1.4.2), libplacebo tag (7.360.1), MPVKit (1.0.0) or mpv tag (0.41.0) | `gh api repos/*/releases` |
| libplacebo master API 7.374 only adds fields and deprecates two functions since 7.360.1 | libplacebo `meson.build` API table |
| `pl_log_create` is `#define`d to `pl_log_create_<PL_API_VER>` "to force a link error" against another API version | libplacebo `src/include/libplacebo/log.h:65-68` |
| MPVKit's FFmpeg GPL build enables `--enable-libplacebo --enable-filter=libplacebo` when the libplacebo thin dir exists | `Sources/BuildScripts/XCFrameworkBuild/main.swift:618-634` |
| MPVKit downloads libplacebo as a zip and skips download when `dist/libplacebo-<version>/libplacebo.zip` exists, but only unzips after a download | `base.swift` `ZipBaseBuild.beforeBuild` |
| BuildShared/MPVKit `BaseBuild.beforeBuild` clones with `--branch <version>` and returns early when `dist/<lib>-<version>/` exists (patches are applied only on a fresh clone) | `BuildShared/Builders/BaseBuild.swift:30-53`, MPVKit `base.swift:113-137` |
| All three MPVKit libmpv patches apply cleanly to mpv `3186d369f9` | `git apply --check` run on 2026-10-03 |
| mpv master requires `libplacebo >= 7.360.1`, `libavcodec >= 60.31.102` (n8.1.2 satisfies) | mpv `meson.build:23-30` |
| mpv master already contains upstream CoreAudio cleanup fixes (`af067b5ea`, `c5d391adb`) | `git log -- audio/out/ao_coreaudio*` |
| Upstream `macvk` reports vsync from a CVDisplayLink: `last_queue_display_time` = first future output time, `vsync_duration` = `videoRefreshPeriod/videoTimeScale*1e9*rateScalar`, `skipped_vsyncs` = expired entries − 1 | mpv `video/out/mac_common.swift:103-110`, `osdep/mac/presentation.swift` |
| `vo_gpu_next` forwards unhandled controls, including `VOCTRL_VO_OPTS_CHANGED`, to `ra_ctx->fns->control`; `vo.c` sends it from the VO thread when any vo option changes | mpv `vo_gpu_next.c:2235-2246`, `vo.c:238-249` |
| `screen-name` is a string vo option (`mp_vo_opts.screen_name`); the `moltenvk` context never reads it today | mpv `options/options.c:181` |
| In display-sync mode a frame shown for more than one vsync is cached, so user shaders run once per source frame, then libplacebo blends cached frames per vsync | mpv `vo_gpu_next.c:1351-1358`, libplacebo `renderer.c:3939-4030` |
| `CVDisplayLink*` is deprecated since macOS 15 SDK but still present in MacOSX27.0.sdk | `CVDisplayLink.h:51` |
| SwiftPM binary zips are renamed `X.xcframework.zip -> X-GPL.xcframework.zip` by MPVKit's own CI for GPL targets | MPVKit `.github/workflows/build.yml` "Build GPL version" step |

## File Structure

New or changed, by repository:

- `~/src/libplacebo-build` (local clone of `mpvkit/libplacebo-build`, not pushed)
  - `Sources/BuildScripts/XCFrameworkBuild/main.swift`: pin libplacebo to the master commit.
- `~/src/MPVKit` (clone of `profanitys1/MPVKit`, branch `amp-master-vsync`)
  - `Sources/BuildScripts/XCFrameworkBuild/main.swift`: pin mpv commit, point libplacebo at the local build.
  - `Sources/BuildScripts/patch/libmpv/0004-moltenvk-vsync-feedback.patch`: new. Adds CVDisplayLink vsync to `context_moltenvk.m`.
  - `Sources/BuildScripts/amp/libplacebo-build-pin.patch`: new. The libplacebo-build change, kept so the release is reproducible from this one repo.
  - `Package.swift`: 9 GPL/libplacebo binary targets repointed to the new release.
- `~/src/amp`
  - `Aagedal Media Player/Logic/MPV/RenderProfile.swift`: add `playbackSyncOptions`.
  - `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`: set interpolation options at init, apply sync options per profile, set `screen-name` and `display-fps-override` before init and on change.
  - `Aagedal Media Player/Logic/MPV/MPVVideoView.swift`: pass the display ID with the refresh rate.
  - `Aagedal Media Player Tests/RenderProfileTests.swift`: one new test.
  - `Aagedal Media Player.xcodeproj/project.pbxproj`, `.../xcshareddata/swiftpm/Package.resolved`: MPVKit repository and revision.
  - `CLAUDE.md`: dependency paragraph.
  - `docs/research/2026-10-03-vsync-bench.md`: new. Measurements.

---

### Task 1: Workspaces

**Files:**
- Create: `~/src/MPVKit` (clone), `~/src/libplacebo-build` (clone)

**Interfaces:**
- Produces: `~/src/MPVKit` on branch `amp-master-vsync` with remotes `origin` = profanitys1, `upstream` = aagedal; `~/src/libplacebo-build` at `2e69520`.

- [ ] **Step 1: Clone both repos**

```bash
git clone https://github.com/profanitys1/MPVKit.git ~/src/MPVKit
git -C ~/src/MPVKit remote add upstream https://github.com/aagedal/MPVKit.git
git clone https://github.com/mpvkit/libplacebo-build.git ~/src/libplacebo-build
```

- [ ] **Step 2: Create the work branch in MPVKit**

`~/src/MPVKit` is a fresh single-purpose clone, so the branch lives in its main worktree (no Worktrunk worktree needed):

```bash
cd ~/src/MPVKit && git switch -c amp-master-vsync
```

- [ ] **Step 3: Verify starting points**

Run: `git -C ~/src/MPVKit log -1 --format=%h; git -C ~/src/libplacebo-build log -1 --format=%h`
Expected: `230c317` and `2e69520`.

---

### Task 2: Build libplacebo master

**Files:**
- Modify: `~/src/libplacebo-build/Sources/BuildScripts/XCFrameworkBuild/main.swift` (the `.libplacebo` version case, and `BuildPlacebo.beforeBuild`)

**Interfaces:**
- Produces: `~/src/libplacebo-build/dist/release/libplacebo-all.zip`, `Libplacebo.xcframework.zip`, `Libplacebo.xcframework.checksum.txt`. The library exports `pl_log_create_374`.

- [ ] **Step 1: Pin the version string**

In `main.swift`, inside `var version: String`, replace

```swift
        case .libplacebo:
            return "v7.360.1"
```

with

```swift
        case .libplacebo:
            // Directory/tag label only. The source commit is pinned in BuildPlacebo.beforeBuild.
            return "v7.374.0-92b5ac6"
```

- [ ] **Step 2: Clone the pinned commit before the base class runs**

Replace the whole `override func beforeBuild() throws { ... }` of `private class BuildPlacebo` with:

```swift
    // Untagged libplacebo master, pinned by commit. BaseBuild can only clone a
    // branch or tag, and it skips cloning when the directory exists, so clone
    // and check out here first.
    static let commit = "92b5ac6db79f4d680eb656692f7bf51e9606f42a"

    override func beforeBuild() throws {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try Utility.launch(path: "/usr/bin/git", arguments: ["clone", library.url, directoryURL.path])
            try Utility.launch(path: "/usr/bin/git", arguments: ["-c", "advice.detachedHead=false", "checkout", Self.commit], currentDirectoryURL: directoryURL)
        }
        try super.beforeBuild()

        // pull all submodules (Vulkan-Headers, glad, jinja, fast_float)
        Utility.shell("git submodule update --init --recursive", currentDirectoryURL: directoryURL)

        // install jinja2 for distutils dependency
        if Utility.shell("python3 -m pip list|grep jinja2") == nil {
            Utility.shell("python3 -m pip install jinja2")
        }
    }
```

- [ ] **Step 3: Build macOS only, in the background, with a log**

```bash
cd ~/src/libplacebo-build && make build platform=macos > "$SCRATCH/libplacebo-build.log" 2>&1
```

Run with `run_in_background: true`, timeout 3600000. Expected exit 0.

- [ ] **Step 4: Verify the API version and outputs**

```bash
cd ~/src/libplacebo-build/dist
ls release/libplacebo-all.zip release/Libplacebo.xcframework.zip release/Libplacebo.xcframework.checksum.txt
rg -n "^Version" release/libplacebo/pkgconfig-example/macos/arm64/libplacebo.pc
nm -g release/libplacebo/lib/macos/thin/arm64/lib/libplacebo.a 2>/dev/null | rg " T _pl_log_create_"
```

Expected: the three files exist, `Version: 7.374.0`, and `T _pl_log_create_374`. If the `.pc` path differs, list it with `fd libplacebo.pc release` and read `Version` there.

- [ ] **Step 5: Save the recipe change for the fork**

```bash
mkdir -p ~/src/MPVKit/Sources/BuildScripts/amp
git -C ~/src/libplacebo-build diff > ~/src/MPVKit/Sources/BuildScripts/amp/libplacebo-build-pin.patch
```

Expected: a non-empty patch touching only `Sources/BuildScripts/XCFrameworkBuild/main.swift`.

---

### Task 3: Vsync feedback patch for the `moltenvk` context

**Files:**
- Create: `~/src/MPVKit/Sources/BuildScripts/patch/libmpv/0004-moltenvk-vsync-feedback.patch`

**Interfaces:**
- Consumes: `context_moltenvk.m` as created by patch `0001`.
- Produces: `ra_ctx_vulkan_moltenvk` with `get_vsync`. Display selection contract for embedders: mpv option `screen-name` holds the target `CGDirectDisplayID` in decimal; empty or non-numeric means `CGMainDisplayID()`.

- [ ] **Step 1: Prepare a patched mpv tree**

```bash
git clone https://github.com/mpv-player/mpv.git "$SCRATCH/mpv-patch"
cd "$SCRATCH/mpv-patch" && git -c advice.detachedHead=false checkout 3186d369f9f090cd1363be0ac46a037824b702c6
for p in ~/src/MPVKit/Sources/BuildScripts/patch/libmpv/000[123]-*.patch; do git apply "$p"; done
git add -A && git commit -qm "MPVKit patches 0001-0003"
```

Expected: no `git apply` errors.

- [ ] **Step 2: Replace `video/out/vulkan/context_moltenvk.m` with the vsync-aware version**

Write this exact content to `$SCRATCH/mpv-patch/video/out/vulkan/context_moltenvk.m`:

```objc
/*
 * This file is part of mpv.
 *
 * mpv is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * mpv is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with mpv.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdlib.h>
#include <string.h>

#include <CoreGraphics/CoreGraphics.h>
#include <CoreVideo/CoreVideo.h>
#include <QuartzCore/CAMetalLayer.h>
#include <MoltenVK/mvk_vulkan.h>

#include "options/options.h"
#include "osdep/threads.h"
#include "osdep/timer.h"

#include "common.h"
#include "context.h"
#include "utils.h"

// CVDisplayLink is deprecated since the macOS 15 SDK in favour of NSView/NSScreen
// display links, which need AppKit objects this embedded context does not own.
// Upstream mpv's macvk context still uses CVDisplayLink for the same timing.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Upcoming display times reported by the display link. 64 entries cover more
// than half a second at 120 Hz; older entries are dropped and counted as skipped.
#define VSYNC_SLOTS 64

struct priv {
    struct mpvk_ctx vk;
    CAMetalLayer *layer;

    CVDisplayLinkRef link;
    CGDirectDisplayID display;
    mp_mutex lock;
    int64_t times[VSYNC_SLOTS];     // mp_time_ns() of each upcoming vsync, ascending
    int64_t durations[VSYNC_SLOTS]; // refresh period at that vsync, in ns
    int count;
    int overflowed;                 // entries dropped because the buffer was full
};

static CVReturn display_link_cb(CVDisplayLinkRef link, const CVTimeStamp *now,
                                const CVTimeStamp *output, CVOptionFlags flags_in,
                                CVOptionFlags *flags_out, void *ctx)
{
    struct priv *p = ctx;
    int64_t time = mp_time_ns_from_raw_time(mp_raw_time_ns_from_mach(output->hostTime));
    int64_t duration = 0;
    if (output->videoTimeScale > 0) {
        duration = (int64_t)((double)output->videoRefreshPeriod / output->videoTimeScale
                             * 1e9 * output->rateScalar);
    }

    mp_mutex_lock(&p->lock);
    if (p->count == VSYNC_SLOTS) {
        memmove(p->times, p->times + 1, (VSYNC_SLOTS - 1) * sizeof(p->times[0]));
        memmove(p->durations, p->durations + 1, (VSYNC_SLOTS - 1) * sizeof(p->durations[0]));
        p->count--;
        p->overflowed++;
    }
    p->times[p->count] = time;
    p->durations[p->count] = duration;
    p->count++;
    mp_mutex_unlock(&p->lock);
    return kCVReturnSuccess;
}

// The display the embedder asked for through --screen-name (a decimal
// CGDirectDisplayID), else the main display.
static CGDirectDisplayID requested_display(struct ra_ctx *ctx)
{
    const char *name = ctx->vo->opts->screen_name;
    if (name && name[0]) {
        char *end = NULL;
        unsigned long id = strtoul(name, &end, 10);
        if (end && *end == '\0' && id > 0)
            return (CGDirectDisplayID)id;
    }
    return CGMainDisplayID();
}

static void bind_display(struct ra_ctx *ctx)
{
    struct priv *p = ctx->priv;
    CGDirectDisplayID display = requested_display(ctx);
    if (!p->link || p->display == display)
        return;
    if (CVDisplayLinkSetCurrentCGDisplay(p->link, display) != kCVReturnSuccess) {
        MP_WARN(ctx, "Could not bind display link to display %u\n", display);
        return;
    }
    p->display = display;
    // Times queued for the previous display no longer describe this one.
    mp_mutex_lock(&p->lock);
    p->count = 0;
    p->overflowed = 0;
    mp_mutex_unlock(&p->lock);
    MP_VERBOSE(ctx, "Display link bound to display %u\n", display);
}

static void moltenvk_get_vsync(struct ra_ctx *ctx, struct vo_vsync_info *info)
{
    struct priv *p = ctx->priv;
    if (!p->link)
        return;

    int64_t now = mp_time_ns();
    mp_mutex_lock(&p->lock);
    int expired = 0;
    while (expired < p->count && p->times[expired] <= now)
        expired++;
    int removed = expired + p->overflowed;
    p->overflowed = 0;
    p->count -= expired;
    memmove(p->times, p->times + expired, p->count * sizeof(p->times[0]));
    memmove(p->durations, p->durations + expired, p->count * sizeof(p->durations[0]));
    if (p->count > 0) {
        info->last_queue_display_time = p->times[0];
        info->vsync_duration = p->durations[0];
        info->skipped_vsyncs = MPMAX(removed - 1, 0);
    } else {
        info->vsync_duration = -1;
        info->skipped_vsyncs = -1;
        info->last_queue_display_time = -1;
    }
    mp_mutex_unlock(&p->lock);
}

static void stop_display_link(struct priv *p)
{
    if (!p->link)
        return;
    CVDisplayLinkStop(p->link);
    CVDisplayLinkRelease(p->link);
    p->link = NULL;
}

static void moltenvk_uninit(struct ra_ctx *ctx)
{
    struct priv *p = ctx->priv;
    stop_display_link(p);
    ra_vk_ctx_uninit(ctx);
    mpvk_uninit(&p->vk);
    mp_mutex_destroy(&p->lock);
}

static void start_display_link(struct ra_ctx *ctx)
{
    struct priv *p = ctx->priv;
    if (CVDisplayLinkCreateWithActiveCGDisplays(&p->link) != kCVReturnSuccess || !p->link) {
        p->link = NULL;
        MP_WARN(ctx, "No display link; frame timing falls back to the swap time\n");
        return;
    }
    CVDisplayLinkSetOutputCallback(p->link, display_link_cb, p);
    bind_display(ctx);
    if (CVDisplayLinkStart(p->link) != kCVReturnSuccess) {
        MP_WARN(ctx, "Could not start display link\n");
        CVDisplayLinkRelease(p->link);
        p->link = NULL;
    }
}

static bool moltenvk_init(struct ra_ctx *ctx)
{
    struct priv *p = ctx->priv = talloc_zero(ctx, struct priv);
    struct mpvk_ctx *vk = &p->vk;
    int msgl = ctx->opts.probing ? MSGL_V : MSGL_ERR;
    mp_mutex_init(&p->lock);

    if (ctx->vo->opts->WinID == -1) {
        MP_MSG(ctx, msgl, "WinID missing\n");
        goto fail;
    }

    if (!mpvk_init(vk, ctx, VK_EXT_METAL_SURFACE_EXTENSION_NAME))
        goto fail;

    p->layer = (__bridge CAMetalLayer *)(intptr_t)ctx->vo->opts->WinID;
    VkMetalSurfaceCreateInfoEXT info = {
         .sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
         .pLayer = p->layer,
    };

    struct ra_ctx_params params = {
        .get_vsync = moltenvk_get_vsync,
    };

    VkInstance inst = vk->vkinst->instance;
    VkResult res = vkCreateMetalSurfaceEXT(inst, &info, NULL, &vk->surface);
    if (res != VK_SUCCESS) {
        MP_MSG(ctx, msgl, "Failed creating MoltenVK surface\n");
        goto fail;
    }

    if (!ra_vk_ctx_init(ctx, vk, params, VK_PRESENT_MODE_FIFO_KHR))
        goto fail;

    start_display_link(ctx);
    return true;
fail:
    moltenvk_uninit(ctx);
    return false;
}

static bool moltenvk_reconfig(struct ra_ctx *ctx)
{
    struct priv *p = ctx->priv;
    CGSize s = p->layer.drawableSize;
    ra_vk_ctx_resize(ctx, s.width, s.height);
    return true;
}

static int moltenvk_control(struct ra_ctx *ctx, int *events, int request, void *arg)
{
    // vo.c sends this on the VO thread whenever a vo option such as
    // --screen-name changes, so the display link follows the window.
    if (request == VOCTRL_VO_OPTS_CHANGED)
        bind_display(ctx);
    return VO_NOTIMPL;
}

#pragma clang diagnostic pop

const struct ra_ctx_fns ra_ctx_vulkan_moltenvk = {
    .type           = "vulkan",
    .name           = "moltenvk",
    .reconfig       = moltenvk_reconfig,
    .control        = moltenvk_control,
    .init           = moltenvk_init,
    .uninit         = moltenvk_uninit,
};
```

- [ ] **Step 3: Generate the patch**

```bash
cd "$SCRATCH/mpv-patch" && git diff > ~/src/MPVKit/Sources/BuildScripts/patch/libmpv/0004-moltenvk-vsync-feedback.patch
```

- [ ] **Step 4: Verify the patch series applies to a clean mpv tree**

```bash
cd "$SCRATCH/mpv-patch" && git reset -q --hard 3186d369f9f090cd1363be0ac46a037824b702c6
for p in ~/src/MPVKit/Sources/BuildScripts/patch/libmpv/*.patch; do git apply --check "$p" && git apply "$p" || echo "FAIL $p"; done
rg -n "moltenvk_get_vsync|VOCTRL_VO_OPTS_CHANGED" video/out/vulkan/context_moltenvk.m
```

Expected: no `FAIL` line. Both names found. The compile check happens in Task 4.

- [ ] **Step 5: Commit**

```bash
cd ~/src/MPVKit && git add Sources/BuildScripts/patch/libmpv/0004-moltenvk-vsync-feedback.patch Sources/BuildScripts/amp/libplacebo-build-pin.patch
git commit -m "Add CVDisplayLink vsync feedback to the moltenvk context"
```

---

### Task 4: Build FFmpeg-GPL and libmpv-GPL against libplacebo master

**Files:**
- Modify: `~/src/MPVKit/Sources/BuildScripts/XCFrameworkBuild/main.swift` (`Library.version` for `.libmpv` and `.libplacebo`; `BuildMPV`)

**Interfaces:**
- Consumes: `~/src/libplacebo-build/dist/release/libplacebo-all.zip` (Task 2), patch `0004` (Task 3).
- Produces: in `~/src/MPVKit/dist/release/`: `Libmpv-GPL.xcframework.zip`, `Libavcodec-GPL`, `Libavdevice-GPL`, `Libavformat-GPL`, `Libavfilter-GPL`, `Libavutil-GPL`, `Libswresample-GPL`, `Libswscale-GPL` `.xcframework.zip` and matching `.xcframework.checksum.txt`.

- [ ] **Step 1: Pin versions**

In `main.swift` `var version: String`:

```swift
        case .libmpv:
            // Directory label only. The source commit is pinned in BuildMPV.beforeBuild.
            return "master-3186d36"
```

and

```swift
        case .libplacebo:
            // Built locally from libplacebo master 92b5ac6 by mpvkit/libplacebo-build
            // (recipe: Sources/BuildScripts/amp/libplacebo-build-pin.patch).
            return "7.374.0-92b5ac6"
```

- [ ] **Step 2: Clone mpv at the pinned commit and apply the patches**

Add to `private class BuildMPV: BaseBuild`, directly after `init()`:

```swift
    // Untagged mpv master, pinned by commit. BaseBuild clones only a branch or
    // tag and applies patches only on a fresh clone, so do both here.
    static let commit = "3186d369f9f090cd1363be0ac46a037824b702c6"

    override func beforeBuild() throws {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try Utility.launch(path: "/usr/bin/git", arguments: ["clone", library.url, directoryURL.path])
            try Utility.launch(path: "/usr/bin/git", arguments: ["-c", "advice.detachedHead=false", "checkout", Self.commit], currentDirectoryURL: directoryURL)
            let patchDir = URL.currentDirectory + "../Sources/BuildScripts/patch/libmpv"
            let names = try FileManager.default.contentsOfDirectory(atPath: patchDir.path).sorted()
            for name in names where name.hasSuffix(".patch") {
                try Utility.launch(path: "/usr/bin/git", arguments: ["apply", (patchDir + name).path], currentDirectoryURL: directoryURL)
            }
        }
        try super.beforeBuild()
    }
```

- [ ] **Step 3: Stage the local libplacebo zip where ZipBaseBuild looks**

```bash
mkdir -p ~/src/MPVKit/dist/libplacebo-7.374.0-92b5ac6
cp ~/src/libplacebo-build/dist/release/libplacebo-all.zip ~/src/MPVKit/dist/libplacebo-7.374.0-92b5ac6/libplacebo.zip
cd ~/src/MPVKit/dist/libplacebo-7.374.0-92b5ac6 && unzip -oq libplacebo.zip && ls
```

Expected: `include  lib  libplacebo.zip  pkgconfig-example`.

- [ ] **Step 4: Run the GPL build for macOS, in the background**

```bash
cd ~/src/MPVKit && make build enable-gpl platform=macos version=amp-1.0.0-mpv3186d36-pl92b5ac6 > "$SCRATCH/mpvkit-gpl-build.log" 2>&1
```

`run_in_background: true`, timeout 7200000. Expected exit 0. On failure read the failing library's log (`dist/<lib>-<version>.log` or the last 80 lines of `$SCRATCH/mpvkit-gpl-build.log`) and fix the cause before retrying. Delete `dist/libmpv-master-3186d36` before a retry that changes patches, because patches are applied only on a fresh clone.

Fallback A (spec): if the failure is inside mpv master itself (not the 0004 patch, not libplacebo), switch libmpv to the tag: set `case .libmpv: return "v0.41.0"`, delete the `BuildMPV.beforeBuild` override and `static let commit`, run `rm -rf dist/libmpv-*`, confirm `git apply --check` of all four patches against a `v0.41.0` checkout, and rerun Step 4. Use tag `amp-1.0.0-mpv0410-pl92b5ac6` everywhere this plan says `amp-1.0.0-mpv3186d36-pl92b5ac6`.

- [ ] **Step 5: Rename to the GPL target names (same as MPVKit CI)**

```bash
cd ~/src/MPVKit/dist/release
for f in Libmpv Libavcodec Libavdevice Libavformat Libavfilter Libavutil Libswresample Libswscale; do
  mv "$f.xcframework.zip" "$f-GPL.xcframework.zip"
  swift package compute-checksum "$f-GPL.xcframework.zip" > "$f-GPL.xcframework.checksum.txt"
  rm -f "$f.xcframework.checksum.txt"
done
ls *-GPL.xcframework.zip | wc -l
```

Expected: `8`.

- [ ] **Step 6: Verify linkage and the new context**

```bash
cd ~/src/MPVKit/dist/release
nm -u libmpv/lib/macos/thin/arm64/lib/libmpv.a | rg "_pl_log_create_"
nm -u FFmpeg/lib/macos/thin/arm64/lib/libavfilter.a | rg "_pl_log_create_"
nm -g libmpv/lib/macos/thin/arm64/lib/libmpv.a | rg "ra_ctx_vulkan_moltenvk"
nm libmpv/lib/macos/thin/arm64/lib/libmpv.a | rg "moltenvk_get_vsync|_CVDisplayLinkSetOutputCallback"
```

Expected: both `nm -u` lines show `_pl_log_create_374` and no other version, `ra_ctx_vulkan_moltenvk` is defined, `moltenvk_get_vsync` and an undefined `_CVDisplayLinkSetOutputCallback` are present. If a release path differs, locate the archive with `fd -e a libmpv dist/release`.

- [ ] **Step 7: Commit the recipe**

```bash
cd ~/src/MPVKit && git add Sources/BuildScripts/XCFrameworkBuild/main.swift
git commit -m "Build libmpv from mpv master 3186d36 against libplacebo master 92b5ac6"
```

---

### Task 5: Publish the release and point the fork's Package.swift at it

**Files:**
- Modify: `~/src/MPVKit/Package.swift` (9 `binaryTarget` blocks)

**Interfaces:**
- Consumes: Task 2 and Task 4 artifacts.
- Produces: tag `amp-1.0.0-mpv3186d36-pl92b5ac6` on `profanitys1/MPVKit` and a pushed commit `MPVKIT_REV` (full SHA) on branch `amp-master-vsync`.

- [ ] **Step 1: Ask the user**

Ask in chat: "Publish release `amp-1.0.0-mpv3186d36-pl92b5ac6` with 9 xcframework zips on public repo profanitys1/MPVKit and push branch `amp-master-vsync`?" Wait for a clear yes. On no, stop and report.

- [ ] **Step 2: Create the release with the assets**

```bash
cd ~/src/MPVKit
cp ~/src/libplacebo-build/dist/release/Libplacebo.xcframework.zip ~/src/libplacebo-build/dist/release/Libplacebo.xcframework.checksum.txt dist/release/
gh release create amp-1.0.0-mpv3186d36-pl92b5ac6 -R profanitys1/MPVKit --prerelease \
  --title "amp: mpv master 3186d36 + libplacebo master 92b5ac6 + moltenvk vsync" \
  --notes "Built on macOS 27.0.1 / Xcode 27.0, macOS arm64+x86_64. Sources: mpv-player/mpv@3186d369f9f090cd1363be0ac46a037824b702c6 with Sources/BuildScripts/patch/libmpv/0001-0004; haasn/libplacebo@92b5ac6db79f4d680eb656692f7bf51e9606f42a via mpvkit/libplacebo-build@2e69520 + Sources/BuildScripts/amp/libplacebo-build-pin.patch; FFmpeg n8.1.2 with this repo's GPL recipe. All other targets are unchanged upstream/aagedal binaries." \
  dist/release/Libmpv-GPL.xcframework.zip dist/release/Libavcodec-GPL.xcframework.zip dist/release/Libavdevice-GPL.xcframework.zip \
  dist/release/Libavformat-GPL.xcframework.zip dist/release/Libavfilter-GPL.xcframework.zip dist/release/Libavutil-GPL.xcframework.zip \
  dist/release/Libswresample-GPL.xcframework.zip dist/release/Libswscale-GPL.xcframework.zip dist/release/Libplacebo.xcframework.zip
```

Expected: release URL printed.

- [ ] **Step 3: Rewrite the 9 targets in Package.swift**

```bash
cd ~/src/MPVKit
TAG=amp-1.0.0-mpv3186d36-pl92b5ac6
BASE="https://github.com/profanitys1/MPVKit/releases/download/$TAG"
for t in Libmpv-GPL Libavcodec-GPL Libavdevice-GPL Libavformat-GPL Libavfilter-GPL Libavutil-GPL Libswresample-GPL Libswscale-GPL Libplacebo; do
  sum=$(cat "dist/release/$t.xcframework.checksum.txt")
  perl -0pi -e "s#(name: \"\Q$t\E\",\n\s*url: \")[^\"]+(\",\n\s*checksum: \")[0-9a-f]+#\${1}$BASE/$t.xcframework.zip\${2}$sum#" Package.swift
done
git diff --stat Package.swift
rg -c "profanitys1/MPVKit/releases/download/$TAG" Package.swift
```

Expected: `rg -c` prints `9`.

- [ ] **Step 4: Validate the published assets against the manifest**

```bash
mkdir -p "$SCRATCH/release-check" && cd "$SCRATCH/release-check"
gh release download amp-1.0.0-mpv3186d36-pl92b5ac6 -R profanitys1/MPVKit --clobber
for z in *.xcframework.zip; do t=${z%.xcframework.zip}; sum=$(swift package compute-checksum "$z"); rg -q "$sum" ~/src/MPVKit/Package.swift && echo "ok $t" || echo "MISMATCH $t"; done
```

Expected: 9 `ok` lines, no `MISMATCH`.

- [ ] **Step 5: Commit and push**

```bash
cd ~/src/MPVKit && git add Package.swift && git commit -m "Point GPL and libplacebo targets at amp-1.0.0-mpv3186d36-pl92b5ac6"
git push -u origin amp-master-vsync
git rev-parse HEAD
```

Record the printed SHA as `MPVKIT_REV`.

---

### Task 6: Pin amp to the fork

**Files:**
- Modify: `~/src/amp/Aagedal Media Player.xcodeproj/project.pbxproj:493-500`
- Modify: `~/src/amp/Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (regenerated)
- Modify: `~/src/amp/CLAUDE.md:38`

**Interfaces:**
- Consumes: `MPVKIT_REV` from Task 5.

- [ ] **Step 1: Change the package reference**

In `project.pbxproj`, inside `8EA00003AAAA000000000001 /* XCRemoteSwiftPackageReference "MPVKit" */`, replace

```
			repositoryURL = "https://github.com/aagedal/MPVKit";
			requirement = {
				kind = revision;
				revision = 230c3174f1515898f24599147ad61c2a277d0dc2;
			};
```

with the same block using `repositoryURL = "https://github.com/profanitys1/MPVKit";` and `revision = <MPVKIT_REV>;` (the full 40-character SHA from Task 5 Step 5).

- [ ] **Step 2: Re-resolve**

```bash
cd ~/src/amp && xcodebuild -resolvePackageDependencies -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" 2>&1 | tail -5
jq '.pins[]|select(.identity=="mpvkit")' "Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
```

Expected: the pin shows `location` `https://github.com/profanitys1/MPVKit` and `revision` = `MPVKIT_REV`.

- [ ] **Step 3: Build Release**

```bash
cd ~/src/amp && xcodebuild build -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -configuration Release -destination platform=macOS -derivedDataPath "$SCRATCH/dd" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= > "$SCRATCH/amp-build.log" 2>&1; echo exit=$?; rg -n "error:|Undefined symbol" "$SCRATCH/amp-build.log" | head
```

`run_in_background: true`. Expected: `exit=0`, no `error:` or `Undefined symbol` lines.

- [ ] **Step 4: Update the dependency paragraph in CLAUDE.md**

Replace line 38 (the `- **MPVKit-GPL** — ...` bullet) with:

```markdown
- **MPVKit-GPL** — `https://github.com/profanitys1/MPVKit`, branch `amp-master-vsync`, pinned to a revision (not `branch:`). Fork of Truls's `aagedal/MPVKit`. Bundles mpv master `3186d369f9` (patches `0001`-`0004` in `Sources/BuildScripts/patch/libmpv`; `0004` gives the `moltenvk` context CVDisplayLink vsync feedback, display chosen through `screen-name` = `CGDirectDisplayID`), libplacebo master `92b5ac6` (API 7.374), FFmpeg n8.1.2 rebuilt against it, MoltenVK 1.4.2. Floors: libplacebo ≥ 7.360.1 (MoltenVK timeline-semaphore workaround, mpv#17258) and MoltenVK ≥ 1.4.2 (1.4.0/1.4.1 lose the device on imported `MTLTexture`s used by zero-copy `hwdec=videotoolbox`). Rebuilding libplacebo forces an FFmpeg rebuild, because `vf_libplacebo` links the API-versioned `pl_log_create_<API>`. Bump the pin deliberately, never by a routine re-resolve.
```

- [ ] **Step 5: Run the full unit suite (baseline: 634 passed, 0 failed, 5 skipped)**

```bash
cd ~/src/amp && xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS -derivedDataPath "$SCRATCH/dd-test" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= > "$SCRATCH/amp-test-pin.log" 2>&1; echo exit=$?; rg -n "Executed .* tests|\*\* TEST" "$SCRATCH/amp-test-pin.log" | tail -3
```

`run_in_background: true`, timeout 1800000. Expected: `** TEST SUCCEEDED **`, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd ~/src/amp && git add "Aagedal Media Player.xcodeproj/project.pbxproj" "Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" CLAUDE.md
git commit -m "Pin MPVKit to the mpv/libplacebo master fork build with moltenvk vsync"
```

---

### Task 7: Display-synced playback options in amp

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/RenderProfile.swift` (after `scaleOptions`)
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` (`setupMPV` ~line 345-347, `applyRenderProfileOption` ~1290-1310, `setRenderProfile` ~1312-1330, `applyDisplayRefreshRate` ~1603-1610, stored properties ~1234)
- Modify: `Aagedal Media Player/Logic/MPV/MPVVideoView.swift:361-365`
- Test: `Aagedal Media Player Tests/RenderProfileTests.swift`

**Interfaces:**
- Produces: `RenderProfile.playbackSyncOptions: [String: String]`; `MPVPlayer.applyDisplay(refreshRate: Double, displayID: UInt32)` replacing `applyDisplayRefreshRate(_:)`.

Impact (GitNexus is not installed in this repo; callers found with `rg`): `applyDisplayRefreshRate` has one caller, `MPVVideoView.swift:363`. `setRenderProfile` is called only from `ContentViewCommandHandlers.swift:153`. `applyRenderProfileOption` is private to `setupMPV`. Risk: low.

- [ ] **Step 1: Write the failing test**

Append inside `final class RenderProfileTests` in `Aagedal Media Player Tests/RenderProfileTests.swift`:

```swift
    func testFaithfulKeepsAudioSyncAndEveryOtherProfileSyncsToTheDisplay() {
        XCTAssertEqual(RenderProfile.off.playbackSyncOptions,
                       ["video-sync": "audio", "interpolation": "no"],
                       "inspection must see each decoded frame once, unblended")
        for profile in RenderProfile.allCases where profile != .off {
            XCTAssertEqual(profile.playbackSyncOptions,
                           ["video-sync": "display-resample", "interpolation": "yes"],
                           profile.rawValue)
        }
    }
```

- [ ] **Step 2: Run it and see it fail**

```bash
cd ~/src/amp && xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS -derivedDataPath "$SCRATCH/dd-test" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/RenderProfileTests" 2>&1 | rg -n "error:|TEST (SUCCEEDED|FAILED)" | head
```

Expected: compile error `value of type 'RenderProfile' has no member 'playbackSyncOptions'`.

- [ ] **Step 3: Add the property**

In `RenderProfile.swift`, after the closing brace of `var scaleOptions`:

```swift

    /// Presentation timing that differs per profile. Every profile sets both keys.
    ///
    /// Faithful stays on mpv's default `audio` sync with no interpolation, so
    /// inspection sees each decoded frame exactly once. Every other profile,
    /// Automatic included, resamples audio to lock video to the display and
    /// blends at frame boundaries (`tscale=oversample`, set at init), which
    /// removes 25 fps judder on a 120 Hz panel. This relies on the MPVKit
    /// fork's moltenvk vsync feedback (CLAUDE.md, MPVKit-GPL).
    var playbackSyncOptions: [String: String] {
        self == .off
            ? ["video-sync": "audio", "interpolation": "no"]
            : ["video-sync": "display-resample", "interpolation": "yes"]
    }
```

- [ ] **Step 4: Run the test and see it pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Set interpolation prerequisites at init**

In `MPVPlayer.swift` `setupMPV()`, directly after the `framedrop` line

```swift
        checkError(mpv_set_option_string(mpv, "framedrop", "vo"), context: "framedrop")
```

insert:

```swift

        // The hwdec surface pool is sized when the decoder opens, and mpv's manual
        // says interpolation "may require" extra frames. Set it before init so a
        // profile switch to interpolation never starves the pool. `oversample` is
        // mpv's default tscale, pinned so a future default change cannot blur.
        checkError(mpv_set_option_string(mpv, "hwdec-extra-frames", "4"), context: "hwdec-extra-frames")
        checkError(mpv_set_option_string(mpv, "tscale", "oversample"), context: "tscale")
        if displayRefreshRate > 0 {
            checkError(mpv_set_option_string(mpv, "display-fps-override", String(format: "%.3f", displayRefreshRate)), context: "display-fps-override")
        }
        if displayID != 0 {
            checkError(mpv_set_option_string(mpv, "screen-name", String(displayID)), context: "screen-name")
        }
```

- [ ] **Step 6: Apply sync options with the profile at init**

In `applyRenderProfileOption()`, after the `for (name, value) in profile.scaleOptions { ... }` loop, add:

```swift
        for (name, value) in profile.playbackSyncOptions {
            checkError(mpv_set_option_string(mpv, name, value), context: name)
        }
```

- [ ] **Step 7: Apply sync options on a runtime profile switch**

In `setRenderProfile(_:)`, replace

```swift
        guard mpv != nil else { return }

        automaticAnalysis?.cancel()
```

with

```swift
        guard mpv != nil else { return }

        // Keyed to the selected profile, not the applied one: Automatic may apply
        // Faithful's shader stack (HDR), but only an explicit Faithful choice means inspection.
        for (name, value) in profile.playbackSyncOptions {
            setString(name, value)
        }

        automaticAnalysis?.cancel()
```

- [ ] **Step 8: Carry the display ID with the refresh rate**

In `MPVPlayer.swift`, next to `private var displayRefreshRate: Double = 0`, add:

```swift
    /// CGDirectDisplayID of the screen showing the video; 0 until the view reports one.
    private var displayID: UInt32 = 0
```

Replace the whole `applyDisplayRefreshRate(_:)` method (including its doc comment) with:

```swift
    /// mpv cannot query the display on macOS, so the app has to tell it.
    /// Without a refresh rate mpv assumes 60 Hz and mistimes frames on a 120 Hz
    /// panel or an external monitor running at 50. The display ID goes to the
    /// MPVKit fork's moltenvk context through `screen-name`, which binds its
    /// vsync display link to that screen. Values set before the context exists
    /// are applied by `setupMPV`.
    func applyDisplay(refreshRate fps: Double, displayID id: UInt32) {
        if fps > 0 {
            displayRefreshRate = fps
            setString("display-fps-override", String(format: "%.3f", fps))
        }
        if id != 0, id != displayID {
            displayID = id
            setString("screen-name", String(id))
        }
    }
```

- [ ] **Step 9: Pass the display ID from the view**

In `MPVVideoView.swift`, replace

```swift
        player.applyDisplayRefreshRate(Double(screen.maximumFramesPerSecond))
```

with

```swift
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        player.applyDisplay(refreshRate: Double(screen.maximumFramesPerSecond), displayID: displayID)
```

- [ ] **Step 10: Confirm no stale callers**

Run: `rg -n "applyDisplayRefreshRate\(" "Aagedal Media Player" --type swift`
Expected: only the view's own private `applyDisplayRefreshRate()` definition and its 4 call sites in `MPVVideoView.swift` (lines ~282, 288, 294, 296). No call to `player.applyDisplayRefreshRate`.

- [ ] **Step 11: Full suite**

Same command as Task 6 Step 5, log `$SCRATCH/amp-test-sync.log`. Expected: `** TEST SUCCEEDED **`, failures 0, one more test than Task 6.

- [ ] **Step 12: Commit**

```bash
cd ~/src/amp && git add "Aagedal Media Player/Logic/MPV/RenderProfile.swift" "Aagedal Media Player/Logic/MPV/MPVPlayer.swift" "Aagedal Media Player/Logic/MPV/MPVVideoView.swift" "Aagedal Media Player Tests/RenderProfileTests.swift"
git commit -m "Sync video to the display with interpolation for every profile except Faithful"
```

---

### Task 8: On-device verification in amp.app

**Files:**
- Create: `docs/research/2026-10-03-vsync-bench.md`

**Interfaces:**
- Consumes: the built app from Task 7 (rebuild Release as in Task 6 Step 3 first).

- [ ] **Step 1: Generate the test clips (60 s, moving test pattern, H.264)**

```bash
mkdir -p "$SCRATCH/clips" && cd "$SCRATCH/clips"
for r in 24000/1001 24 25 30 60; do n=$(echo $r | tr / _); ffmpeg -v error -y -f lavfi -i "testsrc2=size=1920x1080:rate=$r" -t 60 -c:v libx264 -crf 18 -pix_fmt yuv420p "clip_$n.mp4"; done
ffmpeg -v error -y -i ~/Downloads/Movies/hdr10-test.mp4 -t 20 -vf "zscale=t=arib-std-b67:tin=smpte2084:m=bt2020nc:p=bt2020:npl=1000,format=yuv420p10le" -c:v libx265 -x265-params "colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc" -tag:v hvc1 hlg.mov
ls
```

Expected: `clip_24000_1001.mp4 clip_24.mp4 clip_25.mp4 clip_30.mp4 clip_60.mp4 hlg.mov`.

- [ ] **Step 2: Install the build**

```bash
osascript -e 'quit app id "com.aagedal.MediaPlayer"'
rm -rf /Applications/amp.app && cp -R "$SCRATCH/dd/Build/Products/Release/Aagedal Media Player.app" /Applications/amp.app
```

- [ ] **Step 3: Bench each clip on Chroma and Compressed movie, fullscreen, 40 s after warm-up**

For each profile in `chroma compressed` and each clip:

```bash
defaults write com.aagedal.MediaPlayer renderProfile -string chroma
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "com.aagedal.MediaPlayer"' > "$SCRATCH/bench_chroma_25.log" &
LOGPID=$!
open -a /Applications/amp.app "$SCRATCH/clips/clip_25.mp4"
```

After about 7 s, toggle fullscreen with computer-use `app_menu` Playback → Toggle Fullscreen. Wait 50 s. Then `kill $LOGPID` (by pid, never `pkill -f`). Extract:

```bash
rg -o "GPU [^ ]+: [0-9.]+ ms samples=[0-9]+ drops=[0-9]+" "$SCRATCH/bench_chroma_25.log" | tail -45
```

Pass per run: the `drops=` value does not rise over the last 40 lines, and ms/frame is within 10 % of the 2026-10-02 table (chroma 7.0/8.6, compressed 16.1/33.0 for 720p/1080p; these clips are 1080p).

- [ ] **Step 4: HDR check against the previous build**

No iPhone HLG/Dolby Vision clip exists on this Mac (searched `~/Downloads`, `~/Movies` on 2026-10-03), so use the HDR10 file and the HLG clip derived from it in Step 1.

Build the pre-change app in a temporary worktree:

```bash
OLD=$(wt -C ~/src/amp switch --create hdr-baseline --base 063a41d --no-cd --format=json | jq -r .path)
xcodebuild build -project "$OLD/Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -configuration Release -destination platform=macOS -derivedDataPath "$SCRATCH/dd-old" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= > "$SCRATCH/amp-old-build.log" 2>&1; echo exit=$?
```

For each build (old from `$SCRATCH/dd-old`, new from `$SCRATCH/dd`): install it as in Step 2, set `defaults write com.aagedal.MediaPlayer renderProfile -string automatic`, open `hlg.mov`, go fullscreen, seek to 10 s and pause, run `screencapture -x "$SCRATCH/hdr_<old|new>_hlg.png"`; repeat for `hdr10-test.mp4` at 10 s (`hdr_<old|new>_hdr10.png`). Send both pairs to the user with SendUserFile and record their verdict and yours: hue shift, clipped highlights, shadow lift. Reinstall the new build afterwards, then `wt -C ~/src/amp remove hdr-baseline`.

- [ ] **Step 5: Write results**

Create `docs/research/2026-10-03-vsync-bench.md` with: hardware, build SHAs (amp, `MPVKIT_REV`, mpv, libplacebo), a table of clip × profile × median ms × drops at start and end of the 40 s window, the HDR verdict, and the decision taken in Step 6.

- [ ] **Step 6: Decide by the spec's fallbacks**

- Drops flat on every clip: done; keep everything.
- Drops still rise: in `RenderProfile.playbackSyncOptions` return `["video-sync": "audio", "interpolation": "no"]` for every profile, update the doc comment and the test in Task 7 Step 1 to match, record the measurements, keep the library upgrade.
- HDR regression: re-pin libplacebo to v7.360.1 (`mpvkit/libplacebo-build` release, original `Libplacebo` URL and checksum `2fa3d54cb81f302d6f11c7b2f509af30944381c3b11ee9d35096eb4637a6e2dd`), rebuild FFmpeg and libmpv as in Task 4 against it, and republish.

- [ ] **Step 7: Commit**

```bash
cd ~/src/amp && git add docs/research/2026-10-03-vsync-bench.md && git commit -m "Record vsync and interpolation bench on the fork build"
```

- [ ] **Step 8: Update memory**

Update `/Users/filip/.claude/projects/-Users-filip/memory/amp-run-and-bench.md`: replace the `display-resample` finding with the Task 8 result and add the fork, the tag and the `screen-name` display contract.
