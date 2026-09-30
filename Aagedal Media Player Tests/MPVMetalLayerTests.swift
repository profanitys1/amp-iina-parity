// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import CoreGraphics
import Synchronization
import Testing

struct MPVMetalLayerTests {
    private final class SizeLog: Sendable {
        let sizes = Mutex<[CGSize]>([])
    }

    @Test func reportsOnlyAcceptedChanges() {
        let layer = MPVMetalLayer()
        let log = SizeLog()
        layer.onDrawableSizeChange = { size in log.sizes.withLock { $0.append(size) } }

        layer.drawableSize = CGSize(width: 3448, height: 2164)
        layer.drawableSize = CGSize(width: 3448, height: 2164)
        layer.drawableSize = CGSize(width: 1, height: 1)
        layer.drawableSize = CGSize(width: 1920, height: 1080)

        #expect(log.sizes.withLock { $0 } == [CGSize(width: 3448, height: 2164), CGSize(width: 1920, height: 1080)])
    }
}
