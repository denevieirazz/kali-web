# CloudOS — Gemini Persistent Guidelines & Tool Routing

## CloudOS Tool Routing

Para otimizar o consumo de contexto, precisão das respostas e evitar conflitos entre ferramentas, todos os agentes devem seguir estritamente esta matriz de roteamento de ferramentas:

* **Flutter source / runtime / analysis / LSP:**
  → `Dart/Flutter MCP` (`analyze_files`, `roots`, `lsp`, `pub`, `pub_dev_search`)
* **Flutter widget / layout / runtime error / DTD:**
  → `Dart MCP` (`widget_inspector`, `get_runtime_errors`, `dtd`) + `cua-driver` quando validação física
* **Windows API implementation (Win32, COM, Core Audio, ConPTY, DPI, WTS, Job Objects):**
  → `Microsoft Learn MCP` antes de assumir assinaturas ou comportamento de APIs Win32
* **Repositório remoto / CI / PRs / GitHub Actions / Code Security:**
  → `GitHub MCP`
* **Arquivos do workspace / operações locais de arquivo:**
  → `Filesystem MCP` / ferramentas nativas de workspace
* **Busca avançada com ripgrep / Diff cirúrgico por blocos / Processos interativos:**
  → `Desktop Commander MCP` (`start_search`, `edit_block`, `start_process`, `interact_with_process`)
* **Bibliotecas externas e pacotes de terceiros (pub.dev, C++ libs):**
  → `Context7`
* **CloudOS physical desktop / Janelas / Controles / Acessibilidade:**
  → `cua-driver` (UI Automation semântica: `get_window_state`, `list_windows`, `click` por element_index)
* **Automação direta de mouse/teclado / Drag-and-drop / Telas:**
  → `Windows Computer Use MCP` (`mouse_move`, `left_click`, `left_click_drag`, `key`, `list_displays`, `zoom`)
* **CloudOS Browser / navegação / páginas web / downloads web:**
  → `Playwright MCP` (estritamente restrito a páginas web; NUNCA usado no Shell desktop)
* **Git local (commits, diffs, status, branching):**
  → Git shell local (`git status`, `git diff`, `git commit`)
* **Compilação C++ e empacotamento:**
  → `MSBuild.exe` e scripts canônicos (`scripts\native\build-cloudos-native.cmd`, `package-cloudos-native.ps1`)
* **Estado físico do Windows / Probes de sistema:**
  → Win32 Probes dedicados (`CloudOS.BrokerProbe.exe`, `CloudOS.SystemBroker.exe --self-test`) + `cua-driver`

---

## Regras Invioláveis de Segurança e Operação

1. **Shell do Windows Intacto:** Proibido substituir o shell do Windows ou alterar chaves de registro do Winlogon (`HKLM/HKCU shell`, `Userinit`). O `explorer.exe` permanece o shell do Windows.
2. **Sem Segredos no Versionamento:** Proibido comitar chaves de API, PATs, senhas ou tokens. Configurações MCP devem usar variáveis de ambiente ou endpoints OAuth.
3. **Privilégios Mínimos:** Executar sempre como usuário padrão (`AsInvoker`), nunca elevar para Administrador desnecessariamente.
4. **Monitoramento Ativo:** Nunca aguardar comandos em background sem monitoramento contínuo de status e término.
