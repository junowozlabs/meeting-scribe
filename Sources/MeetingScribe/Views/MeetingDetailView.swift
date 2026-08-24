import SwiftUI

struct MeetingDetailView: View {
    @ObservedObject var store: AppStore
    let meeting: Meeting
    @State private var tab = 0
    @State private var title = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if meeting.status == .completed {
                Picker("Conteúdo", selection: $tab) {
                    Text("Notas").tag(0); Text("Transcrição").tag(1); Text("Palavras").tag(2)
                }
                .pickerStyle(.segmented).frame(maxWidth: 430).padding()
                Group {
                    if tab == 0 { SummaryView(meeting: meeting) }
                    else if tab == 1 { TranscriptView(meeting: meeting) }
                    else { WordsView(meeting: meeting) }
                }
            } else { processing }
        }
        .onAppear { title = meeting.title }
        .onChange(of: meeting.id) { _, _ in title = meeting.title }
        .confirmationDialog("Remover esta reunião?", isPresented: $confirmDelete) {
            Button("Remover do histórico") { store.remove(meeting, deleteFiles: false) }
            Button("Mover arquivos para o Lixo", role: .destructive) { store.remove(meeting, deleteFiles: true) }
        } message: { Text("Você pode apenas remover o registro ou também enviar a pasta local ao Lixo.") }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                TextField("Título", text: $title, onCommit: { store.rename(meeting, title: title) })
                    .textFieldStyle(.plain).font(.title2.bold())
                Text("\(AppFormatters.date.string(from: meeting.createdAt)) · \(AppFormatters.duration(meeting.durationSeconds)) · \(meeting.speechModelUsed ?? meeting.status.rawValue)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.reveal(meeting) } label: { Label("Arquivos", systemImage: "folder") }
            Menu { Button("Remover…", role: .destructive) { confirmDelete = true } } label: { Image(systemName: "ellipsis.circle") }
        }.padding(20)
    }

    private var processing: some View {
        VStack(spacing: 18) {
            if meeting.status == .failed {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange)
                Text("Não foi possível concluir").font(.title2.bold())
                Text(meeting.errorMessage ?? "Erro desconhecido").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
                Button("Tentar novamente") { store.retry(meeting) }.buttonStyle(.borderedProminent)
            } else {
                ProgressView(value: meeting.progress).frame(width: 320)
                Text(meeting.status.rawValue).font(.title3.bold())
                Text("O ID do job é salvo assim que ele é criado.").foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SummaryView: View {
    let meeting: Meeting
    var body: some View {
        ScrollView { Text(meeting.summary ?? "Nenhum resumo solicitado.").textSelection(.enabled).frame(maxWidth: 760, alignment: .leading).padding(28).frame(maxWidth: .infinity) }
    }
}

private struct TranscriptView: View {
    let meeting: Meeting
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if meeting.utterances.isEmpty { Text(meeting.text).textSelection(.enabled) }
                else {
                    ForEach(meeting.utterances) { utterance in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(utterance.speaker).font(.headline); Text(AppFormatters.timestamp(utterance.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            Text(utterance.text).textSelection(.enabled)
                        }
                    }
                }
            }.frame(maxWidth: 820, alignment: .leading).padding(28).frame(maxWidth: .infinity)
        }
    }
}

private struct WordsView: View {
    let meeting: Meeting
    var body: some View {
        Table(meeting.words) {
            TableColumn("Tempo") { Text(AppFormatters.timestamp($0.start)).monospacedDigit() }.width(90)
            TableColumn("Speaker") { Text($0.speaker ?? "—") }.width(80)
            TableColumn("Palavra") { Text($0.text) }
            TableColumn("Confiança") { word in
                Text(word.confidence, format: .percent.precision(.fractionLength(1))).foregroundStyle(word.confidence < 0.75 ? .orange : .primary)
            }.width(90)
        }.padding(.horizontal)
    }
}
