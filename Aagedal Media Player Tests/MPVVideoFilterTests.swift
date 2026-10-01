// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class MPVVideoFilterTests: XCTestCase {
    func testLabelledFilterWithoutParameters() {
        let filter = MPVVideoFilter(label: "amp-flip", name: "vflip", parameters: [])
        XCTAssertEqual(filter.filterString, "@amp-flip:vflip")
    }

    func testParametersAreJoinedInOrder() {
        let filter = MPVVideoFilter(label: "amp-crop", name: "crop",
                                    parameters: [("w", "640"), ("h", "480")])
        XCTAssertEqual(filter.filterString, "@amp-crop:crop=w=640:h=480")
    }

    /// A lavfi graph is wrapped in brackets, which is how mpv expects it.
    func testLavfiGraphIsBracketed() {
        let filter = MPVVideoFilter.lavfi(label: "amp-reflect", graph: "vflip")
        XCTAssertEqual(filter.filterString, "@amp-reflect:lavfi=[vflip]")
    }

    /// A LUT path can contain spaces and must survive quoting.
    func testLUTPathIsQuoted() {
        let filter = MPVVideoFilter.lut3d(label: "amp-lut", path: "/Volumes/Grade A/show.cube")
        XCTAssertEqual(filter.filterString,
                       "@amp-lut:lavfi=[lut3d=file='/Volumes/Grade A/show.cube']")
    }

    func testLabelIsUsedForRemoval() {
        let filter = MPVVideoFilter.lavfi(label: "amp-lut", graph: "null")
        XCTAssertEqual(filter.removalArgument, "@amp-lut")
    }
}
