// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import XCTest

final class RenderProfileTests: XCTestCase {
    private var shaderDirectory: URL!

    override func setUpWithError() throws {
        shaderDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "RenderProfileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shaderDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: shaderDirectory)
    }

    private func writeShader(_ name: String) throws {
        try Data().write(to: shaderDirectory.appending(path: name))
    }

    func testOffProfileLoadsNoShaders() {
        let library = ShaderLibrary(directoryPath: shaderDirectory.path)
        XCTAssertEqual(library.shaderPaths(for: .off), [])
        XCTAssertEqual(library.shaderOptionValue(for: .off), "")
        XCTAssertFalse(RenderProfile.off.enablesDeband)
    }

    func testShaderPathsKeepProfileOrder() throws {
        for name in RenderProfile.upscaleLight.shaderFileNames {
            try writeShader(name)
        }

        let library = ShaderLibrary(directoryPath: shaderDirectory.path)
        let paths = library.shaderPaths(for: .upscaleLight)

        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].hasSuffix("ArtCNN_C4F16.glsl"), "the upscaler must run before chroma reconstruction")
        XCTAssertTrue(paths[1].hasSuffix("CfL_Prediction.glsl"))
        XCTAssertEqual(library.shaderOptionValue(for: .upscaleLight), paths.joined(separator: ":"))
        XCTAssertEqual(library.missingShaderNames(for: .upscaleLight), [])
    }

    func testMissingShadersAreDroppedRatherThanFailingTheProfile() throws {
        try writeShader("CfL_Prediction.glsl")

        let library = ShaderLibrary(directoryPath: shaderDirectory.path)

        XCTAssertEqual(library.missingShaderNames(for: .upscaleLight), ["ArtCNN_C4F16.glsl"])
        XCTAssertEqual(library.shaderPaths(for: .upscaleLight).count, 1)
        XCTAssertTrue(library.shaderOptionValue(for: .upscaleLight).hasSuffix("CfL_Prediction.glsl"))
    }

    func testEmptyDirectorySettingFallsBackToTheMpvShaderFolder() {
        XCTAssertEqual(ShaderLibrary(directoryPath: "").directory, ShaderLibrary.defaultDirectory)
        XCTAssertEqual(ShaderLibrary(directoryPath: "   ").directory, ShaderLibrary.defaultDirectory)
    }

    func testTildePathsExpand() {
        let library = ShaderLibrary(directoryPath: "~/shaders")
        XCTAssertFalse(library.directory.path.contains("~"))
        XCTAssertTrue(library.directory.path.hasSuffix("/shaders"))
    }

    func testOnlySharpenDepartsFromTheFaithfulScaler() {
        for profile in RenderProfile.allCases {
            let options = profile.scaleOptions
            XCTAssertEqual(Set(options.keys), ["scale", "scaler-resizes-only"], "every profile must reset every key")
            if profile == .sharpen {
                XCTAssertEqual(options["scale"], "ewa_lanczossharp")
                XCTAssertEqual(options["scaler-resizes-only"], "no")
            } else {
                XCTAssertEqual(options["scale"], "lanczos", "\(profile.rawValue)")
                XCTAssertEqual(options["scaler-resizes-only"], "yes", "\(profile.rawValue)")
            }
        }
    }

    func testDefaultProfileIsAutomatic() {
        XCTAssertEqual(AppSettings.renderProfile.defaultValue, RenderProfile.automatic.rawValue)
    }

    func testAutomaticLoadsNoShadersItselfAndIsListedFirst() {
        XCTAssertEqual(RenderProfile.automatic.shaderFileNames, [])
        XCTAssertFalse(RenderProfile.automatic.enablesDeband)
        XCTAssertEqual(RenderProfile.allCases.first, .automatic)
        XCTAssertEqual(RenderProfile.automatic.displayName, "Automatic")
    }

    func testLibraryResolvesNameLists() throws {
        try writeShader("ravu-zoom-ar-r3.hook")
        let library = ShaderLibrary(directoryPath: shaderDirectory.path)
        let names = ["ravu-zoom-ar-r3.hook", "ArtCNN_C4F16.glsl"]
        XCTAssertEqual(library.shaderPaths(named: names).count, 1)
        XCTAssertTrue(library.shaderPaths(named: names).first?.hasSuffix("ravu-zoom-ar-r3.hook") == true)
        XCTAssertEqual(library.missingShaderNames(named: names), ["ArtCNN_C4F16.glsl"])
    }

    func testOnlyRestorationEnablesDeband() {
        for profile in RenderProfile.allCases {
            XCTAssertEqual(profile.enablesDeband, profile == .restore, "\(profile.rawValue)")
        }
    }

    /// hdeband must run before any other shader and replaces mpv's deband.
    func testHdebandRunsFirstWithBuiltInDebandOff() {
        for profile in RenderProfile.allCases where profile.shaderFileNames.contains("hdeband.glsl") {
            XCTAssertEqual(profile.shaderFileNames.first, "hdeband.glsl", "\(profile.rawValue)")
            XCTAssertFalse(profile.enablesDeband, "\(profile.rawValue)")
        }
    }
}
