# Arquitetura técnica do CloudOS Unified

## Visão geral

O CloudOS é um shell desktop híbrido para Windows. A interface React representa desktop, janelas e aplicativos próprios dentro do WebView2 privilegiado do shell; o agente Node.js conecta a interface aos recursos reais do computador e o host WPF coordena ciclo de vida, janelas nativas e recursos WebView2.

```text
CloudOS.Bootstrap WPF/.NET 8 (recuperação nativa)
    │
CloudOS.Host WPF/.NET 8
    ├── ShellWebView privilegiado
    │   ├── origem fixa https://cloudos.local/
    │   ├── React 19 / TypeScript
    │   ├── bridge JSON v1 allowlisted
    │   └── HTTP/WebSocket para backend efêmero
    │
    ├── BrowserManager
    │   └── BrowserWindow WPF top-level
    │       ├── chrome WPF
    │       └── WebView2CompositionControl por aba
    │           └── conteúdo HTTP/HTTPS externo não confiável
    │
    └── NativeWindowManager / HWND
            │
CloudOS Local Agent (Express, 127.0.0.1, porta efêmera)
    ├── autenticação e primeiro acesso
    ├── inventário Windows / WSL / WSLg
    ├── catálogo opaco de aplicativos
    ├── operações acompanháveis
    ├── PowerShell e terminais WSL reais
    └── broker administrativo sob demanda
```

O fluxo padrão inicia `CloudOS.Host` diretamente. `CloudOS.Bootstrap` continua separado e o modo de substituição do shell do Windows permanece fora desta arquitetura ativa.

## Host desktop

- WPF/.NET 8 e Microsoft Edge WebView2, sem elevação permanente.
- Single-instance por usuário e ativação por named pipe local.
- `CloudOsRuntimeSupervisor` conserva o objeto `Process` iniciado e valida manifesto/health da instância filha.
- Lease autenticada por execução mantém o agente ligado ao host.
- `WebMessageBridge` aceita somente métodos explicitamente allowlisted, valida origem/nonce/handshake e não oferece comando, argv, caminho ou script arbitrário.
- `NativeWindowManager` gerencia HWNDs atribuíveis com foco, estado, fechamento gracioso e containment quando suportado.

## Shell WebView privilegiado

O documento do shell usa origem estável `https://cloudos.local/` e perfil WebView2 em:

```text
%LOCALAPPDATA%\CloudOS\WebView2
```

Somente este WebView recebe:

- `RuntimeBootstrap`;
- `__cloudosNativeNonce`;
- `window.chrome.webview` habilitado;
- `WebMessageBridge`;
- endpoint efêmero do agente CloudOS.

A bridge possui somente operações de host explicitamente definidas. O navegador nativo é aberto pelo método `browser.open`; não existem métodos de browser para executar JavaScript, ler DOM, cookies, headers, arquivos ou comandos nativos. Duas chamadas concorrentes de `browser.open` são serializadas pelo `BrowserManager` e reutilizam a mesma `BrowserWindow`.

## Navegador nativo CloudOS

O aplicativo React `Browser` é apenas um launcher. No Host nativo ele chama `browser.open` e encerra sua janela/processo lógico após a abertura. Em modo web/Vite sem Host ele informa que o Navegador CloudOS requer o Host nativo; não usa `iframe`, `window.open` ou navegador padrão do Windows.

Nesta versão o Browser **não está dentro do Window Manager React**. `BrowserManager` possui uma única `BrowserWindow` WPF top-level por Host. Reabrir o aplicativo restaura/foca a janela existente. A janela contém chrome WPF e até 32 `BrowserTab`, cada uma com `WebView2CompositionControl`; todas as abas compartilham o environment exclusivo do Browser, nunca o do Shell.

### Isolamento de dados e privilégio

O Browser usa:

```text
%LOCALAPPDATA%\CloudOS\Browser\WebView2
%LOCALAPPDATA%\CloudOS\Browser\browser-state.v1.json
```

O UDF do Browser nunca pode ser igual ao UDF do Shell. O Host verifica a separação antes e depois de criar o `CoreWebView2Environment`.

No conteúdo externo:

- `AreHostObjectsAllowed = false`;
- `IsWebMessageEnabled = false`;
- `IsPasswordAutosaveEnabled = false`;
- `IsGeneralAutofillEnabled = false`;
- nenhum RuntimeBootstrap, nonce, JWT, token de supervisor, token de lease ou virtual-host mapping CloudOS é instalado;
- menus de contexto padrão do WebView ficam desabilitados; o chrome usa menus WPF próprios;
- DevTools ficam desabilitados por padrão e só podem ser ativados pelo opt-in explícito `CLOUDOS_BROWSER_DEVTOOLS=1` em desenvolvimento.

CDP remoto não é configurado pelo Browser de produção. O `CloudOS.Browser.TestHost` usa CDP somente em processo de teste com UDF temporário.

### Navegação e URL policy

A barra de endereço é WPF. A policy pura `BrowserPolicy`:

- aceita HTTP/HTTPS;
- converte domínio sem esquema para HTTPS;
- usa HTTP para `localhost`, IPv4 loopback e IPv6 loopback;
- converte texto comum em pesquisa DuckDuckGo;
- normaliza IDN e exibe hostname em forma ASCII/punycode;
- rejeita userinfo, controles, CR/LF/NUL e entradas acima de 8192 caracteres;
- permite `about:blank` somente internamente;
- permite `data:`/`blob:` somente quando originados por conteúdo já carregado e nunca pela barra de endereço;
- bloqueia `file:`, `ftp:`, `javascript:`, `vbscript:`, `shell:`, `cmd:`, `powershell:`, `ms-settings:`, `ms-appx:`, `edge:`, `chrome:`, `devtools:`, `view-source:` e esquemas desconhecidos;
- bloqueia `https://cloudos.local`, trailing-dot equivalente e a origem efêmera do backend, incluindo aliases loopback na mesma porta;
- cancela `LaunchingExternalUriScheme` e não usa `ShellExecute`.

Back/Forward/Stop/Reload usam o histórico e APIs nativas do próprio WebView2. `NewWindowRequested` recebe um WebView2 de nova aba e não abre uma janela Edge externa.

### Abas e experiência

O Browser implementa:

- criar, fechar, trocar, duplicar e reabrir aba fechada;
- fixar/desafixar abas;
- mute por aba e indicador de áudio;
- nova aba CloudOS renderizada por WPF, não por HTML privilegiado;
- restauração opcional da última sessão;
- busca em histórico e favoritos;
- indicador HTTP/HTTPS;
- zoom de 25% a 500%;
- tela cheia WPF;
- impressão e Save Page quando suportados pelo WebView2;
- barra de progresso visual durante navegação;
- atalhos `Ctrl+L`, `Ctrl+T`, `Ctrl+W`, `Ctrl+Shift+T`, `Ctrl+Tab`, `Ctrl+Shift+Tab`, `Alt+Left`, `Alt+Right`, `Ctrl+R`, `Esc`, `Ctrl++`, `Ctrl+-`, `Ctrl+0` e `F11`.

A restauração de sessão não restaura POST bodies, formulários, comandos, credenciais ou cookies pelo JSON. Cookies/cache continuam pertencendo somente ao UDF WebView2.

### Downloads

`BrowserDownloadManager` intercepta `DownloadStarting`, exige destino escolhido pelo usuário via `SaveFileDialog` na produção, mantém confirmação de sobrescrita e acompanha `BytesReceivedChanged`/`StateChanged`. Arquivos baixados nunca são executados ou abertos automaticamente.

Enquanto houver downloads ativos, o chrome WPF mostra `Cancelar downloads`, que cancela todas as operações em andamento. Ao fechar o Browser com downloads ativos, o usuário precisa confirmar; durante shutdown do Host o cancelamento é direto e sem prompt.

O TestHost injeta somente um seletor de destino para diretório temporário, sem alterar o comportamento de produção e sem expor API para páginas externas.

### Permissões, certificados e autenticação HTTP

Permissões suportadas com prompt WPF: câmera, microfone, localização, notificações e downloads automáticos múltiplos. Todas as decisões usam `SavesInProfile = false`; permissões não suportadas são negadas por padrão e o prompt expira em 30 segundos. A origem é revalidada depois da decisão; mudança de scheme/host/port nega a permissão.

Erros TLS recebem sempre `CoreWebView2ServerCertificateErrorAction.Cancel`; não existe bypass `AlwaysAllow`.

Certificados de cliente são escolhidos somente após ação explícita do usuário e apenas da coleção `MutuallyTrustedCertificates`. Após o prompt, host/porta são revalidados. O Host não exporta chave privada. Desafios de autenticação HTTP usam prompt próprio, revalidam a origem, não reutilizam credenciais CloudOS e não persistem senha.

### Histórico, favoritos e sessão

`browser-state.v1.json` persiste:

- URL HTTP/HTTPS sanitizada;
- título;
- timestamp;
- favoritos;
- preferência de restaurar sessão;
- URLs sanitizadas e estado de pin das abas da sessão opt-in.

Limites: 5000 entradas de histórico, 1000 favoritos e 32 abas de sessão. A gravação usa arquivo temporário + flush + replace/backup; arquivo principal corrompido é colocado em quarentena e, quando possível, recuperado do backup atômico.

Não são gravados nesse JSON: cookies, senha, headers, POST body, JWT, certificados, dados de formulário ou fragmentos de URL. Parâmetros de query reconhecidos como token, senha, segredo, recovery code, API key ou autorização são removidos antes de persistir.

JSON parcialmente corrompido ou campos nullable de sessão falham fechado durante normalização, sem acessar o banco CloudOS.

### Limpeza de dados

A ação WPF `Limpar dados do navegador` exige confirmação, cancela prompts/downloads em andamento, usa `CoreWebView2Profile.ClearBrowsingDataAsync(AllProfile)` no profile isolado e limpa o JSON do Browser. Não toca em `%LOCALAPPDATA%\CloudOS\data`, OPFS ou WSL.

### Rede interna CloudOS

Requests HTTP(S) do Browser para a origem privada do Shell/backend são bloqueados pela policy de navegação e por `WebResourceRequested` quando aplicável.

WebSocket possui boundary independente: o terminal backend valida `Origin` antes da autenticação e continua exigindo JWT. Isso é defesa em profundidade porque a política de request HTTP(S) do WebView2 não deve ser tratada como substituto da autorização do servidor WebSocket.

### Erro, crash e lifecycle

Erros de DNS, offline, timeout, conexão, TLS, esquema bloqueado e crash são apresentados por UI WPF, nunca por HTML privilegiado injetado. A primeira falha do renderer recria a aba preservando URL, pin, mute, zoom e estado de nova aba; uma segunda falha em até 30 segundos interrompe a recuperação automática e mostra erro para evitar crash-loop.

Fechar uma aba remove handlers e chama `Dispose()` no `WebView2CompositionControl`. `BrowserCredentialController`, prompts, download handlers e eventos de áudio também são cancelados/removidos no teardown. Fechar a última aba fecha a `BrowserWindow`. O `BrowserManager` é destruído junto com o `WebMessageBridge`, portanto o Browser é fechado antes do teardown final do Host. O UDF e o estado não são apagados no fechamento normal.

## Interface CloudOS

- React 19, TypeScript, Vite e Zustand.
- Kernel, gerenciadores de processos/janelas e sistema de arquivos virtual próprios.
- Central Windows + Linux para capacidades, distribuições, aplicativos e operações.
- Terminal xterm conectado a PowerShell ou Bash dentro de uma distribuição escolhida.

## Agente local

- Express em loopback, JWT e CORS limitado à origem estável do shell no modo nativo.
- WebSocket PTY com executáveis e argumentos definidos pelo servidor; `Origin` é validado antes do JWT.
- Detecção estruturada de ausência do WSL, acesso negado, timeout e falha de comando.
- Catálogo de distribuições obtido por `wsl --list --online`.
- Instalação via broker PowerShell allowlisted e UAC somente quando necessário.
- Catálogo de programas Windows via Menu Iniciar e de programas Linux via arquivos `.desktop`.
- IDs opacos: a página nunca envia executável, caminho ou linha de comando arbitrária.

## Armazenamento

- OPFS: sistema de arquivos virtual da interface CloudOS.
- Shell WebView2: `%LOCALAPPDATA%\CloudOS\WebView2`.
- Browser WebView2 externo: `%LOCALAPPDATA%\CloudOS\Browser\WebView2`.
- Browser history/favorites/session preference: `%LOCALAPPDATA%\CloudOS\Browser\browser-state.v1.json`.
- Auth/recuperação/operações: `%LOCALAPPDATA%\CloudOS\data\cloudos.json`.

O Browser não lê nem escreve o banco de autenticação CloudOS e não toca no OPFS.

## Fronteiras de segurança

- O agente inteiro não deve executar elevado.
- Elevação ocorre apenas no broker para verbos fixos de WSL.
- Instalação, atualização e conversão exigem papel administrador no CloudOS.
- O ambiente do terminal não herda segredos do processo do backend.
- Apps Linux/Windows são lançados apenas por IDs produzidos pelo catálogo do servidor.
- Conteúdo web externo nunca compartilha bridge, UDF, nonce ou tokens com o shell privilegiado.

## API de controle

A API HTTP do agente permanece inalterada. `browser.open` é um método da bridge Host↔Shell, não uma rota REST. Seu contrato serializado é `{ "opened": boolean, "reused": boolean }`.

## Testes do navegador

`CloudOS.Host.Tests` cobre URL policy, schemes, CloudOS/backend aliases, IDN, IPv4/IPv6, userinfo/control chars, storage layout, permission/TLS policy, vínculo de origem, crash-loop, histórico, favoritos, sanitização de URLs, limites, sessão, corrupção e backup.

Os testes backend cobrem a boundary de `Origin` do WebSocket do terminal.

`desktop/CloudOS.Browser.TestHost` existe apenas para testes Windows: cria WebView2 real com UDF/downloads/state temporários e CDP em porta explícita. `tests/playwright/native-browser.spec.ts` valida X-Frame-Options, CSP `frame-ancestors`, ausência de bridge/nonce/runtime, popup→aba, cookies, redirects, fetch interno, WebSocket rejeitado, downloads múltiplos, crash recovery e teardown/limpeza do UDF temporário.

`scripts/test-native-browser-host-smoke.ps1` roda somente no CI ou em VM/Sandbox descartável e valida Shell real → duas chamadas concorrentes de `browser.open` → fechamento da BrowserWindow → Shell/backend continuam → fechamento do Host → processos filhos encerrados.

Consulte `docs/TEST_MATRIX.md`, `docs/KNOWN_LIMITATIONS.md` e `desktop/CloudOS.Host/Browser/README.md`.

## Modo shell futuro

A substituição do Explorer continua fora do fluxo estável. Até pacote assinado, watchdog, last-known-good, rollback, WinRE e qualificação em VM estarem aprovados, nenhuma rota ou script habilita esse modo.
