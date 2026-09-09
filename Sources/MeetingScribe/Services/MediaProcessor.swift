import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum MediaProcessor {
    // AssemblyAI accepts these formats directly, including codecs that AVFoundation cannot decode.
    static let supportedExtensions: Set<String> = [
        "3ga", "8svx", "aac", "ac3", "aif", "aiff", "alac", "amr", "ape", "au", "caf",
        "dss", "flac", "flv", "m4a", "m4b", "m4p", "m4r", "mp3", "mpga", "ogg", "oga",
        "mogg", "opus", "qcp", "tta", "voc", "wav", "wma", "wv", "webm", "mts", "m2ts",
        "ts", "mov", "mp2", "mp4", "m4v", "mxf"
    ]

    static var supportedContentTypes: [UTType] {
        supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    static func supports(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func validateImport(_ url: URL) throws {
        guard supports(url) else {
            throw MediaError.unsupportedFormat
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isReadableKey])
        guard values.isRegularFile == true, values.isReadable != false else { throw MediaError.unreadableFile }
        guard let size = values.fileSize, size > 0 else { throw MediaError.emptyFile }
    }

    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    static func prepareAudio(from inputURL: URL, in outputDirectory: URL) async throws -> URL {
        try validateImport(inputURL)
        // Upload the original file without quality loss or a local codec dependency.
        // CAF is created by the recorder and needs conversion before upload.
        guard inputURL.pathExtension.lowercased() == "caf" else { return inputURL }
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
        case noAudio, cannotExport, unsupportedFormat, unreadableFile, emptyFile
        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: "Formato não compatível. Escolha um arquivo de áudio ou vídeo, como M4A, MP3, MP4, OGG, FLAC ou WAV."
            case .unreadableFile: "Não foi possível abrir este arquivo. Copie-o para uma pasta local e tente novamente."
            case .emptyFile: "Este arquivo está vazio. Escolha um arquivo com áudio."
            case .noAudio: "O arquivo selecionado não contém áudio."
            case .cannotExport: "Não foi possível preparar o áudio para transcrição."
            }
        }
    }
}
