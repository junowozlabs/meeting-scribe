import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: AppStore
    @Environment(\.openSettings) private var openSettings
    @State private var search = ""
    @State private var deleting: Meeting?

    private var filtered: [Meeting] {
        search.isEmpty ? store.meetings : store.meetings.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Biblioteca").font(.headline)
                Spacer()
                Text("\(store.meetings.count)").foregroundStyle(.secondary).monospacedDigit()
            }.padding(.horizontal, 16).padding(.vertical, 12)
            List(selection: $store.selection) {
                ForEach(filtered) { meeting in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(meeting.title).font(.body.weight(.medium)).lineLimit(2).help(meeting.title)
                        HStack(spacing: 5) {
                            Image(systemName: meeting.status == .completed ? "checkmark.circle" : meeting.status == .failed ? "exclamationmark.triangle" : "waveform")
                            Text(meeting.status.rawValue)
                            Spacer(minLength: 2)
                            Text(AppFormatters.duration(meeting.durationSeconds)).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                        Text(meeting.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7).tag(meeting.id)
                    .accessibilityElement(children: .combine)
                    .contextMenu {
                        Button("Mostrar no Finder") { store.reveal(meeting) }
                        Button("Excluir transcrição…", role: .destructive) { deleting = meeting }
                            .disabled(store.isBusy || store.isRecording)
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Text(search.isEmpty ? "Nenhuma transcrição ainda" : "Nenhum resultado para “\(search)”")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if !search.isEmpty { Button("Limpar busca") { search = "" } }
                    }.padding()
                }
            }
            if store.isRecording {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Gravando \(AppFormatters.duration(store.recordingElapsed))", systemImage: "record.circle.fill")
                        .monospacedDigit().font(.headline)
                    Button("Encerrar e transcrever") { store.stopRecording() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
            }
            HStack {
                Button { openSettings() } label: { Label("Ajustes", systemImage: "gearshape") }
                    .buttonStyle(.borderless).padding(.vertical, 10)
                Spacer()
                Link("@junowozlabs", destination: URL(string: "https://github.com/junowozlabs")!)
                    .font(.caption).help("Criado por @junowozlabs")
            }.padding(.horizontal, 16)
        }
        .searchable(text: $search, prompt: "Buscar transcrições")
        .navigationTitle("Meeting Scribe")
        .sheet(item: $deleting) { meeting in
            DeleteMeetingView(store: store, meeting: meeting)
        }
    }
}

struct DeleteMeetingView: View {
    @ObservedObject var store: AppStore
    let meeting: Meeting
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Excluir transcrição?", systemImage: "trash").font(.title2.bold())
            Text(meeting.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text("A transcrição sairá da biblioteca e a pasta com a mídia e as exportações irá para o Lixo do Mac. O arquivo original importado não será alterado.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Mover para o Lixo", role: .destructive) {
                    store.remove(meeting, deleteFiles: true)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 460)
    }
}
