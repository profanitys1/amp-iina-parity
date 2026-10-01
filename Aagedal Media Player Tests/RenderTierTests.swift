// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import Foundation
import Testing

struct RenderTierTests {
    private static let everyTier = Set(RenderTier.allCases)

    @Test(arguments: [
        (0.5, RenderTier.chroma),
        (1.0, .chroma),
        (1.2, .ravuZoom),
        (1.57, .ravuZoom),
        (1.9, .fsrcnnx),
        (2.0, .fsrcnnx),
        (3.0, .fsrcnnx),
    ])
    func picksTheHeaviestTierTheRatioAllows(ratio: Double, expected: RenderTier) {
        #expect(TierSelector.select(ratio: ratio, available: Self.everyTier, floor: .fsrcnnx) == expected)
    }

    @Test(arguments: [
        (2.0, RenderTier.artcnnLight, RenderTier.artcnnLight),
        (2.0, .ravuZoom, .ravuZoom),
        (2.0, .sharpen, .sharpen),
        (2.0, .faithful, .faithful),
        (1.57, .ravuZoom, .ravuZoom),
        (1.57, .sharpen, .sharpen),
    ])
    func neverExceedsTheFloor(ratio: Double, floor: RenderTier, expected: RenderTier) {
        #expect(TierSelector.select(ratio: ratio, available: Self.everyTier, floor: floor) == expected)
    }

    @Test func skipsTiersWhoseShadersAreMissing() {
        let withoutNeuralDoublers: Set<RenderTier> = [.faithful, .sharpen, .ravuZoom]
        #expect(TierSelector.select(ratio: 2.0, available: withoutNeuralDoublers, floor: .fsrcnnx) == .ravuZoom)

        let withoutRAVU: Set<RenderTier> = [.faithful, .chroma, .sharpen, .artcnnLight, .fsrcnnx]
        #expect(TierSelector.select(ratio: 1.2, available: withoutRAVU, floor: .fsrcnnx) == .sharpen)

        #expect(TierSelector.select(ratio: 2.0, available: [], floor: .fsrcnnx) == .faithful)
        #expect(TierSelector.select(ratio: 0.5, available: [.faithful], floor: .fsrcnnx) == .faithful)
    }

    @Test(arguments: [
        ("yuv420p", false), ("yuv422p10", false), ("nv12", false), ("p010", false),
        ("p210", false), ("uyvy422", false), ("yuv410p", false), ("yuv420p16", false), (nil, false), ("", false),
        ("yuv444p10", true), ("gbrp", true), ("rgb24", true), ("gray16", true), ("nv24", true),
    ] as [(String?, Bool)])
    func detectsSourcesWithNothingForCfLToDo(format: String?, full: Bool) {
        #expect(TierSelector.hasFullResolutionChroma(pixelFormat: format) == full)
    }

    @Test func lightTiersReconstructChromaAndDoublersDoNot() {
        for tier in [RenderTier.chroma, .sharpen, .ravuZoom] {
            #expect(tier.shaderFileNames.last == "CfL_Prediction.glsl", "\(tier)")
        }
        for tier in [RenderTier.faithful, .artcnnLight, .fsrcnnx] {
            #expect(!tier.shaderFileNames.contains("CfL_Prediction.glsl"), "\(tier)")
        }
    }

    @Test func ratioIsTheTighterAxis() throws {
        // Fullscreen drawable measured on an M1 Pro 16" on 2026-09-30.
        let ratio = try #require(TierSelector.upscaleRatio(
            source: CGSize(width: 1920, height: 1080),
            drawable: CGSize(width: 3448, height: 2164)
        ))
        #expect(abs(ratio - 3448.0 / 1920.0) < 1e-9)
    }

    @Test func ratioNeedsBothSizes() {
        #expect(TierSelector.upscaleRatio(source: .zero, drawable: CGSize(width: 10, height: 10)) == nil)
        #expect(TierSelector.upscaleRatio(source: CGSize(width: 10, height: 10), drawable: .zero) == nil)
    }

    @Test func stepsDownOneRungAndStopsAtFaithful() {
        #expect(RenderTier.fsrcnnx.steppedDown == .artcnnLight)
        #expect(RenderTier.sharpen.steppedDown == .chroma)
        #expect(RenderTier.chroma.steppedDown == .faithful)
        #expect(RenderTier.faithful.steppedDown == .faithful)
    }

    @Test func onlySharpenChangesTheScaler() {
        for tier in RenderTier.allCases {
            let expected = tier == .sharpen ? RenderProfile.sharpen.scaleOptions : RenderProfile.off.scaleOptions
            #expect(tier.scaleOptions == expected, "\(tier)")
        }
    }

    @Test func libraryResolvesNameLists() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "RenderTierTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appending(path: "ravu-zoom-ar-r3.hook"))

        let library = ShaderLibrary(directoryPath: directory.path)
        let names = ["ravu-zoom-ar-r3.hook", "ArtCNN_C4F16.glsl"]

        #expect(library.shaderPaths(named: names).count == 1)
        #expect(library.shaderPaths(named: names).first?.hasSuffix("ravu-zoom-ar-r3.hook") == true)
        #expect(library.missingShaderNames(named: names) == ["ArtCNN_C4F16.glsl"])
    }

    @Test func enhanceIsOffByDefault() {
        #expect(AppSettings.enhance.key == "enhance")
        #expect(AppSettings.enhance.defaultValue == false)
    }
}
