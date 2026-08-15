# Navegador Nativo CloudOS

Status desta branch: **implementado e em validação Windows; não integrar sem CI verde e smoke local aprovado**.

## Arquitetura

O navegador desta versão abre em uma **janela WPF separada** do `CloudOS.Host`. Ele não é hospedado no Window Manager React e não usa `iframe`.

```text
CloudOS.Host
├── ShellWebView (privilegiado)
│   └── WebMessageBridge / RuntimeBootstrap / origem CloudOS
└── BrowserManager
    └── BrowserWindow WPF
        └── BrowserTab × N
            └── WebView2CompositionControl
```

O app React `Browser` é somente um launcher. Quando o Host está disponível ele chama exclusivamente `browser.open` e encerra seu processo lógico. Sem Host, informa que o navegador nativo é obrigatório; não usa `iframe`, `window.open` ou navegador padrão.

## Isolamento

Shell e Browser usam perfis diferentes:

- Shell: `%LOCALAPPDATA%\CloudOS\WebView2`
- Browser: `%LOCALAPPDATA%\CloudOS\Browser\WebView2`

Sites externos não recebem:

- `WebMessageBridge`;
- `RuntimeBootstrap`;
- `__cloudosNativeNonce`;
- JWT, supervisor token ou lease token;
- host objects;
- virtual-host mapping `cloudos.local`;
- credenciais CloudOS.

Configuração do WebView externo:

- `IsWebMessageEnabled = false`;
- `AreHostObjectsAllowed = false`;
- password autosave desabilitado;
- autofill geral desabilitado;
- DevTools somente quando `CLOUDOS_BROWSER_DEVTOOLS=1` é explicitamente definido;
- certificados TLS inválidos resultam sempre em `Cancel`.

## Navegação e abas

- até 32 abas;
- nova aba, fechar, trocar, duplicar, reabrir aba fechada e fixar;
- popups `window.open` são redirecionados para nova aba WebView2;
- Back, Forward, Stop, Reload, Home;
- domínio sem esquema → HTTPS;
- localhost/loopback → HTTP;
- busca textual → DuckDuckGo;
- IDN exibido em punycode para reduzir ambiguidade;
- nova aba é UI WPF do CloudOS, sem HTML privilegiado injetado em sites.

Esquemas perigosos ou externos são bloqueados. O navegador não usa `ShellExecute` para protocolos externos.

## Recursos de experiência

- histórico e favoritos pesquisáveis;
- restauração da última sessão opcional;
- mute por aba e indicador de áudio;
- indicador HTTP/HTTPS;
- zoom;
- tela cheia WPF;
- impressão;
- salvar página via API WebView2 quando suportado;
- progresso de carregamento;
- página de erro WPF;
- crash recovery: primeira falha recria a aba; segunda em até 30 s interrompe o loop.

Atalhos:

- `Ctrl+L`, `Ctrl+T`, `Ctrl+W`, `Ctrl+Shift+T`;
- `Ctrl+Tab`, `Ctrl+Shift+Tab`;
- `Alt+Left`, `Alt+Right`;
- `Ctrl+R`, `Esc`;
- `Ctrl++`, `Ctrl+-`, `Ctrl+0`;
- `F11`.

## Downloads

Downloads são interceptados antes de começar. Produção usa `SaveFileDialog` WPF com confirmação de sobrescrita. Arquivos nunca são executados ou abertos automaticamente.

O chrome mostra **Cancelar downloads** enquanto houver operações ativas. Fechar o Browser com download em andamento exige confirmação; shutdown do Host cancela sem prompt.

O `BrowserDownloadManager` aceita seletor de destino injetável somente para o `CloudOS.Browser.TestHost`, permitindo testes automatizados em diretório temporário sem automatizar a caixa de diálogo do Windows.

## Permissões, certificados e autenticação HTTP

Prompts WPF são permitidos somente para câmera, microfone, geolocalização, notificações e múltiplos downloads automáticos. Toda decisão usa `SavesInProfile=false` e expira após 30 s. Se a origem mudar enquanto o prompt está aberto, a permissão é negada.

Sensores, permissões desconhecidas e demais tipos não allowlisted são negados.

Certificados de cliente nunca são escolhidos automaticamente: somente itens de `MutuallyTrustedCertificates` podem ser escolhidos pelo usuário, e a origem é revalidada depois do prompt.

Autenticação HTTP solicita usuário/senha em memória, revalida a origem e não persiste a credencial.

## Estado persistido

Arquivo separado:

`%LOCALAPPDATA%\CloudOS\Browser\browser-state.v1.json`

Persistidos somente:

- URL HTTP/HTTPS sanitizada;
- título;
- timestamp;
- favoritos;
- preferência de restaurar sessão;
- URLs sanitizadas/pin das abas da sessão opcional.

Não são persistidos no JSON:

- cookies;
- senhas;
- headers;
- POST body;
- JWT/tokens;
- certificados;
- dados de formulário;
- fragments de URL;
- parâmetros de query reconhecidos como token, senha, segredo ou recovery code.

A escrita usa arquivo temporário, flush, replace/backup e quarentena de JSON corrompido.

## Limpeza de dados

O menu WPF oferece limpeza mediante confirmação. A ação limpa o profile WebView2 isolado e o JSON do Browser. Não toca no banco CloudOS, OPFS ou dados WSL.

## Rede interna CloudOS

Navegação e requests HTTP(S) para `cloudos.local` e para a origem loopback efêmera do backend são bloqueados pelo Browser.

WebSocket não é tratado como uma requisição HTTP(S) normal pela proteção `WebResourceRequested`; por isso a fronteira `/ws/terminal` mantém defesa independente no backend por `Origin` e JWT. Os testes da feature verificam que uma origem externa não consegue abrir uma sessão de terminal.

## Testes

- `CloudOS.Host.Tests`: policy, IDN, IPv4/IPv6, origem, TLS, storage, limites, corrupção e sessão.
- backend tests: política de `Origin` do WebSocket.
- `CloudOS.Browser.TestHost`: WebView2 real com UDF temporário e CDP apenas de teste.
- Playwright WebView2: XFO/CSP, bridge isolation, popup, cookies, redirect, fetch interno, WebSocket rejeitado, downloads, crash recovery e teardown.
- Host smoke no CI Windows: Shell → Browser → fechamento do Browser → backend/Shell continuam → fechamento do Host → filhos encerram.
- `test-powershell7-requirement.ps1`: aceita a sessão `pwsh` 7.2+ e executa os entrypoints com Windows PowerShell 5.1 para exigir falha imediata `POWERSHELL_7_REQUIRED`.

### Validação Windows local

O validador completo e o smoke nativo exigem **PowerShell 7.2 ou superior**. `powershell.exe` (Windows PowerShell 5.1) não é suportado para esses entrypoints e deve falhar no preflight antes de acessar `$IsWindows` ou APIs modernas do smoke.

Comando oficial, somente em Windows Sandbox/VM descartável e sem `%LOCALAPPDATA%\CloudOS` existente:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-native-browser-windows.ps1 -DisposableProfile
```

Quando o validador já está rodando em PowerShell 7, os scripts PowerShell filhos são chamados na mesma sessão; ele não precisa localizar outro `pwsh` no `PATH`.

Nunca use `test:playwright:update` para validar esta feature sem uma mudança visual intencional e revisada.

## Riscos e limitações

- Browser é uma janela WPF top-level separada; ainda não participa do Window Manager React.
- Cookies/cache do Browser são persistentes no UDF por design até limpeza explícita.
- CDP do Browser existe somente no TestHost; produção não deve definir argumentos de remote debugging.
- O smoke completo do Host deve ser executado em GitHub Actions Windows ou VM/Sandbox descartável. O script recusa perfil CloudOS existente fora de CI.
- PowerShell 7.2+ é requisito formal para o validador/smoke; Windows PowerShell 5.1 é suportado apenas como alvo negativo do teste de preflight.
- Nenhuma extensão ou sincronização em nuvem é implementada.

## Rollback

Reverter os commits da feature em ordem inversa com `git revert`. Não usar force-push e não reescrever `integration/cloudos-foundation`.

O rollback não deve apagar automaticamente `%LOCALAPPDATA%\CloudOS\Browser`; esse diretório é isolado do banco e pode conter dados do usuário do Browser.
