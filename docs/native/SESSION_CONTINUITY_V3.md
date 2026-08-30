# Session Continuity V3

## Objetivo

Session Continuity V3 adiciona uma camada de continuidade operacional ao shell nativo do CloudOS. Ela trabalha acima do `CloudOSNativeWindowManager` e ao lado do `NativeSessionRecovery` existente.

A responsabilidade é diferente do recovery de boot: o recovery existente relança aplicativos CloudOS reconhecidos quando necessário. O Continuity V3 cria checkpoints recorrentes da geometria e do estado de janelas que já pertencem às quatro áreas, mantém um journal transacional e permite rollback manual ou pós-crash de forma conservadora.

## Arquitetura

### Continuity Ledger

`NativeSessionContinuityStore` persiste `%LOCALAPPDATA%\CloudOS\continuity_v3.dat`.

O formato é binário e versionado (`version = 3`). Ele contém:

- preferências de continuidade;
- última área ativa;
- contador monotônico de checkpoints;
- contador monotônico do journal;
- checkpoints por workspace;
- identidade de janela por processo, classe e título;
- dispositivo do monitor;
- geometria normalizada em escala 0..10000;
- modo flutuante;
- `showCmd` Win32;
- journal de sessão.

A gravação usa arquivo `.tmp`, `FlushFileBuffers`, cópia `.bak` do estado anterior e promoção com `MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH`.

Na leitura, o store rejeita versões, contagens e comprimentos fora dos limites definidos. Se o arquivo principal falhar, tenta `continuity_v3.dat.bak` e registra o recovery do backup no journal.

### Daemon residente

`NativeSessionContinuityService` possui uma janela `HWND_MESSAGE` e timer de 2 segundos. Não instala hook global e não captura teclado por low-level hooks.

O daemon observa:

- workspace atual;
- janela foreground;
- geometria das janelas gerenciadas;
- estado floating;
- show state;
- mudanças relevantes da assinatura de cada workspace.

Um checkpoint automático só é criado quando o intervalo configurado venceu **e** a assinatura da área mudou. Voltar para uma área sem alterar janela alguma não cria cópias idênticas continuamente.

### Crash marker

Enquanto a sessão está viva existe `%LOCALAPPDATA%\CloudOS\continuity_v3.live`.

O marker contém PID e FILETIME da sessão. Em encerramento normal o serviço salva o ledger e remove o marker. Se a execução terminar sem passar pelo encerramento normal, o marker permanece e a próxima sessão é classificada como interrompida.

Se `restore_after_unclean` estiver habilitado, o serviço reaplica o último checkpoint da última área depois que o shell e o window manager já estão operacionais.

### Checkpoints monitor-aware

Cada janela é salva em coordenadas normalizadas relativas à `rcWork` do monitor onde ela estava. O checkpoint também registra o `MONITORINFOEX::szDevice`.

Na restauração:

1. tenta localizar o mesmo device;
2. se ele não existe mais, usa o monitor mais apropriado da janela atual/monitor primário;
3. converte as coordenadas normalizadas para a work area atual;
4. impõe tamanho mínimo para evitar janelas degeneradas;
5. chama `CloudOSNativeWindowManager::RestoreWindowState`.

Isso permite que uma sessão capturada em uma resolução seja reaplicada depois de mudança de resolução, escala ou topologia sem depender de coordenadas absolutas antigas.

### Matching conservador

A restauração não usa somente HWND nem PID, pois ambos são efêmeros entre sessões.

A identidade usa:

- nome do processo;
- classe Win32;
- trecho do título.

Processo incompatível ou classe incompatível elimina o candidato. O título aumenta a pontuação quando corresponde. Cada HWND só pode satisfazer um registro do checkpoint.

O Continuity V3 **não** chama `CreateProcessW`, `ShellExecuteW`, `WinExec` ou mecanismos equivalentes para reviver processo externo. Esse comportamento é intencional. Aplicativos externos existentes podem ser reposicionados; relançamento arbitrário fica fora desta camada.

## Central de Continuidade

A janela `CloudOS.NativeShell.SessionContinuity.Center.v3` é C++/Win32 nativo e usa o WebSkin visual do shell. Não usa WebView2, React nem `SetParent`.

Ela possui quatro páginas.

### Sessão

Mostra as janelas atualmente gerenciadas com:

- workspace nomeado;
- título;
- processo;
- modo flutuante/gerenciado;
- estado normal/maximizado/minimizado.

Duplo clique foca a janela e troca de workspace quando necessário.

Ações:

- salvar agora;
- restaurar último checkpoint da área;
- abrir Workspace Studio.

### Checkpoints

Lista checkpoints do mais recente para o mais antigo com:

- ID;
- data/hora;
- workspace;
- motivo;
- quantidade de janelas.

Ações:

- restaurar selecionado;
- capturar estado atual;
- excluir checkpoints com confirmação.

### Journal

Mantém eventos como:

- início de sessão;
- recovery pós-crash;
- encerramento limpo;
- troca de workspace;
- checkpoint criado/restaurado/falhou;
- mudança de foco;
- alteração de preferências;
- recovery do `.bak`.

O journal é limitado e rotacionado pelo store.

### Preferências

Configura:

- Continuity habilitado/desabilitado;
- autosave automático;
- restauração depois de sessão interrompida;
- retomada da última área ativa;
- journal de foco;
- intervalo mínimo de autosave (5..3600 s);
- retenção por workspace (1..32).

## Hotkeys

O daemon registra as hotkeys com `MOD_NOREPEAT`:

- `Ctrl+Alt+Shift+C`: Central de Continuidade;
- `Ctrl+Alt+Shift+K`: checkpoint manual da área atual;
- `Ctrl+Alt+Shift+L`: restaurar último checkpoint da área atual.

Se outra aplicação já possuir uma combinação, a falha de `RegisterHotKey` não derruba o shell.

## Descoberta pelo Desktop

O menu de contexto da Área de Trabalho contém `Central de Continuidade...` ao lado de `Workspace Studio...` e `Central de Comandos`.

## Integração com Workspace Studio

`NativeWorkspaceLabels` usa os perfis persistidos pelo Workspace Studio como fonte única para o nome das quatro áreas. O Continuity Center e o journal não inventam um segundo conjunto de nomes.

Checkpoints do Continuity são armazenados no ledger de continuidade, separados dos snapshots explícitos do Workspace Studio. A separação é intencional:

- Workspace Studio: layouts que o usuário escolheu preservar como configuração;
- Continuity: histórico rotativo operacional para autosave/rollback.

## Limites deliberados desta versão

- não serializa conteúdo interno de documentos de terceiros;
- não tenta salvar memória de processo;
- não relança executáveis externos arbitrários;
- não substitui Windows Restart Manager;
- não promete restaurar janela que o aplicativo não recriou;
- não altera Shell Launcher/Winlogon;
- não usa reparenting cross-process.

Esses limites mantêm a camada coerente com o modelo atual do CloudOS: um shell/session environment nativo sobre Windows NT, não um kernel nem um hypervisor.
