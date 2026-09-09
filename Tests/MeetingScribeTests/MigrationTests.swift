import Foundation
import Testing
@testable import MeetingScribe

@Test func migratesLegacyLibraryAndRebasesMediaPaths() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "legacy")
    let destination = root.appending(path: "current")
    let folder = source.appending(path: "Meetings/original")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let audio = folder.appending(path: "source.mp3")
    try Data("audio fixture".utf8).write(to: audio)
    var meeting = Meeting(title: "Histórico", sourceURL: audio, outputDirectory: folder)
    meeting.text = "Texto preservado."
    let originalIndex = try JSONEncoder().encode([meeting])
    try originalIndex.write(to: source.appending(path: "meetings.json"))
    #expect(try LegacyMigration.migrate(from: source, to: destination))
    let migrated = try JSONDecoder().decode([Meeting].self, from: Data(contentsOf: destination.appending(path: "meetings.json")))
    #expect(migrated.first?.id == meeting.id)
    #expect(migrated.first?.text == meeting.text)
    let restored = try #require(migrated.first)
    #expect(restored.sourcePath.hasPrefix(destination.path))
    #expect(FileManager.default.fileExists(atPath: restored.sourcePath))
    #expect(try Data(contentsOf: source.appending(path: "meetings.json")) == originalIndex)
    #expect(FileManager.default.fileExists(atPath: audio.path))
    #expect(try !LegacyMigration.migrate(from: source, to: destination))
}

@Test func migrationDoesNotOverwriteExistingFiles() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "legacy")
    let destination = root.appending(path: "current")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: source.appending(path: "meetings.json"))
    let existing = destination.appending(path: "keep.txt")
    try Data("keep".utf8).write(to: existing)
    #expect(throws: LegacyMigration.MigrationError.self) {
        try LegacyMigration.migrate(from: source, to: destination)
    }
    #expect(try String(contentsOf: existing, encoding: .utf8) == "keep")
    #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "meetings.json").path))
}


@Test func migrationNormalizesInterruptedWorkAndPreservesRemoteIDs() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "legacy")
    let destination = root.appending(path: "current")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let statuses: [MeetingStatus] = [.preparing, .uploading, .transcribing, .summarizing]
    let originals = statuses.map { status in
        var meeting = Meeting(title: status.rawValue, sourceURL: source.appending(path: "audio.mp3"), outputDirectory: source.appending(path: "Meetings/old"))
        meeting.status = status
        if status == .transcribing || status == .summarizing { meeting.transcriptID = "remote-\(status.rawValue)" }
        if status == .summarizing { meeting.text = "Texto salvo." }
        return meeting
    }
    try JSONEncoder().encode(originals).write(to: source.appending(path: "meetings.json"))
    #expect(try LegacyMigration.migrate(from: source, to: destination))
    let migrated = try JSONDecoder().decode([Meeting].self, from: Data(contentsOf: destination.appending(path: "meetings.json")))
    #expect(migrated.map(\.status) == [.failed, .failed, .failed, .completed])
    #expect(migrated.map(\.transcriptID) == originals.map(\.transcriptID))
    #expect(migrated[3].text == "Texto salvo.")
    #expect(migrated[3].summaryError != nil)
    #expect(migrated[2].errorMessage?.contains("retomado") == true)
}
