# POC1_RESULTS.md

## RESULTADO EXECUTADO

**Branch:** `poc/cloudos-linux-runtime-xpra`  
**Base:** `stabilization/cloudos-workflow-batch-4`  
**POC:** Xpra + cliente HTML5 + CloudOS Window  

**VEREDITO DA PROVA EXECUTADA: NÃO VIÁVEL**

> Este veredito significa que o critério de sucesso da POC não foi demonstrado no ambiente de execução disponível. Ele **não prova que a arquitetura Xpra/HTML5 é fundamentalmente inviável**; prova que esta execução não chegou ao runtime Linux porque o runner Windows não possui uma distribuição WSL operacional.

## O QUE FOI IMPLEMENTADO

Fluxo implementado:

```text
CloudOS Window: Linux Runtime POC 1
        ↓ API autenticada
/api/linux-runtime/poc1/start
        ↓
wsl.exe -d <distro> -- sh -lc ...
        ↓
Xpra seamless
        ↓
app Linux allowlisted
        ↓
127.0.0.1:14500-14549
        ↓ HTTP/WebSocket
Xpra HTML5 client
        ↓ iframe contido
CloudOS Window
```

A POC não chama WSLg, não abre navegador externo, não usa `Start-Process`, não usa `xdg-open` e não cria um caminho deliberado para HWND externo.

## CONTENÇÃO

A sessão Xpra é construída com:

- `unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER` antes do start, para não herdar automaticamente o display WSLg;
- `xpra seamless` em display X dedicado;
- listener somente em `127.0.0.1`;
- cliente HTML5 servido pelo próprio Xpra;
- iframe dentro do componente `LinuxRuntimePoc`;
- allowlist fixa: `xclock`, `xeyes`, `xterm`, `gedit`;
- nenhuma instalação automática;
- nenhuma execução arbitrária fornecida pelo frontend.

## CI / CONTRATOS

Workflow: `CloudOS Linux Runtime POC 1`.

### PASSOU

- `npm ci`
- contrato backend específico da POC;
- TypeScript + production build;
- regressão backend.

O contrato confirma:

- bind somente `127.0.0.1`;
- `--html=on`;
- modo `xpra seamless`;
- display X explícito;
- remoção de `DISPLAY`, `WAYLAND_DISPLAY` e `PULSE_SERVER` herdados;
- ausência de `apt`, `dnf`, `pacman`, `snap`, `flatpak` ou instalador na POC;
- rejeição de comandos fora da allowlist.

## PROVA FÍSICA

Runner usado: `windows-latest` do GitHub Actions.

Resultado observado:

```text
RESULTADO: BLOQUEADO

O runner possui wsl.exe,
mas não possui uma distribuição WSL operacional.
Nenhuma instalação foi feita porque a POC é fail-closed.
```

Consequência:

```text
wsl.exe                       DETECTADO
WSL distro operacional        NÃO
xpra dentro do WSL            NÃO ALCANÇADO
xclock/xeyes/xterm/gedit      NÃO ALCANÇADO
Xpra HTTP/WebSocket           NÃO INICIADO
iframe com app Linux real     NÃO EXECUTADO
HWND externo                  NÃO MEDIDO
```

O gate físico ficou vermelho de propósito.

## SCREENSHOTS

**Não existe screenshot válido de um aplicativo Linux renderizado dentro do CloudOS nesta execução.**

Gerar uma imagem do estado mockado/idle e apresentá-la como prova seria inválido. A execução física parou antes de existir uma surface Xpra real.

## LATÊNCIA

**NÃO MEDIDA.**

Não houve frame Linux real transportado pelo Xpra HTML5.

## FOCO

**NÃO MEDIDO fisicamente.**

O iframe está configurado para receber interação, mas o comportamento com uma surface Xpra real não foi executado.

## TECLADO

**NÃO MEDIDO fisicamente.**

O cliente HTML5 é carregado com `keyboard=yes`, mas a cadeia CloudOS → iframe → Xpra → app Linux não foi exercitada nesta execução.

## MOUSE

**NÃO MEDIDO fisicamente.**

Não existiu surface Linux real para validar coordenadas, clique ou drag.

## CLIPBOARD

**NÃO MEDIDO fisicamente.**

A URL usa `clipboard=yes` e o iframe permite `clipboard-read; clipboard-write`, porém nenhuma troca real de clipboard foi executada.

## RESIZE

**NÃO MEDIDO fisicamente.**

O iframe ocupa 100% da área de conteúdo da CloudOS Window, mas não houve sessão Xpra real para confirmar a renegociação da geometria.

## ESTABILIDADE

**Código/contratos: PASSOU.**  
**Runtime Linux real: NÃO MEDIDO.**

## ONDE FALHOU

A falha aconteceu **antes do Xpra**:

```text
Windows GitHub runner
   ↓
wsl.exe existe
   ↓
wsl.exe -l -q
   ↓
nenhuma distro operacional
   ↓
POC bloqueada
```

Portanto, nesta execução não há evidência de falha em:

- Xpra seamless;
- Xpra HTML5;
- WebSocket;
- iframe;
- input;
- clipboard;
- renderização CloudOS.

Esses componentes simplesmente não foram alcançados fisicamente.

## O QUE AINDA É NECESSÁRIO PARA UMA PROVA VÁLIDA

Executar a mesma branch em um host Windows que já tenha:

1. WSL2 operacional;
2. uma distro instalada, preferencialmente a distro CloudOS/Kali já existente no ambiente real;
3. `xpra` já presente na distro;
4. um dos apps simples da allowlist já presente.

Sem instalar nada durante o teste, abrir `Linux Runtime POC 1` no CloudOS, iniciar `xclock` ou `xeyes` e verificar:

```text
app Linux visível dentro da Window CloudOS = SIM
janela Windows separada do app          = 0
mouse                                    = funcional
teclado                                  = funcional quando aplicável
resize                                   = funcional
clipboard                                = funcional quando aplicável
```

Somente depois disso o veredito pode mudar para `VIÁVEL`.

## VEREDITO FINAL

# NÃO VIÁVEL

**com base exclusivamente na prova executada**, porque o critério principal — um aplicativo Linux real renderizado integralmente dentro de uma CloudOS Window — não chegou a ser executado no ambiente disponível.

A causa comprovada é infraestrutura do runner (`wsl.exe` sem distribuição operacional), não uma falha demonstrada da arquitetura Xpra/HTML5.
