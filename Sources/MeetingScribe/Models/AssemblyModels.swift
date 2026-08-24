import Foundation

struct AssemblyTranscriptResponse: Codable {
    let id: String
    let status: String
    let text: String?
    let error: String?
    let audioDuration: Double?
    let languageCode: String?
    let speechModelUsed: String?
    let speakerLabels: Bool?
    let utterances: [TranscriptUtterance]?
    let words: [TranscriptWord]?

    enum CodingKeys: String, CodingKey {
        case id, status, text, error, utterances, words
        case audioDuration = "audio_duration"
        case languageCode = "language_code"
        case speechModelUsed = "speech_model_used"
        case speakerLabels = "speaker_labels"
    }
}

struct UploadResponse: Codable { let uploadURL: String; enum CodingKeys: String, CodingKey { case uploadURL = "upload_url" } }
struct SubmitResponse: Codable { let id: String }
struct LLMResponse: Codable {
    struct Choice: Codable { struct Message: Codable { let content: String }; let message: Message }
    let choices: [Choice]
}

struct CompletedTranscript: Sendable {
    let result: AssemblyTranscriptResponse
    let rawData: Data
}

enum JSONValue: Encodable {
    case string(String), bool(Bool), int(Int), double(Double), array([JSONValue]), object([String: JSONValue])
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
