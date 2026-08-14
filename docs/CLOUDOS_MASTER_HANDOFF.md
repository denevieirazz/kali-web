# CloudOS - Master Handoff & Estado Atual do Sistema

## 1. Visão geral

O CloudOS é um ambiente desktop híbrido para Windows que combina React 19/TypeScript com um Host WPF/.NET 8, Microsoft Edge WebView2, um agente Node/Express em loopback e integração Windows/WSL/WSLg.

```text
CloudOS.Host (WPF / .NET 8)
├── ShellWebView privilegiado
│   ├── React 19 / TypeScript
│   ├── origem https://cloudos.local/
│   ├── WebMessageBridge JSON v1
│   └── REST/WebSocket para agente local
│
├── BrowserManager
│   └── BrowserWindow WPF
│       └── WebView2CompositionControl por aba
│           └── conteúdo externo não confiável
│
├── NativeWindowManager / HWND
└── CloudOsRuntimeSupervisor
    └── CloudOS Backend Node / Express
        ├── Auth & Account Recovery
        ├── PTY Terminal
        ├── App Catalog
        └── Windows / WSL / WSLg
```

## 2. Frontend

- Window Manager web com stacking, foco, minimizar, maximizar e snap.
- NativeAppDock e contrato tipado para janelas Win32/WSLg gerenciadas pelo Host.
- Terminal XTerm.js conectado ao PTY por WebSocket autenticado.
- App Catalog/Store e Central Windows + Linux.
- O aplicativo React `Browser` não renderiza mais sites: ele é somente o launcher do navegador WebView2 nativo.

## 3. Backend

O agente local usa Express em `127.0.0.1` com porta efêmera no modo Host. Ele fornece autenticação, recuperação, capacidades Windows/WSL, operações, catálogo de apps e PTY. A origem do Shell é allowlisted e o runtime do terminal não deve herdar segredos do processo backend.

## 4. Host Desktop

### Supervisor

`CloudOsRuntimeSupervisor` inicia e conserva o objeto `Process` real do agente, usa manifesto/health autenticados e lease privada para manter o lifecycle do backend ligado ao Host.

### WebMessageBridge

A bridge do Shell valida origem, nonce, handshake, limite de mensagem e método allowlisted. Ela nunca aceita método, comando, argv ou caminho arbitrário. O navegador adiciona somente:

```text
browser.open
```

Parâmetro opcional:

```json
{ "url": "https://example.com" }
```

Não existem métodos de browser para executar script, ler DOM/cookies/headers/storage, abrir arquivo ou executar comando.

### NativeWindowManager

Gerencia janelas nativas atribuíveis por HWND/processo, foco, estados, fechamento gracioso e containment quando suportado.

## 5. Navegador Nativo CloudOS

O Browser é uma janela WPF separada nesta versão. `BrowserManager` mantém no máximo uma `BrowserWindow` por Host e reabrir o app restaura/foca a existente.

Cada aba usa `WebView2CompositionControl`; o limite é 32 abas. Back/Forward/Stop/Reload usam as APIs nativas do WebView2. `window.open`/`NewWindowRequested` cria outra aba e não abre uma janela Edge externa.

### Boundary de segurança

Shell:

```text
%LOCALAPPDATA%\CloudOS\WebView2
```

Browser externo:

```text
%LOCALAPPDATA%\CloudOS\Browser\WebView2
```

Estado próprio do Browser:

```text
%LOCALAPPDATA%\CloudOS\Browser\browser-state.v1.json
```

O Browser verifica que seu UDF não coincide com o UDF do Shell. Conteúdo externo recebe:

- `AreHostObjectsAllowed = false`;
- `IsWebMessageEnabled = false`;
- `IsPasswordAutosaveEnabled = false`;
- `IsGeneralAutofillEnabled = false`;
- nenhum RuntimeBootstrap;
- nenhum nonce CloudOS;
- nenhum JWT/token de supervisor/token de lease;
- nenhum virtual-host mapping `cloudos.local`.

`https://cloudos.local` e a origem efêmera atual do backend são bloqueadas pela policy do Browser.

### URL policy

- HTTP/HTTPS permitidos;
- domínio sem esquema vira HTTPS;
- `localhost`/loopback usam HTTP;
- texto comum vira pesquisa DuckDuckGo;
- IDN é normalizado para ASCII/punycode;
- userinfo, CR/LF/NUL/controles e entradas >8192 são rejeitados;
- `about:blank` somente interno;
- `file:`, `ftp:`, `javascript:`, `vbscript:`, `shell:`, `cmd:`, `powershell:`, `ms-settings:`, `ms-appx:`, `edge:`, `chrome:`, `devtools:`, `view-source:` e esquemas desconhecidos são bloqueados;
- não há `ShellExecute` para protocolos externos.

### Downloads

`DownloadStarting` é interceptado e exige `SaveFileDialog` WPF com confirmação de sobrescrita. Progresso/estado usam `CoreWebView2DownloadOperation`. Downloads nunca são executados/abertos automaticamente. Fechar o Browser com downloads ativos pede confirmação; shutdown do Host cancela sem prompt.

### Permissões e credenciais

Câmera, microfone, localização, notificações e múltiplos downloads automáticos recebem prompt WPF temporário. `SavesInProfile=false` sempre. Demais permissões são negadas por padrão; timeout de 30 s resulta em deny.

Erro TLS usa sempre `Cancel`; não existe bypass. Certificado de cliente só é escolhido explicitamente dentre `MutuallyTrustedCertificates`. Basic/Digest/NTLM usam prompt próprio e a senha não é persistida.

### Histórico/favoritos

O JSON separado persiste somente URL, título, data e favoritos; limites de 5000/1000. Escrita é temporária/atômica com backup. Principal corrompido é colocado em quarentena e backup válido é recuperado quando disponível.

### Erros/crash/lifecycle

Erros são exibidos no chrome WPF, não por HTML privilegiado. Primeira falha do renderer recria a aba; segunda falha em até 30 s interrompe recuperação automática. Fechar aba remove handlers e chama `Dispose`; a última aba fecha a BrowserWindow. O Browser é encerrado durante teardown da bridge/Host e seu UDF não é apagado.

## 6. Dados reais

O banco real continua fora do Git:

```text
%LOCALAPPDATA%\CloudOS\data\cloudos.json
```

O navegador nativo não lê nem grava esse banco, não toca no OPFS e não altera WSL, autenticação ou recuperação.

## 7. Build e testes

```powershell
npm.cmd run lint
npm.cmd run build
npm.cmd test
npm.cmd run test:e2e
node scripts/run-node-tests.js frontend/test
npm.cmd run test:playwright

dotnet build desktop/CloudOS.Host/CloudOS.Host.csproj -c Release
dotnet run --project desktop/CloudOS.Host.Tests/CloudOS.Host.Tests.csproj -c Release
dotnet build desktop/CloudOS.Bootstrap/CloudOS.Bootstrap.csproj -c Release
dotnet run --project desktop/CloudOS.Bootstrap.Tests/CloudOS.Bootstrap.Tests.csproj -c Release

# Windows + WebView2 Runtime
npm.cmd run test:browser:webview
```

O test host `desktop/CloudOS.Browser.TestHost` existe somente para validar WebView2 real com UDF temporário e CDP explícito. Não faz parte do fluxo normal do Host.

## 8. Testes do Browser

`CloudOS.Host.Tests` cobre URL/pesquisa, esquemas bloqueados, origem Shell/backend, IDN, layout/UDF isolado, policy de permissões, TLS fail-closed, crash-loop, histórico/favoritos, limites, arquivo corrompido e backup atômico.

`tests/playwright/native-browser.spec.ts` usa WebView2 real para validar X-Frame-Options DENY, CSP `frame-ancestors 'none'`, ausência de bridge/nonce/runtime, popup→aba, cookies compartilhados dentro do profile Browser e bloqueios de `cloudos.local`/`file://`.

## 9. Recursos estáveis/experimentais

| Recurso | Estado |
| --- | --- |
| Auth e recuperação | Estável |
| Terminal PTY | Estável |
| Window Manager web | Estável |
| Docking Win32/WSLg | Estável / em evolução |
| Navegador WebView2 nativo | Feature em validação Windows |
| Instalação automática de distros WSL | Experimental |
| Windows Shell replacement | Planejamento |

## 10. Limitações conhecidas da feature Browser

- O Browser abre em janela WPF separada; ainda não participa do Window Manager React.
- O chrome WPF precisa de smoke test manual Windows para prompts, SaveFileDialog e UX de tabs.
- CDP é usado somente pelo test host; produção não o habilita por padrão.
- O Browser não possui password manager próprio e desabilita autofill/password autosave do WebView2.
