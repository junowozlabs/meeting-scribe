import AVFoundation
import Foundation

enum MediaProcessor {
    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        return (try? await asset.load(.duration).seconds) ?? 0
    }

    static func prepareAudio(from inputURL: URL, in outputDirectory: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw MediaError.noAudio }
        let outputURL = outputDirectory.appending(path: "meeting-audio.m4a")
        try? FileManager.default.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaError.cannotExport
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = true
        await exporter.export()
        guard exporter.status == .completed else { throw exporter.error ?? MediaError.cannotExport }
        return outputURL
    }

    static func mixAudio(systemURL: URL?, microphoneURL: URL?, systemOffset: Double, microphoneOffset: Double, outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let sources = [(systemURL, systemOffset), (microphoneURL, microphoneOffset)].compactMap { url, offset in url.map { ($0, offset) } }
        let earliest = sources.map(\.1).min() ?? 0
        var parameters: [AVMutableAudioMixInputParameters] = []
        for (url, offset) in sources {
            let asset = AVURLAsset(url: url)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first,
                  let targetTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let duration = try await asset.load(.duration)
            try targetTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: CMTime(seconds: max(0, offset - earliest), preferredTimescale: 48_000))
            let input = AVMutableAudioMixInputParameters(track: targetTrack)
            input.setVolume(sources.count > 1 ? 0.72 : 1, at: .zero)
            parameters.append(input)
        }
        guard !parameters.isEmpty, let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { throw MediaError.cannotExport }
        try? FileManager.default.removeItem(at: outputURL)
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        exporter.audioMix = mix
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        await exporter.export()
        guard exporter.status == .completed else { throw exporter.error ?? MediaError.cannotExport }
    }

    static func combineVideo(_ videoURL: URL, audioURL: URL, audioOffset: Double = 0, outputURL: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let composition = AVMutableComposition()
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let targetVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let targetAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw MediaError.cannotExport }
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        try targetVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideo, at: .zero)
        let offset = CMTime(seconds: max(0, audioOffset), preferredTimescale: 48_000)
        let available = max(.zero, CMTimeSubtract(videoDuration, offset))
        try targetAudio.insertTimeRange(CMTimeRange(start: .zero, duration: min(available, audioDuration)), of: sourceAudio, at: offset)
        targetVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw MediaError.cannotExport }
        try? FileManager.default.removeItem(at: outputURL)
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        await exporter.export()
        guard exporter.status == .completed else { throw exporter.error ?? MediaError.cannotExport }
    }

    enum MediaError: LocalizedError {
        case noAudio, cannotExport
        var errorDescription: String? {
            switch self {
            case .noAudio: "O arquivo selecionado não contém áudio."
            case .cannotExport: "Não foi possível preparar o áudio para transcrição."
            }
        }
    }
}
