# CloudOS Native Shell V3 — pesquisa de produtividade, recovery e integração

## Objetivo

A fase V3 fecha cinco lacunas que ainda impediam o Shell V2 de se comportar como um desktop environment de uso diário: Snap Assist por arrasto, previews da taskbar, pesquisa real de aplicações instaladas, operações grandes de arquivo/ZIP e recuperação de sessão protegida por watchdog.

A regra arquitetural permanece: o Windows continua fornecendo kernel, DWM, Shell COM, áudio, drivers, segurança e gerenciamento de processos. O CloudOS organiza a sessão usando APIs públicas/documentadas e evita injeção, subclass cross-process e reparenting arbitrário.

## 1. Snap Assist por WinEvent

Fontes primárias:

- https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setwineventhook
- https://learn.microsoft.com/windows/win32/winauto/event-constants
- https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-monitorfromwindow
- https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-getmonitorinfow

`SetWinEventHook` permite observar eventos de acessibilidade/desktop sem injetar uma DLL no processo alvo quando `WINEVENT_OUTOFCONTEXT` é usado. A documentação exige um message loop no thread chamador para a entrega dos eventos out-of-context.

Decisão CloudOS:

- observar `EVENT_SYSTEM_MOVESIZESTART`, `EVENT_SYSTEM_MOVESIZEEND` e `EVENT_OBJECT_LOCATIONCHANGE`;
- nunca subclassificar a titlebar de uma aplicação externa;
- calcular as zonas a partir do `rcWork` do monitor, já descontando AppBars;
- mostrar um overlay `WS_EX_NOACTIVATE | WS_EX_TRANSPARENT` que não rouba input;
- aplicar o encaixe somente ao fim do arrasto;
- suportar metade esquerda/direita, quatro quadrantes, três colunas e 2/3;
- manter o tiling global manual e marcar a janela encaixada como floating dentro desse tiling para os dois modelos não brigarem.

Atalhos durante o arrasto:

- borda esquerda/direita: 50/50;
- cantos: 1/4;
- topo: maximizar;
- Ctrl + topo: coluna esquerda/centro/direita de 1/3 conforme o cursor;
- Ctrl + esquerda/direita: 1/3;
- Shift + esquerda/direita: 2/3.

## 2. Hover previews na Taskbar

Fontes primárias:

- https://learn.microsoft.com/windows/win32/api/dwmapi/nf-dwmapi-dwmregisterthumbnail
- https://learn.microsoft.com/windows/win32/api/dwmapi/nf-dwmapi-dwmquerythumbnailsourcesize
- https://learn.microsoft.com/windows/win32/api/dwmapi/nf-dwmapi-dwmupdatethumbnailproperties
- https://learn.microsoft.com/windows/win32/api/dwmapi/nf-dwmapi-dwmunregisterthumbnail

Decisão CloudOS:

- anexar a funcionalidade ao HWND de cada AppBar via `SetWindowSubclass` apenas dentro do próprio processo CloudOS;
- ao manter o mouse sobre uma tarefa, abrir popup independente `CloudOS.NativeShell.TaskPreview.v1`;
- registrar thumbnail DWM com DwmRegisterThumbnail somente enquanto o preview está visível;
- redimensionar mantendo proporção com `DwmQueryThumbnailSourceSize`;
- clique no preview foca a janela;
- botão fechar envia `WM_CLOSE` à janela;
- destruir a taskbar sempre desfaz o thumbnail e a subclass.

Isso é diferente de capturar screenshots: a miniatura continua sendo composta pelo DWM.

## 3. Start Indexer em background

Fontes primárias:

- https://learn.microsoft.com/windows/win32/shell/knownfolderid
- https://learn.microsoft.com/windows/win32/api/shlobj_core/nf-shlobj_core-shgetknownfolderpath
- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-ienumshellitems
- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nf-shobjidl_core-ishellitem-bindtohandler

O catálogo `kAllApps` do CloudOS não representa todas as aplicações instaladas. O Windows mantém atalhos por usuário em `FOLDERID_Programs`, atalhos comuns em `FOLDERID_CommonPrograms` e uma namespace virtual `shell:AppsFolder` que inclui aplicações empacotadas/registradas.

Decisão CloudOS:

- indexar `FOLDERID_Programs` e `FOLDERID_CommonPrograms` recursivamente;
- aceitar `.lnk`, `.url` e `.exe` presentes nessas árvores;
- enumerar `shell:AppsFolder` com `BHID_EnumItems` / `IEnumShellItems`;
- executar a indexação em `std::thread` separado com COM inicializado naquele thread;
- deduplicar pelo alvo de lançamento;
- combinar resultados do índice Windows com `NativeSearchEngine` dos apps CloudOS;
- fuzzy match simples por subsequência além de exact/prefix/contains;
- F5/Reindexar refaz o índice sem bloquear o popup.

A UI não declara que o índice é o Windows Search Index. É um índice de launchers do CloudOS construído a partir das namespaces públicas acima.

## 4. IFileOperation + progress sink

Fontes primárias:

- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-ifileoperation
- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-ifileoperationprogresssink
- https://learn.microsoft.com/windows/win32/api/shobjidl_core/nf-shobjidl_core-ifileoperation-advise

`IFileOperationProgressSink` é o ponto documentado para receber eventos de uma `IFileOperation`, incluindo início/fim, pré/pós operação e `UpdateProgress`.

Decisão CloudOS:

- `CloudOS.Native.FileOperations.v1` roda cópia/movimentação em worker STA;
- `CLSID_FileOperation` executa copy/move real;
- `IFileOperationProgressSink` atualiza a UI sem bloquear o thread principal;
- `GetAnyOperationsAborted` diferencia cancelamento do sucesso;
- `FOFX_ADDUNDORECORD` pede integração com undo quando suportado;
- o botão Cancelar faz o sink retornar `ERROR_CANCELLED` antes dos próximos itens;
- conclusão publica notificação CloudOS.

## 5. ZIP

O Windows 10/11 distribui `tar.exe`/bsdtar como ferramenta de sistema em instalações modernas. Esta fase usa esse backend para criar e extrair ZIP sem adicionar biblioteca de terceiros ou copiar código de compressão para o repositório.

Decisão CloudOS:

- `tar.exe -a -c -f` para criar ZIP;
- `tar.exe -xf ... -C ...` para extrair;
- processo criado sem console;
- cancelamento encerra somente o processo de archive iniciado pela operação;
- retorno não zero vira erro explícito na UI;
- a interface usa marquee durante ZIP porque o CLI não oferece callback público de percentual compatível com o progress sink de `IFileOperation`.

Limitação declarada: se `tar.exe` não estiver disponível, a operação ZIP falha de forma visível. Isso não é apresentado como uma API Win32 de ZIP.

## 6. Session Recovery

A sessão persistida fica em `%LOCALAPPDATA%\\CloudOS\\session_v3.dat`, escrita por arquivo temporário + `MoveFileExW(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)`. Um marker `session_v3.unclean` existe enquanto a sessão está ativa.

Estado salvo:

- classe HWND;
- título;
- app CloudOS conhecido;
- PID para janela externa ainda viva;
- workspace;
- floating;
- bounds;
- estado normal/maximizado/minimizado.

Política de segurança:

- apps CloudOS conhecidos podem ser relançados;
- janelas externas só têm geometria restaurada se o mesmo PID/class/title ainda existir — o CloudOS não relança executáveis arbitrários descobertos na sessão;
- a janela de operações de arquivos é deliberadamente transitória e nunca é reexecutada automaticamente, para não duplicar copy/move/archive depois de crash;
- snapshots são atualizados periodicamente e antes de suspend/shutdown quando o shell recebe as mensagens de sessão.

## 7. Watchdog

Fontes primárias:

- https://learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw
- https://learn.microsoft.com/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject
- https://learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-openprocess

Decisão CloudOS:

- o processo UI permanece o processo normal que o usuário iniciou;
- depois que a inicialização passa, ele cria uma segunda instância `CloudOS.exe --watchdog <pid>` via `CreateProcessW`;
- o helper abre o PID com `SYNCHRONIZE` e espera com `WaitForSingleObject` no process handle;
- exit code 0 é tratado como saída limpa e não relança;
- exit não zero é tratado como falha e dispara um novo CloudOS depois que HWNDs/AppBars/mutex puderam ser liberados;
- um mutex de sessão impede duas UIs CloudOS simultâneas;
- um segundo launch manual apenas tenta trazer o Desktop existente para frente;
- o mecanismo de reinício antigo continua compatível: a nova instância aguarda o mutex enquanto a anterior fecha;
- não existe loop infinito deliberado: watchdog é iniciado só depois que `Initialize()` do shell passa.

## 8. Lifecycle da sessão Windows

O Desktop CloudOS recebe uma subclass interna do próprio processo, usada apenas para observar:

- `WM_QUERYENDSESSION` — snapshot antes da decisão de logout/shutdown;
- `WM_ENDSESSION` — marca a saída como limpa quando a sessão realmente termina;
- `WM_POWERBROADCAST/PBT_APMSUSPEND` — snapshot antes de suspensão.

Isso não subclassifica aplicações de terceiros.

## Critérios de não regressão V3

O contrato deve falhar se:

- os fontes V3 deixarem de ser compilados;
- Snap Assist perder `SetWinEventHook` ou as zonas de `rcWork`;
- hover preview perder qualquer etapa do ciclo DWM thumbnail;
- Start voltar a pesquisar somente `kAllApps`;
- o indexador perder as duas Known Folders ou `shell:AppsFolder`;
- copy/move deixar de usar `CLSID_FileOperation` + progress sink;
- ZIP deixar de mostrar erro/cancelamento do backend;
- recovery começar a relançar a janela transitória de operações de arquivo;
- watchdog começar antes de `CloudOSApplication::Initialize()` ter sucesso;
- o launcher antigo com `SetParent` voltar ao build;
- tiling automático voltar ao startup.

## Próximas fronteiras depois do V3

Ainda ficam fora deste bloco: integração genérica com a notification area de terceiros, pins arrastáveis/agrupamento completo da taskbar, Snap Layout popup sobre o botão Maximizar de cada janela CloudOS, thumbnails de arquivo no Files, busca de arquivos, tabs, propriedades/ACLs, Wi-Fi/Bluetooth nativos no flyout e integração com sessões de mídia.
