# CloudOS Shell Supervisor V11

## Objetivo

A V11 move a autoridade principal de recuperacao para um processo externo pequeno: `CloudOS.Supervisor.exe`.

O supervisor nao carrega WebView2, nao depende do runtime do CloudOS para decidir se o shell esta saudavel e nao altera o registro do Windows. O executavel reaproveita a base independente de `CloudOS.NativeRecovery`, mantendo tambem uma interface manual de recuperacao em `CloudOS.Supervisor.exe --recovery-ui`.

## Fluxo normal

1. `CloudOS.Supervisor.exe` cria um mutex por sessao para evitar supervisores concorrentes.
2. Ele inicia `CloudOS.exe --supervised` da mesma pasta.
3. O CloudOS continua protegendo a propria instancia com `Local\\CloudOS.NativeShell.Session.v1`.
4. O supervisor espera o health ABI V9 chegar a Ready por ate 30 segundos.
5. Depois de Ready, o supervisor acompanha o handle real do processo e o heartbeat da thread de UI.
6. Saida normal/voluntaria do CloudOS encerra o supervisor sem respawn.

Quando `--supervised` esta presente, o watchdog embutido do `CloudOS.exe` nao e iniciado. Isso deixa apenas uma autoridade de recovery e elimina corrida entre dois loops de restart.

## Readiness e hang

Readiness nao significa apenas processo existente. O supervisor abre `Local\\CloudOS.NativeShell.Health.v9`, valida magic/schema/tamanho de 96 bytes, PID, estado Ready e heartbeat fresco.

- timeout padrao de readiness: 30 segundos;
- timeout padrao de heartbeat: 5 segundos;
- leitura usa o mesmo seqlock do ABI V9 para evitar snapshot rasgado;
- mapping ausente ou heartbeat parado alem do limite e tratado como falha observavel.

Para um shell que nao responde, o supervisor primeiro envia o protocolo `RequestGracefulExitMessage` para `CloudOS.NativeShell.Desktop.v2`. O handler marca ShuttingDown e executa `PostQuitMessage(0)`, permitindo que `CloudOSApplication::Shutdown()` salve checkpoint e destrua os subsistemas normalmente. `TerminateProcess` e usado apenas se esse encerramento nao acontecer dentro do prazo.

## Crash-loop e backoff

Falhas sao limitadas por politica, em vez de reinicio infinito:

- maximo padrao: 3 falhas consecutivas;
- backoff: 500 ms, 1 s, 2 s, limitado a 4 s;
- uma execucao estavel longa reinicia o contador de falhas;
- exit codes normais nao sao classificados como crash depois que Ready foi alcancado.

O modo de CI `--probe-failure-loop` usa `--supervisor-probe-fail`, que termina antes de criar HWND ou estado de sessao. Isso valida o loop de falha sem corromper dados do usuario.

## Fallback seguro para Explorer

Quando o limite de falhas e atingido, a V11 executa fallback conservador:

1. verifica `Shell_TrayWnd`;
2. se Explorer ja estiver atuando como shell, nao inicia outro;
3. caso contrario, resolve `%WINDIR%\\explorer.exe` com `GetWindowsDirectoryW`;
4. inicia o Explorer sem matar processos Windows e sem alterar a configuracao de shell no registro.

O supervisor nunca encerra Explorer e nao altera o registro para tornar Explorer ou CloudOS permanente. O objetivo e devolver uma interface Windows utilizavel quando o CloudOS nao consegue permanecer saudavel.

## Guardas de processo

A interface manual de recovery preserva as verificacoes anteriores:

- caminho da instalacao deve coincidir;
- usuario deve coincidir por SID;
- session id deve coincidir;
- a decisao e a acao usam o mesmo handle, evitando redirecionamento por reutilizacao de PID.

## CI

`run-native-supervisor-smoke-v11.ps1` executa tres verificacoes:

- `--self-test`: invariantes internas e classificacao de exit codes;
- `--probe-ready-once`: o supervisor inicia o CloudOS real, observa Ready, exige pelo menos tres novos heartbeats e solicita shutdown gracioso;
- `--probe-failure-loop`: tres terminacoes anormais deterministicas exercitam restart/backoff e a decisao de fallback. `--probe-no-explorer` impede que o teste abra Explorer quando o runner nao possui shell Explorer.

O smoke tambem exige que nao sobrem mapping de health nem processos CloudOS da instalacao.

## Limite de aceite

O hosted CI valida a implementacao do supervisor, readiness, heartbeat, shutdown gracioso, crash-loop e decisao de fallback. Ele nao prova substituicao permanente do shell do Windows, logon shell customizado ou comportamento de Explorer em todas as politicas corporativas. Esses cenarios continuam sendo testes de VM/hardware antes de qualquer uso como shell de logon.
