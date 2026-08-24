import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: AppStore
    @State private var search = ""

    private var filtered: [Meeting] {
        search.isEmpty ? store.meetings : store.meetings.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(selection: $store.selection) {
            Section("Reuniões") {
                ForEach(filtered) { meeting in
                    HStack(spacing: 10) {
                        Image(systemName: meeting.status == .completed ? "checkmark.circle.fill" : meeting.status == .failed ? "exclamationmark.triangle.fill" : "waveform")
                            .foregroundStyle(meeting.status == .failed ? .red : meeting.status == .completed ? .green : .secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting.title).lineLimit(1)
                            Text("\(AppFormatters.date.string(from: meeting.createdAt)) · \(AppFormatters.duration(meeting.durationSeconds))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(meeting.id)
                    .contextMenu { Button("Mostrar no Finder") { store.reveal(meeting) } }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, prompt: "Buscar reuniões")
        .navigationTitle("Meeting Scribe")
        .safeAreaInset(edge: .bottom) {
            if store.isRecording {
                HStack {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Gravando \(AppFormatters.duration(store.recordingElapsed))").monospacedDigit()
                    Spacer()
                    Button("Parar") { store.stopRecording() }.buttonStyle(.borderless)
                }
                .padding(10).background(.regularMaterial)
            }
        }
    }
}
