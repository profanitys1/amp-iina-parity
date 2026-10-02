#!/bin/bash

# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints facts, frame statistics and the resulting class for every video under the given
# folders (default: ~/Downloads/Movies, ~/Downloads/whatsapp, ~/Downloads/Archives/Movies).
# Tab-separated numbers only; no frame is written to disk or shown. The classifier and the
# frame maths are compiled from the app's own sources, so the output matches the app.
#
# Usage: scripts/calibrate-profile-picker.sh [folder]   (any number of folders)
# Environment: FFMPEG and FFPROBE override the binaries found on PATH.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_dir="$(cd "$script_dir/.." && pwd)"
logic_dir="$repository_dir/Aagedal Media Player/Logic/MPV"
workspace_dir="$(mktemp -d "${TMPDIR:-/tmp}/aagedal-calibrate.XXXXXX")"
trap 'rm -rf "$workspace_dir"' EXIT

swiftc -O -o "$workspace_dir/calibrate" \
    "$logic_dir/SourceClassifier.swift" \
    "$logic_dir/FrameMath.swift" \
    "$script_dir/calibrate-profile-picker/main.swift"

"$workspace_dir/calibrate" "$@"
