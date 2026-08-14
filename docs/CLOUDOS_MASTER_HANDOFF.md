# CloudOS - Master Handoff & Estado Atual do Sistema

## 1. Visão geral

O CloudOS é um ambiente desktop híbrido para Windows que combina React 19/TypeScript com Host WPF/.NET 8, Microsoft Edge WebView2, agente Node/Express em loopback e integração Windows/WSL/WSLg.

```text
CloudOS.Host (WPF / .NET 8)
├── ShellWebView privilegiado
│   ├── React 19 / TypeScript
│   ├── origem https://cloudos.local/
│   ├── WebMessageBridge JSON v1
│   └── REST/WebSocket para agente local
│
├── BrowserManager
│   └── BrowserWindow WPF top-level
│       ├── chrome WPF
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
- Sem Host, o launcher informa que o navegador nativo é necessário; não usa `iframe`, `window.open` nem navegador padrão.

## 3. Backend

O agente local usa Express em `127.0.0.1` com porta efêmera no modo Host. Ele fornece autenticação, recuperação, capacidades Windows/WSL, operações, catálogo de apps e PTY.

O terminal WebSocket possui boundary própria de `Origin` e continua exigindo JWT. A proteção HTTP(S) do Browser não substitui autorização do servidor WebSocket.

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

Resposta:

```json
{ "opened": true, "reused": false }
```

Duas chamadas concorrentes são serializadas e reutilizam uma única `BrowserWindow`. Não existem métodos de browser para executar script, ler DOM/cookies/headers/storage, abrir arquivo ou executar comando.

### NativeWindowManager

Gerencia janelas nativas atribuíveis por HWND/processo, foco, estados, fechamento gracioso e containment quando suportado.

## 5. Navegador Nativo CloudOS

Status da branch: **implementado e em validação Windows; não integrar sem o HEAD final verde**.

O Browser é uma janela WPF separada nesta versão. Ele **não está dentro do Window Manager React**. `BrowserManager` mantém no máximo uma `BrowserWindow` por Host e reabrir o app restaura/foca a existente.

Cada aba usa `WebView2CompositionControl`; limite 32. Popups viram abas e não janelas Edge externas.

### Boundary de segurança

Shell:

```text
%LOCALAPPDATA%\CloudOS\WebView2
```

Browser externo:

```text
%LOCALAPPDATA%\CloudOS\Browser\WebView2
```

Estado próprio:

```text
%LOCALAPPDATA%\CloudOS\Browser\browser-state.v1.json
```

Conteúdo externo recebe:

- `AreHostObjectsAllowed = false`;
- `IsWebMessageEnabled = false`;
- `IsPasswordAutosaveEnabled = false`;
- `IsGeneralAutofillEnabled = false`;
- nenhum RuntimeBootstrap/nonce/JWT/supervisor token/lease token;
- nenhum virtual-host mapping `cloudos.local`;
- nenhum comando nativo arbitrário.

`cloudos.local` e a origem efêmera do backend, incluindo aliases loopback na mesma porta, são bloqueados pela policy HTTP(S). Protocolos externos são cancelados e não usam `ShellExecute`.

DevTools ficam desabilitados por padrão e só podem ser habilitados por `CLOUDOS_BROWSER_DEVTOOLS=1` em desenvolvimento explícito. CDP remoto de produção não é configurado; o TestHost usa CDP somente com UDF temporário.

### URL policy

- HTTP/HTTPS;
- domínio sem esquema → HTTPS;
- localhost/IPv4/IPv6 loopback → HTTP;
- texto comum → DuckDuckGo;
- IDN → ASCII/punycode;
- userinfo, CR/LF/NUL/controles e entradas >8192 rejeitados;
- `about:blank` somente interno;
- `data:`/`blob:` não podem ser digitados na barra;
- `file:`, `ftp:`, `javascript:`, `vbscript:`, `shell:`, `cmd:`, `powershell:`, `ms-settings:`, `ms-appx:`, `edge:`, `chrome:`, `devtools:`, `view-source:` e desconhecidos bloqueados.

### UX de abas e navegação

- criar/fechar/trocar/duplicar/reabrir/fixar aba;
- Back/Forward/Stop/Reload/Home;
- mute e indicador de áudio por aba;
- nova aba CloudOS em WPF;
- busca em histórico/favoritos;
- restauração da última sessão opt-in;
- indicador HTTP/HTTPS;
- zoom 25%–500%;
- tela cheia WPF;
- impressão;
- salvar página quando suportado pelo WebView2;
- progresso visual de carregamento;
- atalhos completos documentados no README do Browser.

### Downloads

Produção intercepta `DownloadStarting` e exige `SaveFileDialog` WPF com confirmação de sobrescrita. O chrome mostra `Cancelar downloads` enquanto houver operações ativas e suporta cancelamento em lote. Downloads nunca são executados/abertos automaticamente.

Fechar o Browser com downloads ativos pede confirmação; shutdown do Host cancela sem prompt. O TestHost injeta somente destino dentro de diretório temporário para automatizar testes.

### Permissões, certificados e HTTP auth

Câmera, microfone, localização, notificações e múltiplos downloads automáticos recebem prompt WPF temporário. `SavesInProfile=false` sempre; demais permissões são deny-by-default; timeout 30 s. Se scheme/host/port mudar enquanto o prompt está aberto, a resposta é negada.

TLS inválido usa sempre `Cancel`, sem bypass. Certificado de cliente só é escolhido explicitamente dentre `MutuallyTrustedCertificates` e host/porta são revalidados após o prompt. HTTP auth usa prompt próprio, revalida origem e não persiste senha.

### Estado e privacidade

Persistidos no JSON do Browser:

- URL HTTP/HTTPS sanitizada;
- título/timestamp;
- favoritos;
- preferência de restaurar sessão;
- URLs sanitizadas/pins da sessão opcional.

Limites: 5000 histórico, 1000 favoritos, 32 abas de sessão.

Não persistir no JSON: cookies, senhas, headers, POST body, JWT/tokens, certificados, formulários, fragments ou query params reconhecidos como segredo/token/recovery/API key.

Escrita usa temp + flush + replace/backup. Principal corrompido é quarantined; backup válido é recuperado. JSON parcialmente corrompido é normalizado fail-closed.

### Limpeza de dados

Ação WPF com confirmação limpa o profile WebView2 isolado e o JSON do Browser. Não toca no banco CloudOS, OPFS ou WSL.

### Crash/lifecycle

Erros são WPF, não HTML privilegiado. Primeira falha do renderer recria aba e preserva URL/pin/mute/zoom/nova aba; segunda falha em até 30 s para o loop.

Fechar aba remove handlers e faz `Dispose`. Prompts, credenciais, áudio e downloads possuem teardown. Fechar última aba fecha BrowserWindow. Teardown do Host fecha Browser antes do fim do Host; UDF não é apagado no fechamento normal.

## 6. Dados reais

O banco real continua fora do Git:

```text
%LOCALAPPDATA%\CloudOS\data\cloudos.json
```

O Browser não lê/grava esse banco, não toca em OPFS e não altera WSL, autenticação ou recuperação.

## 7. Build e testes

```powershell
npm ci
npm.cmd run lint
npm.cmd run build
npm.cmd test
npm.cmd run test:e2e
node scripts/run-node-tests.js frontend/test

dotnet build desktop/CloudOS.Host/CloudOS.Host.csproj -c Release
dotnet run --project desktop/CloudOS.Host.Tests/CloudOS.Host.Tests.csproj -c Release
dotnet build desktop/CloudOS.Bootstrap/CloudOS.Bootstrap.csproj -c Release
dotnet run --project desktop/CloudOS.Bootstrap.Tests/CloudOS.Bootstrap.Tests.csproj -c Release
dotnet build desktop/CloudOS.Browser.TestHost/CloudOS.Browser.TestHost.csproj -c Release

npx playwright test --grep-invert "Navegador CloudOS — WebView2 real"
npx playwright test tests/playwright/native-browser.spec.ts --output=test-results/native-browser --reporter=list
```

Smoke completo do Host:

```powershell
# CI Windows ou VM/Sandbox descartável
./scripts/test-native-browser-host-smoke.ps1
```

Fora de CI, o script exige `-AllowNonCi` e recusa um perfil CloudOS local existente, evitando usar o banco real como fixture.

## 8. Testes do Browser

`CloudOS.Host.Tests` cobre URL/pesquisa, schemes, Shell/backend aliases, IDN, IPv4/IPv6, userinfo/control chars, UDF isolado, permissões, vínculo de origem, TLS fail-closed, crash-loop, histórico/favoritos, sanitização de URL, limites, sessão, corrupção e backup.

Backend tests cobrem a policy de `Origin` do terminal WebSocket.

`tests/playwright/native-browser.spec.ts` usa WebView2 real para XFO, CSP frame-ancestors, bridge/nonce/runtime ausentes, popup, cookies entre abas, redirects, fetch interno, WebSocket rejeitado, file, downloads múltiplos, crash e teardown/UDF temporário.

O Host smoke valida Shell real → `browser.open` concorrente → fechamento do Browser → Shell/backend continuam → fechamento do Host → filhos encerram.

Artifacts de falha da feature são limitados ao output nativo sanitizado; banco/UDF/cookies/tokens/environment não devem ser publicados.

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

## 10. Referências de handoff

- `docs/ARCHITECTURE.md`
- `docs/KNOWN_LIMITATIONS.md`
- `docs/TEST_MATRIX.md`
- `desktop/CloudOS.Host/Browser/README.md`

Não fazer merge do navegador antes de o workflow Windows do HEAD final ficar verde e o smoke manual/CI ser revisado.
