import Foundation
import CoreGraphics
import CoreText
import UniformTypeIdentifiers

enum ExportService {
    enum Format: String, CaseIterable, Identifiable {
        case txt, markdown, pdf, srt, vtt
        var id: String { rawValue }
        var fileExtension: String { self == .markdown ? "md" : rawValue }
        var title: String {
            switch self {
            case .txt: "Texto (.txt)"
            case .markdown: "Markdown (.md)"
            case .pdf: "Documento PDF (.pdf)"
            case .srt: "Legendas (.srt)"
            case .vtt: "Legendas WebVTT (.vtt)"
            }
        }
        var contentType: UTType { UTType(filenameExtension: fileExtension) ?? .plainText }
        var needsTimestamps: Bool { self == .srt || self == .vtt }
    }

    static func suggestedFilename(meeting: Meeting, format: Format) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
        let name = meeting.title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((name.isEmpty ? "Transcrição" : name).prefix(120)) + "." + format.fileExtension
    }

    static func transcriptText(_ meeting: Meeting) -> String {
        meeting.utterances.isEmpty ? meeting.text : meeting.utterances.map {
            "[\(AppFormatters.timestamp($0.start)) - \(AppFormatters.timestamp($0.end))] \($0.speaker): \($0.text)"
        }.joined(separator: "\n\n")
    }

    static func hasTimedTranscript(_ meeting: Meeting) -> Bool {
        !meeting.utterances.isEmpty || !meeting.words.isEmpty
    }

    static func markdown(_ meeting: Meeting) -> String {
        let heading = meeting.title.replacingOccurrences(of: "\n", with: " ")
        var text = "# \(heading)\n\nData: \(AppFormatters.date.string(from: meeting.createdAt))\n\nDuração: \(AppFormatters.duration(meeting.durationSeconds))\n"
        if let summary = meeting.summary, !summary.isEmpty, !summary.contains("Resumo não gerado:") {
            text += "\n## Resumo\n\n\(summary)\n"
        }
        return text + "\n## Transcrição\n\n" + transcriptText(meeting) + "\n"
    }

    static func export(meeting: Meeting, format: Format, to url: URL) throws {
        guard !meeting.text.isEmpty || !meeting.utterances.isEmpty else { throw ExportError.noTranscript }
        if format.needsTimestamps && !hasTimedTranscript(meeting) { throw ExportError.noTimestamps }
        let data: Data
        switch format {
        case .txt: data = Data((transcriptText(meeting) + "\n").utf8)
        case .markdown: data = Data(markdown(meeting).utf8)
        case .pdf: data = try pdfData(meeting)
        case .srt: data = Data(speakerSRT(captions(meeting)).utf8)
        case .vtt: data = Data(speakerVTT(captions(meeting)).utf8)
        }
        try data.write(to: url, options: .atomic)
    }

    // Word timestamps remain useful when speaker labels were disabled.
    private static func captions(_ meeting: Meeting) -> [TranscriptUtterance] {
        if !meeting.utterances.isEmpty { return meeting.utterances }
        var result: [TranscriptUtterance] = []
        var group: [TranscriptWord] = []
        func flush() {
            guard let first = group.first, let last = group.last else { return }
            result.append(TranscriptUtterance(speaker: first.speaker ?? "", text: group.map(\.text).joined(separator: " "),
                start: first.start, end: last.end, confidence: nil, words: nil))
            group = []
        }
        for word in meeting.words {
            if let first = group.first, group.count >= 12 || word.start - first.start >= 5_000 || word.speaker != first.speaker { flush() }
            group.append(word)
        }
        flush()
        return result
    }

    static func pdfData(_ meeting: Meeting) throws -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let body = CGRect(x: 48, y: 55, width: 499, height: 725)
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 21, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)
        ]
        let text = NSMutableAttributedString(string: meeting.title + "\n\n", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): titleFont
        ])
        text.append(NSAttributedString(string: AppFormatters.date.string(from: meeting.createdAt) + " · " + AppFormatters.duration(meeting.durationSeconds) + "\n\n", attributes: attributes))
        if let summary = meeting.summary, !summary.isEmpty, !summary.contains("Resumo não gerado:") {
            text.append(NSAttributedString(string: "Resumo\n\n" + summary + "\n\n", attributes: attributes))
        }
        text.append(NSAttributedString(string: "Transcrição\n\n" + transcriptText(meeting), attributes: attributes))
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { throw ExportError.pdfFailed }
        var mediaBox = page
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, [kCGPDFContextTitle: meeting.title] as CFDictionary) else { throw ExportError.pdfFailed }
        var offset = 0
        var pageNumber = 1
        while offset < text.length {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), CGPath(rect: body, transform: nil), nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { context.endPDFPage(); context.closePDF(); throw ExportError.pdfFailed }
            let footer = NSAttributedString(string: "Meeting Scribe · @junowoz                                      \(pageNumber)", attributes: attributes)
            context.textPosition = CGPoint(x: 48, y: 30)
            CTLineDraw(CTLineCreateWithAttributedString(footer), context)
            context.endPDFPage()
            offset += visible.length
            pageNumber += 1
        }
        context.closePDF()
        return output as Data
    }

    enum ExportError: LocalizedError {
        case noTranscript, noTimestamps, pdfFailed
        var errorDescription: String? {
            switch self {
            case .noTranscript: "A transcrição ainda não está disponível. Aguarde a conclusão antes de exportar."
            case .noTimestamps: "Esta transcrição não tem marcações de tempo. Exporte como TXT, Markdown ou PDF."
            case .pdfFailed: "Não foi possível criar o PDF. Tente exportar como TXT ou Markdown."
            }
        }
    }

    static func saveAll(meeting: Meeting, rawJSON: Data?, srt: String?, vtt: String?) throws {
        let directory = URL(filePath: meeting.outputDirectory, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let transcript = meeting.utterances.isEmpty ? meeting.text : meeting.utterances.map {
            "[\(AppFormatters.timestamp($0.start)) - \(AppFormatters.timestamp($0.end))] \($0.speaker): \($0.text)"
        }.joined(separator: "\n\n")
        try (transcript + "\n").write(to: directory.appending(path: "transcript-speakers.txt"), atomically: true, encoding: .utf8)
        if let summary = meeting.summary { try (summary + "\n").write(to: directory.appending(path: "summary.md"), atomically: true, encoding: .utf8) }
        if let rawJSON { try rawJSON.write(to: directory.appending(path: "transcript.json"), options: .atomic) }
        if let srt { try srt.write(to: directory.appending(path: "transcript.srt"), atomically: true, encoding: .utf8) }
        if let vtt { try vtt.write(to: directory.appending(path: "transcript.vtt"), atomically: true, encoding: .utf8) }
        let model = meeting.speechModelUsed ?? "—"
        let language = meeting.languageCode ?? "—"
        let markdown = "# \(meeting.title)\n\n- Data: \(AppFormatters.date.string(from: meeting.createdAt))\n- Duração: \(AppFormatters.duration(meeting.durationSeconds))\n- Modelo: \(model)\n- Idioma: \(language)\n\n## Transcrição\n\n" + transcript + "\n"
        try markdown.write(to: directory.appending(path: "transcript.md"), atomically: true, encoding: .utf8)
        let csv = "inicio_ms,fim_ms,speaker,confianca,texto\n" + meeting.words.map {
            let escaped = $0.text.replacingOccurrences(of: "\"", with: "\"\"")
            let speaker = $0.speaker ?? ""
            return "\($0.start),\($0.end),\(speaker),\($0.confidence),\"\(escaped)\""
        }.joined(separator: "\n")
        try (csv + "\n").write(to: directory.appending(path: "words-confidence.csv"), atomically: true, encoding: .utf8)
        if !meeting.utterances.isEmpty {
            try speakerSRT(meeting.utterances).write(to: directory.appending(path: "transcript-speakers.srt"), atomically: true, encoding: .utf8)
            try speakerVTT(meeting.utterances).write(to: directory.appending(path: "transcript-speakers.vtt"), atomically: true, encoding: .utf8)
        }
    }

    static func speakerSRT(_ utterances: [TranscriptUtterance]) -> String {
        utterances.enumerated().map { index, value in
            "\(index + 1)\n\(AppFormatters.timestamp(value.start, srt: true)) --> \(AppFormatters.timestamp(value.end, srt: true))\n\(value.speaker.isEmpty ? "" : value.speaker + ": ")\(value.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    private static func escapeVTT(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func speakerVTT(_ utterances: [TranscriptUtterance]) -> String {
        "WEBVTT\n\n" + utterances.map { value in
            "\(AppFormatters.timestamp(value.start)) --> \(AppFormatters.timestamp(value.end))\n\(value.speaker.isEmpty ? "" : "<v " + escapeVTT(value.speaker) + ">")\(escapeVTT(value.text))"
        }.joined(separator: "\n\n") + "\n"
    }
}
