// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class MPVCodecWhitelistTests: XCTestCase {
    func testUnsupportedCodecIsRemoved() {
        let result = MPVCodecWhitelist.narrowed("h264,av1,vp9") { codec in
            codec == "av1" ? false : true
        }
        XCTAssertEqual(result, "h264,vp9")
    }

    /// No change means no write, so mpv is not told something it already knows.
    func testEverythingSupportedReturnsNil() {
        let result = MPVCodecWhitelist.narrowed("h264,av1") { _ in true }
        XCTAssertNil(result)
    }

    /// A codec this app cannot check must be left alone, not dropped.
    func testUnknownCodecIsRetained() {
        let result = MPVCodecWhitelist.narrowed("h264,av1,theora") { codec in
            codec == "theora" ? nil : (codec == "av1" ? false : true)
        }
        XCTAssertEqual(result, "h264,theora")
    }

    func testAllUnsupportedYieldsEmptyString() {
        let result = MPVCodecWhitelist.narrowed("av1,vp9") { _ in false }
        XCTAssertEqual(result, "")
    }

    func testWhitespaceAroundEntriesIsIgnored() {
        let result = MPVCodecWhitelist.narrowed("h264, av1 ,vp9") { codec in
            codec == "av1" ? false : true
        }
        XCTAssertEqual(result, "h264,vp9")
    }

    func testEmptyWhitelistReturnsNil() {
        XCTAssertNil(MPVCodecWhitelist.narrowed("") { _ in false })
    }
}
