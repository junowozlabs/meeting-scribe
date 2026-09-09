import CoreGraphics
import PDFKit
import Foundation
import Testing
@testable import MeetingScribe

private func exportFixture() -> Meeting {
    var meeting = Meeting(title: "Reunião de planejamento", sourceURL: URL(filePath: "/tmp/source.mp3"), outputDirectory: URL(filePath: "/tmp/output"))
    meeting.text = "Olá, equipe. Decidimos continuar."
    meeting.utterances = [TranscriptUtterance(speaker: "Juno", text: meeting.text, start: 1_250, end: 4_500, confidence: nil, words: nil)]
    meeting.summary = "Próximo passo: revisar a proposta."
    return meeting
}

@Test func exportsEveryUserFormat() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let meeting = exportFixture()
    for format in ExportService.Format.allCases {
        let url = directory.appending(path: ExportService.suggestedFilename(meeting: meeting, format: format))
        try ExportService.export(meeting: meeting, format: format, to: url)
        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
        if format == .pdf {
            #expect(String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-")
        } else {
            #expect(String(decoding: data, as: UTF8.self).contains("Olá, equipe."))
        }
    }
}

@Test func paginatesLongPDFWithoutDroppingText() throws {
    var meeting = exportFixture()
    meeting.utterances = []
    meeting.text = String(repeating: "Uma linha da reunião com acentuação em português.\n", count: 450) + "MARCADOR FINAL"
    let data = try ExportService.pdfData(meeting)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    #expect(document.numberOfPages > 3)
    #expect(document.page(at: document.numberOfPages) != nil)
    let extracted = try #require(PDFDocument(data: data)?.string)
    #expect(extracted.contains("MARCADOR FINAL"))
    #expect(extracted.contains("acentuação em português"))
}

@Test func exportsCaptionsWithoutSpeakerLabels() throws {
    var meeting = exportFixture()
    meeting.utterances = []
    meeting.words = [TranscriptWord(text: "Olá", start: 100, end: 500, confidence: 1, speaker: nil), TranscriptWord(text: "equipe", start: 500, end: 900, confidence: 1, speaker: nil)]
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".srt")
    defer { try? FileManager.default.removeItem(at: url) }
    try ExportService.export(meeting: meeting, format: .srt, to: url)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("00:00:00,100 --> 00:00:00,900"))
    #expect(text.contains("\nOlá equipe"))
    #expect(!text.contains("\n: "))
}

@Test func rejectsUnavailableCaptionsAndEmptyTranscript() throws {
    var meeting = exportFixture()
    meeting.utterances = []
    let url = URL(filePath: "/tmp/should-not-exist-" + UUID().uuidString)
    #expect(throws: ExportService.ExportError.self) { try ExportService.export(meeting: meeting, format: .srt, to: url) }
    meeting.text = ""
    #expect(throws: ExportService.ExportError.self) { try ExportService.export(meeting: meeting, format: .txt, to: url) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func safeFilenamesAndCaptionEscaping() {
    var meeting = exportFixture()
    meeting.title = "  Projeto / gravação: final\n"
    let filename = ExportService.suggestedFilename(meeting: meeting, format: .markdown)
    #expect(!filename.contains("/"))
    #expect(!filename.contains(":"))
    #expect(!filename.contains("\n"))
    #expect(filename.hasSuffix(".md"))
    let utterance = TranscriptUtterance(speaker: "A > B", text: "<teste> & oi", start: 0, end: 2_000, confidence: nil, words: nil)
    #expect(ExportService.speakerVTT([utterance]).contains("<v A &gt; B>&lt;teste&gt; &amp; oi"))
}

@Test func acceptsDocumentedMediaFormats() {
    for ext in ["m4a", "mp3", "mp4", "ogg", "flac", "wav", "webm", "opus", "MOV", "caf"] {
        #expect(MediaProcessor.supports(URL(filePath: "/tmp/media." + ext)))
    }
    #expect(!MediaProcessor.supports(URL(filePath: "/tmp/media.txt")))
    #expect(!MediaProcessor.supports(URL(string: "https://example.com/audio.mp3")!))
}

@Test func rejectsEmptyFilesAndDirectories() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".mp3")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "empty.mp3")
    try Data().write(to: file)
    #expect(throws: MediaProcessor.MediaError.self) { try MediaProcessor.validateImport(directory) }
    #expect(throws: MediaProcessor.MediaError.self) { try MediaProcessor.validateImport(file) }
}

@Test func uploadsOriginalWithoutNativeCodecRequirement() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    // The service validates actual codec content remotely; local import preserves bytes.
    for ext in ["ogg", "flac", "webm", "mp3", "mp4"] {
        let file = directory.appending(path: "source." + ext)
        let bytes = Data("test payload for passthrough".utf8)
        try bytes.write(to: file)
        let prepared = try await MediaProcessor.prepareAudio(from: file, in: directory)
        #expect(prepared == file)
        #expect(try Data(contentsOf: prepared) == bytes)
    }
}
