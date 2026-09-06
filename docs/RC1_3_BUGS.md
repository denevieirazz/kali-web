# CloudOS RC1.3 — Relatório de Diagnóstico e Correção de Defeitos

Este documento registra formalmente as anomalias, vazamentos e comportamentos anômalos identificados e mitigados durante o ciclo de estabilização e congelamento do **CloudOS Release Candidate 1.3 (Build 34)**.

---

## 1. Vazamento Exponencial de Temporizadores em `SettingsWindow`

### Sintoma e Diagnóstico
- **Arquivo Afetado:** `desktop/CloudOS.FlutterShell/lib/features/settings/presentation/settings_window.dart`
- **Causa Raiz:** No diálogo de confirmação de reversão de resolução de tela (`_showRevertConfirmationDialog()`), a chamada de temporizador periódico `_revertTimer = Timer.periodic(const Duration(seconds: 1), ...)` estava instanciada diretamente dentro do closure `builder: (context, setDialogState)` do `StatefulBuilder`.
- **Efeito:** A cada segundo decorrido, ao invocar `setDialogState(() => _revertCountdown--)`, o Flutter executava novamente a função `builder`, criando um novo temporizador concorrente sobreposto. A cada segundo adicional, o número de temporizadores ativos crescia exponencialmente (1 -> 2 -> 4 -> 8...), gerando múltiplos disparos por segundo e vazando memória em fechamento antecipado.
- **Correção Implementada:**
  1. A instanciação do `Timer.periodic` foi movida para fora do builder do diálogo, operando de forma única com callback delegado `updateDialog?.call(() {})`.
  2. Adicionado encerramento forçado do temporizador no callback `.whenComplete(...)` do `showDialog`.
  3. Confirmada a existência do método `dispose()` da classe de estado `_SettingsWindowState` cancelando qualquer temporizador remanescente.
- **Evidência:** 157/157 testes Flutter aprovados; teste de estresse de 100 aberturas e fechamentos de preferências sem vazamentos.

---

## 2. Invocação de Descarte Prematuro em Rotas de Diálogos Efêmeros

### Sintoma e Diagnóstico
- **Arquivos Afetados:** `desktop/CloudOS.FlutterShell/lib/shell/cloudos_shell.dart` e `desktop/CloudOS.FlutterShell/lib/features/files/presentation/files_window.dart`
- **Causa Raiz:** Ao tentar encapsular controladores `TextEditingController` em blocos `try { ... } finally { controller.dispose(); }` logo após o retorno de `await showDialog(...)`, o método `dispose()` era chamado no exato momento do retorno da `Future`. Contudo, no Flutter, a rota de diálogo (`DialogRoute`) ainda permanece montada na árvore durante sua animação de fechamento (`pop animation`, ~200-300ms).
- **Efeito:** Durante os frames de animação de fechamento do diálogo, o `TextField` ainda montado tentava renderizar e registrar listeners no controlador recém-descartado, disparando a asserção do Flutter: `A TextEditingController was used after being disposed`.
- **Correção Implementada:**
  - Preservado o ciclo de vida natural dos controladores locais dos diálogos efêmeros, que são coletados pelo Garbage Collector após o desmonte completo da rota da árvore de widgets, garantindo zero asserções na transição.
- **Evidência:** Execução de `desktop_interaction_test.dart` e `files_production_features_test.dart` com 100% de aprovação.

---

## 3. Gestão de Limite de Sessões no Gerenciador ConPTY

### Sintoma e Diagnóstico
- **Arquivo Afetado:** `desktop/CloudOS.FlutterShell/native_bridge/cloudos_conpty_manager.cpp` e `desktop/CloudOS.FlutterShell/windows/runner/cloudos_conpty_manager.cpp`
- **Causa Raiz:** O método `StartSession` verificava preliminarmente `if (sessions_.size() >= kMaxSessions)` antes de realizar a purga de sessões encerradas (`closing && !is_alive`), fazendo com que sessões de processos que já haviam finalizado permanecessem ocupando slots e impedissem a abertura de novas abas até uma limpeza posterior.
- **Correção Implementada:**
  - Inserido loop de varredura prévia para purgar sessões finalizadas antes da validação do teto máximo de 32 sessões ConPTY simultâneas.
- **Evidência:** 49/49 contratos nativos aprovados, incluindo `test-conpty-stability-v22-contract.ps1`.

---

## 4. Alinhamento de Protocolo Binário no Harness de Teste de Estresse do Broker

### Sintoma e Diagnóstico
- **Componente Afetado:** `scripts/soak-stress` e clientes IPC sintéticos
- **Causa Raiz:** O System Broker V21 implementa enquadramento estrito baseado em prefixo de 4 bytes (uint32 little-endian) com handshake obrigatório `{"protocol":21,"type":"request","id":"...","method":"hello",...}` antes de autorizar requisições RPC. Clientes que enviavam linhas de texto com quebra de linha eram rejeitados por falha de enquadramento.
- **Correção Implementada:**
  - Implementado o conector binário padrão em PowerShell (`BinaryWriter`/`BinaryReader`) respeitando o handshake e serialização nativa do CloudOS V21.
- **Evidência:** 2.000 pings consecutivos processados com 0 erros e vazão contínua em conexão aberta.
