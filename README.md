# Meeting Scribe

App macOS local-first para gravar reuniões (áudio interno + microfone), importar áudio/vídeo e gerar transcrições completas pela AssemblyAI.

![Ícone do Meeting Scribe](Resources/AppIcon-1024.png)

## Executar

Requer macOS 14 ou superior e Xcode/Swift instalados.

```bash
./script/build_and_run.sh
```

Na primeira gravação, permita **Microfone** e **Gravação de Tela** em Ajustes do Sistema > Privacidade e Segurança. A chave da AssemblyAI é salva somente no Keychain.

## Saídas automáticas

Cada reunião fica em `~/Library/Application Support/MeetingScribe/Meetings/` com a mídia local e `transcript.json`, TXT/Markdown, SRT/VTT, legendas com speakers, CSV de confiança e resumo quando habilitado.

O app usa Universal-3.5 Pro com fallback para Universal-2 por padrão. Resumos, decisões e tarefas usam o LLM Gateway da própria AssemblyAI.
