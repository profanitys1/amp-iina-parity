// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import XCTest

final class OSCPositionTests: XCTestCase {
    func testFractionsClampToUnitRange() {
        XCTAssertEqual(OSCPosition(horizontal: -3, vertical: 12).horizontal, 0)
        XCTAssertEqual(OSCPosition(horizontal: -3, vertical: 12).vertical, 1)
        XCTAssertEqual(OSCPosition(horizontal: .nan, vertical: .infinity),
                       OSCPosition(horizontal: 0.5, vertical: 0.5))
    }

    func testDefaultSitsCentredNearTheBottom() {
        XCTAssertEqual(OSCPosition.default.horizontal, 0.5)
        XCTAssertEqual(OSCPosition.default.vertical, 1)
    }

    func testOriginKeepsTheCardInsideTheVideoRect() {
        let video = CGSize(width: 1000, height: 600)
        let card = CGSize(width: 460, height: 67)

        let centred = OSCPosition(horizontal: 0.5, vertical: 1)
            .origin(in: video, cardSize: card)
        XCTAssertEqual(centred.x, 270, accuracy: 0.001)
        // 25pt bottom margin: 600 - 67 - 25
        XCTAssertEqual(centred.y, 508, accuracy: 0.001)

        let hardLeft = OSCPosition(horizontal: 0, vertical: 0)
            .origin(in: video, cardSize: card)
        XCTAssertEqual(hardLeft.x, 0, accuracy: 0.001)
        XCTAssertEqual(hardLeft.y, 0, accuracy: 0.001)

        let hardRight = OSCPosition(horizontal: 1, vertical: 1)
            .origin(in: video, cardSize: card)
        XCTAssertEqual(hardRight.x, 540, accuracy: 0.001)
    }

    func testOriginSurvivesAVideoRectSmallerThanTheCard() {
        let origin = OSCPosition(horizontal: 0.5, vertical: 1)
            .origin(in: CGSize(width: 200, height: 40), cardSize: CGSize(width: 460, height: 67))
        XCTAssertEqual(origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.001)
    }

    func testHorizontalDragSnapsToCentreWithinFivePoints() {
        let snapped = OSCPosition.snappedHorizontal(
            forProposedX: 272, videoWidth: 1000, cardWidth: 460
        )
        XCTAssertTrue(snapped.didSnap)
        XCTAssertEqual(snapped.fraction, 0.5, accuracy: 0.001)

        let free = OSCPosition.snappedHorizontal(
            forProposedX: 300, videoWidth: 1000, cardWidth: 460
        )
        XCTAssertFalse(free.didSnap)
        XCTAssertEqual(free.fraction, 300.0 / 540.0, accuracy: 0.001)
    }

    func testSnapDoesNotFireTwiceWhileHeldAtCentre() {
        let first = OSCPosition.snappedHorizontal(forProposedX: 270, videoWidth: 1000, cardWidth: 460)
        XCTAssertTrue(first.didSnap)
        XCTAssertEqual(first.fraction, 0.5, accuracy: 0.001)
    }
}
