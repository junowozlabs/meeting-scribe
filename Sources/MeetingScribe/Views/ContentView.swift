import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: AppStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showRecorder = false
    @State private var isDropTarget = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
        } detail: {
            VStack(spacing: 0) {
                if store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "key")
                        Text("Conecte sua conta AssemblyAI para começar.")
                        Spacer()
                        Button("Adicionar API key") { openSettings() }
                    }.padding(14).background(.quaternary)
                }
                if let meeting = store.selectedMeeting {
                    MeetingDetailView(store: store, meeting: meeting).id(meeting.id)
                } else {
                    EmptyLibraryView(importAction: chooseMedia, recordAction: beginRecording)
                }
            }
        }
        .overlay {
            if isDropTarget {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 18).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.doc").font(.system(size: 48))
                        Text("Solte os arquivos para transcrever").font(.title2.bold())
                        Text("Áudios e vídeos entram na fila, um de cada vez.")
                    }
                }.padding(12).allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isDropTarget)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            store.importMedia(urls)
            return true
        } isTargeted: { isDropTarget = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.isBusy {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(store.activityText + (store.queuedCount > 0 ? " · \(store.queuedCount) na fila" : "")).font(.callout).accessibilityLabel("Progresso: \(store.activityText)")
                    Spacer()
                    Button(store.queuedCount > 0 ? "Cancelar processamento e fila" : "Cancelar processamento") { store.cancelActiveWork() }
                }.padding(14).background(.bar)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: chooseMedia) { Label("Importar arquivos", systemImage: "plus") }
                    .help("Importar áudios ou vídeos (⌘O)")
                Button(action: beginRecording) { Label("Gravar", systemImage: "record.circle") }
                    .disabled(store.isBusy || store.isRecording).help("Gravar áudio do Mac e microfone")
            }
        }
        .sheet(isPresented: $showRecorder) { RecordingSetupView(store: store, isPresented: $showRecorder) }
        .onReceive(NotificationCenter.default.publisher(for: .importMedia)) { _ in chooseMedia() }
        .onReceive(NotificationCenter.default.publisher(for: .newRecording)) { _ in beginRecording() }
    }

    private func beginRecording() {
        guard !store.isBusy, !store.isRecording else { return }
        if store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { openSettings() }
        else { showRecorder = true }
    }

    private func chooseMedia() {
        let panel = NSOpenPanel()
        panel.title = "Importar áudios ou vídeos"
        panel.message = "Selecione um ou mais arquivos. Eles serão transcritos em sequência."
        panel.prompt = "Importar"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = MediaProcessor.supportedContentTypes
        if panel.runModal() == .OK { store.importMedia(panel.urls) }
    }
}

private struct EmptyLibraryView: View {
    let importAction: () -> Void
    let recordAction: () -> Void
    var body: some View {
        VStack(spacing: 28) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 88, height: 88).accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Dê voz aos seus arquivos.").font(.largeTitle.weight(.semibold))
                Text("Arraste áudios ou vídeos para cá.\nEncontre cada transcrição nesta biblioteca, quando precisar.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button(action: importAction) { Label("Importar arquivos", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Button(action: recordAction) { Label("Gravar reunião", systemImage: "record.circle") }
            }.controlSize(.large)
            Text("M4A · MP3 · MP4 · OGG · FLAC · WAV · WebM e outros")
                .font(.callout).foregroundStyle(.secondary)
            Text("A mídia é enviada à AssemblyAI para transcrição.\nO histórico e os arquivos ficam neste Mac.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
