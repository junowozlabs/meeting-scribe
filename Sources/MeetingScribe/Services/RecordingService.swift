@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import CoreGraphics
import Foundation

struct RecordingResult: Sendable {
    let audioURL: URL
    let screenURL: URL?
    let duration: TimeInterval
}

final class RecordingService: NSObject, @unchecked Sendable {
    var onCaptureError: (@Sendable (Error) -> Void)?
    private let captureQueue = DispatchQueue(label: "com.junowoz.MeetingScribe.capture")
    private let microphoneQueue = DispatchQueue(label: "com.junowoz.MeetingScribe.microphone")
    private var stream: SCStream?
    private var microphoneSession: AVCaptureSession?
    private var systemWriter: TimedWriter?
    private var microphoneWriter: TimedWriter?
    private var videoWriter: TimedWriter?
    private var directory: URL?
    private var startedAt: Date?
    private var recordsScreen = false

    func requestPermissions(includeMicrophone: Bool) async -> Bool {
        let screenGranted = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        guard screenGranted else { return false }
        guard includeMicrophone else { return true }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(in directory: URL, includeMicrophone: Bool, recordScreen: Bool) async throws {
        guard await requestPermissions(includeMicrophone: includeMicrophone) else { throw RecordingError.permissionDenied }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw RecordingError.noDisplay }
        let ownApplication = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplication.map { [$0] } ?? [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.showsCursor = true
        let scale = min(1, min(1_920.0 / Double(display.width), 1_080.0 / Double(display.height)))
        configuration.width = max(2, Int(Double(display.width) * scale) / 2 * 2)
        configuration.height = max(2, Int(Double(display.height) * scale) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6

        self.directory = directory
        recordsScreen = recordScreen
        systemWriter = try TimedWriter(url: directory.appending(path: ".system.m4a"), kind: .audio)
        microphoneWriter = includeMicrophone ? try TimedWriter(url: directory.appending(path: ".microphone.m4a"), kind: .audio) : nil
        videoWriter = recordScreen ? try TimedWriter(url: directory.appending(path: ".screen.mov"), kind: .video(width: configuration.width, height: configuration.height)) : nil

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
        if recordScreen { try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue) }
        self.stream = stream
        if includeMicrophone { try configureMicrophone() }
        try await stream.startCapture()
        if let microphoneSession { microphoneQueue.async { microphoneSession.startRunning() } }
        startedAt = Date()
    }

    func stop() async throws -> RecordingResult {
        guard let directory, let startedAt else { throw RecordingError.notRecording }
        do {
            if let stream { try await stream.stopCapture() }
            await stopMicrophone()
            captureQueue.sync {}; microphoneQueue.sync {}
            try await systemWriter?.finish(); try await microphoneWriter?.finish(); try await videoWriter?.finish()

            let system = systemWriter?.hasSamples == true ? systemWriter?.url : nil
            let microphone = microphoneWriter?.hasSamples == true ? microphoneWriter?.url : nil
            guard system != nil || microphone != nil else { throw RecordingError.noAudio }
            let referenceTime = systemWriter?.hasSamples == true ? systemWriter?.firstTime ?? 0 : microphoneWriter?.firstTime ?? 0
            let audioURL = directory.appending(path: "meeting-audio.m4a")
            try await MediaProcessor.mixAudio(
                systemURL: system,
                microphoneURL: microphone,
                systemOffset: systemWriter?.firstTime ?? referenceTime,
                microphoneOffset: microphoneWriter?.firstTime ?? referenceTime,
                outputURL: audioURL
            )
            var screenURL: URL?
            if recordsScreen, let videoWriter, videoWriter.hasSamples {
                let finalVideo = directory.appending(path: "screen-recording.mov")
                let earliestAudio = [systemWriter, microphoneWriter].compactMap { $0?.hasSamples == true ? $0?.firstTime : nil }.min() ?? videoWriter.firstTime
                try await MediaProcessor.combineVideo(videoWriter.url, audioURL: audioURL, audioOffset: max(0, earliestAudio - videoWriter.firstTime), outputURL: finalVideo)
                screenURL = finalVideo
            }
            cleanupTemporaryFiles()
            let duration = Date().timeIntervalSince(startedAt)
            reset()
            return RecordingResult(audioURL: audioURL, screenURL: screenURL, duration: duration)
        } catch {
            await stopMicrophone()
            systemWriter?.cancel(); microphoneWriter?.cancel(); videoWriter?.cancel()
            cleanupTemporaryFiles(); reset()
            throw error
        }
    }

    func cancel() async {
        try? await stream?.stopCapture()
        await stopMicrophone()
        systemWriter?.cancel(); microphoneWriter?.cancel(); videoWriter?.cancel()
        cleanupTemporaryFiles()
        reset()
    }

    private func configureMicrophone() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else { throw RecordingError.noMicrophone }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RecordingError.noMicrophone }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: microphoneQueue)
        guard session.canAddOutput(output) else { throw RecordingError.noMicrophone }
        session.addOutput(output)
        microphoneSession = session
    }

    private func stopMicrophone() async {
        guard let microphoneSession, microphoneSession.isRunning else { return }
        await withCheckedContinuation { continuation in
            microphoneQueue.async { microphoneSession.stopRunning(); continuation.resume() }
        }
    }

    private func cleanupTemporaryFiles() {
        for writer in [systemWriter, microphoneWriter, videoWriter].compactMap({ $0 }) { try? FileManager.default.removeItem(at: writer.url) }
    }
    private func reset() {
        stream = nil; microphoneSession = nil; systemWriter = nil; microphoneWriter = nil; videoWriter = nil; directory = nil; startedAt = nil
    }

    enum RecordingError: LocalizedError {
        case permissionDenied, noDisplay, noMicrophone, notRecording, noAudio
        var errorDescription: String? {
            switch self {
            case .permissionDenied: "Permita Gravação de Tela e Microfone em Ajustes do Sistema > Privacidade e Segurança. Pode ser necessário reabrir o app."
            case .noDisplay: "Nenhuma tela disponível para gravação."
            case .noMicrophone: "Nenhum microfone disponível."
            case .notRecording: "Não há gravação em andamento."
            case .noAudio: "A gravação terminou sem áudio utilizável."
            }
        }
    }
}

extension RecordingService: SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onCaptureError?(error)
    }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .audio: systemWriter?.append(sampleBuffer)
        case .screen: videoWriter?.append(sampleBuffer)
        default: break
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        microphoneWriter?.append(sampleBuffer)
    }
}

private final class TimedWriter: @unchecked Sendable {
    enum Kind { case audio, video(width: Int, height: Int) }
    let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private(set) var firstTime = 0.0
    private(set) var hasSamples = false

    init(url: URL, kind: Kind) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        let fileType: AVFileType
        let settings: [String: Any]
        switch kind {
        case .audio:
            fileType = .m4a
            settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        case .video(let width, let height):
            fileType = .mov
            settings = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height]
            input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        }
        writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecordingService.RecordingError.noAudio }
        writer.add(input)
    }

    func append(_ buffer: CMSampleBuffer) {
        guard writer.status != .failed && writer.status != .cancelled else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        if !hasSamples {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: time)
            firstTime = time.seconds
            hasSamples = true
        }
        if input.isReadyForMoreMediaData { _ = input.append(buffer) }
    }

    func finish() async throws {
        guard hasSamples else { return }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed { throw writer.error ?? RecordingService.RecordingError.noAudio }
    }
    func cancel() { writer.cancelWriting() }
}
