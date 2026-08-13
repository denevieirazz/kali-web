# CloudOS Desktop Host

O host WPF/.NET 8 mantém o frontend React dentro do WebView2, inicia o agente Node.js diretamente e valida a identidade da sessão antes de navegar. Ele roda como usuário normal; a elevação continua limitada ao broker WSL allowlisted.

## Desenvolvimento

Pré-requisitos:

- frontend compilado com `npm run build`;
- Node.js 20+;
- .NET SDK 8;
- Microsoft Edge WebView2 Runtime.

```powershell
dotnet build .\desktop\CloudOS.Host\CloudOS.Host.csproj -c Release
dotnet run --project .\desktop\CloudOS.Host\CloudOS.Host.csproj -c Release -- --root . --node C:\caminho\node.exe
```

Opções: `--fullscreen`, `--kiosk`, `--developer-mode`, `--root` e `--node`.

O pacote final deve colocar `node.exe` em `runtime/node.exe`, o backend em `agent/backend/` e o build React em `web/`. Dados, logs, segredo JWT e perfil WebView2 ficam em `%LOCALAPPDATA%\CloudOS`.

Arquivos persistentes principais:

```text
%LOCALAPPDATA%\CloudOS\data\cloudos.json
%LOCALAPPDATA%\CloudOS\data\cloudos.json.bak
%LOCALAPPDATA%\CloudOS\data\cloudos.json.pre-v2.bak
%LOCALAPPDATA%\CloudOS\data\.jwt-secret
%LOCALAPPDATA%\CloudOS\WebView2
%LOCALAPPDATA%\CloudOS\logs
```

## Origem persistente do shell

O documento principal sempre abre em `http://cloudos.localhost/`, mapeado pelo
WebView2 diretamente para o diretório compilado `web/` com acesso cross-origin
negado. A porta aleatória do agente Node não participa mais da origem do
documento; por isso `localStorage`, IndexedDB e OPFS permanecem no mesmo perfil
entre reinicializações. O sufixo especial `localhost` é considerado contexto
potencialmente confiável pelo Chromium, inclusive em HTTP, e evita misturar um
documento HTTPS com a API/WS HTTP de loopback.

Na primeira execução desta versão, preferências que tenham ficado em uma origem
antiga `http://127.0.0.1:<porta>` não podem ser copiadas automaticamente por
causa da política de mesma origem. Contas e dados persistidos pelo backend em
`%LOCALAPPDATA%\CloudOS\data` não são apagados; apenas o estado exclusivamente
cliente da origem antiga pode começar limpo uma única vez.

Antes dos scripts da interface, o host injeta um objeto imutável
`window.__CLOUDOS_RUNTIME__` com `apiBase` e `webSocketBase` apontando para o
agente efêmero validado. O agente continua ligado exclusivamente a
`127.0.0.1`; CORS e a validação de origem do WebSocket aceitam a origem fixa
somente quando o processo foi iniciado em modo nativo pelo host. O bridge de
mensagens confia apenas no documento `cloudos.localhost`, enquanto suas chamadas
HTTP internas usam separadamente o endpoint de loopback.

O mapping do WebView2 não passa pelo middleware HTTP do backend. Por isso o host
instala uma CSP no início de cada documento confiável e usa
`CoreWebView2HostResourceAccessKind.Deny`. A CSP mantém as exceções de
`unsafe-eval` e estilos inline porque os aplicativos OSL/SDK e a interface atual
dependem delas; removê-las exige primeiro substituir essas execuções dinâmicas.

Validação isolada da política de origem e do bootstrap:

```powershell
dotnet run --project .\desktop\CloudOS.Host.Tests\CloudOS.Host.Tests.csproj -c Release
```

## Limite visual

O WebView2 incorpora o shell React. Programas Windows e WSLg permanecem janelas top-level nativas do Windows; o host rastreia as janelas que consegue atribuir com segurança e as espelha na taskbar CloudOS. Isso mantém compatibilidade e desempenho. Captura literal de pixels dentro de uma janela React é uma fase experimental separada.
