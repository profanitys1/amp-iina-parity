// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Maps a container's colour-transfer label to the transfer function the scope
/// pipeline must use.
///
/// Two callers need this and used to carry their own copy: the metadata path
/// and mpv's `video-params/gamma`. Anything not recognised resolves to SDR, so
/// an unfamiliar label cannot silently push HDR scaling onto SDR content.
nonisolated enum HDRTransferResolver {
    static func resolve(colorTransfer: String?) -> TransferFunction {
        guard let colorTransfer = colorTransfer?.lowercased(), !colorTransfer.isEmpty else {
            return .sdr
        }
        if colorTransfer.contains("smpte2084")
            || colorTransfer.contains("st2084")
            || colorTransfer == "pq" {
            return .pq
        }
        if colorTransfer.contains("arib-std-b67") || colorTransfer == "hlg" {
            return .hlg
        }
        return .sdr
    }
}
