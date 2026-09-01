# CloudOS System Broker Security & Threat Model (V21)

## 1. Escopo e Limites de Confiança

O **CloudOS System Broker** (`CloudOS.SystemBroker.exe`) atua como a autoridade de sistema por usuário no Windows. Ele atende requisições vindas da interface Flutter e de utilitários locais autorizados através de IPC nomeado.

### Limite de Confiança (Trust Boundaries)
1. **Cliente IPC (Flutter / Processos da Sessão):** Não confiável para execução arbitrária de código; todas as entradas passam por parsing e validação rigorosa.
2. **System Broker (Processo Per-User):** Confiável para orquestrar serviços do usuário, ler catálogo e delegar chamadas seguras ao Win32.
3. **Outros Usuários / Processos Externos:** Não autorizados a acessar o pipe de comunicação ou o mutex de sessão.

---

## 2. Matriz de Ameaças e Mitigações

| Ameaça | Vetor de Ataque | Mitigação no System Broker V21 |
| :--- | :--- | :--- |
| **Acesso Cruzado de Usuários (Cross-User Access)** | Outro usuário na máquina tenta ler o estado ou lançar apps na sessão da vítima. | **DACL Explícita:** O pipe é criado com descritor de segurança contendo apenas o SID do usuário atual e SYSTEM (`D:(A;;GA;;;<USER_SID>)(A;;GA;;;SY)`). `Everyone` e `Authenticated Users` são bloqueados. |
| **Injeção de Linha de Comando (Arbitrary Command Injection)** | Um cliente malicioso envia strings de comando shell (ex: `calc.exe && rmdir ...`) no payload. | **Zero APIs de Shell Genérico:** O broker não possui `executeCommand` ou `runShell`. Todas as requisições de execução usam identificadores tipados (`windows:notepad`, `wsl:gimp`) mapeados internamente para targets estáticos confiáveis. |
| **Sequestro de Named Pipe (Pipe Squatting / Hijacking)** | Processo antecipa a criação do pipe e escuta no lugar do broker legítimo. | O nome do pipe inclui o SID do usuário e o SessionId da sessão Windows atual, combinados com um Mutex nomeado global de instância única. |
| **Esgotamento de Memória por Mensagens Gigantes (Oversized Payloads)** | Envio de buffer malformado de gigabytes para forçar Out-Of-Memory (OOM). | O broker aplica limite estrito de `kMaxPayloadBytes = 1048576` (1 MiB). Mensagens acima do limite são rejeitadas antes da alocação de buffers adicionais. |
| **Inundação de Eventos (Event Flooding / DoS)** | Slider de volume ou brilho arrastado gera dezenas de eventos por frame. | **Event Coalescing:** O `EventBusV21` unifica atualizações consecutivas de mesmo tipo em fila e limita a profundidade máxima da fila por cliente. |
| **Queda do Broker (Broker Crash / Unavailability)** | Broker encerra inesperadamente devido a erro transitório. | **Resiliência do Cliente:** O `CloudOSBrokerClientV21` e o Flutter entram em estado degradado com fallback gracioso para preview sem congelar ou travar a interface. |

---

## 3. Conformidade com Privilégios Mínimos

* O `CloudOS.SystemBroker.exe` é compilado com `<UACExecutionLevel>AsInvoker</UACExecutionLevel>`.
* Nenhuma operação da V21 requer nem solicita privilégios de Administrador (`SYSTEM` ou `Elevated`).
* Operações com privilégios elevados futuras serão delegadas a um helper isolado (`CloudOS.ElevatedHelper.exe`) sob solicitação explícita do usuário.
