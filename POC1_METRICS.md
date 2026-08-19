# POC1_METRICS.md

## OBJETIVO

Registrar métricas suficientes para responder, durante a prova física, onde o tempo e a instabilidade estão entre:

```text
clique Abrir xclock
  -> readiness
  -> spawn WSL/Xpra
  -> Xpra server saudável
  -> porta alcançável no Windows
  -> HTML5 disponível
  -> WebSocket disponível
  -> iframe carregado
  -> primeira janela remota criada
```

Este arquivo define o contrato de telemetria. Ele não inventa resultados físicos.

## MÉTRICAS DE BACKEND

| Métrica | Definição | Fonte |
|---|---|---|
| `preflightMs` | tempo do readiness WSL+distro+Xpra+app+porta+orphans | runtime manager |
| `wslServerReadyMs` | tempo entre spawn e `xpra info :display` responder | runtime manager |
| `windowsTransportReadyMs` | tempo entre spawn e HTTP Xpra ficar alcançável pelo host Windows | runtime manager |
| `bootMs` | tempo entre spawn e todos os gates de start concluírem, incluindo WebSocket | runtime manager |
| `websocketHandshakeMs` | duração do último handshake WebSocket direto com Xpra | runtime manager |
| `lastHealthMs` | duração da última rodada de health | runtime manager |
| `healthFailures` | health checks classificados como não saudáveis | runtime manager |
| `restartCount` | restarts explícitos da sessão | runtime manager |
| `reconnectCount` | transições degradado -> saudável observadas | runtime/frontend |
| `proxyHttpRequests` | requests HTTP encaminhados pelo capability proxy | proxy |
| `proxyWebSocketConnections` | conexões WebSocket encaminhadas ao Xpra | proxy |

## MÉTRICAS DE FRONTEND

| Métrica | Definição | Fonte |
|---|---|---|
| `iframeLoadMs` | tempo entre atribuição do surface URL e `iframe.onload` | CloudOS Window |
| `firstRemoteWindowMs` | tempo entre ação start/restart e primeira `.window` criada pelo Xpra HTML5 dentro de `#screen` | MutationObserver no iframe |

## O QUE `firstRemoteWindowMs` SIGNIFICA

A implementação do Xpra HTML5 representa cada janela remota com um elemento DOM `.window` e canvas associado.

Assim:

```text
#screen .window apareceu
```

significa que uma janela remota chegou ao cliente HTML5.

Não significa necessariamente que o primeiro repaint do canvas já terminou.

Por isso o relatório físico deve separar:

```text
primeira janela remota detectada automaticamente
primeiro conteúdo visual confirmado por screenshot
```

## HEALTH DETAIL

Cada sessão possui:

### `health.linux`

Executa:

```text
xpra info :<display>
```

Campos úteis:

```text
ok
durationMs
error
```

### `health.windowsTcp`

Conexão TCP do backend Windows para:

```text
127.0.0.1:<xpra-port>
```

### `health.http`

Valida:

- HTTP OK;
- content-type HTML;
- documento contendo identificação Xpra.

Também registra headers de embedding observados no upstream para diagnóstico.

### `health.websocket`

Handshake WebSocket real contra o Xpra.

## CLASSIFICAÇÕES

```text
XPRA_SERVER_UNHEALTHY
XPRA_WINDOWS_LOOPBACK_BLOCKED
XPRA_HTTP_UNAVAILABLE
XPRA_WEBSOCKET_UNAVAILABLE
```

Essas classificações são mais importantes que um único número de latency, pois isolam o boundary quebrado.

## RECONEXÃO

O URL do cliente Xpra usa:

```text
reconnect=yes
```

O runtime também acompanha transições:

```text
ready
-> degraded
-> ready
```

Cada recuperação incrementa `reconnectCount`.

O frontend mantém contagem local equivalente para a sessão ativa e envia o maior valor observado ao backend.

## INTERVALO DE HEALTH

A UI da POC faz health polling aproximadamente a cada 10 segundos para as sessões ativas.

Motivo:

- rápido o suficiente para detectar queda durante a prova;
- não transforma health em tráfego contínuo dominante;
- até quatro sessões continuam com carga pequena.

## TIMEOUTS

### Probe Xpra/app

```text
15 s
```

### Start total por boundary

```text
25 s
```

### Health interno

```text
4 s
```

### TCP/HTTP individual

```text
~1.5 s
```

### WebSocket handshake

```text
~2 s
```

### Stop

```text
~6 s
```

Timeout não aciona instalação nem fallback. O estado vira diagnóstico.

## CAMPOS QUE DEVEM SER CAPTURADOS NA PROVA FÍSICA

Para cada app:

```text
APP:
DISTRO:
XPRA_VERSION:
BOOT_MS:
WSL_SERVER_READY_MS:
WINDOWS_TRANSPORT_READY_MS:
WEBSOCKET_HANDSHAKE_MS:
IFRAME_LOAD_MS:
FIRST_REMOTE_WINDOW_MS:
HEALTH_MS:
RESTART_COUNT:
RECONNECT_COUNT:
HEALTH_FAILURES:
```

## MATRIZ MÍNIMA

### xclock

Obrigatório para primeiro PASS.

Registrar:

- start frio;
- stop;
- restart;
- resize CloudOS Window;
- 2 minutos de estabilidade;
- ausência de janela Windows externa.

### xeyes

Registrar:

- mouse tracking;
- resize;
- coexistência com xclock.

### xterm

Registrar:

- foco;
- teclado;
- clipboard entrada/saída;
- resize.

### gedit

Registrar:

- foco;
- texto;
- clipboard;
- diálogo simples, se disponível;
- coexistência com outra sessão.

## CRITÉRIO DE ALERTA DA POC

Não existe threshold de produção nesta fase.

Usar apenas estas categorias:

### PASSOU

Funcionalidade funciona e não houve quebra de containment.

### ALERTA

Funcionalidade funciona, porém existe latency/reconnect/resize anormal que precisa ser investigado antes da próxima etapa.

### FALHOU

Um gate funcional falhou ou surgiu janela externa.

## CRITÉRIO DE CONTAINMENT

Independentemente das métricas de performance:

```text
qualquer HWND/top-level Windows externo criado pelo app Linux
= FALHOU
```

Mesmo que boot e latency sejam excelentes.

## RESULTADOS ATUAIS

No ambiente CI utilizado anteriormente:

```text
WSL executable          detectado
WSL distro operacional  não disponível
Xpra                     não alcançado
app Linux                não alcançado
```

Portanto as métricas físicas continuam sem valor real nesse ambiente.

O hardening atual permite coletá-las quando a branch for executada no PC físico com os pré-requisitos já presentes.
