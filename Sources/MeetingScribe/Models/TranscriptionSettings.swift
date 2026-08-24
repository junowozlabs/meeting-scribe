import Foundation

enum AssemblyRegion: String, Codable, CaseIterable, Identifiable {
    case us = "US"
    case eu = "EU"

    var id: String { rawValue }
    var apiBaseURL: URL {
        URL(string: self == .us ? "https://api.assemblyai.com" : "https://api.eu.assemblyai.com")!
    }
    var llmBaseURL: URL {
        URL(string: self == .us ? "https://llm-gateway.assemblyai.com" : "https://llm-gateway.eu.assemblyai.com")!
    }
}

enum SpeechModelChoice: String, Codable, CaseIterable, Identifiable {
    case bestWithFallback
    case universal35Pro
    case universal2

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bestWithFallback: "Melhor disponível + fallback"
        case .universal35Pro: "Universal-3.5 Pro"
        case .universal2: "Universal-2"
        }
    }
    var modelIDs: [String] {
        switch self {
        case .bestWithFallback: ["universal-3-5-pro", "universal-2"]
        case .universal35Pro: ["universal-3-5-pro"]
        case .universal2: ["universal-2"]
        }
    }
}

enum AudioTagsChoice: String, Codable, CaseIterable, Identifiable {
    case removeAll = "all"
    case keepEvents = "speaker"
    var id: String { rawValue }
    var title: String { self == .removeAll ? "Texto limpo" : "Manter eventos de áudio" }
}

enum PIISubstitution: String, Codable, CaseIterable, Identifiable {
    case entityName = "entity_name"
    case hash
    var id: String { rawValue }
    var title: String { self == .entityName ? "Nome da entidade" : "Hash" }
}

struct TranscriptionSettings: Codable, Equatable {
    var region: AssemblyRegion = .us
    var model: SpeechModelChoice = .bestWithFallback
    var languageCode = ""
    var speakerLabels = true
    var expectedSpeakers: Int?
    var minimumSpeakers: Int?
    var maximumSpeakers: Int?
    var speakerNames = ""
    var multichannel = false
    var prompt = ""
    var keyterms = ""
    var customSpelling = ""
    var audioTags: AudioTagsChoice = .removeAll
    var punctuate = true
    var formatText = true
    var disfluencies = false
    var filterProfanity = false
    var redactPII = false
    var piiSubstitution: PIISubstitution = .entityName
    var entityDetection = false
    var sentimentAnalysis = false
    var autoHighlights = false
    var contentSafety = false
    var iabCategories = false
    var medicalMode = false
    var audioStartSeconds: Double?
    var audioEndSeconds: Double?
    var generateSummary = true
    var deleteRemoteAfterSave = false

    var parsedSpeakerNames: [String] {
        speakerNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    var parsedKeyterms: [String] {
        keyterms.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    var parsedCustomSpelling: [(from: [String], to: String)] {
        customSpelling.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            let sources = parts[0].split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !sources.isEmpty, parts[1].split(separator: " ").count == 1 else { return nil }
            return (sources, parts[1])
        }
    }
}
