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
    │   └── BrowserWindow WPF
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

O bridge possui somente operações de host explicitamente definidas. O navegador nativo é aberto pelo método `browser.open`; não existem métodos de browser para executar JavaScript, ler DOM, cookies, headers, arquivos ou comandos nativos.

## Navegador nativo CloudOS

O aplicativo React `Browser` é apenas um launcher. No Host nativo ele chama `browser.open` e encerra sua janela/processo lógico após a abertura. Em modo web/Vite sem Host ele informa que o Navegador CloudOS requer o Host nativo; não usa `iframe`, `window.open` ou navegador padrão do Windows.

`BrowserManager` possui uma única `BrowserWindow` WPF por Host. Reabrir o aplicativo restaura/foca a janela existente. A janela contém chrome WPF e até 32 `BrowserTab`, cada uma com `WebView2CompositionControl` e todas compartilhando um environment exclusivo do Browser.

### Isolamento de dados

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
- DevTools ficam desabilitados por padrão e só podem ser ativados pelo opt-in explícito `CLOUDOS_BROWSER_DEVTOOLS=1`.

### Navegação e URL policy

A barra de endereço é WPF. A policy pura `BrowserPolicy`:

- aceita HTTP/HTTPS;
- converte domínio sem esquema para HTTPS;
- usa HTTP para `localhost` e IPs loopback;
- converte texto comum em pesquisa DuckDuckGo;
- normaliza IDN para forma ASCII/punycode;
- rejeita userinfo, controles, CR/LF/NUL e entradas acima de 8192 caracteres;
- permite `about:blank` somente internamente;
- bloqueia `file:`, `ftp:`, `javascript:`, `vbscript:`, `shell:`, `cmd:`, `powershell:`, `ms-settings:`, `ms-appx:`, `edge:`, `chrome:`, `devtools:`, `view-source:` e esquemas desconhecidos;
- bloqueia `https://cloudos.local` e a origem efêmera atual do backend;
- não usa `ShellExecute` para protocolos externos.

Back/Forward/Stop/Reload usam o histórico e APIs nativas do próprio WebView2. `NewWindowRequested` é convertido em nova aba e não abre uma janela Edge externa.

### Downloads

`BrowserDownloadManager` intercepta `DownloadStarting`, exige `SaveFileDialog`, usa confirmação de sobrescrita e acompanha `BytesReceivedChanged`/`StateChanged`. Arquivos baixados nunca são executados ou abertos automaticamente. Ao fechar o Browser com downloads ativos, o usuário precisa confirmar o cancelamento; durante shutdown do Host o encerramento é direto.

### Permissões, certificados e autenticação HTTP

Permissões suportadas com prompt WPF: câmera, microfone, localização, notificações e downloads automáticos múltiplos. Todas as decisões usam `SavesInProfile = false`; permissões não suportadas são negadas por padrão e o prompt expira em 30 segundos.

Erros TLS recebem sempre `CoreWebView2ServerCertificateErrorAction.Cancel`; não existe bypass `AlwaysAllow`.

Certificados de cliente são escolhidos somente após ação explícita do usuário e apenas da coleção `MutuallyTrustedCertificates`. O Host não exporta chave privada. Desafios de autenticação HTTP usam prompt próprio, não reutilizam credenciais CloudOS e não persistem senha.

### Histórico e favoritos

`browser-state.v1.json` persiste somente URL, título, data e favoritos. Limites: 5000 entradas de histórico e 1000 favoritos. A gravação usa arquivo temporário + replace/backup; arquivo principal corrompido é colocado em quarentena e, quando possível, recuperado do backup atômico.

Não são gravados nesse JSON: cookies, senha, headers, POST body, JWT, certificados ou dados de formulário. Cookies/cache do conteúdo externo pertencem exclusivamente ao UDF WebView2 do Browser.

### Erro, crash e lifecycle

Erros de DNS, offline, timeout, conexão, TLS, esquema bloqueado e crash são apresentados por UI WPF, nunca por HTML privilegiado injetado. A primeira falha do renderer recria a aba preservando a URL; uma segunda falha em até 30 segundos interrompe a recuperação automática e mostra erro para evitar crash-loop.

Fechar uma aba remove handlers e chama `Dispose()` no `WebView2CompositionControl`. Fechar a última aba fecha a `BrowserWindow`. O `BrowserManager` é destruído junto com o `WebMessageBridge`, portanto o Browser é fechado durante teardown do Host. O UDF e o histórico não são apagados ao fechar.

## Interface CloudOS

- React 19, TypeScript, Vite e Zustand.
- Kernel, gerenciadores de processos/janelas e sistema de arquivos virtual próprios.
- Central Windows + Linux para capacidades, distribuições, aplicativos e operações.
- Terminal xterm conectado a PowerShell ou Bash dentro de uma distribuição escolhida.

## Agente local

- Express em loopback, JWT e CORS limitado à origem estável do shell no modo nativo.
- WebSocket PTY com executáveis e argumentos definidos pelo servidor.
- Detecção estruturada de ausência do WSL, acesso negado, timeout e falha de comando.
- Catálogo de distribuições obtido por `wsl --list --online`.
- Instalação via broker PowerShell allowlisted e UAC somente quando necessário.
- Catálogo de programas Windows via Menu Iniciar e de programas Linux via arquivos `.desktop`.
- IDs opacos: a página nunca envia executável, caminho ou linha de comando arbitrária.

## Armazenamento

- OPFS: sistema de arquivos virtual da interface CloudOS.
- Shell WebView2: `%LOCALAPPDATA%\CloudOS\WebView2`.
- Browser WebView2 externo: `%LOCALAPPDATA%\CloudOS\Browser\WebView2`.
- Browser history/favorites: `%LOCALAPPDATA%\CloudOS\Browser\browser-state.v1.json`.
- Auth/recuperação/operações: `%LOCALAPPDATA%\CloudOS\data\cloudos.json`.

O Browser não lê nem escreve o banco de autenticação CloudOS e não toca no OPFS.

## Fronteiras de segurança

- O agente inteiro não deve executar elevado.
- Elevação ocorre apenas no broker para verbos fixos de WSL.
- Instalação, atualização e conversão exigem papel administrador no CloudOS.
- O ambiente do terminal não herda segredos do processo do backend.
- Apps Linux/Windows são lançados apenas por IDs produzidos pelo catálogo do servidor.
- Conteúdo web externo nunca compartilha bridge, UDF ou tokens com o shell privilegiado.

## API de controle

A API HTTP do agente permanece inalterada. `browser.open` é um método da bridge Host↔Shell, não uma rota REST.

## Testes do navegador

Testes puros no `CloudOS.Host.Tests` cobrem URL policy, esquemas, origens CloudOS, IDN, storage layout, permission/TLS policy, crash-loop, histórico, favoritos, limites, corrupção e backup.

`desktop/CloudOS.Browser.TestHost` existe apenas para testes Windows: cria WebView2 real com UDF temporário e CDP em porta explícita. `tests/playwright/native-browser.spec.ts` usa esse host para validar X-Frame-Options, CSP `frame-ancestors`, ausência de bridge/nonce/runtime, popup→aba, cookies compartilhados entre abas e bloqueios de `cloudos.local`/`file://`.

## Modo shell futuro

A substituição do Explorer continua fora do fluxo estável. Até pacote assinado, watchdog, last-known-good, rollback, WinRE e qualificação em VM estarem aprovados, nenhuma rota ou script habilita esse modo.
