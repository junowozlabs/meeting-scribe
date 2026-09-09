import Foundation

/// Copies a legacy library without replacing an existing library or modifying the original.
enum LegacyMigration {
    static let legacyBundleIdentifier = "com.junowoz.MeetingScribe"

    @discardableResult
    static func migrate(from source: URL, to destination: URL) throws -> Bool {
        let manager = FileManager.default
        let indexName = "meetings.json"
        guard !manager.fileExists(atPath: destination.appending(path: indexName).path) else { return false }
        let sourceIndex = source.appending(path: indexName)
        guard manager.fileExists(atPath: sourceIndex.path) else { throw MigrationError.missingHistory }
        var meetings = try JSONDecoder().decode([Meeting].self, from: Data(contentsOf: sourceIndex))
        let staging = destination.deletingLastPathComponent().appending(path: ".meeting-scribe-migration-\(UUID().uuidString)")
        try manager.createDirectory(at: staging.appending(path: "Meetings"), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        for index in meetings.indices {
            let original = meetings[index]
            if [.preparing, .uploading, .transcribing, .summarizing].contains(original.status) {
                meetings[index].markProcessingCancelled()
            }
            let folderName = original.id.uuidString
            let originalFolder = source.appending(path: "Meetings").appending(path: URL(filePath: original.outputDirectory).lastPathComponent)
            let stagedFolder = staging.appending(path: "Meetings").appending(path: folderName)
            let finalFolder = destination.appending(path: "Meetings").appending(path: folderName)
            if manager.fileExists(atPath: originalFolder.path) {
                try manager.copyItem(at: originalFolder, to: stagedFolder)
            } else {
                try manager.createDirectory(at: stagedFolder, withIntermediateDirectories: true)
            }
            meetings[index].outputDirectory = finalFolder.path
            let sourceName = URL(filePath: original.sourcePath).lastPathComponent
            if manager.fileExists(atPath: stagedFolder.appending(path: sourceName).path) {
                meetings[index].sourcePath = finalFolder.appending(path: sourceName).path
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meetings).write(to: staging.appending(path: indexName), options: .atomic)
        if manager.fileExists(atPath: destination.path) {
            let contents = try manager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            guard contents.isEmpty else { throw MigrationError.destinationNotEmpty }
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: staging, to: destination)
        return true
    }

    enum MigrationError: LocalizedError {
        case missingHistory, destinationNotEmpty
        var errorDescription: String? {
            switch self {
            case .missingHistory: "Selecione a pasta MeetingScribe que contém meetings.json e a pasta Meetings."
            case .destinationNotEmpty: "A pasta de destino já contém arquivos. A migração foi interrompida para preservar seus dados."
            }
        }
    }
}
