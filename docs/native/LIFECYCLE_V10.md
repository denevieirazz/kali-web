# CloudOS Lifecycle V10

## Objetivo

Lifecycle V10 endurece a continuidade do shell entre mudancas de energia, sessao e topologia de display sem transformar o CloudOS em substituto obrigatorio do Explorer.

Base desta etapa: `work/stability-readiness-v9` / `b618ec52401688ca73c6d621d6aeefed16cd8f68`.

## Implementacao

### Suspend / resume

O desktop nativo autoritativo continua sendo `CloudOS.NativeShell.Desktop.v2`.

Antes de `PBT_APMSUSPEND`, o coordenador V10 reconcilia o Window Manager e grava o checkpoint de Session Continuity.

Os eventos de retorno:

- `PBT_APMRESUMEAUTOMATIC`
- `PBT_APMRESUMECRITICAL`
- `PBT_APMRESUMESUSPEND`

nao executam trabalho pesado diretamente dentro de `WM_POWERBROADCAST`. Eles enfileiram uma revalidacao na thread da UI. A revalidacao reconcilia janelas, reaplica pendencias de recovery, tenta recuperar o registro WTS caso necessario, reaplica work area/AppBars e grava um novo checkpoint.

### WTS / RDP

A base V7 continua registrando `WTSRegisterSessionNotification(..., NOTIFY_FOR_THIS_SESSION)` no HWND do desktop.

Lifecycle V10 acrescenta:

- checkpoint em lock, logoff e disconnect;
- revalidacao enfileirada em unlock, logon e reconnect;
- nova tentativa de registro WTS a cada 30 ticks de 1 segundo quando o registro inicial falhar;
- nenhuma acao em sessoes de outro usuario, porque o registro continua limitado a `NOTIFY_FOR_THIS_SESSION`.

### Display / hotplug

`WM_DISPLAYCHANGE` e `WM_DEVICECHANGE` enfileiram revalidacao. A camada V10 nao inventa resolucao, DPI ou monitor sintetico: ela pede que as superficies nativas consultem novamente o Windows.

As Taskbars recebem `WM_DISPLAYCHANGE` e executam novamente `PositionAppBar()`. O desktop recebe `WM_SETTINGCHANGE / SPI_SETWORKAREA` e atualiza a area de trabalho. O loop principal continua responsavel por detectar mudanca real da assinatura de monitores e reconstruir o conjunto de AppBars quando a topologia mudou.

### Single instance

O contrato existente do mutex `Local\\CloudOS.NativeShell.Session.v1` permanece a autoridade. Uma segunda abertura na mesma sessao deve apenas tentar trazer a instancia existente para frente e encerrar sem substituir o PID publicado pelo Health V9.

## Probe deterministico

`--lifecycle-probe` habilita apenas mensagens privadas usadas pelo teste. Nao desliga seguranca nem muda o comportamento normal do shell.

O smoke `scripts/native/run-native-lifecycle-smoke-v10.ps1` inicia o binario real com:

`--stability-probe --lifecycle-probe`

e valida:

1. readiness e heartbeat V9;
2. segunda instancia encerrando sem substituir a primeira;
3. suspend/checkpoint;
4. resume/revalidate;
5. display/revalidate;
6. session disconnect/checkpoint;
7. session reconnect/revalidate;
8. PID original e heartbeat preservados;
9. `session_v3.dat` presente e estruturalmente nao vazio.

O CI publica `lifecycle-v10-smoke.json` junto do artifact de release.

## Matriz fisica de aceite

O hosted runner nao suspende a VM de maneira equivalente a um notebook real, nao fornece uma sessao RDP controlavel e nao permite hotplug fisico de monitor. Portanto o smoke acima e um teste do handler e das invariantes, nao uma alegacao de cobertura fisica.

Antes de declarar a frente Lifecycle completamente validada em hardware, executar em VM/maquina de teste:

| Transicao | Ciclos minimos | Criterio |
|---|---:|---|
| Suspend -> resume | 5 | Mesmo processo ou recovery esperado; exatamente uma instancia; heartbeat retorna; checkpoint valido |
| Lock -> unlock | 5 | Uma instancia; janelas reconciliadas; nenhum relaunch duplicado |
| RDP connect -> disconnect -> console reconnect | 5 | Uma instancia por sessao; checkpoint preservado; AppBars/work area revalidados |
| Monitor attach -> detach | 5 por monitor | Taskbars correspondem aos monitores atuais; `rcWork` correto; nenhuma AppBar fantasma |
| DPI/topologia apos resume | 5 | Desktop e Taskbars consultam novamente DPI/work area sem geometria antiga |

Logoff/restart real deve continuar restrito a VM de teste porque encerra a sessao do runner/usuario.

## Privacidade

O smoke registra somente PID, contadores de heartbeat, codigos de verificacao e metadados do arquivo de checkpoint (existencia, tamanho e timestamp). Nao grava titulo de janela, documentos, linha de comando, URL, credencial, conteudo de sessao ou dump de memoria.

## Limites

Lifecycle V10 melhora a revalidacao e cria cobertura automatizada repetivel, mas nao transforma um smoke sintetico em teste de firmware, driver, RDP real ou hotplug fisico. O criterio do roadmap permanece: a matriz fisica precisa passar antes de marcar a frente Lifecycle como validada em producao.
