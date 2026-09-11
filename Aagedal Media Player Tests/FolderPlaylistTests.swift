// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import XCTest

@MainActor
final class FolderPlaylistTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "FolderPlaylistTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["clip2.mp4", "clip10.mp4", "clip1.mp4", "notes.txt"] {
            try Data().write(to: folder.appending(path: name))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testSiblingsAreMediaOnlyAndNaturallySorted() {
        let siblings = PlayerWindowCoordinator.siblingMediaFiles(
            containing: folder.appending(path: "clip1.mp4"),
            fileManager: .default
        )

        XCTAssertEqual(siblings.map(\.lastPathComponent),
                       ["clip1.mp4", "clip2.mp4", "clip10.mp4"],
                       "text files must be excluded and order must be Finder-natural")
    }
}
