// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import Testing

struct GPUBudgetMonitorTests {
    @Test func parsesFreshPassesFromMpvJSON() throws {
        let json = #"{"fresh":[{"desc":"merging planes","last":35666,"avg":99470,"peak":405833,"count":7,"samples":[405833]},{"desc":"ortho (vert) upscaling (lanczos)","last":434083,"avg":1000000,"peak":595667,"count":31,"samples":[]}],"redraw":[]}"#
        let timing = try #require(VOPassTiming(json: json))
        #expect(abs(timing.totalMilliseconds - 1.09947) < 1e-9)
        #expect(timing.minimumSampleCount == 7)
    }

    // With FSRCNNX_x2_16 loaded, mpv 0.41 never samples the final output pass:
    // it stays at count 0 while the 29 shader passes reach 256 (measured on
    // gaia.mov, 2026-09-30). An unsampled pass must not hold warm-up forever.
    @Test func ignoresPassesMpvNeverSamples() throws {
        let json = #"{"fresh":[{"desc":"feature map 1","last":150000,"avg":177000,"peak":400000,"count":256,"samples":[]},{"desc":"aggregation","last":250000,"avg":251000,"peak":300000,"count":256,"samples":[]},{"desc":"ortho (horiz) upscaling (lanczos), color encoding","last":0,"avg":0,"peak":0,"count":0,"samples":[]}],"redraw":[]}"#
        let timing = try #require(VOPassTiming(json: json))
        #expect(timing.minimumSampleCount == 256)
        #expect(abs(timing.totalMilliseconds - 0.428) < 1e-9)
    }

    @Test(arguments: [#"{"fresh":[],"redraw":[]}"#, "fresh:\n", ""])
    func rejectsEmptyOrNonJSONPasses(json: String) {
        #expect(VOPassTiming(json: json) == nil)
    }

    @Test func budgetIsHalfThePeriodOfTheSlowerRate() throws {
        let cinema = try #require(GPUBudgetMonitor(sourceFPS: 24, displayFPS: 120).budgetMilliseconds)
        #expect(abs(cinema - 500.0 / 24.0) < 1e-9)
        let noDisplay = try #require(GPUBudgetMonitor(sourceFPS: 60, displayFPS: 0).budgetMilliseconds)
        #expect(abs(noDisplay - 500.0 / 60.0) < 1e-9)
        #expect(GPUBudgetMonitor(sourceFPS: 0, displayFPS: .nan).budgetMilliseconds == nil)
    }

    @Test func waitsForEveryPassToWarmUp() {
        var monitor = GPUBudgetMonitor(sourceFPS: 24, displayFPS: 120)
        let compileSpike = BudgetSample(
            timing: VOPassTiming(totalMilliseconds: 81.66, minimumSampleCount: 0), droppedFrames: 0, uptime: 0)
        #expect(monitor.evaluate(compileSpike) == .warmingUp)
    }

    // 24 fps figures measured at 2.69x on an M1 Pro: C4F16 12.0 ms, C4F32 28.2 ms.
    @Test func judgesWarmTimingsAgainstTheBudget() {
        var light = GPUBudgetMonitor(sourceFPS: 24, displayFPS: 120)
        #expect(light.evaluate(BudgetSample(
            timing: VOPassTiming(totalMilliseconds: 12.0, minimumSampleCount: 49), droppedFrames: 0, uptime: 0)) == .withinBudget)

        var strong = GPUBudgetMonitor(sourceFPS: 24, displayFPS: 120)
        #expect(strong.evaluate(BudgetSample(
            timing: VOPassTiming(totalMilliseconds: 28.2, minimumSampleCount: 78), droppedFrames: 0, uptime: 0)) == .overBudget)
    }

    @Test func aDropBurstIsOverBudgetEvenWithoutTimings() {
        var monitor = GPUBudgetMonitor(sourceFPS: 0, displayFPS: 0)
        #expect(monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 0, uptime: 0)) == .withinBudget)
        #expect(monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 8, uptime: 1)) == .overBudget)
    }

    // RAVU zoom dropped 2 frames while its shader compiled, then none.
    @Test func startUpDropsBelowTheLimitAreTolerated() {
        var monitor = GPUBudgetMonitor(sourceFPS: 0, displayFPS: 0)
        for (second, drops) in [(0.0, 0), (1, 1), (2, 2), (3, 2), (4, 2)] {
            #expect(monitor.evaluate(BudgetSample(timing: nil, droppedFrames: drops, uptime: second)) == .withinBudget)
        }
    }

    @Test func dropsOutsideTheWindowAreForgotten() {
        var monitor = GPUBudgetMonitor(sourceFPS: 0, displayFPS: 0)
        _ = monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 0, uptime: 0))
        _ = monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 2, uptime: 1))
        #expect(monitor.evaluate(BudgetSample(timing: nil, droppedFrames: 4, uptime: 5)) == .withinBudget)
    }

    @Test(arguments: [
        ("vo/gpu-next/libplacebo", "Failed executing hook, disabling\n", true),
        ("vo/gpu-next/libplacebo", "Failed creating render pass for dispatch\n", false),
        ("cplayer", "Failed executing hook, disabling\n", false),
    ])
    func recognisesOnlyTheLibplaceboHookFailure(prefix: String, text: String, expected: Bool) {
        #expect(GPUBudgetMonitor.isShaderFailure(prefix: prefix, text: text) == expected)
    }
}
