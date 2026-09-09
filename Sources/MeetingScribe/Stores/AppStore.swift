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
    @Published private(set) var queuedCount = 0
    private var pendingJobs: [@MainActor () async -> Void] = []
    private var activeMeetingID: UUID?

    private let recordingService = RecordingService()
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    private var activeTask: Task<Void, Never>?
    private let fileManager = FileManager.default
    private let storageDirectory: URL?
    private let trashItem: (URL) throws -> Void
    private var historyIsReadable = true

    init(storageDirectory: URL? = nil, apiKeyOverride: String? = nil, resumePending: Bool = true,
         trashItem: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.trashItem = trashItem
        self.storageDirectory = storageDirectory
        apiKey = apiKeyOverride ?? KeychainStore.loadAPIKey()
        if storageDirectory == nil,
           UserDefaults.standard.data(forKey: "transcription-settings") == nil,
           let legacy = UserDefaults(suiteName: LegacyMigration.legacyBundleIdentifier)?.data(forKey: "transcription-settings"),
           (try? JSONDecoder().decode(TranscriptionSettings.self, from: legacy)) != nil {
            UserDefaults.standard.set(legacy, forKey: "transcription-settings")
        }
        if let data = UserDefaults.standard.data(forKey: "transcription-settings"),
           let value = try? JSONDecoder().decode(TranscriptionSettings.self, from: data) { settings = value }
        else { settings = TranscriptionSettings() }
        loadMeetings()
        selection = meetings.first?.id
        for meeting in meetings where [.preparing, .uploading].contains(meeting.status) {
            update(meeting.id) { $0.status = .failed; $0.errorMessage = "O app foi fechado antes de receber um ID da AssemblyAI. Tente novamente." }
        }
        if resumePending, hasAPIKey {
            for pending in meetings where [.transcribing, .summarizing].contains(pending.status) {
                if pending.status == .summarizing, !pending.text.isEmpty {
                    retrySummary(pending)
                } else if pending.transcriptID != nil {
                    enqueue { [weak self] in await self?.resumeTranscript(pending) }
                }
            }
        }
        recordingService.onCaptureError = { [weak self] error in
            Task { @MainActor in self?.handleCaptureError(error) }
        }
    }

    var selectedMeeting: Meeting? { meetings.first { $0.id == selection } }
    var meetingsRoot: URL {
        if let storageDirectory { return storageDirectory.appending(path: "Meetings", directoryHint: .isDirectory) }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "MeetingScribe/Meetings", directoryHint: .isDirectory)
    }

    func importLegacyHistory() {
        guard !isBusy, !isRecording else { return }
        guard meetings.isEmpty else {
            alertMessage = "Já existe um histórico neste app. A biblioteca anterior foi preservada e não será sobrescrita."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Importar histórico anterior"
        panel.message = "Selecione a pasta MeetingScribe que contém meetings.json e a pasta Meetings."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Importar histórico"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try LegacyMigration.migrate(from: source, to: meetingsRoot.deletingLastPathComponent())
            guard imported else {
                alertMessage = "Já existe um histórico no destino. Nenhum arquivo foi alterado."
                return
            }
            historyIsReadable = true
            loadMeetings()
            selection = meetings.first?.id
            alertMessage = "Histórico importado. Os arquivos originais foram preservados."
        } catch {
            alertMessage = "Não foi possível importar o histórico: \(error.localizedDescription)"
        }
    }

    func savePreferences() {
        do {
            apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try KeychainStore.saveAPIKey(apiKey)
            UserDefaults.standard.set(try JSONEncoder().encode(settings), forKey: "transcription-settings")
        } catch { alertMessage = error.localizedDescription }
    }

    func validateAPIKey() {
        guard requireAPIKey(), !isBusy, !isRecording else { return }
        isBusy = true; activityText = "Validando chave…"
        activeTask = Task {
            defer { isBusy = false; activityText = ""; activeTask = nil; startNextJob() }
            do {
                try await AssemblyAIClient(apiKey: apiKey, region: settings.region).validateKey()
                alertMessage = "Chave válida. Conexão com a AssemblyAI concluída."
            } catch { alertMessage = error.localizedDescription }
        }
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    @discardableResult
    private func requireAPIKey() -> Bool {
        guard hasAPIKey else {
            alertMessage = "Adicione sua API key da AssemblyAI em Ajustes antes de transcrever."
            return false
        }
        return true
    }

    func importMedia(_ url: URL) { importMedia([url]) }

    func importMedia(_ urls: [URL]) {
        guard requireAPIKey() else { return }
        for url in urls {
            do { try MediaProcessor.validateImport(url) }
            catch { alertMessage = error.localizedDescription; continue }
            enqueue { [weak self] in
                await self?.createAndTranscribe(sourceURL: url, suggestedTitle: url.deletingPathExtension().lastPathComponent)
            }
        }
    }

    func enqueue(_ job: @escaping @MainActor () async -> Void) {
        guard historyIsReadable else {
            alertMessage = "O histórico não pôde ser lido. O arquivo original foi preservado. Abra a pasta de dados e restaure uma cópia válida de meetings.json antes de continuar."
            return
        }
        pendingJobs.append(job)
        queuedCount = pendingJobs.count
        startNextJob()
    }

    private func startNextJob() {
        guard activeTask == nil, !isBusy, !isRecording, !pendingJobs.isEmpty else { return }
        let job = pendingJobs.removeFirst()
        queuedCount = pendingJobs.count
        isBusy = true
        activeTask = Task {
            await job()
            activeMeetingID = nil
            isBusy = false
            activityText = ""
            activeTask = nil
            startNextJob()
        }
    }

    func startRecording(includeMicrophone: Bool, recordScreen: Bool) {
        guard !isRecording, !isBusy, historyIsReadable, requireAPIKey() else { return }
        let title = "Reunião \(Date().formatted(date: .abbreviated, time: .shortened))"
        let directory = makeMeetingDirectory(title: title)
        isBusy = true; activityText = "Solicitando permissões…"
        activeTask = Task {
            defer { activeMeetingID = nil; activeTask = nil; startNextJob() }
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
            defer { activeMeetingID = nil; activeTask = nil; startNextJob() }
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
        pendingJobs.removeAll(); queuedCount = 0
        activeTask?.cancel()
        if isRecording {
            isRecording = false; recordingTimer?.invalidate(); recordingTimer = nil
            activeTask = Task {
                await recordingService.cancel()
                isBusy = false; activityText = ""; activeTask = nil
                startNextJob()
            }
        }
        if let pending = meetings.first(where: { $0.id == activeMeetingID }) {
            update(pending.id) { $0.markProcessingCancelled() }
        }
        isBusy = activeTask != nil; activityText = isBusy ? "Cancelando…" : ""
    }

    func retry(_ meeting: Meeting) {
        guard requireAPIKey() else { return }
        if meeting.transcriptID != nil { enqueue { [weak self] in await self?.resumeTranscript(meeting) } }
        else { importMedia(URL(filePath: meeting.sourcePath)) }
    }

    func rename(_ meeting: Meeting, title: String) {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        update(meeting.id) { $0.title = value }
    }

    func reveal(_ meeting: Meeting) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: meeting.outputDirectory)])
    }

    func remove(_ meeting: Meeting, deleteFiles: Bool) {
        guard activeMeetingID != meeting.id else {
            alertMessage = "Cancele o processamento antes de excluir esta transcrição."
            return
        }
        let directory = URL(filePath: meeting.outputDirectory)
        if deleteFiles, fileManager.fileExists(atPath: directory.path) {
            do { try trashItem(directory) }
            catch {
                alertMessage = "Não foi possível mover os arquivos para a Lixeira. O histórico foi preservado. Tente novamente: \(error.localizedDescription)"
                return
            }
        }
        meetings.removeAll { $0.id == meeting.id }
        if selection == meeting.id { selection = meetings.first?.id }
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
            activeMeetingID = meeting.id
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
            if settings.generateSummary {
                update(meeting.id) { $0.status = .summarizing }
                activityText = "Gerando notas da reunião…"
                do {
                    let summary = try await client.summary(transcriptText: result.text ?? "")
                    update(meeting.id) { $0.summary = summary; $0.summaryError = nil }
                } catch is CancellationError { throw CancellationError() }
                catch { update(meeting.id) { $0.summaryError = error.localizedDescription } }
            }
            activityText = "Exportando arquivos…"
            async let srt = try? client.subtitle(id: transcriptID, format: "srt")
            async let vtt = try? client.subtitle(id: transcriptID, format: "vtt")
            let subtitleValues = await (srt, vtt)
            guard let finalMeeting = meetings.first(where: { $0.id == meeting.id }) else { return }
            try ExportService.saveAll(meeting: finalMeeting, rawJSON: completed.rawData, srt: subtitleValues.0, vtt: subtitleValues.1)
            update(meeting.id) { $0.status = .completed; $0.progress = 1 }
            if settings.deleteRemoteAfterSave {
                do { try await client.deleteTranscript(id: transcriptID) }
                catch { alertMessage = "A transcrição está salva. Não foi possível apagar a cópia na AssemblyAI: \(error.localizedDescription)" }
            }
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
        return meetingsRoot.appending(path: "\(stamp)-\(safe)-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    }

    private func handleCaptureError(_ error: Error) {
        guard isRecording else { return }
        isRecording = false; recordingTimer?.invalidate(); recordingTimer = nil
        isBusy = false; activityText = ""; alertMessage = "A gravação foi interrompida pelo macOS: \(error.localizedDescription)"
        activeTask = Task {
            await recordingService.cancel()
            activeTask = nil
            startNextJob()
        }
    }

    private func resumeTranscript(_ meeting: Meeting) async {
        guard meetings.contains(where: { $0.id == meeting.id }), let transcriptID = meeting.transcriptID, requireAPIKey() else { return }
        activeMeetingID = meeting.id
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
                do { let value = try await client.summary(transcriptText: result.text ?? ""); update(meeting.id) { $0.summary = value; $0.summaryError = nil } }
                catch is CancellationError { throw CancellationError() }
                catch { update(meeting.id) { $0.summaryError = error.localizedDescription } }
            }
            async let srt = try? client.subtitle(id: transcriptID, format: "srt")
            async let vtt = try? client.subtitle(id: transcriptID, format: "vtt")
            let subtitles = await (srt, vtt)
            if let final = meetings.first(where: { $0.id == meeting.id }) {
                try ExportService.saveAll(meeting: final, rawJSON: completed.rawData, srt: subtitles.0, vtt: subtitles.1)
            }
            update(meeting.id) { $0.status = .completed; $0.progress = 1 }
            if settings.deleteRemoteAfterSave {
                do { try await client.deleteTranscript(id: transcriptID) }
                catch { alertMessage = "A transcrição está salva. Não foi possível apagar a cópia na AssemblyAI: \(error.localizedDescription)" }
            }
            isBusy = false; activityText = ""
        } catch is CancellationError {
            isBusy = false; activityText = ""
        } catch {
            update(meeting.id) { $0.status = .failed; $0.errorMessage = error.localizedDescription }
            isBusy = false; activityText = ""; alertMessage = error.localizedDescription
        }
    }
    func retrySummary(_ meeting: Meeting) {
        guard requireAPIKey(), !meeting.text.isEmpty else { return }
        enqueue { [weak self] in
            guard let self, self.meetings.contains(where: { $0.id == meeting.id }) else { return }
            self.activeMeetingID = meeting.id
            self.activityText = "Gerando resumo…"
            self.update(meeting.id) { $0.status = .summarizing; $0.summaryError = nil }
            do {
                let client = AssemblyAIClient(apiKey: self.apiKey, region: self.settings.region)
                let summary = try await client.summary(transcriptText: meeting.text)
                try Task.checkCancellation()
                self.update(meeting.id) { $0.summary = summary; $0.status = .completed; $0.progress = 1 }
                let url = URL(filePath: meeting.outputDirectory).appending(path: "summary.md")
                try summary.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.update(meeting.id) {
                    $0.status = .completed
                    $0.summaryError = error is CancellationError ? "Resumo cancelado. Você pode tentar novamente." : error.localizedDescription
                }
            }
        }
    }

    private func update(_ id: UUID, change: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        change(&meetings[index]); persistMeetings()
    }
    private var indexURL: URL { meetingsRoot.deletingLastPathComponent().appending(path: "meetings.json") }
    private func loadMeetings() {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        let value: [Meeting]
        do {
            value = try JSONDecoder().decode([Meeting].self, from: Data(contentsOf: indexURL))
        } catch {
            historyIsReadable = false
            alertMessage = "Não foi possível ler o histórico em \(indexURL.path). O arquivo foi preservado. Restaure uma cópia válida de meetings.json e reabra o app."
            return
        }
        meetings = value.map { meeting in
            var restored = meeting
            if let summary = restored.summary, summary.hasPrefix("_Resumo não gerado:") {
                restored.summary = nil
                restored.summaryError = "O resumo anterior falhou. Tente gerar novamente ou confira o acesso ao resumo na sua conta AssemblyAI."
            }
            return restored
        }
    }
    private func persistMeetings() {
        guard historyIsReadable else { return }
        do {
            try fileManager.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            // Keep backward-compatible decoding by storing dates in the default format for now.
            encoder.dateEncodingStrategy = .deferredToDate
            try encoder.encode(meetings).write(to: indexURL, options: .atomic)
        } catch { alertMessage = "Não foi possível salvar o histórico: \(error.localizedDescription)" }
    }
}
