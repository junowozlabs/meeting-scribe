import Foundation

enum MeetingStatus: String, Codable {
    case ready = "Pronta"
    case preparing = "Preparando mídia"
    case uploading = "Enviando"
    case transcribing = "Transcrevendo"
    case summarizing = "Gerando resumo"
    case completed = "Concluída"
    case failed = "Falhou"
}

struct TranscriptWord: Codable, Hashable, Identifiable {
    var id: String { "\(start)-\(end)-\(text)" }
    let text: String
    let start: Int
    let end: Int
    let confidence: Double
    let speaker: String?
}

struct TranscriptUtterance: Codable, Hashable, Identifiable {
    var id: String { "\(start)-\(end)-\(speaker)" }
    let speaker: String
    let text: String
    let start: Int
    let end: Int
    let confidence: Double?
    let words: [TranscriptWord]?
}

struct Meeting: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var durationSeconds: Double
    var sourcePath: String
    var outputDirectory: String
    var transcriptID: String?
    var speechModelUsed: String?
    var languageCode: String?
    var status: MeetingStatus
    var progress: Double
    var text: String
    var summary: String?
    var summaryError: String?
    var utterances: [TranscriptUtterance]
    var words: [TranscriptWord]
    var errorMessage: String?

    mutating func markProcessingCancelled() {
        if status == .summarizing, !text.isEmpty {
            status = .completed
            progress = 1
            errorMessage = nil
            summaryError = "Resumo cancelado. Sua transcrição está salva. Você pode gerar o resumo novamente."
        } else {
            status = .failed
            errorMessage = transcriptID == nil
                ? "Processamento cancelado. Tente novamente quando quiser."
                : "Processamento pausado. O ID remoto foi preservado e pode ser retomado sem criar cobrança duplicada."
        }
    }

    init(title: String, sourceURL: URL, outputDirectory: URL, durationSeconds: Double = 0) {
        id = UUID()
        self.title = title
        createdAt = Date()
        self.durationSeconds = durationSeconds
        sourcePath = sourceURL.path
        self.outputDirectory = outputDirectory.path
        status = .ready
        progress = 0
        text = ""
        utterances = []
        words = []
    }
}
