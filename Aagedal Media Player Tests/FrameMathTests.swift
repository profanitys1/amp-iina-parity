// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Foundation
import Testing

struct FrameMathTests {
    /// Deterministic generator so the synthetic frames are the same on every run.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let side = 256

    private static func gaussian(_ rng: inout SplitMix) -> Double {
        let u = Double.random(in: 0.000_1..<1, using: &rng)
        let v = Double.random(in: 0..<1, using: &rng)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }

    private static func clamp(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }

    private static func shading(_ x: Int, _ y: Int) -> Double { 90 + 60 * sin(Double(x) / 37) + 50 * cos(Double(y) / 29) }

    /// Independent noise at every pixel over a smooth shading: real fine detail.
    private static func sharpFrame() -> [UInt8] {
        var rng = SplitMix(state: 1)
        return (0..<side * side).map { clamp(shading($0 % side, $0 / side) + 40 * gaussian(&rng)) }
    }

    /// A 64x64 noise texture enlarged 4x with bilinear sampling: no detail above a quarter of Nyquist.
    private static func blurredUpscale() -> [UInt8] {
        var rng = SplitMix(state: 2)
        let small = 64
        let texture = (0..<small * small).map { _ in 128 + 40 * gaussian(&rng) }
        return (0..<side * side).map { i in
            let x = (Double(i % side) + 0.5) / 4 - 0.5
            let y = (Double(i / side) + 0.5) / 4 - 0.5
            let x0 = max(0, min(small - 2, Int(x.rounded(.down))))
            let y0 = max(0, min(small - 2, Int(y.rounded(.down))))
            let fx = max(0, min(1, x - Double(x0)))
            let fy = max(0, min(1, y - Double(y0)))
            let top = texture[y0 * small + x0] * (1 - fx) + texture[y0 * small + x0 + 1] * fx
            let bottom = texture[(y0 + 1) * small + x0] * (1 - fx) + texture[(y0 + 1) * small + x0 + 1] * fx
            return clamp(top * (1 - fy) + bottom * fy)
        }
    }

    /// Every 8x8 block a constant level: the signature of a coarse transform codec.
    private static func blockPattern() -> [UInt8] {
        var rng = SplitMix(state: 3)
        let blocks = side / 8
        let levels = (0..<blocks * blocks).map { _ in 128 + 30 * gaussian(&rng) }
        return (0..<side * side).map { clamp(levels[($0 / side / 8) * blocks + ($0 % side) / 8] + 2 * gaussian(&rng)) }
    }

    private static func flatWithNoise() -> [UInt8] {
        var rng = SplitMix(state: 4)
        return (0..<side * side).map { _ in clamp(128 + 6 * gaussian(&rng)) }
    }

    private static func smoothFrame() -> [UInt8] {
        (0..<side * side).map { clamp(shading($0 % side, $0 / side)) }
    }

    private func stats(_ frame: [UInt8]) throws -> FrameStats {
        try #require(FrameMath.stats(luma: frame, width: Self.side, height: Self.side))
    }

    @Test func blockPatternHasHighBlockiness() throws {
        #expect(try stats(Self.blockPattern()).blockiness > 5)
    }

    @Test func framesWithoutBlockingStayNearOne() throws {
        for frame in [Self.sharpFrame(), Self.smoothFrame(), Self.flatWithNoise()] {
            let value = try stats(frame).blockiness
            #expect(value > 0.9 && value < 1.15, "blockiness \(value)")
        }
    }

    @Test func blurredUpscaleHasLowerDetailRatioThanSharpDetail() throws {
        let sharp = try stats(Self.sharpFrame()).detailRatio
        let blurred = try stats(Self.blurredUpscale()).detailRatio
        #expect(blurred < sharp - 0.1, "blurred \(blurred) sharp \(sharp)")
    }

    @Test func gaussianNoiseGivesHighNoiseAndAFlatFrameDoesNot() throws {
        #expect(try stats(Self.flatWithNoise()).noise > 0.015)
        #expect(try stats(Self.smoothFrame()).noise < 0.005)
    }

    @Test func aFlatFrameCarriesNoStatistics() {
        let flat = [UInt8](repeating: 16, count: Self.side * Self.side)
        #expect(FrameMath.stats(luma: flat, width: Self.side, height: Self.side) == nil)
    }

    @Test func tinyOrShortFramesCarryNoStatistics() {
        #expect(FrameMath.stats(luma: [UInt8](repeating: 0, count: 64), width: 8, height: 8) == nil)
        #expect(FrameMath.stats(luma: [UInt8](repeating: 0, count: 10), width: 256, height: 256) == nil)
    }

    @Test func oddSizedFramesAreHandled() throws {
        let width = 257, height = 255
        let frame = (0..<width * height).map { UInt8(truncatingIfNeeded: ($0 * 2_654_435_761) >> 13) }
        #expect(FrameMath.stats(luma: frame, width: width, height: height) != nil)
    }

    @Test func averageIsTheMeanOfEachField() throws {
        let mean = try #require(FrameMath.average([
            FrameStats(detailRatio: 0.2, blockiness: 1, noise: 0.1),
            FrameStats(detailRatio: 0.4, blockiness: 3, noise: 0.3),
        ]))
        #expect(abs(mean.detailRatio - 0.3) < 1e-12)
        #expect(abs(mean.blockiness - 2) < 1e-12)
        #expect(abs(mean.noise - 0.2) < 1e-12)
        #expect(FrameMath.average([]) == nil)
    }

    @Test func sampleTimesSkipTheEndsAndAreEvenlySpread() {
        let times = FrameMath.sampleTimes(duration: 100)
        #expect(times.count == 8)
        #expect(abs(times[0] - 10.625) < 1e-9)
        #expect(abs(times[7] - 89.375) < 1e-9)
        for (a, b) in zip(times, times.dropFirst()) { #expect(abs((b - a) - 11.25) < 1e-9) }
    }

    @Test func shortOrUnknownDurationsGetNoSamples() {
        #expect(FrameMath.sampleTimes(duration: 1.99).isEmpty)
        #expect(FrameMath.sampleTimes(duration: 0).isEmpty)
        #expect(FrameMath.sampleTimes(duration: .nan).isEmpty)
        #expect(FrameMath.sampleTimes(duration: 2).count == 8)
    }

    @Test func parsesTheHeaderFFmpegWrites() throws {
        var data = Data("P5\n3 2\n255\n".utf8)
        data.append(contentsOf: [1, 2, 3, 4, 5, 6])
        let image = try #require(FrameMath.parsePGM(data))
        #expect(image.width == 3 && image.height == 2)
        #expect(image.luma == [1, 2, 3, 4, 5, 6])
    }

    @Test func rejectsTruncatedOrForeignData() {
        var data = Data("P5\n3 2\n255\n".utf8)
        data.append(contentsOf: [1, 2, 3])
        #expect(FrameMath.parsePGM(data) == nil)
        #expect(FrameMath.parsePGM(Data("P6\n1 1\n255\nabc".utf8)) == nil)
        #expect(FrameMath.parsePGM(Data()) == nil)
    }
}
