// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class HardwareDecoderSettingTests: XCTestCase {
    /// Reflection correction needs a video filter, and a filter cannot touch an
    /// opaque VideoToolbox surface, so copy-back is forced regardless of choice.
    func testReflectionForcesCopyBack() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "videotoolbox", correctsReflection: true),
            "videotoolbox-copy")
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "auto", correctsReflection: true),
            "videotoolbox-copy")
    }

    /// Turning hardware decoding off must stay off even with a filter installed.
    func testDisabledStaysDisabled() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "no", correctsReflection: true),
            "no")
    }

    func testAutoMapsToVideoToolbox() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "auto", correctsReflection: false),
            "videotoolbox")
    }

    func testExplicitChoiceIsHonoured() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "videotoolbox-copy", correctsReflection: false),
            "videotoolbox-copy")
    }

    /// An unrecognised stored value must not be passed to mpv verbatim.
    func testUnknownPreferenceFallsBackToVideoToolbox() {
        XCTAssertEqual(
            MPVPlayer.hwdecOptionValue(preference: "nonsense", correctsReflection: false),
            "videotoolbox")
    }
}
