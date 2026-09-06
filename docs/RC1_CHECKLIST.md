# CloudOS — Release Candidate 1 (RC1) Verification Checklist

Este checklist consolida a validação técnica e funcional do CloudOS Release Candidate 1 (RC1).

---

## 1. Regra de Ouro e Segurança de Shell (Gate 0)

- [x] **Explorer Oficial**: Windows Explorer permanece shell primário (`explorer.exe`) em HKLM\Winlogon\Shell.
- [x] **Userinit Íntegro**: `C:\WINDOWS\system32\userinit.exe,` verificado sem alterações.
- [x] **Ausência de Shell Persistente Não Autorizado**: Nenhuma chave HKCU ativa apontando para CloudOS.
- [x] **Confinamento em Modo Usuário**: Zero drivers de kernel, zero serviços privilegiados, zero elevação administrativa obrigatória.
- [x] **Ferramenta de Recuperação Operacional**: `CloudOS.Recovery.exe status` confirma `EXPLORER` ativo e íntegro.

---

## 2. Superfícies e UX do Produto

- [x] **Desktop Interativo**:
  - Drag and drop de ícones com persistência de coordenadas em `CloudOSPreferences`.
  - Reflow automático com clamp dentro dos limites da tela após resize ou troca de DPI.
  - Seleção por clique, duplo-clique para abrir aplicativos e atalhos.
- [x] **Menu Iniciar (Start Menu)**:
  - Busca rápida e indexação profunda (*Deep Search*) para seções de Configurações e pastas de Arquivos.
  - Fixar / Desafixar aplicativos com clique direito e persistência per-user.
  - Exibição de aplicativos recentes baseada em histórico real de lançamentos.
- [x] **Barra de Tarefas e Dock**:
  - Alternador de 4 áreas de trabalho (Workspaces) com autoridade NativeShell.
  - Indicador de estado de janelas abertas e minimizadas.
  - Acesso rápido à Central de Ações, Notificações e Configurações Rápidas.
- [x] **Gerenciador de Arquivos (Files)**:
  - Navegação entre pastas autorizadas (Home, Downloads, Documentos, Desktop, C:\, WSL).
  - Rota de Lixeira integrada com `RecycleBinView` nativa (contagem de itens, espaço ocupado, esvaziar lixeira).
  - Bloqueio contra escape para o Windows Explorer fora de rotas autorizadas.
- [x] **Gerenciador de Tarefas (Task Manager)**:
  - Monitoramento de processos ativos, memória, CPU e tipo de processo.
  - Lista de proteção (denylist) para processos críticos do Windows (`winlogon`, `csrss`, `lsass`, `services`, `smss`, `system`, `svchost`, `explorer`, `dwm`).
- [x] **Central de Configurações (Settings)**:
  - Seção de Visão Geral (Overview) com cards dinâmicos para Monitor, Áudio, Rede, Energia, WSL e Shell.
  - Backup de preferências do usuário com Exportação JSON e Redefinição de Fábrica com dupla confirmação.
- [x] **Terminal ConPTY**:
  - Seletor de perfis no botão `+` (PowerShell, CMD, WSL Ubuntu).
  - Detecção de término de processo com botão e banner de reinicialização de sessão.
- [x] **Navegador (Browser)**:
  - WebView2 isolado com suporte a devtools, recarga e navegação segura.
  - Banner de recuperação em falha de navegação com botão "Tentar novamente".
- [x] **Primeira Execução (OOBE / First Run)**:
  - Assistente de 7 etapas (< 1 min) com cálculo automático de perfil de hardware e preferência de inicialização.

---

## 3. Cobertura de Testes Automatizados

| Suíte de Testes | Contratos / Testes | Resultado |
|---|:---:|:---:|
| **Flutter Test Suite** (`flutter test`) | 151 / 151 | **100% PASS** |
| **Native Contract Suite** (`test-native-contract-suite.ps1`) | 49 / 49 | **100% PASS** |
| **Installer Contracts Suite** (`test-all-installer-contracts.ps1`) | 5 / 5 | **100% PASS** |
| **Startup Contracts Suite** (`test-all-startup-contracts.ps1`) | 5 / 5 | **100% PASS** |
| **Shell Contracts Suite** (`test-all-shell-contracts.ps1`) | 10 / 10 | **100% PASS** |
| **SystemBroker Self-Test** (`CloudOS.SystemBroker.exe --self-test`) | 51 / 51 | **100% PASS** |
| **SystemBroker Smoke Test** (`run-system-broker-smoke-v21.ps1`) | 14 / 14 | **100% PASS** |

---

## 4. Empacotamento e Entrega de Release

- [x] **Release Integrado**: `scripts/stage-integrated-v21.ps1` aprovado com integridade SHA256.
- [x] **Pacote Portátil**: `dist/CloudOS` gerado com 33 componentes, 38.16 MB e manifesto verificado.
- [x] **Script Inno Setup**: `scripts/installer/CloudOS.iss` pronto para compilação (`ISS READY / EXE NOT BUILT`).
