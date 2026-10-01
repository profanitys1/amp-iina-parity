// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class HardwareDecodeCapabilitiesTests: XCTestCase {
    /// A codec outside the probed set has no answer, so callers keep it.
    func testUnknownCodecHasNoOpinion() {
        let capabilities = HardwareDecodeCapabilities()
        capabilities.beginProbing()
        XCTAssertNil(capabilities.isSupported(mpvCodec: "theora"))
    }

    /// h264 is not probed: every Mac this app runs on decodes it in hardware,
    /// and probing costs a long VideoToolbox call for a foregone answer.
    func testH264IsNotProbed() {
        let capabilities = HardwareDecodeCapabilities()
        capabilities.beginProbing()
        XCTAssertNil(capabilities.isSupported(mpvCodec: "h264"))
    }

    /// Probed codecs must return a definite answer once probing finishes.
    func testProbedCodecsAnswerDefinitely() {
        let capabilities = HardwareDecodeCapabilities()
        capabilities.beginProbing()
        for codec in ["av1", "vp9", "prores"] {
            XCTAssertNotNil(capabilities.isSupported(mpvCodec: codec),
                            "\(codec) should have a definite answer")
        }
    }

    /// Asking before probing must not crash or block forever.
    func testQueryBeforeProbingReturnsNil() {
        XCTAssertNil(HardwareDecodeCapabilities().isSupported(mpvCodec: "av1"))
    }
}
