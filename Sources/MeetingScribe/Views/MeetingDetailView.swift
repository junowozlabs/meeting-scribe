import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct MeetingDetailView: View {
    @ObservedObject var store: AppStore
    let meeting: Meeting
    @State private var tab = 0
    @State private var showRename = false
    @State private var title = ""
    @State private var confirmDelete = false
    @State private var copied = false
    @State private var showPlayer = false
    @State private var player: AVPlayer?
    @State private var query = ""
    @State private var playbackError = false
    @AppStorage("transcript-text-size") private var textSize = 16.0

    var body: some View {
        VStack(spacing: 0) {
            header
            if meeting.status == .failed, !meeting.text.isEmpty {
                HStack {
                    Label(meeting.errorMessage ?? "O texto foi preservado. Tente concluir novamente.", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("Tentar concluir") { store.retry(meeting) }.disabled(store.isBusy || store.isRecording)
                }.padding(16).background(.quaternary)
            }
            if !meeting.text.isEmpty || meeting.status == .completed {
                HStack(spacing: 16) {
                    Picker("Conteúdo", selection: $tab) {
                        Text("Transcrição").tag(0)
                        Text("Resumo").tag(1)
                        Text("Palavras").tag(2)
                    }.pickerStyle(.segmented).frame(maxWidth: 350)
                    Spacer()
                    Menu {
                        Button("Texto menor") { textSize = max(13, textSize - 1) }
                        Button("Texto maior") { textSize = min(24, textSize + 1) }
                        Button("Tamanho padrão") { textSize = 16 }
                    } label: { Label("Tamanho do texto", systemImage: "textformat.size") }
                        .menuStyle(.borderlessButton).fixedSize().help("Ajustar tamanho da leitura")
                }.padding(.horizontal, 24).padding(.vertical, 16)
                if showPlayer, let player {
                    VideoPlayer(player: player).frame(height: 160).padding(.horizontal, 24)
                        .onReceive(player.currentItem!.publisher(for: \.status)) { status in playbackError = status == .failed }
                    if playbackError {
                        HStack {
                            Text("O macOS não reproduz este formato. A transcrição continua disponível.")
                            Button("Abrir no Finder") { store.reveal(meeting) }
                        }.font(.callout).padding(.horizontal, 24)
                    }
                }
                if tab == 0 {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Buscar nesta transcrição", text: $query)
                            .textFieldStyle(.plain).accessibilityLabel("Buscar nesta transcrição")
                        if !query.isEmpty { Button("Limpar") { query = "" }.buttonStyle(.borderless) }
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 24).padding(.bottom, 8)
                    transcript
                } else if tab == 1 { summary }
                else { words }
            } else { processing }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $confirmDelete) { DeleteMeetingView(store: store, meeting: meeting) }
        .sheet(isPresented: $showRename) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Renomear transcrição").font(.title2.bold())
                TextField("Título", text: $title).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancelar") { showRename = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Salvar título") { store.rename(meeting, title: title); showRename = false }
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(28).frame(width: 460)
        }
        .onDisappear { player?.pause() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(meeting.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                HStack(spacing: 12) {
                    Text(meeting.createdAt, style: .date)
                    Label(AppFormatters.duration(meeting.durationSeconds), systemImage: "clock")
                    Label(meeting.status.rawValue, systemImage: meeting.status == .failed ? "exclamationmark.triangle" : "text.bubble")
                }.font(.callout).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(alignment: .leading, spacing: 10) { actions }
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
    }

    @ViewBuilder private var actions: some View {
        Menu {
            ForEach(ExportService.Format.allCases, id: \.self) { format in
                Button(format.title) { export(format) }
                    .disabled((format == .srt || format == .vtt) && !ExportService.hasTimedTranscript(meeting))
            }
        } label: { Label("Exportar", systemImage: "square.and.arrow.up") }
            .disabled(meeting.text.isEmpty)
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ExportService.transcriptText(meeting), forType: .string)
            copied = true
        } label: { Label(copied ? "Copiado" : "Copiar texto", systemImage: copied ? "checkmark" : "doc.on.doc") }
            .disabled(meeting.text.isEmpty)
        Button {
            if player == nil { player = AVPlayer(url: URL(filePath: meeting.sourcePath)) }
            showPlayer.toggle()
            if !showPlayer { player?.pause() }
        } label: { Label(showPlayer ? "Ocultar mídia" : "Ouvir mídia", systemImage: "play.circle") }
            .disabled(!FileManager.default.fileExists(atPath: meeting.sourcePath))
        Menu {
            Button("Renomear…") { title = meeting.title; showRename = true }
            Button("Mostrar arquivos no Finder") { store.reveal(meeting) }
        } label: { Label("Mais", systemImage: "ellipsis") }
        Button(role: .destructive) { confirmDelete = true } label: { Label("Excluir", systemImage: "trash") }
            .disabled(store.isBusy || store.isRecording)
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if meeting.utterances.isEmpty {
                    if query.isEmpty || meeting.text.localizedCaseInsensitiveContains(query) {
                        Text(meeting.text).textSelection(.enabled)
                    } else { noResults }
                } else {
                    let matches = meeting.utterances.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.speaker.localizedCaseInsensitiveContains(query) }
                    if matches.isEmpty { noResults }
                    ForEach(matches) { utterance in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Pessoa \(utterance.speaker)", systemImage: "person.crop.circle")
                                    .font(.callout.weight(.semibold))
                                Text(AppFormatters.timestamp(utterance.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Text(utterance.text).textSelection(.enabled)
                        }
                    }
                }
            }.font(.system(size: textSize)).lineSpacing(6)
                .frame(maxWidth: 740, alignment: .leading).padding(28).frame(maxWidth: .infinity)
        }
    }

    private var noResults: some View {
        ContentUnavailableView("Nenhum trecho encontrado", systemImage: "magnifyingglass", description: Text("Tente outra palavra ou limpe a busca para ver a transcrição completa."))
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = meeting.summaryError {
                    Label("A transcrição está salva. O resumo não ficou pronto.", systemImage: "exclamationmark.bubble")
                        .font(.headline)
                    Text(error).foregroundStyle(.secondary)
                    Button("Tentar gerar resumo novamente") { store.retrySummary(meeting) }
                        .disabled(store.isBusy || store.isRecording)
                } else if let summary = meeting.summary, !summary.isEmpty {
                    Text(LocalizedStringKey(summary)).textSelection(.enabled)
                } else {
                    Label("Nenhum resumo gerado", systemImage: "text.alignleft").font(.headline)
                    Text("Gere um resumo com decisões e tarefas usando sua conta AssemblyAI. Esse recurso depende do acesso ao modelo de resumo.").foregroundStyle(.secondary)
                    Button("Gerar resumo") { store.retrySummary(meeting) }
                        .disabled(store.isBusy || store.isRecording)
                }
            }.font(.system(size: textSize)).lineSpacing(6)
                .frame(maxWidth: 740, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var words: some View {
        Table(meeting.words) {
            TableColumn("Tempo") { Text(AppFormatters.timestamp($0.start)).monospacedDigit() }.width(80)
            TableColumn("Pessoa") { Text($0.speaker ?? "Não identificada") }.width(100)
            TableColumn("Palavra") { Text($0.text).textSelection(.enabled) }
            TableColumn("Confiança") { word in
                Text(word.confidence, format: .percent.precision(.fractionLength(1))).monospacedDigit()
            }.width(90)
        }.overlay {
            if meeting.words.isEmpty { ContentUnavailableView("Sem detalhes por palavra", systemImage: "textformat.abc", description: Text("O texto completo continua disponível na aba Transcrição.")) }
        }
    }

    private var processing: some View {
        VStack(spacing: 20) {
            if meeting.status == .failed {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 36))
                Text("Não foi possível concluir").font(.title2.bold())
                Text(meeting.errorMessage ?? "Tente novamente ou confira sua conexão e a API key nos Ajustes.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
                Button("Tentar novamente") { store.retry(meeting) }
                    .buttonStyle(.borderedProminent).disabled(store.isBusy || store.isRecording)
            } else {
                ProgressView(value: meeting.progress).frame(maxWidth: 300)
                Text(meeting.status.rawValue).font(.title3.bold())
                Text("Você pode continuar consultando a biblioteca enquanto aguarda.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func export(_ format: ExportService.Format) {
        let panel = NSSavePanel()
        panel.title = "Exportar transcrição"
        panel.nameFieldStringValue = ExportService.suggestedFilename(meeting: meeting, format: format)
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.contentType]
        if panel.runModal() == .OK, let url = panel.url {
            do { try ExportService.export(meeting: meeting, format: format, to: url) }
            catch { store.alertMessage = "Não foi possível exportar. Escolha outra pasta e tente novamente. \(error.localizedDescription)" }
        }
    }
}
