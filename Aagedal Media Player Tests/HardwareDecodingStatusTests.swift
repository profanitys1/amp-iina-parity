// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class HardwareDecodingStatusTests: XCTestCase {
    /// mpv reports `no` when it fell back to software decoding.
    func testSoftwareDecodingIsNotHardwareBacked() {
        let status = HardwareDecodingStatus(mpvValue: "no")
        XCTAssertFalse(status.isHardwareBacked)
        XCTAssertEqual(status.label, "Software decoding")
    }

    /// No decoder loaded yet is not the same as software decoding, and must
    /// not be shown as if it were a result.
    func testUnavailableIsDistinctFromSoftware() {
        let status = HardwareDecodingStatus(mpvValue: nil)
        XCTAssertFalse(status.isHardwareBacked)
        XCTAssertEqual(status.label, "Not yet decoded")
        XCTAssertEqual(HardwareDecodingStatus.unavailable.label, status.label)
    }

    func testVideoToolboxIsHardwareBacked() {
        let status = HardwareDecodingStatus(mpvValue: "videotoolbox")
        XCTAssertTrue(status.isHardwareBacked)
        XCTAssertEqual(status.label, "Hardware decoding (videotoolbox)")
    }

    /// The copy-back variant is still hardware decode; it only changes where
    /// the frames land, which matters to filters, not to the user.
    func testCopyBackVariantIsHardwareBacked() {
        XCTAssertTrue(HardwareDecodingStatus(mpvValue: "videotoolbox-copy").isHardwareBacked)
    }

    /// An empty string is what a malformed event yields; treat it as absent.
    func testEmptyStringIsTreatedAsAbsent() {
        XCTAssertEqual(HardwareDecodingStatus(mpvValue: "").label, "Not yet decoded")
    }
}
