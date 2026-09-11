// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import XCTest

final class SubtitleDropTests: XCTestCase {
    func testSubtitleExtensionsAreRecognised() {
        for name in ["a.srt", "a.ass", "a.ssa", "a.vtt", "a.sub", "A.SRT"] {
            XCTAssertTrue(
                PlayerWindowCoordinator.isSubtitleFile(URL(fileURLWithPath: "/tmp/\(name)")),
                "\(name) should be treated as a subtitle"
            )
        }
    }

    func testMediaFilesAreNotSubtitles() {
        for name in ["a.mp4", "a.mkv", "a.mov", "a.wav", "a.txt"] {
            XCTAssertFalse(
                PlayerWindowCoordinator.isSubtitleFile(URL(fileURLWithPath: "/tmp/\(name)")),
                "\(name) should not be treated as a subtitle"
            )
        }
    }
}
