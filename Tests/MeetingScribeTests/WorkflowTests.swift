import Foundation
import Testing
@testable import MeetingScribe

@Test func oldHistoryDecodesWithoutSummaryError() throws {
    let meeting = Meeting(title: "Reunião", sourceURL: URL(filePath: "/tmp/audio.mp3"), outputDirectory: URL(filePath: "/tmp/meeting"))
    let data = try JSONEncoder().encode(meeting)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "summaryError")
    let restored = try JSONDecoder().decode(Meeting.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(restored.id == meeting.id)
    #expect(restored.summaryError == nil)
}

@Test func summaryFailureRemainsSeparateFromTranscript() throws {
    var meeting = Meeting(title: "Reunião", sourceURL: URL(filePath: "/tmp/audio.mp3"), outputDirectory: URL(filePath: "/tmp/meeting"))
    meeting.text = "Decidimos lançar na sexta."
    meeting.summaryError = "Sem acesso ao resumo."
    meeting.status = .completed
    let restored = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(meeting))
    #expect(restored.text == meeting.text)
    #expect(restored.summary == nil)
    #expect(restored.summaryError == meeting.summaryError)
    #expect(restored.status == .completed)
}

@Test func inaccessibleSummaryHasRecoveryWithoutRawPayload() {
    let raw = #"{"metadata":{"errors":["Your account does not have access to this LLM Gateway model"]},"request_id":"private-id"}"#
    let message = AssemblyAIClient.errorMessage(statusCode: 400, data: Data(raw.utf8))
    #expect(message.contains("A transcrição continua disponível"))
    #expect(message.contains("tente gerar o resumo novamente"))
    #expect(!message.contains("private-id"))
}

@Test func authenticationAndRateLimitsHaveRecovery() {
    #expect(AssemblyAIClient.errorMessage(statusCode: 401, data: Data()).contains("API key"))
    #expect(AssemblyAIClient.errorMessage(statusCode: 429, data: Data()).contains("Aguarde"))
    #expect(AssemblyAIClient.errorMessage(statusCode: 503, data: Data()).contains("Tente novamente"))
}

@MainActor @Test func failedTrashPreservesHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory, apiKeyOverride: "", resumePending: false,
                         trashItem: { _ in throw CocoaError(.fileWriteNoPermission) })
    let meeting = Meeting(title: "Preservar", sourceURL: directory.appending(path: "audio.mp3"), outputDirectory: directory)
    store.meetings = [meeting]
    store.selection = meeting.id
    store.remove(meeting, deleteFiles: true)
    #expect(store.meetings.count == 1)
    #expect(store.selection == meeting.id)
    #expect(store.alertMessage?.contains("histórico foi preservado") == true)
}

@MainActor @Test func renameTrimsAndRejectsBlankTitle() {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory, apiKeyOverride: "", resumePending: false)
    let meeting = Meeting(title: "Original", sourceURL: directory.appending(path: "audio.mp3"), outputDirectory: directory)
    store.meetings = [meeting]
    store.rename(meeting, title: "  \n ")
    #expect(store.meetings.first?.title == "Original")
    store.rename(meeting, title: "  Novo nome \n")
    #expect(store.meetings.first?.title == "Novo nome")
}

@MainActor @Test func queueRunsInOrderWithoutCancellingActiveJob() async {
    let store = AppStore(storageDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), apiKeyOverride: "", resumePending: false)
    var events: [Int] = []
    store.enqueue {
        events.append(1)
        await Task.yield()
        #expect(!Task.isCancelled)
        events.append(2)
    }
    store.enqueue { events.append(3) }
    #expect(store.queuedCount == 1)
    for _ in 0..<100 where store.isBusy { await Task.yield() }
    #expect(events == [1, 2, 3])
    #expect(store.queuedCount == 0)
}

@MainActor @Test func missingKeyDoesNotCreateOrQueueMeeting() {
    let store = AppStore(storageDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), apiKeyOverride: " \n", resumePending: false)
    store.importMedia([URL(filePath: "/tmp/test.mp3")])
    #expect(store.meetings.isEmpty)
    #expect(store.queuedCount == 0)
    #expect(!store.isBusy)
    #expect(store.alertMessage?.contains("API key") == true)
}

@MainActor @Test func damagedHistoryIsNeverOverwritten() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = Data("damaged but recoverable history".utf8)
    let index = directory.appending(path: "meetings.json")
    try original.write(to: index)
    let store = AppStore(storageDirectory: directory, apiKeyOverride: "", resumePending: false)
    store.enqueue {}
    #expect(!store.isBusy)
    #expect(store.queuedCount == 0)
    #expect(try Data(contentsOf: index) == original)
    #expect(store.alertMessage?.contains("preservado") == true)
}


@MainActor @Test func missingOutputDirectoryCanBeRemovedFromHistory() {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(storageDirectory: directory, apiKeyOverride: "", resumePending: false)
    let meeting = Meeting(title: "Antiga", sourceURL: directory.appending(path: "audio.mp3"), outputDirectory: directory.appending(path: "missing"))
    store.meetings = [meeting]
    store.selection = meeting.id
    store.remove(meeting, deleteFiles: true)
    #expect(store.meetings.isEmpty)
    #expect(store.selection == nil)
    #expect(store.alertMessage == nil)
}

@Test func cancelledSummaryKeepsCompletedTranscript() {
    var meeting = Meeting(title: "Reunião", sourceURL: URL(filePath: "/tmp/audio.mp3"), outputDirectory: URL(filePath: "/tmp/meeting"))
    meeting.status = .summarizing
    meeting.text = "Texto já salvo."
    meeting.transcriptID = "remote-id"
    meeting.markProcessingCancelled()
    #expect(meeting.status == .completed)
    #expect(meeting.text == "Texto já salvo.")
    #expect(meeting.transcriptID == "remote-id")
    #expect(meeting.errorMessage == nil)
    #expect(meeting.summaryError?.contains("cancelado") == true)
}

@Test func cancelledTranscriptionKeepsRemoteIDForResume() {
    var meeting = Meeting(title: "Reunião", sourceURL: URL(filePath: "/tmp/audio.mp3"), outputDirectory: URL(filePath: "/tmp/meeting"))
    meeting.status = .transcribing
    meeting.transcriptID = "remote-id"
    meeting.markProcessingCancelled()
    #expect(meeting.status == .failed)
    #expect(meeting.transcriptID == "remote-id")
    #expect(meeting.errorMessage?.contains("retomado") == true)
}
