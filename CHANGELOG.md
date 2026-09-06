# Changelog — CloudOS

Todas as alterações notáveis deste projeto são documentadas neste arquivo.

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
