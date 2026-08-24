import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MeetingScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("Meeting Scribe", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 640)
                .alert("Meeting Scribe", isPresented: Binding(
                    get: { store.alertMessage != nil },
                    set: { if !$0 { store.alertMessage = nil } }
                )) { Button("OK") { store.alertMessage = nil } } message: { Text(store.alertMessage ?? "") }
        }
        .defaultSize(width: 1_180, height: 760)
        .commands {
            CommandMenu("Reunião") {
                Button("Importar mídia…") { NotificationCenter.default.post(name: .importMedia, object: nil) }.keyboardShortcut("o")
                Button(store.isRecording ? "Encerrar gravação" : "Nova gravação") {
                    if store.isRecording { store.stopRecording() } else { NotificationCenter.default.post(name: .newRecording, object: nil) }
                }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        Settings { SettingsView(store: store).frame(width: 620, height: 620) }
    }
}

extension Notification.Name {
    static let importMedia = Notification.Name("MeetingScribe.importMedia")
    static let newRecording = Notification.Name("MeetingScribe.newRecording")
}
