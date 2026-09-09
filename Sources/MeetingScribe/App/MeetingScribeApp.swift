import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var workInProgress: (() -> Bool)?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard workInProgress?() == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Há uma gravação ou transcrição em andamento"
        alert.informativeText = "Continue no app para concluir. Sair agora pode interromper a gravação e descartar os arquivos que ainda estão na fila."
        alert.addButton(withTitle: "Continuar no app")
        alert.addButton(withTitle: "Sair mesmo assim")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MeetingScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var updates = UpdateService()

    var body: some Scene {
        WindowGroup("Meeting Scribe", id: "main") {
            GeometryReader { geometry in
                ContentView(store: store)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
                .onAppear { appDelegate.workInProgress = { store.isBusy || store.isRecording || store.queuedCount > 0 } }
                .frame(minWidth: 780, minHeight: 560)
                .environment(\.locale, Locale(identifier: "pt_BR"))
                .alert("Meeting Scribe", isPresented: Binding(
                    get: { store.alertMessage != nil },
                    set: { if !$0 { store.alertMessage = nil } }
                )) { Button("OK") { store.alertMessage = nil } } message: { Text(store.alertMessage ?? "") }
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Buscar atualizações…", action: updates.checkForUpdates)
                    .disabled(!updates.canCheckForUpdates)
            }
            CommandMenu("Reunião") {
                Button("Importar mídia…") { NotificationCenter.default.post(name: .importMedia, object: nil) }.keyboardShortcut("o")
                Button(store.isRecording ? "Encerrar gravação" : "Nova gravação") {
                    if store.isRecording { store.stopRecording() } else { NotificationCenter.default.post(name: .newRecording, object: nil) }
                }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        Settings { SettingsView(store: store).environmentObject(updates).frame(width: 650, height: 650) }
    }
}

extension Notification.Name {
    static let importMedia = Notification.Name("MeetingScribe.importMedia")
    static let newRecording = Notification.Name("MeetingScribe.newRecording")
}
