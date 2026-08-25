# PHYSICAL_VALIDATION_READINESS.md

## ESCOPO

Esta revisão prepara exclusivamente a **primeira validação física da POC 1 do CloudOS Linux Runtime**.

Não implementa funcionalidades.
Não altera runtime.
Não altera proxy.
Não altera WebSocket.
Não abre Stage 2.
Não adiciona apps.
Não altera arquitetura.

**Branch auditada:** `poc/cloudos-linux-runtime-xpra`  
**HEAD de código auditado:** `83b17bf92bb493902b4bb6f1186b8066958674d1`  
**Objetivo físico mínimo:**

```text
xclock real no WSL
        ↓
Xpra seamless
        ↓
CloudOS HTTP/WebSocket proxy
        ↓
Xpra HTML5
        ↓
iframe da CloudOS Window
        ↓
zero janela Windows externa do xclock
```

A criação deste arquivo é documentação apenas. O código analisado permanece o mesmo.

---

# RESUMO EXECUTIVO

A POC está **tecnicamente pronta para uma primeira tentativa física controlada**, mas existem condições que precisam ser verificadas manualmente antes de clicar `Abrir XClock`.

O maior ganho para reduzir a probabilidade de um falso fracasso é **não executar o checklist completo de uma vez**.

A primeira execução deve provar somente:

```text
1. pré-requisitos reais
2. xclock
3. Xpra server saudável
4. transporte Windows localhost
5. HTTP proxy
6. WebSocket proxy
7. iframe
8. primeira janela remota
9. ausência de HWND/janela Windows externa
10. Stop
11. confirmação de cleanup
```

Somente depois desse PASS devem ser exercitados:

```text
xeyes
xterm
gedit
multi-app
restart repetido
crash/recovery de backend
orphan recovery provocado
```

Esses testes continuam pertencendo à POC1, mas não devem contaminar a primeira demonstração de containment.

---

# BLOQUEADORES

## B-01 — pré-requisitos do PC físico ainda não foram observados

O CI anterior comprovou apenas:

```text
wsl.exe presente
nenhuma distro WSL operacional no runner
```

Ele não informa o estado do PC físico.

Antes da prova, precisam estar verdes:

```text
WSL                  presente
Distro                presente
Xpra                  presente
xclock                presente
Xpra HTML5            presente
X11 backend do Xpra   presente
```

Se qualquer um estiver ausente:

```text
RESULTADO = BLOQUEADO
```

Não instalar nada durante a prova.

### Gate manual

No PowerShell:

```powershell
wsl.exe -l -v
```

Definir a distro já existente:

```powershell
$distro = 'kali-linux'
```

Usar o nome real se for diferente.

Então:

```powershell
wsl.exe -d $distro -- sh -lc 'command -v xpra && xpra --version'
wsl.exe -d $distro -- sh -lc 'command -v xclock'
```

Não prosseguir se algum comando falhar.

---

## B-02 — `command -v xpra` não prova que o cliente HTML5 está instalado

O readiness atual valida:

```text
command -v xpra
command -v xclock
xpra --version
```

Isso não prova que os componentes necessários para esta POC estejam completos.

No empacotamento Debian atual do projeto Xpra, `xpra-server` possui `xpra-html5` e `xpra-x11` como **Recommends**, não como dependências rígidas.

Portanto é possível existir:

```text
xpra executable = SIM
xpra-html5       = NÃO
```

ou:

```text
xpra executable = SIM
xpra-x11         = NÃO
```

Nesses cenários, o readiness pode passar pelo probe inicial e a falha aparecer somente no start.

### Gate manual obrigatório para Kali/Debian

```powershell
wsl.exe -d $distro -- sh -lc 'dpkg-query -W xpra-server xpra-x11 xpra-html5 2>/dev/null || true'
```

Precisamos observar os componentes efetivamente instalados.

Se Xpra tiver sido instalado por outro método, não assumir equivalência apenas pelo nome do executável; confirmar que a instalação possui servidor X11 e HTML5.

**Não instalar durante a prova.**

Fonte primária consultada durante esta auditoria:

```text
Xpra-org/xpra
packaging/debian/xpra/control
```

---

## B-03 — compatibilidade dos flags Xpra não é validada pelo readiness

A versão física ainda é desconhecida.

A POC usa:

```text
xpra seamless
--start-child
--exit-with-children
--session-name
--bind-tcp
--html=on
--start-new-commands=no
--bind=noabstract
```

O Xpra atual documenta `xpra seamless` como modo de encaminhamento de aplicações individuais e mantém suporte a `start-child` e HTML5, mas a versão instalada na distro física pode ser diferente.

### Gate manual

Antes de abrir CloudOS:

```powershell
wsl.exe -d $distro -- sh -lc "xpra seamless --help 2>&1 | grep -E -- 'start-child|exit-with-children|session-name|bind-tcp|html|start-new-commands'"
```

Se opções essenciais não existirem, registrar:

```text
BLOQUEADO: XPRA_CLI_INCOMPATIBLE
```

`XPRA_CLI_INCOMPATIBLE` é apenas uma classificação do relatório físico; não é um novo errorCode de produto.

---

## B-04 — a POC verifica a porta, mas não verifica previamente colisão do X DISPLAY

O mapeamento atual é determinístico:

```text
14500 -> :100
14501 -> :101
...
14549 -> :149
```

O readiness procura uma porta Windows livre, mas não testa previamente se o display X correspondente já está ocupado por uma sessão Xpra/X11 que não esteja no ledger da POC.

Exemplo:

```text
Windows port 14500 = livre
Xpra display :100  = já ocupado
```

O readiness pode escolher a porta 14500 e o start falhar no Linux.

### Gate manual obrigatório

```powershell
wsl.exe -d $distro -- sh -lc 'xpra list 2>/dev/null || true'
```

Antes da primeira prova, o ambiente ideal é:

```text
nenhuma sessão desconhecida em :100..:149
```

Se houver sessão desconhecida nessa faixa:

```text
NÃO matar automaticamente
NÃO iniciar a POC às cegas
```

Usar um ambiente limpo ou encerrar a sessão somente se sua origem for conhecida.

---

## B-05 — uma sessão órfã antiga deve ser resolvida antes da demonstração

O ledger protege sessões pertencentes à POC, mas a recuperação depende do `ownerId`.

Readiness pode detectar uma entrada órfã de uma CloudOS Window antiga, enquanto o botão `Limpar órfãos` da nova Window envia o `ownerId` atual.

Se o `windowId` mudou após restart, existe a possibilidade de:

```text
readiness detecta órfão antigo
        ↓
cleanup filtrado pelo owner novo
        ↓
entrada antiga não é removida
        ↓
readiness continua bloqueado
```

Isso não afeta uma primeira execução em ambiente limpo.

Para reduzir risco:

```text
começar a prova com xpra list limpo
faixa 14500-14549 limpa
nenhuma mensagem LINUX_POC_ORPHANED_SESSION
```

Se houver orphan antes do primeiro teste, tratar como **BLOQUEADOR DE PREPARAÇÃO**, não como falha de containment.

---

# RISCOS

## R-01 — mismatch de timeout entre frontend e backend

O backend pode gastar:

```text
probe Xpra/app       até 15 s
wait Xpra server     até 25 s
wait Windows path    até 25 s
```

O frontend, porém, usa:

```text
readiness request    timeout padrão ~10 s
start request        40 s
```

Além disso, o frontend faz readiness e o backend repete readiness dentro de `start`.

Em WSL frio, um ambiente válido pode parecer indisponível apenas por timing.

### Mitigação sem código

O checklist já executa comandos WSL antes de abrir a POC. Manter essa ordem.

Antes de abrir CloudOS:

```powershell
wsl.exe -d $distro -- sh -lc 'true'
wsl.exe -d $distro -- sh -lc 'xpra --version && command -v xclock'
```

Isso aquece a distro e reduz muito a chance do primeiro readiness atingir timeout.

Se a UI reportar timeout mas o WSL responder normalmente no terminal, não clicar repetidamente. Esperar alguns segundos, reabrir/atualizar a POC e observar o estado antes de concluir falha.

---

## R-02 — health WebSocket atual testa Xpra diretamente, não a cadeia completa do proxy

O health backend executa handshake em:

```text
ws://127.0.0.1:<xpra-port>/
```

Isso prova:

```text
Xpra aceita upgrade WebSocket direto
```

Não prova automaticamente:

```text
iframe
 -> CloudOS backend
 -> capability path
 -> handleXpraProxyUpgrade
 -> Xpra
```

O proxy WebSocket só é provado de ponta a ponta quando o cliente HTML5 realmente conecta.

Portanto é possível, em teoria:

```text
Health WS = OK
iframe WS = FALHA
```

### Evidência obrigatória na primeira prova

Se houver inspector de rede disponível, confirmar um WebSocket com path semelhante a:

```text
/__cloudos/linux-runtime/poc1/<session>/<capability>/
```

com upgrade bem sucedido.

Se inspector não estiver disponível, usar como prova indireta forte:

```text
proxyWebSocketConnections > 0
+
firstRemoteWindowMs preenchido
+
xclock visualmente presente
```

`proxyWebSocketConnections` sozinho não é suficiente porque hoje ele conta a tentativa antes da confirmação do upstream.

---

## R-03 — health HTTP também testa o Xpra direto, não o proxy completo

`probeHttp()` testa:

```text
Windows backend -> 127.0.0.1:<xpra-port>/
```

A cadeia:

```text
iframe -> CloudOS proxy -> Xpra HTML5
```

é exercitada somente quando o iframe carrega.

Por isso:

```text
HTTP health OK
```

não deve ser usado sozinho como prova de surface readiness.

`iframeLoadMs` + `firstRemoteWindowMs` + screenshot são os gates superiores.

---

## R-04 — Stop não confirma que Xpra terminou antes de apagar a referência

O stop atual:

```text
xpra stop :display || true
        ↓
child.kill() em wsl.exe
        ↓
state = stopped
        ↓
remove session
        ↓
remove ledger reference
```

Erros de `xpra stop` são suprimidos.

Não há post-condition obrigatória como:

```text
xpra info :display deve falhar
porta deve estar fechada
```

Se `xpra stop` falhar e o servidor Linux sobreviver, a POC pode remover o próprio registro antes de confirmar a morte do servidor.

### Mitigação obrigatória na prova

Após Stop:

```powershell
wsl.exe -d $distro -- sh -lc 'xpra list 2>/dev/null || true'
```

E:

```powershell
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -ge 14500 -and $_.LocalPort -le 14549 }
```

O Stop só recebe `PASSOU` se:

```text
display desapareceu
porta desapareceu
CloudOS continua responsivo
```

---

## R-05 — ledger possui falhas silenciosas

`readLedger()` transforma parse/read failure em lista vazia.

`writeLedger()` ignora erros de gravação.

Isso é adequado para não derrubar CloudOS, mas reduz capacidade forense:

```text
ledger corrompido/sem permissão
        ↓
nenhum erro visível
        ↓
recovery de órfão pode ficar cego
```

Para a primeira prova, manter ambiente limpo e não depender do ledger como única evidência de cleanup.

---

## R-06 — logs Xpra são somente memória de processo

stdout/stderr do Xpra são capturados em memória e limitados.

Eles aparecem principalmente quando o start/processo falha.

Não existe nesta POC um log persistente de sessão bem sucedida.

Se ocorrer:

```text
health verde
iframe carregado
nenhuma .window remota
```

os logs disponíveis na UI podem ser insuficientes para explicar o motivo.

### Mitigação

Durante a primeira prova, preservar:

```text
screenshot da UI
Network/Console se disponível
error textual completo
xpra --version
xpra list
métricas mostradas
backend console se estiver visível no fluxo dev
```

Não alterar código durante a prova para obter logs adicionais.

---

## R-07 — `errorCode` pós-readiness pode não chegar à UI

As rotas backend retornam JSON com:

```json
{
  "error": "...",
  "errorCode": "XPRA_...",
  "details": {}
}
```

Porém o `apiClient` geral converte resposta de erro em `Error(message)` e não preserva `errorCode/details` como campos do objeto lançado.

Consequência:

```text
readiness errorCode   normalmente visível
start failure code    pode virar apenas mensagem textual
```

O checklist atual manda registrar exatamente o `errorCode`.

### Mitigação

Se o start falhar depois de `READINESS OK`:

1. não repetir imediatamente;
2. capturar a mensagem inteira da UI;
3. se possível abrir Network/DevTools;
4. registrar o JSON da resposta de `/api/linux-runtime/poc1/start`;
5. preservar `errorCode` e `details` daquela resposta.

Sem esse payload, não inventar o código.

---

## R-08 — `withTimeout` não cancela o probe interno

O helper de timeout usa `Promise.race`.

Quando o timeout externo vence, o loop interno não recebe `AbortSignal` e pode continuar até seu próprio deadline.

Em caso extremo:

```text
outer timeout
 -> start entra em cleanup
 -> probe interno ainda executa por curto período
```

É improvável que isso quebre a primeira prova saudável, mas pode gerar diagnósticos sobrepostos em uma falha de timeout.

Mitigação: após timeout, não clicar Start repetidamente; esperar o estado estabilizar antes de tentar qualquer ação.

---

## R-09 — restart não é uma única operação atômica da fila

`restart` executa conceitualmente:

```text
stop enfileirado
        ↓
start enfileirado
```

Existe uma janela entre as duas operações onde outra chamada externa poderia entrar na fila.

A UI `busy` reduz isso na interação normal, mas fechamento de Window ou chamadas paralelas podem interagir.

Não testar restart na primeira demonstração de containment.

Primeiro obter PASS de xclock + Stop.

---

## R-10 — métricas de proxy contam tentativas, não sucesso confirmado

Hoje:

```text
proxyHttpRequests
proxyWebSocketConnections
```

são incrementadas ao entrar no proxy.

Especialmente `proxyWebSocketConnections` é incrementado antes de o socket upstream confirmar sucesso.

Interpretação correta:

```text
> 0 = houve tentativa pelo path
```

Não:

```text
> 0 = conexão funcional comprovada
```

A prova funcional continua sendo a remote window real.

---

## R-11 — `reconnectCount` não mede diretamente os eventos de reconnect do cliente HTML5

O Xpra HTML5 atual emite eventos de browser como:

```text
connection-established
connection-lost
```

A POC não consome esses eventos diretamente para a métrica.

O contador atual acompanha principalmente:

```text
health degraded -> healthy
```

Assim, um reconnect interno do cliente HTML5 pode não aparecer se os probes diretos do backend permanecerem verdes.

Para a primeira prova:

```text
reconnectCount = indicador de health recovery
```

não um contador exato de reconnects de browser.

---

## R-12 — `iframeLoadMs` não comprova sessão Xpra funcional

`iframe.onload` também pode acontecer quando uma página de erro/redirect termina de carregar.

Portanto:

```text
iframeLoadMs preenchido
```

não significa containment aprovado.

A sequência mínima de evidência é:

```text
iframeLoadMs
+
proxy WS observado
+
firstRemoteWindowMs
+
xclock visual
```

---

## R-13 — `firstRemoteWindowMs` é janela criada, não primeiro pixel

A métrica usa:

```text
#screen .window
```

Ela demonstra que o cliente HTML5 criou a janela remota.

Não garante que o canvas já recebeu o primeiro repaint.

A prova visual continua necessária.

---

## R-14 — multi-app aumenta a superfície de falha sem ajudar a primeira resposta

O checklist completo possui xclock+xeyes, xterm, gedit e recovery de órfão.

Esses testes são úteis, mas não respondem melhor à pergunta inicial:

> Um aplicativo Linux real consegue ficar dentro do CloudOS sem abrir uma janela Windows externa?

Executá-los antes de registrar o primeiro PASS mistura:

```text
containment
input
clipboard
multi-session
restart
recovery
```

### Decisão para a primeira execução

Não iniciar multi-app antes do primeiro xclock PASS.

---

# INCERTO

## I-01 — versão física do Xpra

Ainda desconhecida.

A auditoria verificou o Xpra upstream atual, mas o PC real pode usar outra versão.

Precisamos registrar:

```text
xpra --version
```

antes da prova.

---

## I-02 — versão física do Xpra HTML5

O cliente HTML5 upstream atual usa:

```javascript
const server = getstrparam("server") || window.location.hostname;
const port = getintparam("port") || window.location.port;
const path = getstrparam("path", ...) || window.location.pathname;
...
client.path = path.split("index.html")[0];
```

Isso é compatível com o design atual do capability proxy:

```text
/__cloudos/linux-runtime/poc1/<session>/<token>/
```

porque o WebSocket tende a reutilizar o pathname pelo qual o HTML5 foi carregado.

O próprio Xpra HTML5 também documenta suporte a reverse proxy e parâmetro `path`.

Porém a versão instalada fisicamente pode ser diferente.

Esse comportamento só será definitivamente confirmado quando o primeiro WebSocket do iframe abrir.

Fontes primárias consultadas:

```text
Xpra-org/xpra-html5/html5/index.html
Xpra-org/xpra-html5/docs/Configuration.md
```

---

## I-03 — WSL localhost forwarding / firewall no PC real

A POC consegue distinguir:

```text
Xpra saudável no Linux
Windows TCP falhando
```

mas não consegue atribuir a causa a uma regra específica do firewall.

No PC físico ainda é desconhecido se:

```text
localhost forwarding funciona
networkingMode interfere
firewall interfere
software de segurança interfere
```

Se `XPRA_WINDOWS_LOOPBACK_BLOCKED` aparecer, parar ali e investigar a fronteira de rede; não mudar arquitetura.

---

## I-04 — WebView2/browser permissions para clipboard

Containment visual não depende de clipboard.

Clipboard depende também do contexto do WebView/browser.

Para a primeira prova com xclock:

```text
clipboard NÃO é gate de containment
```

Ele deve ser testado depois, com xterm/gedit, se o primeiro PASS existir.

---

## I-05 — foco/teclado não são bem demonstrados por xclock

xclock é bom para provar pixels e containment, mas fraco para provar teclado.

Não transformar essa limitação em falso fracasso do xclock.

Na primeira prova:

```text
mouse básico / window interaction = observação
teclado                           = não obrigatório
```

Xterm é o teste posterior apropriado dentro da POC1.

---

## I-06 — zero HWND externo só pode ser confirmado fisicamente

O código evita WSLg deliberadamente:

```text
unset DISPLAY
unset WAYLAND_DISPLAY
unset PULSE_SERVER
```

E usa Xpra HTML5 no browser.

Isso reduz fortemente o caminho que criaria janela WSLg.

Mas a afirmação:

```text
janela Windows externa = 0
```

continua exigindo observação real:

```text
Desktop Windows
Alt+Tab
before/after MainWindowHandle
```

Nenhum teste estático substitui isso.

---

# PRONTO

## P-01 — modo Xpra escolhido é coerente com containment HTML5

A documentação upstream atual do Xpra descreve `xpra seamless` como modo de aplicações individuais e afirma explicitamente que, com o cliente HTML5, as janelas encaminhadas permanecem dentro do canvas/browser.

Fonte primária:

```text
Xpra-org/xpra/docs/Usage/Seamless.md
```

Isso está alinhado com o objetivo da POC.

---

## P-02 — caminho WSLg foi removido do start da POC

O comando de start executa:

```text
unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER
```

antes do Xpra.

Também usa:

```text
xpra seamless :<display>
```

em display X dedicado.

O contrato automatizado valida que o comando não contém:

```text
0.0.0.0
WSLg
Weston
RAIL
```

---

## P-03 — listener Xpra é loopback only

A POC usa:

```text
--bind-tcp=127.0.0.1:<port>,auth=allow
```

Não existe bind deliberado em interface externa.

---

## P-04 — capability proxy mantém o HTML5 no origin CloudOS

A surface entregue ao iframe é:

```text
/__cloudos/linux-runtime/poc1/<session>/<token>/
```

O HTTP proxy:

```text
valida session/token
remove Authorization CloudOS
remove Cookie CloudOS
remove Referer/Origin upstream
encaminha somente GET/HEAD
reescreve redirects locais
ajusta frame-ancestors para same-origin
```

O WebSocket usa o mesmo capability path.

---

## P-05 — path do proxy é coerente com o Xpra HTML5 upstream atual

No cliente HTML5 atual, o caminho de conexão é derivado de `window.location.pathname` quando não existe override explícito.

Isso favorece exatamente a forma como a POC serve o cliente dentro do prefixo capability-scoped.

É uma evidência arquitetural forte antes da prova física.

---

## P-06 — readiness separa boundaries úteis

Hoje existem diagnósticos explícitos para:

```text
WSL
Distro
Xpra
app
porta
orphans
Xpra server no Linux
Windows TCP
HTTP
WebSocket
```

Isso é suficiente para não confundir automaticamente:

```text
app ausente
```

com:

```text
rede WSL
```

ou:

```text
WebSocket
```

---

## P-07 — health possui quatro probes independentes

Para sessão ativa:

```text
xpra info :display
Windows TCP
HTTP Xpra
WebSocket Xpra
```

Isso permite localizar a maioria das falhas antes da renderização.

Limitação conhecida: os probes HTTP/WS são diretos contra Xpra e não substituem o teste end-to-end do proxy.

---

## P-08 — primeira remote window é observável

O frontend observa:

```text
#screen .window
```

no iframe Xpra.

Se a versão física do HTML5 for compatível, `firstRemoteWindowMs` oferece uma marca automática de que a janela remota chegou ao browser.

---

## P-09 — código passou os gates automatizados relevantes

No HEAD de código auditado, o workflow POC1 registrou:

```text
npm ci                         PASSOU
Backend POC contract           PASSOU
TypeScript + production build  PASSOU
Backend regression             PASSOU
```

O `CloudOS Workflow Drone` também concluiu com sucesso nesse HEAD.

O job físico do CI permaneceu vermelho porque o runner não possui distro WSL operacional, exatamente como esperado pelo modo fail-closed.

---

## P-10 — o checklist já possui evidência before/after de janelas Windows

A sequência existente registra:

```text
poc1-windows-before.csv
poc1-windows-after.csv
Alt+Tab
screenshot principal
```

`MainWindowHandle` é evidência auxiliar; observação visual/Alt+Tab continua obrigatória.

---

# LACUNAS DE TESTE AUTOMATIZADO

Nenhuma delas será preenchida nesta tarefa porque o pedido atual é preparação sem implementação.

Os testes existentes cobrem principalmente contratos estáticos:

```text
allowlist
comando Xpra
loopback
flags
proxy path parsing
CSP rewrite
redirect rewrite
```

Ainda não existe teste automatizado real para:

```text
lifecycle queue concorrente
start -> stop real
restart real
ledger corrupto
orphan real
HTTP proxy contra upstream real
WebSocket proxy upgrade real
iframe HTML5 real
first remote window real
cleanup pós-stop verificado
```

Esses itens não impedem a tentativa física, mas significam que a primeira máquina real será também o primeiro teste integrado de algumas fronteiras.

---

# LOGS E EVIDÊNCIA QUE NÃO DEVEM FALTAR

Antes da prova:

```text
HEAD.txt / SHA anotado
xpra --version
wsl.exe -l -v
xpra list
lista de listeners 14500-14549
poc1-windows-before.csv
```

Durante:

```text
READINESS
mensagem de erro inteira, se houver
bootMs
websocketHandshakeMs
iframeLoadMs
firstRemoteWindowMs
proxyHttpRequests
proxyWebSocketConnections
health classification
screenshot principal
Network WebSocket 101, se disponível
```

Depois:

```text
poc1-windows-after.csv
Alt+Tab verificado
xpra list após Stop
listeners 14500-14549 após Stop
```

Se qualquer evidência estiver ausente, registrar `NÃO MEDIDO` em vez de inferir.

---

# SEQUÊNCIA RECOMENDADA PARA A PRIMEIRA PROVA

## 1. Confirmar o código

```powershell
git switch poc/cloudos-linux-runtime-xpra
git status --short
git rev-parse HEAD
```

Confirmar que não existem alterações locais inesperadas.

---

## 2. Confirmar WSL/distro e aquecer a distro

```powershell
wsl.exe -l -v
wsl.exe -d $distro -- sh -lc 'true'
```

---

## 3. Confirmar Xpra, HTML5, X11 e xclock

```powershell
wsl.exe -d $distro -- sh -lc 'command -v xpra && xpra --version'
wsl.exe -d $distro -- sh -lc 'command -v xclock'
wsl.exe -d $distro -- sh -lc 'dpkg-query -W xpra-server xpra-x11 xpra-html5 2>/dev/null || true'
```

Se a instalação não for baseada em pacotes Debian, confirmar os componentes por seu método de instalação, sem instalar durante a prova.

---

## 4. Confirmar CLI

```powershell
wsl.exe -d $distro -- sh -lc "xpra seamless --help 2>&1 | grep -E -- 'start-child|exit-with-children|session-name|bind-tcp|html|start-new-commands'"
```

---

## 5. Confirmar displays limpos

```powershell
wsl.exe -d $distro -- sh -lc 'xpra list 2>/dev/null || true'
```

Nenhuma sessão desconhecida em `:100..:149`.

---

## 6. Confirmar portas limpas

```powershell
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -ge 14500 -and $_.LocalPort -le 14549 } |
  Sort-Object LocalPort
```

---

## 7. Capturar baseline Windows

Usar o procedimento já definido em `POC1_PHYSICAL_CHECKLIST.md`.

---

## 8. Iniciar CloudOS

Usar somente o fluxo normal já existente.

Não abrir Xpra em navegador externo.

---

## 9. Abrir Linux Runtime POC 1

Antes de Start:

```text
READINESS OK
wsl           OK
distribution  OK
xpra          OK
app           OK
port          OK
orphans       OK
```

`windowsLoopback` e `websocket` podem permanecer pendentes antes de existir uma sessão live.

---

## 10. Iniciar somente XClock

Não iniciar xeyes/xterm/gedit ainda.

Não clicar Start duas vezes.

---

## 11. Observar a cadeia na ordem

```text
bootMs aparece
health fica saudável
proxy HTTP recebe requests
proxy WS recebe tentativa
iframe carrega
firstRemoteWindowMs aparece
xclock fica visualmente presente
```

Se health estiver verde mas `firstRemoteWindowMs` não aparecer, não declarar PASS. Capturar Network/Console e parar a expansão do teste.

---

## 12. Confirmar containment

PASS somente se simultaneamente:

```text
xclock visível dentro da CloudOS Window
nenhum xclock externo no desktop Windows
nenhum app Linux externo em Alt+Tab
before/after não evidencia nova janela nativa do app
```

Capturar screenshot principal imediatamente após essa confirmação.

---

## 13. Manter estabilidade curta

Após o screenshot inicial, observar por aproximadamente 2 minutos conforme checklist existente.

Não adicionar outros apps nessa janela durante essa etapa.

---

## 14. Executar Stop

Depois verificar obrigatoriamente:

```text
porta fechou
display Xpra sumiu
CloudOS continua responsivo
```

Só então marcar cleanup como PASS.

---

## 15. Encerrar a primeira execução

Se os passos anteriores passaram:

```text
POC1 CONTAINMENT BÁSICO = PASSOU
```

Somente numa segunda rodada da mesma POC1 executar:

```text
xeyes
xterm
gedit
multi-app
restart
orphan recovery provocado
```

---

# CRITÉRIO GO / NO-GO ANTES DE CLICAR `ABRIR XCLOCK`

## GO

Todos:

```text
[ ] branch/SHA corretos
[ ] working tree conhecido
[ ] WSL operacional
[ ] distro operacional
[ ] xpra presente
[ ] xclock presente
[ ] xpra-server completo
[ ] xpra-x11 presente/equivalente
[ ] xpra-html5 presente/equivalente
[ ] flags essenciais reconhecidas
[ ] :100..:149 sem colisão desconhecida
[ ] 14500..14549 sem listener inesperado
[ ] nenhuma orphan warning
[ ] baseline de janelas Windows capturado
```

## NO-GO

Qualquer um:

```text
WSL ausente
Distro ausente
Xpra ausente
xclock ausente
HTML5 ausente
X11 backend ausente
flags incompatíveis
DISPLAY em conflito
orphan não resolvido
ambiente de portas desconhecido
```

Nesse caso o resultado é:

```text
BLOQUEADO
```

Não `NÃO VIÁVEL`.

---

# DECISÃO FINAL

## BLOQUEADORES

Existem **bloqueadores condicionais de ambiente** que precisam ser eliminados pelo preflight físico:

```text
Xpra HTML5 instalado
Xpra X11 backend instalado
CLI compatível
faixa DISPLAY limpa
faixa de portas limpa
sem orphan antigo
```

Nenhum deles exige nova arquitetura.

## RISCOS

Os maiores riscos de execução são:

```text
timeouts com WSL frio
health direto não testar proxy end-to-end
stop sem post-condition de morte
errorCode pós-start pouco visível na UI
ledger/logs silenciosos
reconnect metric incompleta
```

Todos possuem mitigação operacional suficiente para uma primeira prova controlada.

## INCERTO

Só o PC físico pode decidir:

```text
versão real Xpra/HTML5
localhost forwarding/firewall
WebView2 behavior
proxy WebSocket real
primeira remote window real
zero HWND externo
```

## PRONTO

**PRONTO PARA EXECUTAR O PREFLIGHT FÍSICO: SIM.**

**PRONTO PARA CLICAR `ABRIR XCLOCK`: SOMENTE SE TODOS OS GATES GO ESTIVEREM VERDES.**

**CONTAINMENT CERTIFICADO: NÃO — ainda depende da prova física.**

A primeira execução deve ser mantida mínima:

```text
xclock
-> containment
-> screenshot
-> zero janela Windows
-> estabilidade curta
-> stop
-> cleanup confirmado
```

Nada além disso deve ser necessário para responder a pergunta fundamental da POC1.