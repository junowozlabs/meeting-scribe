import Foundation

enum ExportService {
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
            "\(index + 1)\n\(AppFormatters.timestamp(value.start, srt: true)) --> \(AppFormatters.timestamp(value.end, srt: true))\n\(value.speaker): \(value.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    static func speakerVTT(_ utterances: [TranscriptUtterance]) -> String {
        "WEBVTT\n\n" + utterances.map { value in
            "\(AppFormatters.timestamp(value.start)) --> \(AppFormatters.timestamp(value.end))\n<v \(value.speaker)>\(value.text)"
        }.joined(separator: "\n\n") + "\n"
    }
}
