import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore
    @State private var showRecorder = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            if let meeting = store.selectedMeeting { MeetingDetailView(store: store, meeting: meeting) }
            else { EmptyLibraryView(importAction: chooseMedia, recordAction: { showRecorder = true }) }
        }
        .toolbar {
            ToolbarItemGroup {
                if store.isBusy {
                    ProgressView().controlSize(.small)
                    Text(store.activityText).foregroundStyle(.secondary)
                    Button("Cancelar") { store.cancelActiveWork() }
                }
                Button { chooseMedia() } label: { Label("Importar", systemImage: "square.and.arrow.down") }
                Button { showRecorder = true } label: { Label("Gravar", systemImage: "record.circle") }
                    .disabled(store.isBusy || store.isRecording)
            }
        }
        .sheet(isPresented: $showRecorder) { RecordingSetupView(store: store, isPresented: $showRecorder) }
        .onReceive(NotificationCenter.default.publisher(for: .importMedia)) { _ in chooseMedia() }
        .onReceive(NotificationCenter.default.publisher(for: .newRecording)) { _ in showRecorder = true }
    }

    private func chooseMedia() {
        let panel = NSOpenPanel()
        panel.title = "Escolha um áudio ou vídeo"
        panel.prompt = "Transcrever"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK, let url = panel.url { store.importMedia(url) }
    }
}

private struct EmptyLibraryView: View {
    let importAction: () -> Void
    let recordAction: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Suas reuniões, sem trabalho manual", systemImage: "waveform.and.mic")
        } description: {
            Text("Grave o Mac e o microfone ou importe qualquer áudio/vídeo. O app prepara, transcreve e exporta tudo automaticamente.")
        } actions: {
            HStack {
                Button("Gravar reunião", action: recordAction).buttonStyle(.borderedProminent)
                Button("Importar mídia", action: importAction)
            }
        }
    }
}
