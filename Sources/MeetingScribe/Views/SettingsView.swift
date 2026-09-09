import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject private var updates: UpdateService

    var body: some View {
        TabView {
            Form {
                Text("Conecte sua conta").font(.title2.bold())
                Text("Cole a API key da AssemblyAI. A transcrição usa o saldo da sua conta.").foregroundStyle(.secondary)
                SecureField("API key da AssemblyAI", text: $store.apiKey)
                Link("Obter API key na AssemblyAI", destination: URL(string: "https://www.assemblyai.com/dashboard/signup")!)
                HStack {
                    Button("Salvar no Keychain") { store.savePreferences() }
                    Button("Testar conexão") { store.savePreferences(); store.validateAPIKey() }.disabled(store.isBusy || store.isRecording)
                    if store.isBusy { ProgressView().controlSize(.small) }
                }
                Picker("Região dos dados", selection: $store.settings.region) { ForEach(AssemblyRegion.allCases) { Text($0.rawValue).tag($0) } }
                Text("A chave fica protegida no Keychain do macOS. Os arquivos são enviados à AssemblyAI para transcrição; o histórico fica neste Mac.").font(.callout).foregroundStyle(.secondary)
            }
            .padding().tabItem { Label("Conta", systemImage: "key") }

            Form {
                Picker("Modelo", selection: $store.settings.model) { ForEach(SpeechModelChoice.allCases) { Text($0.title).tag($0) } }
                TextField("Idioma", text: $store.settings.languageCode)
                Text("Deixe vazio para detectar automaticamente ou use pt para português.").font(.caption).foregroundStyle(.secondary)
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
                Text("O resumo exige acesso ao modelo de resumo na AssemblyAI. Se falhar, a transcrição continua disponível.").font(.caption).foregroundStyle(.secondary)
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
                    Toggle("Ocultar dados pessoais", isOn: $store.settings.redactPII)
                    Picker("Substituição de dados pessoais", selection: $store.settings.piiSubstitution) { ForEach(PIISubstitution.allCases) { Text($0.title).tag($0) } }
                        .disabled(!store.settings.redactPII)
                    Toggle("Detectar entidades", isOn: $store.settings.entityDetection)
                    Toggle("Análise de sentimento", isOn: $store.settings.sentimentAnalysis)
                    Toggle("Frases-chave", isOn: $store.settings.autoHighlights)
                    Toggle("Tópicos IAB", isOn: $store.settings.iabCategories)
                    Toggle("Classificação de segurança", isOn: $store.settings.contentSafety)
                    Toggle("Vocabulário médico", isOn: $store.settings.medicalMode)
                    HStack {
                        TextField("Início (segundos)", value: $store.settings.audioStartSeconds, format: .number)
                        TextField("Fim (segundos)", value: $store.settings.audioEndSeconds, format: .number)
                    }
                    Button("Salvar preferências") { store.savePreferences() }.buttonStyle(.borderedProminent)
                }.padding()
            }.tabItem { Label("Avançado", systemImage: "slider.horizontal.3") }
            Form {
                Text("Meeting Scribe").font(.title.bold())
                Text("Criado por @junowoz").font(.headline)
                Link("Conhecer o projeto no GitHub", destination: URL(string: "https://github.com/junowoz/meeting-scribe")!)
                Text("Versão \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Desenvolvimento")")
                Toggle("Buscar atualizações automaticamente", isOn: $updates.automaticallyChecksForUpdates)
                Button("Buscar atualizações agora", action: updates.checkForUpdates)
                    .disabled(!updates.canCheckForUpdates)
                Text("As atualizações são assinadas pelo projeto e distribuídas pelo GitHub.").foregroundStyle(.secondary)
            }.padding().tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .onDisappear { store.savePreferences() }
    }
}
