// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

/// The arrow table, cell by cell: four keys against seven modifier
/// combinations, each with the action *and* the route it takes, plus the cells
/// the table preserves outside that matrix.
@MainActor
final class PlayerArrowKeyMapTests: XCTestCase {
    private struct Cell {
        let key: NSEvent.SpecialKey
        let modifiers: NSEvent.ModifierFlags
        let action: PlayerArrowAction
        let route: PlayerArrowRoute
    }

    private static let shift = NSEvent.ModifierFlags.shift
    private static let option = NSEvent.ModifierFlags.option
    private static let command = NSEvent.ModifierFlags.command
    private static let control = NSEvent.ModifierFlags.control

    private static let matrix: [Cell] = [
        // Left / Right
        Cell(key: .leftArrow, modifiers: [], action: .seekBy(-5), route: .broadcast),
        Cell(key: .rightArrow, modifiers: [], action: .seekBy(5), route: .broadcast),
        Cell(key: .leftArrow, modifiers: [shift], action: .seekBy(-10), route: .broadcast),
        Cell(key: .rightArrow, modifiers: [shift], action: .seekBy(10), route: .broadcast),
        Cell(key: .leftArrow, modifiers: [option], action: .stepFrames(-1), route: .local),
        Cell(key: .rightArrow, modifiers: [option], action: .stepFrames(1), route: .local),
        Cell(key: .leftArrow, modifiers: [shift, option], action: .seekBy(-10), route: .local),
        Cell(key: .rightArrow, modifiers: [shift, option], action: .seekBy(10), route: .local),
        Cell(key: .leftArrow, modifiers: [command], action: .previousFile, route: .broadcast),
        Cell(key: .rightArrow, modifiers: [command], action: .nextFile, route: .broadcast),
        Cell(key: .leftArrow, modifiers: [control], action: .seekBy(-5), route: .broadcast),
        Cell(key: .rightArrow, modifiers: [control], action: .seekBy(5), route: .broadcast),
        Cell(key: .leftArrow, modifiers: [control, command], action: .seekBy(-5), route: .broadcast),
        Cell(key: .rightArrow, modifiers: [control, command], action: .seekBy(5), route: .broadcast),

        // Up / Down
        Cell(key: .upArrow, modifiers: [], action: .adjustVolume(5), route: .local),
        Cell(key: .downArrow, modifiers: [], action: .adjustVolume(-5), route: .local),
        Cell(key: .upArrow, modifiers: [shift], action: .stepFrames(-10), route: .broadcast),
        Cell(key: .downArrow, modifiers: [shift], action: .stepFrames(10), route: .broadcast),
        Cell(key: .upArrow, modifiers: [option], action: .adjustVolume(1), route: .local),
        Cell(key: .downArrow, modifiers: [option], action: .adjustVolume(-1), route: .local),
        Cell(key: .upArrow, modifiers: [shift, option], action: .stepFrames(-10), route: .local),
        Cell(key: .downArrow, modifiers: [shift, option], action: .stepFrames(10), route: .local),
        Cell(key: .upArrow, modifiers: [command], action: .seekToStart, route: .broadcast),
        Cell(key: .downArrow, modifiers: [command], action: .seekToEnd, route: .broadcast),
        Cell(key: .upArrow, modifiers: [control], action: .adjustVolume(5), route: .local),
        Cell(key: .downArrow, modifiers: [control], action: .adjustVolume(-5), route: .local),
        Cell(key: .upArrow, modifiers: [control, command], action: .adjustVolume(5), route: .local),
        Cell(key: .downArrow, modifiers: [control, command], action: .adjustVolume(-5), route: .local),
    ]

    func testTheArrowMatrixHasTwentyEightCells() {
        XCTAssertEqual(Self.matrix.count, 28,
                       "Four keys against seven modifier combinations.")
    }

    func testTheArrowMatrixNamesTheActionAndTheRouteOfEveryCell() {
        for cell in Self.matrix {
            let decision = PlayerKeyMap.arrowDecision(key: cell.key, modifiers: cell.modifiers)
            XCTAssertEqual(
                decision,
                PlayerArrowDecision(action: cell.action, route: cell.route),
                "\(cell.key) with \(cell.modifiers)"
            )
            XCTAssertEqual(
                PlayerKeyMap.arrowAction(key: cell.key, modifiers: cell.modifiers),
                cell.action,
                "\(cell.key) with \(cell.modifiers)"
            )
            XCTAssertEqual(
                PlayerKeyMap.arrowRoute(key: cell.key, modifiers: cell.modifiers),
                cell.route,
                "\(cell.key) with \(cell.modifiers)"
            )
        }
    }

    /// The two chords the table preserves beyond the matrix: Command with
    /// Option keeps the old local start/end jump instead of the broadcast one.
    func testTheCommandOptionStartAndEndCellsStayLocal() {
        XCTAssertEqual(
            PlayerKeyMap.arrowDecision(key: .upArrow, modifiers: [Self.command, Self.option]),
            PlayerArrowDecision(action: .seekToStart, route: .local)
        )
        XCTAssertEqual(
            PlayerKeyMap.arrowDecision(key: .downArrow, modifiers: [Self.command, Self.option]),
            PlayerArrowDecision(action: .seekToEnd, route: .local)
        )
    }

    func testTheFallThroughsSurviveTheControlBranch() {
        // Control+Command on Left/Right used to reach the plain broadcast seek,
        // because the control branch only ever owned Up/Down.
        for key in [NSEvent.SpecialKey.leftArrow, .rightArrow] {
            XCTAssertEqual(
                PlayerKeyMap.arrowRoute(key: key, modifiers: [Self.control, Self.command]),
                .broadcast
            )
            XCTAssertEqual(
                PlayerKeyMap.arrowDecision(key: key, modifiers: [Self.control, Self.command]),
                PlayerKeyMap.arrowDecision(key: key, modifiers: [])
            )
        }
        // Control+Command on Up/Down stays in the control branch: local volume.
        for key in [NSEvent.SpecialKey.upArrow, .downArrow] {
            XCTAssertEqual(PlayerKeyMap.arrowRoute(key: key, modifiers: [Self.control, Self.command]), .local)
            XCTAssertEqual(
                PlayerKeyMap.arrowDecision(key: key, modifiers: [Self.control, Self.command]),
                PlayerKeyMap.arrowDecision(key: key, modifiers: [Self.control])
            )
        }
    }

    func testTheNonArrowKeysStayUnmapped() {
        for key in [NSEvent.SpecialKey.tab, .carriageReturn, .pageUp, .pageDown, .home, .end] {
            XCTAssertNil(
                PlayerKeyMap.arrowDecision(key: key, modifiers: []),
                "\(key) must stay with its own handler"
            )
        }
    }

    func testTheMonitorSwitchesOverTheArrowTableAndKeepsItsFocusGuards() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Aagedal Media Player/UI/PlayerView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("PlayerKeyMap.arrowAction(key: specialKey"),
                      "The monitor must decide arrows through the table.")
        XCTAssertTrue(source.contains("PlayerKeyMap.arrowRoute(key: specialKey"),
                      "The monitor must take the route from the same table.")
        for guardName in ["isTimelineFocused", "isOverlayControlFocused", "isTextInputActive"] {
            XCTAssertTrue(source.contains(guardName),
                          "\(guardName) must still guard the monitor.")
        }
    }
}
