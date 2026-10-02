// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Testing

struct ProfilePickerTests {
    private static let p720 = 1280.0 * 720
    private static let p1080 = 1920.0 * 1080
    private static let fullscreen = 3448.0 * 1940
    private static let windowed = 2560.0 * 1440

    private func pick(_ sourceClass: SourceClass, fps: Double, source: Double, drawable: Double,
                      excluding: Set<RenderProfile> = []) -> RenderProfile {
        ProfilePicker.pick(sourceClass: sourceClass, fps: fps, sourcePixels: source, drawablePixels: drawable,
                           excluding: excluding)
    }

    @Test func costsMatchTheMeasurementsAtTheAnchors() throws {
        let at720 = try #require(ProfilePicker.estimatedMilliseconds(profile: .compressed, sourcePixels: Self.p720, drawablePixels: Self.fullscreen))
        let at1080 = try #require(ProfilePicker.estimatedMilliseconds(profile: .compressed, sourcePixels: Self.p1080, drawablePixels: Self.fullscreen))
        #expect(abs(at720 - 16.1) < 1e-9)
        #expect(abs(at1080 - 33.0) < 1e-9)
    }

    @Test func costScalesWithDrawableAndSourcePixels() throws {
        let half = try #require(ProfilePicker.estimatedMilliseconds(profile: .sharpen, sourcePixels: Self.p1080, drawablePixels: Self.fullscreen / 2))
        #expect(abs(half - 5.85) < 1e-9)
        let fourK = try #require(ProfilePicker.estimatedMilliseconds(profile: .upscaleLight, sourcePixels: 3840.0 * 2160, drawablePixels: Self.fullscreen))
        #expect(abs(fourK - 31.0 * 4) < 1e-9)
    }

    @Test func unmeasuredProfilesHaveNoCost() {
        #expect(ProfilePicker.estimatedMilliseconds(profile: .upscaleStrong, sourcePixels: Self.p720, drawablePixels: Self.fullscreen) == nil)
    }

    @Test func chainsAreHeaviestFirstAndEndFaithful() {
        for sourceClass in SourceClass.allCases {
            for fps in [24.0, 60.0] {
                let chain = ProfilePicker.chain(for: sourceClass, fps: fps)
                #expect(chain.last == .off, "\(sourceClass) \(fps)")
                #expect(!chain.contains(.upscaleStrong))
            }
        }
        #expect(ProfilePicker.chain(for: .compressed, fps: 24) == [.compressed, .efficient, .sharpen, .chroma, .off])
    }

    @Test func topazNeverGetsDenoiseOrAdaptiveSharpen() {
        for fps in [24.0, 60.0] {
            let chain = ProfilePicker.chain(for: .topaz, fps: fps)
            #expect(Set(chain).isDisjoint(with: [.compressed, .compressedGrain, .crisp, .restore]))
        }
    }

    @Test func hdrStaysFaithful() {
        #expect(pick(.hdr, fps: 24, source: Self.p1080, drawable: Self.windowed) == .off)
    }

    @Test func compressedFallsBackWithFrameRateAndSize() {
        #expect(pick(.compressed, fps: 24, source: Self.p720, drawable: Self.fullscreen) == .compressed)
        #expect(pick(.compressed, fps: 30, source: Self.p1080, drawable: Self.fullscreen) == .efficient)
        #expect(pick(.compressed, fps: 30, source: Self.p1080, drawable: Self.windowed) == .compressed)
        #expect(pick(.compressed, fps: 60, source: Self.p720, drawable: Self.fullscreen) == .efficient)
        #expect(pick(.compressed, fps: 60, source: Self.p1080, drawable: Self.fullscreen) == .sharpen)
        #expect(pick(.compressed, fps: 60, source: Self.p1080, drawable: Self.windowed) == .efficient)
    }

    @Test func cleanAndTopazUseNeuralOnlyBelowThirtyFps() {
        #expect(pick(.clean, fps: 24, source: Self.p1080, drawable: Self.fullscreen) == .upscaleLight)
        #expect(pick(.clean, fps: 30, source: Self.p1080, drawable: Self.fullscreen) == .sharpen)
        #expect(pick(.clean, fps: 60, source: Self.p1080, drawable: Self.fullscreen) == .sharpen)
        #expect(pick(.topaz, fps: 60, source: Self.p720, drawable: Self.fullscreen) == .sharpen)
        #expect(pick(.topaz, fps: 24, source: Self.p720, drawable: Self.fullscreen) == .upscaleLight)
    }

    @Test func softUsesCrispWhenItFitsAndSharpenAbove30Fps() {
        #expect(pick(.soft, fps: 24, source: Self.p720, drawable: Self.fullscreen) == .crisp)
        #expect(pick(.soft, fps: 24, source: Self.p1080, drawable: Self.fullscreen) == .upscaleLight)
        #expect(pick(.soft, fps: 24, source: Self.p1080, drawable: Self.windowed) == .crisp)
        #expect(pick(.soft, fps: 60, source: Self.p1080, drawable: Self.fullscreen) == .sharpen)
    }

    @Test func fourKSourceFullscreenFallsAllTheWayToFaithful() {
        #expect(pick(.clean, fps: 30, source: 3840.0 * 2160, drawable: Self.fullscreen) == .off)
    }

    @Test func excludedProfilesAreSkippedButFaithfulNeverIs() {
        // Stepping down repeatedly walks the chain one fitting entry at a time.
        var excluded: Set<RenderProfile> = []
        var walked: [RenderProfile] = []
        while true {
            let next = pick(.compressed, fps: 24, source: Self.p720, drawable: Self.fullscreen, excluding: excluded)
            walked.append(next)
            if next == .off { break }
            excluded.insert(next)
        }
        #expect(walked == [.compressed, .efficient, .sharpen, .chroma, .off])
        #expect(pick(.compressed, fps: 24, source: Self.p720, drawable: Self.fullscreen, excluding: [.compressed]) == .efficient)
        let everything = Set(RenderProfile.allCases)
        #expect(pick(.compressed, fps: 24, source: Self.p720, drawable: Self.fullscreen, excluding: everything) == .off)
    }

    @Test func unknownSizesAndRateArePessimistic() {
        // 1080p, fullscreen, 30 fps: compressed (33 ms) does not fit 26.7 ms.
        #expect(pick(.compressed, fps: 0, source: 0, drawable: 0) == .efficient)
    }
    @Test func automaticIsNeverCostedOrPicked() {
        #expect(ProfilePicker.estimatedMilliseconds(profile: .automatic, sourcePixels: Self.p720, drawablePixels: Self.fullscreen) == nil)
        for sourceClass in SourceClass.allCases {
            for fps in [24.0, 60.0] {
                #expect(!ProfilePicker.chain(for: sourceClass, fps: fps).contains(.automatic))
            }
        }
    }
}
