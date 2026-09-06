# Changelog — CloudOS

Todas as alterações notáveis deste projeto são documentadas neste arquivo.

## [21.0.0-rc.1.3] - 2026-09-06

### Adicionado e Aprimorado
- **Eliminação de Vazamento de Memória em Diálogo (Timer Exponencial)**: Correção no diálogo de redefinição de fábrica em `SettingsWindow`, garantindo que o `Timer.periodic` seja isolado fora do builder de interface e cancelado pontualmente via `.whenComplete()`.
- **Reaping e Coleta de Sessões Zumbis no ConPTY**: Adição de rotina de coleta de processos de terminal encerrados em `CloudOSConptyManager::StartSession` antes de avaliar o limite de 32 sessões simultâneas (`kMaxSessions`), prevenindo esgotamento de handles sob ciclo repetitivo de abre/fecha.
- **Suíte de Soak e Estresse (Soak Stability Pass)**: Teste contínuo com monitoramento periódico (15s/30s) sob carga pesada: Working Set estável (~14.2 MB), Private Memory delta de -0.23 MB, redução de 12 handles Win32 e estabilização de threads de 11 para 5. Zero vazamentos detectados.
- **Resiliência Extrema de IPC do System Broker**: Processamento ininterrupto de 2.000 requisições sequenciais de ping com 0 falhas e 400 consultas em concorrência paralela (4 threads).
- **Integridade de Armazenamento e Tolerância a Falhas**: Validação de 5 transferências consecutivas de 100MB com SHA256 bit-a-bit e rejeição de nomes de dispositivos DOS (`CON`, `PRN`, `AUX`, `NUL`).
- **Instalador Oficial Inno Setup (Build 34)**: Pacote `CloudOS-Setup-21.0.0-rc.1.3-x64.exe` (11.79 MB, SHA256 `20baaa1c693c889dac980d00073bbfec13462a77cb0e76ed980634e4555f684f`) gerado e verificado com manifesto e feed de atualização.

## [21.0.0-rc.1.2] - 2026-09-06

### Adicionado e Aprimorado
- **Validação de Ciclo de Vida Real do Instalador**: Teste físico completo do executável oficial Inno Setup `CloudOS-Setup-21.0.0-rc.1.2-x64.exe` (11.79 MB, SHA256 `45a86456b432aa50d909806a0f7d793f0b4cc246e439db5946baf2509b6a2111`) em caminhos com espaços, independência de repositório e desinstalação idempotente.
- **Comparador SemVer 2.0.0 (`Compare-CloudOSSemVer`)**: Implementação de comparação de versão semântica completa com suporte a pré-releases e precedências no mecanismo de atualização e manutenção.
- **Benchmark e Teste de Estresse do IPC**: 500 chamadas sequenciais com média de 28.92 ms de latência e 34.5 req/s; rejeição imediata de frames > 1 MiB e payloads malformados sem instabilidade do broker.
- **Sanitização de Identidade de Desenvolvimento**: Substituição de nomes e caminhos estáticos por consultas dinâmicas de ambiente (`Platform.environment['USERNAME']`) no Menu Iniciar, Configurações e caminhos mock.
- **Delimitação de Preferências**: Listas de aplicativos fixados e recentes delimitadas em memória (50 e 20 itens) com suíte de testes unitários dedicada.
- **Automação de CI para Release Candidate**: Novo fluxo `.github/workflows/rc-validation.yml` para validação contínua de integridade de release e todos os 49 contratos nativos e 20 contratos de shell/instalador.

## [21.0.0-rc.1.1] - 2026-09-05

### Adicionado e Aprimorado
- **Compilação Real do Instalador Inno Setup**: Pipeline automatizado via `scripts/release/build-rc.ps1`, compilando `CloudOS-Setup-21.0.0-rc.1.1-x64.exe` com Inno Setup 6, salvaguardas contra diretórios críticos do Windows em `[Code]` e geração de hashes `SHA256SUMS.txt`.
- **Centralização Canônica de Versão**: Metadados sincronizados entre `version.json`, `cloudos_version.dart` e todas as superfícies de interface (Diagnósticos, Sobre e Relatórios).
- **Resiliência e Migração de Preferências (`schemaVersion: 2`)**: Migração automática do schema v1 -> v2, quarentena de JSON corrompido (`.corrupt.<timestamp>`) e rotação delimitada de até 5 backups de segurança.
- **Atualizador Endurecido (Downgrade Protection)**: Rejeição de atualizações para builds inferiores sem o parâmetro `-Force` e suporte a feed estruturado `update-feed.json`.
- **Proteção Estendida no Gerenciador de Tarefas**: Inclusão de `CloudOS.Supervisor.exe`, `CloudOS.SystemBroker.exe` e `CloudOS.Recovery.exe` na lista de proteção contra encerramento de processos.
- **Validação de Nomes de Arquivo**: Bloqueio de nomes de dispositivos reservados (`CON`, `PRN`, `AUX`, etc.) e caracteres proibidos no Gerenciador de Arquivos com mensagens em português do Brasil.
- **Pacote de Diagnóstico Sanitizado**: Automação `scripts/diagnostics/export-diagnostics-bundle.ps1` que gera arquivo ZIP de suporte sem caminhos absolutos de usuário e sem dados confidenciais.
- **Validação Estrita do GATE 0**: Script dedicado `scripts/safety/assert-gate0.ps1` para garantia da inviolabilidade do Windows Explorer e do Userinit.

### Documentação
- Novos documentos completos: `docs/INSTALL.md`, `docs/SECURITY_MODEL.md`, `docs/PRIVACY.md`, `docs/RC1_1_RELEASE_CHECKLIST.md`, `docs/RC1_1_USER_QA.md` e `docs/RC1_1_BUGS.md`.
- Atualização aprofundada de `docs/RECOVERY.md` e `docs/UPDATES.md`.

## [1.0.0-rc1] - 2026-09-05

### Adicionado
- **Lixeira Nativa (RecycleBinView)**: Integração da rota `trash` no Gerenciador de Arquivos com endpoints Win32 (`files.queryRecycleBin` e `files.emptyRecycleBin`) via `SHQueryRecycleBinW` e `SHEmptyRecycleBinW`.
- **Persistência de Preferências (`CloudOSPreferences`)**: Sistema transacional e versionado (`schemaVersion: 1`) com suporte a backup automático em caso de corrupção para posições de ícones, pin status, aplicativos recentes e preferências OOBE.
- **Desktop Interativo Aprimorado**: Reflow responsivo e clamp de coordenadas nos limites da tela em mudanças de resolução ou DPI.
- **Menu Iniciar com Deep Search**: Indexação de configurações do sistema (Vídeo, Áudio, Rede, Energia, WSL, etc.) e pastas de arquivos; menu de contexto com clique direito para Fixar/Desafixar e histórico de recentes.
- **Lista de Proteção no Gerenciador de Tarefas**: Denylist para processos vitais do Windows (`winlogon`, `csrss`, `lsass`, `services`, `smss`, `system`, `svchost`, `explorer`, `dwm`) evitando falha ou tela azul acidental.
- **Painel de Visão Geral em Configurações**: Dashboard consolidado com status em tempo real de hardware, rede, energia, WSL e shell; exportação de backup em JSON e redefinição de fábrica com dupla confirmação.
- **Terminal ConPTY com Seletor de Perfis**: Dropdown para alternância entre PowerShell, CMD e WSL; banner e ação para reiniciar sessões encerradas.
- **Navegador WebView2 Resiliente**: Banner visual e botão de recuperação imediata para falhas de rede ou carregamento.
- **Instalador Inno Setup (`scripts/installer/CloudOS.iss`)**: Especificação oficial per-user com verificação de dependências (VC++ Redistributable, WebView2 Runtime, WSL2) e desinstalador limpo.
- **Inventário de Superfícies (`docs/RC1_INVENTORY.md`)**: Catálogo auditado de todas as 28 superfícies do sistema.

### Segurança e Integridade
- **Gate 0 Estritamente Mantido**: Windows Explorer (`explorer.exe`) permanece o shell primário do sistema operacional em `HKLM\Winlogon\Shell`.
- Confinamento 100% em modo usuário (zero drivers de kernel ou modificações privilegiadas).
- Cobertura completa de testes: 151 testes Flutter, 49 contratos nativos, 5 contratos de instalação, 5 contratos de startup e 10 contratos de shell (100% PASS).
