# CloudOS System Broker & Event Bus (V21)

## 1. Visão Geral e Propósito

A etapa **V21** introduz o **CloudOS System Broker** (`CloudOS.SystemBroker.exe`) e seu barramento de eventos (**Event Bus**), desacoplando a camada de apresentação Flutter do controle nativo do sistema operacional.

```
+--------------------------------------------------+
|                  Flutter UI                      |
| (Desktop / Taskbar / Start / Files / Settings)   |
+--------------------------------------------------+
                       |
                       v
+--------------------------------------------------+
|               CloudOSBridge (Dart)               |
+--------------------------------------------------+
                       |
                       v
+--------------------------------------------------+
|            Flutter Native Bridge C++             |
|                  (Camada Fina)                   |
+--------------------------------------------------+
                       |
            Typed IPC (Named Pipe)
                       |
                       v
+--------------------------------------------------+
|            CloudOS.SystemBroker.exe              |
|                                                  |
| - AppServiceV21       - SystemServiceV21         |
| - WslServiceV21       - JobManagerV21            |
| - EventBusV21         - DiagnosticsV21           |
+--------------------------------------------------+
                       |
                       v
+--------------------------------------------------+
|            Windows / Win32 / WinRT / WSL         |
+--------------------------------------------------+
```

### Divisão de Responsabilidades
1. **Flutter UI:** Apresentação visual, renderização responsiva, animações e widgets.
2. **Flutter Native Bridge C++ (`CloudOSFlutterBridgeV20`):** Adaptador fino do `MethodChannel` para IPC.
3. **CloudOS System Broker (`CloudOS.SystemBroker.exe`):** Autoridade operacional de sistema (catálogo de apps, snapshot de hardware, gerência de jobs, barramento de eventos).
4. **Supervisor V11 (`CloudOS.Supervisor.exe`):** Autoridade externa de integridade e recuperação de processos.

---

## 2. Protocolo de Comunicação IPC (Protocolo 21)

A comunicação entre clientes e o System Broker utiliza **Windows Named Pipes** no padrão:
`\\.\pipe\CloudOS.SystemBroker.v21.<UserSID>.<SessionID>`

### Envelopes de Mensagem

#### 1. Request (Cliente -> Broker)
```json
{
  "protocol": 21,
  "type": "request",
  "id": "req-001",
  "method": "apps.list",
  "payload": {}
}
```

#### 2. Response (Broker -> Cliente)
```json
{
  "protocol": 21,
  "type": "response",
  "id": "req-001",
  "ok": true,
  "payload": {
    "apps": [ ... ],
    "generation": 1
  }
}
```

#### 3. Event (Broker -> Clientes Inscritos)
```json
{
  "protocol": 21,
  "type": "event",
  "event": "system.volumeChanged",
  "payload": {
    "volume": 0.85,
    "generation": 2
  },
  "timestamp": 1788211608359
}
```

---

## 3. Serviços Nativos Integrados

| Serviço | Responsabilidade | Eventos Publicados |
| :--- | :--- | :--- |
| **`AppServiceV21`** | Catálogo unificado de aplicativos (Windows, Linux WSL2, CloudOS), validação de IDs e execução protegida. | `apps.catalogChanged` |
| **`SystemServiceV21`** | Leitura de telemetria de hardware (nome do host, usuário, rede, bateria, volume, brilho). | `system.snapshotChanged`, `system.volumeChanged`, `system.brightnessChanged` |
| **`WslServiceV21`** | Enumeração de distribuições WSL instaladas e verificação de ambiente WSLg. | `wsl.distributionsChanged` |
| **`JobManagerV21`** | Fila de tarefas assíncronas em segundo plano com controle de estados (`Queued`, `Running`, `Completed`, `Failed`, `Cancelled`). | `job.started`, `job.progress`, `job.completed`, `job.failed` |
| **`EventBusV21`** | Gerenciador thread-safe de inscrições com suporte a wildcards (`system.*`), coalescing de eventos rápidos e backpressure. | Todos |
| **`DiagnosticsV21`** | Snapshot seguro de telemetria interna para troubleshooting. | N/A |

---

## 4. Garantias de Segurança e Limites de Autoridade

1. **Zero Comandos Arbitrários:** O protocolo público do broker não expõe métodos como `executeCommand`, `runShell` ou `runPowerShell`. Todo lançamento de aplicativo ocorre por mapeamento de ID estritamente validado.
2. **Single Instance por Sessão de Usuário:** Mutex de sessão nomeado `Global\CloudOS.SystemBroker.Mutex.v21.<SID>.<SessionId>`.
3. **Isolamento de Privilégios:** O broker é executado como processo de usuário comum (`AsInvoker`).
4. **Sem Mutação de Sistema Crítico:** A V21 não altera chaves de registro do Winlogon, não encerra o `explorer.exe` e não executa reboot/logout.
