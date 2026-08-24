import AVFoundation
import Foundation
import Testing
@testable import MeetingScribe

@Test func formatsSpeakerCaptions() {
    let utterances = [TranscriptUtterance(speaker: "Juno", text: "Olá, equipe.", start: 1_250, end: 3_500, confidence: 0.96, words: nil)]
    #expect(ExportService.speakerSRT(utterances).contains("00:00:01,250 --> 00:00:03,500"))
    #expect(ExportService.speakerVTT(utterances).contains("<v Juno>Olá, equipe."))
}

@Test func parsesAdvancedSettings() {
    var settings = TranscriptionSettings()
    settings.speakerNames = "Juno, Walter"
    settings.keyterms = "MEPO, Universal-3.5 Pro"
    settings.customSpelling = "mepo=MEPO"
    #expect(settings.parsedSpeakerNames == ["Juno", "Walter"])
    #expect(settings.parsedKeyterms.count == 2)
    #expect(settings.parsedCustomSpelling.first?.to == "MEPO")
    #expect(settings.parsedCustomSpelling.first?.from == ["mepo"])
}

@Test func mixesSystemAndMicrophoneIntoOneAudioTrack() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let system = directory.appending(path: "system.caf")
    let microphone = directory.appending(path: "microphone.caf")
    try makeTone(at: system, frequency: 440)
    try makeTone(at: microphone, frequency: 660)
    let output = directory.appending(path: "mixed.m4a")
    try await MediaProcessor.mixAudio(systemURL: system, microphoneURL: microphone, systemOffset: 10, microphoneOffset: 10.1, outputURL: output)
    let asset = AVURLAsset(url: output)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    let duration = try await asset.load(.duration).seconds
    #expect(tracks.count == 1)
    #expect(duration > 0.9)
}

@Test func supportsMicrophoneOnlyRecording() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let microphone = directory.appending(path: "microphone.caf")
    try makeTone(at: microphone, frequency: 440)
    let output = directory.appending(path: "mixed.m4a")
    try await MediaProcessor.mixAudio(systemURL: nil, microphoneURL: microphone, systemOffset: 0, microphoneOffset: 5, outputURL: output)
    let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)
    #expect(tracks.count == 1)
}

private func makeTone(at url: URL, frequency: Double) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames: AVAudioFrameCount = 48_000
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let values = buffer.floatChannelData![0]
    for frame in 0..<Int(frames) { values[frame] = Float(sin(2 * .pi * frequency * Double(frame) / 48_000) * 0.15) }
    try file.write(from: buffer)
}
