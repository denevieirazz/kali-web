# CloudOS 21.0.0-rc.1.3 Release Notes

## Resumo do Release Candidate 1.3
O **CloudOS 21.0.0-rc.1.3 (Build 34)** é o marco de congelamento de versão (*Release Freeze*), teste de embebição prolongada (*Soak Test*) e endurecimento contra vazamentos (*Leak Hardening*) antes da homologação final em uso diário pelo usuário. Esta versão elimina causas de degradação contínua (timers zumbis e acumulação de sessões ConPTY), consolida a estabilidade de memória e recursos Win32 sob estresse repetitivo, e prepara o instalador físico definitivo.

---

## Destaques da Versão

### 1. Correções Críticas de Estabilidade e Vazamento de Recursos
- **Settings Window — Eliminação de Timer Exponencial:**
  - **Causa Raiz:** No diálogo de confirmação de reversão de fábrica (`_showRevertConfirmationDialog`), o `Timer.periodic(1 segundo)` era instanciado dentro do `StatefulBuilder.builder`. A cada tick ou reconstrução da interface, um novo timer era alocado sem cancelar o anterior, provocando uma explosão de ticks e alocação desnecessária de memória.
  - **Correção:** O timer foi isolado fora do builder, com ciclo de vida gerenciado estritamente no escopo da função e limpeza forçada via `.whenComplete(() => timer?.cancel())`.
- **ConPTY Manager — Coleta e Reaping de Sessões Zumbis:**
  - **Causa Raiz:** Ao abrir e fechar repetidamente sessões de terminal (`PowerShell`, `CMD`, `WSL`), processos finalizados pelo usuário permaneciam contabilizados no mapa `sessions_` até o limite estático de 32 sessões (`kMaxSessions`), momento em que novas aberturas eram rejeitadas.
  - **Correção:** `CloudOSConptyManager::StartSession` agora executa uma varredura de colheita (*pruning*) de sessões mortas via `WaitForSingleObject(proc, 0) == WAIT_OBJECT_0` e fecha handles órfãos antes de checar o limiar de capacidade.

---

### 2. Resultados da Suíte de Soak e Estresse (3 Minutos + 2.000 Requisições)
A instância compilada e instalada fisicamente em `%LOCALAPPDATA%\Programs\CloudOS RC13 Soak` foi submetida a um ciclo intensivo de estresse e monitoramento periódico (a cada 15 segundos):
- **Memória de Trabalho (Working Set):** Manteve-se estável em ~14.2 MB (delta de `+0.05 MB`).
- **Memória Privada (Private Bytes):** Delta de `-0.23 MB` (sem qualquer vazamento detectado ao longo de todo o soak).
- **Handles Win32:** Redução de `-12` handles (169 -> 157 handles), demonstrando liberação proativa de recursos pelo broker.
- **Threads Ativas:** Convergência saudável de 11 para 5 threads em repouso.
- **Vazão de IPC:** 2.000 requisições sequenciais de ping processadas sem nenhuma falha ou perda de pacote.
- **Concorrência:** 400 consultas simultâneas em 4 threads paralelas concluídas com 100% de sucesso.
- **Proteção Contra Payloads Abusivos:** Rejeição *fail-closed* imediata de frames > 1 MiB e payloads JSON malformados sem desestabilização do processo.
- **Integridade de Armazenamento:** 5 transferências consecutivas de arquivos de 100MB (tempo médio ~31ms por cópia) com verificação bit-a-bit de hash SHA256 e rejeição de nomes de dispositivos DOS (`CON`, `PRN`, `AUX`, `NUL`).
- **Persistência Atômica:** 100 gravações atômicas de preferências via `.tmp` sem corrupção de schema ou fragmentação de dados.

---

### 3. Artefatos Oficiais de Distribuição
- **Instalador Oficial:** `dist/releases/21.0.0-rc.1.3/CloudOS-Setup-21.0.0-rc.1.3-x64.exe`
- **Tamanho:** 11.79 MB (12,367,288 bytes)
- **Hash SHA256:** `20baaa1c693c889dac980d00073bbfec13462a77cb0e76ed980634e4555f684f`
- **Manifesto de Hashes:** `dist/releases/21.0.0-rc.1.3/SHA256SUMS.txt`
- **Feed de Atualização:** `dist/releases/21.0.0-rc.1.3/update-feed.json`
- **Metadados PE VersionInfo:**
  - `ProductName`: `CloudOS`
  - `ProductVersion`: `21.0.0-rc.1.3`
  - `FileVersion`: `21.0.0.34`
  - `Architecture`: `x64`
- **Assinatura:** Declarado como `NotSigned` (Release Candidate não assinado).

---

### 4. Varreduras de Segurança e Integridade
- **OSV Scanner:** Executado sobre o manifesto `desktop/CloudOS.FlutterShell/pubspec.lock` — **0 vulnerabilidades conhecidas**.
- **Gitleaks:** Varredura em toda a árvore de código e histórico — **Sem segredos expostos**.
- **Assert Gate 0:** Windows Explorer permanece o shell primário intocado do Windows (`HKLM\Winlogon\Shell = explorer.exe`), Userinit padrão ativo e nenhuma substituição persistente configurada.

---

### 5. Status de Homologação
- **Pronto para Ativação de Shell Persistente:** **NÃO** (*READY FOR PERSISTENT SHELL ACTIVATION = NO*).
- **Próximo Passo:** Homologação física direta pelo usuário Douglas conforme o roteiro em `docs/RC1_3_USER_QA.md`.
