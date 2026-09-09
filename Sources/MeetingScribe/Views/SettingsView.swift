import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @EnvironmentObject private var updates: UpdateService

    var body: some View {
        TabView {
            settingsPage { account }
                .tabItem { Label("Conta", systemImage: "key") }
            settingsPage { transcription }
                .tabItem { Label("Transcrição", systemImage: "waveform") }
            settingsPage { advanced }
                .tabItem { Label("Avançado", systemImage: "slider.horizontal.3") }
            settingsPage { about }
                .tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .onDisappear { store.savePreferences() }
    }

    private func settingsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28, content: content)
                .frame(maxWidth: 560, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.visible)
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
    }

    private var account: some View {
        Group {
            section("Conecte sua conta") {
                description("Cole a API key da AssemblyAI. A transcrição usa o saldo da sua conta.")
                SettingsField("API key da AssemblyAI") {
                    SecureField("API key da AssemblyAI", text: $store.apiKey)
                }
                Link("Obter API key na AssemblyAI", destination: URL(string: "https://www.assemblyai.com/dashboard/signup")!)
                HStack(spacing: 12) {
                    Button("Salvar chave") { store.savePreferences() }
                        .buttonStyle(.borderedProminent)
                    Button("Testar conexão") { store.savePreferences(); store.validateAPIKey() }
                        .disabled(store.isBusy || store.isRecording)
                    if store.isBusy { ProgressView().controlSize(.small) }
                }
            }
            section("Onde seus dados ficam") {
                SettingsField("Região dos dados") {
                    Picker("Região dos dados", selection: $store.settings.region) {
                        ForEach(AssemblyRegion.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                description("A chave fica protegida no Keychain do macOS. Os arquivos são enviados à AssemblyAI para transcrição. O histórico fica neste Mac.")
            }
        }
    }

    private var transcription: some View {
        Group {
            section("Texto e idioma") {
                SettingsField("Modelo de transcrição") {
                    Picker("Modelo de transcrição", selection: $store.settings.model) {
                        ForEach(SpeechModelChoice.allCases) { Text($0.title).tag($0) }
                    }
                }
                SettingsField("Idioma") {
                    TextField("Idioma", text: $store.settings.languageCode)
                }
                description("Deixe vazio para detectar automaticamente ou use pt para português.")
            }
            section("Participantes") {
                Toggle("Separar locutores", isOn: $store.settings.speakerLabels)
                SettingsField("Número exato de locutores (opcional)") {
                    TextField("Número exato de locutores", value: $store.settings.expectedSpeakers, format: .number)
                }.disabled(!store.settings.speakerLabels)
                HStack(alignment: .top, spacing: 16) {
                    SettingsField("Mínimo de locutores") {
                        TextField("Mínimo de locutores", value: $store.settings.minimumSpeakers, format: .number)
                    }
                    SettingsField("Máximo de locutores") {
                        TextField("Máximo de locutores", value: $store.settings.maximumSpeakers, format: .number)
                    }
                }.disabled(!store.settings.speakerLabels || store.settings.expectedSpeakers != nil)
                SettingsField("Nomes conhecidos, separados por vírgula") {
                    TextField("Nomes conhecidos, separados por vírgula", text: $store.settings.speakerNames)
                }.disabled(!store.settings.speakerLabels)
                Toggle("Áudio multicanal importado", isOn: $store.settings.multichannel)
            }
            section("Resumo e privacidade") {
                Toggle("Gerar resumo, decisões e tarefas", isOn: $store.settings.generateSummary)
                description("O resumo exige acesso ao modelo de resumo na AssemblyAI. Se falhar, a transcrição continua disponível.")
                Toggle("Apagar a transcrição remota depois de exportar", isOn: $store.settings.deleteRemoteAfterSave)
            }
            saveButton
        }
    }

    private var advanced: some View {
        Group {
            section("Vocabulário e contexto") {
                SettingsField("Contexto da reunião") {
                    TextField("Contexto da reunião", text: $store.settings.prompt, axis: .vertical).lineLimit(3...8)
                }
                SettingsField("Termos importantes, separados por vírgula") {
                    TextField("Termos importantes, separados por vírgula", text: $store.settings.keyterms, axis: .vertical).lineLimit(2...6)
                }
                SettingsField("Grafias personalizadas") {
                    TextField("Grafias personalizadas", text: $store.settings.customSpelling, axis: .vertical).lineLimit(2...6)
                }
                description("Use variante|variante=Correto para indicar a grafia desejada.")
            }
            section("Formatação do texto") {
                SettingsField("Eventos de áudio") {
                    Picker("Eventos de áudio", selection: $store.settings.audioTags) {
                        ForEach(AudioTagsChoice.allCases) { Text($0.title).tag($0) }
                    }
                }
                Toggle("Pontuação automática", isOn: $store.settings.punctuate)
                Toggle("Formatação automática", isOn: $store.settings.formatText)
                Toggle("Preservar hesitações", isOn: $store.settings.disfluencies)
                Toggle("Filtrar palavrões", isOn: $store.settings.filterProfanity)
            }
            section("Dados pessoais") {
                Toggle("Ocultar dados pessoais", isOn: $store.settings.redactPII)
                SettingsField("Substituição de dados pessoais") {
                    Picker("Substituição de dados pessoais", selection: $store.settings.piiSubstitution) {
                        ForEach(PIISubstitution.allCases) { Text($0.title).tag($0) }
                    }
                }.disabled(!store.settings.redactPII)
            }
            section("Análises adicionais") {
                Toggle("Detectar entidades", isOn: $store.settings.entityDetection)
                Toggle("Análise de sentimento", isOn: $store.settings.sentimentAnalysis)
                Toggle("Frases-chave", isOn: $store.settings.autoHighlights)
                Toggle("Tópicos IAB", isOn: $store.settings.iabCategories)
                Toggle("Classificação de segurança", isOn: $store.settings.contentSafety)
                Toggle("Vocabulário médico", isOn: $store.settings.medicalMode)
            }
            section("Trecho do áudio") {
                description("Deixe os campos vazios para transcrever o arquivo inteiro.")
                HStack(alignment: .top, spacing: 16) {
                    SettingsField("Início (segundos)") {
                        TextField("Início em segundos", value: $store.settings.audioStartSeconds, format: .number)
                    }
                    SettingsField("Fim (segundos)") {
                        TextField("Fim em segundos", value: $store.settings.audioEndSeconds, format: .number)
                    }
                }
            }
            saveButton
        }
    }

    private var about: some View {
        Group {
            section("Meeting Scribe") {
                Text("Criado por @junowozlabs").font(.headline)
                Link("Conhecer o projeto no GitHub", destination: URL(string: "https://github.com/junowozlabs/meeting-scribe")!)
                description("Versão \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Desenvolvimento")")
            }
            section("Atualizações") {
                Toggle("Buscar atualizações automaticamente", isOn: $updates.automaticallyChecksForUpdates)
                Button("Buscar atualizações agora", action: updates.checkForUpdates)
                    .disabled(!updates.canCheckForUpdates)
                description("As atualizações são assinadas pelo projeto e distribuídas pelo GitHub.")
            }
            section("Biblioteca anterior") {
                description("Na primeira instalação desta versão, você pode copiar a biblioteca anterior. Os arquivos originais são preservados.")
                Button("Importar histórico da versão anterior…") { store.importLegacyHistory() }
                    .disabled(store.isBusy || store.isRecording || !store.meetings.isEmpty)
                if !store.meetings.isEmpty {
                    description("A importação do histórico anterior está disponível quando esta biblioteca está vazia.")
                }
            }
        }
    }

    private var saveButton: some View {
        Button("Salvar preferências") { store.savePreferences() }
            .buttonStyle(.borderedProminent)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func description(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            content.labelsHidden().accessibilityLabel(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
