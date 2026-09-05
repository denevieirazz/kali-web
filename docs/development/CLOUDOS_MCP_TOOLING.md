# CloudOS — MCP Development Tooling Architecture & Guidelines

Este documento descreve o ecossistema de **Model Context Protocol (MCP)** configurado para o desenvolvimento do **CloudOS**.

> [!IMPORTANT]
> **MCP é estritamente ferramental de desenvolvimento.**
> Nenhum servidor ou cliente MCP é empacotado no instalador do CloudOS, nem faz parte do runtime de produção do usuário final. O usuário final não necessita de Node.js, Python ou servidores MCP para executar o CloudOS.

---

## 1. Classificação e Inventário de MCPs

| Ferramenta / Servidor | Classificação | Origem / Mantenedor | Função Principal no CloudOS | Escopo / Limites |
| :--- | :--- | :--- | :--- | :--- |
| **Dart / Flutter MCP** | **Official** | Google / Dart Team (`dart mcp-server`) | Análise estática (LSP), testes unitários, Widget Inspector, DTD, hot reload/restart | `desktop/CloudOS.FlutterShell` |
| **Microsoft Learn MCP** | **Official** | Microsoft (`https://learn.microsoft.com/api/mcp`) | Consulta a documentações canônicas de APIs Win32, COM, Core Audio, ConPTY, DPI, UIA | Consultas técnicas para C++/Win32 |
| **GitHub MCP** | **Official** | GitHub / Microsoft (`https://api.githubcopilot.com/mcp/`) | Leitura de repositório remoto, status de CI/Actions, issues, PRs e code security | Somente telemetria e CI remota (Git local roda via shell) |
| **Filesystem MCP** | **Official MCP Server** | Model Context Protocol (`@modelcontextprotocol/server-filesystem`) | Navegação e operações de arquivo dentro do repositório | Restrito estritamente à raiz do repositório CloudOS |
| **Playwright MCP** | **Microsoft Official** | Microsoft (`@playwright/mcp@latest`) | Testes e automação de páginas web no CloudOS Browser | Restrito a páginas web e WebView2 browser (NÃO usado no desktop shell) |
| **Context7** | **Third-party Service** | Upstash (`https://mcp.context7.com/mcp`) | Documentação atualizada de pacotes externos e bibliotecas (pub.dev, C++ libs) | Documentação de terceiros |
| **cua-driver** | **Existing Local Tooling** | Antigravity Native Tooling (`.cua-driver.exe`) | Inspeção física do desktop Windows, árvore UI Automation (UIA), cliques semânticos e screenshots | Desktop Windows real, janelas e controles nativos |
| **Desktop Commander MCP** | **Community / Open Source** | Eduards Ruzga (`@wonderwhy-er/desktop-commander`) | Controle interativo de processos de terminal, busca de código ripgrep e edição cirúrgica por blocos | Operações avançadas de terminal, processos interativos, busca e diffs |
| **Windows Computer Use MCP** | **Community / Open Source** | `windows-computer-use-mcp` | Automação desktop direta (mouse pixel-level, teclado, drag-and-drop, displays, screenshots por região) | Simulação de mouse/teclado físico, atalhos de SO e geometria de telas |

---

## 2. Detalhamento Técnico dos Servidores MCP

### 2.1 Dart / Flutter MCP (Oficial)
* **Comando:** `dart mcp-server` (disponível nativamente no Dart SDK 3.13.2+).
* **Por que usamos:** Permite análise rica do Flutter (`analyze_files`), navegação semântica via LSP, auto-descoberta de erros de runtime, inspeção visual da árvore de widgets via `widget_inspector` e controle de ciclo de vida do app em debug (`hot_reload`, `hot_restart`, DTD).
* **Como testar:** `dart mcp-server --help` ou via ferramenta MCP `analyze_files` / `roots`.
* **Quando NÃO usar:** Não deve ser usado para builds de produção Release nem para empacotamento (`package-cloudos-native.ps1`), onde o pipeline padrão de build em shell permanece a autoridade.

### 2.2 Microsoft Learn MCP (Oficial)
* **Endpoint:** `https://learn.microsoft.com/api/mcp` (HTTP Streamable).
* **Por que usamos:** Garante que qualquer implementação de APIs Windows complexas (DPI, ConPTY, Core Audio, Job Objects, Named Pipes, WTS) utilize assinaturas oficiais e atuais da Microsoft, evitando alucinações de APIs Win32.
* **Como testar:** Consulta a APIs como `WM_DPICHANGED` ou `IFileOperation`.
* **Quando NÃO usar:** Não usar para pacotes Dart/Flutter de terceiros (usar Context7 ou Dart MCP).

### 2.3 GitHub MCP (Oficial)
* **Endpoint:** `https://api.githubcopilot.com/mcp/` (OAuth / Bearer).
* **Por que usamos:** Permite verificar status das GitHub Actions, validar conformidade com branches remotas e auditar logs de CI.
* **Regra de Segurança:** NUNCA armazenar Personal Access Tokens (PAT) em arquivos versionados. Autenticação é resolvida via OAuth ou variável de ambiente.
* **Quando NÃO usar:** Não substitui o `git` local. Commits, diffs, branches locais e status do repositório continuam sendo executados diretamente via Git shell local.

### 2.4 Filesystem MCP (Oficial Model Context Protocol Server)
* **Comando:** `npx -y @modelcontextprotocol/server-filesystem .`
* **Por que usamos:** Provê operações de arquivo padronizadas sob o protocolo MCP.
* **Escopo:** Restrito dinamicamente à raiz atual do CloudOS (`.`). O servidor não tem acesso a diretórios externos (`C:\Windows`, `C:\Users\...\Documents`, etc.).

### 2.5 Playwright MCP (Microsoft Oficial)
* **Comando:** `npx -y @playwright/mcp@latest`
* **Por que usamos:** Testes de páginas web reais carregadas pelo navegador embutido (`CloudOS.Browser`).
* **Restrição Crítica:** O desktop web/React legado foi 100% aposentado. O Playwright MCP **NÃO** deve ser utilizado para inspecionar Desktop, Taskbar, Start Menu ou janelas do shell nativo. Para o shell, utiliza-se exclusivamente `cua-driver` (Windows UIA) e `dart-mcp-server`.

### 2.6 Context7 (Third-Party)
* **Endpoint:** `https://mcp.context7.com/mcp`
* **Por que usamos:** Recuperação de documentação com versionamento correto de pacotes externos do `pub.dev` e bibliotecas C++.
* **Quando NÃO usar:** Para APIs da Microsoft, prefira sempre o **Microsoft Learn MCP**. Para o núcleo do Dart/Flutter, prefira o **Dart MCP**.

### 2.7 cua-driver (Windows UI Automation Nativo)
* **Executável:** `~/.cua-driver/packages/current/cua-driver.exe`
* **Por que usamos:** O CloudOS é um desktop real sobre o Windows. O `cua-driver` se integra diretamente à API COM `IUIAutomationCacheRequest`, inspecionando controles por `AutomationId`, nome acessível, tipo de controle, padrões de ação (`InvokePattern`, `ValuePattern`, `ScrollPattern`) e gerando screenshots de validação física.
* **Auditoria:** Possui árvore semântica UIA completa via `get_window_state`, tornando desnecessário instalar ferramentas adicionais redundantes como `win32-mcp-server`.

### 2.8 Desktop Commander MCP (Community / wonderwhy-er)
* **Comando:** `npx -y @wonderwhy-er/desktop-commander@latest --no-onboarding`
* **Por que usamos:** Oferece controle robusto de processos de terminal interativos (`start_process`, `read_process_output`, `interact_with_process`, `force_terminate`), paginação de saída de processos longos, busca rápida de código com ripgrep (`start_search`, `get_more_search_results`), edição cirúrgica por blocos (`edit_block`) e leitura de arquivos com offset negativo (tail de logs).
* **Como testar:** Handshake JSON-RPC `initialize` (automatizado em `scripts/dev/test-cloudos-mcp-environment.ps1`).
* **Regras de Segurança:** Todo comando disparado pelo Desktop Commander respeita rigorosamente as regras do CloudOS: nunca alterar chaves do Winlogon, não substituir o shell do Windows, não elevar privilégios sem necessidade e manter monitoramento contínuo de tarefas.

### 2.9 Windows Computer Use MCP (Community)
* **Comando:** `npx -y windows-computer-use-mcp`
* **Por que usamos:** Provê automação de baixo nível para controle físico de mouse e teclado no Windows (`mouse_move`, `left_click`, `right_click`, `double_click`, `left_click_drag`, `scroll`, `type`, `key`, `hold_key`, `cursor_position`, `list_running_applications`, `get_frontmost_application`, `open_application`, `list_displays`, `read_clipboard`, `write_clipboard`, `screenshot`, `zoom`).
* **Complementaridade com cua-driver:**
  - `cua-driver` é a autoridade para **inspeção e validação semântica UIA** (por `AutomationId`, acessibilidade e árvore COM);
  - `windows-computer-use` é a ferramenta para **ações físicas diretas de input** (arrastar janelas com drag-and-drop, atalhos combinados de teclas, medição de geometria de displays).
* **Como testar:** Handshake JSON-RPC `initialize` (automatizado em `scripts/dev/test-cloudos-mcp-environment.ps1`).
* **Regras de Segurança:** Ações de teclado e mouse devem ser restritas aos testes em andamento. Proibido acionar sequências que alterem configurações do sistema operacional hospedeiro ou acionem o shell padrão do Windows.

---

## 3. Matriz de Roteamento de Ferramentas (Tool Routing)

```text
Código/Runtime Flutter          → Dart/Flutter MCP (analyze, test, DTD, inspector)
Widgets / Erros de layout       → Dart MCP + cua-driver (UIA físico)
Assinaturas e APIs Windows      → Microsoft Learn MCP (Win32, COM, Shell, DPI)
CI remota / PRs / Actions       → GitHub MCP
Arquivos do projeto             → Filesystem MCP / ferramentas de workspace
Busca ripgrep e diff por blocos → Desktop Commander MCP (start_search, edit_block)
Processos de terminal interativo→ Desktop Commander MCP (start_process, interact_with_process)
Input físico direto / Drag-drop → Windows Computer Use MCP (mouse_move, key, left_click_drag)
Displays / Zoom de tela         → Windows Computer Use MCP (list_displays, zoom, screenshot)
Bibliotecas de terceiros        → Context7
Desktop e Janelas do CloudOS    → cua-driver (UI Automation semântica)
Navegador CloudOS / Web pages   → Playwright MCP
Git local                       → Git shell local
Build C++ e Contratos Nativos   → MSBuild e test-native-contract-suite.ps1
```

---

## 4. Workflow Integrado de Desenvolvimento e Validação Física

O ciclo de vida de desenvolvimento deve seguir este fluxo integrado:

```text
1. Editar código Dart/Flutter ou C++/Win32
   ↓
2. Executar análise estática via Dart MCP (`analyze_files`)
   ↓
3. Executar testes de unidade do Flutter (`desktop/CloudOS.FlutterShell`)
   ↓
4. Iniciar Flutter em modo debug com DTD (`--print-dtd`) se necessário
   ↓
5. Conectar Dart MCP ao processo Flutter para leitura de erros de runtime
   ↓
6. Inspecionar árvore física com `cua-driver:get_window_state` (AutomationId, Bounds, DPI)
   ↓
7. Interagir semanticamente via UIA (InvokePattern / ValuePattern) sem depender de coordenadas cegas
   ↓
8. Capturar screenshot como evidência física de renderização
   ↓
9. Aplicar correções com Hot Reload
   ↓
10. Compilar Release C++ e validar os 48 contratos nativos (`scripts/native/test-native-contract-suite.ps1`)
   ↓
11. Executar Git diff local e verificar integridade
   ↓
12. Consultar status da CI via GitHub MCP
```

---

## 5. Script de Verificação de Saúde do Ambiente

Para verificar se todas as dependências locais de desenvolvimento dos MCPs estão operacionais sem expor credenciais, execute:

```powershell
pwsh -File scripts/dev/test-cloudos-mcp-environment.ps1
```

O script valida:
* Raiz do repositório CloudOS
* Dart SDK e comando nativo `mcp-server`
* Flutter SDK
* Node.js e NPX
* `cua-driver` e árvore UI Automation
* Desktop Commander MCP (handshake JSON-RPC via npx)
* Windows Computer Use MCP (handshake JSON-RPC via npx)
* Integridade dos arquivos de configuração `.agents/mcp_config.json` e `~/.gemini/config/mcp_config.json`
