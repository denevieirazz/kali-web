# POC1_STAGE2_PLAN.md

## STATUS

**PLANO SOMENTE. NÃO IMPLEMENTADO.**

Nenhuma mudança desta etapa altera a arquitetura da POC 1, instala aplicações, adiciona marketplace, catálogo, App Manager, Browser novo ou compositor novo.

## PRÉ-REQUISITO PARA QUALQUER STAGE 2

Stage 2 só deve começar depois de uma prova física POC1 com resultado mínimo:

```text
xclock real no WSL                       PASSOU
Xpra real                                PASSOU
Xpra HTML5 dentro da CloudOS Window      PASSOU
janela Windows externa do xclock         0
mouse                                    PASSOU
resize                                   PASSOU
stop/cleanup                             PASSOU
screenshot de containment                PRESENTE
```

Sem isso, não há motivo técnico para ampliar o conjunto de aplicações.

## SEQUÊNCIA RECOMENDADA

```text
xclock
  ↓
gedit
  ↓
GIMP
  ↓
Firefox
  ↓
multiple windows / surface mapping
```

A ordem cresce a complexidade de forma controlada.

---

## STAGE 2A — GEDIT

### Por que primeiro

Gedit adiciona comportamento real de desktop sem trazer a complexidade extrema de browser ou edição gráfica pesada:

- teclado;
- seleção de texto;
- clipboard;
- menus;
- diálogo de abrir/salvar;
- transient/modal windows;
- resize frequente.

### Objetivo

Provar que uma aplicação GTK real continua totalmente contida no Xpra HTML5/CloudOS Window quando cria mais de uma janela X11.

### Gates

```text
start                         PASSOU
firstRemoteWindowMs           MEDIDO
teclado                       PASSOU
clipboard in/out              PASSOU
resize                        PASSOU
dialog                        CONTIDO
janela Windows externa        0
stop/cleanup                  PASSOU
```

### Decisão após Gedit

Se menus/dialogs escaparem do iframe, resolver **essa mesma cadeia Xpra** antes de avançar.

Não trocar de arquitetura só para contornar uma falha não diagnosticada.

---

## STAGE 2B — GIMP

### Por que depois de Gedit

GIMP testa uma carga mais exigente:

- múltiplas janelas/dialogs;
- imagens maiores;
- repaint intenso;
- tool windows;
- pointer interactions;
- clipboard de imagem;
- maior pressão de CPU/memória.

### Objetivo

Descobrir o limite prático da POC Xpra/HTML5 para aplicações desktop complexas, ainda sem transformá-las em CloudOS top-level windows individuais.

### Métricas adicionais a observar

```text
bootMs
firstRemoteWindowMs
frame responsiveness visual
CPU backend
CPU WSL/Xpra
memória
reconnectCount
healthFailures
resize latency
```

### Containment

Todos os painéis/dialogs do GIMP devem continuar dentro da área Xpra hospedada na CloudOS Window.

Qualquer top-level Windows externo continua sendo FALHA.

---

## STAGE 2C — FIREFOX

### Por que somente depois

Firefox adiciona:

- processo multiprocess;
- aceleração gráfica;
- vídeo;
- áudio;
- IME/input mais complexo;
- clipboard intenso;
- alta taxa de repaint;
- WebGL;
- possíveis diferenças X11/Wayland.

Ele não deve ser usado para provar o conceito inicial de containment porque mistura muitos subsistemas ao mesmo tempo.

### Objetivo

Medir se o transporte Xpra HTML5 continua utilizável sob uma carga gráfica pesada e interativa.

### Gates

```text
containment                   PASSOU
teclado/mouse                 PASSOU
clipboard                     PASSOU
scroll                        PASSOU
vídeo básico                  AVALIADO
áudio                         AVALIADO
resize                        PASSOU ou ALERTA documentado
reconnect                     SEM LOOP
janela Windows externa        0
```

### Resultado possível

Se Firefox funcionar, Xpra pode continuar sendo um runtime de compatibilidade útil.

Se a experiência ficar lenta, isso não invalida automaticamente containment; separa-se:

```text
viabilidade de containment
vs.
viabilidade de performance para apps pesados
```

---

## STAGE 2D — MULTIPLE WINDOWS

### Situação da POC1

Hoje múltiplas aplicações podem existir simultaneamente como sessões Xpra diferentes dentro do laboratório POC1.

Dentro de uma sessão, o próprio Xpra HTML5 representa suas janelas remotas dentro do iframe.

Isso ainda não significa:

```text
cada janela Linux = uma CloudOS top-level Window
```

### Objetivo futuro

Somente depois que xclock → gedit → GIMP → Firefox tiverem evidência suficiente, estudar a separação de cada janela remota em um objeto gerenciado pelo Window Manager CloudOS.

### Informações que precisam existir antes de implementar

Para cada janela Linux/Xpra:

```text
remote window id
título
geometry
parent/transient id
modal state
mapped/unmapped
min/max size
focus state
app/session id
close lifecycle
```

### Pergunta decisiva

Antes de alterar arquitetura, responder com evidência:

> O Xpra HTML5/protocolo expõe metadados e superfícies de janela em granularidade suficiente para o CloudOS separar cada remote window sem depender do compositor interno do cliente HTML5?

Se SIM, pode existir um Stage 2 surface bridge ainda baseado em Xpra.

Se NÃO, só então reavaliar o caminho de compositor/RAIL descrito na pesquisa de longo prazo.

Nenhuma dessas alternativas é implementada neste plano.

---

## CRITÉRIO DE PROMOÇÃO ENTRE ETAPAS

Não avançar apenas porque o app abriu.

Cada etapa precisa registrar:

```text
containment
start
health
stop
restart
cleanup
input
resize
diálogos aplicáveis
telemetria
screenshots
zero janela Windows externa
```

Uma regressão no containment bloqueia a etapa seguinte.

---

## O QUE NÃO FAZER NO STAGE 2

Não começar por:

- loja;
- catálogo;
- marketplace;
- descoberta automática de aplicações;
- instalador automático;
- SDK;
- App Manager;
- associação de arquivos Linux;
- integração de desktop inteira;
- compositor próprio;
- Browser CloudOS novo.

Primeiro aumentar progressivamente a complexidade do **mesmo containment comprovado**.

## VEREDITO DO PLANO

A evolução correta, se a POC1 física passar, é:

```text
1. consolidar xclock
2. validar input/dialogs com gedit
3. validar desktop complexo com GIMP
4. validar carga gráfica pesada com Firefox
5. estudar granularidade real de multiple windows
```

Somente a evidência dessas etapas deve decidir se Xpra permanece runtime principal de containment, vira runtime de compatibilidade ou é substituído futuramente por uma bridge de superfícies mais direta.
