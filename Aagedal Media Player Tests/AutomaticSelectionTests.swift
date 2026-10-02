// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Testing

struct AutomaticSelectionTests {
    private static let fullscreen = 3448.0 * 1940
    private static let windowed = 2560.0 * 1440
    private let thresholds = SourceClassifier.Thresholds(lowBitsPerPixel: 0.05, blockiness: 1.6, softDetailRatio: 0.54)

    private func selection(drawable: Double = fullscreen) -> AutomaticSelection {
        var selection = AutomaticSelection(thresholds: thresholds)
        _ = selection.setDrawable(pixels: drawable)
        return selection
    }

    private func facts(width: Int = 1280, height: Int = 720, fps: Double = 24, bitrate: Int64 = 20_000_000,
                       topazTag: String? = nil) -> SourceFacts {
        SourceFacts(codec: "h264", width: width, height: height, fps: fps, videoBitrate: bitrate,
                    bitDepth: 8, isHDR: false, topazTag: topazTag)
    }

    private let soft = FrameStats(detailRatio: 0.3, blockiness: 1.1, noise: 0)
    private let healthy = FrameStats(detailRatio: 0.65, blockiness: 1.1, noise: 0)

    @Test func metadataAloneGivesTheFirstPick() {
        var selection = selection()
        let choice = selection.beginFile(facts: facts(bitrate: 600_000))
        #expect(choice.profile == .compressed)
        #expect(choice.classification == SourceClassification(sourceClass: .compressed, reason: "0.6 Mbit/s"))
        #expect(choice.badgeText == "Auto · Compressed movie · 0.6 Mbit/s")
        #expect(selection.current == choice)
    }

    @Test func statsThatChangeTheClassChangeThePick() {
        var selection = selection()
        #expect(selection.beginFile(facts: facts()).profile == .upscaleLight)
        let refined = selection.update(facts: facts(), stats: soft)
        #expect(refined.profile == .crisp)
        #expect(refined.classification.sourceClass == .soft)
    }

    @Test func statsThatKeepTheClassKeepThePick() {
        var selection = selection()
        let first = selection.beginFile(facts: facts())
        let second = selection.update(facts: facts(), stats: healthy)
        #expect(second.profile == first.profile)
        #expect(second.classification.sourceClass == .clean)
    }

    @Test func aTopazTagFoundLaterReclassifies() {
        var selection = selection()
        _ = selection.beginFile(facts: facts(bitrate: 600_000))
        let choice = selection.update(facts: facts(bitrate: 600_000, topazTag: "Proteus"), stats: nil)
        #expect(choice.classification.sourceClass == .topaz)
        #expect(choice.profile == .upscaleLight)
    }

    @Test func aDrawableChangeRepicksWithTheSameStats() {
        var selection = selection()
        let source = facts(width: 1920, height: 1080, fps: 30, bitrate: 1_000_000)
        #expect(selection.beginFile(facts: source).profile == .efficient)
        #expect(selection.setDrawable(pixels: Self.windowed).profile == .compressed)
        #expect(selection.setDrawable(pixels: Self.fullscreen).profile == .efficient)
    }

    @Test func steppingDownWalksTheChainAndStopsAtFaithful() throws {
        var selection = selection()
        _ = selection.beginFile(facts: facts(bitrate: 600_000))
        var walked: [RenderProfile] = []
        while let next = selection.stepDown() { walked.append(next.profile) }
        #expect(walked == [.efficient, .sharpen, .chroma, .off])
        #expect(selection.current?.isSteppedDown == true)
        #expect(selection.stepDown() == nil)
    }

    @Test func aStepDownSurvivesStatsAndDrawableChangesButNotANewFile() {
        var selection = selection()
        _ = selection.beginFile(facts: facts(bitrate: 600_000))
        #expect(selection.stepDown()?.profile == .efficient)
        #expect(selection.update(facts: facts(bitrate: 600_000), stats: healthy).profile == .efficient)
        #expect(selection.setDrawable(pixels: Self.windowed).profile == .efficient)
        let next = selection.beginFile(facts: facts(bitrate: 600_000))
        #expect(next.profile == .compressed)
        #expect(next.isSteppedDown == false)
    }

    @Test func aBrokenProfileStaysExcludedAcrossFiles() {
        var selection = selection()
        _ = selection.beginFile(facts: facts(bitrate: 600_000))
        #expect(selection.markActiveProfileBroken()?.profile == .efficient)
        #expect(selection.beginFile(facts: facts(bitrate: 600_000)).profile == .efficient)
    }

    @Test func hdrNeverLeavesFaithfulAndCannotStepDown() {
        var selection = selection()
        var hdr = facts()
        hdr.isHDR = true
        let choice = selection.beginFile(facts: hdr)
        #expect(choice.profile == .off)
        #expect(choice.badgeText == "Auto · Faithful · HDR")
        #expect(selection.stepDown() == nil)
        #expect(selection.markActiveProfileBroken() == nil)
    }

    @Test func beforeAnythingIsKnownThePickIsPessimisticButValid() {
        var selection = AutomaticSelection(thresholds: thresholds)
        let choice = selection.beginFile(facts: SourceFacts())
        #expect(choice.profile == .sharpen)
    }
}
