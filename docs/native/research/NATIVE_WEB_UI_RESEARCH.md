# Pesquisa de referência — Web UI sobre autoridade nativa

Data: 2026-08-29

## Objetivo

Recuperar a qualidade visual do frontend histórico do CloudOS sem restaurar a antiga arquitetura em que a camada web tentava ser o sistema operacional. A regra desta migração é explícita:

> HTML/CSS/React/TypeScript podem apresentar a interface. C++/Win32 continua sendo a autoridade sobre janelas, processos, filesystem, CloudOS Drive, ConPTY, WSL e políticas de segurança.

Programas externos do Windows continuam sendo HWNDs top-level reais. O WebView2 não captura, não reparenta e não incorpora Brave, Explorer, Terminal ou qualquer aplicativo externo.

## Referências pesquisadas

### Microsoft WebView2 — Win32/C++

Fontes oficiais:

- https://learn.microsoft.com/microsoft-edge/webview2/get-started/win32
- https://learn.microsoft.com/microsoft-edge/webview2/concepts/working-with-local-content
- https://learn.microsoft.com/microsoft-edge/webview2/concepts/security
- https://learn.microsoft.com/microsoft-edge/webview2/concepts/performance
- https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution

Decisões aplicadas:

1. usar WebView2 apenas dentro da superfície visual do shell;
2. carregar assets locais por `SetVirtualHostNameToFolderMapping`, sem servidor Node/Vite em produção;
3. usar `PostWebMessageAsJson` / `WebMessageReceived` para o canal UI -> host;
4. validar a origem de toda mensagem recebida;
5. bloquear navegação da superfície do shell para origins que não sejam `https://cloudos.local`;
6. não expor um host object genérico nem um método `exec` para JavaScript;
7. usar o Evergreen WebView2 Runtime e manter fallback para o desktop GDI/Win32 se runtime/assets não estiverem disponíveis.

### MicrosoftEdge/WebView2Samples

Fonte:

- https://github.com/MicrosoftEdge/WebView2Samples

Licença: MIT.

O projeto oficial foi usado como referência de lifecycle para `CreateCoreWebView2EnvironmentWithOptions`, criação do controller, `WebMessageReceived`, resize e shutdown. Nenhum framework de shell externo foi importado.

### Frontend histórico do próprio CloudOS

Fontes internas preservadas:

- `frontend/src/index.css`
- `frontend/src/components/Desktop/`
- `frontend/src/components/StartMenu/`
- `frontend/src/components/Taskbar/`
- `frontend/src/components/Window/`
- `frontend/src/apps/CloudOSFiles/`

O frontend antigo é reutilizado como **biblioteca visual e oracle de produto**, não como autoridade de runtime. A nova entrada `NativeShellSurface` reaproveita design tokens, wallpaper e linguagem visual, mas não importa os stores antigos de process manager, window manager, filesystem, kernel ou serviços HTTP como fonte da verdade.

## Arquitetura

```text
CloudOS.exe (C++ / Win32)
  |
  +-- CloudOSNativeWindowManager --------> HWNDs reais
  +-- NativeAppLauncher -----------------> processos/apps reais
  +-- NativeCloudOSDrive ----------------> storage seguro
  +-- ConPTY / WSL / telemetria nativa
  |
  +-- CloudOSDesktopSurface
       |
       +-- NativeWebViewHost (preferido)
       |     |
       |     +-- https://cloudos.local -> bin/<Config>/ui
       |     +-- React/CSS = apresentação
       |     +-- WebMessage = bridge estreita
       |
       +-- CloudOSNativeDesktopWindow (fallback GDI)
```

## Contrato da bridge inicial

A interface pode solicitar apenas ações nomeadas e validadas, por exemplo:

- `app.launch:<id conhecido>`
- `window.focus:<HWND conhecido>`
- `workspace.switch:<1..4>`
- `tiling.toggle`
- `window.minimize`
- `window.maximize`
- `window.close`
- `window.next`
- `window.snap:left|right`

O C++ publica snapshots de estado com apps, janelas reais, workspace, tiling e telemetria. A UI não inventa processos, janelas ou métricas.

## Regras de segurança

- nenhuma API `exec(command)` genérica;
- nenhuma navegação web arbitrária dentro da superfície do shell;
- mensagens somente de `https://cloudos.local`;
- JavaScript não recebe acesso bruto a Win32, filesystem ou handles;
- toda expansão da bridge deve ganhar método específico, validação e teste de contrato;
- conteúdo remoto deve abrir no navegador real, não transformar a superfície do shell em navegador.

## Build/distribuição

O Vite/TypeScript continua sendo ferramenta de build da interface. O runtime distribuído usa apenas os assets estáticos gerados em `frontend/dist`, copiados para `CloudOS.NativeShell/bin/<Config>/ui`.

Produção não depende de:

- Vite dev server;
- Express para servir a UI;
- `localhost:5173` / `15173`;
- Node.js rodando ao lado do CloudOS.

O pacote nativo `Microsoft.Web.WebView2` é restaurado durante o build C++ e o loader é ligado ao `CloudOS.exe`. O Evergreen WebView2 Runtime permanece pré-requisito de renderização; se ausente, o shell mantém o fallback nativo existente.

## Próxima migração

Depois de estabilizar o desktop híbrido, migrar visualmente os aplicativos em blocos, mantendo cada backend nativo. `CloudOSFiles` é candidato prioritário: preservar seu frontend rico, substituir `OPFS`/facades HTTP pela bridge `NativeCloudOSDrive`/Windows Shell/WSL.

## Estado da implementação

A fundação híbrida foi integrada na branch nativa e esta revisão existe para disparar a validação completa do pipeline: contratos, build estático do frontend, restauração do SDK WebView2, build MSVC x64 e cópia dos assets para o diretório do executável.
