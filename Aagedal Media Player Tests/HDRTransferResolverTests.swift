// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class HDRTransferResolverTests: XCTestCase {
    /// The three spellings mpv and SwiftMediaMetadata use for PQ.
    func testPqSpellings() {
        for value in ["smpte2084", "PQ", "st2084", "smpte2084 (PQ)"] {
            XCTAssertEqual(HDRTransferResolver.resolve(colorTransfer: value), .pq, value)
        }
    }

    func testHlgSpelling() {
        for value in ["arib-std-b67", "HLG", "arib-std-b67 (HLG)"] {
            XCTAssertEqual(HDRTransferResolver.resolve(colorTransfer: value), .hlg, value)
        }
    }

    /// SDR transfers, and anything unrecognised, must resolve to SDR rather
    /// than guessing HDR and clipping the picture.
    func testSdrAndUnknownResolveToSdr() {
        for value in ["bt709", "bt1886", "gamma28", "", "something-new"] {
            XCTAssertEqual(HDRTransferResolver.resolve(colorTransfer: value), .sdr, value)
        }
    }

    /// The metadata path passes nil when a file has no video stream.
    func testNilResolvesToSdr() {
        XCTAssertEqual(HDRTransferResolver.resolve(colorTransfer: nil), .sdr)
    }
}
