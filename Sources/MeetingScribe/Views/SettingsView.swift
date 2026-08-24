import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        TabView {
            Form {
                SecureField("API key", text: $store.apiKey)
                HStack {
                    Button("Salvar no Keychain") { store.savePreferences() }
                    Button("Testar conexão") { store.savePreferences(); store.validateAPIKey() }
                    if store.isBusy { ProgressView().controlSize(.small) }
                }
                Picker("Região dos dados", selection: $store.settings.region) { ForEach(AssemblyRegion.allCases) { Text($0.rawValue).tag($0) } }
                Text("A chave nunca é salva em arquivo ou UserDefaults.").font(.caption).foregroundStyle(.secondary)
            }
            .padding().tabItem { Label("Conta", systemImage: "key") }

            Form {
                Picker("Modelo", selection: $store.settings.model) { ForEach(SpeechModelChoice.allCases) { Text($0.title).tag($0) } }
                TextField("Idioma (vazio = detectar; exemplo: pt)", text: $store.settings.languageCode)
                Toggle("Separar locutores", isOn: $store.settings.speakerLabels)
                TextField("Número exato de locutores (opcional)", value: $store.settings.expectedSpeakers, format: .number)
                    .disabled(!store.settings.speakerLabels)
                HStack {
                    TextField("Mínimo", value: $store.settings.minimumSpeakers, format: .number)
                    TextField("Máximo", value: $store.settings.maximumSpeakers, format: .number)
                }
                .disabled(!store.settings.speakerLabels || store.settings.expectedSpeakers != nil)
                TextField("Nomes conhecidos, separados por vírgula", text: $store.settings.speakerNames)
                    .disabled(!store.settings.speakerLabels)
                Toggle("Áudio multicanal importado", isOn: $store.settings.multichannel)
                Toggle("Gerar resumo, decisões e tarefas", isOn: $store.settings.generateSummary)
                Toggle("Apagar transcript remoto depois de exportar", isOn: $store.settings.deleteRemoteAfterSave)
                Button("Salvar preferências") { store.savePreferences() }.buttonStyle(.borderedProminent)
            }
            .padding().tabItem { Label("Transcrição", systemImage: "waveform") }

            ScrollView {
                Form {
                    TextField("Contexto da reunião", text: $store.settings.prompt, axis: .vertical)
                    TextField("Termos importantes, separados por vírgula", text: $store.settings.keyterms, axis: .vertical)
                    TextField("Grafias: variante|variante=Correto", text: $store.settings.customSpelling, axis: .vertical)
                    Picker("Eventos de áudio", selection: $store.settings.audioTags) { ForEach(AudioTagsChoice.allCases) { Text($0.title).tag($0) } }
                    Toggle("Pontuação automática", isOn: $store.settings.punctuate)
                    Toggle("Formatação automática", isOn: $store.settings.formatText)
                    Toggle("Preservar hesitações", isOn: $store.settings.disfluencies)
                    Toggle("Filtrar palavrões", isOn: $store.settings.filterProfanity)
                    Toggle("Redigir PII", isOn: $store.settings.redactPII)
                    Picker("Substituição de PII", selection: $store.settings.piiSubstitution) { ForEach(PIISubstitution.allCases) { Text($0.title).tag($0) } }
                        .disabled(!store.settings.redactPII)
                    Toggle("Detectar entidades", isOn: $store.settings.entityDetection)
                    Toggle("Análise de sentimento", isOn: $store.settings.sentimentAnalysis)
                    Toggle("Frases-chave", isOn: $store.settings.autoHighlights)
                    Toggle("Tópicos IAB", isOn: $store.settings.iabCategories)
                    Toggle("Classificação de segurança", isOn: $store.settings.contentSafety)
                    Toggle("Medical Mode", isOn: $store.settings.medicalMode)
                    HStack {
                        TextField("Início (segundos)", value: $store.settings.audioStartSeconds, format: .number)
                        TextField("Fim (segundos)", value: $store.settings.audioEndSeconds, format: .number)
                    }
                    Button("Salvar preferências") { store.savePreferences() }.buttonStyle(.borderedProminent)
                }.padding()
            }.tabItem { Label("Avançado", systemImage: "slider.horizontal.3") }
        }
        .onDisappear { store.savePreferences() }
    }
}
