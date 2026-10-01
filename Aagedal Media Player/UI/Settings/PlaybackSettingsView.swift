// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Decode, audio-output and buffering settings. Every control here defaults to
// mpv's own behaviour, so an untouched install plays exactly as it did.

import SwiftUI

struct PlaybackSettingsView: View {
    @AppStorage(AppSettings.preventDisplaySleep.key)
    private var preventDisplaySleep = AppSettings.preventDisplaySleep.defaultValue
    @AppStorage(AppSettings.quitWhenNoOpenedWindow.key)
    private var quitWhenNoOpenedWindow = AppSettings.quitWhenNoOpenedWindow.defaultValue
    @AppStorage(AppSettings.audioPassthroughCodecs.key)
    private var audioPassthroughCodecs = AppSettings.audioPassthroughCodecs.defaultValue
    @AppStorage(AppSettings.replayGainMode.key)
    private var replayGainMode = AppSettings.replayGainMode.defaultValue
    @AppStorage(AppSettings.replayGainPreamp.key)
    private var replayGainPreamp = AppSettings.replayGainPreamp.defaultValue
    @AppStorage(AppSettings.replayGainClip.key)
    private var replayGainClip = AppSettings.replayGainClip.defaultValue
    @AppStorage(AppSettings.replayGainFallback.key)
    private var replayGainFallback = AppSettings.replayGainFallback.defaultValue
    @AppStorage(AppSettings.gaplessAudio.key)
    private var gaplessAudio = AppSettings.gaplessAudio.defaultValue
    @AppStorage(AppSettings.forceAVFoundationOutput.key)
    private var forceAVFoundationOutput = AppSettings.forceAVFoundationOutput.defaultValue
    @AppStorage(AppSettings.hardwareDecoder.key)
    private var hardwareDecoder = AppSettings.hardwareDecoder.defaultValue
    @AppStorage(AppSettings.videoDecodeThreads.key)
    private var videoDecodeThreads = AppSettings.videoDecodeThreads.defaultValue
    @AppStorage(AppSettings.audioDecodeThreads.key)
    private var audioDecodeThreads = AppSettings.audioDecodeThreads.defaultValue
    @AppStorage(AppSettings.preferredAudioLanguages.key)
    private var preferredAudioLanguages = AppSettings.preferredAudioLanguages.defaultValue
    @AppStorage(AppSettings.demuxerMaxBytes.key)
    private var demuxerMaxBytes = AppSettings.demuxerMaxBytes.defaultValue
    @AppStorage(AppSettings.demuxerReadaheadSeconds.key)
    private var demuxerReadaheadSeconds = AppSettings.demuxerReadaheadSeconds.defaultValue

    var body: some View {
        Form {
            Section("Session") {
                Toggle("Keep the Display Awake While Playing", isOn: $preventDisplaySleep)
                Toggle("Quit When the Last Window Closes", isOn: $quitWhenNoOpenedWindow)
            }

            Section("Audio Output") {
                Toggle("Force AVFoundation Output", isOn: $forceAVFoundationOutput)
                TextField("Passthrough Codecs", text: $audioPassthroughCodecs,
                          prompt: Text("ac3,dts,eac3"))
                Text("Comma-separated codecs to send to a receiver undecoded. Empty decodes everything locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Gapless Playback", selection: $gaplessAudio) {
                    Text("Weak").tag("weak")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                }
            }

            Section("Level Adjustment") {
                Picker("ReplayGain", selection: $replayGainMode) {
                    Text("Off").tag("no")
                    Text("Track").tag("track")
                    Text("Album").tag("album")
                }
                Text("Off by default: a review tool should not quietly change the level of the thing being reviewed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if replayGainMode != "no" {
                    Stepper("Pre-amp: \(replayGainPreamp, specifier: "%.1f") dB",
                            value: $replayGainPreamp, in: -15...15, step: 0.5)
                    Stepper("Fallback: \(replayGainFallback, specifier: "%.1f") dB",
                            value: $replayGainFallback, in: -15...15, step: 0.5)
                    Toggle("Prevent Clipping", isOn: $replayGainClip)
                }
            }

            Section("Decoding") {
                Picker("Hardware Decoding", selection: $hardwareDecoder) {
                    Text("Automatic").tag("auto")
                    Text("VideoToolbox").tag("videotoolbox")
                    Text("VideoToolbox (Copy Back)").tag("videotoolbox-copy")
                    Text("Off").tag("no")
                }
                Text("Automatic uses VideoToolbox for the codecs this Mac decodes in hardware. Mirrored files always use copy back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(videoDecodeThreads == 0
                        ? "Video Threads: Automatic"
                        : "Video Threads: \(videoDecodeThreads)",
                        value: $videoDecodeThreads, in: 0...32)
                Stepper(audioDecodeThreads == 0
                        ? "Audio Threads: Automatic"
                        : "Audio Threads: \(audioDecodeThreads)",
                        value: $audioDecodeThreads, in: 0...32)
                TextField("Preferred Audio Languages", text: $preferredAudioLanguages,
                          prompt: Text("eng,nor"))
            }

            Section("Buffering") {
                TextField("Demuxer Size", text: $demuxerMaxBytes, prompt: Text("Automatic"))
                Text("For example 2GiB. Backward playback and long-GOP 4K both want more than the default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(demuxerReadaheadSeconds == 0
                        ? "Readahead: Automatic"
                        : "Readahead: \(demuxerReadaheadSeconds, specifier: "%.0f") s",
                        value: $demuxerReadaheadSeconds, in: 0...120, step: 5)
            }

            Section {
                Text("Changes apply the next time a file is opened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
