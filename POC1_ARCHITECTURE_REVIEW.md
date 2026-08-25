# POC1_ARCHITECTURE_REVIEW.md

## ESCOPO

Esta revisão cobre exclusivamente a POC 1 do CloudOS Linux Runtime:

```text
Linux app no WSL
  -> Xpra seamless
  -> HTTP/WebSocket local
  -> bridge/proxy CloudOS
  -> Xpra HTML5
  -> iframe
  -> CloudOS Window
```

Não cobre Batch 5, IA, Browser novo, Productization, marketplace, catálogo, App Manager, GIMP ou Firefox.

## OBJETIVO DE CONTAINMENT

Critério físico:

```text
app Linux real visível dentro de uma CloudOS Window = SIM
janela Windows top-level criada pelo app             = 0
WSLg como display do app                             = NÃO
```

A POC força esse caminho removendo `DISPLAY`, `WAYLAND_DISPLAY` e `PULSE_SERVER` herdados antes do `xpra seamless`. O app recebe o display X virtual criado pelo Xpra e não o display WSLg.

## ARQUITETURA APÓS HARDENING

```text
CloudOS Window (ownerId = windowId)
        |
        | API autenticada
        v
/api/linux-runtime/poc1/*
        |
        v
Xpra POC Runtime Manager
  - readiness
  - start/stop/restart
  - health
  - session map
  - ledger de recovery
  - cleanup
  - métricas
        |
        | wsl.exe -d <distro> -- sh -lc
        v
WSL distro
  xpra seamless :100..:149
  --start-child=<allowlisted app>
  --bind-tcp=127.0.0.1:14500..14549
  --html=on
        |
        | WSL localhost forwarding
        v
Windows 127.0.0.1:<xpra-port>
        |
        | capability-scoped HTTP + WebSocket proxy
        v
/__cloudos/linux-runtime/poc1/<session>/<token>/
        |
        v
Xpra HTML5 dentro do iframe CloudOS
```

## BACKEND

### Readiness

O backend diferencia explicitamente:

- `WSL_NOT_FOUND`: `wsl.exe` ausente/host não compatível;
- `WSL_UNAVAILABLE`: WSL existe, mas não responde;
- `WSL_DISTRO_MISSING`: WSL operacional sem distro;
- `WSL_DISTRO_NOT_INSTALLED`: distro solicitada não existe;
- `XPRA_MISSING`: Xpra ausente na distro;
- `LINUX_POC_APP_MISSING`: xclock/xeyes/xterm/gedit ausente;
- `XPRA_PORT_UNAVAILABLE`: faixa local da POC ocupada;
- `LINUX_POC_ORPHANED_SESSION`: sessão da própria POC sobreviveu ao backend;
- `XPRA_WINDOWS_LOOPBACK_BLOCKED`: Xpra responde dentro do WSL, mas Windows não alcança a porta local;
- `XPRA_HTTP_UNAVAILABLE`: TCP existe ou foi tentado, mas HTML5 não ficou disponível;
- `XPRA_WEBSOCKET_UNAVAILABLE`: HTML responde, mas handshake WebSocket falha.

Readiness bloqueado retorna payload diagnóstico completo; não vira falha silenciosa de transporte da API.

### Runtime manager

A variável única `activeSession` foi substituída por um gerenciador de sessões.

Cada sessão contém:

- `id` aleatório;
- `ownerId` da CloudOS Window;
- app allowlisted;
- distro;
- porta;
- display X;
- capability token para o surface proxy;
- estado;
- processo filho `wsl.exe` enquanto o backend permanece vivo;
- health;
- métricas;
- diagnóstico limitado de stdout/stderr.

Estados relevantes:

```text
starting
ready
degraded
stopping
stopped
failed
```

### Multi-app

A POC aceita somente:

- xclock;
- xeyes;
- xterm;
- gedit.

Até quatro apps distintas podem ficar ativas por CloudOS Window. Cada app recebe porta/display próprios.

O hardening não transforma isso em catálogo. É uma allowlist fixa de teste.

### Serialização de lifecycle

Start/stop/cleanup são serializados por uma fila interna para reduzir corridas como:

```text
start A + start B escolhendo a mesma porta
stop durante start
cleanup concorrente com restart
```

Além disso, a porta escolhida entra em `reservedPorts` antes do spawn.

## BRIDGE HTTP / WEBSOCKET

### Problema anterior

O iframe apontava diretamente para:

```text
http://127.0.0.1:<xpra-port>/
```

Isso criava outra origin e deixava o sucesso do embedding dependente dos headers de segurança emitidos pela versão instalada do Xpra.

### Solução POC1

A API autenticada entrega uma URL capability-scoped:

```text
/__cloudos/linux-runtime/poc1/<sessionId>/<random-token>/
```

O backend:

1. valida session ID + token;
2. aceita apenas sessão `starting`, `ready` ou `degraded`;
3. encaminha GET/HEAD para o Xpra loopback;
4. não encaminha Authorization/cookies CloudOS ao Xpra;
5. remove `X-Frame-Options` do upstream;
6. preserva a CSP do Xpra, substituindo apenas `frame-ancestors` por `'self'`;
7. reescreve redirects de volta para o capability path;
8. encaminha o WebSocket com o mesmo capability path;
9. nunca expõe a porta Xpra em `0.0.0.0`.

O listener Xpra permanece em `127.0.0.1`.

## IFRAME

O iframe usa:

```text
allow-scripts
allow-same-origin
allow-forms
allow-pointer-lock
clipboard-read
clipboard-write
```

`allow-downloads` foi removido porque file transfer está desativado na POC.

Como o cliente Xpra é servido pelo proxy do mesmo origin CloudOS, a POC consegue observar o DOM do cliente HTML5 e detectar a primeira `.window` criada dentro de `#screen`.

Isso fornece uma métrica concreta de primeira janela remota.

### Risco conhecido

`allow-scripts + allow-same-origin` significa que o Xpra HTML5 é tratado como código local confiável desta POC. Isso é aceitável apenas para provar containment com uma instalação local conhecida do Xpra.

Não é a política de isolamento recomendada para Productization.

## WEBSOCKET

Há dois caminhos de WebSocket no mesmo servidor HTTP CloudOS:

```text
/ws/terminal
/__cloudos/linux-runtime/poc1/<session>/<token>/...
```

O servidor agora usa um dispatcher explícito de `upgrade`:

- `/ws/terminal` -> WebSocketServer do Terminal;
- capability path POC1 -> tunnel TCP para Xpra;
- qualquer outro upgrade -> socket encerrado.

Isso evita a possibilidade de o WebSocketServer do Terminal rejeitar o upgrade Xpra antes do bridge.

## HEALTH

Cada health check mede separadamente:

### Linux side

```text
xpra info :<display>
```

Prova que a sessão Xpra responde dentro da distro.

### Windows TCP

Tenta conexão TCP real em:

```text
127.0.0.1:<xpra-port>
```

### HTTP

Busca `/` e exige:

- resposta HTTP OK;
- conteúdo HTML;
- identificação Xpra no documento.

### WebSocket

Executa handshake WebSocket real contra a porta Xpra.

### Classificação

```text
Linux falha
 -> XPRA_SERVER_UNHEALTHY

Linux OK + Windows TCP falha
 -> XPRA_WINDOWS_LOOPBACK_BLOCKED

TCP OK + HTTP falha
 -> XPRA_HTTP_UNAVAILABLE

HTTP OK + WS falha
 -> XPRA_WEBSOCKET_UNAVAILABLE
```

O diagnóstico `XPRA_WINDOWS_LOOPBACK_BLOCKED` não afirma automaticamente que o firewall é a causa. Ele aponta os dois suspeitos objetivos naquele boundary: WSL localhost forwarding/rede e firewall local.

## ORPHANS

### Problema

Um restart do backend destrói o objeto JavaScript, mas pode não destruir imediatamente o Xpra dentro da distro.

### Ledger

A POC grava somente suas próprias sessões em um ledger no temp directory do host.

Campos persistidos:

- id;
- ownerId;
- app;
- distro;
- display;
- porta;
- timestamp.

### Reconciliação

Readiness consulta entradas do ledger que não existem no processo atual e testa:

- `xpra info :display` dentro do WSL;
- porta Windows correspondente.

Se uma entrada própria continuar viva, o start é bloqueado com `LINUX_POC_ORPHANED_SESSION` até `cleanup` explícito.

A POC não mata sessões Xpra desconhecidas fora do seu ledger.

## CLEANUP

Cleanup acontece em quatro pontos:

1. botão explícito de stop;
2. restart (stop seguido de novo start);
3. fechamento real da CloudOS Window;
4. shutdown do backend CloudOS.

### React StrictMode

Unmount em StrictMode pode ocorrer durante a verificação de desenvolvimento sem a janela ter sido realmente fechada.

Para não matar a sessão incorretamente, cleanup por unmount é atrasado em 1 segundo e cancelado se a mesma `windowId` montar novamente nesse intervalo.

## FAIL-CLOSED

Se faltar requisito:

```text
CloudOS continua responsivo
surface iframe não é criada
nenhuma instalação é iniciada
nenhum fallback WSLg ocorre
diagnóstico é mostrado no painel readiness
```

Start só é chamado depois de readiness `ready=true`.

## MULTI-APP NA POC1

A POC 1 agora suporta várias sessões simultâneas, porém **dentro do mesmo aplicativo CloudOS de laboratório**.

A UI usa tabs de sessão:

```text
[XClock ready] [XEyes ready] [XTerm ready] [Gedit ready]
```

Cada tab aponta para um Xpra server próprio.

Isto prova que o manager não está acoplado a um único processo Linux.

Isto ainda não significa:

```text
uma CloudOS top-level Window por wl_surface/X11 window
```

Essa integração pertence ao estágio posterior, não à POC1.

## TELEMETRIA

Backend:

- `preflightMs`;
- `wslServerReadyMs`;
- `windowsTransportReadyMs`;
- `bootMs`;
- `websocketHandshakeMs`;
- `lastHealthMs`;
- health failures;
- restart count;
- reconnect count;
- número de requests HTTP no proxy;
- número de conexões WebSocket no proxy.

Frontend:

- `iframeLoadMs`;
- `firstRemoteWindowMs`.

`firstRemoteWindowMs` mede o intervalo do clique/start até o Xpra HTML5 criar a primeira `.window` em `#screen`.

## PONTOS FRÁGEIS REMANESCENTES

### 1. `auth=allow`

A porta é loopback-only e o acesso do iframe usa capability token no proxy, porém outro processo local pode tentar conectar diretamente à porta Xpra.

Isso é aceitável para a POC física, mas não para Productization.

### 2. Dependência de localhost forwarding do WSL

A arquitetura atual exige que uma porta Linux local seja alcançável pelo host Windows através de localhost forwarding/mirrored networking.

Se o Windows bloquear essa ponte, o health reporta `XPRA_WINDOWS_LOOPBACK_BLOCKED`.

### 3. Versões diferentes do Xpra

A CLI `xpra seamless`, `--html=on`, `--start-new-commands=no` e o HTML5 client precisam existir na versão instalada.

O probe valida Xpra/app, e o start/HTTP/WS gates detectam incompatibilidade subsequente.

### 4. Clipboard de browser

Clipboard depende das permissões do WebView/browser, além do Xpra.

A POC fornece `clipboard-read; clipboard-write`, mas a prova física ainda precisa testar ida e volta.

### 5. Primeira janela não é primeiro pixel

O DOM `.window` prova que o Xpra recebeu/criou uma janela remota. O canvas pode receber seu primeiro repaint alguns milissegundos depois.

Para POC1, `firstRemoteWindowMs` é o indicador automático. A evidência visual continua sendo screenshot físico.

### 6. Várias janelas dentro de uma sessão Xpra

Um app como gedit pode abrir dialog próprio dentro do mesmo cliente Xpra. A POC mantém essas janelas dentro do iframe, mas não as converte em CloudOS top-level windows separadas.

## CONCLUSÃO DA AUDITORIA

O caminho entre:

```text
xclock executa
```

e:

```text
xclock aparece dentro da CloudOS Window
```

agora possui gates explícitos em todas as fronteiras conhecidas:

```text
WSL
-> distro
-> xpra
-> app
-> display/port
-> Xpra server health no Linux
-> Windows localhost transport
-> HTTP HTML5
-> WebSocket
-> capability proxy
-> iframe load
-> primeira Xpra window DOM
```

Nenhum desses gates instala ou substitui dependências automaticamente.

A única prova ainda indisponível neste ambiente é a execução física em um Windows com distro WSL + Xpra + app já presentes.
