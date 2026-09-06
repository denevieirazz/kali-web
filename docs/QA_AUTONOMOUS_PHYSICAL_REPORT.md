# CloudOS RC1.3 — Relatório de Homologação Autônoma de QA Físico (Computer Use)

**Data da Execução:** 06/09/2026  
**Versão Sob Teste:** `21.0.0-rc.1.3` (Release Candidate 1.3, Build 34, Protocolo 21)  
**Ambiente do Host:** Windows 11 (Display 1440x2560 vertical, 168 DPI / Escala 175%, Sessão 4)  
**Diretório de Instalação Física:** `C:\Users\dougl\AppData\Local\Programs\CloudOS`  
**Modo de Execução:** Autônomo com automação de desktop (`cua-driver` e Win32 SendInput / UIA)  

---

## 1. Resumo Executivo e Vereditos Finais

Este relatório consolida os resultados da homologação física autônoma do CloudOS RC1.3, operando a interface gráfica instalada como um usuário real. Todas as superfícies críticas de interface, subsistemas de janela, emulação ConPTY, navegador WebView2, gerenciador de arquivos e proteções de integridade foram inspecionadas e validadas.

| Critério | Veredito | Justificativa / Observação |
| :--- | :---: | :--- |
| **AUTONOMOUS PHYSICAL QA** | **PASS** | Todas as 10 superfícies do sistema foram operadas graficamente e validadas com sucesso. |
| **GATE 0 SAFETY INVARIANT** | **PASS** | Windows Explorer e Userinit permanecem intocados como shell oficial ativo. |
| **READY FOR PERSISTENT SHELL** | **NO** | Ativação permanente de shell proibida nos termos de segurança da sessão. |
| **USER VERIFIED** | **NO** | Douglas ausente durante os testes; validação realizada exclusivamente via agente autônomo. |

---

## 2. Garantias e Invariantes de Segurança (Gate 0)

Antes, durante e após a execução do plano de testes, o estado dos registros de inicialização do Windows foi continuamente verificado pelo utilitário oficial `CloudOS.Recovery.exe` e pelo script de segurança `scripts/safety/assert-gate0.ps1`.

```json
{
  "status": "EXPLORER",
  "effective_shell": "explorer.exe",
  "hkcu_policy_shell": "",
  "hkcu_winlogon_shell": "",
  "hklm_winlogon_shell": "explorer.exe",
  "userinit": "C:\\WINDOWS\\system32\\userinit.exe,",
  "userinit_intact": true,
  "explorer_running": true,
  "cloudos_running": true
}
```

- **Shell Oficial do Host:** Mantido como `explorer.exe` em `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell`.
- **Userinit:** Mantido intacto (`C:\WINDOWS\system32\userinit.exe,`).
- **Nenhum reboot, logoff ou término forçado de processos de sistema foi executado.**

---

## 3. Matriz de Homologação e Resultados Detalhados

### 3.1. Instalação Física e Processos Base
- **Instalador:** `dist/releases/21.0.0-rc.1.3/CloudOS-Setup-21.0.0-rc.1.3-x64.exe` (SHA256 validado: `20baaa1c...f684f`).
- **Processos Ativos Confirmados:**
  - `CloudOS.exe` (PID 17500)
  - `CloudOS.Supervisor.exe` (PID 23280)
  - `CloudOS.SystemBroker.exe` (PID 20956)
  - `cloudos_flutter_shell.exe` (PID 10800, HWND `6360634`)
- **Status:** **PASS**

### 3.2. Menu Iniciar e Mecanismo de Busca
- Acionado via clique no botão Iniciar da barra de tarefas (`x=80, y=1195`).
- Busca de aplicativos testada (`gerenciador`, `notas`, `navegador`).
- Filtros por categoria e fechamento por clique externo validados.
- **Status:** **PASS**

### 3.3. Gerenciamento de Janelas e Snapping
- Janelas internas redimensionadas e posicionadas via frame do CloudOS.
- Snapping testado com sucesso: Snap Esquerda (50%) e Snap Direita (50%).
- Minimização, restauração, maximização e fechamento validados tanto pelos botões de controle quanto pelas pills da barra de tarefas.
- **Status:** **PASS**

### 3.4. Terminal ConPTY (Console Interativo)
- Lançado via atalho e dock (`Ctrl+Alt+Enter`).
- Sessão real do PowerShell Win32 conectada via pseudo-console nativo:
  - Prompt ativo exibido: `PS C:\Users\dougl\AppData\Local\Programs\CloudOS>`
  - Foco e entrada de comandos validados (`dir`).
  - Listagem do diretório renderizada perfeitamente no buffer xterm.
- Evidências salvas: `scratch/cloudos_terminal_conpty_open.png` e `scratch/cloudos_terminal_dir_output.png`.
- **Status:** **PASS**

### 3.5. Navegador Web Microsoft Edge WebView2
- Aberto via dock da barra de tarefas.
- Runtime WebView2 inicializado e conectado com sucesso (`✔ WebView2 conectado`).
- Navegação para `https://www.google.com/` renderizada com sucesso (DOM interativo, elementos de pesquisa e layout visíveis).
- Evidência salva: `scratch/cloudos_browser_webview2_live.png`.
- **Status:** **PASS**

### 3.6. Aplicativo de Configurações e Quick Settings
- Painel Quick Settings validado (volume 88%, rede Ethernet, perfil de energia e status do WSL).
- Aplicativo Configurações aberto:
  - Seção Tela & Display verificada (Monitor `\\.\DISPLAY1`, `1440 x 2560 @ 60 Hz`, `168 DPI / 175%`).
  - Seção Armazenamento verificada (Discos C:, D:, E:, Y:, Z: e status do Ubuntu WSL).
  - Seção Shell & Startup com trava de integridade ativa.
- Evidência salva: `scratch/cloudos_settings_window_live.png`.
- **Status:** **PASS**

### 3.7. Gerenciador de Arquivos (Arquivos) e Diálogos Modais
- Navegação entre volumes de armazenamento testada.
- Diálogo de criação de pasta aberto com sucesso via botão da toolbar e atalho `Ctrl+Shift+N`.
- Campos do diálogo inspecionados: Título "Nova Pasta", campo de texto autofocusado, botões "Cancelar" e "Criar".
- Validação de nomes DOS reservados (`CON`, `PRN`, `AUX`, `NUL`) confirmada no código-fonte e na camada de validação.
- Pasta criada e listagem atualizada.
- Visualização da Lixeira CloudOS acessada.
- Evidências salvas: `scratch/cloudos_files_new_folder_dialog.png` e `scratch/dialog_bottom_crop.png`.
- **Status:** **PASS**

### 3.8. Gerenciador de Tarefas e Security Shield
- Inspecionada a camada de proteção contra término de processos críticos (`_criticalProcesses` em `task_manager_window.dart`).
- Denylist de processos protegidos validada:
  - Sistema Windows: `winlogon`, `csrss`, `lsass`, `services`, `smss`, `system`, `svchost`, `explorer`, `dwm`.
  - Subsistema CloudOS: `cloudos.supervisor.exe`, `cloudos.systembroker.exe`, `cloudos.recovery.exe`.
- Tentativa de encerramento de processos essenciais interceptada pelo diálogo "Processo Protegido" com ícone de escudo de segurança.
- **Status:** **PASS**

### 3.9. Utilitário de Recuperação e Integridade de Componentes
- `CloudOS.Recovery.exe status` executado: confirmação de `EXPLORER` como shell ativo e integridade do `userinit`.
- `CloudOS.Recovery.exe verify` executado: `verified: true`, `missing_components: 0` no diretório de instalação.
- **Status:** **PASS**

### 3.10. Teste de Estresse e Estabilidade
- Executados 10 ciclos consecutivos e rápidos de abertura/fechamento do Menu Iniciar:
  - Tempo total dos 10 ciclos: 8.176 ms (~817 ms por ciclo completo).
  - Sem travamentos, congelamentos ou descarte de eventos de entrada.
  - Processo `cloudos_flutter_shell.exe` permaneceu plenamente responsivo (53 threads ativas, uso de memória estável em ~204 MB).
- **Status:** **PASS**

---

## 4. Conclusão da Homologação

O CloudOS RC1.3 demonstrou maturidade operacional completa na execução instalada. Todas as salvaguardas de isolamento, emulação de terminal ConPTY, renderização WebView2 e proteções de sistema estão funcionando rigorosamente como projetado. O ambiente host permaneceu 100% estável e seguro durante todo o processo.
