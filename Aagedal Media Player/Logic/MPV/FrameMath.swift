// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import Foundation

/// Pure picture maths on 8-bit luma frames, plus the frame sampling plan and PGM parsing the
/// analyzer and the calibration script share.
nonisolated enum FrameMath {
    /// Files shorter than this are not analysed.
    static let minimumDuration = 2.0
    static let frameCount = 8

    /// Evenly spread timestamps in seconds, skipping the first and last 5 % of the file.
    static func sampleTimes(duration: Double, count: Int = frameCount) -> [Double] {
        guard duration.isFinite, duration >= minimumDuration, count > 0 else { return [] }
        return (0..<count).map { duration * (0.05 + 0.9 * (Double($0) + 0.5) / Double(count)) }
    }

    /// Parses a binary PGM (`P5`, maxval 255) as written by ffmpeg's `pgm` encoder.
    static func parsePGM(_ data: Data) -> (luma: [UInt8], width: Int, height: Int)? {
        let bytes = [UInt8](data)
        var index = 0
        func token() -> String? {
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x09 { index += 1 }
            let start = index
            while index < bytes.count, !(bytes[index] == 0x20 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x09) { index += 1 }
            return start < index ? String(decoding: bytes[start..<index], as: UTF8.self) : nil
        }
        guard token() == "P5", let w = token().flatMap({ Int($0) }), let h = token().flatMap({ Int($0) }),
              token() == "255", w > 0, h > 0 else { return nil }
        index += 1 // the single whitespace byte after maxval
        guard bytes.count - index >= w * h else { return nil }
        return (Array(bytes[index..<(index + w * h)]), w, h)
    }

    static let minimumSide = 16
    static let flatGradient: Float = 0.25
    static let blockSize = 8

    static func stats(luma: [UInt8], width: Int, height: Int) -> FrameStats? {
        let w = width / 2 * 2
        let h = height / 2 * 2
        guard w >= minimumSide, h >= minimumSide, luma.count >= width * height else { return nil }
        var pixels = [Float](repeating: 0, count: w * h)
        luma.withUnsafeBufferPointer { src in
            pixels.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    vDSP_vfltu8(src.baseAddress! + y * width, 1, dst.baseAddress! + y * w, 1, vDSP_Length(w))
                }
            }
        }
        let steps = stepSums(pixels, width: w, height: h)
        let gradient = steps.meanAll
        guard gradient >= flatGradient else { return nil }
        return FrameStats(
            detailRatio: Double(residualMean(pixels, width: w, height: h) / gradient),
            blockiness: Double(steps.blockiness),
            noise: Double(flatBlockNoise(pixels, width: w, height: h) / 255)
        )
    }

    static func average(_ frames: [FrameStats]) -> FrameStats? {
        guard !frames.isEmpty else { return nil }
        let n = Double(frames.count)
        return FrameStats(
            detailRatio: frames.map(\.detailRatio).reduce(0, +) / n,
            blockiness: frames.map(\.blockiness).reduce(0, +) / n,
            noise: frames.map(\.noise).reduce(0, +) / n
        )
    }

    // MARK: Steps

    private struct Steps { var meanAll: Float; var blockiness: Float }

    /// Absolute neighbour differences. A step into column/row 8k is a block boundary.
    private static func stepSums(_ p: [Float], width w: Int, height h: Int) -> Steps {
        var boundary: Double = 0, other: Double = 0
        var boundaryCount = 0, otherCount = 0
        var diff = [Float](repeating: 0, count: w)
        p.withUnsafeBufferPointer { px in
            diff.withUnsafeMutableBufferPointer { d in
                for y in 0..<h {
                    let row = px.baseAddress! + y * w
                    // horizontal: d[i] = |row[i+1] - row[i]|
                    vDSP_vsub(row, 1, row + 1, 1, d.baseAddress!, 1, vDSP_Length(w - 1))
                    vDSP_vabs(d.baseAddress!, 1, d.baseAddress!, 1, vDSP_Length(w - 1))
                    var total: Float = 0, onBoundary: Float = 0
                    vDSP_sve(d.baseAddress!, 1, &total, vDSP_Length(w - 1))
                    let boundaries = (w - 1 - (blockSize - 1) + blockSize - 1) / blockSize
                    vDSP_sve(d.baseAddress! + (blockSize - 1), vDSP_Stride(blockSize), &onBoundary, vDSP_Length(boundaries))
                    boundary += Double(onBoundary); boundaryCount += boundaries
                    other += Double(total - onBoundary); otherCount += (w - 1) - boundaries
                    // vertical: step from row y-1 to y
                    if y > 0 {
                        let prev = px.baseAddress! + (y - 1) * w
                        vDSP_vsub(prev, 1, row, 1, d.baseAddress!, 1, vDSP_Length(w))
                        vDSP_vabs(d.baseAddress!, 1, d.baseAddress!, 1, vDSP_Length(w))
                        var sum: Float = 0
                        vDSP_sve(d.baseAddress!, 1, &sum, vDSP_Length(w))
                        if y % blockSize == 0 { boundary += Double(sum); boundaryCount += w }
                        else { other += Double(sum); otherCount += w }
                    }
                }
            }
        }
        let meanAll = Float((boundary + other) / Double(max(1, boundaryCount + otherCount)))
        let meanOther = other / Double(max(1, otherCount))
        let meanBoundary = boundary / Double(max(1, boundaryCount))
        let blockiness = meanOther < 1e-6 ? 1 : Float(meanBoundary / meanOther)
        return Steps(meanAll: meanAll, blockiness: blockiness)
    }

    // MARK: Detail

    /// Mean |frame - bilinear(box2x(frame))|.
    private static func residualMean(_ p: [Float], width w: Int, height h: Int) -> Float {
        let hw = w / 2, hh = h / 2
        var small = [Float](repeating: 0, count: hw * hh)
        for y in 0..<hh {
            for x in 0..<hw {
                let i = 2 * y * w + 2 * x
                small[y * hw + x] = (p[i] + p[i + 1] + p[i + w] + p[i + w + 1]) * 0.25
            }
        }
        var total: Double = 0
        for y in 0..<h {
            let sy = (Float(y) + 0.5) / 2 - 0.5
            let y0 = max(0, min(hh - 1, Int(sy.rounded(.down))))
            let y1 = min(hh - 1, y0 + 1)
            let fy = max(0, min(1, sy - Float(y0)))
            for x in 0..<w {
                let sx = (Float(x) + 0.5) / 2 - 0.5
                let x0 = max(0, min(hw - 1, Int(sx.rounded(.down))))
                let x1 = min(hw - 1, x0 + 1)
                let fx = max(0, min(1, sx - Float(x0)))
                let top = small[y0 * hw + x0] * (1 - fx) + small[y0 * hw + x1] * fx
                let bottom = small[y1 * hw + x0] * (1 - fx) + small[y1 * hw + x1] * fx
                total += Double(abs(p[y * w + x] - (top * (1 - fy) + bottom * fy)))
            }
        }
        return Float(total / Double(w * h))
    }

    // MARK: Noise

    /// Median standard deviation over the flattest 10 % of 8x8 blocks, in grey levels.
    private static func flatBlockNoise(_ p: [Float], width w: Int, height h: Int) -> Float {
        let bw = w / blockSize, bh = h / blockSize
        guard bw > 0, bh > 0 else { return 0 }
        var deviations = [Float]()
        deviations.reserveCapacity(bw * bh)
        for by in 0..<bh {
            for bx in 0..<bw {
                var sum: Float = 0, sumSquares: Float = 0
                for y in 0..<blockSize {
                    let base = (by * blockSize + y) * w + bx * blockSize
                    for x in 0..<blockSize {
                        let v = p[base + x]
                        sum += v; sumSquares += v * v
                    }
                }
                let n = Float(blockSize * blockSize)
                let mean = sum / n
                deviations.append(max(0, sumSquares / n - mean * mean).squareRoot())
            }
        }
        deviations.sort()
        let flattest = max(1, deviations.count / 10)
        return deviations[flattest / 2]
    }
}
