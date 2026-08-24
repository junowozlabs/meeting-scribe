import AppKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var selection: UUID?
    @Published var settings: TranscriptionSettings
    @Published var apiKey: String
    @Published var isRecording = false
    @Published var recordingElapsed: TimeInterval = 0
    @Published var isBusy = false
    @Published var activityText = ""
    @Published var alertMessage: String?

    private let recordingService = RecordingService()
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    private var activeTask: Task<Void, Never>?
    private let fileManager = FileManager.default

    init() {
        apiKey = KeychainStore.loadAPIKey()
        if let data = UserDefaults.standard.data(forKey: "transcription-settings"),
           let value = try? JSONDecoder().decode(TranscriptionSettings.self, from: data) { settings = value }
        else { settings = TranscriptionSettings() }
        loadMeetings()
        selection = meetings.first?.id
        for meeting in meetings where [.preparing, .uploading].contains(meeting.status) {
            update(meeting.id) { $0.status = .failed; $0.errorMessage = "O app foi fechado antes de receber um ID da AssemblyAI. Tente novamente." }
        }
        if !apiKey.isEmpty, let pending = meetings.first(where: { $0.transcriptID != nil && [.transcribing, .summarizing].contains($0.status) }) {
            Task { await resumeTranscript(pending) }
        }
        recordingService.onCaptureError = { [weak self] error in
            Task { @MainActor in self?.handleCaptureError(error) }
        }
    }

    var selectedMeeting: Meeting? { meetings.first { $0.id == selection } }
    var meetingsRoot: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "MeetingScribe/Meetings", directoryHint: .isDirectory)
    }

    func savePreferences() {
        do {
            try KeychainStore.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            UserDefaults.standard.set(try JSONEncoder().encode(settings), forKey: "transcription-settings")
        } catch { alertMessage = error.localizedDescription }
    }

    func validateAPIKey() {
        guard !apiKey.isEmpty else { alertMessage = "Cole sua API key da AssemblyAI primeiro."; return }
        isBusy = true; activityText = "Validando chave…"
        activeTask = Task {
            defer { isBusy = false; activityText = "" }
            do {
                try await AssemblyAIClient(apiKey: apiKey, region: settings.region).validateKey()
                alertMessage = "Chave válida. Conexão com a AssemblyAI concluída."
            } catch { alertMessage = error.localizedDescription }
        }
    }

    func importMedia(_ url: URL) {
        activeTask?.cancel()
        activeTask = Task { await createAndTranscribe(sourceURL: url, suggestedTitle: url.deletingPathExtension().lastPathComponent) }
    }

    func startRecording(includeMicrophone: Bool, recordScreen: Bool) {
        guard !isRecording, !isBusy else { return }
        let title = "Reunião \(Date().formatted(date: .abbreviated, time: .shortened))"
        let directory = makeMeetingDirectory(title: title)
        isBusy = true; activityText = "Solicitando permissões…"
        activeTask = Task {
            do {
                try await recordingService.start(in: directory, includeMicrophone: includeMicrophone, recordScreen: recordScreen)
                try Task.checkCancellation()
                isRecording = true; isBusy = false; activityText = ""
                recordingStartedAt = Date(); recordingElapsed = 0
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.recordingElapsed = Date().timeIntervalSince(self?.recordingStartedAt ?? Date()) }
                }
            } catch is CancellationError {
                await recordingService.cancel(); isBusy = false; activityText = ""
            } catch { isBusy = false; activityText = ""; alertMessage = error.localizedDescription }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false; recordingTimer?.invalidate(); recordingTimer = nil
        isBusy = true; activityText = "Finalizando e mixando áudio…"
        activeTask = Task {
            do {
                let result = try await recordingService.stop()
                try Task.checkCancellation()
                isBusy = false; activityText = ""
                await createAndTranscribe(sourceURL: result.audioURL, suggestedTitle: "Reunião \(Date().formatted(date: .abbreviated, time: .shortened))", existingDirectory: result.audioURL.deletingLastPathComponent(), duration: result.duration)
            } catch is CancellationError {
                isBusy = false; activityText = ""
            } catch { isBusy = false; activityText = ""; alertMessage = error.localizedDescription }
        }
    }

    func cancelActiveWork() {
        activeTask?.cancel(); activeTask = nil
        if isRecording {
            Task { await recordingService.cancel() }
            isRecording = false; recordingTimer?.invalidate(); recordingTimer = nil
        }
        if let pending = meetings.first(where: { [.preparing, .uploading, .transcribing, .summarizing].contains($0.status) }) {
            update(pending.id) { $0.status = .failed; $0.errorMessage = $0.transcriptID == nil ? "Processamento cancelado." : "Processamento pausado. O ID remoto foi preservado e pode ser retomado sem criar cobrança duplicada." }
        }
        isBusy = false; activityText = ""
    }

    func retry(_ meeting: Meeting) {
        if meeting.transcriptID != nil { activeTask = Task { await resumeTranscript(meeting) } }
        else { importMedia(URL(filePath: meeting.sourcePath)) }
    }

    func rename(_ meeting: Meeting, title: String) {
        update(meeting.id) { $0.title = title }
    }

    func reveal(_ meeting: Meeting) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: meeting.outputDirectory)])
    }

    func remove(_ meeting: Meeting, deleteFiles: Bool) {
        if deleteFiles { try? fileManager.trashItem(at: URL(filePath: meeting.outputDirectory), resultingItemURL: nil) }
        meetings.removeAll { $0.id == meeting.id }
        selection = meetings.first?.id
        persistMeetings()
    }

    private func createAndTranscribe(sourceURL: URL, suggestedTitle: String, existingDirectory: URL? = nil, duration: Double? = nil) async {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Adicione sua API key da AssemblyAI em Ajustes antes de transcrever."
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            return
        }
        let directory = existingDirectory ?? makeMeetingDirectory(title: suggestedTitle)
        var createdMeetingID: UUID?
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let localSource: URL
            if sourceURL.deletingLastPathComponent() == directory { localSource = sourceURL }
            else {
                let destination = directory.appending(path: "source.\(sourceURL.pathExtension.isEmpty ? "media" : sourceURL.pathExtension)")
                try? fileManager.removeItem(at: destination)
                try fileManager.copyItem(at: sourceURL, to: destination)
                localSource = destination
            }
            let measuredDuration: Double
            if let duration { measuredDuration = duration }
            else { measuredDuration = await MediaProcessor.duration(of: localSource) }
            var meeting = Meeting(title: suggestedTitle, sourceURL: localSource, outputDirectory: directory, durationSeconds: measuredDuration)
            createdMeetingID = meeting.id
            meeting.status = .preparing; meeting.progress = 0.05
            meetings.insert(meeting, at: 0); selection = meeting.id; persistMeetings()
            isBusy = true; activityText = "Preparando mídia…"

            let preparedURL: URL
            if localSource.lastPathComponent == "meeting-audio.m4a" { preparedURL = localSource }
            else { preparedURL = try await MediaProcessor.prepareAudio(from: localSource, in: directory) }
            try Task.checkCancellation()
            update(meeting.id) { $0.status = .uploading; $0.progress = 0.2 }
            activityText = "Enviando para AssemblyAI…"
            let client = AssemblyAIClient(apiKey: apiKey, region: settings.region)
            let uploadURL = try await client.upload(fileURL: preparedURL)
            try Task.checkCancellation()
            let transcriptID = try await client.submit(audioURL: uploadURL, settings: settings)
            update(meeting.id) { $0.transcriptID = transcriptID; $0.status = .transcribing; $0.progress = 0.45 }
            activityText = "Transcrevendo com \(settings.model.title)…"
            let completed = try await client.waitForTranscript(id: transcriptID) { [weak self] status in
                await MainActor.run { self?.activityText = status == "queued" ? "Na fila da AssemblyAI…" : "Transcrevendo…" }
            }
            let result = completed.result
            update(meeting.id) {
                $0.durationSeconds = result.audioDuration ?? measuredDuration
                $0.text = result.text ?? ""
                $0.utterances = result.utterances ?? []
                $0.words = result.words ?? []
                $0.speechModelUsed = result.speechModelUsed
                $0.languageCode = result.languageCode
                $0.progress = 0.82
            }
            var summary: String?
            if settings.generateSummary {
                update(meeting.id) { $0.status = .summarizing }
                activityText = "Gerando notas da reunião…"
                do { summary = try await client.summary(transcriptText: result.text ?? "") }
                catch { summary = "_Resumo não gerado: \(error.localizedDescription)_" }
                update(meeting.id) { $0.summary = summary }
            }
            activityText = "Exportando arquivos…"
            async let srt = try? client.subtitle(id: transcriptID, format: "srt")
            async let vtt = try? client.subtitle(id: transcriptID, format: "vtt")
            let subtitleValues = await (srt, vtt)
            guard let finalMeeting = meetings.first(where: { $0.id == meeting.id }) else { return }
            try ExportService.saveAll(meeting: finalMeeting, rawJSON: completed.rawData, srt: subtitleValues.0, vtt: subtitleValues.1)
            update(meeting.id) { $0.status = .completed; $0.progress = 1 }
            if settings.deleteRemoteAfterSave { try await client.deleteTranscript(id: transcriptID) }
            isBusy = false; activityText = ""
        } catch is CancellationError {
            isBusy = false; activityText = ""
        } catch {
            if let id = createdMeetingID { update(id) { $0.status = .failed; $0.errorMessage = error.localizedDescription } }
            isBusy = false; activityText = ""; alertMessage = error.localizedDescription
        }
    }

    private func makeMeetingDirectory(title: String) -> URL {
        let safe = title.replacingOccurrences(of: "[^a-zA-Z0-9À-ÿ_-]+", with: "-", options: .regularExpression)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return meetingsRoot.appending(path: "\(stamp)-\(safe)", directoryHint: .isDirectory)
    }

    private func handleCaptureError(_ error: Error) {
        guard isRecording else { return }
        isRecording = false; recordingTimer?.invalidate(); recordingTimer = nil
        isBusy = false; activityText = ""; alertMessage = "A gravação foi interrompida pelo macOS: \(error.localizedDescription)"
        Task { await recordingService.cancel() }
    }

    private func resumeTranscript(_ meeting: Meeting) async {
        guard let transcriptID = meeting.transcriptID, !apiKey.isEmpty else { return }
        isBusy = true; activityText = "Retomando transcrição existente…"
        update(meeting.id) { $0.status = .transcribing; $0.errorMessage = nil }
        do {
            let client = AssemblyAIClient(apiKey: apiKey, region: settings.region)
            let completed = try await client.waitForTranscript(id: transcriptID) { [weak self] status in
                await MainActor.run { self?.activityText = status == "queued" ? "Na fila da AssemblyAI…" : "Transcrevendo…" }
            }
            let result = completed.result
            update(meeting.id) {
                $0.durationSeconds = result.audioDuration ?? $0.durationSeconds
                $0.text = result.text ?? ""
                $0.utterances = result.utterances ?? []
                $0.words = result.words ?? []
                $0.speechModelUsed = result.speechModelUsed
                $0.languageCode = result.languageCode
                $0.progress = 0.82
            }
            if settings.generateSummary {
                update(meeting.id) { $0.status = .summarizing }
                activityText = "Gerando notas da reunião…"
                do { let value = try await client.summary(transcriptText: result.text ?? ""); update(meeting.id) { $0.summary = value } }
                catch { update(meeting.id) { $0.summary = "_Resumo não gerado: \(error.localizedDescription)_" } }
            }
            async let srt = try? client.subtitle(id: transcriptID, format: "srt")
            async let vtt = try? client.subtitle(id: transcriptID, format: "vtt")
            let subtitles = await (srt, vtt)
            if let final = meetings.first(where: { $0.id == meeting.id }) {
                try ExportService.saveAll(meeting: final, rawJSON: completed.rawData, srt: subtitles.0, vtt: subtitles.1)
            }
            update(meeting.id) { $0.status = .completed; $0.progress = 1 }
            if settings.deleteRemoteAfterSave { try await client.deleteTranscript(id: transcriptID) }
            isBusy = false; activityText = ""
        } catch is CancellationError {
            isBusy = false; activityText = ""
        } catch {
            update(meeting.id) { $0.status = .failed; $0.errorMessage = error.localizedDescription }
            isBusy = false; activityText = ""; alertMessage = error.localizedDescription
        }
    }
    private func update(_ id: UUID, change: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        change(&meetings[index]); persistMeetings()
    }
    private var indexURL: URL { meetingsRoot.deletingLastPathComponent().appending(path: "meetings.json") }
    private func loadMeetings() {
        guard let data = try? Data(contentsOf: indexURL), let value = try? JSONDecoder().decode([Meeting].self, from: data) else { return }
        meetings = value
    }
    private func persistMeetings() {
        do {
            try fileManager.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            // Keep backward-compatible decoding by storing dates in the default format for now.
            encoder.dateEncodingStrategy = .deferredToDate
            try encoder.encode(meetings).write(to: indexURL, options: .atomic)
        } catch { alertMessage = "Não foi possível salvar o histórico: \(error.localizedDescription)" }
    }
}
