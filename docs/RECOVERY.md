# CloudOS — Arquitetura de Recuperação e Segurança (RC1.1)

O CloudOS adota uma arquitetura de recuperação e resiliência multicamadas fundamentada no princípio **GATE 0**:
o Windows Explorer (`explorer.exe`) permanece ininterruptamente como o shell oficial do sistema operacional, e o CloudOS nunca assume persistência destrutiva no Winlogon.

---

## 1. Princípios Fundamentais de Recuperação

1. **Gate 0 Inviolável:**
   - `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell` permanece rigorosamente configurado como `explorer.exe`.
   - `Userinit` permanece o binário oficial: `C:\WINDOWS\system32\userinit.exe,`.
   - A inicialização automática é feita exclusivamente via `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` em modo de usuário.
2. **Supervisor Watchdog (V11/V22):**
   - O processo nativo `CloudOS.Supervisor.exe` monitora o ciclo de vida do Flutter Shell e do System Broker via Job Objects e Named Pipe heartbeat.
   - Em caso de crash súbito do processo de apresentação, o Supervisor registra a falha no journal de recuperação.
3. **Detecção de Crash Loop:**
   - Se 3 falhas ocorrerem em uma janela inferior a 60 segundos, o Supervisor entra em **Modo de Segurança (Safe Mode)**.
   - No Safe Mode, o shell apresenta a interface simplificada de recuperação e desativa restaurações automáticas de janelas que possam ter causado o crash.
4. **Fallback Transparente ao Explorer:**
   - Se o usuário encerrar a sessão do CloudOS ou acionar a restauração de emergência, o Windows Explorer assume a visibilidade completa da área de trabalho sem necessidade de logoff ou reinicialização.

---

## 2. Ferramenta Nativa de Recuperação (`CloudOS.Recovery.exe`)

O utilitário autônomo C++/Win32 `CloudOS.Recovery.exe` não possui dependência de runtime externo (Flutter, .NET ou Electron) e pode ser acionado diretamente pelo terminal ou pelo Gerenciador de Tarefas do Windows:

### Comandos Suportados:

- `CloudOS.Recovery.exe status`
  Retorna o diagnóstico completo em JSON:
  - `status`: Estado atual do shell (`EXPLORER` ou `CANARY`).
  - `effective_shell`: Executável ativo responsável pelo shell.
  - `userinit_intact`: Confirmação booleana da integridade do Userinit.
  - `hklm_winlogon_shell`: Confirmação do shell oficial da máquina.
  - `explorer_running`: Verificação do processo `explorer.exe`.

- `CloudOS.Recovery.exe restore-explorer`
  Força a limpeza imediata de qualquer política per-user e garante que o Windows Explorer seja trazido para o primeiro plano.

- `CloudOS.Recovery.exe safe-mode`
  Ativa a bandeira de inicialização em modo de segurança para diagnosticar falhas de extensões, configurações ou plugins.

- `CloudOS.Recovery.exe reset`
  Restaura as configurações de fábrica do CloudOS, preservando os arquivos pessoais do usuário.

---

## 3. Validação Automatizada de Segurança

O script `scripts/safety/assert-gate0.ps1` é executado antes e depois de qualquer pipeline de build, empacotamento ou teste:

```powershell
pwsh.exe -NoProfile -File scripts\safety\assert-gate0.ps1
```

Se qualquer valor do Registro do Windows desviar do padrão seguro (`effective_shell: explorer.exe`), o script aborta a execução e notifica o operador imediatamente.
