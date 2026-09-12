// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Lets non-AppDelegate code show or hide the welcome window.

import Foundation

@MainActor
final class WelcomeWindowPresenter {
    static let shared = WelcomeWindowPresenter()

    var present: (() -> Void)?
    var dismiss: (() -> Void)?

    private init() {}
}
