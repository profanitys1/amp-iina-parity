// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Prints, for every video under the given folders, the facts amp reads from metadata, the frame
// statistics, and the class the shipped classifier gives it. Numbers only: no frame is saved or
// shown. Built by scripts/calibrate-profile-picker.sh from the app's own SourceClassifier.swift
// and FrameMath.swift, so the output is what the app would compute.

import Foundation

let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "mts", "m2ts", "ts", "mxf"]

func tool(_ name: String, environment key: String) -> String {
    if let override = ProcessInfo.processInfo.environment[key], !override.isEmpty { return override }
    let probe = Process()
    probe.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    probe.arguments = [name]
    let pipe = Pipe()
    probe.standardOutput = pipe
    try? probe.run()
    probe.waitUntilExit()
    let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
        FileHandle.standardError.write(Data("\(name) not found; set \(key)\n".utf8))
        exit(1)
    }
    return path
}

let ffmpeg = tool("ffmpeg", environment: "FFMPEG")
let ffprobe = tool("ffprobe", environment: "FFPROBE")

func run(_ executable: String, _ arguments: [String]) -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return Data() }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return data
}

func number(_ value: Any?) -> Double? {
    if let string = value as? String { return Double(string) }
    return (value as? NSNumber)?.doubleValue
}

func frameRate(_ value: Any?) -> Double {
    guard let text = value as? String else { return 0 }
    let parts = text.split(separator: "/").compactMap { Double($0) }
    if parts.count == 2, parts[1] > 0 { return parts[0] / parts[1] }
    return parts.first ?? 0
}

func probe(_ path: String) -> (facts: SourceFacts, duration: Double)? {
    let data = run(ffprobe, ["-v", "error", "-select_streams", "v:0",
                             "-show_entries", "stream=codec_name,width,height,avg_frame_rate,bit_rate,pix_fmt,color_transfer:stream_tags:format=duration,bit_rate:format_tags",
                             "-of", "json", path])
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let stream = (root["streams"] as? [[String: Any]])?.first else { return nil }
    let format = root["format"] as? [String: Any] ?? [:]
    let duration = number(format["duration"]) ?? 0
    let bitrate = number(stream["bit_rate"]) ?? number(format["bit_rate"]) ?? 0
    let transfer = (stream["color_transfer"] as? String) ?? ""
    var tags: [String: Any] = (format["tags"] as? [String: Any]) ?? [:]
    tags.merge((stream["tags"] as? [String: Any]) ?? [:]) { first, _ in first }
    let topaz = tags.first { ["videoai", "videoai_provider"].contains($0.key.lowercased()) }.map { "\($0.value)" }
    let facts = SourceFacts(
        codec: stream["codec_name"] as? String,
        width: Int(number(stream["width"]) ?? 0),
        height: Int(number(stream["height"]) ?? 0),
        fps: frameRate(stream["avg_frame_rate"]),
        videoBitrate: Int64(bitrate),
        bitDepth: SourceFacts.bitDepth(pixelFormat: stream["pix_fmt"] as? String),
        isHDR: transfer == "smpte2084" || transfer == "arib-std-b67",
        topazTag: topaz
    )
    return (facts, duration)
}

func stats(_ path: String, duration: Double) -> FrameStats? {
    var frames: [FrameStats] = []
    for time in FrameMath.sampleTimes(duration: duration) {
        let data = run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-nostdin", "-ss", String(format: "%.3f", time),
                                "-i", path, "-frames:v", "1", "-an", "-sn", "-pix_fmt", "gray",
                                "-f", "image2pipe", "-c:v", "pgm", "-"])
        if let image = FrameMath.parsePGM(data), let value = FrameMath.stats(luma: image.luma, width: image.width, height: image.height) {
            frames.append(value)
        }
    }
    return frames.count >= 4 ? FrameMath.average(frames) : nil
}

func files(under folder: String) -> [String] {
    let root = (folder as NSString).expandingTildeInPath
    guard let walker = FileManager.default.enumerator(atPath: root) else { return [] }
    var found: [String] = []
    for case let relative as String in walker where videoExtensions.contains((relative as NSString).pathExtension.lowercased()) {
        found.append((root as NSString).appendingPathComponent(relative))
    }
    return found.sorted()
}

let folders = CommandLine.arguments.count > 1
    ? Array(CommandLine.arguments.dropFirst())
    : ["~/Downloads/Movies", "~/Downloads/whatsapp", "~/Downloads/Archives/Movies"]

print(["file", "codec", "size", "fps", "kbit_s", "bits_per_pixel", "bit_depth", "hdr", "topaz",
       "detail", "blockiness", "noise", "class", "reason"].joined(separator: "\t"))
for folder in folders {
    for path in files(under: folder) {
        guard let (facts, duration) = probe(path) else { continue }
        let measured = stats(path, duration: duration)
        let result = SourceClassifier.classify(facts, measured)
        let columns: [String] = [
            path,
            facts.codec ?? "-",
            "\(facts.width)x\(facts.height)",
            String(format: "%.3f", facts.fps),
            String(format: "%.0f", Double(facts.videoBitrate) / 1000),
            facts.bitsPerPixel.map { String(format: "%.4f", $0) } ?? "-",
            facts.bitDepth.map(String.init) ?? "-",
            facts.isHDR ? "yes" : "no",
            facts.topazTag == nil ? "no" : "yes",
            measured.map { String(format: "%.3f", $0.detailRatio) } ?? "-",
            measured.map { String(format: "%.3f", $0.blockiness) } ?? "-",
            measured.map { String(format: "%.4f", $0.noise) } ?? "-",
            result.sourceClass.rawValue,
            result.reason,
        ]
        print(columns.joined(separator: "\t"))
        fflush(stdout)
    }
}
