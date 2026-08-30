# CloudOS Stability / Readiness V9

## Objetivo

A V9 transforma a frente de estabilidade do roadmap em uma entrega verificavel:
readiness observavel, heartbeat da thread de UI, deteccao de hang/crash e soak com
orcamentos de crescimento de recursos. Ela nao promete estabilidade de 24 horas sem
que esse ensaio seja realmente executado; o CI faz um smoke curto e o mesmo harness
suporta ensaios longos locais/VM.

## Health ABI em memoria compartilhada

O shell publica `Local\\CloudOS.NativeShell.Health.v9` somente na sessao Windows da
instancia. O bloco possui ABI binario fixo de 96 bytes e schema 9. Campos expostos:

- estado `Starting`, `Ready` ou `ShuttingDown`;
- PID, session ID e thread ID da UI;
- tick de inicio, tick de readiness, tick e contador do heartbeat;
- HWND numerico principal, sem titulo/conteudo;
- quantidade de handles, objetos GDI e USER.

O bloco usa seqlock: `sequence` impar significa escrita em andamento; leitores aceitam
apenas duas leituras com a mesma sequencia par. O evento manual-reset
`Local\\CloudOS.NativeShell.Ready.v9` e sinalizado quando as superficies essenciais
foram criadas e observadas em dois ciclos consecutivos do heartbeat.

O heartbeat roda como `WM_TIMER` no HWND do desktop nativo. Portanto um processo que
continua vivo mas deixa de despachar mensagens deixa o heartbeat envelhecer. Isso
permite distinguir processo existente de UI funcional.

## Superficies exigidas para Ready

A V9 considera o shell pronto quando a thread de UI ja entrou no message loop e as
seguintes superficies first-party existem:

- desktop nativo;
- pelo menos uma Taskbar/AppBar;
- Start;
- Quick Settings;
- Notification Center.

A confirmacao exige dois ticks consecutivos para evitar publicar Ready durante uma
transicao curta de criacao/reconstrucao.

## Stability probe

`CloudOS.exe --stability-probe` executa o shell normal, mas nao inicia o watchdog de
recovery. Isso existe apenas para testes: se o processo falhar, o harness precisa ver
o PID original morrer em vez de um novo shell esconder a falha. Uma inicializacao
normal continua usando o watchdog exatamente como antes.

## Harness de soak

`scripts/native/run-native-soak-v9.ps1` pode iniciar uma instancia isolada ou observar
um PID existente. Depois de Ready, ele coleta somente metadata allowlisted:

- `Responding`;
- CPU;
- working set e private bytes;
- threads e handles;
- handles/GDI/USER publicados pelo health block;
- idade e sequencia do heartbeat.

Falhas detectadas incluem:

- readiness nao atingido dentro do timeout;
- processo encerrado ou PID do health block trocado;
- heartbeat vencido;
- tres amostras consecutivas com janela nao respondendo;
- crescimento acima dos orcamentos configurados;
- CPU media acima do limite quando esse limite e habilitado.

Nenhum titulo de janela, arquivo do usuario, linha de comando de processos, URL,
credencial, conteudo de sessao, dump ou upload entra no relatorio.

## Smoke CI

O workflow Native Full-System deve, depois do build Release x64, iniciar:

```powershell
pwsh -File scripts/native/run-native-soak-v9.ps1 `
  -Launch `
  -DurationSeconds 20 `
  -StartupTimeoutSeconds 30 `
  -HeartbeatTimeoutSeconds 5 `
  -MaxWorkingSetGrowthMB 256 `
  -MaxPrivateGrowthMB 256 `
  -MaxHandleGrowth 512 `
  -MaxGdiGrowth 256 `
  -MaxUserGrowth 256 `
  -MaxThreadGrowth 64
```

O JSON do smoke e publicado junto aos artifacts de CI para auditoria.

## Ensaio de 24 horas

O criterio final do roadmap continua exigindo uma execucao real de 24 horas por
configuracao. Exemplo:

```powershell
pwsh -File scripts/native/run-native-soak-v9.ps1 `
  -Launch `
  -DurationSeconds 86400 `
  -IntervalMilliseconds 5000 `
  -HeartbeatTimeoutSeconds 10 `
  -MaxWorkingSetGrowthMB 256 `
  -MaxPrivateGrowthMB 256 `
  -MaxHandleGrowth 256 `
  -MaxGdiGrowth 128 `
  -MaxUserGrowth 128 `
  -MaxThreadGrowth 32 `
  -MaxAverageCpuPercent 1
```

Esse comando e um criterio de aceite, nao uma alegacao de que o teste ja ocorreu.
Para piloto serio, repetir em configuracoes de monitor/DPI e com apps reais abertos.

## Diagnostico local

`collect-native-diagnostics.ps1` passa a enriquecer cada amostra do processo dono do
health block com estado, heartbeat, GDI, USER e handle count. A politica de privacidade
anterior permanece: metadata local allowlisted e zero upload.

O ZIP portatil inclui o leitor do health block, coletor de diagnostico e harness de
soak para que o mesmo protocolo validado no repositorio acompanhe o build entregue.
