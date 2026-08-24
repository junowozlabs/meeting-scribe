import SwiftUI

struct RecordingSetupView: View {
    @ObservedObject var store: AppStore
    @Binding var isPresented: Bool
    @State private var microphone = true
    @State private var screen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "record.circle").font(.system(size: 32)).foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text("Nova gravação").font(.title2.bold())
                    Text("O áudio interno do Mac é sempre capturado.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Incluir meu microfone", isOn: $microphone)
                Toggle("Salvar também a gravação da tela", isOn: $screen)
            }
            GroupBox {
                Label("O macOS pedirá acesso à Gravação de Tela para capturar o som do Meet, Zoom, navegador e outros apps. Use fones para reduzir eco.", systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary).padding(4)
            }
            HStack {
                Button("Cancelar") { isPresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Começar gravação") {
                    store.startRecording(includeMicrophone: microphone, recordScreen: screen)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 500)
    }
}
