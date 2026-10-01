// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One entry in mpv's video filter chain. Every filter carries a label so it can
// be removed by name later, the way the audio channel router already works.
// The string format follows mpv's filter syntax; see IINA's MPVFilter.swift
// for the fuller model this is a deliberate subset of.

import Foundation

nonisolated struct MPVVideoFilter: Equatable {
    let label: String
    /// The mpv filter name and its `key=value` parameters, already joined.
    private let body: String

    init(label: String, name: String, parameters: [(String, String)]) {
        self.label = label
        let joined = parameters.map { "\($0.0)=\($0.1)" }.joined(separator: ":")
        body = joined.isEmpty ? name : "\(name)=\(joined)"
    }

    private init(label: String, body: String) {
        self.label = label
        self.body = body
    }

    var filterString: String { "@\(label):\(body)" }

    /// mpv removes a labelled filter by its label alone.
    var removalArgument: String { "@\(label)" }

    static func lavfi(label: String, graph: String) -> MPVVideoFilter {
        MPVVideoFilter(label: label, body: "lavfi=[\(graph)]")
    }

    /// A 3D LUT, the filter a grading review most often wants.
    // ponytail: a path containing ' breaks the quoting; escape it when a LUT picker ships.
    static func lut3d(label: String, path: String) -> MPVVideoFilter {
        lavfi(label: label, graph: "lut3d=file='\(path)'")
    }
}
