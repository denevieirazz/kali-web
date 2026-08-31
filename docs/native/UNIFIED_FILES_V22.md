# CloudOS V22 — Unified Files & Open With Architecture

## 1. Visão Geral

A milestone **V22** implementa a integração completa de arquivos unificados (Windows + Linux via WSL2) e o sistema de associações e lançamento de aplicativos (*Open With*) no CloudOS.

O gerenciamento de arquivos do CloudOS é dividido de maneira estrita entre camadas:
1. **Camada de Apresentação (Flutter Shell)**:
   - Gerencia abas (`FilesTabState`), histórico de navegação, estado de seleção e filtros de busca.
   - Fornece visualização fluida em Grade (*Grid*) e Lista (*List*).
   - Renderiza diálogos de criação de pastas, renomeação, propriedades e diálogo modal de *Abrir Com...*.
   - Comunica-se exclusivamente via `MethodChannel` (`invokeBrokerRpc`) com o System Broker nativo.

2. **Camada de Sistema & Segurança (System Broker C++)**:
   - Classe `FileServiceV22` implementa todos os métodos de arquivo executando como usuário padrão (`standard user`).
   - Usa APIs nativas Win32 / Shell COM (`SHGetKnownFolderPath`, `GetLogicalDriveStringsW`, `GetDiskFreeSpaceExW`, `FindFirstFileExW`).
   - Usa `IFileOperation` / `SHFileOperationW` com `FOF_ALLOWUNDO` para deleção segura (Lixeira / Recycle Bin do Windows) e renomeação atômica.
   - Mapeia caminhos UNC de distros Linux (`\\wsl.localhost\<distro>` e `\\wsl$\<distro>`) para caminhos Linux `/home/...` via `wslpath -a -u` seguro.
   - Consulta associações de programas Windows e aplicativos Linux registrados (`AppServiceV21`) para a lista de *Open With*.
   - Executa tarefas assíncronas de longa duração (cópia, movimentação, busca recursiva) através do `JobManagerV21` emitindo eventos no `EventBusV21`.

---

## 2. Roteamento de Métodos IPC (`files.*`)

| Método | Payload | Resposta | Descrição |
|---|---|---|---|
| `files.knownFolders` | `{}` | `{"folders": [...]}` | Lista pastas conhecidas do usuário (Início, Desktop, Documentos, Downloads, Imagens, Vídeos, Músicas, WSL distros). |
| `files.drives` | `{}` | `{"drives": [...]}` | Lista unidades lógicas de disco locais e removíveis com espaço livre e total. |
| `files.list` | `{"path": "...", "sortField": "name", "ascending": true, "showHidden": false}` | `{"items": [...], "totalItems": N, "hasMore": bool}` | Lista itens do diretório com paginação, ordenação e metadados completos. |
| `files.metadata` | `{"path": "..."}` | `{...metadata...}` | Retorna metadados detalhados de um arquivo ou pasta específica. |
| `files.resolvePath` | `{"target": "home"}` | `{"resolved": "C:\\Users\\..."}` | Resolve alvos virtuais (`home`, `desktop`, `documents`) para caminhos físicos absolutos. |
| `files.createFolder` | `{"parentPath": "...", "name": "..."}` | `{"ok": bool}` | Cria nova pasta validando nomes reservados (`CON`, `PRN`, `NUL`, etc.). |
| `files.rename` | `{"path": "...", "newName": "..."}` | `{"ok": bool}` | Renomeia arquivo ou pasta via `IFileOperation`. |
| `files.delete` | `{"paths": [...], "permanent": bool}` | `{"ok": bool}` | Move para a Lixeira do Windows (`permanent=false`) ou exclui permanentemente. |
| `files.copy` | `{"sources": [...], "destination": "..."}` | `{"jobId": "..."}` | Inicia job assíncrono de cópia via `JobManagerV21`. |
| `files.move` | `{"sources": [...], "destination": "..."}` | `{"jobId": "..."}` | Inicia job assíncrono de movimentação via `JobManagerV21`. |
| `files.search` | `{"rootPath": "...", "query": "...", "recursive": true}` | `{"jobId": "..."}` | Inicia busca recursiva assíncrona. |
| `files.open` | `{"path": "..."}` | `{"ok": bool}` | Abre arquivo com o manipulador padrão do sistema operacional. |
| `files.openWith.list` | `{"path": "..."}` | `{"apps": [...]}` | Retorna lista de aplicativos Windows e Linux capazes de abrir o arquivo. |
| `files.openWith.launch` | `{"path": "...", "appId": "...", "platform": "..."}` | `{"ok": bool}` | Lança aplicativo selecionado passando o caminho mapeado corretamente. |

---

## 3. Segurança e Sandboxing

1. **Privilégios de Usuário Padrão**: Todas as ações de manipulação de arquivo rodam na sessão do usuário atual. Nunca solicitam nem utilizam elevação UAC desnecessária.
2. **Sem Comandos Arbitrários**: Proibido uso de `system()`, `cmd.exe /c` ou interpolação crua de strings em shells.
3. **Mapeamento Seguro de Caminhos Linux**: A conversão entre `\\wsl.localhost\Ubuntu\path` e caminhos POSIX é feita com validação rigorosa de escape de argumentos.
4. **Proteção de Nomes Reservados**: Proteção contra criação de nomes de arquivos reservados no Windows (`CON`, `PRN`, `AUX`, `NUL`, `COM1-9`, `LPT1-9`).
